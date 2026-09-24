# 2. Backup is a versioned S3 mirror of the whole checkout

Date: 2026-09-24

## Status

Accepted

## Context

The original backup uploaded `sqlite3 .backup` snapshots and Active Storage
blobs to a new timestamped S3 prefix every 6 hours. Each run was a full copy,
and it left out everything else in the Production State (master key, `.env`,
backup credentials) as well as the code. So a restore still needed a git clone
plus secrets gathered from elsewhere.

ADR 0001 made the checkout the whole deployment: copy the directory, run
`make install`, start. The backup should give you exactly that directory back,
so that restoring works like a machine migration.

## Decision

The backup is an incremental `aws s3 sync --delete` of the repository directory,
minus an explicit list of Ephemeral Files, to a single mirror prefix, run
hourly. It includes `.git`, uncommitted work, and secrets. Live SQLite databases
are never synced. Consistent snapshots are uploaded to the same keys instead, so
a restore needs no translation. File modes and symlinks, which S3 cannot
represent, are stored in a Metadata Manifest that the restore script re-applies.

History comes from S3 bucket versioning with a lifecycle rule that expires
noncurrent versions after 30 days, not from repeated full copies. The backup IAM
user can read versions but not delete them.

Secrets are protected by the bucket, not by client-side encryption: public
access is blocked, SSE-S3 is on, and the IAM policy is scoped to the prefix. The
account, bucket, and key are never in the repo. They live in the gitignored
`deploy/backup.env`, which the installer writes after provisioning the bucket
and a per-host IAM user.

## Consequences

- Restore: fetch the restore script from the mirror, run it, then
  `make install && make update`. `backup.env` comes back with everything else,
  so the restored machine resumes backups with no extra setup.
- Each run uploads only changed files, plus about 30 MB of database snapshots,
  which always differ.
- Anyone who can read the bucket gets the master key, OAuth secret, and backup
  key. The bucket's access controls are the only protection. We accepted this to
  avoid a separate encryption key, since losing that key would make the backup
  unrecoverable.
- The mirror holds only the latest state. Point-in-time recovery works per file
  through object versions, within the 30-day window, and is a manual procedure.
  Whole-tree point-in-time restore is not supported.
- A bad write is recoverable only for 30 days after the next sync overwrites it.
- The old timestamped snapshots are not migrated. The mirror uses
  `<prefix>/tree/` so they are left untouched.
