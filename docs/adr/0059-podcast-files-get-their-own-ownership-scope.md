# ADR-0059: Podcast files get their own ownership scope

Status: accepted

## Context

An episode's audio has always sat in an internal library the catalog
manages but nobody browses as a folder. Until now that distinction was
convention: the files were ordinary catalog rows, so every verb that
acts on a file - delete, trash, restore, the upgrade resolver - reached
them, and the only thing keeping a user from trashing an episode was
that no screen offered it.

ADR-0052 already found the first cost of that. `RemoveEpisodeDownload`
deleted through the catalog, every delete mode archives an item on
losing its last file, and the show's unplayed count stopped matching its
own episode list. The fix was to route the one verb through
`podcast.Service.Unfetch`, which drops the file and keeps the episode.
That left the other verbs untouched and one gap open: `Unfetch` took no
file-mutation lease, so it could unlink a file a retention pass was
walking.

Upstream has now closed both halves, and not the way the ask was
written. The request was to run `Unfetch` under `fs-mutate`, the scope
that serializes scan, organize, and delete. What shipped is a second
scope, `podcast-fs`, and a set of refusals: `PlanDeletePIDs` rejects an
episode outright, the query-driven `PlanDelete` skips episodes and
reports the count, and `RestoreTrash` refuses a target under a podcast
root.

## Decision

The download tree owns its files, and WaxDeck stops pretending
otherwise on every surface.

**Two scopes rather than one.** A separate `podcast-fs` lease is the
better shape and the reason is throughput. The verbs that contend for
podcast files are each other - an unfetch, a retention apply, a
download's commit tail - and they are all brief. Folding them into
`fs-mutate` would have made every episode download wait behind a library
scan that cannot touch the file it wants. The scopes nest in a fixed
order (`fs-mutate` then `podcast-fs`) for the one import path that needs
both, so they cannot deadlock.

`catalog-busy` therefore describes two scopes now, not one. That is the
right generalization: what the code means is "a shared file-mutation
scope is held, wait and retry", and which scope it was is not something
a client can act on differently. `DELETE /episodes/{pid}/fetch` answers
it again, and the handler arm ADR-0052 left dead is live.

**Unsubscribe cleanup reclaims through `Unfetch`.** Adopting the bump
without this would have regressed silently: `removeShowDownloads` called
`PlanDeletePIDs`, which now refuses, so the cleanup would have logged a
warning and stopped reclaiming anything. It loops `Unfetch` per episode
instead, which is what unsubscribe wanted all along - bytes gone, record
and play state kept, episode re-fetchable. The loop runs on a context
detached from the request, because the unsubscribe has already committed
by then and a client disconnect must not strand half a cleanup.

A contended file gets a short bounded retry and is then skipped with a
warning, the same posture as the in-use skip beside it. This is worth
stating plainly because nothing sweeps a skipped file up later:
`sweepShowRetention` returns early once a show has no subscribers, by
design, so the file waits for an explicit unfetch. That is an accepted
leak of bytes, not an oversight, and it was already true of the in-use
case.

**Both catalog delete surfaces refuse an episode in WaxDeck's own
words.** `/library/items/delete` and the upgrade resolver would
otherwise reach the catalog's refusal and read it back to the caller as
"use `podcast unfetch`", naming a CLI verb this server does not expose.
Both refuse before planning, with the same message, and the whole list
is refused when one pid names an episode - matching the catalog rather
than silently dropping items from a call the caller thought covered
them. Neither auto-routes to `Unfetch`: that is a different contract,
with no undo journal and a subscription gate, and inferring it from a
delete would be the kind of helpfulness that deletes the wrong thing.
The tool paths (book merge, book split, cue split) need no guard, since
only `bk-` and `tr-` items reach them.

**Legacy trashed episodes leave by purge, not by restore.** Real
libraries have them, because until this change unsubscribe and
items-delete both trashed episode items. Upstream's purge paths are
unchanged, so `EmptyTrash`, per-entry purge, and age expiry still clear
them; only restore refuses, and re-downloading the episode is the way
back. The admin trash screen hides Restore on those rows rather than
drawing a button that always fails - the hidden-never-disabled rule -
and keeps Purge. The player's "Delete files" row is hidden for episodes
for the same reason: "remove download" is the episode's equivalent and
lives on the episode's own surfaces.

## Consequences

An episode is now the one item kind whose file the catalog's delete
cannot touch, which is a rule worth knowing before adding a surface that
deletes things in bulk. New delete paths need the same guard, and the
shared `errEpisodeNotDeletable` exists so they read identically.

Retention gained a deferral it did not have. A busy `podcast-fs` lease
re-queues the show and tries next cycle, mirroring the in-use deferral
above it; the download worker needed nothing, since its commit tail
already waits the lease out and a loss past that budget rides the
existing fetch backoff.

The e2e retry helper's subject widened. It was written for one lease and
now wraps two, which changes nothing about how it works: the refusal
code is the same and so is the reason it clears.
