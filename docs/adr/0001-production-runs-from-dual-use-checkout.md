# 1. Production runs from the dual-use checkout in the operator's home directory

Date: 2026-07-04

## Status

Accepted

## Context

The original deployment model rsynced the repo to `/opt/notes/web`, ran the
app as a dedicated `notes` system user, and scattered production state across
the filesystem: databases and blobs in `/opt/notes/web/storage`, OAuth secrets
in a systemd drop-in, AWS backup credentials in `/etc/notes-backup.env`. The
dedicated user could not reach the mise-managed Ruby in `/home/ubuntu`, which
forced ~40 lines of setfacl workarounds, and two-owner permission conflicts
were a documented failure mode.

The operator wants machine migration to be trivial: copy one directory,
run one make target, start the service. This is a single-tenant personal
application on a personal VPS, with TLS terminated by Caddy on a separate
machine reached over Tailscale.

## Decision

The git checkout at the operator's home directory (e.g. `/home/ubuntu/notes`)
*is* the production deployment. All production state — SQLite databases,
Active Storage blobs, master key, `.env`, backup credentials — lives inside
it. The service runs as the operator's own user (`ubuntu`). The only artifact
outside the directory is the systemd unit (plus timer), generated from
in-repo templates by `make install` with no secrets in it. The same checkout
is also the development workspace; `make update` performs no git operations.
Caddy is not installed on this machine; the app exposes Thruster on port 3002
to the tailnet, Puma binds loopback only, and Rails runs with
`assume_ssl`/`force_ssl` on.

## Consequences

- Machine migration is: stop old service, copy the directory (cold cutover),
  `make install`, `make update`, start. No state hunt through `/etc`.
- The setfacl/ownership machinery is deleted; git, the app, and backups all
  operate as one user.
- Isolation is deliberately sacrificed: a compromised app process has the
  operator's full home-directory access. Partially mitigated with systemd
  sandboxing (`ProtectSystem=strict`, explicit `ReadWritePaths`,
  `NoNewPrivileges`).
- Production runs whatever the working tree contains; a half-finished edit
  becomes production on the next restart. The operator accepts this and
  enforces tree discipline manually.
- Development tooling (tests, consoles) runs adjacent to live data;
  Rails' production-environment checks are the guardrail against
  destructive-task typos.
