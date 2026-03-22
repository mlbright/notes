# Notes S3 Backup

Systemd service and timer that back up the Notes app SQLite databases and Active Storage files to an S3 bucket every 6 hours.

## What gets backed up

| Data | S3 key pattern |
|------|---------------|
| `production.sqlite3` | `<prefix>/db/<timestamp>/production.sqlite3` |
| `production_cache.sqlite3` | `<prefix>/db/<timestamp>/production_cache.sqlite3` |
| `production_queue.sqlite3` | `<prefix>/db/<timestamp>/production_queue.sqlite3` |
| `production_cable.sqlite3` | `<prefix>/db/<timestamp>/production_cable.sqlite3` |
| Active Storage blobs | `<prefix>/storage/<timestamp>/…` |

Each database is safely copied with `sqlite3 .backup` before upload so the running app is never blocked.

## Prerequisites

- `sqlite3` CLI
- AWS CLI v2 (`aws`)
- An S3 bucket with appropriate write permissions

## Setup

1. **Create the credentials file** at `/etc/notes-backup.env`:

   ```env
   S3_BUCKET=my-notes-backup-bucket
   S3_PREFIX=notes
   AWS_ACCESS_KEY_ID=AKIA…
   AWS_SECRET_ACCESS_KEY=…
   AWS_DEFAULT_REGION=us-east-1
   ```

   Lock it down:

   ```bash
   sudo chmod 600 /etc/notes-backup.env
   ```

2. **Copy the files into place**:

   ```bash
   sudo cp backup-service/notes-backup.service /etc/systemd/system/
   sudo cp backup-service/notes-backup.timer   /etc/systemd/system/
   ```

3. **Enable and start the timer**:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now notes-backup.timer
   ```

4. **Verify** the timer is scheduled:

   ```bash
   systemctl list-timers notes-backup.timer
   ```

## Manual run

```bash
sudo systemctl start notes-backup.service
journalctl -u notes-backup.service -e
```

## Customization

- **Frequency** – edit the `OnCalendar=` line in `notes-backup.timer` (e.g., `*-*-* 00/1:00:00` for hourly).
- **App location** – change `APP_ROOT` in the service unit if the app isn't at `/opt/notes/web`.
- **Retention** – configure an S3 lifecycle policy on the bucket to expire old backups automatically.
- **ntfy notifications** – set `NTFY_TOPIC` in `/etc/notes-backup.env` to receive a push notification after each backup (success or failure). Optionally set `NTFY_URL` to use a self-hosted ntfy server (defaults to `https://ntfy.sh`).
