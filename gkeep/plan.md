# Plan: Import Google Keep Notes to Hippo Service

## TL;DR
Import 399 Google Keep notes (JSON exports from Takeout) into the Hippo notes service at `https://hippo.chameleon-gopher.ts.net/` via its REST API. A Go program will parse each JSON file, convert content (text notes, checklists, annotations) to the expected format, authenticate via the API, create notes with preserved timestamps, apply state (archived/pinned/trashed), upload image attachments, and skip duplicates on re-run. Rate limiting (300 req/5 min) must be respected.

## Steps

### Phase 1: Setup
1. Initialize Go module in `gkeep/` (`go mod init gkeep-import`).
2. Single-file `main.go` — no external dependencies, use `net/http`, `encoding/json`, `mime/multipart`, `os`, `path/filepath`, `time`.

### Phase 2: Authentication
3. Parse `gkeep/credentials` (line 1: `user: <email>`, line 2: `password: <pw>`).
4. POST `/api/v1/auth/token` with `{"email": "...", "password": "..."}` to obtain Bearer token.

### Phase 3: Duplicate Detection — Fetch Existing Notes
5. Before importing, paginate through `GET /api/v1/notes?limit=100&page=N` (all filters: active, archived, pinned, trash) to build a set of existing notes keyed by `(title, created_at)`.
6. Also check `GET /api/v1/notes?filter=archived`, `GET /api/v1/notes?filter=trash` to cover all states.
7. Store as a `map[string]bool` where key = `title + "|" + created_at_iso`.

### Phase 4: Parse & Transform Notes
8. `filepath.Glob("Takeout/Keep/*.json")` to find all note files.
9. For each JSON file, unmarshal and transform:
   - **Title**: `title` → `title` (pass through)
   - **Body (text notes)**: `textContent` → `body`
   - **Body (list notes)**: `listContent` → markdown checklist (`- [x] item` / `- [ ] item`), skip empty items
   - **Annotations**: Append web links as `\n\n---\n[title](url)` for each annotation
   - **Timestamps**: Convert `createdTimestampUsec` / `userEditedTimestampUsec` (microseconds since epoch) → ISO 8601 for `created_at` / `updated_at`
   - **Pinned**: `isPinned` → `pinned`
   - **Checklist**: `true` when note has `listContent`
   - **Attachments**: `attachments` array with `filePath` and `mimetype` fields (5 notes have these)

### Phase 5: Create Notes via API (with dedup + attachments)
10. For each note, check the dedup map — if `(title, created_at)` already exists, log "skipped" and continue.
11. POST `/api/v1/notes` with `{title, body, pinned, checklist, created_at, updated_at}`.
12. If `isArchived` → PATCH `/api/v1/notes/:id/archive`.
13. If `isTrashed` → DELETE `/api/v1/notes/:id` (soft-delete).
14. If `attachments` field is present → for each attachment, open the image file from `Takeout/Keep/<filePath>`, POST as multipart form to `/api/v1/notes/:id/attachments` with field name `files[]`.
15. Rate limiting: track request count per 5-min window, sleep when approaching 280.
16. Log progress: filename, note ID, status (created/skipped/archived/trashed/attachment-uploaded/error).

## Relevant Files

**Source (Google Keep):**
- `gkeep/Takeout/Keep/*.json` — 399 note JSON files to parse
- `gkeep/credentials` — API credentials (email + password)
- `gkeep/Takeout/Keep/1646858452060.156945860.png` — attached to "Milpitas Trip March 2022"
- `gkeep/Takeout/Keep/1649012806970.511963.4167171958.jpg` — attached to "BlindsCharlotte"
- `gkeep/Takeout/Keep/1649013008445.920898.3678188915.jpg` — attached to "BlindsTheo"
- `gkeep/Takeout/Keep/1680363840639.1026319901.png` — attached to "Mother's day (Helen)"
- `gkeep/Takeout/Keep/1680363851850.1668385968.png` — attached to "Mother's day (Helen)"

**Destination (API):**
- `web/app/controllers/api/v1/notes_controller.rb` — `note_params` permits: `title`, `body`, `pinned`, `checklist`, `max_size`, `created_at`, `updated_at`
- `web/app/controllers/api/v1/notes_controller.rb` — `archive`, `destroy` actions for post-create state
- `web/app/controllers/api/v1/attachments_controller.rb` — multipart upload with `files[]` field, 25 MB max, returns 201
- `web/app/controllers/api/v1/auth_controller.rb` — Token auth endpoint

**Output:**
- `gkeep/main.go` — The import program
- `gkeep/go.mod` — Go module file
- `gkeep/plan.md` — This plan

## Verification
1. `go build -o gkeep-import . && ./gkeep-import` from the `gkeep/` directory — confirm it completes without errors
2. Check stdout log for count of created / skipped / archived / trashed / attachment-uploaded / error
3. Run again — all 399 notes should show "skipped" (dedup working)
4. `curl -H "Authorization: Bearer <token>" https://hippo.chameleon-gopher.ts.net/api/v1/notes?limit=5` — verify notes exist
5. `curl ... /api/v1/notes?filter=archived` — verify archived notes imported
6. Spot-check a list note body for `- [x]` / `- [ ]` markdown formatting
7. Spot-check "Milpitas Trip March 2022" note for uploaded attachment

## Decisions
- **Language**: Go (stdlib only, no external deps). Uses `net/http`, `encoding/json`, `mime/multipart`.
- **Trashed notes**: Import then soft-delete, preserving original state in service's trash
- **Keep colors**: Skip — no clean mapping to the service's tag model (Keep export has no labels)
- **Annotations**: Append as markdown links at end of body, separated by `---`
- **Deduplication**: Match on `(title, created_at)` — must fetch all existing notes (across active/archived/trash) before importing
- **Attachments**: JSON `attachments` array has `filePath` (filename in Keep dir) and `mimetype`. Upload via multipart POST to `/api/v1/notes/:id/attachments` with field name `files[]`.
- **Rate limiting**: Counter + sleep approach; reset counter every 5 minutes, sleep when nearing 280 requests
- **Script location**: `gkeep/main.go` run from `gkeep/` directory, paths to Takeout are relative
