#!/usr/bin/env bash
#
# Sync the repository directory, minus Ephemeral Files, to the Backup Mirror
# in S3 (see CONTEXT.md and docs/adr/0002).
#
# Layout under s3://$S3_BUCKET/$S3_PREFIX/:
#   tree/          mirror of the repo root (incremental, with --delete)
#   manifest.tsv   Metadata Manifest: modes and symlinks S3 cannot represent
#
# History comes from S3 bucket versioning, not from repeated full copies.
#
# Configuration comes from deploy/backup.env (loaded by the systemd unit via
# EnvironmentFile, or sourced here when run by hand):
#   S3_BUCKET        target bucket (required)
#   S3_PREFIX        key prefix inside the bucket (default: notes)
#   AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_DEFAULT_REGION
#   NTFY_TOPIC       optional ntfy topic; notified on failure
#   NTFY_URL         ntfy server (default: https://ntfy.sh)
#   NTFY_ON_SUCCESS  set to 1 to also notify on success

set -Eeuo pipefail

APP_DIR=${APP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}

if [[ -z ${S3_BUCKET:-} && -f "${APP_DIR}/deploy/backup.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${APP_DIR}/deploy/backup.env"
  set +a
fi

: "${S3_BUCKET:?S3_BUCKET must be set (see deploy/backup.env.example)}"
: "${S3_PREFIX:=notes}"
: "${NTFY_URL:=https://ntfy.sh}"

DEST="s3://${S3_BUCKET}/${S3_PREFIX}"
EXCLUDE_FILE="${APP_DIR}/deploy/backup-exclude"
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/notes-backup-XXXXXX")

cleanup() {
  rm -rf "${STAGE}"
}
trap cleanup EXIT

# Usage: notify_ntfy <title> <message> <tags>
notify_ntfy() {
  [[ -n ${NTFY_TOPIC:-} ]] || return 0
  curl -sf -o /dev/null -H "Title: $1" -H "Tags: $3" -d "$2" \
    "${NTFY_URL}/${NTFY_TOPIC}" || true
}

on_failure() {
  notify_ntfy "Notes backup failed" \
    "Backup to ${DEST}/ failed at $(date -Iseconds) on $(hostname -s)" \
    "rotating_light,backup"
}
trap on_failure ERR

log() {
  echo "[$(date -Iseconds)] $*"
}

# Translate deploy/backup-exclude into `aws s3 sync` filters (applied in
# order, later ones win) and `find` prune expressions for the manifest.
aws_filters=()
find_prunes=()
reincludes=()
while IFS= read -r line || [[ -n ${line} ]]; do
  line=${line#"${line%%[![:space:]]*}"}
  line=${line%"${line##*[![:space:]]}"}
  [[ -z ${line} || ${line} == \#* ]] && continue
  if [[ ${line} == !* ]]; then
    aws_filters+=(--include "${line#!}")
    reincludes+=("${line#!}")
  elif [[ ${line} == */* ]]; then
    aws_filters+=(--exclude "${line}")
    find_prunes+=(-path "./${line}" -o)
  else
    aws_filters+=(--exclude "${line}" --exclude "*/${line}")
    find_prunes+=(-name "${line}" -o)
  fi
done <"${EXCLUDE_FILE}"

# Live databases are replaced by Database Snapshots (uploaded separately).
# Excluded paths are also exempt from --delete, so the snapshots survive.
aws_filters+=(--exclude "web/storage/production*.sqlite3")

log "Starting backup of ${APP_DIR} to ${DEST}/"

# --- Database Snapshots ---
mkdir -p "${STAGE}/db"
snapshots=()
for src in "${APP_DIR}"/web/storage/production*.sqlite3; do
  [[ -f ${src} ]] || continue
  name=$(basename "${src}")
  sqlite3 "${src}" ".backup '${STAGE}/db/${name}'"
  check=$(sqlite3 "${STAGE}/db/${name}" "PRAGMA quick_check;")
  if [[ ${check} != ok ]]; then
    echo "Snapshot of ${name} failed quick_check: ${check}" >&2
    false
  fi
  snapshots+=("${name}")
done
log "  Snapshotted ${#snapshots[@]} database(s)"

# --- Metadata Manifest ---
# One line per path: type (f/d/l) TAB octal mode TAB path TAB symlink target.
manifest="${STAGE}/manifest.tsv"
{
  echo "# Metadata Manifest for ${APP_DIR} on $(hostname -s) at $(date -Iseconds)"
  (
    cd "${APP_DIR}"
    find . -mindepth 1 \( "${find_prunes[@]}" -false \) -prune \
      -o -printf '%y\t%m\t%P\t%l\n'
    for path in "${reincludes[@]}"; do
      if [[ -e ${path} || -L ${path} ]]; then
        find "${path}" -maxdepth 0 -printf '%y\t%m\t%p\t%l\n'
      fi
    done
  )
} >"${manifest}"

# --- Mirror ---
aws s3 sync "${APP_DIR}/" "${DEST}/tree/" \
  --delete --no-follow-symlinks --only-show-errors "${aws_filters[@]}"
log "  Synced repository tree"

for name in "${snapshots[@]}"; do
  aws s3 cp "${STAGE}/db/${name}" "${DEST}/tree/web/storage/${name}" \
    --only-show-errors
done
log "  Uploaded database snapshots"

# Uploaded last, so the manifest's timestamp marks the last complete run.
aws s3 cp "${manifest}" "${DEST}/manifest.tsv" --only-show-errors
log "Backup complete"

if [[ ${NTFY_ON_SUCCESS:-} == 1 ]]; then
  notify_ntfy "Notes backup succeeded" \
    "Backup to ${DEST}/ completed at $(date -Iseconds)" \
    "white_check_mark,backup"
fi
