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
files dropped into a library root by hand: the server watches its roots
and scans a dropped directory seconds after it goes quiet (network
mounts without change events lean on the scan schedule instead), and a
background pass follows the catalog's change log and opens an album-unit
entry for what a scan added, waiting for the scan to settle first so an
album arrives whole rather than one entry per file indexed so far. It watches from the
moment the feature lands rather than sweeping up what was already there,
so an upgrade does not drop an existing library into the queue; a
library set to **leave alone** in the console (matching mode `off`) is
never touched at all.

Confident matches apply themselves and appear in the queue as
auto-applied, with a revert button; everything else waits for review
with ranked candidates, a match percentage, a per-field distance
breakdown, and a side-by-side diff of current against proposed track
metadata. The percentage reflects what the unit asked for: an album
rip is charged for every release track it is missing, while a single
file (one acquired video, one uploaded track) is scored on its own
evidence and the rest of the release is shown as context, not counted
against it. Decisions:

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
Under `auto`, one-file units still queue for review by default: a lone
track picking among near-tied releases (the album, its deluxe, every
compilation carrying the recording) is the kind of wrong-release risk
a person should accept deliberately. A per-library "auto-apply
confident singles" switch - beside the matching mode in the review
queue's menu - opts in, and even then singles apply themselves only at
a stricter confidence than albums. An upload or URL acquisition names
no library until import places it; the switch reaches those through
the one library that could hold the music, so on a server with several
music libraries they always queue.

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
folder picker on every platform WaxDeck builds for - the web build,
the Linux and Windows desktops, and Android, where folder access is
the system tree picker (SAF) - and drag-and-drop onto the library or
uploads screen on web and desktop. A picked folder is walked
recursively and its shape rides along, so disc subfolders survive to
the grouping step. Web and Android transfers read their file handles
in windows, so picking a multi-hundred-megabyte album never loads it
into memory.

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

Uploads accept the same extensions the scanner catalogs by default -
mp3, mpga, flac, wav, wave, ogg, oga, opus, m4a, m4b, m4r, mp4, alac,
aac, adts, wma, aiff, aif, aifc, afc, ape, wv, mpc, mp+, and mka - so
a file that uploads is a file the next scan picks up. That rules webm
out: the scanner has always skipped it, because a WebM routinely
carries video. `WAXDECK_UPLOAD_FORMATS` swaps in an
operator's own list (replacing that set, not extending it). Audible's
DRM containers (aax, aaxc) are refused by name whatever the set says -
the files are encrypted, so no format list can make them playable -
and the refusal says so instead of implying a codec gap. The health
payload reports the effective sets, and the client's pick dialogs,
folder walks, and drop zones filter against what it says, so a custom
format set filters correctly rather than being second-guessed by a
client-side mirror; the mirror remains only as the fallback for
servers older than the field, whose custom formats stay reachable
through the dialogs' "All files" group. The server-side format check
at session create is the real gate either way. A folder pick or a
drop reports DRM files it filtered out by name, and explains itself
when nothing survived the filter at all; the cover images and logs an
album folder is expected to shed are left behind without commentary.

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

Each field is edited with the control its type wants rather than a
bare text box: counts (year, track and disc numbers, seasons) take
digits only, booleans (compilation, an episode's explicit flag) are
switches, an episode's type is a closed choice over the three values
the server accepts, and genres are chips backed by a picker. An administrator's
picker lists the canonical genre tree - the vocabulary the normalizer
rewrites onto - and anyone may still type a genre as free text, which
is what the server accepts from every session. Credits are chips per
role, driven by the same per-kind role vocabulary the server
advertises: remove a name from its chip, add names under a chosen
role, and only the roles that changed are written. A track's `artist`
credit is shown but not chip-edited - the artist field is what
resolves it.

Everything on the screen stages into one draft, and the sticky save
bar at the bottom is the only thing that writes: fields, credits,
tags, lyrics (emptying the lyrics field removes them on save),
chapters, and the release status go in one press, with the bar
counting what is unsaved. Write-back failures are reported beside
that bar, where the next save is decided.

On a single-file audiobook the chapter list is part of that draft: a
row per chapter with its start stamp and title, each chapter running
to the next one's start and the last to the end of the book, plus a
restore that hands the marks back to what the file embeds. A
multi-file book keeps its part-boundary marks - they are the merge
tool's contract, not the editor's to redraw.

The catalog database is the working copy: edits land there first and
touch files only when the request opts into write-back. Edits lock
their fields by default so scans and enrichment respect curation;
locks are visible and reversible in the editor, and per-field
provenance shows who set what (file tags, a user, enrichment, or the
organizer). A write-back that fails after the catalog committed
reports per-file detail and surfaces as an out-of-sync diagnostic
rather than failing the edit. Lyrics write-back writes the `.lrc`
sidecar so corrections stay portable to every other player.

What the editor writes, listeners read. A track's tempo, its ISRC and
its MusicBrainz recording id come back on the item read, and the app's
Details sheet (any item's overflow menu) shows them beside the file's
technical facts, so a curated tempo or identifier is visible to
everyone rather than only to whoever opens the editor.

### Where a cover came from

Covers and lyrics carry the same attribution the scalar fields do:
whether they were read out of the file's own tags, out of an image or
`.lrc` sitting beside the audio, out of a podcast feed, fetched from a
metadata provider (which is named), or set by hand.

Wherever a cover is drawn large enough to carry a caption - the
artwork manager, the album, artist, book and show headers, the radio
face, and the full-screen player - a line under it says which. It is
always on and nothing hides it. The grids do not carry it, because a
48-pixel thumbnail has no room for a line and no listener reads two
hundred of them; the player pays a read of its own for the one track on
screen rather than putting provenance on every listing row.

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
an ordinary empty one, and carries a **Pin this cover** switch
wherever it is mounted, which is how the pin comes off. On a release,
an artist, or a podcast show the switch rides
`PUT /entities/{entityType}/{entityPid}/artwork/lock`; on an item it
rides the item's own `art` field lock, the same surface the scalar
locks use. Playlists are refused the entity switch: a playlist's
cover authority is its own uploaded-versus-generated marker, and
clearing an uploaded playlist cover hands the slot back to the mosaic
built from the members.

A podcast show's cover is the one entity not administrators-only:
accounts with the manage-podcasts permission set, clear, and pin it
too, through **Set cover** in the show's own menu. A hand-set show
cover is pinned, which is what keeps the next feed sync from fetching
the feed's image over it; clearing it and lifting the pin hands the
slot back to the feed, which refills on the next sync.

That mosaic marks itself. It is stored with the source `generated`, so
the source mark under it reads as the server's own composition rather
than as a picture somebody chose - which is what it read as before the
vocabulary had a word for it.

### Editing a release: the workbench

An album opens the release workbench, reached from the album's
overflow (administrators only, because barcodes and labels are shared
by everyone who can see the release). Where there is room it is two
panes with a draggable seam the client remembers: the release and its
member tracks on the left, and an editor for whatever is selected on
the right. The album row opens the release's own form; a track row
opens that track's full item editor - the same typed form, staged
draft, and save bar it has at its own location; checking several
tracks opens a bulk form over the selection. On a phone the workbench
is the track list: a track pushes its own editor, and the album and
bulk forms open as sheets. The list drives from the keyboard - j/k and
the arrows move, space checks, e opens, Escape backs out -
and never while a text field has focus.

The album form holds the cover in the same artwork grid the item
editor uses (set, clear, the source mark, and the pin), the release's
own name and handle (**Sort name** and the **MusicBrainz release
ID**), and its edition columns (barcode, label, catalog number, media,
country), each showing where its current value came from and whether
it is locked. Only the fields that changed are sent, so a one-word
correction does not lock the other six. Total tracks appears among
them as a derived number, not a field: nothing stores it - it is the
release's membership counted - so the row shows the count, marks it
derived, and says that editing the tracks is what changes it.

The album title, album artist, and year live on the tracks rather
than the release, so the album form ends with a rewrite section that
applies them to every member in one batch. Because every member moves
at once, the release is renamed in place: it keeps its entry, and its
artwork, pins, curation and play history with it. A name another
release already owns merges the two instead, and the workbench
follows the pid the response reports either way. Editing only some of
a release's members is the other case - those fork onto a new entry
and the rest stay behind - which is what the bulk form over a checked
subset does.

The bulk form works over any checked set of tracks. A field the
selection agrees on opens on that value; one it disagrees on opens
empty under a **Mixed** chip, and typing there sets it on every
track. Only edited fields ride the batch, which reports what it
edited, what it skipped for locks (a choice on the form: refuse the
batch, skip locked tracks, or override the locks), and any files
whose tags could not be rewritten. A bulk save locks every field it
writes, and one batch takes at most 1,000 items - the form says both.

### Artists and release groups

The other two catalog entities edit at the same location, by their
own pids. An artist's editor holds the artwork grid with the pin
(the picture is the artist's own), the sort name - the one artist
field that fans out to the crediting files' tags, behind the same
write-back switch - and the MusicBrainz artist ID. A release group's
holds its sort name, its MusicBrainz ID, and its type (album, EP,
single, compilation, audiobook), all database-only overrides; its
picture is its releases' and is not managed here. Both are
administrators-only, like every entity edit, and both seed from the
curation rows: a field nobody has set opens honestly empty rather
than echoing a derived value it would then offer to write back. The
doors are the artist screen's overflow and, for the release group,
the workbench's album pane; only the fields that changed are sent.

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
(key free, keyed on ASIN), fanart.tv artwork when
`WAXDECK_FANARTTV_KEY` is set, Discogs artwork and genres when
`WAXDECK_DISCOGS_TOKEN` is set, and a book ladder past Audnexus:
Hardcover bridges an ASIN to the ISBN (`WAXDECK_HARDCOVER_KEY`), and
Google Books and Open Library answer by ISBN, or by a title-and-author
search that must match both names (key free; a Google Books key only
raises its quota). Ahead of all of them ride any custom providers the
install wired through `WAXDECK_ENRICH_PROVIDER_URLS` - self-hosted
services implementing the contract in `docs/custom-provider-api/`. The
editor's per-item fetch uses the same providers for one item at a
time.

The precedence between them is one rule, and it is what makes the
key-free providers safe to run beside the identity pass. MusicBrainz
matching is authoritative for identity fields and locks what it writes,
so nothing below it can move those values. Every injected provider
writes fill-when-empty and lock-respecting: it fills a field nothing has
claimed, and never replaces a value a person, a tag, or the match put
there. Genres are the one place the order is inverted on purpose - the
injected providers are asked first, because they answer where
MusicBrainz has no genre at all - and even there a MusicBrainz genre is
never evicted.

Artist portraits come from two passes, split by whether the artist has
a MusicBrainz id. An artist matching one rides the catalog's own
enrichment pass, which asks fanart.tv and Deezer for artist art
through the same provider port everything else goes through; fanart.tv
also supplies a scenic background there, and disc art on a release
group, since it is the one provider that answers per role.

An artist with no MusicBrainz id is invisible to that pass, so a daily
background sweep (also kicked by each admin-run enrichment) covers the
remainder, asking Deezer under an exact-ish name match. It writes
fill-when-empty and pin-respecting like every enrichment write,
remembers artists with no findable image so they are not refetched
every pass (a forced enrichment run drops that memory), and skips
compilation stand-ins like Various Artists. `WAXDECK_ARTIST_ART=false`
turns off both.

That fetch previews before it applies. The editor's Fetch button asks
`POST /items/{pid}/enrich/preview` what the providers would change -
field diffs and the cover image, each naming its provider, plus the
reasons for what was skipped - and shows the answer as a sheet.
Applying passes the previewed proposal back, and the server commits
exactly those values rather than fetching fresh ones a moment later:
what was approved is what lands, with the local guards re-run so a
field locked or filled since the preview is skipped, never
overwritten. The catalog's key-free built-ins (Cover Art Archive,
ListenBrainz, LRCLIB) cannot be previewed - their fetch and write are
one engine pass - so they still run fill-when-empty when the apply
lands, and the sheet says so; an empty preview offers the fetch for
exactly that reason. The bodyless `enrichItem` stays as the blind
one-shot for older clients.
