# Context — Ubiquitous Language

Glossary of terms used when discussing the Notes system and its operation. Keep
this free of implementation detail; it defines _words_, not designs.

## Deployment & operations

- **Production State** — Everything that must survive a machine move for
  production to continue: the four SQLite databases, Active Storage blobs, the
  Rails master key, the application environment file, and the backup
  credentials. By decision, all Production State lives inside the repository
  directory; the only artifact outside it is the installed systemd unit, which
  contains no state.

- **Dual-Use Checkout** — The single working tree that is simultaneously the
  development workspace and the running production deployment. There is no
  separate "deployed copy": production runs whatever the working tree contains
  at service start.

- **Generated Unit** — A systemd unit file installed into `/etc/systemd/system`
  by `make install`, produced from a template in the repo with machine-specific
  values (paths, Ruby location) baked in. Generated Units are artifacts, never
  edited in place; the template is the source of truth.

- **Cold Cutover** — The migration procedure for moving production between
  machines: stop the service on the old machine, copy Production State, migrate,
  start here. Consistency comes from the stop, not from online backup tooling.

- **Update** — Making the running service reflect the current working tree:
  install gems and the embedding model, migrate databases, precompile assets,
  restart. Explicitly excludes git operations; what the tree contains is the
  operator's business.

- **Backup Mirror** — The off-site copy of the repository directory, minus
  Ephemeral Files, kept current by incremental sync. It always reflects the
  latest backup run; history comes from the store retaining superseded and
  deleted versions for a bounded window, not from repeated full copies.

- **Ephemeral File** — Anything in the repository directory that can be
  regenerated or is worthless after a restart (temp files, logs, compiled
  assets, installed dependencies, test/development databases, SQLite WAL
  sidecars). Excluded from the Backup Mirror by an explicit list, not by
  `.gitignore` — gitignored does not mean ephemeral.

- **Database Snapshot** — A consistent point-in-time copy of a live SQLite
  database, taken while the service runs. The Backup Mirror holds snapshots,
  never the live database files, placed where the live files belong so a restore
  needs no translation.

- **Metadata Manifest** — The record, stored with the Backup Mirror, of the file
  modes and symlinks that the object store cannot represent. A restore is only
  exact once the manifest has been re-applied.

## Rust port

- **Reference** — The Rails implementation of the Notes system at a pinned
  commit, treated as the authority on behaviour: where the Port and the
  Reference disagree, the Port is wrong unless the difference was chosen
  deliberately. Avoid: original, legacy app.

- **Port** — The Rust reimplementation of the Notes system. It is a candidate
  replacement for the Reference: it runs against the same Production State,
  unchanged, so either one can serve production and switching between them in
  either direction loses nothing. Avoid: clone, rewrite.

- **Parity** — The Port and the Reference producing the same outcome for the
  same request against the same starting state: the same response and the same
  resulting Production State. Each surface has its own bar for "the same" (the
  JSON API is compared exactly, web pages by their document structure).
  Avoid: equivalence, correctness.

- **Switch** — Changing which implementation, Reference or Port, serves
  production, on the same machine and against the same Production State. Either
  direction is a restart. Not a Cold Cutover, which moves production between
  machines. Avoid: cutover, migration.

- **Point of No Return** — The first Port change whose Production State the
  Reference can no longer read correctly. Until it, a Switch back to the
  Reference loses nothing; after it, going back means restoring the Database
  Snapshot taken just before it, and losing everything written since. Reached
  only deliberately, never as a side effect of an ordinary change.

## Search & retrieval

- **Search** — Finding notes by the words they contain, for a person browsing
  their notes. Results are whole notes.

- **Retrieval** — Finding the Passages most relevant to a query, by meaning as
  well as wording, so an agent can ground an answer in them. Covers every note
  the user can access, owned or shared, archived or not, except trashed notes;
  only current content, never past versions or attachments. Avoid: semantic
  search, RAG search.

- **Passage** — A contiguous excerpt of one note's current content, returned to
  an agent as a retrieval result and always attributable to that note.
  Passages have no identity of their own: they are recut whenever their note
  changes and are cited through their note and Heading Trail. Avoid: chunk,
  snippet, fragment.

- **Heading Trail** — The chain of headings that enclose a Passage within its
  note, outermost first (e.g. "Backups › S3 bucket"). Empty for a Passage that
  sits above any heading. Avoid: breadcrumb, section path.
