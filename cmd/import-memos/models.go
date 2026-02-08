package main

import "time"

// --- Memos API models ---

// MemosUser represents a user from the Memos API.
type MemosUser struct {
	Name        string `json:"name"`        // e.g. "users/1"
	Username    string `json:"username"`
	DisplayName string `json:"displayName"`
	Email       string `json:"email"`
	Role        string `json:"role"` // ADMIN, USER
	State       string `json:"state"`
}

// MemosListUsersResponse is the response from GET /api/v1/users.
type MemosListUsersResponse struct {
	Users         []MemosUser `json:"users"`
	NextPageToken string      `json:"nextPageToken"`
}

// MemosAttachment represents an attachment on a memo.
type MemosAttachment struct {
	Name         string `json:"name"`         // e.g. "attachments/uid123"
	Filename     string `json:"filename"`
	Type         string `json:"type"`         // MIME type
	Size         int64  `json:"size"`
	ExternalLink string `json:"externalLink"`
}

// MemosMemo represents a memo from the Memos API.
type MemosMemo struct {
	Name        string            `json:"name"` // e.g. "memos/abc123"
	State       string            `json:"state"` // NORMAL, ARCHIVED
	Creator     string            `json:"creator"` // e.g. "users/1"
	CreateTime  time.Time         `json:"createTime"`
	UpdateTime  time.Time         `json:"updateTime"`
	DisplayTime time.Time         `json:"displayTime"`
	Content     string            `json:"content"`
	Visibility  string            `json:"visibility"` // PRIVATE, PROTECTED, PUBLIC
	Tags        []string          `json:"tags"`
	Pinned      bool              `json:"pinned"`
	Attachments []MemosAttachment `json:"attachments"`
	Snippet     string            `json:"snippet"`
	Parent      string            `json:"parent"`
}

// MemosListMemosResponse is the response from GET /api/v1/memos.
type MemosListMemosResponse struct {
	Memos         []MemosMemo `json:"memos"`
	NextPageToken string      `json:"nextPageToken"`
}

// MemosUserStats is the response from GET /api/v1/users/{user}:getStats.
type MemosUserStats struct {
	Name     string         `json:"name"`
	TagCount map[string]int `json:"tagCount"`
}

// --- Notes API models ---

// NotesUser is not explicitly returned; we use auth info.
// We track users by their token and what the auth endpoint returns.

// NotesTag represents a tag from the Notes API.
type NotesTag struct {
	ID    int    `json:"id"`
	Name  string `json:"name"`
	Color string `json:"color"`
}

// NotesTagsResponse is the response from GET /api/v1/tags.
type NotesTagsResponse struct {
	Tags []NotesTag `json:"tags,omitempty"`
}

// NotesNote represents a note from the Notes API.
type NotesNote struct {
	ID       int        `json:"id"`
	Title    string     `json:"title"`
	Body     string     `json:"body"`
	Pinned   bool       `json:"pinned"`
	Archived bool       `json:"archived"`
	Trashed  bool       `json:"trashed"`
	MaxSize  int        `json:"max_size"`
	UserID   int        `json:"user_id"`
	Tags     []NotesTag `json:"tags"`
}

// NotesPagination is the pagination info from Notes list endpoints.
type NotesPagination struct {
	Page  int `json:"page"`
	Limit int `json:"limit"`
	Pages int `json:"pages"`
	Count int `json:"count"`
}

// NotesListResponse is the response from GET /api/v1/notes.
type NotesListResponse struct {
	Notes      []NotesNote     `json:"notes"`
	Pagination NotesPagination `json:"pagination"`
}

// NotesAttachment represents attachment metadata from the Notes API.
type NotesAttachment struct {
	ID          int    `json:"id"`
	Filename    string `json:"filename"`
	ContentType string `json:"content_type"`
	ByteSize    int64  `json:"byte_size"`
}

// FileData holds a downloaded file ready for upload.
type FileData struct {
	Filename    string
	ContentType string
	Data        []byte
}

// UserMapping holds the mapping from a Memos user to a Notes user.
type UserMapping struct {
	MemosUserName    string // e.g. "users/1"
	MemosUsername     string
	MemosDisplayName string
	NotesToken       string
}

// MigrationStats tracks stats for a single user migration.
type MigrationStats struct {
	NotesCreated       int
	TagsCreated        int
	AttachmentsUploaded int
	Errors             []string
}
