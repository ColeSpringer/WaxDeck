# Sonic analysis and the similarity worker

Sonic discovery runs on per-track audio embeddings. By default the
server computes them itself: the embedded analyzer works through the
library in the background, paced so it never competes with playback,
and there is nothing to install or configure. Analysis is
incremental: new tracks queue as they are scanned, and identical
audio never re-analyzes (embeddings are keyed by the audio essence
hash, which survives retags and moves). Until a track is analyzed,
discovery answers with metadata heuristics, so nothing waits on
coverage.

Watch progress in the app's settings, or at
`GET /api/v1/similarity/status`: coverage percentage, queue depth,
and the stored model. Administrators turn analysis on and off with
the Sonic analysis switch in the server settings; it applies
immediately, no restart. `WAXDECK_SONIC_ANALYSIS` only seeds the
default before an administrator first touches the switch.

## Offloading analysis to a worker

Installs that want the analysis CPU somewhere else (a NAS keeping its
fans quiet, a desktop with cycles to spare, a GPU box running a
heavier model) can hand the job to an external worker instead:

1. Set `WAXDECK_WORKER_TOKENS` on the server (any random string;
   comma separate several for rotation) and, usually, flip Sonic
   analysis off in the server settings so the server stops analyzing
   itself.
2. Run the `waxdeck-analyzer` image (published alongside the server
   images) anywhere that can reach the server, with
   `WAXDECK_ANALYZER_URL` pointing at it and
   `WAXDECK_ANALYZER_TOKEN` set to the same token. The compose
   template in `deploy/` carries a ready-made service for it under
   the `similarity` profile.

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
   awaiting analysis. Each item names the track, its essence hash,
   and where to pull audio. Leases expire on their own, so a crashed
   worker needs no cleanup. An empty batch means full coverage; sleep
   `retryAfterSeconds` and poll again.
2. `GET /media/analysis/{pid}?format=wav|flac` serves decode-ready
   audio: 16 kHz mono, gain untouched. WAV is the loopback default;
   remote workers request FLAC for losslessly identical input at
   roughly half the bytes. Needs the streaming engine.
3. `POST /api/v1/similarity/embeddings` records a batch:
   `{model, dims, embeddings: [{pid, essence, vector}]}`. Echo the
   essence from the work item; the server normalizes vectors and
   maintains the neighbor graph at ingest.

Rules of the contract:

- One model at a time. Vectors of different models never compare, so
  posting a new `model` tag drops stored vectors of the old one and
  coverage restarts. Version your model tag; never change what a tag
  computes.
- Vectors must be deterministic for identical audio.
- Only music tracks are analyzed. Virtual tracks carved from a shared
  file by a cue sheet are excluded (they share the backing file's
  essence).

## Same-host mode

A worker on the server's own host can skip the HTTP audio pull: set
`WAXDECK_WORKER_LOCAL_PATHS=true` on the server and mount the library
read-only into the worker. Work items then carry a library-relative
`localPath` and the worker decodes the original file itself. Only
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
