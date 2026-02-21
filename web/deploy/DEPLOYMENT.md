# Deployment Guide — VPS with systemd + Caddy

This guide covers deploying the Notes app to an Ubuntu/Debian VPS as a systemd
service behind Caddy with automatic TLS.

## Architecture

```
                ┌────────────────────┐
  Internet ───▶│  Caddy (443/TLS)   │
                └────────┬───────────┘
                         │ reverse_proxy :3000
                ┌────────▼───────────┐
                │  Thruster          │
                │  (asset cache/gzip)│
                └────────┬───────────┘
                         │
                ┌────────▼───────────┐
                │  Puma              │
                │  + Solid Queue     │
                │  (single process)  │
                └────────┬───────────┘
                         │
                ┌────────▼───────────┐
                │  SQLite databases  │
                │  storage/*.sqlite3 │
                └────────────────────┘
```

Puma runs Solid Queue in-process (`SOLID_QUEUE_IN_PUMA=true`), so there is
only **one systemd service** to manage.  Thruster sits in front of Puma to
handle compressed asset serving and X-Sendfile acceleration.

## Prerequisites

| Requirement       | Version / Notes                     |
|-------------------|-------------------------------------|
| OS                | Ubuntu 22.04+ or Debian 12+         |
| Ruby              | 4.0.1 (matches `.ruby-version`)     |
| SQLite            | 3.35+ (ships with above distros)    |
| Caddy             | any recent packaged version         |
| Domain + DNS      | A record pointing to the VPS IP     |
| Ports 80/443 open | for HTTP/HTTPS traffic               |

## Quick Start (automated)

```bash
# On the VPS, clone the repo and run the installer:
git clone <repo-url> /tmp/notes-src
cd /tmp/notes-src/web

# Edit the variables at the top of deploy/install.sh:
#   DOMAIN, LETSENCRYPT_EMAIL
sudo bash deploy/install.sh
```

The script:
1. Installs system dependencies (build tools, Caddy)
2. Creates a `notes` system user
3. Installs Ruby 4.0.1 via `ruby-install`
4. Copies the app to `/opt/notes/web`
5. Runs `bundle install` (deployment mode, no dev/test gems)
6. Prepares the production database (`db:prepare`)
7. Precompiles assets (Tailwind + Propshaft)
8. Installs the systemd unit and enables it
9. Configures Caddy (TLS is automatic via Let's Encrypt / ZeroSSL)
10. Starts the service

## Manual Setup

### 1. System dependencies

```bash
sudo apt update
sudo apt install -y build-essential git curl libssl-dev libreadline-dev \
  zlib1g-dev libsqlite3-dev libyaml-dev libffi-dev \
  debian-keyring debian-archive-keyring apt-transport-https

# Install Caddy
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt install -y caddy
```

### 2. Create application user

```bash
sudo useradd --system --create-home --shell /usr/sbin/nologin notes
```

### 3. Install Ruby

Use [ruby-install](https://github.com/postmodern/ruby-install):

```bash
ruby-install --system ruby 4.0.1
```

Or use your preferred Ruby version manager (rbenv, asdf, mise, etc.).

### 4. Deploy application code

```bash
sudo mkdir -p /opt/notes/web
sudo rsync -a --delete \
  --exclude='.git' \
  --exclude='storage/development.sqlite3' \
  --exclude='storage/test.sqlite3' \
  /path/to/source/web/ /opt/notes/web/
sudo chown -R notes:notes /opt/notes/web
```

### 5. Install gems

```bash
cd /opt/notes/web
sudo -u notes bundle config set --local deployment true
sudo -u notes bundle config set --local without 'development test'
sudo -u notes bundle install --jobs 4
```

### 6. Configure secrets

Copy your `master.key` to the server:

```bash
scp config/master.key root@server:/opt/notes/web/config/master.key
sudo chown notes:notes /opt/notes/web/config/master.key
sudo chmod 600 /opt/notes/web/config/master.key
```

Alternatively, set the `RAILS_MASTER_KEY` environment variable in
`/opt/notes/web/.env`:

```bash
echo 'RAILS_MASTER_KEY=your-key-here' | sudo tee /opt/notes/web/.env
sudo chown notes:notes /opt/notes/web/.env
sudo chmod 600 /opt/notes/web/.env
```

### 7. Prepare database and assets

```bash
sudo -u notes bash -c 'cd /opt/notes/web && RAILS_ENV=production bin/rails db:prepare'
sudo -u notes bash -c 'cd /opt/notes/web && RAILS_ENV=production bin/rails assets:precompile'
```

### 8. Install systemd service

```bash
sudo cp /opt/notes/web/deploy/notes-web.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable notes-web
sudo systemctl start notes-web
```

### 9. Configure Caddy

```bash
# Copy and edit the Caddyfile (replace domain):
sudo sed 's/notes\.example\.com/your-domain.com/g' \
  /opt/notes/web/deploy/Caddyfile \
  > /etc/caddy/Caddyfile

sudo mkdir -p /var/log/caddy

# Validate and reload:
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

Caddy automatically provisions and renews TLS certificates via Let's Encrypt
(or ZeroSSL). No separate `certbot` step is needed — just ensure the domain's
DNS A record points to the VPS and ports 80/443 are open.

## Managing the Service

```bash
# Start / stop / restart
sudo systemctl start notes-web
sudo systemctl stop notes-web
sudo systemctl restart notes-web

# View status
sudo systemctl status notes-web

# Follow logs (stdout/stderr from Puma)
sudo journalctl -u notes-web -f

# Follow Rails application log
tail -f /opt/notes/web/log/production.log

# Graceful restart (zero-downtime via Puma hot restart)
sudo systemctl reload notes-web    # sends USR1 to Puma
```

## Environment Variables

Set these in `/opt/notes/web/.env` (loaded by the systemd unit via
`EnvironmentFile`). The service file provides sensible defaults for all of
them.

| Variable              | Default     | Description                            |
|-----------------------|-------------|----------------------------------------|
| `RAILS_ENV`           | `production`| Rails environment                      |
| `PORT`                | `3000`      | Puma listen port                       |
| `RAILS_MASTER_KEY`    | —           | Decrypts `credentials.yml.enc`         |
| `GOOGLE_CLIENT_ID`    | —           | Google OAuth2 client ID                |
| `GOOGLE_CLIENT_SECRET` | —          | Google OAuth2 client secret            |
| `SOLID_QUEUE_IN_PUMA` | `true`      | Run Solid Queue inside Puma            |
| `RAILS_MAX_THREADS`   | `3`         | Puma threads (also sets DB pool)       |
| `WEB_CONCURRENCY`     | `1`         | Puma worker processes                  |
| `RAILS_LOG_LEVEL`     | `info`      | `debug`, `info`, `warn`, `error`       |
| `RUBY_YJIT_ENABLE`    | `1`         | Enable YJIT JIT compiler              |

### OAuth Credentials

Google OAuth2 credentials are provided to the service via a systemd drop-in
override. The install script creates a placeholder at
`/etc/systemd/system/notes-web.service.d/oauth.conf`.

Edit it with your real values:

```bash
sudo systemctl edit notes-web   # opens the override in $EDITOR
```

Or edit the file directly:

```bash
sudo nano /etc/systemd/system/notes-web.service.d/oauth.conf
```

The file should contain:

```ini
[Service]
Environment=GOOGLE_CLIENT_ID=your-client-id
Environment=GOOGLE_CLIENT_SECRET=your-client-secret
```

Then reload and restart:

```bash
sudo systemctl daemon-reload
sudo systemctl restart notes-web
```

> **Note:** Environment variables take precedence over values stored in Rails
> encrypted credentials (`credentials.yml.enc`). If you prefer to use
> credentials instead, remove or leave the override values as `changeme` and
> store the secrets via `bin/rails credentials:edit` under the `google:` key.

## Backups with Litestream

[Litestream](https://litestream.io/) continuously replicates SQLite databases
to S3-compatible storage.

```bash
# Install Litestream
curl -fsSL https://github.com/benbjohnson/litestream/releases/latest/download/litestream-linux-amd64.tar.gz \
  | sudo tar -C /usr/local/bin -xz litestream

# Create config
sudo tee /etc/litestream.yml <<'EOF'
dbs:
  - path: /opt/notes/web/storage/production.sqlite3
    replicas:
      - type: s3
        bucket: your-backup-bucket
        path: notes/production.sqlite3
        endpoint: https://s3.your-provider.com
        access-key-id: ${LITESTREAM_ACCESS_KEY_ID}
        secret-access-key: ${LITESTREAM_SECRET_ACCESS_KEY}

  - path: /opt/notes/web/storage/production_queue.sqlite3
    replicas:
      - type: s3
        bucket: your-backup-bucket
        path: notes/production_queue.sqlite3
        endpoint: https://s3.your-provider.com

  - path: /opt/notes/web/storage/production_cache.sqlite3
    replicas:
      - type: s3
        bucket: your-backup-bucket
        path: notes/production_cache.sqlite3
        endpoint: https://s3.your-provider.com

  - path: /opt/notes/web/storage/production_cable.sqlite3
    replicas:
      - type: s3
        bucket: your-backup-bucket
        path: notes/production_cable.sqlite3
        endpoint: https://s3.your-provider.com
EOF

# Run as a systemd service
sudo systemctl enable --now litestream
```

## Updating the Application

```bash
# 1. Pull new code
cd /path/to/source && git pull

# 2. Sync to server
rsync -a --delete \
  --exclude='.git' \
  --exclude='storage/*.sqlite3' \
  --exclude='tmp' \
  --exclude='log' \
  web/ root@server:/opt/notes/web/

# 3. On the server
ssh root@server << 'EOF'
  cd /opt/notes/web
  chown -R notes:notes .
  sudo -u notes bundle install --quiet
  sudo -u notes RAILS_ENV=production bin/rails db:migrate
  sudo -u notes RAILS_ENV=production bin/rails assets:precompile
  sudo systemctl restart notes-web
EOF
```

## Troubleshooting

| Symptom                        | Check                                            |
|--------------------------------|--------------------------------------------------|
| Service won't start            | `journalctl -u notes-web -e` for error output    |
| 502 Bad Gateway from Caddy     | Is Puma running? `systemctl status notes-web`    |
| Assets not loading             | Run `bin/rails assets:precompile` again           |
| DB errors after migration      | Check ownership: `ls -la /opt/notes/web/storage/` |
| Permission denied              | Verify `ReadWritePaths` in the service file      |
| Master key errors              | Ensure `config/master.key` or `RAILS_MASTER_KEY` |
