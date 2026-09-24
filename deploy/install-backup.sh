#!/usr/bin/env bash
#
# Install the S3 backup (see "Backups" in deploy/DEPLOYMENT.md).
#
# Usage: deploy/install-backup.sh [--no-provision] [--admin-profile NAME]
#
# Provisioning (the default) uses admin AWS credentials (the default
# credential chain, e.g. an `aws login` session, or --admin-profile) to:
#   - create the bucket if missing, block public access, enable versioning,
#     and add a lifecycle rule expiring superseded versions under the prefix
#     after NONCURRENT_DAYS (default 30)
#   - create or reuse the IAM user notes-backup-<hostname>, whose inline
#     policy (backup-iam-policy.json.tmpl) covers only this bucket and prefix
#   - create an access key for it (asking first if it already has one) and
#     write deploy/backup.env
#
# --no-provision skips all of that and uses the existing deploy/backup.env,
# e.g. after a restore, where backup.env comes back with everything else.
#
# Either way it then verifies the backup credentials, installs and enables
# notes-backup.service + notes-backup.timer, and (after provisioning) runs a
# first backup. Safe to re-run.
#
# Bucket, prefix, and region are prompted for, defaulting to S3_BUCKET,
# S3_PREFIX, and AWS_DEFAULT_REGION from the environment or backup.env.

set -Eeuo pipefail

APP_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WEB_DIR="${APP_DIR}/web"
DEPLOY_DIR="${APP_DIR}/deploy"
ENV_FILE="${DEPLOY_DIR}/backup.env"
SYSTEMD_DIR=/etc/systemd/system
SERVICE_USER=$(id -un)
IAM_USER="notes-backup-$(hostname -s)"
NONCURRENT_DAYS=${NONCURRENT_DAYS:-30}

provision=1
admin_profile=
while (($#)); do
  case $1 in
    --no-provision) provision=0 ;;
    --admin-profile)
      admin_profile=${2:?--admin-profile needs a profile name}
      shift
      ;;
    -h | --help)
      sed -n '5p' "$0" | sed 's/^# *//'
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      exit 2
      ;;
  esac
  shift
done

log() {
  echo "==> $*"
}

die() {
  echo "error: $*" >&2
  exit 1
}

# Value of KEY in backup.env, or empty. Never sourced: the backup key must
# not leak into the admin credential chain.
env_get() {
  [[ -f ${ENV_FILE} ]] || return 0
  sed -n "s/^$1=//p" "${ENV_FILE}" | tail -n 1
}

# Usage: ask <label> <default>
ask() {
  local answer=
  if [[ -t 0 ]]; then
    read -rp "$1 [$2]: " answer
  fi
  printf '%s' "${answer:-$2}"
}

confirm() {
  local answer=
  [[ -t 0 ]] || return 1
  read -rp "$1 [y/N]: " answer
  [[ ${answer} == [yY]* ]]
}

admin() {
  aws ${admin_profile:+--profile "${admin_profile}"} "$@"
}

backup_aws() {
  env -u AWS_PROFILE -u AWS_SESSION_TOKEN \
    AWS_ACCESS_KEY_ID="${key_id}" \
    AWS_SECRET_ACCESS_KEY="${secret}" \
    AWS_DEFAULT_REGION="${region}" \
    aws "$@"
}

((EUID != 0)) || die "run as the user that owns the service, not root"
for cmd in aws sqlite3 curl; do
  command -v "${cmd}" >/dev/null || die "${cmd} not found (AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)"
done

if ((provision)); then
  bucket=$(ask "S3 bucket" "${S3_BUCKET:-$(env_get S3_BUCKET)}")
  prefix=$(ask "Key prefix" "${S3_PREFIX:-$(env_get S3_PREFIX)}")
  prefix=${prefix:-notes}
  prefix=${prefix%/}
  region_default=${AWS_DEFAULT_REGION:-$(env_get AWS_DEFAULT_REGION)}
  region_default=${region_default:-$(admin configure get region 2>/dev/null || true)}
  region=$(ask "AWS region" "${region_default:-us-east-1}")
  [[ -n ${bucket} ]] || die "a bucket name is required"

  account=$(admin sts get-caller-identity --query Account --output text) ||
    die "no admin AWS credentials (try: aws login, or --admin-profile NAME)"
  log "Provisioning s3://${bucket}/${prefix}/ in account ${account} (${region})"

  # --- Bucket ---
  if admin s3api head-bucket --bucket "${bucket}" 2>/dev/null; then
    log "Bucket exists"
  elif [[ ${region} == us-east-1 ]]; then
    admin s3api create-bucket --bucket "${bucket}" --region "${region}" >/dev/null
    log "Created bucket"
  else
    admin s3api create-bucket --bucket "${bucket}" --region "${region}" \
      --create-bucket-configuration "LocationConstraint=${region}" >/dev/null
    log "Created bucket"
  fi

  admin s3api put-public-access-block --bucket "${bucket}" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  admin s3api put-bucket-versioning --bucket "${bucket}" \
    --versioning-configuration Status=Enabled
  encryption=$(admin s3api get-bucket-encryption --bucket "${bucket}" \
    --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
    --output text)
  log "Public access blocked, versioning enabled, default encryption ${encryption}"

  # --- Lifecycle: expire superseded versions of the Backup Mirror ---
  rule_id="notes-backup-${prefix//\//-}"
  rule=$(
    cat <<JSON
{"ID": "${rule_id}", "Status": "Enabled", "Filter": {"Prefix": "${prefix}/"},
 "NoncurrentVersionExpiration": {"NoncurrentDays": ${NONCURRENT_DAYS}},
 "Expiration": {"ExpiredObjectDeleteMarker": true},
 "AbortIncompleteMultipartUpload": {"DaysAfterInitiation": 7}}
JSON
  )
  other_rules=$(admin s3api get-bucket-lifecycle-configuration --bucket "${bucket}" \
    --query 'Rules[].ID' --output text 2>/dev/null | tr '\t' '\n' | grep -vx -e "${rule_id}" -e None || true)
  if [[ -n ${other_rules} ]]; then
    echo "WARNING: bucket has other lifecycle rules (${other_rules//$'\n'/, }); not overwriting them." >&2
    echo "Add this rule yourself:" >&2
    echo "${rule}" >&2
  else
    admin s3api put-bucket-lifecycle-configuration --bucket "${bucket}" \
      --lifecycle-configuration "{\"Rules\": [${rule}]}"
    log "Lifecycle: superseded versions expire after ${NONCURRENT_DAYS} days"
  fi

  # --- IAM user scoped to the prefix ---
  if admin iam get-user --user-name "${IAM_USER}" >/dev/null 2>&1; then
    log "IAM user ${IAM_USER} exists"
  else
    admin iam create-user --user-name "${IAM_USER}" \
      --tags Key=purpose,Value=notes-backup >/dev/null
    log "Created IAM user ${IAM_USER}"
  fi
  policy=$(sed -e "s|@S3_BUCKET@|${bucket}|g" -e "s|@S3_PREFIX@|${prefix}|g" \
    "${DEPLOY_DIR}/backup-iam-policy.json.tmpl")
  admin iam put-user-policy --user-name "${IAM_USER}" \
    --policy-name notes-backup --policy-document "${policy}"
  log "Applied policy: s3://${bucket}/${prefix}/* only"

  key_id=$(env_get AWS_ACCESS_KEY_ID)
  secret=$(env_get AWS_SECRET_ACCESS_KEY)
  keys=$(admin iam list-access-keys --user-name "${IAM_USER}" \
    --query 'AccessKeyMetadata[].AccessKeyId' --output text)
  if [[ -n ${key_id} && -n ${secret} && " ${keys} " == *" ${key_id} "* ]]; then
    log "Reusing access key ${key_id} from backup.env"
  else
    if [[ -n ${keys} && ${keys} != None ]]; then
      confirm "${IAM_USER} already has access key(s) ${keys}. Create another?" ||
        die "aborted; delete a stale key with: aws iam delete-access-key --user-name ${IAM_USER} --access-key-id <id>"
    fi
    read -r key_id secret < <(admin iam create-access-key --user-name "${IAM_USER}" \
      --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text)
    log "Created access key ${key_id}"
  fi

  # --- backup.env (Production State: travels with the directory) ---
  ntfy_lines=$(grep -E '^#?NTFY_' "${ENV_FILE}" 2>/dev/null ||
    printf '#NTFY_TOPIC=my-topic\n#NTFY_URL=https://ntfy.sh\n#NTFY_ON_SUCCESS=1\n')
  tmp=$(umask 077 && mktemp "${ENV_FILE}.XXXXXX")
  cat >"${tmp}" <<ENV
# Written by deploy/install-backup.sh. Loaded by notes-backup.service.
S3_BUCKET=${bucket}
S3_PREFIX=${prefix}
AWS_ACCESS_KEY_ID=${key_id}
AWS_SECRET_ACCESS_KEY=${secret}
AWS_DEFAULT_REGION=${region}

# Optional ntfy notification on failure (and on success with NTFY_ON_SUCCESS=1).
${ntfy_lines}
ENV
  chmod 600 "${tmp}"
  mv "${tmp}" "${ENV_FILE}"
  log "Wrote ${ENV_FILE}"
else
  [[ -f ${ENV_FILE} ]] || die "${ENV_FILE} is missing; run without --no-provision"
  bucket=$(env_get S3_BUCKET)
  prefix=$(env_get S3_PREFIX)
  prefix=${prefix:-notes}
  region=$(env_get AWS_DEFAULT_REGION)
  key_id=$(env_get AWS_ACCESS_KEY_ID)
  secret=$(env_get AWS_SECRET_ACCESS_KEY)
  [[ -n ${bucket} && -n ${key_id} && -n ${secret} ]] ||
    die "${ENV_FILE} needs S3_BUCKET, AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
fi

# --- Verify the backup credentials (new IAM keys take a few seconds) ---
for attempt in {1..12}; do
  if backup_aws s3api list-objects-v2 --bucket "${bucket}" --prefix "${prefix}/" \
    --max-keys 1 >/dev/null 2>&1; then
    log "Backup credentials can reach s3://${bucket}/${prefix}/"
    break
  fi
  ((attempt < 12)) || die "backup credentials cannot list s3://${bucket}/${prefix}/"
  sleep 5
done

# --- systemd units (Generated Units: never edit the installed copies) ---
sed -e "s|@APP_DIR@|${APP_DIR}|g" \
  -e "s|@WEB_DIR@|${WEB_DIR}|g" \
  -e "s|@SERVICE_USER@|${SERVICE_USER}|g" \
  "${DEPLOY_DIR}/notes-backup.service.tmpl" |
  sudo tee "${SYSTEMD_DIR}/notes-backup.service" >/dev/null
sudo install -m 644 "${DEPLOY_DIR}/notes-backup.timer" "${SYSTEMD_DIR}/notes-backup.timer"
sudo systemctl daemon-reload
sudo systemctl enable --now notes-backup.timer
log "Installed notes-backup.service and enabled notes-backup.timer"

if ((provision)); then
  log "Running first backup (journalctl -u notes-backup -f to follow)"
  sudo systemctl start notes-backup.service ||
    die "first backup failed; see: journalctl -u notes-backup -e"
  log "First backup complete"
fi

systemctl list-timers notes-backup.timer --no-pager
