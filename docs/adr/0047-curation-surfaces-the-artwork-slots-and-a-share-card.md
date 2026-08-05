# 47. The curation surfaces, the artwork slots, and what a share card is

Date: 2026-08-04

## Status

Accepted.

## Context

Seven surfaces were still on the old shell after the console landed: the
review queue and its entry, health and its issue drills, diagnostics,
the metadata editor, organize, and uploads. They are the screens
somebody uses while doing something to the library rather than while
listening to it, and they had grown the same way the admin surfaces had
- each in the slice that needed it, each deciding its own chrome.

Three things had to be decided rather than merely restyled.

**A review entry has no width of its own.** The queue is the flagship
keyboard surface: j and k move a cursor, a, s, and u decide the row
under it, e opens it. Opening it replaced the queue with a page, which
means the keys stop working exactly when the reviewer has the entry in
front of them. On a desktop there is room for both, and the layout
system already says details swap the content pane above sidebar width.

**The artwork model has been five slots since ADR-0014 and the editor
could only say whether one of them was inherited.** `art-roles` reads
what an entity holds at its own level, `PUT`/`DELETE /items/{pid}/
artwork?role=` write any of them, and nothing in the app called either.
The editor showed one line: has its own cover, inherits one, or has
none.

**A year-in-review card is an image, and nothing in this app has ever
made one.** The recap answers data; rendering something shareable from
it is client work with a platform question underneath - a browser
downloads a file, a desktop writes one, and a phone has neither of those
as a useful answer.

## Decision

### The review entry is a pane, and still a location

`/admin/review` and `/admin/review/:entryId` sit under one `ShellRoute`
that builds a single `ReviewSurface` for both. Where there is room the
queue keeps its rows, its scroll position, and its keys while the entry
fills a pane beside them; where there is not, the entry is the page.
The entry keeps its own location either way, so `e` moves the address
bar and a link to an entry opens it.

The shell is what makes the promise true. Declaring the entry as a
nested route stacks a second surface over the first, with a fresh state
scrolled to the top - the queue is "kept" only in the sense that it is
still mounted underneath, unreachable. For the same reason the list
holds one position in the widget tree whether or not the pane is open:
moving it rebuilds its `Scrollable`, and a new scroll position starts at
the top of a queue somebody had scrolled. Leaving the entry is a move
back to the queue's location rather than a pop, because there is one
page.

Which candidate an entry is decided against is shared state, not the
pane's own. The pane's Approve and the queue's `a` are on screen
together and act on the same row, so a private selection would have them
approve different releases with no warning.

The keyboard contract carries over verbatim - the same bindings, the
same handles, `review-queue.spec.ts` unmodified - because the phase
brief is chrome and the keys are not chrome. The one addition is that
the cursor follows the pane: a row opened by tap becomes the selected
row, or the next j resumes from wherever the cursor was left and the
pane jumps somewhere unrelated.

Which arrangement to draw is measured, not read off the window's size
class. This screen sits inside the shell's sidebar *and* the console's
section list, which take nearly 500 pixels before it starts, so an
840-pixel window - the width at which the class says "sidebar" - leaves
it under 400 to work with and a pane would have negative width.

Selection mode announces itself through the row rather than through a
tick beside it. `WaxTappable` excludes the semantics of everything
under it, so a checkbox inside would report nothing at all; the row's
own `selected` carries whether it is checked, and the glyph beside it
is a picture of that.

The queue's list is not a `WaxTable`. Keyboard selection scrolls by
arithmetic over a fixed row extent, which needs a `ListView.builder`
with an `itemExtent` and a scroll position of its own; the table builds
its rows eagerly, which is what buys the compact card fallback and is
the opposite of what a paging queue wants. The screen is a filling
sliver rather than a scaffold body for the same reason: a body is handed
unbounded height, and the list under it would build every row it has.

### A tappable table row keeps its controls outside itself

`WaxTable`'s row wraps its cells in a `WaxTappable`, which reports the
row as one button and excludes the semantics of everything under it.
Any control drawn *in* the row - health's Fix button, a rescan, an
overflow menu - therefore had no handle of its own and no way to be
reached by anything but a sighted pointer. The trailing slot and the
compact card's detail button now sit beside the tappable region rather
than inside it. Nothing had noticed because the one table with a
trailing control had no row tap.

### Diagnostics pages by a button

The table draws its rows eagerly, so the scroll listener that used to
append a hundred rows whenever the page neared its end would keep
growing a frame nobody asked to grow. "Load more" is the verb, and the
caption says there is more. This is a deliberate trade of a paging
gesture for a bounded frame on the one console surface that can hold
tens of thousands of rows.

### The artwork manager is a grid of five slots

Every role gets a tile: what is in it (format and pixel size, read from
`art-roles`), whether it is the entity's own, and the two verbs. Front
is the only role that walks the album and artist chain, so it is the
only one that can read *inherited* - and a slot the item does not own
has nothing to clear, because that image belongs to the album and an
album is not edited from here. Clearing asks for the word back
(`showTypedConfirm`), because the bytes go.

Replacing a slot cannot be seen without help: artwork lives at one URL
whatever it holds and the response is cacheable for a day. The store
already owns that - `evict` notes the URL replaced and asks for it under
a fresh `v` everywhere - so the manager calls it and adds no bust of its
own. A counter here would have busted a URL only this screen draws,
leaving the canonical one the rows and the deck bar render untouched.
`artUrlFor` grew `role`, which keeps the URL where the rest of the
contract's paths live.

Images are read whole into memory, unlike an upload: the endpoint takes
one body and enforces 16 MiB, so the manager checks the size before
transferring rather than after. Drag-and-drop is the existing
`AudioDropArea` with an image extension set and a handle per slot.

### The metadata editor stays pushed

It is opened from a review entry's track row, from a book, and from the
lyrics view. A location declares one parent; this one has three
ancestries and therefore none, which is exactly the `push` half of the
routing rule. This closes the second of the two entries P6 opened about
routes that could not `go` - the episode took the other answer in P12
(ADR-0032) by putting its show in the path, and there is no equivalent
here: no path could name all three callers.

### Share cards are rendered from the preview

Both shapes are 1080 wide - 1080 x 1920 for a story, 1080 x 1080 for a
post - and the card is laid out at those pixel dimensions with every
size on it a fraction of the 1080. The export captures the preview's own
repaint boundary, which sits *inside* the `FittedBox` that shrinks it:
the boundary wraps the card at its full layout size and the shrinking is
a transform above it, so what comes out is the export size from a
subtree that is genuinely on screen. Mounting a second full-size copy
off the side of the sheet was the first attempt and is exactly what a
repaint boundary cannot capture - a subtree nothing painted has no layer
to hand over.

Nothing on a card is fetched. No artwork, no logo request: a card
renders the same offline as online, in one frame, and the recap's own
numbers are the whole content. Text scaling is pinned off inside it: an
exported image is not something the viewer is reading at their own size,
and every glyph is a fraction of a 1080-wide box that cannot grow.

The export captures the preview's boundary, so the previews are a
scrolled `Row` rather than a lazy list - a child scrolled out of a
`ListView` is neither built nor painted, and a repaint boundary that
painted nothing has no layer to hand over.

### `ShareCardExporter` is a port, and Android gets a channel

Keeping a finished image is the platform question, and the three answers
differ enough to be three implementations behind one interface. The
browser downloads a blob. A desktop writes into the downloads directory
(temp in the target directory, fsync, verify, atomic rename) and the
outcome says where. Android hands it to the share sheet over the
`waxdeck/share` channel this app already owns for share-sheet *intake*,
through a `FileProvider` scoped to one cache directory - a file in
app-private storage is a file nothing else on the phone can open, so
saving one there and reporting a path would be a feature that does
nothing.

No plugin. The Android half is forty lines of Kotlin on a channel that
existed, which is cheaper than a pinned dependency and its port.

## Consequences

`WaxTextField` grew `maxLines`. The design system had no multiline
input, and the LRC editor is the first caller; above one line the field
takes the card radius and drops its clear button, because a paragraph is
not something one press should throw away.

The lyrics pane counts what is timed. The server takes the text as
typed, so a line whose stamp did not parse silently becomes an unsynced
line, and the preview is the only place that is visible before saving.

Every one of these screens now raises its messages through the shell
messenger rather than a local `ScaffoldMessenger`, which is what lets a
widget test read them off the container instead of hunting for a
snackbar.

The Android share path is not verified. There is no device here and no
Android build in CI, so the Kotlin, the manifest provider, and the
`file_paths.xml` scope are unexercised; the entry in
`docs/deferred-work.md` names what to check. Everything else - the
render, the PNG's declared dimensions, the web download's shape - is
covered by the widget suite, which encodes a real card through
`runAsync` and reads its size back out of the IHDR.

The phase's own e2e run surfaced three defects that predate it, all in
`docs/bugs.md`: the console draws no section list at the e2e viewport,
a connect session row reports a rect its click cannot reach, and the
suite's `typeInto` helper verifies the DOM rather than the app, so a
form can submit with a field the helper called filled. The last is why
the suite has been unreliable locally and quiet in CI, where two
retries absorb it.

Two deferred entries close: the multi-slot artwork editor and
share-card image export. Two open: the card draws no artwork, so a
top-artists card is a list of names rather than a mosaic (the route to
covers wants the store's `bytesFor` threaded through a render that
currently takes one frame and no network), and the Android share path
is hardware-gated as above.
