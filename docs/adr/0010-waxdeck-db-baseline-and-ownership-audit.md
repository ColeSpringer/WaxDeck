# 10. The waxdeck.db baseline and the state ownership audit

Date: 2026-07-22

## Status

Accepted

## Context

waxdeck.db grew through nine in-code migrations, one per feature
slice. By the end that history carried twelve ALTER TABLE ADD COLUMN
statements whose only reason to exist was the order the slices landed
in: three tables accreted columns in places that no longer read
naturally, and every fresh database replayed the whole accretion to
reach a state a single script could express directly. Pre-release
there are no deployed databases to migrate, so the history bought
nothing. WaxBin, for comparison, already ships a single clean
baseline.

The same review asked a second question: is WaxDeck maintaining state
that the WaxBin catalog already owns, or the reverse? ADR-0003 fixed
the boundary mechanics (two files, never ATTACHed, PIDs across); this
audit checks the contents against that boundary, table by table.

## Decision

### One baseline, edited in place until first release

The nine migrations are squashed into a single baseline script: every
CREATE TABLE and index, with the accreted columns folded into their
natural positions (listen_sessions.skipped_ms beside ms_played, the
ten users columns grouped by concern, tool_tasks.summary beside
progress_pct). The reorder is safe: server code contains no SELECT *,
no positional scans, and no schema introspection.

Until first release, every schema change edits the baseline in place.
user_version stays 1, and the change's PR notes that dev databases
must be deleted and recreated. At first release the baseline freezes
and append-only migrations resume from index 1.

Two mechanisms keep in-place editing honest:

- A normalized schema golden
  (`server/internal/db/testdata/schema.golden`, regenerated with
  `UPDATE_GOLDEN=1`) dumps every table's columns, foreign keys, and
  indexes in a sorted, name-stable form. The squash was verified by
  dumping the nine-migration schema, squashing, and requiring an
  empty diff; from here on, each baseline edit shows up in review as
  a semantic schema diff instead of a SQL rewrite.
- A baseline fingerprint: migrate stores the sha256 of the baseline
  script in sync_state in the same transaction that applies it, and
  refuses to open a database whose stored hash differs from the
  build's. A stale dev database fails at boot with a delete-and-restart
  message instead of limping into "no such column" errors. A missing
  hash row is adopted, not refused. The guard is deleted at first
  release along with the policy.

Old dev databases (user_version 2 through 9) are refused by the
existing newer-than-build version guard. Backup archives taken before
the squash refuse to restore the same way; accepted, pre-release.

### The ownership audit: every overlap is a keep

Each place where waxdeck.db state brushes against catalog state was
checked. All of them stay, for reasons that hold individually:

- **listen_sessions vs the catalog's play sessions.** WaxDeck's rows
  carry an idempotency key (user, session), the skipped_ms savings
  counter, and a source marker for offline replay, and they feed the
  stats surface. The catalog session API is never called and must not
  learn these fields; this table is WaxDeck's listening record, not a
  mirror of one.
- **play_state_stamps vs the catalog's play_state.** The catalog row
  has a single UpdatedAt that position checkpoints bump constantly,
  which makes per-field offline-replay guards unimplementable against
  it. WaxDeck mirrors its own per-field stamps, and the resume surface
  also rides them (RecentPositionStamps drives the recent-positions
  shelf), so upstream per-field stamps alone would not retire the
  table. Both facts are recorded in docs/upstream-requests.md.
- **users vs the catalog user.** WaxDeck is the sole identity
  authority; the catalog user is created at provisioning and stores no
  credentials. One row per side, joined by pid, no duplicated fields.
- **transcript_cache vs catalog transcripts.** WaxDeck caches
  time-coded cues fetched on demand for the transcript overlay; the
  catalog stores search-reduced transcript text captured at episode
  download. Different representations, different lifetimes. The gap
  (episodes whose cues WaxDeck fetched but whose text the catalog
  never captured because they were streamed, not downloaded) is filed
  upstream.
- **silence_maps loudness fields vs catalog loudness.** WaxDeck's
  integrated_lufs and true_peak_db ride the WaxFlow silence pass and
  drive voice boost at stream start. The catalog's loudness is
  ReplayGain from an analysis pass WaxDeck never invokes. Disjoint
  producers and disjoint consumers cannot disagree.
- **embeddings vs catalog fingerprints.** Sonic similarity vectors and
  acoustic identification fingerprints share nothing but the essence
  key both are correctly keyed on.
- **Denormalized display text** (audit_log actor and target names,
  scrobble_outbox artist and title, review_entries titles) is copied
  at write time because those rows must outlive catalog deletions and
  renames. That is the point, not a sync bug.
- **Parallel lease queues** (analysis, fetch, retention, match, fix,
  similarity, scrobble, notify outboxes) all follow one WaxDeck-owned
  work-queue shape. The catalog runs its own jobs; none of these
  shadow it.

The audit also confirmed there are no other WaxDeck-maintained stores
hiding outside internal/db: the only sql.Open elsewhere in the server
is the restore preflight's read-only probe of an archived waxdeck.db,
WaxTap keeps no database, and the Flutter app's drift database is a
device-local cache of server state, listed here only for completeness.

## Consequences

- Fresh databases are created by one script whose layout reads as
  designed rather than accreted, and the migration runner's loop is
  unchanged (it simply has one element until release).
- Contributors change schema by editing the baseline and regenerating
  the golden; review reads the golden diff. PRs carry the "delete
  data/waxdeck.db" note, and the fingerprint guard backstops anyone
  who misses it.
- Restore of pre-squash backup archives is gone. The preflight warns
  on the version mismatch and boot refuses the restored file; the
  answer pre-release is to re-rip state, not to migrate it.
- ADR-0003's boundary stands unmodified; this audit is the periodic
  proof that the contents still respect it, and the next audit has a
  checklist shape to follow.
