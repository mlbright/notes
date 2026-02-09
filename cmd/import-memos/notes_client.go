package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"strings"
	"time"
)

// NotesClient interacts with a Notes Rails app REST API.
type NotesClient struct {
	baseURL    string
	token      string
	httpClient *http.Client
}

// NewNotesClient creates a new Notes API client.
func NewNotesClient(baseURL, token string) *NotesClient {
	return &NotesClient{
		baseURL: strings.TrimRight(baseURL, "/"),
		token:   token,
		httpClient: &http.Client{
			Timeout: 60 * time.Second,
		},
	}
}

// doRequest performs an authenticated HTTP request with an optional JSON body.
func (c *NotesClient) doRequest(method, path string, body io.Reader, contentType string) ([]byte, int, error) {
	reqURL := c.baseURL + path
	req, err := http.NewRequest(method, reqURL, body)
	if err != nil {
		return nil, 0, fmt.Errorf("creating request for %s: %w", path, err)
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Accept", "application/json")
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, 0, fmt.Errorf("requesting %s: %w", path, err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, resp.StatusCode, fmt.Errorf("reading response from %s: %w", path, err)
	}

	return respBody, resp.StatusCode, nil
}

// doJSON performs an authenticated JSON request and checks the status code.
func (c *NotesClient) doJSON(method, path string, payload any) ([]byte, error) {
	var body io.Reader
	ct := "application/json"

	if payload != nil {
		data, err := json.Marshal(payload)
		if err != nil {
			return nil, fmt.Errorf("marshaling JSON for %s: %w", path, err)
		}
		body = bytes.NewReader(data)
	}

	respBody, status, err := c.doRequest(method, path, body, ct)
	if err != nil {
		return nil, err
	}

	if status < 200 || status >= 300 {
		snippet := string(respBody)
		if len(snippet) > 200 {
			snippet = snippet[:200] + "..."
		}
		return nil, fmt.Errorf("HTTP %d from %s %s: %s", status, method, path, snippet)
	}

	return respBody, nil
}

// Authenticate obtains an API token by email and password, storing it on the
// client for subsequent requests. Returns the token string.
func (c *NotesClient) Authenticate(email, password string) (string, error) {
	payload := map[string]string{
		"email":    email,
		"password": password,
	}

	// This endpoint doesn't require auth, but doJSON sends the header harmlessly.
	body, err := c.doJSON("POST", "/api/v1/auth/token", payload)
	if err != nil {
		return "", fmt.Errorf("authenticating with Notes: %w", err)
	}

	var resp struct {
		Token     string `json:"token"`
		ExpiresAt string `json:"expires_at"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return "", fmt.Errorf("parsing auth response: %w", err)
	}
	if resp.Token == "" {
		return "", fmt.Errorf("no token returned from Notes auth endpoint")
	}

	c.token = resp.Token
	return resp.Token, nil
}

// Ping checks connectivity by listing tags (a lightweight authenticated endpoint).
func (c *NotesClient) Ping() error {
	_, err := c.doJSON("GET", "/api/v1/tags", nil)
	return err
}

// ListTags returns all tags for the authenticated user.
func (c *NotesClient) ListTags() ([]NotesTag, error) {
	body, err := c.doJSON("GET", "/api/v1/tags", nil)
	if err != nil {
		return nil, fmt.Errorf("listing tags: %w", err)
	}

	// The response may be either { "tags": [...] } or just [...].
	// Try the wrapper first.
	var wrapped NotesTagsResponse
	if err := json.Unmarshal(body, &wrapped); err == nil && wrapped.Tags != nil {
		return wrapped.Tags, nil
	}

	var tags []NotesTag
	if err := json.Unmarshal(body, &tags); err != nil {
		return nil, fmt.Errorf("parsing tags response: %w", err)
	}
	return tags, nil
}

// CreateTag creates a new tag and returns it.
func (c *NotesClient) CreateTag(name, color string) (*NotesTag, error) {
	payload := map[string]string{
		"name":  name,
		"color": color,
	}

	body, err := c.doJSON("POST", "/api/v1/tags", payload)
	if err != nil {
		return nil, fmt.Errorf("creating tag %q: %w", name, err)
	}

	var tag NotesTag
	if err := json.Unmarshal(body, &tag); err != nil {
		return nil, fmt.Errorf("parsing created tag: %w", err)
	}

	return &tag, nil
}

// CreateNote creates a new note and returns it. If createdAt or updatedAt are
// non-zero, they are sent so the Notes API preserves the original timestamps.
func (c *NotesClient) CreateNote(title, noteBody string, pinned bool, tagIDs []int, maxSize int, createdAt, updatedAt time.Time) (*NotesNote, error) {
	payload := map[string]any{
		"title":  title,
		"body":   noteBody,
		"pinned": pinned,
	}
	if len(tagIDs) > 0 {
		payload["tag_ids"] = tagIDs
	}
	if maxSize > 32768 {
		payload["max_size"] = maxSize
	}
	if !createdAt.IsZero() {
		payload["created_at"] = createdAt.Format(time.RFC3339)
	}
	if !updatedAt.IsZero() {
		payload["updated_at"] = updatedAt.Format(time.RFC3339)
	}

	body, err := c.doJSON("POST", "/api/v1/notes", payload)
	if err != nil {
		return nil, fmt.Errorf("creating note: %w", err)
	}

	var note NotesNote
	if err := json.Unmarshal(body, &note); err != nil {
		return nil, fmt.Errorf("parsing created note: %w", err)
	}

	return &note, nil
}

// ArchiveNote archives a note by ID.
func (c *NotesClient) ArchiveNote(noteID int) error {
	path := fmt.Sprintf("/api/v1/notes/%d/archive", noteID)
	_, err := c.doJSON("PATCH", path, nil)
	if err != nil {
		return fmt.Errorf("archiving note %d: %w", noteID, err)
	}
	return nil
}

// UploadAttachments uploads one or more files to a note as multipart form data.
func (c *NotesClient) UploadAttachments(noteID int, files []FileData) error {
	if len(files) == 0 {
		return nil
	}

	var buf bytes.Buffer
	writer := multipart.NewWriter(&buf)

	for _, f := range files {
		part, err := writer.CreateFormFile("files[]", f.Filename)
		if err != nil {
			return fmt.Errorf("creating form file for %s: %w", f.Filename, err)
		}
		if _, err := part.Write(f.Data); err != nil {
			return fmt.Errorf("writing file data for %s: %w", f.Filename, err)
		}
	}

	if err := writer.Close(); err != nil {
		return fmt.Errorf("closing multipart writer: %w", err)
	}

	path := fmt.Sprintf("/api/v1/notes/%d/attachments", noteID)
	respBody, status, err := c.doRequest("POST", path, &buf, writer.FormDataContentType())
	if err != nil {
		return fmt.Errorf("uploading attachments to note %d: %w", noteID, err)
	}

	if status < 200 || status >= 300 {
		snippet := string(respBody)
		if len(snippet) > 200 {
			snippet = snippet[:200] + "..."
		}
		return fmt.Errorf("HTTP %d uploading attachments to note %d: %s", status, noteID, snippet)
	}

	return nil
}
