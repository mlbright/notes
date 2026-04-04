package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const (
	baseURL        = "https://hippo.chameleon-gopher.ts.net"
	apiBase        = baseURL + "/api/v1"
	rateLimit      = 280
	rateWindow     = 5 * time.Minute
	keepDir        = "Takeout/Keep"
	credentialsFile = "credentials"
)

// --- Google Keep JSON schema ---

type KeepNote struct {
	Color                    string           `json:"color"`
	IsTrashed                bool             `json:"isTrashed"`
	IsPinned                 bool             `json:"isPinned"`
	IsArchived               bool             `json:"isArchived"`
	Title                    string           `json:"title"`
	TextContent              string           `json:"textContent"`
	UserEditedTimestampUsec  int64            `json:"userEditedTimestampUsec"`
	CreatedTimestampUsec     int64            `json:"createdTimestampUsec"`
	ListContent              []KeepListItem   `json:"listContent"`
	Annotations              []KeepAnnotation `json:"annotations"`
	Attachments              []KeepAttachment `json:"attachments"`
}

type KeepListItem struct {
	Text      string `json:"text"`
	IsChecked bool   `json:"isChecked"`
}

type KeepAnnotation struct {
	Description string `json:"description"`
	Source      string `json:"source"`
	Title       string `json:"title"`
	URL         string `json:"url"`
}

type KeepAttachment struct {
	FilePath string `json:"filePath"`
	MimeType string `json:"mimetype"`
}

// --- API response types ---

type AuthResponse struct {
	Token     string `json:"token"`
	ExpiresAt string `json:"expires_at"`
}

type NoteResponse struct {
	ID        int    `json:"id"`
	Title     string `json:"title"`
	CreatedAt string `json:"created_at"`
}

type NotesListResponse struct {
	Notes      []NoteResponse `json:"notes"`
	Pagination struct {
		Page  int `json:"page"`
		Pages int `json:"pages"`
		Count int `json:"count"`
	} `json:"pagination"`
}

// --- Rate limiter ---

type RateLimiter struct {
	count     int
	windowStart time.Time
}

func (rl *RateLimiter) Wait() {
	if rl.windowStart.IsZero() {
		rl.windowStart = time.Now()
	}
	rl.count++
	if rl.count >= rateLimit {
		elapsed := time.Since(rl.windowStart)
		if elapsed < rateWindow {
			sleep := rateWindow - elapsed
			log.Printf("Rate limit: sleeping %v", sleep)
			time.Sleep(sleep)
		}
		rl.count = 0
		rl.windowStart = time.Now()
	}
}

// --- HTTP helpers ---

type Client struct {
	http  *http.Client
	token string
	rl    RateLimiter
}

func (c *Client) doJSON(method, url string, body any) ([]byte, int, error) {
	c.rl.Wait()

	var reqBody io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return nil, 0, fmt.Errorf("marshal: %w", err)
		}
		reqBody = bytes.NewReader(data)
	}

	req, err := http.NewRequest(method, url, reqBody)
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("Content-Type", "application/json")
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, resp.StatusCode, err
	}
	return respBody, resp.StatusCode, nil
}

func (c *Client) uploadFile(url, filePath string) error {
	c.rl.Wait()

	f, err := os.Open(filePath)
	if err != nil {
		return fmt.Errorf("open %s: %w", filePath, err)
	}
	defer f.Close()

	var buf bytes.Buffer
	w := multipart.NewWriter(&buf)
	part, err := w.CreateFormFile("files[]", filepath.Base(filePath))
	if err != nil {
		return fmt.Errorf("create form file: %w", err)
	}
	if _, err := io.Copy(part, f); err != nil {
		return fmt.Errorf("copy file: %w", err)
	}
	w.Close()

	req, err := http.NewRequest("POST", url, &buf)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", w.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+c.token)

	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("upload failed (%d): %s", resp.StatusCode, body)
	}
	return nil
}

// --- Core logic ---

func parseCredentials(path string) (email, password string, err error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", "", err
	}
	for _, line := range strings.Split(string(data), "\n") {
		if rest, ok := strings.CutPrefix(line, "user: "); ok {
			email = strings.TrimSpace(rest)
		}
		if rest, ok := strings.CutPrefix(line, "password: "); ok {
			password = strings.TrimSpace(rest)
		}
	}
	if email == "" || password == "" {
		return "", "", fmt.Errorf("missing email or password in %s", path)
	}
	return email, password, nil
}

func authenticate(c *Client, email, password string) error {
	body, status, err := c.doJSON("POST", apiBase+"/auth/token", map[string]string{
		"email":    email,
		"password": password,
	})
	if err != nil {
		return fmt.Errorf("auth request: %w", err)
	}
	if status != http.StatusOK {
		return fmt.Errorf("auth failed (%d): %s", status, body)
	}
	var auth AuthResponse
	if err := json.Unmarshal(body, &auth); err != nil {
		return fmt.Errorf("auth parse: %w", err)
	}
	c.token = auth.Token
	log.Printf("Authenticated (token expires %s)", auth.ExpiresAt)
	return nil
}

func usecToTime(usec int64) time.Time {
	return time.UnixMicro(usec)
}

func buildBody(note KeepNote) string {
	var body string

	if len(note.ListContent) > 0 {
		var lines []string
		for _, item := range note.ListContent {
			if item.Text == "" {
				continue
			}
			if item.IsChecked {
				lines = append(lines, "- [x] "+item.Text)
			} else {
				lines = append(lines, "- [ ] "+item.Text)
			}
		}
		body = strings.Join(lines, "\n")
	} else {
		body = note.TextContent
	}

	if len(note.Annotations) > 0 {
		var links []string
		for _, ann := range note.Annotations {
			if ann.URL == "" {
				continue
			}
			title := ann.Title
			if title == "" {
				title = ann.URL
			}
			links = append(links, fmt.Sprintf("[%s](%s)", title, ann.URL))
		}
		if len(links) > 0 {
			body += "\n\n---\n" + strings.Join(links, "\n")
		}
	}

	return body
}

func dedupKey(title, createdAt string) string {
	// Normalize: parse and re-format to strip milliseconds for consistent comparison
	t, err := time.Parse(time.RFC3339Nano, createdAt)
	if err != nil {
		// Try alternate format with .000Z
		t, err = time.Parse("2006-01-02T15:04:05.000Z", createdAt)
		if err != nil {
			return title + "|" + createdAt
		}
	}
	return title + "|" + t.UTC().Format("2006-01-02T15:04:05")
}

func fetchExistingNotes(c *Client) (map[string]bool, error) {
	existing := make(map[string]bool)

	for _, filter := range []string{"", "archived", "trash"} {
		for page := 1; ; page++ {
			url := fmt.Sprintf("%s/notes?limit=100&page=%d", apiBase, page)
			if filter != "" {
				url += "&filter=" + filter
			}

			body, status, err := c.doJSON("GET", url, nil)
			if err != nil {
				return nil, fmt.Errorf("fetch notes (filter=%s, page=%d): %w", filter, page, err)
			}
			if status != http.StatusOK {
				return nil, fmt.Errorf("fetch notes (%d): %s", status, body)
			}

			var resp NotesListResponse
			if err := json.Unmarshal(body, &resp); err != nil {
				return nil, fmt.Errorf("parse notes: %w", err)
			}

			for _, n := range resp.Notes {
				existing[dedupKey(n.Title, n.CreatedAt)] = true
			}

			if page >= resp.Pagination.Pages || len(resp.Notes) == 0 {
				break
			}
		}
	}

	log.Printf("Found %d existing notes for dedup", len(existing))
	return existing, nil
}

// importResult indicates the outcome of importing a single note.
type importResult int

const (
	resultCreated importResult = iota
	resultSkipped
)

func importNote(c *Client, noteFile string, existing map[string]bool) (importResult, error) {
	data, err := os.ReadFile(noteFile)
	if err != nil {
		return 0, fmt.Errorf("read %s: %w", noteFile, err)
	}

	var note KeepNote
	if err := json.Unmarshal(data, &note); err != nil {
		return 0, fmt.Errorf("parse %s: %w", noteFile, err)
	}

	createdAt := usecToTime(note.CreatedTimestampUsec).UTC().Format(time.RFC3339)
	updatedAt := usecToTime(note.UserEditedTimestampUsec).UTC().Format(time.RFC3339)

	key := dedupKey(note.Title, createdAt)
	if existing[key] {
		log.Printf("SKIP %s (already exists)", filepath.Base(noteFile))
		return resultSkipped, nil
	}

	body := buildBody(note)
	isChecklist := len(note.ListContent) > 0

	payload := map[string]any{
		"title":      note.Title,
		"body":       body,
		"pinned":     note.IsPinned,
		"checklist":  isChecklist,
		"created_at": createdAt,
		"updated_at": updatedAt,
	}

	respBody, status, err := c.doJSON("POST", apiBase+"/notes", payload)
	if err != nil {
		return 0, fmt.Errorf("create note: %w", err)
	}
	if status != http.StatusCreated {
		return 0, fmt.Errorf("create note (%d): %s", status, respBody)
	}

	var created NoteResponse
	if err := json.Unmarshal(respBody, &created); err != nil {
		return 0, fmt.Errorf("parse created note: %w", err)
	}

	noteURL := fmt.Sprintf("%s/notes/%d", apiBase, created.ID)
	log.Printf("CREATED %s → id=%d title=%q", filepath.Base(noteFile), created.ID, note.Title)

	// Archive if needed
	if note.IsArchived {
		if _, status, err := c.doJSON("PATCH", noteURL+"/archive", nil); err != nil {
			log.Printf("  WARN archive %d: %v", created.ID, err)
		} else if status != http.StatusOK {
			log.Printf("  WARN archive %d: status %d", created.ID, status)
		} else {
			log.Printf("  ARCHIVED %d", created.ID)
		}
	}

	// Trash if needed
	if note.IsTrashed {
		if _, status, err := c.doJSON("DELETE", noteURL, nil); err != nil {
			log.Printf("  WARN trash %d: %v", created.ID, err)
		} else if status != http.StatusOK {
			log.Printf("  WARN trash %d: status %d", created.ID, status)
		} else {
			log.Printf("  TRASHED %d", created.ID)
		}
	}

	// Upload attachments
	for _, att := range note.Attachments {
		attPath := filepath.Join(keepDir, att.FilePath)
		if err := c.uploadFile(noteURL+"/attachments", attPath); err != nil {
			log.Printf("  WARN attachment %s: %v", att.FilePath, err)
		} else {
			log.Printf("  ATTACHED %s to %d", att.FilePath, created.ID)
		}
	}

	// Record in dedup map so re-runs within same execution skip too
	existing[key] = true

	return resultCreated, nil
}

func main() {
	log.SetFlags(log.Ltime)

	email, password, err := parseCredentials(credentialsFile)
	if err != nil {
		log.Fatalf("Credentials: %v", err)
	}

	client := &Client{http: &http.Client{Timeout: 30 * time.Second}}

	if err := authenticate(client, email, password); err != nil {
		log.Fatalf("Auth: %v", err)
	}

	existing, err := fetchExistingNotes(client)
	if err != nil {
		log.Fatalf("Fetch existing: %v", err)
	}

	files, err := filepath.Glob(filepath.Join(keepDir, "*.json"))
	if err != nil {
		log.Fatalf("Glob: %v", err)
	}
	log.Printf("Found %d JSON files to import", len(files))

	var nCreated, nSkipped, nErrored int
	for _, f := range files {
		result, err := importNote(client, f, existing)
		if err != nil {
			log.Printf("ERROR %s: %v", filepath.Base(f), err)
			nErrored++
		} else if result == resultSkipped {
			nSkipped++
		} else {
			nCreated++
		}
	}

	log.Printf("Done: %d created, %d skipped, %d errors (of %d total)", nCreated, nSkipped, nErrored, len(files))
}
