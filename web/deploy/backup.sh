#!/usr/bin/env bash
#
# backup.sh — Back up everything needed to recreate the Notes app
#              (given that source code is separately available).
#
# What this backs up:
#   1. SQLite databases (safe online backup via sqlite3 .backup)
#   2. Active Storage attachment files (uploaded images, files, videos)
#   3. config/master.key (decrypts credentials.yml.enc from source)
#   4. .env file (runtime secrets like RAILS_MASTER_KEY)
#   5. Systemd OAuth override (Google OAuth2 credentials)
#
# Usage:
#   sudo bash deploy/backup.sh                  # uses defaults
#   sudo bash deploy/backup.sh /mnt/backups 14  # custom destination & retention
#
# Recommended cron (daily at 03:00):
#   0 3 * * * /opt/notes/web/deploy/backup.sh >> /var/log/notes-backup.log 2>&1
#
# Restore:
#   See the restore instructions printed by: deploy/backup.sh --help
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
APP_DIR="${NOTES_APP_DIR:-/opt/notes/web}"
BACKUP_DIR="${1:-/opt/notes/backups}"
RETAIN_DAYS="${2:-7}"                       # delete backups older than this
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_NAME="notes-backup-${TIMESTAMP}"
WORK_DIR="$(mktemp -d)"
SNAPSHOT_DIR="${WORK_DIR}/${BACKUP_NAME}"

# SQLite databases to back up (only the primary one is essential;
# queue/cache/cable are ephemeral but included for completeness).
DATABASES=(
  production.sqlite3
  production_queue.sqlite3
  production_cache.sqlite3
  production_cable.sqlite3
)

# Systemd OAuth override location
OAUTH_OVERRIDE="/etc/systemd/system/notes-web.service.d/oauth.conf"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
red()    { printf '\033[0;31m%s\033[0m\n' "$*"; }

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage: deploy/backup.sh [BACKUP_DIR] [RETAIN_DAYS]

  BACKUP_DIR   Where to store backup archives (default: /opt/notes/backups)
  RETAIN_DAYS  Delete backups older than this many days (default: 7)

Environment variables:
  NOTES_APP_DIR  Application root (default: /opt/notes/web)

Restore procedure:
  1. Extract the backup archive:
       tar xzf notes-backup-YYYYMMDD-HHMMSS.tar.gz

  2. Deploy the source code to ${APP_DIR} (git clone, rsync, etc.)

  3. Stop the service:
       sudo systemctl stop notes-web

  4. Restore the databases:
       cp notes-backup-*/databases/*.sqlite3 ${APP_DIR}/storage/

  5. Restore Active Storage attachments:
       cp -r notes-backup-*/active-storage/* ${APP_DIR}/storage/

  6. Restore the master key:
       cp notes-backup-*/secrets/master.key ${APP_DIR}/config/master.key
       chmod 600 ${APP_DIR}/config/master.key

  7. Restore .env (if present in backup):
       cp notes-backup-*/secrets/env ${APP_DIR}/.env
       chmod 600 ${APP_DIR}/.env

  8. Restore OAuth override (if present in backup):
       sudo mkdir -p /etc/systemd/system/notes-web.service.d
       sudo cp notes-backup-*/secrets/oauth.conf \
         /etc/systemd/system/notes-web.service.d/oauth.conf
       sudo chmod 600 /etc/systemd/system/notes-web.service.d/oauth.conf

  9. Fix ownership and start:
       sudo chown -R notes:notes ${APP_DIR}/storage ${APP_DIR}/config/master.key
       sudo systemctl daemon-reload
       sudo systemctl start notes-web
EOF
  exit 0
}

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && usage

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
if [[ ! -d "$APP_DIR" ]]; then
  red "ERROR: Application directory not found: ${APP_DIR}"
  red "Set NOTES_APP_DIR or pass the correct path."
  exit 1
fi

if ! command -v sqlite3 &>/dev/null; then
  red "ERROR: sqlite3 is required but not found in PATH."
  exit 1
fi

# ---------------------------------------------------------------------------
# Create snapshot directory structure
# ---------------------------------------------------------------------------
mkdir -p "${SNAPSHOT_DIR}/databases"
mkdir -p "${SNAPSHOT_DIR}/active-storage"
mkdir -p "${SNAPSHOT_DIR}/secrets"

# ---------------------------------------------------------------------------
# 1. Back up SQLite databases (online-safe via sqlite3 .backup)
# ---------------------------------------------------------------------------
green "[$(date +%H:%M:%S)] Backing up databases..."

for db in "${DATABASES[@]}"; do
  db_path="${APP_DIR}/storage/${db}"
  if [[ -f "$db_path" ]]; then
    sqlite3 "$db_path" ".backup '${SNAPSHOT_DIR}/databases/${db}'"
    green "  ✓ ${db} ($(du -h "${SNAPSHOT_DIR}/databases/${db}" | cut -f1))"
  else
    yellow "  ⚠ ${db} not found, skipping"
  fi
done

# ---------------------------------------------------------------------------
# 2. Back up Active Storage attachment files
# ---------------------------------------------------------------------------
green "[$(date +%H:%M:%S)] Backing up Active Storage attachments..."

# Active Storage uses two-character directory names (e.g., b5/, dn/, ee/)
attachment_count=0
for dir in "${APP_DIR}/storage"/*/; do
  dirname="$(basename "$dir")"
  # Skip non-Active-Storage entries (sqlite files are already handled)
  if [[ ${#dirname} -eq 2 ]]; then
    cp -r "$dir" "${SNAPSHOT_DIR}/active-storage/"
    attachment_count=$((attachment_count + 1))
  fi
done

if [[ $attachment_count -gt 0 ]]; then
  as_size="$(du -sh "${SNAPSHOT_DIR}/active-storage" | cut -f1)"
  green "  ✓ ${attachment_count} blob directories (${as_size})"
else
  yellow "  ⚠ No Active Storage attachments found"
fi

# ---------------------------------------------------------------------------
# 3. Back up secrets
# ---------------------------------------------------------------------------
green "[$(date +%H:%M:%S)] Backing up secrets..."

# master.key — required to decrypt credentials.yml.enc (which is in source)
if [[ -f "${APP_DIR}/config/master.key" ]]; then
  cp "${APP_DIR}/config/master.key" "${SNAPSHOT_DIR}/secrets/master.key"
  chmod 600 "${SNAPSHOT_DIR}/secrets/master.key"
  green "  ✓ master.key"
else
  yellow "  ⚠ master.key not found (RAILS_MASTER_KEY may be in .env instead)"
fi

# .env — may contain RAILS_MASTER_KEY, OAuth creds, or other overrides
if [[ -f "${APP_DIR}/.env" ]]; then
  cp "${APP_DIR}/.env" "${SNAPSHOT_DIR}/secrets/env"
  chmod 600 "${SNAPSHOT_DIR}/secrets/env"
  green "  ✓ .env"
else
  yellow "  ⚠ .env not found (not required if master.key is present)"
fi

# Systemd OAuth override
if [[ -f "$OAUTH_OVERRIDE" ]]; then
  cp "$OAUTH_OVERRIDE" "${SNAPSHOT_DIR}/secrets/oauth.conf"
  chmod 600 "${SNAPSHOT_DIR}/secrets/oauth.conf"
  green "  ✓ oauth.conf (systemd override)"
else
  yellow "  ⚠ OAuth systemd override not found at ${OAUTH_OVERRIDE}"
fi

# ---------------------------------------------------------------------------
# 4. Write a manifest for verification
# ---------------------------------------------------------------------------
cat > "${SNAPSHOT_DIR}/MANIFEST.txt" <<EOF
Notes Backup — ${TIMESTAMP}
==============================
Host:       $(hostname)
Date:       $(date -Iseconds)
App dir:    ${APP_DIR}
Rails env:  production

Files:
$(cd "$SNAPSHOT_DIR" && find . -type f | sort | while read -r f; do
    printf "  %-60s %s\n" "$f" "$(du -h "$f" | cut -f1)"
  done)

To restore, see: deploy/backup.sh --help
EOF

green "[$(date +%H:%M:%S)] Wrote MANIFEST.txt"

# ---------------------------------------------------------------------------
# 5. Create compressed archive
# ---------------------------------------------------------------------------
mkdir -p "$BACKUP_DIR"
archive="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"

green "[$(date +%H:%M:%S)] Creating archive..."
tar czf "$archive" -C "$WORK_DIR" "$BACKUP_NAME"
chmod 600 "$archive"

archive_size="$(du -h "$archive" | cut -f1)"
green "[$(date +%H:%M:%S)] ✓ Archive created: ${archive} (${archive_size})"

# ---------------------------------------------------------------------------
# 6. Prune old backups
# ---------------------------------------------------------------------------
if [[ "$RETAIN_DAYS" -gt 0 ]]; then
  pruned=$(find "$BACKUP_DIR" -name 'notes-backup-*.tar.gz' -mtime +"$RETAIN_DAYS" -print -delete | wc -l)
  if [[ "$pruned" -gt 0 ]]; then
    green "[$(date +%H:%M:%S)] Pruned ${pruned} backup(s) older than ${RETAIN_DAYS} days"
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
green ""
green "================================================================"
green "  Backup complete!"
green ""
green "  Archive:    ${archive}"
green "  Size:       ${archive_size}"
green "  Databases:  ${#DATABASES[@]} checked"
green "  Blobs:      ${attachment_count} directories"
green "  Retention:  ${RETAIN_DAYS} days"
green "================================================================"
