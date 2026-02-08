# A note taking and retrieval system

A Ruby on Rails notes application with companion Android and iOS apps built using Turbo Native (Hotwire).

## Architecture

- Single-instance deployment with role-based access (administrator + regular users)
- Ruby on Rails backend with SQLite database
- Mobile apps via Turbo Native, sharing the web UI with native navigation wrappers
- Attachments stored on local disk via Active Storage
- Deploy to a VPS with nginx (reverse proxy + TLS) and systemd

## Data model

- **User**: name, email, role (admin/user), session timeout (default 1h), preferences
- **Note**: title (optional), body (markdown), pinned, archived, trashed, trashed_at, max_size (default 32K), timestamps
- **Tag**: name, color; notes have many tags through a join table
- **NoteVersion**: snapshot of note body + metadata, created on each save
- **Share**: note_id, user_id, permission (read-write); owner can revoke
- **Attachment**: file/image/video via Active Storage, belongs to a note

## Authentication & authorization

- OAuth2 with Google as the identity provider
- Session-based auth for the web app; token-based auth (with refresh tokens) for Turbo Native clients
- Admin role can manage users and see platform-level settings
- Users can only access their own notes plus notes explicitly shared with them
- Adjustable session timeout defaulting to 1h with sliding expiration

## Features

### Notes
- Notes are private by default
- Notes can be shared read-write with other users; sharing is revocable
- Notes can be pinned and archived
- Notes can be copied and merged
- Soft-delete: notes go to trash first, permanently deleted after 30 days
- Display created and updated timestamps
- Version history: a snapshot is saved on each edit; users can view diffs and restore previous versions
- Adjustable maximum note size with a 32K character default

### Editor
- Toggle between WYSIWYG rich-text editing and raw markdown editing
- WYSIWYG mode powered by Tiptap (ProseMirror-based); stores content as markdown
- Click to open a note, edit button (or double-click on desktop) to enter edit mode

### Attachments
- File, image, and video attachments on notes
- Stored on local disk via Active Storage
- Configurable per-file size limit (default 25 MB)

### Search & organization
- Full-text search across note titles and bodies (SQLite FTS5)
- Tag notes with user-defined labels for organization
- Filter notes by tag, pinned/archived/trashed status, and date range

### Export
- Export a single note as a markdown file
- Bulk-export all notes (or a filtered set) as a directory of markdown files

### API
- Complete RESTful JSON API covering all application features (notes CRUD, tags, sharing, attachments, search, export)
- Token-based authentication (same mechanism used by Turbo Native clients)
- Versioned endpoints (e.g., /api/v1/) to allow non-breaking evolution
- Pagination, filtering, and sorting on collection endpoints
- Consistent error responses with standard HTTP status codes
- OpenAPI (Swagger) specification auto-generated from the codebase and kept up to date
- Rate limiting to protect against abuse
- API documentation published and accessible at /api/docs

## Development

### Guidelines
- All files (Ruby, JavaScript, YAML, Markdown, etc.) must be formatted according to the dominant community standard for that language (e.g., Standard for Ruby, Prettier for JS, markdownlint for Markdown)
- Enforce formatting and linting in CI — PRs that fail checks should not be merged
- Follow Rails conventions (REST resources, fat models/thin controllers, concerns for shared behavior)
- Write clear, descriptive commit messages; keep commits focused on a single change

### Testing
- Comprehensive test suite covering models, controllers, request specs, and system/integration tests
- Aim for high coverage on business logic (sharing, permissions, versioning, search)
- CI pipeline running tests and linting on every push
- Use factories (FactoryBot) over fixtures for test data

### Project structure
- Keep the Rails app and the Turbo Native mobile apps in their own separate directories
- Use Solid Queue for any background jobs (e.g., permanent trash deletion)

## Deployment

- Target: VPS (Ubuntu/Debian)
- nginx as reverse proxy with TLS (Let's Encrypt)
- systemd unit(s) to manage the Rails app (Puma) and Solid Queue workers
- SQLite database with Litestream for continuous replication/backups
- Active Storage files backed up alongside the database

## Aesthetics

- Simplicity is the primary design principle
- Take inspiration from Google Keep: card-based layout, minimal chrome, fast interactions
- Responsive design that works well in Turbo Native mobile shells
