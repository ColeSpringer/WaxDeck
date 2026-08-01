# 28. The rolling queue window

Date: 2026-07-28

## Status

Accepted. Supersedes the rejected consequence recorded in ADR-0019's
status: the cap's windowing is no longer the final answer for an
ordered list, and both draws now refill.

## Context

The local queue holds at most 500 entries (ADR-0019), which mirrors the
server's Connect session cap so a queue can always be handed to an
endpoint whole. A scope larger than that is windowed rather than
refused. Until now the window was also the end of it: starting a
5,000-track genre at its first track played 500 and stopped, with 4,500
tracks the listener had asked for silently out of reach. ADR-0019
recorded that as deliberate for the ordered case and anticipated a
refill only for a rolling shuffle. It is not what the product wants - it
is the truncation the cap exists to avoid, moved one screen later - and
the shuffled half had no producer either, because nothing in the app
minted a shuffled window until this phase's Shuffle buttons.

So both draws want the same thing: a way back to the scope the window
was cut from, and a draw against it as the window drains.

## Decision

**The source travels with the queue, and knows where it stands.**
`QueueSource` grows three fields beside its kind and label: `rolling`
(this queue is a window over something larger), `cursor` (where the
source's own listing stands at the queue's frontier), and `seed` (the
permutation a random draw walks). All three persist: the mirror's
`queue_meta` already carries a `sourceCursor` column, and the seed rides
in front of the cursor in it, because a cursor issued under one seed is
invalid under another and the two are the same fact - where the listing
stands. A cursor is base64url, so the separator can never appear in one.

**A pager turns a source back into pids.** `QueueSourcePager` is the
port; the repository implementation knows how each source lists itself -
a bucket is a facet drill, the whole library is a browse list, a
playlist is its own members endpoint. Sources with no listing behind
them (a mix, a search, one item tapped on its own) answer null, and the
window is sealed rather than left claiming there is more.

**The refill is a third piece, not a fourth job for either.**
`QueueRefiller` watches the queue drain and draws when fewer than ten
entries remain unplayed. The queue controller stays a pure state machine
with no I/O; the pager stays I/O with no queue semantics. A draw appends
through `appendWindow`, which reuses the eviction rule ADR-0019 already
ships: history goes first, the entry playing is never evicted, and the
arrivals it just added are spared.

**Draw size is a hundred, not a cap's worth.** The draw lands on a queue
that is nearly full, so every entry it adds evicts an older one. A
cap-sized draw would leave the queue with no history at all - the
"Previously" strip empty a moment after a track ends. A hundred is
several hours ahead and leaves most of the queue to what was played.

**Two ways to find a place in the source, and the ordered window needs
both.** A caller's cursor names where its listing stands, which is the
queue's frontier only when the queue took everything the caller had. A
shuffled window is a sample of the whole loaded list, so the caller's
cursor is exactly right. An ordered window is a contiguous run, and one
cut short of the caller's last item ends inside the list: resuming from
the caller's cursor would step over everything between. So the cursor is
dropped there, and the draw finds its place by the entry at the frontier
- the last one taken from the scope, in the order the scope handed them
over - paging the source from its head until it passes that pid. That
costs a page per cap's worth of scope passed, on the one path that needs
it, and it is exact where a stale cursor would not be. A draw never
re-adds what the queue already holds, so a frontier moved by a hand
reorder costs an overlap rather than a duplicate.

**A shuffled window over a bucket shuffles what arrives, page by page.**
The contract offers a random list over the whole library
(`list=random` with a stable seed) and none scoped to a facet. So
"Shuffle all music" from the tracks index seeds from a random page and
walks that permutation, which is a real shuffle; a shuffled artist or
genre pages its bucket in listing order and shuffles each arriving page
among itself. The cost is that a shuffled 5,000-track genre hears a
shuffle of its first 500 before it hears a shuffle of its second 500.
The fix is a facet filter on the browse endpoint, which needs WaxBin's
`read.BrowseOptions` to take one; it is filed in
`docs/upstream-requests.md` with this workaround recorded beside it.

*Amended 2026-07-31: it landed.* `read.BrowseOptions.Query` arrived
upstream, `GET /library/browse` took `facet`/`facetKey` scoped by the
same filter the bucket's own listing uses, and a seeded bucket source
now draws `browse(random, facet:, facetKey:, seed:)` instead of paging
the listing. A shuffled bucket is one permutation over the whole of it,
whatever its size. See ADR-0040.

The first window is a page the Shuffle button draws for itself, not the
list the screen happens to have scrolled into memory. Sampling an
accumulated list drops whatever it did not sample - the queue cannot
hold it, and the cursor beside it points past all of it - so a visitor
who scrolled a 5,000-track genre before pressing Shuffle would lose
everything they scrolled past. One page is exactly one window's worth,
and the cursor that comes with it is that window's frontier, which is
what makes the coverage claim above true rather than nearly true.

**The window says so on screen.** `QueueSource.rolling` was declared and
captioned by the queue surface before anything set it; now the play
verbs set it, and the refiller clears it when the scope runs out, so the
caption is true in both directions.

## Consequences

A queue over a scope larger than the cap keeps playing. Connect sees the
window move, because the endpoint controller already reports on queue
changes and a refill is one. A restore resumes the draw rather than
restarting it, since the cursor and the seed persist with the queue.

A failed draw waits for the current entry to change before trying again:
a failure is usually the network, and the next queue edit is often the
same second. The visible cost of a draw that never succeeds is the
behaviour this ADR replaces - a queue that ends at its window - which is
not worth taking anything down for.

Refills are bounded per drain (five draws), so a scope with a long run of
pages that filter down to nothing does not get walked to its end while
somebody waits for the next track, and a marker the source no longer
holds seals the window after forty pages rather than paging forever.
