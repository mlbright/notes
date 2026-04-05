# Notes MCP Server

An [MCP (Model Context Protocol)](https://modelcontextprotocol.io) server that connects AI agents to the Notes application. Enables Claude, Copilot, and other MCP-compatible agents to create, search, read, update, pin, archive, tag, and share notes.

## Prerequisites

- Node.js 18+ (uses built-in `fetch`)
- A running Notes web application with API access
- A user account with a password set

## Setup

```bash
cd mcp
npm install
npm run build
```

## Environment Variables

| Variable | Required | Description | Example |
|---|---|---|---|
| `NOTES_API_URL` | Yes | Base URL of the Notes app | `http://localhost:3000` |
| `NOTES_EMAIL` | Yes | Your account email | `user@example.com` |
| `NOTES_PASSWORD` | Yes | Your account password | `secret` |

## Available Tools

### Notes
| Tool | Description |
|---|---|
| `list_notes` | List notes with optional filter (pinned/archived/trash), tag, sort, pagination |
| `get_note` | Get a single note by ID with full content |
| `create_note` | Create a note with title, body (markdown), optional tags |
| `update_note` | Update a note's title, body, pinned status, or tags |
| `delete_note` | Soft-delete (trash) a note; if already trashed, permanently delete |
| `search_notes` | Full-text search across titles and bodies |
| `pin_note` | Toggle pinned status |
| `archive_note` | Archive a note |
| `unarchive_note` | Unarchive a note |
| `restore_note` | Restore a note from trash |
| `list_trash` | List trashed notes |

### Tags
| Tool | Description |
|---|---|
| `list_tags` | List all tags |
| `create_tag` | Create a tag with name and optional hex color |

### Sharing
| Tool | Description |
|---|---|
| `list_shares` | List users a note is shared with |
| `share_note` | Share a note with another user by email |
| `revoke_share` | Revoke a user's access to a shared note |

## Client Configuration

### Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) or `%APPDATA%\Claude\claude_desktop_config.json` (Windows):

```json
{
  "mcpServers": {
    "notes": {
      "command": "node",
      "args": ["/absolute/path/to/mcp/dist/index.js"],
      "env": {
        "NOTES_API_URL": "https://notes.example.com",
        "NOTES_EMAIL": "user@example.com",
        "NOTES_PASSWORD": "your-password"
      }
    }
  }
}
```

### VS Code (GitHub Copilot)

A `.vscode/mcp.json` file is already included in this repository. To get started:

1. **Build the server** (if you haven't already):
   ```bash
   cd mcp
   npm install
   npm run build
   ```

2. **Add your credentials** — open `.vscode/mcp.json` and fill in `NOTES_EMAIL` and `NOTES_PASSWORD`. Update `NOTES_API_URL` if your server isn't at `http://localhost:3000`:
   ```json
   {
     "servers": {
       "notes": {
         "command": "node",
         "args": ["${workspaceFolder}/mcp/dist/index.js"],
         "env": {
           "NOTES_API_URL": "http://localhost:3000",
           "NOTES_EMAIL": "user@example.com",
           "NOTES_PASSWORD": "your-password"
         }
       }
     }
   }
   ```

3. **Reload VS Code** — the MCP server will appear in the Copilot agent mode tool list. You can verify by opening Copilot Chat (agent mode) and checking that tools like `list_notes`, `create_note`, and `search_notes` are available.

> **Tip:** To avoid committing credentials, add `.vscode/mcp.json` to your `.gitignore` or use VS Code's user-level MCP settings instead (Settings > search "mcp").

### Claude Code

```bash
claude mcp add notes -- node /absolute/path/to/mcp/dist/index.js \
  --env NOTES_API_URL=https://notes.example.com \
  --env NOTES_EMAIL=user@example.com \
  --env NOTES_PASSWORD=your-password
```

## Authentication Flow

The server authenticates lazily on the first tool call:

1. Calls `POST /api/v1/auth/token` with email + password
2. Receives a bearer token (30-day expiry)
3. Uses the token for all subsequent API calls
4. Automatically refreshes the token before it expires

## Development

```bash
npm run build   # Compile TypeScript
npm start       # Run the server (requires env vars)
```
