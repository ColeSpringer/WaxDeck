# 6. Playlists on the catalog engine, with reissued smart-rule pids

Date: 2026-07-19

## Status

Accepted

## Context

Playlists could live in either database. The catalog engine ships a
complete playlist service: static ordered lists, smart lists whose
typed rule tree evaluates per user on read (user-state fields like
stars, ratings, and play counts bind the evaluating user at query
time), owner plus shared visibility, M3U8 round trips, and change-log
rows. WaxDeck's own database holds only auth and integration state and
never joins catalog listings.

Two constraints shaped the design:

1. The engine has no rule-update call. A smart playlist's rule is
   fixed at creation; renames and visibility changes update in place,
   but replacing the rule means creating a successor and deleting the
   original, which changes the playlist's pid.
2. Playlist rows carry no user dimension in the engine's change log,
   and private playlists must never leak existence to other users, so
   playlist changes cannot ride the catalog sync stream. They ride the
   per-user server stream instead, fanned out to every user for shared
   playlists.

## Decision

Playlists live in the catalog engine, reached only through its facade.
WaxDeck adds the API surface, visibility enforcement (a private
playlist reads as absent for everyone but its owner; shared playlists
are readable by all and writable by the owner), the owner-evaluation
rule for shared smart lists, and sync fan-out.

Rule replacement reissues the pid, stated in the API contract rather
than hidden: the update response carries the new pid with
`previousPid` linking to the retired one, the same link is stored
(a small key-value row) so sync hydrations and detail reads repeat
it, and the retired pid's absence plus the successor's presence reach
every affected user's server stream as two events. Clients relink
instead of seeing a delete and a create.

The considered alternative was a WaxDeck-owned stable pid aliased to
the current engine pid. It would erase the reissue class entirely, but
the alias would have to be consulted and rewritten on every surface
that mentions a playlist pid (REST, sync events, the Subsonic
adapter), and a translation table between two databases for one
mutation path is more machinery than the problem deserves. If the
engine ever grows an in-place rule update, the reissue paragraphs in
the contract retire and nothing else changes; the alias would have
been permanent plumbing.

The wire rule format is WaxDeck's own (a flat node tree with a type
discriminator, values string-encoded), converted to the engine's typed
AST server-side. The vocabulary is mirrored by hand because the
engine's field map is unexported; the rule-fields endpoint serves it
to editors so clients never hardcode it. Rules are bounded on write
(200 nodes, 10 levels) and validated by a dry-run count so bad rules
fail the create, not the first read.

## Consequences

- Smart playlists are pay-per-read: membership is evaluated on every
  listing, never materialized. At household scale over the engine's
  indexed per-user joins this is milliseconds; nothing caches, so
  nothing goes stale.
- A shared smart playlist shows every viewer the owner's evaluation
  (the owner's stars and ratings), matching the contract's "viewers
  see the owner's list" rule. Viewers' own library visibility still
  filters what they can read.
- The pid-reissue seam is honest but real: clients must follow
  `previousPid`, and `createdAt` restarts on reissue. An engine-side
  in-place rule update is the recorded upstream candidate that would
  dissolve it.
- Relative date rules ("played in the last 30 days") cannot be
  expressed; the engine compares absolute timestamps only. The
  contract documents the gap and it is the second recorded upstream
  candidate.

## Update — 2026-07-23: the reissue seam is dissolved

Both recorded upstream candidates landed. The catalog engine grew an
in-place rule setter (`playlist.SetRule`), relative-date operators
(`inTheLast`/`notInTheLast`, anchored at read time), and limit modes
beyond a plain count (a seeded random draw and minutes or megabytes
budgets). WaxDeck adopted all three.

- **Rule edits apply in place.** `UpdatePlaylist` calls the rule setter
  under the existing pid instead of creating a successor and deleting
  the original. The pid is now stable for the playlist's whole
  lifetime, `createdAt` no longer restarts, and a rule edit reaches
  every affected user's server stream as a single `playlist` event that
  re-hydrates the changed playlist. The reissue machinery is retired:
  the `previousPid` settings mirror, the two-event sync, and the client
  follow logic are all gone.
- **`previousPid` stays in the contract, deprecated.** Removing a
  response property is a breaking change under the compatibility gate,
  so the property remains, marked deprecated, and is never populated (a
  now-stable pid leaves it permanently absent). This ADR's "clients
  must follow `previousPid`" and "`createdAt` restarts" consequences
  above no longer hold.
- **Relative dates and limit modes are expressible.** A date condition
  accepts `inTheLast`/`notInTheLast` with a whole-days value that
  re-evaluates its window on every read; a rule carries an optional
  limit mode (`random`, `minutes`, `megabytes`) with an optional seed.
  WaxDeck converts the day count to the engine's nanosecond window and
  maps the wire mode onto the engine's, validating the same
  combinations the engine rejects (a random draw takes no sort order, a
  seed needs a non-count mode, a budget needs a positive limit) so a
  bad rule answers `invalid-request` on write rather than on first
  read.

Pre-1.0 forward-compatibility, recorded so it is not re-derived: the
limit mode rides an additive field on the version-1 rule document. An
older WaxBin binary parsing a mode-carrying doc drops the mode and
still honors the limit, so a "random 25" rule degrades to "the first 25
in sort order" and a "60 minutes" rule to "60 rows". That silent drift
is accepted before 1.0.
