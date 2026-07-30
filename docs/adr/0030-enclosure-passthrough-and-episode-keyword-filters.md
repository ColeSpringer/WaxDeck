# 30. Enclosure passthrough, and the filter that decides what gets fetched

Date: 2026-07-28

## Status

Accepted.

## Context

A podcast episode WaxDeck had not fetched could not be played at all.
Every URL-minting path refused it: play-info answered `conflict`, the
Subsonic surface withheld a `streamId`, and a cast queue containing one
errored out. The refusal came from a single place, `StreamSource`, which
resolves an item to a file on this host and had nothing to resolve.

That is a defensible answer for a server whose whole job is holding
files, and a bad one for a listener. Every other podcast client in
existence plays the enclosure straight off the feed's host and treats a
local copy as an optimization. WaxDeck had the enclosure URL sitting in
the catalog the whole time.

The second half of this ADR is the other side of the same coin. Which
episodes get fetched at all was one boolean per subscription,
`autoDownload`, applied to every new arrival. A daily show with a weekly
segment worth keeping had two settings: all of it, or none of it.

## Decision

**An unfetched episode streams by relaying its feed enclosure.** The
server proxies the podcast host's bytes through its own origin at
`GET /media/enclosure`, media-token authenticated exactly as the rest of
`/media/*` is. Play-info answers 200 with that URL; the episode still
reports `downloaded: false`, because it is not.

**The decision sits at each URL-minting site, not in `StreamSource`.**
This is the part worth writing down, because the obvious place is wrong.
`flow.Source.Path` is "the containing file's absolute path on this host",
and the bridge feeds it to `srcRef`, which maps a path onto a WaxFlow
root reference. There is no value a `Source` can carry that makes the
sidecar fetch a remote URL. So `StreamSource` and `DirectPlayInfo` keep
answering the conflict, which is their honest "there are no local bytes
here", and each of the three callers that turns an item into a URL
catches it and mints a relay URL instead: play-info (both the bridge and
the no-bridge branch), the Subsonic stream handler (both branches), and
the cast resolver's `StreamItems` (both branches). `ErrEpisodeNotFetched`
is the sentinel they match on, so the fallback fires for that reason and
no other.

**A proxy, not a redirect.** A redirect hands the listener's IP address
to the podcast host, and the web build could not play the result anyway:
cross-origin without CORS, and plain-http enclosures under an https
origin are mixed content. This is the same reasoning that moved radio
station logos to a server-side proxy.

**The target URL is resolved from the episode, never taken from the
request.** `/media/enclosure` accepts a pid and a media token and nothing
else. A caller holding a token for one episode reaches that episode's
audio and no other address, which is what separates this from an open
proxy. There is no URL parameter and there will not be one.

**Response headers are an allowlist.** `Content-Type`, `Content-Length`,
`Content-Range`, `Accept-Ranges`, `ETag`, and `Last-Modified` come back;
everything else stops at the relay. A denylist would mean a podcast
host's `Set-Cookie`, its server banner, or its next new tracking header
reaching WaxDeck clients by default, with the deny list catching up
afterwards.

**Ranges pass both ways, which is the substance of the handler.** A
listener scrubs an episode, so `Range` and `If-Range` are forwarded
upstream and 206, `Content-Range`, and `Accept-Ranges` are mirrored back.
A host that ignores ranges answers 200 and the relay carries that through
unchanged.

**`seekable` is best effort for passthrough, and the spec says so.**
Whether the host honours ranges is not knowable until the first upstream
request. Probing at mint would put a third-party round trip inside every
play-info call, so play-info reports `seekable: true` and clients degrade
if a seek fails.

**The relay invents one header and no more: `Content-Type`, and only
when the host sent none.** A response with no content type will not play
at all, and the feed's declared enclosure type is the standard answer.
Everything else is mirrored or absent. In particular the feed's declared
`EnclosureSize` is **not** used to backfill a missing `Content-Length`,
which an earlier draft of this work proposed. A host that omits it is
answering chunked, feed-declared lengths are routinely stale, and
declaring a length the relay cannot honour makes the server truncate the
body or leave the client waiting on bytes that never arrive. A missing
`Content-Length` is a benign loss; a wrong one is a broken episode. The
same argument, smaller, applies to `Accept-Ranges`: the host is the only
party that knows, and `seekable` already tells clients to try.

**A private feed's stored credentials go out with the relay, and only
for its own subscribers.** A paid or member-only host refuses an
unauthenticated GET, so a relay without them would 401 on exactly the
feeds a listener paid for, while fetching the same episode works:
WaxBin's download passes the show's `User`/`Pass` through to
`SetBasicAuth`, and so does the transcript fetch. Passthrough joins them
rather than becoming the one path that cannot read a private feed.

Spending them needs a rule, because an episode read stays open to any
caller who can see the podcast library while the credentials belong to
the show. Without a check, any account on the server could stream a paid
feed on the strength of somebody else's subscription - a real widening,
since before this an unfetched episode of such a show simply refused.
So the credentials are resolved only for a caller who subscribes; every
other caller keeps the conflict, and play-info never mints a relay URL
it knows the relay would refuse. Any subscriber shares them, which is
how they got there: they are a property of the show, set by whoever
subscribed with them, not a per-user secret.

The listener never sees them. They are set on the outbound request, the
response header allowlist has no `WWW-Authenticate` in it, and Go drops
`Authorization` on a redirect that leaves the original host, so a CDN
hop does not carry them either.

**The guarded client has no overall timeout, deliberately.** An episode
plays for an hour in real time; a client-level deadline would cut a
listener off mid-episode. The request context is the only lifetime bound.
Otherwise it is the radio client: a dialer refusing private addresses
after DNS resolution, capped redirects, and a response-header timeout.
The private-address guard follows `allowPrivateFeedHosts`, not the radio
flag, because an enclosure is a feed's own file.

**What passthrough does not carry.** The audio is never analyzed, so
silence trim and voice boost stay absent until the episode is fetched,
and the skip map stays `unavailable`. On Subsonic, `maxBitRate` and
format conversion do not apply: there is no local file for the streaming
engine to cut, so the relay is raw and the parameter is ignored rather
than silently honoured.

**An endpoint that forces an output format does not get passthrough.**
The jukebox is handed `wav` and the DLNA floor is `mp3` because those
endpoints require them - the jukebox reads a wav preamble off its input
and refuses anything else. A relay serves whatever the podcast host
sends and there is no local file to cut, so passthrough cannot satisfy a
forced format; those endpoints keep the conflict they answered before,
which names the fetch that would make the episode playable on them.
Handing them a raw enclosure would trade a clear refusal for a failure
inside the driver, the same trade the multi-part refusal beside it
already declines. Subsonic's `maxBitRate` is different and is ignored
rather than refused: it is a hint about quality, not a requirement the
endpoint cannot decode past.

**A queue containing an unfetched episode falls off the gapless timeline
path, and that is intended.** `ConnectResolver.Timeline` calls
`StreamSource` per entry and returns `nil, nil` on any error, which sends
the queue to per-item URLs. A remote enclosure cannot join a
server-minted timeline, and the degradation is already clean, so nothing
changes here. It is recorded because it is otherwise discovered as a
mystery later.

**Manual unfetch keeps its `stateReadsInUse` refusal.** Passthrough makes
the premise false for the *next* listener, but not for the current one:
the hazard the guard exists for is an in-flight sidecar session reading a
path that is about to be deleted, and that session dies mid-track whether
or not a later listener could have streamed the enclosure instead.

**`hasEnclosure` is what a client reads to decide whether to offer
play.** `downloaded` no longer answers that question: an episode that is
not downloaded still plays when the feed named audio. So the episode
summary carries both, and `downloaded` now means what it says - local
bytes, and the analysis that rides them (silence trim, voice boost, the
skip map). The one episode that cannot play at all is `downloaded`
false with `hasEnclosure` false, and that is the only one play-info
still answers `conflict` for.

**Per-feed keyword filters are a title-only term matcher.**
`SubscriptionSettings.autoDownloadFilter` carries `include` and `exclude`
term lists, matched case-insensitively against the episode title. An
empty `include` admits everything; `exclude` wins over `include`.

**Titles only, not descriptions.** Feed descriptions carry sponsor copy,
show boilerplate, and in some feeds full transcripts, so an exclude term
matched against them fires on episodes a listener would never call a
match, and the behaviour stops being predictable from the row the user is
looking at.

**Terms are bounded in characters, not bytes.** The spec's `maxLength`
counts characters, and a byte-wise cap would cut a multi-byte rune in
half and store invalid UTF-8 - which any non-English show reaches
immediately, and which yields a term that then matches nothing.

**Filters apply to future arrivals only.** Editing one does not
re-evaluate the backlog and does not unqueue anything already fetched. A
filter is a subscription policy going forward, not a query over history.

**Not the smart-list rule engine, though it exists now.** That engine is
a catalog-query rule tree evaluated against library items. This decision
happens at feed-refresh time over feed rows whose episodes may have no
catalog item yet, so a rule tree has nothing to evaluate against. A small
term matcher is the right shape and is not a stopgap.

**The union across subscribers is preserved.** Auto-download enqueues an
episode when *any* subscriber with `autoDownload` on has a filter that
admits it, matching the rule retention already documents: the effective
policy for a show is the most generous union across its subscribers.

## Consequences

Play-info's 409 now means one thing rather than two: an episode whose
feed named no enclosure at all. Two tests that pinned the old contract
moved in the same change, one in the integration suite and one in the
e2e podcast journey, and the e2e journey now asserts a ranged read
through the relay.

Subsonic clients get a `streamId` on unfetched episodes, so a show
browses and plays before anything is downloaded. The status still reports
the download state, which is what keeps a client's download button
honest about what is held locally.

A listener now has three states rather than two: not fetched and playing
from the host, not fetched and unplayable (no enclosure), and fetched
with analysis. The middle one is small and the spec names it.

Filters add two nullable columns to `podcast_subscriptions` and one
matcher with a table test. The cost of the title-only choice is that a
listener who wants to filter on a description cannot; the benefit is that
what the filter does is visible from the episode list.

**Delete `data/waxdeck.db` before running this build.** The two columns
are an in-place edit of the baseline schema, which is what this repo's
pre-release policy asks for: `user_version` stays 1 and the fingerprint
guard in `migrate` turns an older database into a clear boot-time refusal
rather than a later "no such column". Every existing development database
trips it.

The relay is a new public surface, so two of its properties are worth
stating rather than leaving to be rediscovered. A `HEAD` reaches it,
because Go's `ServeMux` routes `HEAD` to a `GET` pattern and cast
renderers, DLNA devices, and Safari all probe with one; it answers
headers and never pulls the body, which would otherwise fetch a whole
episode to throw away. And it has no concurrency or byte bound, matching
`/media/radio/{pid}`, which is recorded in `docs/deferred-work.md` rather
than solved here: both need the same shape of fix and neither is an open
proxy, since the URL comes from a feed or station the user chose.
