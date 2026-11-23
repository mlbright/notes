# 4. Rails is replaced by a Rust Port that shares Production State

Date: 2026-11-22

## Status

Accepted

## Context

The Notes system is to be reimplemented in Rust. A first draft plan proposed
Loco with SeaORM, a schema regenerated from `schema.rb`, Loco's job queue and a
three-agent pipeline comparing curl output. Checked against the code, it
missed most of what makes this application hard to replace: the FTS5 tables
and triggers already live in the database (`structure.sql`), note bodies are
rendered by Redcarpet with app-specific options, the HTML embeds Rails-signed
blob IDs and CSRF tokens, Passages are cut by Ruby string rules, and Retrieval
depends on matching embeddings from a pinned model.

The port follows Basecamp's rails-to-rust toolkit
(`github.com/basecamp/rails-to-rust`): a pinned Reference, contracts captured
from the running Rails runtime, strict Parity with narrow per-case masks, and
rollback rehearsals. This ADR records the choices that shape it. The full
rationale is in the conversion plan of the `notes-rust` repository.

## Decision

The Port is a candidate replacement, not a new application. It runs against
the existing Production State unchanged — the same SQLite files, blobs, API
tokens and session cookies — so either implementation can serve production and
a Switch in either direction is a restart.

- **Repository.** The Port lives in a separate `notes-rust` repository whose
  `reference/` submodule pins this repository. Production State stays in this
  checkout (ADR 0001); the Port is told its path.
- **Reference first.** Defects found while porting (security holes, the
  unscheduled trash purge) are fixed here, then re-pinned, so the Port ports
  fixed behaviour. After pinning, `web/` takes no behaviour changes until the
  Switch; security and dependency updates land in batches, each re-pinned.
- **One Switch.** The whole application switches at once. The Port has its own
  Generated Unit, exclusive with `notes-web` through `Conflicts=`, serving port
  3002 directly; `make switch-to-port` and `make switch-to-rails` change over.
- **Stack.** axum, rusqlite with sqlite-vec linked in, and Askama templates
  mirroring the ERB views. SQL is explicit, one connection writes, and each
  note save owns its transaction. No ORM and no framework migrations: the
  database schema is a contract the Port reads, not one it generates.
- **Compatibility leaves.** The Port reads and writes Rails' encrypted session
  cookie and masked CSRF tokens, and produces Rails' signed blob IDs, from a
  `SECRET_KEY_BASE` shared through `web/.env`. Markdown is rendered by
  Redcarpet's own C core compiled into the Port. Passages are cut by a hand
  port of `Passage::Cutter`, checked against golden cuts.
- **Embeddings are shared.** The Port uses the same model files, tokenizer
  crate and ONNX Runtime version, and writes the same `embedding_model` key.
  Its vectors must agree with the Reference's (cosine ≥ 0.9999) and Retrieval
  responses must match byte for byte on a golden query set.
- **Background work is in-process.** The Port opens only the primary database.
  Embedding, the 10-minute sweep and the daily trash purge run as tasks inside
  the process, rebuilt from database state; Solid Queue, Solid Cache and the
  cable database are left to Rails.
- **Parity bars.** JSON responses are compared byte for byte; HTML by
  normalized document structure plus browser interaction checks on a desktop
  and a phone viewport. The Switch also requires no p95 latency regression on
  the note list, a note page, Search, Retrieval and a note save.
- **No standby window, with guarded rollback.** Features may land in the Port
  right after the Switch. Changes are expand-only by default; CI boots the
  pinned Reference on data the Port wrote and reads every row back; Port schema
  changes are plain SQL applied by an explicit `make migrate-port`. The first
  change the Reference cannot read is the Point of No Return: it sets
  `rails_rollback = false`, takes a labelled Database Snapshot, masks
  `notes-web` and makes `make switch-to-rails` refuse.

## Alternatives rejected

- **Loco with SeaORM.** Its migrator, JWT auth, job queue and runtime templates
  would each have to be disabled to keep Production State unchanged, and the
  queries that matter (FTS5, `bm25()`, `vec_distance_cosine()`) are raw SQL
  anyway. sqlx's async SQLite is a background thread around a single writer.
- **Switching route groups one at a time behind Caddy.** Both implementations
  would write live data at once, so the Port would have to enqueue Solid Queue
  jobs and cut Passages identically while Rails swept behind it. That mixed
  mode needs its own Parity and is thrown away after the last group moves.
- **A separate embedding model key for the Port.** Simpler to verify, but every
  Switch would leave Retrieval keyword-only for minutes while one side
  re-embedded everything.
- **A Rust markdown crate.** Redcarpet is not CommonMark; existing notes would
  render differently and the Switch would become a rendering change. Replacing
  the C core with a Rust engine remains a follow-up, as a deliberate change.
- **A standby window after the Switch.** It would keep rollback free by
  freezing features. The guarded expand-only rules keep rollback free for as
  long as changes allow, and end it only deliberately.

## Consequences

- Rails' session cookie, CSRF masking and signed-ID formats become Port code,
  verified against vectors produced by the Reference, for as long as Rails is a
  rollback target.
- The Port carries vendored C (Redcarpet) and links ONNX Runtime dynamically.
- While Rails can be switched back to, any Port change touching persisted data
  must be labelled rollback-safe or rollback-breaking, and pass the rollback
  rehearsal in CI.
- Retiring Rails — removing `notes-web`, deciding where Production State lives,
  retiring `master.key`, amending ADRs 0001 and 0003 — is its own decision,
  taken at the Point of No Return rather than on a timetable.
