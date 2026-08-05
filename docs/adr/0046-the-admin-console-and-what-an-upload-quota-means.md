# 46. The admin console, and what an upload quota means

Date: 2026-08-04

## Status

Accepted.

## Context

Eleven administrative surfaces had grown up one at a time, each landing
wherever the slice that built it happened to be. They were reachable as
eleven rows in the sidebar's Curation group, which said nothing about
how they related; the switches that govern the whole instance sat in a
list of personal preferences, between "reduce motion" and "artwork
size"; the maintenance timetable was a band at the bottom of the backups
page, so a library scan lived under Backups; and there was no page
anywhere that said what the set of libraries even is. `/admin` was a
location the Server settings section linked to and no route answered.

Three things also had to be decided rather than merely built.

**A scan discovers files and identifies none of them.** The matching
pipeline had three producers - an upload, an acquisition, and a
hand-pressed rematch - and a library scan was not one of them. Files
dropped into a root by hand sat unidentified until somebody noticed,
which is why the onboarding copy could not honestly say the server was
matching anything.

**A library created at runtime can half-work, silently.** Creating a
root reconciles the WaxFlow sidecar so it serves the same directory. When
that fails the library still browses, downloads, and direct-plays, and
only streaming is broken - and the reason was recorded on the audit
entry and in the server log while the 201 reported a plain success.

**"Upload quota" reads as two different things.** `UploadBytesInUse`
summed every non-discarded session, imported ones included, and
`DeleteUpload` refuses imported rows, so bytes that reached the library
stayed charged for good. A user who filled a small quota was locked out
permanently, including after following the refusal's own advice.

## Decision

### The console is a shell around `/admin`, not a screen

One nested `ShellRoute` wraps every `/admin` location. Above sidebar
width it draws a second-level section list beside the page, grouped
(Overview, Library, People, Server); below it, the console is one screen
at a time and `/admin` is the list of sections. Every section keeps its
own location, so "it is under Backups" stays a link rather than a set of
directions, and a section opened cold arrives with its navigation around
it.

`AdminSection` is the single declaration the section list, the compact
list, the active highlight, and the router all read. A section claims a
location by longest declared prefix, so a drill-in (`/admin/health/
missing-artwork`) keeps its section lit and the dashboard's own location
wins only when nothing longer matches.

The shell's Curation group collapses to four entries: Uploads, Tasks,
Review queue, and the console. Review keeps a top-level row of its own as
well as a console section - it is the surface an administrator opens
daily, and burying the keyboard-first screen a level deeper to tidy the
group would cost more than the tidiness is worth. `/tasks` stays outside
`/admin` for the reason it always was: starting a task is not an
administrator-only act.

### Server settings move out of Settings

The listener's Settings screen keeps a Server section, and it becomes a
door: the About row, and a row that opens the console. The switches
themselves (signup, read-only, sonic analysis, transcoding, retention)
are decisions about the instance and belong beside the other ones. The
settings registry keeps an entry for the console row carrying the
keywords those switches were searched by, so a query for "read-only"
still lands somewhere true.

### Scan discoveries enqueue matching, off the change log

`SweepDiscoveries` tails the catalog's change feed the way the genre
sweeper does, and turns items a scan created into album-unit review
entries. Four things make it behave:

- **It defers entirely while a catalog job runs.** That is the debounce.
  A scan writes its additions file by file, and a pass running mid-scan
  would cut an album into as many entries as it had files indexed so far.
- **Its first run anchors at the tail, not at the oldest retained
  change** - the opposite of the genre sweeper, deliberately. That one
  rewrites a scalar onto a vocabulary: idempotent, invisible, worth
  applying to everything already there. This one opens entries a person
  has to decide, and rewinding would drop an entire existing library into
  the review queue as an upgrade side effect nobody asked for.
- **Creations only, and never what an upload produced.** An apply
  rewrites the items it matched, so reading update rows back would
  re-review what was just decided; and a file that arrived through the
  upload or acquisition pipeline was reviewed on its way in, so the scan
  that indexes it afterwards is the same audio arriving twice.
- **A library set to `off` is left alone.** That mode exists to say "this
  collection is already curated", and filling the queue with entries
  nobody will decide is the touching it forbids.

Idempotence is a pending-unit guard rather than the cursor:
`PendingReviewUnits` answers the library, title, and artist of every
entry already awaiting a decision, and the *caller* folds case. That
side matters: SQLite's `lower()` is ASCII-only, so folding in SQL and
comparing in Go would leave "ÉTÉ" as "ÉtÉ" against "été" and every
accented album would miss its own entry and open a fresh one on every
tick, forever. With one spelling, an entry already waiting is found rather than opened twice, whether the second look
comes from a re-read of the log or from an album whose files straddled
two passes. Correctness rests there, which is what lets the cursor be an
optimization: each collected item carries the seq it arrived on, so a
pass that stops at its unit cap stores the position of the item it
stopped on rather than rewinding to the start of the batch and
re-reading up to 500 change rows, and every album unit in them, on
every tick of a large first scan.

### `streamingWarning` on the create response

The 201 carries the degradation. The administrator who made the change is
looking at the response; asking them to go and read the audit log for the
half that failed is how a silent partial success happens. The libraries
screen keeps it on screen until the next create rather than in a toast:
it is a sentence about something now permanently half-working, not a
confirmation.

### An upload quota is a pending-upload limit

The quota means **in-flight footprint, not total contribution**. It caps
what may sit in staging awaiting review, so an import releases the
headroom it held. `UploadBytesInUse` skips imported alongside discarded -
one predicate - and the field is labelled and explained as what it is:
"Pending upload limit", with helper copy saying that importing frees the
space.

The change gives the sum a partial index (`uploads_staged`, on
`user_id, size_bytes` where the state is neither discarded nor
imported). Freeing the space is exactly what lets imported rows
accumulate for good, so the table this sums over now grows without
bound while the population it charges stays bounded by retention;
indexing the population rather than the table is what keeps a quota
check from walking an enthusiastic uploader's whole history every time
they open a session.

The rejected reading, total contribution, wanted release-on-delete
accounting that had to stay correct across trash, restore, purge, merge,
dedup, and the health fixes, and it had no answer for a restore that
would re-charge a user already at their cap. This is also the phase that
first makes a quota settable, so neither reading was observable before
now and the label is where the decision becomes visible.

### Kids mode is one preset

The user editor gains a "Child account preset": no explicit content, no
delete, download, or upload, and a deny rule for the advisory tag files
actually carry. Everything it sets stays editable. Kids mode is
admin-configured in v1 by decision - no kid-facing UI ships - so the
preset is the whole of it. Library grants are deliberately left alone:
which libraries a child may see is the one part nobody else can guess.

## Consequences

The console's own components are new in `waxdeck_ui`: `WaxTable` (sticky
header, column priorities, a card list below sidebar width with the full
record behind a detail sheet), `StatTile`, and `showTypedConfirm`.
Compact behaviour belongs to the table rather than to each screen,
because every screen would otherwise decide differently what a phone
gets - and a `detail` column has to go *somewhere* on a phone rather
than simply disappearing, which is what the sheet is for.

The review marker a new entry raises is batched rather than suppressed.
It is an invalidation hint - it is what makes the review screen refetch -
so a scan that opens thousands of entries cannot raise one per entry per
administrator, and cannot raise none either. `openReviewEntry` stays
quiet for scan-origin entries and the sweeper raises one marker per pass.

The counting on `GET /libraries` is opt-in through `counts`. Subsonic's
`getMusicFolders` calls the same service listing on every connect, and
`startsWith` compiles to `LIKE ? ESCAPE '\'`, which turns SQLite's LIKE
optimization off - so counting by default put a scan per root on a path
that had read no catalog at all.

`librariesProvider` and `libraryMatchingProvider` moved from the review
controller to the admin providers: the review screen's matching menu is
one reader of that state and the libraries table is the other, and two
declarations would be two caches disagreeing about what a library is set
to.

The command palette can start a scan now, gated on the role by `offered`
rather than by `enabled`, so an account that cannot start one is not
taught the command at all.

Three of 6.15's sections are not built and are recorded in
`docs/deferred-work.md`: server-scope notification targets, shares
oversight, and per-library transcoding context. The libraries screen's
item count is a path-prefix count, because the catalog's query language
has no library dimension - the same attribution every other
library-scoped answer already uses, and now also an upstream ask (a
`library` field in the store's field table, against a column that is
already there and already joined).
