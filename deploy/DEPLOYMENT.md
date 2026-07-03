# Deployment Guide

Production runs **directly from this git checkout**. There is no separate
deployed copy: the working tree at the repo root (e.g. `/home/ubuntu/notes`)
is both the development workspace and the production deployment.

## Principles

- **All production state lives inside this directory.** Copy the directory to
  a new machine, run `make install`, and production runs there. The only
  artifacts outside the repo are the systemd units, which are generated from
  templates in `deploy/` and contain no secrets.
- **The service runs as your own user** (whoever runs `make install`), so
  git, the app, mise-managed Ruby, and backups all share one owner.
- **No git in `make update`.** Production runs whatever the working tree
  contains; keeping the tree in a runnable state is the operator's job.

### Production state inventory

| State                                   | Location                        |
|-----------------------------------------|---------------------------------|
| SQLite databases (primary/cache/queue/cable) | `web/storage/*.sqlite3`    |
| Active Storage blobs                    | `web/storage/<2-char dirs>/`    |
| Rails master key                        | `web/config/master.key`         |
| Runtime env (APP_HOST, Google OAuth, …) | `web/.env`                      |
| Backup credentials (S3/AWS, ntfy)       | `deploy/backup.env`             |

All of these are gitignored. Everything else is code and regenerable.

## Architecture

```
               ┌─────────────────────────────┐
 Internet ───▶ │ Caddy machine (443, TLS)    │   ← separate host; see
               └──────────┬──────────────────┘     deploy/caddy-snippet.md
                          │ Tailscale, plain HTTP
               ┌──────────▼──────────────────┐
               │ this machine :3002 Thruster │   ← listens on all interfaces
               │        127.0.0.1:3001 Puma  │   ← loopback only
               │        + Solid Queue        │
               └──────────┬──────────────────┘
                          │
               ┌──────────▼──────────────────┐
               │ web/storage/*.sqlite3       │
               │ web/storage/ (blobs)        │
               └─────────────────────────────┘
```

TLS terminates at Caddy; `config.assume_ssl` / `config.force_ssl` are enabled
in production, so the app generates https URLs and secure cookies based on
`X-Forwarded-Proto`.

## Prerequisites

- Ubuntu 24.04+ with sudo access
- [mise](https://mise.jdx.dev/) installed for your user, with Ruby
  provisioned: `cd web && mise install`
- Tailscale (or equivalent private network) connecting this machine and the
  Caddy machine

## First-time setup

```bash
git clone <repo-url> ~/notes
cd ~/notes

# 1. Ruby via mise
cd web && mise install && cd ..

# 2. Secrets — see "Secrets reference" below
cp /path/to/master.key web/config/master.key && chmod 600 web/config/master.key
$EDITOR web/.env
cp deploy/backup.env.example deploy/backup.env && $EDITOR deploy/backup.env
chmod 600 deploy/backup.env

# 3. Install system packages + systemd units (uses sudo)
make install

# 4. Gems, database, assets, start
make update

# 5. Verify
make status
curl -s http://localhost:3002/up
```

Then configure the Caddy machine: see [caddy-snippet.md](./caddy-snippet.md).

## Secrets reference

### `web/.env`

Loaded by the systemd unit (`EnvironmentFile`). Keep `chmod 600`.

```env
# Public domain served by the Caddy machine (enables Host authorization).
APP_HOST=notes.example.com

# Google OAuth2 (web sign-in).
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...

# Only needed if web/config/master.key is absent.
#RAILS_MASTER_KEY=...
```

### `web/config/master.key`

Decrypts `web/config/credentials.yml.enc`. `chmod 600`.

### `deploy/backup.env`

S3 bucket and AWS credentials for the backup timer; see
[backup.env.example](./backup.env.example). `chmod 600`.

## Make targets

| Target         | What it does                                                        |
|----------------|---------------------------------------------------------------------|
| `make install` | `install-deps` + `install-web` + `install-backup` (idempotent)      |
| `make install-deps`   | apt packages (build tools, sqlite3, libvips, awscli, …)      |
| `make install-web`    | Renders + installs `notes-web.service`, enables it           |
| `make install-backup` | Renders + installs backup service + timer, enables the timer |
| `make update`  | `bundle install` → `db:prepare` → `assets:precompile` → restart     |
| `make restart` | Restart the service                                                 |
| `make status`  | Service status + backup timer schedule                              |
| `make logs`    | Follow the journal                                                  |

`make install` bakes the repo path, your username, and the current mise Ruby
path into the installed units. **Re-run `make install-web install-backup`
after upgrading Ruby or moving the repo.** Never edit the files in
`/etc/systemd/system` directly — they are generated artifacts.

## Updating the app

```bash
cd ~/notes
git pull          # or merge, or edit — your call; make never touches git
make update
```

Because this is a dual-use checkout, remember: **a service restart boots
whatever is in the working tree**, including half-finished edits. Keep the
tree runnable before `make update`, reboots, or anything that restarts the
service.

## Backups

A systemd timer (`notes-backup.timer`) uploads consistent `sqlite3 .backup`
snapshots of all four databases plus the Active Storage blobs to S3 every
6 hours (see `deploy/backup-s3.sh`).

```bash
# Run one manually / inspect
sudo systemctl start notes-backup.service
journalctl -u notes-backup.service -e
systemctl list-timers notes-backup.timer
```

Frequency: edit `OnCalendar=` in `deploy/notes-backup.timer`, then
`make install-backup`. Retention: use an S3 lifecycle policy.

## Migrating production from another machine (cold cutover)

Scenario: the old machine runs the classic layout (app at `/opt/notes/web`,
OAuth secrets in a systemd drop-in, AWS keys in `/etc/notes-backup.env`).
Afterwards, the old machine shuts down and this checkout runs production.
The public domain stays the same, so Google OAuth redirect URIs are untouched.

On **this machine**, complete "First-time setup" above through step 3
(`make install`) — but don't create secrets or run `make update` yet; they
come from the old machine.

1. **Stop production on the old machine** (this is the start of downtime;
   a clean stop checkpoints the SQLite WAL files so plain file copies are
   consistent):

   ```bash
   ssh old-machine 'sudo systemctl stop notes-web && sudo systemctl disable --now notes-backup.timer'
   ```

2. **Copy the databases and blobs** into this checkout:

   ```bash
   scripts/pull-production-storage old-machine   # host defaults to rattlesnake
   ```

   The script is a guarded version of
   `rsync -av old-machine:/opt/notes/web/storage/ web/storage/`: it aborts if
   `notes-web` is running on either machine, aborts on a non-empty remote WAL
   (the fingerprint of an unclean stop — after a clean stop the `-wal`/`-shm`
   sidecars are empty leftovers, and it excludes them from the copy), requires
   `--force` to overwrite existing local production databases, never deletes
   local files, and reads the remote side with `sudo rsync` (needs
   passwordless sudo; use `--no-sudo` if the files are readable directly).
   `--dry-run` previews the transfer.

3. **Copy the master key:**

   ```bash
   rsync -av old-machine:/opt/notes/web/config/master.key ~/notes/web/config/master.key
   chmod 600 ~/notes/web/config/master.key
   ```

4. **Reconstruct `web/.env`** from the old machine's `.env` plus the OAuth
   drop-in (the drop-in mechanism no longer exists here):

   ```bash
   # Old .env, if it existed:
   ssh old-machine 'sudo cat /opt/notes/web/.env' >> ~/notes/web/.env
   # OAuth credentials from the old systemd drop-in:
   ssh old-machine 'sudo cat /etc/systemd/system/notes-web.service.d/oauth.conf'
   # → copy GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET values into ~/notes/web/.env
   # Add the public domain:
   echo 'APP_HOST=notes.example.com' >> ~/notes/web/.env
   chmod 600 ~/notes/web/.env
   ```

5. **Recreate the backup credentials** from the old `/etc/notes-backup.env`:

   ```bash
   ssh old-machine 'sudo cat /etc/notes-backup.env' > ~/notes/deploy/backup.env
   chmod 600 ~/notes/deploy/backup.env
   ```

6. **Migrate and start** (this checkout's code may carry newer migrations
   than the old machine's data — `db:prepare` inside `make update` handles
   that):

   ```bash
   cd ~/notes
   make update
   make status
   curl -s http://localhost:3002/up        # expect 200
   ```

7. **Cut over the reverse proxy**: point the Caddy machine's
   `reverse_proxy` at this machine's Tailscale hostname
   (see [caddy-snippet.md](./caddy-snippet.md)), reload Caddy, and verify
   `https://<domain>/up` and a real sign-in end to end.

8. **Decommission the old machine** once you've confirmed sign-in, note
   content, attachments, and a manual backup run
   (`sudo systemctl start notes-backup.service`) all work from here.

## Managing the service

```bash
make status                      # service + timer overview
make logs                        # journal (Puma stdout/stderr)
sudo systemctl {start|stop|restart|reload} notes-web
tail -f web/log/production.log   # Rails application log
```

## Troubleshooting

| Symptom                    | Check                                                        |
|----------------------------|--------------------------------------------------------------|
| Service won't start        | `journalctl -u notes-web -e`                                 |
| 502 from Caddy             | Is Thruster up? `curl http://localhost:3002/up`; tailnet reachable from the Caddy box? |
| Blocked host error         | `APP_HOST` in `web/.env` must equal the public domain        |
| Redirect loop / http URLs  | Caddy must forward `X-Forwarded-Proto` (default `reverse_proxy` does) |
| Assets not loading         | `make update` (re-runs `assets:precompile`)                  |
| Master key errors          | `web/config/master.key` present and `chmod 600`?             |
| Write errors (DB/uploads)  | `ReadWritePaths` in the unit; re-run `make install-web` if the repo moved |
| Stale Ruby after upgrade   | Re-run `make install-web` (unit bakes in the mise Ruby path) |
| Backup failures            | `journalctl -u notes-backup -e`; `deploy/backup.env` present and valid? |
