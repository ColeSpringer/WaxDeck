# 12. Upload batches and grouped review entries

Date: 2026-07-22

## Status

Accepted

## Context

Manual uploads shipped complete on the server side - resumable
chunked sessions, quota, staging, and the identify-review-import
pipeline - but every completed session opened its own review entry.
That was right for one file and wrong for the common case the client
edge was about to enable: picking or dropping an album folder. Twelve
per-file entries for one release flood the review queue, defeat the
matching engine's album-level evidence, and fire twelve
review-ready notifications where one release deserves one.

Grouping cannot simply be inferred server-side, for two reasons found
during design. First, the clustering engine (`match.Cluster`) is not
metadata-only: it falls back to directory keys and folds disc
subfolders (`CD1`, `Disc 2`) into their parent - but staged uploads
each live in their own per-session staging directory, so the paths
the server sees carry no usable hierarchy. Second, the server cannot
observe a died client mid-batch: it sees only sessions that stopped
receiving bytes, so "the batch is complete" is not detectable, only
declarable.

## Decision

### A batch is declared intent, joined per session

`POST /uploads/batches` opens a batch carrying a grouping intent -
`album` (one multi-file entry), `tracks` (one entry per file), or
`auto` (cluster by tags and paths) - chosen explicitly in the upload
dialog. Sessions join by `batchId` at creation and may carry
`batchPath`, the file's directory relative to the picked or dropped
folder. `batchPath` exists purely as the clustering hint: `auto`
clusters over `join(batchPath, fileName)`, restoring the directory
fallback and the disc-folder fold that staging paths destroyed. It is
never a filesystem path on the server - validation rejects absolute
paths, parent traversal, and control bytes, and caps the length.

Share-sheet multi-file handoffs create an `auto` batch with no
dialog: the share gesture is fire-and-forget, and auto-detection
groups an album share while leaving unrelated files separate.

### Finalize over declared counts

The batch closes by an explicit
`POST /uploads/batches/{batchId}/complete`, not by a declared file
count. A count cannot distinguish "the last file is still uploading"
from "the client died"; an explicit finalize is exact for live
clients, and the 24-hour expiry janitor is the backstop for dead
ones. The janitor runs the same grouping with whatever staged by
then (state `expired`, conflict on a later client finalize):
completed transfer work is never silently discarded, the grouping
just degrades to what arrived. An expired-empty batch finalizes
empty. Client cancel is delete-members-then-finalize, so an
abandoned batch never resurrects into surprise review entries a day
later.

### Members persist their evidence; finalize only groups

A batch member's completion runs everything a solo upload runs -
parse, fingerprint, duplicate checks - and persists the built review
track document on the session row (`uploads.track_doc`) instead of
opening an entry. Finalize reads the documents back and groups; it
never re-parses or re-fingerprints. Entry opening is therefore cheap
enough to run inline in the finalize request.

### The straggler race is correct by construction

A member can complete concurrently with the finalize. The member's
persist is one conditional statement - stage the document only while
the batch row still reads `open` - and the finalize runs its
state flip and its staged-member gather in one transaction. SQLite's
single write connection serializes the two, so either the member
landed before the flip (the gather covers it, exactly one entry in
the batch) or it landed after (zero rows affected, the member falls
through to the ordinary per-file entry path, exactly one entry of
its own). No orphaned staged member, no double entry, under either
ordering; the integration tests drive both orderings
deterministically. A finalize interrupted between the flip and entry
opening is repaired by the idempotent retry, which gathers staged
members still lacking an entry.

Once the flip commits, entry opening and member linking run on the
process context, not the request context: they are server-side
completion of a committed decision, and a client disconnect
mid-finalize must not cancel them halfway. Residual link failures -
genuine database errors by then - surface as a failed finalize
instead of a silent success, since a success with an unlinked member
would let retention reap its staged file while the entry still
references it.

Three further guards keep interrupted or racing finalization
convergent. Finalization is serialized per process (one mutex around
flip-plus-entries): two concurrent finalizes - a double click, a
timed-out client retrying - would otherwise both gather the same
still-unlinked members and open duplicate entries. Entry ids are
recorded on the batch row as each entry opens, and every finalize
first runs a repair pass that links gathered members whose document
already sits inside a recorded entry - so a link lost to a crash or
database failure is completed on retry, never covered by a duplicate
entry. And the janitor's listing includes expired batches still
holding a staged, entry-less member (the state its own interrupted
entry opening leaves, which the conflict-answering client finalize
never revisits), so that gap heals on the next tick. Member links
are a narrow conditional claim (only a still-unlinked staged row),
so a member deleted mid-finalize is skipped as nothing-to-do rather
than failing the batch; the deleted file's document can transiently
remain in a pending entry, where an import attempt reports the
missing file and the entry is discarded by hand - accepted for a
sub-second window.

Members of a still-open batch are exempt from upload-session expiry:
irrelevant under default retention (seven days against a 24-hour
batch window) but load-bearing when an operator configures retention
below the batch window.

## Consequences

- An album folder yields one review entry and one review-ready
  notification instead of one per file.
- The uploads listing needs no batch endpoints: rows carry `batchId`
  and the client groups visually; create and finalize responses are
  the only batch reads.
- Two more columns ride every upload row (`batch_id`, `batch_path`)
  plus the transient `track_doc`; all empty for solo uploads, which
  behave exactly as before.
- The janitor gains a second drain (expired batches) inside the
  existing supervised ticker; no new goroutine.
- A client that dies after finalize but before its last member
  completes leaves that member to open a per-file entry when (if) it
  completes later - the deliberate degradation, preferred over
  holding the batch open indefinitely.
