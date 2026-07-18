# 3. Two databases, never ATTACHed

Date: 2026-07-18

## Status

Accepted

## Context

WaxDeck embeds the WaxBin catalog (waxbin.db) and also keeps state of
its own: users, sessions, listen sessions, and later outboxes, shares,
and review queues. SQLite's ATTACH would let one connection join across
both files, and a joined "my listens with catalog titles" query looks
tempting.

## Decision

WaxDeck's own state lives in waxdeck.db, a separate SQLite database
beside waxbin.db, and the two are never ATTACHed. All catalog access
goes through the WaxBin facade; all WaxDeck state goes through the
internal db package. Cross-database references are by PID and tolerate
dangling values.

waxdeck.db uses one dedicated write connection and a small read pool,
WAL journaling with synchronous=NORMAL, and a busy timeout as
belt-and-braces. High-frequency writers coalesce before they reach the
database.

## Consequences

- The join-heavy surface people expect ATTACH for does not exist:
  per-user listening state (ratings, play counts, progress, queues,
  playlists) lives inside waxbin.db by design and is served by WaxBin's
  own query engine, so catalog-with-user-state queries are single
  database behind the facade. WaxDeck's tables are auth, ops, and
  integration state that never joins catalog listings; the touches that
  do cross are PID point lookups batched through the facade.
- ATTACH would couple WaxDeck to WaxBin's internal schema (dozens of
  tables on its own migration cadence) when the facade is the stability
  contract.
- SQLite gives no cross-file write atomicity in WAL mode, so a joined
  write path would be a lie anyway.
- SQL strings are invisible to the import lint that enforces the
  ownership boundary; keeping the databases apart keeps the boundary
  machine-checkable.
- Backup is the pair: the WaxBin backup API for the catalog plus VACUUM
  INTO for waxdeck.db, packaged in one archive.
