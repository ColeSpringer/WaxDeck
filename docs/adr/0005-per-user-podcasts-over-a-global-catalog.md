# 5. Per-user podcasts over a global catalog

Date: 2026-07-18

## Status

Accepted

## Context

The catalog engine stores podcast shows, episodes, and downloaded
files once, with no user dimension: subscriptions there are a single
library-wide list, retention is a per-show keep-newest-N, and the only
per-user state it holds is playback state. WaxDeck promises multi-user
podcasts: two people follow different shows (or the same show) with
their own settings, retention resolves generously across households,
and private feed URLs never leak.

Three design points needed a decision:

1. Where the per-user subscription dimension lives.
2. How per-user retention preferences reconcile into the catalog's
   single per-show policy, and who deletes files.
3. What "private feed" means when the show itself is shared.

## Decision

Shows, episodes, and files stay global in the catalog; subscriptions
are rows in WaxDeck's own database (user, show, settings), and every
user-facing surface is a per-user view over the shared catalog.

Retention resolves as the most generous union across a show's
subscribers: any keep-all wins, otherwise the largest keep-N. WaxDeck
pushes the union into the catalog's per-show policy and drives the
sweep itself, on a queue, never inline with a request. The sweep
protects episodes starred by any subscriber or sitting in any
subscriber's queue by pinning them (the catalog's own retention
exemption, written as a full-fidelity re-upsert so nothing else
changes), and defers a show whose candidate files look actively
played. Removing a file never removes history: the catalog's
archive-preserve guarantee is upstream-tested, and an invocation guard
here asserts positions survive a sweep.

A show with zero subscribers keeps its files. Removing a show from the
catalog cascades away every user's play history for its episodes, so
destructive cleanup is an explicit administrative act, never a side
effect of the last unsubscribe.

Amendment: the last unsubscribe may opt in to reclaiming the show's
downloaded audio (`removeDownloads` on the unsubscribe call). This is
not the destructive cleanup above: the files move to the library
trash, restorable and re-fetchable, episodes stay browsable, and no
play history is touched. The flag is honored only when the caller was
the show's final subscriber (otherwise the remaining subscribers'
retention owns the files and it is ignored), and files that read as
actively played are skipped. Field use showed the alternative was
stranded files: once the last subscriber leaves, the per-episode
remove endpoint is subscriber-gated and nothing else reclaims the
space.

Show privacy is global and sticky: a show becomes private when it is
first subscribed with credentials or when any subscriber ever flags
their subscription private, and it never becomes public again. Private
means the feed URL (which for tokenized feeds is the secret itself)
appears in no API response and no OPML export, for any user. It does
not hide the show's existence or content from users who can see the
podcast library. Credentials are stored once per show, sealed through
the catalog's injected cipher; the last supplied set wins, and
re-subscribing with credentials is the rotation path.

The gpodder compatibility surface is the one deliberate exception to
URL hiding: it returns the caller's own subscription list as feed
URLs, private ones included, because that list is the entire point of
a credentialed per-user sync protocol and third-party apps cannot
function without it.

## Consequences

Subscription reads join two databases by PID, dangling-tolerant like
every other cross-database reference. The refresh scheduler and its
failure accounting live in WaxDeck (the catalog keeps validators but
no failure state). The union sweep re-derives from subscription rows
every cycle, so it is idempotent and crash-safe by construction. A
household that wants files gone faster must lower every subscriber's
keep-N, which is the intended reading of "most generous union".
