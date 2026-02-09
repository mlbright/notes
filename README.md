# Notes

A self-hosted note-taking application inspired by Google Keep. Built with Ruby on Rails, SQLite, and Hotwire, with companion mobile apps via Turbo Native.

## Features

- **Rich editing** — Toggle between WYSIWYG (Tiptap/ProseMirror) and raw Markdown; content stored as Markdown
- **Organization** — Pin, archive, and tag notes with colored labels
- **Full-text search** — SQLite FTS5-powered search across titles and bodies
- **Version history** — Automatic snapshots on every save; view diffs and restore previous versions
- **Sharing** — Share notes read-write with other users; revocable by the owner
- **Attachments** — Upload files, images, and videos (stored locally via Active Storage, 25 MB default limit)
- **Soft delete** — Trashed notes are permanently deleted after 30 days
- **Export** — Download individual notes or bulk-export as Markdown files
- **REST API** — Complete JSON API at `/api/v1/` with token-based auth, pagination, rate limiting, and OpenAPI docs at `/api/docs`
- **Authentication** — Google OAuth2 for web sessions; email/password with token-based auth for API and mobile clients
- **Admin panel** — User management and platform settings for administrators
- **Responsive design** — Card-based layout that works well on desktop and in Turbo Native mobile shells

## Prerequisites

- **Ruby** 4.0.1 (see `web/.ruby-version`)
- **Bundler** (ships with Ruby)
- **SQLite** 3.x with development headers
- **libvips** (for image processing / Active Storage variants)
- **Node.js** (not required — asset pipeline uses importmap)
- **Go** 1.23+ (only for the optional `cmd/import-memos` tool)

On Debian/Ubuntu:

```bash
sudo apt-get install sqlite3 libsqlite3-dev libvips
```

## Project Structure

```
notes/
├── AGENTS.md           # Architecture and design specification
├── README.md           # This file
├── web/                # Rails application
│   ├── app/            # Models, controllers, views, jobs, assets
│   ├── config/         # Rails configuration, routes, deploy config
│   ├── db/             # Migrations, schema, seeds
│   ├── spec/           # RSpec test suite
│   ├── Dockerfile      # Production container image
│   ├── Gemfile         # Ruby dependencies
│   └── Procfile.dev    # Foreman process definitions for development
└── cmd/
    └── import-memos/   # Go CLI tool to migrate data from Memos
```

## Getting Started

### Setup

```bash
cd web
bin/setup
```

This installs gem dependencies, creates the SQLite database, and runs migrations. A default admin user is seeded (`mlbright@gmail.com` / `admin`).

### Development Server

```bash
cd web
bin/dev
```

This starts the Rails server and Tailwind CSS watcher via Foreman. The app is available at **http://localhost:3000**.

Alternatively, start the Rails server alone:

```bash
cd web
bin/rails server
```

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `PORT` | `3000` | HTTP port for the development server |
| `RAILS_ENV` | `development` | Rails environment (`development`, `test`, `production`) |
| `RAILS_MASTER_KEY` | — | Decrypts `config/credentials.yml.enc` (required in production) |
| `WEB_CONCURRENCY` | `1` | Number of Puma worker processes |
| `RAILS_MAX_THREADS` | `5` | Threads per Puma worker / max DB connections |
| `SOLID_QUEUE_IN_PUMA` | `true` | Run Solid Queue background jobs inside the Puma process |

## Testing

The test suite uses RSpec with FactoryBot:

```bash
cd web

# Run the full test suite
bundle exec rspec

# Run a specific spec file
bundle exec rspec spec/models/note_spec.rb

# Run a specific test by line number
bundle exec rspec spec/requests/api/v1/notes_spec.rb:42
```

### CI Pipeline

```bash
cd web
bin/ci
```

This runs the full CI pipeline:

1. `bin/setup` — Install dependencies and prepare the database
2. `bin/rubocop` — Ruby style checks (Standard/Rails Omakase)
3. `bin/bundler-audit` — Gem vulnerability audit
4. `bin/importmap audit` — JavaScript dependency audit
5. `bin/brakeman` — Static security analysis

## Building for Production

### Docker

```bash
cd web

# Build the production image
docker build -t notes .

# Run the container
docker run -d \
  -p 80:80 \
  -e RAILS_MASTER_KEY=<value-from-config/master.key> \
  -v notes_storage:/rails/storage \
  --name notes \
  notes
```

The Dockerfile uses a multi-stage build:
- **Build stage** — Installs gems, precompiles bootsnap and assets
- **Runtime stage** — Minimal image with the compiled app, runs as non-root user
- **Entrypoint** — Automatically runs pending migrations on startup
- **Server** — Puma behind Thruster (HTTP compression + asset caching), exposed on port 80

### Asset Precompilation

If deploying without Docker:

```bash
cd web
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile
```

## Deployment

### With Kamal

The project includes a [Kamal](https://kamal-deploy.org) configuration at `web/config/deploy.yml`:

```bash
cd web

# First-time setup
bin/kamal setup

# Deploy
bin/kamal deploy

# Open a Rails console on the server
bin/kamal console

# Tail logs
bin/kamal logs
```

Edit `config/deploy.yml` to configure:
- **Server IP** — Update `servers.web` with your VPS address
- **Registry** — Point to your Docker registry
- **Environment** — Set `RAILS_MASTER_KEY` and other secrets in `.kamal/secrets`

### Manual VPS Deployment

Target: Ubuntu/Debian VPS with nginx + systemd.

1. **Install dependencies:**
   ```bash
   sudo apt-get install ruby sqlite3 libsqlite3-dev libvips nginx
   ```

2. **Clone and set up:**
   ```bash
   git clone <repo-url> /opt/notes
   cd /opt/notes/web
   RAILS_ENV=production bin/setup
   ```

3. **Set the master key:**
   ```bash
   # Copy from your local machine:
   scp config/master.key server:/opt/notes/web/config/master.key
   # Or set as an environment variable:
   export RAILS_MASTER_KEY=<your-key>
   ```

4. **Precompile assets:**
   ```bash
   RAILS_ENV=production bin/rails assets:precompile
   ```

5. **Create a systemd service** (`/etc/systemd/system/notes.service`):
   ```ini
   [Unit]
   Description=Notes (Puma)
   After=network.target

   [Service]
   Type=simple
   User=deploy
   WorkingDirectory=/opt/notes/web
   Environment=RAILS_ENV=production
   Environment=RAILS_MASTER_KEY=<your-key>
   Environment=SOLID_QUEUE_IN_PUMA=true
   ExecStart=/opt/notes/web/bin/thrust /opt/notes/web/bin/rails server
   Restart=always

   [Install]
   WantedBy=multi-user.target
   ```

6. **Configure nginx** as a reverse proxy:
   ```nginx
   server {
       listen 80;
       server_name notes.example.com;

       location / {
           proxy_pass http://127.0.0.1:3000;
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto $scheme;
       }
   }
   ```

7. **TLS** — Use Let's Encrypt with Certbot:
   ```bash
   sudo apt-get install certbot python3-certbot-nginx
   sudo certbot --nginx -d notes.example.com
   ```

8. **Backups** — Use [Litestream](https://litestream.io) for continuous SQLite replication:
   ```bash
   litestream replicate /opt/notes/web/storage/production.sqlite3 s3://bucket/notes/
   ```

## API

The REST API is available at `/api/v1/`. Documentation is served at `/api/docs`.

### Authentication

```bash
# Obtain a token
curl -X POST http://localhost:3000/api/v1/auth/token \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "secret"}'

# Use the token
curl http://localhost:3000/api/v1/notes \
  -H "Authorization: Bearer <token>"
```

### Rate Limiting

API requests are rate-limited to **3000 requests per 5 minutes** per IP address and per API token. Exceeding the limit returns HTTP 429 with a `Retry-After` header.

## Import Tool

A standalone Go CLI at `cmd/import-memos/` migrates data from a [Memos](https://github.com/usememos/memos) instance into Notes.

### Build

```bash
cd cmd/import-memos
go build -o import-memos .
```

### Usage

```bash
./import-memos \
  --memos-url https://memos.example.com \
  --memos-token "$(cat ~/.memo-token)" \
  --notes-url http://localhost:3000 \
  --delay 200
```

| Flag | Required | Description |
|---|---|---|
| `--memos-url` | Yes | Base URL of the Memos instance |
| `--memos-token` | Yes | Personal Access Token for Memos |
| `--notes-url` | Yes | Base URL of the Notes instance |
| `--delay` | No | Milliseconds to wait between Notes API calls (default: 0) |
| `--dry-run` | No | Preview what would be imported without writing |

The tool interactively prompts for Notes user credentials to map Memos users to Notes accounts. It migrates:

- Memo content (with H1 headings extracted as note titles)
- Tags (created if they don't exist, default gray color)
- Pinned / archived state
- Attachments (files up to 25 MB)
- Original created/updated timestamps

### Limitations

- Memo relations, reactions, and comments are not migrated
- Visibility settings have no equivalent — all imported notes are private
- Shares are not migrated
- Tag colors default to gray (`#6b7280`)

## License

Private — all rights reserved.
