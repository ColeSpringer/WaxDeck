# Custom enrichment providers

WaxDeck's enrichment fills artwork, genres, lyrics, scalar metadata
fields, and book metadata from pluggable providers. Besides the built-ins, an install can point
the server at any HTTP service implementing the small contract in
[`openapi.yaml`](openapi.yaml) - a regional lyrics database, a
scene-specific cover source, a house genre taxonomy - and it is asked
first unless an administrator reorders the sources.

## The contract in one paragraph

Two endpoints. `GET /capabilities` answers who the provider is (the
`name` becomes the provenance mark on everything it supplies) and which
kinds of enrichment it serves, optionally per target type.
`POST /enrich` answers one lookup: WaxDeck sends the identity hints it
holds for a target (titles, names, MBID/ASIN/ISBN/ISRC, a release's
barcode and catalog number, a track duration) and which capabilities the
answer is wanted for (`wants`), and the service answers `200` with
everything it found or `204` for a clean no-match. That is the whole
surface - it mirrors WaxDeck's in-process provider port one-to-one, so
there is no search/match handshake to implement.

## Registering a provider

```
WAXDECK_ENRICH_PROVIDER_URLS=regional=https://lyrics.lan:8080
WAXDECK_ENRICH_PROVIDER_AUTH=regional=some-long-token   # optional
```

Both take comma-separated `name=value` pairs; the auth token rides as
`Authorization: Bearer <token>` on every request. The name on the left
is the operator's label for wiring and log lines; the provenance name
users see is the one the service advertises.

WaxDeck validates each provider at startup: the capabilities document
must answer (a short retry ladder absorbs a compose boot race) and
advertise a non-empty name no other provider stamps its values with,
or the server refuses to start, naming the provider. A downed sidecar
is therefore a visible refusal rather than a silently absent provider;
under compose, `depends_on` avoids even the retries. A provider that
answers but advertises only capabilities this WaxDeck build does not
understand, or declares none for a target type it knows, is skipped
with a log line instead - that is version skew,
not misconfiguration.

The catalog's own names are taken: its built-ins' `musicbrainz`,
`coverartarchive`, `listenbrainz` and `lrclib`, and the marker labels
`musicbrainz:edition` and `none`.

## Semantics worth knowing

- Values land fill-when-empty and never over a locked field; a
  candidate may return more than was asked and WaxDeck keeps what fits.
- The `fields` capability is scalar metadata and gates two walks that
  differ only by request type: `recording` for a track's tempo, ISRC
  and composer, `release` for an album's label and year. Answer nothing
  for the rung you do not know. An album year fans out to every track
  on it, so WaxDeck refuses one where the members already disagree.
- Art is asked at the `release_group` rung for the group's picture and
  at the `release` rung for one pressing's: `cover` for an album with no
  front at all, `aux-art` for its other slots. Answer a `release` only
  when you know that pressing (by barcode, catalog number or release
  MBID); if its cover is the group's picture WaxDeck already holds, say
  `frontIsGroupFront` instead of sending the bytes again.
- Roles other than the front ride `art`, keyed `back`, `disc`,
  `booklet` or `background`; the artist-art walk reads an artist's
  picture from `art.front` (or `cover`). `artist-art` is an artist's
  portrait and background both; a provider serving one advertises
  `artist-front` or `artist-background`, and `wants` names the half a
  walk will keep.
- A provider that serves a capability only for some target types says
  so in `capabilitiesAt`, target type to capability names, and is asked
  only at those rungs; a phase runs only when some provider serves it
  at its own rung. It narrows `capabilities`: a name listed there alone
  is ignored, and an unknown target type is logged and ignored. Without
  `capabilitiesAt`, every capability is taken to be served for every
  target type.
- Images are refused over 8 MiB, as SVG, or when the bytes are not a
  recognizable image. A refused image is logged and dropped; the rest
  of the answer still lands.
- `204` is a miss: the target is marked and asked about again once the
  retry window has passed (30 days by default) or on a forced run. A
  `404` and an all-empty `200` object read the same way, though `204`
  says it explicitly.
- Anything else is a failure, not a miss: a 5xx or any other status, a
  timeout, a refused connection, a body that is not the promised JSON.
  The lookup stays owed and is asked once more on the next pass, and
  three failures in a row sit the provider out for the rest of the pass.
  Answer an
  error when unsure: a wrong `204` settles the target until the retry
  window passes.
- WaxDeck keeps no cache of enrich answers (a candidate can carry a
  whole cover inline), so caching is the service's to do; `force: true`
  asks it to bypass whatever cache it keeps.
- WaxDeck paces its calls (default 500ms apart per host) and never
  calls concurrently within one enrichment pass. Whatever the service
  itself calls out to is its own business to pace.

The server's bridge tests
(`server/internal/providers/httpbridge_test.go`) double as a
conformance reference: the stub service they drive is a minimal
correct implementation of this contract.
