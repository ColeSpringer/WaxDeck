# 50. The e2e account model and the shared server

Date: 2026-08-05

## Status

Accepted. ADR-0049 covers the driver layer the same re-architecture
introduces. Reaffirms ADR-0036: the server ships no test-only surface.

## Context

The Playwright suite ran every spec against one WaxDeck process as one
administrator, four workers wide, with no reset between tests. Eight of
34 diagnosed breakage incidents were collisions between those workers,
and the suite had grown a body of folklore to live with them: four
`test.describe.serial` groups, three chained projects, a 409-retry around
a sibling's catalog lease, fixture-dodging conventions, and roughly 28
comment sites across 15 files reasoning about what another worker might
be doing.

The specific collisions, each of which had actually fired:

- **Per-user aggregates drifted.** The gpodder journey subscribed to the
  same fixture feed as the podcasts journey and reported a play position
  as the same account, so a show's unplayed backlog was not the feed's
  episode count. Every count had to be re-read from the server rather
  than written down.
- **Whole-object preference PUTs clobbered each other.** `PUT
  /users/me/prefs` replaces the document, and every writer builds its
  body from a snapshot it read earlier, so two specs writing different
  keys is last-writer-wins over fields neither meant to touch. Key
  disjointness was not the protection it read as.
- **Subscription changes retired the shared account's catalog cursors**,
  turning another worker's in-flight `/sync/catalog?since=` into a 410.
- **Sync events hydrate play state at read time**, so asserting `starred`
  off an event raced every other starrer of that pid - which produced a
  written-down ledger of which spec was allowed to star which fixture.
- **Every worker's page was a Connect endpoint of the same account**, so
  a spec that cast a load could land its queue on another worker's page.

None of these are defects in the product. They are all one cause: four
unrelated scenarios sharing a login.

Two things made a naive fix unavailable. The server deliberately ships no
reset or seeding endpoint, and adding one to make tests cheap is exactly
what ADR-0036 refuses. And the shared installation is not incidental - it
is the household this product is for, and it is where the seven real
defects the suite has caught actually lived.

## Decision

**One account per test, minted through the production API. The server
stays shared.**

### Per test, not per file

The account name is derived from `testInfo.titlePath` and
`repeatEachIndex`: a slug of the title path, truncated to fit the
64-character username limit, with a short FNV hash appended so truncation
cannot collide. Deterministic, so a retry lands on the same account and a
run against a reused stack re-uses rather than accumulates.

The repeat index is part of the key because `titlePath` is not: it is the
file and the titles above the test and nothing else, so under
`--repeat-each=3` - which is exactly what the soak runs - all three
copies would derive one name and log in as one account. The workflow
built to find flakes would have manufactured the aliasing this ADR
removes. A retry index is deliberately absent for the opposite reason: a
retried test is meant to land on the account its first attempt used.

Per test rather than per file is what lets `fullyParallel: true` stay.
Tests within a file no longer share state, so intra-file concurrency is
safe, a retried test never sees its file-mates' leavings, and exact-state
assertions get stronger rather than weaker. The per-file alternative
carries a hidden invariant - every test independently re-runnable against
its file-mates' output - that nothing could check and that
`describe.serial`'s skip-on-failure was partly buying.

The cost is per-test setup, which `driver/seed/` makes one call. A file
whose setup is genuinely expensive and not replaceable by seeding could
be given a file-scoped account, declared in `accountShapes` so that it is
visible in review. Nothing has needed one, and the field is deliberately
absent until something does: a declared option that silently changes
nothing reads as a lever somebody has already pulled.

### Minting is idempotent, because there is no reset

`mintAccount` posts to `/users` and accepts 201 or 409, then logs in
either way. That is safe on a reused stack, safe on a retry, and safe
against a sibling worker minting the same name in the same instant.

The 409 path does two more things, because an account that already exists
was shaped by whatever was declared when it was made. It revokes the
sessions earlier runs left on it, so the device list the settings screen
draws does not grow without bound; and it reconciles the account's roles
against the shape declared now, as a set rather than a contains-check, so
that dropping `admin` is honoured as surely as gaining it. Neither runs
on a fresh stack. The account set is bounded by construction - one per
test, about ninety - and a renamed test strands an inert account, which
is harmless.

The same rule covers anything else created by name: playlists, stations,
shares, app passwords get a spec-scoped deterministic name with
create-or-reuse semantics, or a `finally` that cleans up.

Every minted account gets `libraryAccess: {mode: 'all'}` and the server's
own default permissions. `accountShapes` declares the exceptions. The
admin role is the one that matters, because it is server-global
authority, and its holders are pinned twice - in `accountShapes` and in
`lint/conformance.mjs` - so granting one is a two-file edit that shows up
in review.

The bootstrap administrator keeps two jobs and no others: it is the
subject of `first-run.spec.ts`, and it is the minting authority. The
ratchet fails any other spec that names it.

### What is deliberately still shared

The catalog and its files, the file-mutation lease, the admin settings
and the read-only switch, the radio station library, the review queue,
invites, audit, backups, notification targets, and the event fan-out.
Four workers still contend for all of it, because that contention is the
product's own subject matter. Only same-login aliasing is removed.

That splits assertions in two, and the split is the one thing a spec
author has to keep in mind:

- **Per-user state is this test's alone.** Queues, stars, positions,
  subscriptions, preferences, playlists, bookmarks, listens, shares.
  Exact counts are legal. Absence is legal. Snapshots are legal.
- **Catalog state is not.** A reused stack carries previous runs'
  uploads and three other workers are writing right now, so a catalog
  listing is asserted by the presence of what this test made, never by
  what it does not contain. `retryCatalogBusy` wraps anything that takes
  the mutation lease.

### Scheduling

Projects run: `setup` (first run) → the parallel wave → the catalog
mutators, uploads before admin-ops so the read-only window cannot overlap
an upload → the focus-sensitive specs → `motion-smoke`. Four workers and
the 120-second default test timeout stay.

Retries are `E2E_RETRIES`, defaulting to 1 in CI and 0 locally - down
from 2, because a test that needs three attempts is a quarantine
candidate, not a pass. A `@quarantine` tag is excluded from the blocking
run via `grepInvert` and included in the soak; every quarantined test
owes a `docs/deferred-work.md` entry in the same commit, so the exclusion
is tracked debt rather than a place things go to be forgotten.

The soak (`e2e-soak.yaml`, weekly and on demand) runs
`E2E_RETRIES=0 --repeat-each=3` with quarantine included. CI's e2e job
walks the JSON report afterwards and annotates any test that only passed
on a retry, and keeps `test-results/` - the traces and hang evidence -
for a flaky run as well as a failed one, which is the run whose evidence
was previously discarded.

## Consequences

- Exact assertions become available where they were previously illegal:
  preference snapshots, `unplayedCount === 3`, own-queue and own-position
  reads, a deterministic never-played shelf, and own-event sync
  assertions including absence.
- All four `describe.serial` groups, the `prefs-radio` chained project,
  the gpodder-to-podcasts coupling, and about twenty of the 28
  sibling-reasoning comments are dissolved rather than disciplined.
- The deferred-work entry about the read-only switch overlapping an
  upload is closed by ordering the mutator projects, not by a comment.
- Every test pays a mint (one create-or-409 plus one login). The startup
  scan poll, previously a per-test call at 42 sites, becomes one
  worker-scoped fixture.
- A stack that is reused across many runs accumulates a bounded set of
  accounts. `make reset` still drops them; nothing needs to.
- A spec that wants a second account in the same test mints one
  explicitly and drives it with `createApp` on its own page. That is the
  multi-client shape (connect, identity, sync), and it is now explicit
  rather than implicit in everything.
- The suite no longer proves that two sessions of one account behave. It
  never deliberately did; that was an accident of the old model, and the
  specs that mean it now say so.
