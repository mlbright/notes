# Deployment Guide

Production runs **directly from this git checkout**. There is no separate
deployed copy: the working tree at the repo root (e.g. `/home/ubuntu/notes`) is
both the development workspace and the production deployment.

## Principles

- **All production state lives inside this directory.** Copy the directory to a
  new machine, run `make install`, and production runs there. The only artifacts
  outside the repo are the systemd units, which are generated from templates in
  `deploy/` and contain no secrets.
- **The service runs as your own user** (whoever runs `make install`), so git,
  the app, mise-managed Ruby, and backups all share one owner.
- **No git in `make update`.** Production runs whatever the working tree
  contains; keeping the tree in a runnable state is the operator's job.

### Production state inventory

| State                                        | Location                     |
| -------------------------------------------- | ---------------------------- |
| SQLite databases (primary/cache/queue/cable) | `web/storage/*.sqlite3`      |
| Active Storage blobs                         | `web/storage/<2-char dirs>/` |
| Rails master key                             | `web/config/master.key`      |
| Runtime env (APP_HOST, Google OAuth, …)      | `web/.env`                   |
| Backup credentials (S3/AWS, ntfy)            | `deploy/backup.env`          |

All of these are gitignored. Everything else is code and regenerable.

## Architecture

```text
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

TLS terminates at Caddy; `config.assume_ssl` / `config.force_ssl` are enabled in
production, so the app generates https URLs and secure cookies based on
`X-Forwarded-Proto`.

## Prerequisites

- Ubuntu 24.04+ with sudo access
- [mise](https://mise.jdx.dev/) installed for your user, with Ruby provisioned:
  `cd web && mise install`
- Tailscale (or equivalent private network) connecting this machine and the
  Caddy machine
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
  (not in Ubuntu's apt repositories) and, for the one-time backup provisioning,
  admin credentials for your AWS account (e.g. `aws login`, or a named AWS CLI
  profile)

## First-time setup

```bash
git clone <repo-url> ~/notes
cd ~/notes

# 1. Ruby via mise
cd web && mise install && cd ..

# 2. Secrets — see "Secrets reference" below
cp /path/to/master.key web/config/master.key && chmod 600 web/config/master.key
$EDITOR web/.env

# 3. Install system packages + systemd units (uses sudo). The first run
#    prompts for the S3 bucket and provisions it; see "Backups" below.
#    Add AWS_PROFILE=<name> to provision with a named AWS CLI profile.
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

S3 bucket, prefix, region, and the backup IAM user's access key. Written by
`deploy/install-backup.sh`; see [backup.env.example](./backup.env.example) to
write it by hand. `chmod 600`.

## Make targets

Run `make` (or `make help`) to list the targets with the variables and examples.

| Target                | What it does                                                                            |
| --------------------- | --------------------------------------------------------------------------------------- |
| `make help`           | List targets, variables, and examples (the default target)                              |
| `make install`        | `install-deps` + `install-web` + `install-backup` (idempotent)                          |
| `make install-deps`   | apt packages (build tools, sqlite3, libvips, …)                                         |
| `make install-web`    | Renders + installs `notes-web.service`, enables it                                      |
| `make install-backup` | `deploy/install-backup.sh`: provisions S3 on first run, installs backup service + timer |
| `make backup`         | Run a backup now                                                                        |
| `make update`         | `bundle install` → `db:prepare` → `assets:precompile` → restart                         |
| `make restart`        | Restart the service                                                                     |
| `make status`         | Service status + backup timer schedule                                                  |
| `make logs`           | Follow the journal                                                                      |

`make install` bakes the repo path, your username, and the current mise Ruby
path into the installed units. **Re-run `make install-web install-backup` after
upgrading Ruby or moving the repo.** Never edit the files in
`/etc/systemd/system` directly — they are generated artifacts.

## Updating the app

```bash
cd ~/notes
git pull          # or merge, or edit — your call; make never touches git
make update
```

Because this is a dual-use checkout, remember: **a service restart boots
whatever is in the working tree**, including half-finished edits. Keep the tree
runnable before `make update`, reboots, or anything that restarts the service.

## Backups

`notes-backup.timer` runs `deploy/backup-s3.sh` every hour. It keeps a **Backup
Mirror** of the whole checkout in S3: code, `.git`, uncommitted edits, secrets,
Active Storage blobs, and consistent `sqlite3 .backup` snapshots of the four
production databases. It excludes the Ephemeral Files listed in
[backup-exclude](./backup-exclude) (temp files, logs, compiled assets,
`node_modules`, test databases, WAL sidecars). See
[ADR 0002](../docs/adr/0002-backup-is-a-versioned-mirror-of-the-checkout.md).

```text
s3://<bucket>/<prefix>/tree/          mirror of the repo root
s3://<bucket>/<prefix>/manifest.tsv   file modes + symlinks (S3 can't store them)
```

Runs are incremental (`aws s3 sync --delete`): only changed files upload, plus
the database snapshots (~30 MB) every time. History comes from S3 bucket
**versioning**: overwritten and deleted objects are kept as noncurrent versions
for 30 days, then expired by a lifecycle rule. The backup IAM user can write and
read versions but cannot delete them, so a compromised machine cannot erase the
history.

Nothing about the AWS account is in the repo: the bucket, prefix, region, and
key live in the gitignored `deploy/backup.env`.

### Installing

```bash
aws login                       # admin credentials, used once for provisioning
deploy/install-backup.sh        # or: make install-backup
```

To provision with a named AWS CLI profile instead of the default credentials:

```bash
aws login --profile <name>      # if the profile uses an `aws login` session
make install-backup AWS_PROFILE=<name>
# or: deploy/install-backup.sh --admin-profile <name>
```

The script prompts for bucket, prefix (default `notes`), and region. Then it:

1. Creates the bucket if missing, blocks public access, enables versioning, and
   adds the lifecycle rule (`NONCURRENT_DAYS=60 deploy/install-backup.sh` to
   change the window). It won't overwrite a bucket's other lifecycle rules; it
   prints the rule for you to add instead.
2. Creates (or reuses) the IAM user `notes-backup-<hostname>` with an inline
   policy scoped to `<bucket>/<prefix>/*`
   ([backup-iam-policy.json.tmpl](./backup-iam-policy.json.tmpl)), and an access
   key for it. If the user already has a key, it asks before creating another.
3. Writes `deploy/backup.env` (`chmod 600`).
4. Verifies the key, installs and enables the systemd units, and runs a first
   backup.

Re-running it is safe. Use `--no-provision` to skip AWS entirely and only
install the units from an existing `backup.env`. `make install-backup` passes
`--no-provision` automatically once `backup.env` exists, so the profile only
matters on the first run (or when you run the script directly to re-provision).
The profile is used for provisioning only: the timer always runs with the backup
IAM user's key from `backup.env`.

### Operating

```bash
make backup                                  # run one now
journalctl -u notes-backup.service -e        # logs
systemctl list-timers notes-backup.timer     # schedule
aws s3 ls s3://<bucket>/<prefix>/manifest.tsv   # its timestamp = last complete run
```

- **Notifications:** set `NTFY_TOPIC` in `backup.env` to get an ntfy push on
  failure; add `NTFY_ON_SUCCESS=1` to also be told about successes.
- **Frequency:** edit `OnCalendar=` in `deploy/notes-backup.timer`, then
  `make install-backup`.
- **What's excluded:** edit `deploy/backup-exclude`. Excluded paths are also
  exempt from `--delete`, so objects already in S3 under a newly excluded path
  stay there until you remove them.

## Restore from S3

Restoring is a copy of the directory plus the usual install. It works the same
for disaster recovery and for moving to a new machine.

1. On the target machine, meet the Prerequisites (mise, Ruby via `mise install`
   once the tree is present, AWS CLI v2), and get credentials that can read the
   bucket: `aws login` (optionally for a named profile), or the backup key from
   a saved copy of `backup.env`.
2. If the old machine is still up, stop it first (see step 1 of the cold cutover
   below). Otherwise it keeps writing to the same mirror.
3. Fetch the restore script from the mirror and run it:

   ```bash
   aws s3 cp s3://<bucket>/notes/tree/deploy/restore-s3.sh . && chmod +x restore-s3.sh
   S3_BUCKET=<bucket> S3_PREFIX=notes ./restore-s3.sh ~/notes
   ```

   With a named AWS CLI profile, pass `--profile <name>` to both `aws` and
   `restore-s3.sh`.

   It downloads the latest mirror, removes stale WAL sidecars, and re-applies
   the Metadata Manifest (executable bits, `600` secrets, symlinks). It refuses
   while `notes-web` runs on this machine, and refuses to overwrite existing
   production databases without `--force`. It never deletes local files.
   `--env path/to/backup.env` loads the bucket and credentials from a file
   (`--profile` takes precedence over its key).

4. Install and start:

   ```bash
   cd ~/notes && (cd web && mise install)
   make install     # backup.env came back with the restore, so no provisioning
   make update
   curl -s http://localhost:3002/up
   ```

5. If the hostname changed, the timer now runs with the old machine's key, which
   still works. Run `deploy/install-backup.sh` (with provisioning, and
   `--admin-profile <name>` if needed) to give this machine its own key, then
   delete the old one in IAM.

Alternatively, restore into a staging directory and `rsync -a` it into place.
The restored directory is a normal git checkout, including any work that was
uncommitted at backup time.

### Recovering an older version of a file

The script restores only the latest state. For point-in-time recovery of
individual files (within the 30-day window):

```bash
aws s3api list-object-versions --bucket <bucket> \
  --prefix notes/tree/web/storage/production.sqlite3 \
  --query 'Versions[].[VersionId,LastModified]' --output text
aws s3api get-object --bucket <bucket> \
  --key notes/tree/web/storage/production.sqlite3 \
  --version-id <VersionId> production.sqlite3.restored
```

A file deleted locally shows up as a delete marker. Its earlier versions are
still listed and can be fetched the same way.

## Migrating production from another machine (cold cutover)

Scenario: the old machine runs the classic layout (app at `/opt/notes/web`,
OAuth secrets in a systemd drop-in, AWS keys in `/etc/notes-backup.env`).
Afterwards, the old machine shuts down and this checkout runs production. The
public domain stays the same, so Google OAuth redirect URIs are untouched.

On **this machine**, complete "First-time setup" above through step 3
(`make install`) — but don't create secrets or run `make update` yet; they come
from the old machine.

1. **Stop production on the old machine** (this is the start of downtime; a
   clean stop checkpoints the SQLite WAL files so plain file copies are
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
   local files, and reads the remote side with `sudo rsync` (needs passwordless
   sudo; use `--no-sudo` if the files are readable directly). `--dry-run`
   previews the transfer.

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

5. **Set up backups** with `deploy/install-backup.sh` (see "Backups"). If you
   reuse the old machine's bucket, keep the default prefix layout: the mirror
   lives under `<prefix>/tree/`, so the old timestamped snapshots under
   `<prefix>/db/` and `<prefix>/storage/` are left alone.

6. **Migrate and start** (this checkout's code may carry newer migrations than
   the old machine's data — `db:prepare` inside `make update` handles that):

   ```bash
   cd ~/notes
   make update
   make status
   curl -s http://localhost:3002/up        # expect 200
   ```

7. **Cut over the reverse proxy**: point the Caddy machine's `reverse_proxy` at
   this machine's Tailscale hostname (see
   [caddy-snippet.md](./caddy-snippet.md)), reload Caddy, and verify
   `https://<domain>/up` and a real sign-in end to end.

8. **Decommission the old machine** once you've confirmed sign-in, note content,
   attachments, and a manual backup run
   (`sudo systemctl start notes-backup.service`) all work from here.

## Managing the service

```bash
make status                      # service + timer overview
make logs                        # journal (Puma stdout/stderr)
sudo systemctl {start|stop|restart|reload} notes-web
tail -f web/log/production.log   # Rails application log
```

## Troubleshooting

| Symptom                         | Check                                                                                                                                         |
| ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Service won't start             | `journalctl -u notes-web -e`                                                                                                                  |
| 502 from Caddy                  | Is Thruster up? `curl http://localhost:3002/up`; tailnet reachable from the Caddy box?                                                        |
| Blocked host error              | `APP_HOST` in `web/.env` must equal the public domain                                                                                         |
| Redirect loop / http URLs       | Caddy must forward `X-Forwarded-Proto` (default `reverse_proxy` does)                                                                         |
| Assets not loading              | `make update` (re-runs `assets:precompile`)                                                                                                   |
| Master key errors               | `web/config/master.key` present and `chmod 600`?                                                                                              |
| Write errors (DB/uploads)       | `ReadWritePaths` in the unit; re-run `make install-web` if the repo moved                                                                     |
| Stale Ruby after upgrade        | Re-run `make install-web` (unit bakes in the mise Ruby path)                                                                                  |
| Backup failures                 | `journalctl -u notes-backup -e`; `deploy/backup.env` present and valid? Re-run `deploy/install-backup.sh --no-provision` to re-verify the key |
| Restored scripts not executable | The manifest wasn't applied; re-run `restore-s3.sh --force`                                                                                   |
