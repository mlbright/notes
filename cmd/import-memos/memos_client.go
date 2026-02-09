package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// MemosClient interacts with a Memos instance REST API.
type MemosClient struct {
	baseURL    string
	token      string
	httpClient *http.Client
}

// NewMemosClient creates a new Memos API client.
func NewMemosClient(baseURL, token string) *MemosClient {
	return &MemosClient{
		baseURL: strings.TrimRight(baseURL, "/"),
		token:   token,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

// doRequest performs an authenticated HTTP request and returns the response body.
func (c *MemosClient) doRequest(method, path string) ([]byte, error) {
	reqURL := c.baseURL + path
	req, err := http.NewRequest(method, reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("creating request for %s: %w", path, err)
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Accept", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("requesting %s: %w", path, err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("reading response from %s: %w", path, err)
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		snippet := string(body)
		if len(snippet) > 200 {
			snippet = snippet[:200] + "..."
		}
		return nil, fmt.Errorf("HTTP %d from %s: %s", resp.StatusCode, path, snippet)
	}

	return body, nil
}

// Ping checks connectivity by fetching the instance profile.
func (c *MemosClient) Ping() error {
	_, err := c.doRequest("GET", "/api/v1/instance/profile")
	return err
}

// ListUsers returns all users from the Memos instance.
func (c *MemosClient) ListUsers() ([]MemosUser, error) {
	var allUsers []MemosUser
	pageToken := ""
	page := 0

	fmt.Print("  Fetching users from Memos...")
	for {
		page++
		path := "/api/v1/users?pageSize=200"
		if pageToken != "" {
			path += "&pageToken=" + url.QueryEscape(pageToken)
		}

		body, err := c.doRequest("GET", path)
		if err != nil {
			fmt.Println()
			return nil, fmt.Errorf("listing users: %w", err)
		}

		var resp MemosListUsersResponse
		if err := json.Unmarshal(body, &resp); err != nil {
			fmt.Println()
			return nil, fmt.Errorf("parsing users response: %w", err)
		}

		allUsers = append(allUsers, resp.Users...)
		fmt.Printf(" %d users so far (page %d)...", len(allUsers), page)

		if resp.NextPageToken == "" {
			break
		}
		pageToken = resp.NextPageToken
	}

	fmt.Printf(" done (%d total)\n", len(allUsers))
	return allUsers, nil
}

// GetUserStats returns the stats (including tag counts) for a user.
func (c *MemosClient) GetUserStats(userName string) (*MemosUserStats, error) {
	// userName is like "users/1", endpoint is GET /api/v1/users/1:getStats
	path := "/api/v1/" + userName + ":getStats"

	body, err := c.doRequest("GET", path)
	if err != nil {
		return nil, fmt.Errorf("getting stats for %s: %w", userName, err)
	}

	var stats MemosUserStats
	if err := json.Unmarshal(body, &stats); err != nil {
		return nil, fmt.Errorf("parsing user stats: %w", err)
	}

	return &stats, nil
}

// ListMemos returns all memos for a specific creator and state.
// creatorName is e.g. "users/1", state is "NORMAL" or "ARCHIVED".
func (c *MemosClient) ListMemos(creatorName, state string) ([]MemosMemo, error) {
	var allMemos []MemosMemo
	pageToken := ""
	page := 0

	fmt.Printf("    Fetching %s memos for %s...", state, creatorName)
	for {
		page++
		params := url.Values{}
		params.Set("pageSize", "200")
		params.Set("state", state)
		// Filter by creator using CEL filter expression.
		parts := strings.Split(creatorName, "/")
		if len(parts) == 2 {
			params.Set("filter", fmt.Sprintf("creator == \"%s\"", creatorName))
		}
		if pageToken != "" {
			params.Set("pageToken", pageToken)
		}

		path := "/api/v1/memos?" + params.Encode()
		body, err := c.doRequest("GET", path)
		if err != nil {
			fmt.Println()
			return nil, fmt.Errorf("listing memos (state=%s): %w", state, err)
		}

		var resp MemosListMemosResponse
		if err := json.Unmarshal(body, &resp); err != nil {
			fmt.Println()
			return nil, fmt.Errorf("parsing memos response: %w", err)
		}

		allMemos = append(allMemos, resp.Memos...)
		fmt.Printf(" %d", len(allMemos))

		if resp.NextPageToken == "" {
			break
		}
		pageToken = resp.NextPageToken
	}

	fmt.Printf(" done (%d %s memos)\n", len(allMemos), state)
	return allMemos, nil
}

// ListAllMemos returns all NORMAL and ARCHIVED memos for a creator, sorted
// by create time ascending (oldest first).
func (c *MemosClient) ListAllMemos(creatorName string) ([]MemosMemo, error) {
	normal, err := c.ListMemos(creatorName, "NORMAL")
	if err != nil {
		return nil, err
	}
	archived, err := c.ListMemos(creatorName, "ARCHIVED")
	if err != nil {
		return nil, err
	}

	all := append(normal, archived...)
	fmt.Printf("    Total: %d memos (%d normal, %d archived). Sorting by date...\n", len(all), len(normal), len(archived))

	// Sort by CreateTime ascending.
	for i := 0; i < len(all); i++ {
		for j := i + 1; j < len(all); j++ {
			if all[j].CreateTime.Before(all[i].CreateTime) {
				all[i], all[j] = all[j], all[i]
			}
		}
	}

	return all, nil
}

// DownloadAttachment downloads an attachment file from the Memos file server.
// attachmentName is like "attachments/uid123", filename is the original filename.
func (c *MemosClient) DownloadAttachment(attachmentName, filename string) (*FileData, error) {
	// Extract UID from "attachments/uid123"
	parts := strings.SplitN(attachmentName, "/", 2)
	if len(parts) != 2 {
		return nil, fmt.Errorf("invalid attachment name: %s", attachmentName)
	}
	uid := parts[1]

	path := "/file/attachments/" + url.PathEscape(uid) + "/" + url.PathEscape(filename)
	reqURL := c.baseURL + path
	req, err := http.NewRequest("GET", reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("creating attachment download request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+c.token)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("downloading attachment %s: %w", attachmentName, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("HTTP %d downloading attachment %s/%s", resp.StatusCode, uid, filename)
	}

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("reading attachment data: %w", err)
	}

	contentType := resp.Header.Get("Content-Type")
	if contentType == "" {
		contentType = "application/octet-stream"
	}

	return &FileData{
		Filename:    filename,
		ContentType: contentType,
		Data:        data,
	}, nil
}
