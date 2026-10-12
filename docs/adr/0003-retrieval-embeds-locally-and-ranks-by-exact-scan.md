# 3. Retrieval embeds locally and ranks by exact scan in SQLite

Date: 2026-10-12

## Status

Accepted

## Context

Agents need Retrieval: the Passages of a user's notes most relevant to a query,
by meaning as well as wording, so they can ground answers in them. The app only
retrieves; the agent's own LLM does the generating. Keyword search (FTS5)
already exists, so the new part is semantic matching, which needs an embedding
for every Passage and for every query.

The constraints come from the deployment (ADR 0001): one modest VPS that is
both the development workspace and production. It has an i5-8265U (4 cores,
throttles under load), about 3 GB of free memory, and is already using swap.
Puma runs one process with 3 threads, and Solid Queue forks a job worker from
it. The data is about 2,300 English notes, which cut into roughly 5,000
Passages, and grows slowly.

Measured on this host:

- `informers` (ONNX Runtime) installs from precompiled gems on Ruby 4.0.7.
- `bge-small-en-v1.5` quantized to int8 uses about 120 MB per process and
  embeds a query in 5–7 ms and a note-sized Passage in about 55 ms. Quality is
  essentially unchanged from full precision, which uses about 260 MB.
  `multilingual-e5-small` uses 840 MB.
- ONNX Runtime holds Ruby's GVL for the whole of each call. While one thread
  embeds, every other thread in that process stops.
- sqlite-vec's `vec_distance_cosine()` over a plain table of 5,000 vectors,
  with the access and filter joins, takes about 7 ms. Its `vec0` virtual table
  takes about 4 ms but cannot filter on tags or shares. Rails loads
  `db/structure.sql` with the `sqlite3` command-line tool, which has no `vec0`
  module, so a `vec0` table cannot be recreated from it ("no such module:
  vec0"). Pure Ruby takes 100–130 ms.

## Decision

Embeddings are computed in-process by `bge-small-en-v1.5` (int8), pinned to one
Hugging Face revision. `make update` installs the model into
`web/vendor/models`, like a dependency, and nothing is downloaded at runtime.
The directory is an Ephemeral File, excluded from backups.

Notes are embedded only in a Solid Queue job, which runs in the forked worker
process, one job at a time with 2 ONNX threads. Queries are embedded inside the
request. Each process loads its own copy of the model on first use, never
before Solid Queue forks.

Embeddings are float32 blobs in a plain `passages` table in the primary
database, tagged with the model that produced them. Queries rank them with
sqlite-vec's `vec_distance_cosine()` in an ordinary SQL query, so access checks
and filters are the same joins the rest of the app uses. The keyword ranking
(FTS5 over Passages) and the semantic ranking are merged with reciprocal rank
fusion.

## Alternatives rejected

- **A hosted embedding API.** No model to install and no GVL problem, but every
  note would leave the server, and Retrieval would depend on an external
  service and its keys.
- **sqlite-vec `vec0`.** Slightly faster, but filters by tag or share would
  have to be applied after the nearest-neighbour search, which can return too
  few results, and `db/structure.sql` could no longer recreate the database.
- **Pure Ruby similarity.** No extension, but 100–130 ms per query, holding the
  GVL throughout.
- **A larger or multilingual model.** `multilingual-e5-small` costs 7× the
  memory, and the notes are all in English.
- **Embedding notes inside the request that saves them.** It would freeze the
  other Puma threads for about 60 ms per Passage.

## Consequences

- Memory: about 120 MB in Puma once the first query arrives, and 120 MB in the
  job worker once the first note is embedded.
- Ranking is an exact scan, so its cost grows linearly: about 70 ms at 50,000
  Passages. At that scale, revisit `vec0` or an approximate index. Passages
  can be rebuilt from note text, so switching is a migration plus a re-embed.
- Changing the model is a constant change. Embeddings from the old model are
  ignored, so those notes match by wording only until the sweep re-embeds
  them, which takes about 6 minutes for 5,000 Passages.
- A new note is keyword-searchable as soon as it is saved and semantically
  searchable once the job has run, usually within seconds and at most within
  the 10-minute sweep.
- Every primary-database connection loads the sqlite-vec extension (see
  `config/database.yml`). The gem has no 32-bit ARM, aarch64 or musl builds,
  so the lockfile is x86_64 glibc only.
