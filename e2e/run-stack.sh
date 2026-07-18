#!/usr/bin/env bash
# Launches the end-to-end playback stack for playwright: synthesizes the
# fixture library (no binary media in git), builds and starts the WaxFlow
# streaming sidecar, then execs the waxdeck server binary (built by
# `make build` beforehand) so playwright owns the process tree.
set -euo pipefail

E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$E2E_DIR/.run"

rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR"/{library,waxdeck-data,waxflow-data,waxflow-cache}

(cd "$E2E_DIR/../fixtures" && go run ./cmd/fixturegen -out "$RUN_DIR/library" -preset all >/dev/null)
(cd "$E2E_DIR/../server" && go build -o "$RUN_DIR/waxflow-catalog" ./cmd/waxflow-catalog)

WAXFLOW_ADDR=127.0.0.1:4418 \
WAXFLOW_ROOTS="lib=$RUN_DIR/library" \
WAXFLOW_DATA_DIR="$RUN_DIR/waxflow-data" \
WAXFLOW_CACHE_DIR="$RUN_DIR/waxflow-cache" \
WAXFLOW_API_KEYS=e2e-test-key \
	"$RUN_DIR/waxflow-catalog" server &
SIDECAR=$!

WAXDECK_DATA_DIR="$RUN_DIR/waxdeck-data" \
WAXDECK_LIBRARY_ROOTS="lib=$RUN_DIR/library" \
WAXDECK_FLOW_URL=http://127.0.0.1:4418 \
WAXDECK_FLOW_API_KEY=e2e-test-key \
	"$E2E_DIR/../server/waxdeck" &
SERVER=$!

# Not exec: the script stays alive as the process the supervisor tracks
# and forwards its own death to both children, so killing it can never
# leave the sidecar (or the server) behind as an orphan. Group kills
# still work the same as before.
cleanup() { kill "$SERVER" "$SIDECAR" 2>/dev/null || true; }
trap cleanup EXIT INT TERM HUP
wait "$SERVER"
