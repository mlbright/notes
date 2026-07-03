# Context — Ubiquitous Language

Glossary of terms used when discussing the Notes system and its operation.
Keep this free of implementation detail; it defines *words*, not designs.

## Deployment & operations

- **Production State** — Everything that must survive a machine move for
  production to continue: the four SQLite databases, Active Storage blobs,
  the Rails master key, the application environment file, and the backup
  credentials. By decision, all Production State lives inside the repository
  directory; the only artifact outside it is the installed systemd unit,
  which contains no state.

- **Dual-Use Checkout** — The single working tree that is simultaneously the
  development workspace and the running production deployment. There is no
  separate "deployed copy": production runs whatever the working tree
  contains at service start.

- **Generated Unit** — A systemd unit file installed into `/etc/systemd/system`
  by `make install`, produced from a template in the repo with machine-specific
  values (paths, Ruby location) baked in. Generated Units are artifacts, never
  edited in place; the template is the source of truth.

- **Cold Cutover** — The migration procedure for moving production between
  machines: stop the service on the old machine, copy Production State,
  migrate, start here. Consistency comes from the stop, not from online
  backup tooling.

- **Update** — Making the running service reflect the current working tree:
  install gems, migrate databases, precompile assets, restart. Explicitly
  excludes git operations; what the tree contains is the operator's business.
