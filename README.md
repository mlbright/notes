# Notes

A self-hosted note-taking application inspired by Google Keep. Built with Ruby
on Rails, SQLite, and Hotwire, with companion mobile apps via Turbo Native.

## Features

- **Rich editing** — Toggle between WYSIWYG (Tiptap/ProseMirror) and raw
  Markdown; content stored as Markdown
- **Organization** — Pin, archive, and tag notes with colored labels
- **Full-text search** — SQLite FTS5-powered search across titles and bodies
- **Version history** — Automatic snapshots on every save; view diffs and
  restore previous versions
- **Sharing** — Share notes read-write with other users; revocable by the owner
- **Attachments** — Upload files, images, and videos (stored locally via Active
  Storage, 25 MB default limit)
- **Soft delete** — Trashed notes are permanently deleted after 30 days
- **Export** — Download individual notes or bulk-export as Markdown files
- **REST API** — Complete JSON API at `/api/v1/` with token-based auth,
  pagination, rate limiting, and OpenAPI docs at `/api/docs`
- **Authentication** — Google OAuth2 for web sessions; email/password with
  token-based auth for API and mobile clients
- **Admin panel** — User management and platform settings for administrators
- **Responsive design** — Card-based layout that works well on desktop and in
  Turbo Native mobile shells

## Prerequisites

- **Ruby** 4.0.7, pinned in `web/mise.toml`; with
  [mise](https://mise.jdx.dev), `cd web && mise install` installs it
- **Bundler** (ships with Ruby)
- **SQLite** 3.x with development headers
- **libvips** (for image processing / Active Storage variants)
- **Node.js** (only for the optional `mcp/` server; the web app uses importmap)
- **shellcheck** and **[shfmt](https://github.com/mvdan/sh)** (only for
  `make lint` / `make format` on the shell scripts)

On Debian/Ubuntu:

```bash
sudo apt-get install sqlite3 libsqlite3-dev libvips
```

## Project Structure

```text
notes/
├── AGENTS.md           # Architecture and design specification
├── CONTEXT.md          # Glossary of domain terms
├── Makefile            # Deployment targets and shell lint/format (`make` lists them)
├── README.md           # This file
├── deploy/             # systemd unit templates, backup script, Caddy notes
├── docs/
│   └── adr/            # Architecture decision records
├── mcp/                # MCP server exposing the Notes API (TypeScript)
├── scripts/            # Operational helper scripts
└── web/                # Rails application
    ├── app/            # Models, controllers, views, jobs, assets
    ├── config/         # Rails configuration, routes, deploy config
    ├── db/             # Migrations, schema, seeds
    ├── spec/           # RSpec test suite
    ├── Dockerfile      # Production container image
    ├── Gemfile         # Ruby dependencies
    └── Procfile.dev    # Foreman process definitions for development
```

## Getting Started

### Setup

```bash
cd web
bin/setup
```

This installs gem dependencies, creates the SQLite database, and runs
migrations. A default admin user is seeded (`mlbright@gmail.com` / `admin`).

### Development Server

```bash
cd web
bin/dev
```

This starts the Rails server and Tailwind CSS watcher via Foreman. The app is
available at **<http://localhost:3000>**.

Alternatively, start the Rails server alone:

```bash
cd web
bin/rails server
```

### Environment Variables

| Variable              | Default       | Description                                                    |
| --------------------- | ------------- | -------------------------------------------------------------- |
| `PORT`                | `3000`        | HTTP port for the development server                           |
| `RAILS_ENV`           | `development` | Rails environment (`development`, `test`, `production`)        |
| `RAILS_MASTER_KEY`    | —             | Decrypts `config/credentials.yml.enc` (required in production) |
| `WEB_CONCURRENCY`     | `1`           | Number of Puma worker processes                                |
| `RAILS_MAX_THREADS`   | `5`           | Threads per Puma worker / max DB connections                   |
| `SOLID_QUEUE_IN_PUMA` | `true`        | Run Solid Queue background jobs inside the Puma process        |

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

### Shell Scripts

The shell scripts in `deploy/`, `scripts/`, and `web/bin/` are linted with
ShellCheck and formatted with shfmt, from the repo root:

```bash
make lint     # shellcheck, then fail if any script is not shfmt-formatted
make format   # rewrite the scripts in place with shfmt
```

The style (2-space indent, indented `case` arms) lives in `.editorconfig`, so
editors that run shfmt format the same way.

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
- **Server** — Puma behind Thruster (HTTP compression + asset caching), exposed
  on port 80

### Asset Precompilation

If deploying without Docker:

```bash
cd web
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile
```

## Deployment

Production runs **directly from the git checkout** — there is no separate
deployed copy. All production state (SQLite databases, Active Storage blobs,
secrets) lives inside the repo directory; the only artifacts outside it are
systemd units generated by `make install` from templates in `deploy/`. TLS is
handled by Caddy on a **separate machine**, reverse-proxying to this one over
Tailscale.

```bash
# One-time (and after Ruby upgrades): apt deps + systemd units
make install

# Deploy the current working tree: bundle, migrate, precompile, restart
make update

# Inspect
make status
make logs
```

See [deploy/DEPLOYMENT.md](deploy/DEPLOYMENT.md) for the full runbook —
first-time setup, secrets reference, backups (S3 timer), the Caddy snippet for
the proxy machine, and the cold-cutover procedure for migrating production from
another machine.

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

API requests are rate-limited to **3000 requests per 5 minutes** per IP address
and per API token. Exceeding the limit returns HTTP 429 with a `Retry-After`
header.

## Import Tool

The Memos import CLI was removed; it is available in git history at `d86b86c`
(`import-memos/`).

## License

Private — all rights reserved.
