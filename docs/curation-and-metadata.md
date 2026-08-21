# Curation and metadata

WaxDeck is a metadata completer as much as a player. This page covers
the matching review queue, uploads, the metadata editor, the health
dashboard, duplicates and upgrades, the file organizer, and the
audiobook and CUE tooling.

## Matching and the review queue

WaxDeck identifies music against MusicBrainz the way beets does, not
the way a lookup box does: files group into album units (tags first,
directories for untagged files, disc folders folded in), candidate
releases arrive by tagged MusicBrainz ids, acoustic fingerprints, and
text search, every candidate is scored by weighted field distances
over an optimal track assignment, and the unit is decided as a whole.
A unit never half applies.

Files reach the pipeline four ways: an upload, a URL acquisition, a
rematch pressed on an item, and a scan. That last one is what covers
files dropped into a library root by hand: a background pass follows the
catalog's change log and opens an album-unit entry for what a scan
added, waiting for the scan to settle first so an album arrives whole
rather than one entry per file indexed so far. It watches from the
moment the feature lands rather than sweeping up what was already there,
so an upgrade does not drop an existing library into the queue; a
library set to **leave alone** in the console (matching mode `off`) is
never touched at all.

Confident matches apply themselves and appear in the queue as
auto-applied, with a revert button; everything else waits for review
with ranked candidates, a match percentage, a per-field distance
breakdown, and a side-by-side diff of current against proposed track
metadata. Decisions:

- **Approve** applies the chosen candidate (the ranked best by
  default) and locks the applied fields so a rescan cannot undo the
  acceptance.
- **Keep as is** accepts the current metadata unchanged.
- **Mark unofficial** is keep-as-is plus a locked `RELEASESTATUS`
  custom tag: YouTube rips, remixes, live sets, and personal
  recordings have no canonical release, and marking them says so.
  Unofficial content is excluded from match retries and health
  penalties, stays browsable by the tag, and remains fully
  hand-editable. Files that arrive already tagged with a bootleg
  status are treated the same way.
- **Skip** dismisses the entry without touching anything.
- **Revert** (on applied entries) restores the pre-apply snapshot and
  unlocks the fields. Reverts of auto-applied entries feed the
  calibration statistic the queue shows, so trust in auto-apply is
  measured, not asserted.

Per-library matching modes: `auto` (the default), `review` (nothing
applies itself), and `off` for libraries the engine must never touch.

Matching needs the network. MusicBrainz lookups are paced to their
etiquette (one request per second) and cached; AcoustID fingerprint
evidence requires an API key (`WAXDECK_ACOUSTID_KEY`) and the
`fpcalc` binary, and matching degrades gracefully to tag and search
evidence without them. `WAXDECK_MATCHING=false` disables the engine
entirely.

## Uploads

Users with upload rights (an admin grant, with an optional per-user
pending upload limit) can push audio from any client: uploads are chunked and
resumable, carry a required media type label (music, podcast episode,
audiobook), and stage outside the library until a review decision
imports them. Items a user's own uploads bring into the library stay
editable by that user afterward: the full-depth editor's item-scoped
operations accept the uploader as well as administrators. The
identify pipeline runs on every completed upload, so a well-tagged
file usually arrives with its candidates already scored. Duplicate
warnings (exact bytes, or the same recording in a different encoding)
inform the decision instead of blocking it. The uploads screen shows
what the account currently has waiting at the top of the session list.
The limit caps what may sit in staging awaiting a decision, so
importing an upload frees the room it held.

Files reach the flow three ways: a file picker on every platform, a
folder picker everywhere but Android (whose folder access means SAF
tree URIs, which the picker port does not speak), and drag-and-drop
onto the library or uploads screen on web and desktop. A picked folder
is walked recursively and its shape rides along, so disc subfolders
survive to the grouping step. Web transfers read the browser's file
handles in windows, so picking a multi-hundred-megabyte album never
loads it into memory.

Uploading several files at once asks a grouping question so an album
folder does not flood the review queue with per-file entries:
**Auto-detect** (the default) clusters files into album units by
their tags and relative folders - disc subfolders like `CD1` fold
into one release - **One album** reviews everything as a single
release, and **Separate tracks** opens one entry per file. The
grouping rides an upload batch: members upload individually
(per-file failures never sink the rest), and the batch finalizes
into review entries when the transfer finishes - or within a day,
with whatever arrived, if the client vanished. Files shared to the
Android app group by auto-detection without asking.

The client's pick dialogs filter to the default accepted-format set
(a hardcoded mirror of the server's list); a server running a custom
`WAXDECK_UPLOAD_FORMATS` still accepts its formats through the
dialogs' "All files" group, and the server-side format check at
session create is the real gate either way.

Three ceilings sit on a session before a byte moves, alongside the
per-account pending-upload limit: one file may declare at most 16 GiB,
one request may carry at most 32 MiB of it, and a session is refused
outright when the staging volume has no room for what it declared -
counting what the transfers already running have been promised and
leaving half a gigabyte spare. Opening sessions is paced per account
too, generously enough that no real transfer meets it; sending bytes
is not, so a folder of any size moves at whatever the link does. See
[upload oversight](admin-and-ops.md).

Imports move files into the library, so at least one library root
must be opted into managed placement with `WAXDECK_MANAGED_ROOTS`
(root names, comma separated). Unlisted roots are never written: the
conservative default is that WaxDeck moves nothing it did not place.

## Acquiring from a URL

Users with upload rights can also pull audio in by URL from the
library's **+** button (Add from URL): a single YouTube video, a
playlist, or a channel (bounded to two hundred entries per
acquisition; subscribing the channel as a show is the archive-scale
path). The downloader is on by default; it needs a managed library
root for the files to land in (`WAXDECK_MANAGED_ROOTS`), and
`WAXDECK_YOUTUBE=false` turns it off. See the getting-started guide.
The download runs as a background task through the acquisition
bridge, with SponsorBlock cuts and embedded source metadata (title,
channel, thumbnail) plus provenance tags recording where the audio
came from. The files then stage exactly like uploads and flow through
the same identify and review pipeline, grouped into album units.

This is where the honest-metadata story matters most: a ripped album
playlist with clean titles will often match its release and arrive
fully tagged, while an unofficial remix or live set may match nothing
that exists outside that video. Both are first-class outcomes. The
review queue offers keep-as-is and mark-unofficial beside any
candidates, the source-derived metadata is preserved either way, and
the person who acquired the content keeps item-scoped editing rights
over it afterward, so hand-naming a remix does not require an
administrator.

## The metadata editor

Every field in the vocabulary is editable, not a five-field form:
scalar fields per media type (including identifiers like ISRC, ASIN,
ISBN, and MusicBrainz ids, validated on write), typed credits with
per-kind role vocabularies, lyrics (timed LRC or plain text),
chapters on single-file audiobooks, front-cover artwork for items and
entities, custom tags (which are full browse dimensions), and entity
edits (sort names, identifiers, release group types) with their own
provenance.

The catalog database is the working copy: edits land there first and
touch files only when the request opts into write-back. Edits lock
their fields by default so scans and enrichment respect curation;
locks are visible and reversible in the editor, and per-field
provenance shows who set what (file tags, a user, enrichment, or the
organizer). A write-back that fails after the catalog committed
reports per-file detail and surfaces as an out-of-sync diagnostic
rather than failing the edit. Lyrics write-back writes the `.lrc`
sidecar so corrections stay portable to every other player.

### Where a cover came from

Covers and lyrics carry the same attribution the scalar fields do:
whether they were read out of the file's own tags, out of an image or
`.lrc` sitting beside the audio, out of a podcast feed, fetched from a
metadata provider (which is named), or set by hand.

Wherever a cover is drawn large enough to carry a caption - the
artwork manager, the album, artist, book and show headers, and the
radio face - a line under it says which. It is always on and nothing
hides it. The grids do not carry it, because a 48-pixel thumbnail has
no room for a line and no listener reads two hundred of them.

A release usually holds no cover of its own and shows one of its
tracks' instead. Its caption says both things - where that track's
picture came from, and that the release did not choose it - rather
than reporting a decision nobody made. On radio the picture is the
station's own announcement or a provider's answer for the title it
announced, and the caption names which; the station logo underneath
is the station's and carries no mark.

### Pinned covers

Setting a cover pins it, which is what keeps it through an enrichment
run, a rescan, and a podcast feed changing its image URL. A pin governs
writes and nothing else: what you see is always the first level of the
chain that holds a picture, so a track with no cover of its own shows
its album's and an album with none shows a member track's, pinned or
not.

Clearing removes the picture at that level and leaves the pin exactly as
it stands, on an item as on a release. The read then falls back down the
chain as usual - what the pin buys is that nothing automatic puts a new
cover in the slot you just emptied, which is the difference between
"this has no cover of its own" and "refill this from wherever you can".

That state - pinned with nothing behind it - is visible rather than
silent: the artwork manager draws it as a pinned empty slot instead of
an ordinary empty one, and the album editor carries a **Pin this
cover** switch over
`PUT /entities/{entityType}/{entityPid}/artwork/lock`, which is how an
administrator lets go of it. Playlists are refused there: a playlist's
cover authority is its own uploaded-versus-generated marker, and
clearing an uploaded playlist cover hands the slot back to the mosaic
built from the members.

### Editing a release

An album's own fields are edited on their own screen, reached from the
album's overflow (administrators only, because barcodes and labels are
shared by everyone who can see the release). It opens on the album
itself - the cover, the title, the year, the running time, and the
tracks a write-back would reach - because "also rewrite the matching
tags in every track on this release" is a sentence about files nobody
can see from the form.

The cover sits in the same artwork grid the item editor uses: set,
clear, the source mark, and the pin above. Below it are the release's
own name and handle (**Sort name** and the **MusicBrainz release ID**)
and its edition columns (barcode, label, catalog number, media,
country), each showing where its current value came from and whether
it is locked. Only the fields that changed are sent, so a one-word
correction does not lock the other six.

## The genre vocabulary

Genre tags are whatever the files say, which means one genre arrives
under several names. WaxDeck normalizes them onto a canonical
vocabulary: a two-level tree of top-level genres and the genres
grouped under them, each with one display spelling and the aliases
that resolve to it. Case, diacritics, and punctuation already fold in
the catalog ("Hip-Hop" and "hip hop" are one genre there), so the
aliases are for the synonyms folding cannot reach: "Rap" onto
"Hip Hop", "DnB" onto "Drum & Bass", a run-together "HipHop". A genre
the tree does not know is left exactly as it is, never guessed at.

A background sweeper keeps the catalog folded onto the vocabulary
continuously, following the catalog's change log, so a library
scanned tomorrow normalizes shortly after it lands rather than
waiting for anyone to press a button. A genre you locked in the
editor is yours and is left alone. `POST /admin/genre-normalize`
runs a full-catalog pass for a library older than the change log
retains, or to apply a vocabulary edit at once; `dryRun` reports what
would change first.

WaxDeck ships a broad default tree. The admin console's Genre tree
section edits it: the vocabulary on one side, one genre's name, parent,
and aliases on the other, with the whole tree saved in one write
(every save rewinds the sweeper, so a rename and a re-parent should be
one change rather than two full re-checks). Reverting to the shipped
default and starting a normalization pass, dry-run first, are both
there. Over the API, `GET /admin/genre-tree` reads whatever is in force
and `PUT` replaces it wholesale (an empty list goes back to the shipped
default). A tree that could not resolve one
way is refused rather than stored, so an alias claimed by two genres
or a genre nested three levels deep is a clear error, not a silent
coin flip. The `genre-whitelist` health rule lists what is still
off-tree, which is the list to work from when deciding what the
vocabulary should learn next.

## Health dashboard

The health sweep scores the library for completeness: missing or
small artwork, missing identifiers, years, genres, lyrics, narrators
and ASINs on books, genres outside the canonical tree, files whose
paths disagree with the organize template, files whose tags lag the
catalog, legacy-only tag values, and corrupt audio. Items marked
unofficial are exempt from the rules that assume a canonical release.
Rules with an automated fix can be fixed in bulk; fixes run in the
background at provider-etiquette pace. A fresh install shows a
warming-up state with honest progress instead of a wall of red.

## Duplicates and upgrades

The audit's duplicate findings (artists, albums, release groups,
genres) surface with suggested survivors; merging re-parents
everything onto the survivor, play history included, and survives
rescans because the survivor keeps its identity. Quality upgrade
groups (the same recording in different encodings, found through the
fingerprint index) resolve by keeping the best and trashing the rest,
recoverable within the trash window.

## Organizer

Template-driven renames and moves with a dry-run preview, using the
server's configured organize profiles. Sidecars (covers, lyrics, cue
sheets) ride along with their files, moves are crash safe, and
templates are sandboxed per path segment so they cannot escape the
library root. WaxDeck never fights an externally managed library:
organizing is always explicit.

## Audiobook and CUE tooling

With the streaming engine configured:

- **Merge** a multi-file audiobook into one chaptered file: parts
  join gaplessly, chapter marks land at the part boundaries with
  sensible titles, tags and cover carry over, and everyone's resume
  position survives the merge. The parts go to the trash unless kept.
- **Split** a single-file audiobook at its chapters, or a CUE rip
  into real per-track files (sample exact, lossless for lossless
  sources). CUE albums already browse and play as native per-track
  items without splitting; the physical split is for people who want
  real files with working write-back and fingerprints.

Tool tasks run in the background and report progress over the event
channel; the task log lives under the tools API.

## Enrichment

The catalog's enrichment pass (MusicBrainz identity first, then
providers in priority order) fills artwork, genres, lyrics, and book
metadata, respecting locks and never overwriting curated values.
WaxDeck registers its own providers ahead of the catalog's built-ins:
Deezer and iTunes artwork (key free), Audnexus audiobook metadata
(key free, keyed on ASIN), and fanart.tv artwork when
`WAXDECK_FANARTTV_KEY` is set. The editor's per-item fetch uses the
same providers for one item at a time.
