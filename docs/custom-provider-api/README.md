# Custom enrichment providers

WaxDeck's enrichment fills artwork, genres, lyrics, scalar metadata
fields, and book metadata from pluggable providers. Besides the built-ins, an install can point
the server at any HTTP service implementing the small contract in
[`openapi.yaml`](openapi.yaml) - a regional lyrics database, a
scene-specific cover source, a house genre taxonomy - and it joins the
chain ahead of every built-in provider.

## The contract in one paragraph

Two endpoints. `GET /capabilities` answers who the provider is (the
`name` becomes the provenance mark on everything it supplies) and which
kinds of enrichment it serves. `POST /enrich` answers one lookup:
WaxDeck sends the identity hints it holds for a target (titles, names,
MBID/ASIN/ISBN/ISRC/barcode, a track duration), and the service answers
`200` with everything it found or `204` for a clean no-match. That is the whole
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
advertise a non-empty name, or the server refuses to start, naming the
provider. A downed sidecar is therefore a visible refusal rather than a
silently absent provider; under compose, `depends_on` avoids even the
retries. A provider that answers but advertises only capabilities this
WaxDeck build does not understand is skipped with a log line instead -
that is version skew, not misconfiguration.

## Semantics worth knowing

- Values land fill-when-empty and never over a locked field; a
  candidate may return more than was asked and WaxDeck keeps what fits.
- The `fields` capability is scalar metadata and gates two walks that
  differ only by request type: `recording` for a track's tempo, ISRC
  and composer, `release` for an album's label and year. Answer nothing
  for the rung you do not know. An album year fans out to every track
  on it, so WaxDeck refuses one where the members already disagree.
- Covers are refused over 8 MiB, or when the bytes are not a
  recognizable image.
- A non-200/204 answer is treated as transient: logged, skipped,
  retried on a later enrichment pass. Don't answer `404` for "no
  match" - that also reads as a miss, but `204` says it explicitly.
  An all-empty `200` object reads as a miss too.
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
