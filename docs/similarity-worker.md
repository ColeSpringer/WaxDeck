# Sonic analysis and the similarity worker

Sonic discovery runs on per-track audio embeddings. By default the
server computes them itself: the embedded analyzer works through the
library in the background, paced so it never competes with playback,
and there is nothing to install or configure. Analysis is
incremental: new tracks join the queue half a minute after a scan goes
quiet (a long scan is swept every ten minutes as it runs), and
identical audio never re-analyzes (embeddings are keyed by the audio
essence hash, which survives retags and moves; a track carved out of a
shared file by a cue sheet adds its window to that key). Until a track
is analyzed, discovery answers with metadata heuristics, so nothing
waits on coverage.

Watch progress in the app's settings, or at
`GET /api/v1/similarity/status`: coverage percentage, queue depth,
and the stored model. Coverage is over music long enough to analyze,
less any audio the analyzer found it cannot read, so it reaches 100%
once every other track has its vector. Administrators turn analysis
on and off with the Sonic analysis switch in the server settings; it
applies immediately, no restart. `WAXDECK_SONIC_ANALYSIS` only seeds
the default before an administrator first touches the switch.

## Offloading analysis to a worker

Installs that want the analysis CPU somewhere else (a NAS keeping its
fans quiet, a desktop with cycles to spare, a GPU box running a
heavier model) can hand the job to an external worker instead:

1. Set `WAXDECK_WORKER_TOKENS` on the server (any random string;
   comma separate several for rotation) and, usually, flip Sonic
   analysis off in the server settings so the server stops analyzing
   itself.
2. On the other machine, download `waxdeck-analyzer_<version>_<os>_<arch>`
   from the release (it sits beside the server archives) and run it:

   ```sh
   WAXDECK_ANALYZER_URL=http://your-server:4420 \
   WAXDECK_ANALYZER_TOKEN=<one of WAXDECK_WORKER_TOKENS> \
   WAXDECK_ANALYZER_FORMAT=flac \
   ./waxdeck-analyzer
   ```

   One static binary, no dependencies; keep it running under systemd or
   whatever the machine uses. From a clone, `go build ./cmd/waxdeck-analyzer`
   in `server/` builds the same thing.

The reference worker computes the same embedding as the embedded
analyzer, so switching between them never restarts coverage.

## The worker contract

The worker API is deliberately small, so implementations are
interchangeable: the shipped reference worker, a heavier model on a
GPU box, or anything else that can decode audio and emit a vector.
Three endpoints, all authenticated with a server-configured worker
token (`WAXDECK_WORKER_TOKENS`, comma separated for rotation) as a
bearer:

1. `GET /api/v1/similarity/work?limit=` leases a batch of tracks
   awaiting analysis. Each item names the track, its analysis key,
   and where to pull audio; a track that no longer holds the audio its
   key names is never handed out. Leases expire on their own, so a
   crashed worker needs no cleanup; work leased over and over without
   a vector filed rests, and is queued again after a week. An empty
   batch only means nothing can be handed out now: coverage may be
   complete, or the rest of the queue is leased, the streaming engine
   is not answering, or the catalog is handed to a maintenance
   operation.
   Sleep `retryAfterSeconds` and poll again. A hand-off that begins
   while the batch is read answers `503` `catalog-maintenance`; back off
   and poll again.
2. `GET /media/analysis/{pid}?format=wav|flac` serves decode-ready
   audio: 16 kHz mono, gain untouched, and for a carved track only
   its own window of the file. WAV is the loopback default;
   remote workers request FLAC for losslessly identical input at
   roughly half the bytes. Needs the streaming engine.
3. `POST /api/v1/similarity/embeddings` records a batch:
   `{model, dims, embeddings: [{pid, essence, vector}]}`. Echo the
   work item's key as `essence` (it is opaque); the server normalizes
   vectors and maintains the neighbor graph at ingest. A vector can be
   refused alone, listed in `rejected` with its code:
   - `invalid-request`: malformed, the wrong length for `dims`, or all
     zeros. The work stays leased and comes back in a later batch once
     its lease lapses.
   - `not-found`: the track no longer holds the audio the key names (it
     was rewritten, replaced, re-cut, trashed, or left the library). Its
     work is dropped; do not send the vector again.
   - `internal`: the server could not read its catalog to check the
     vector. The work comes back in a later batch once its lease lapses.

   During a catalog hand-off a report answers `503`
   `catalog-maintenance`. The vectors filed before the hand-off began
   stand, and sending the report again once the catalog is back is safe:
   a filed vector only replaces itself.

Rules of the contract:

- One model at a time. Vectors of different models never compare, so
  posting a new `model` tag drops stored vectors of the old one and
  coverage restarts. Version your model tag; never change what a tag
  computes.
- Vectors must be deterministic for identical audio.
- Only music tracks are analyzed, cue-carved ones included: each is
  analyzed over its own window of the shared file.

## Same-host mode

A worker on the server's own host can skip the HTTP audio pull: set
`WAXDECK_WORKER_LOCAL_PATHS=true` on the server and mount the library
read-only into the worker. Work items then carry a library-relative
`localPath` and the worker decodes the original file itself, except
for cue-carved tracks, which always come over HTTP. Only
meaningful for single-root libraries; multi-root setups use the HTTP
pull regardless.

## Scale honesty

Similarity search is a brute-force scan over the vectors, in memory.
At a hundred thousand tracks and a couple hundred dimensions that is
milliseconds per query and well under 100 MB of memory, which is why
there is no approximate index to install, tune, or corrupt. Paths ride
the precomputed neighbor graph instead of scanning. If profiling on a
real library ever demands an index, that is an internal change behind
the same API.
