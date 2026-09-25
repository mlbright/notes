#!/usr/bin/env bash
#
# Restore the latest Backup Mirror from S3 into a directory, then re-apply
# the Metadata Manifest (file modes and symlinks). Afterwards, run
# `make install && make update` in the restored directory.
#
# Usage:
#   S3_BUCKET=<bucket> [S3_PREFIX=notes] deploy/restore-s3.sh [--force] [--profile NAME] [--env FILE] TARGET_DIR
#
# Needs AWS credentials with read access to the bucket: your own session
# (`aws login`, or the AWS CLI profile named by `--profile NAME`) or the
# backup key from a saved copy of deploy/backup.env (`--env FILE` sources it;
# `--profile` takes precedence over the file's key). On a fresh machine this
# script is not on disk yet; fetch it from the mirror itself:
#
#   aws [--profile NAME] s3 cp s3://<bucket>/notes/tree/deploy/restore-s3.sh . && chmod +x restore-s3.sh
#
# Guards: refuses while notes-web is running on this machine, and refuses to
# overwrite existing production databases in TARGET_DIR without --force.
# Never deletes files in TARGET_DIR.
#
# Restores the latest state only. For point-in-time recovery of individual
# files, see "Restore from S3" in deploy/DEPLOYMENT.md.

set -Eeuo pipefail

usage() {
  sed -n '8,9p' "$0" | sed 's/^# *//' >&2
  exit 2
}

force=0
env_file=
profile=
target=
while (($#)); do
  case $1 in
    --force) force=1 ;;
    --env)
      env_file=${2:?--env needs a file}
      shift
      ;;
    --profile)
      profile=${2:?--profile needs a profile name}
      shift
      ;;
    -h | --help) usage ;;
    -*)
      echo "unknown option: $1" >&2
      usage
      ;;
    *)
      [[ -z ${target} ]] || usage
      target=$1
      ;;
  esac
  shift
done
[[ -n ${target} ]] || usage

if [[ -n ${env_file} ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${env_file}"
  set +a
fi

: "${S3_BUCKET:?S3_BUCKET must be set}"
: "${S3_PREFIX:=notes}"
SRC="s3://${S3_BUCKET}/${S3_PREFIX}"

s3() {
  aws ${profile:+--profile "${profile}"} s3 "$@"
}

if systemctl is-active --quiet notes-web.service 2>/dev/null; then
  echo "error: notes-web.service is running here; stop it first" >&2
  exit 1
fi

mkdir -p "${target}"
target=$(cd "${target}" && pwd)

if [[ ${force} != 1 ]] && compgen -G "${target}/web/storage/production*.sqlite3" >/dev/null; then
  echo "error: ${target} already has production databases; use --force to overwrite" >&2
  exit 1
fi

manifest=$(mktemp)
trap 'rm -f "${manifest}"' EXIT

echo "Restoring ${SRC}/ into ${target}"
s3 cp "${SRC}/manifest.tsv" "${manifest}" --only-show-errors
echo "  $(head -n 1 "${manifest}" | sed 's/^# //')"

s3 sync "${SRC}/tree/" "${target}/" --only-show-errors
echo "  Downloaded files"

# Stale SQLite sidecars would be replayed into the restored snapshots.
rm -f "${target}"/web/storage/production*.sqlite3-wal \
  "${target}"/web/storage/production*.sqlite3-shm

# Files and symlinks first, then directories deepest-first, so a restrictive
# directory mode never blocks the entries beneath it.
cd "${target}"
while IFS=$'\t' read -r type mode path link; do
  case ${type} in
    f)
      if [[ -f ${path} ]]; then
        chmod "${mode}" "${path}"
      fi
      ;;
    l)
      mkdir -p "$(dirname "${path}")"
      rm -f "${path}"
      ln -s "${link}" "${path}"
      ;;
  esac
done < <(grep -v '^#' "${manifest}")

grep -v '^#' "${manifest}" | awk -F'\t' '$1 == "d"' | sort -t$'\t' -k3,3r |
  while IFS=$'\t' read -r _ mode path _; do
    mkdir -p "${path}"
    chmod "${mode}" "${path}"
  done
echo "  Applied Metadata Manifest"

cat <<MSG

Restore complete. Next:
  cd ${target}
  make install     # systemd units (backup timer uses the restored deploy/backup.env)
  make update      # gems, migrations, assets, start notes-web
MSG
