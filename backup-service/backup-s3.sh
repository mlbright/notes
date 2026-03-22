#!/usr/bin/env bash
#
# Back up the Notes Rails app SQLite databases and Active Storage files to S3.
#
# Required environment variables (set in the systemd service or an EnvironmentFile):
#   S3_BUCKET        – target S3 bucket name
#   S3_PREFIX        – key prefix inside the bucket  (default: "notes")
#   APP_ROOT         – path to the Rails app root    (default: "/opt/notes/web")
#   AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_DEFAULT_REGION
#                    – standard AWS CLI credentials
#
# Optional:
#   NTFY_TOPIC       – ntfy.sh topic to notify on completion (success or failure)
#   NTFY_URL         – ntfy server URL (default: "https://ntfy.sh")
#
# The script uses `sqlite3 .backup` to obtain a consistent snapshot of each
# database before uploading, so the running application is never blocked.

set -euo pipefail

: "${S3_BUCKET:?S3_BUCKET must be set}"
: "${APP_ROOT:=/opt/notes/web}"
: "${S3_PREFIX:=notes}"
: "${NTFY_URL:=https://ntfy.sh}"

TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
WORK_DIR=$(mktemp -d "/tmp/notes-backup-XXXXXX")

cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

# Send a notification to a ntfy topic. Called on both success and failure.
# Usage: notify_ntfy <title> <message> <tags>
notify_ntfy() {
  if [[ -z "${NTFY_TOPIC:-}" ]]; then
    return
  fi
  local title="$1" message="$2" tags="$3"
  curl -sf -o /dev/null \
    -H "Title: ${title}" \
    -H "Tags: ${tags}" \
    -d "${message}" \
    "${NTFY_URL}/${NTFY_TOPIC}" || true
}

on_failure() {
  notify_ntfy "Notes backup failed" "Backup to s3://${S3_BUCKET}/${S3_PREFIX}/ failed at $(date -Iseconds)" "rotating_light,backup"
}
trap 'on_failure; cleanup' ERR

echo "[$(date -Iseconds)] Starting backup to s3://${S3_BUCKET}/${S3_PREFIX}/"

# --- SQLite databases ---
DATABASES=(
  "production.sqlite3"
  "production_cache.sqlite3"
  "production_queue.sqlite3"
  "production_cable.sqlite3"
)

for db in "${DATABASES[@]}"; do
  src="${APP_ROOT}/storage/${db}"
  if [[ -f "${src}" ]]; then
    dest="${WORK_DIR}/${db}"
    sqlite3 "${src}" ".backup ${dest}"
    aws s3 cp "${dest}" "s3://${S3_BUCKET}/${S3_PREFIX}/db/${TIMESTAMP}/${db}" --quiet
    echo "  Uploaded ${db}"
  else
    echo "  Skipped ${db} (not found)"
  fi
done

# --- Active Storage files ---
STORAGE_DIR="${APP_ROOT}/storage"
if [[ -d "${STORAGE_DIR}" ]]; then
  aws s3 sync "${STORAGE_DIR}" "s3://${S3_BUCKET}/${S3_PREFIX}/storage/${TIMESTAMP}/" \
    --exclude "*.sqlite3" \
    --exclude "*.sqlite3-wal" \
    --exclude "*.sqlite3-shm" \
    --quiet
  echo "  Uploaded Active Storage files"
fi

echo "[$(date -Iseconds)] Backup complete"

notify_ntfy "Notes backup succeeded" "Backup to s3://${S3_BUCKET}/${S3_PREFIX}/ completed at $(date -Iseconds)" "white_check_mark,backup"
