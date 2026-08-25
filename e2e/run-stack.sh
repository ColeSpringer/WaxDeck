#!/usr/bin/env bash
# The e2e stack for playwright: synthesized fixture library, WaxFlow
# sidecar, then the waxdeck binary `make build` left behind.
set -euo pipefail

E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$E2E_DIR/.run"

# Native form for paths handed to the Go binaries: Windows cannot open
# Git bash's /c/... form, and env vars and file contents get no conversion.
RUN_DIR_NATIVE="$RUN_DIR"
command -v cygpath >/dev/null 2>&1 && RUN_DIR_NATIVE="$(cygpath -m "$RUN_DIR")"

rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR"/{library,waxdeck-data,waxflow-data,waxflow-cache,podcasts,feed,upload-src}

(cd "$E2E_DIR/../fixtures" && go run ./cmd/fixturegen -out "$RUN_DIR_NATIVE/library" -preset all >/dev/null)
# Source files for the manual-upload journey: outside the scanned
# library, so they only ever enter it through the upload pipeline.
(cd "$E2E_DIR/../fixtures" && go run ./cmd/fixturegen -out "$RUN_DIR_NATIVE/upload-src" -preset upload >/dev/null)
# The release-workbench journey's own album, so its import never holds
# the destination the manual-upload journey's import needs.
(cd "$E2E_DIR/../fixtures" && go run ./cmd/fixturegen -out "$RUN_DIR_NATIVE/upload-src" -preset upload-workbench >/dev/null)
# The folder-pick journey's own album, written under a disc subdirectory
# so what the picker walks is a tree. The stray text file is there to be
# left behind: a folder pick cannot filter by type in the dialog, so the
# filtering it does afterwards is what this proves.
mkdir -p "$RUN_DIR/upload-src/Harbour Lights/Disc 1"
(cd "$E2E_DIR/../fixtures" && go run ./cmd/fixturegen -out "$RUN_DIR_NATIVE/upload-src/Harbour Lights/Disc 1" -preset upload-folder >/dev/null)
echo "not audio" >"$RUN_DIR/upload-src/Harbour Lights/notes.txt"
# An Audible container beside the album: the picker's DRM deny-list is
# what leaves it behind, and the journey asserts the refusal is said.
echo "not really encrypted" >"$RUN_DIR/upload-src/Harbour Lights/memoir.aax"
# A cover to set by hand. Beside the upload sources rather than in the
# library: it is a file a picker walks to, not media under scan.
(cd "$E2E_DIR/../fixtures" && go run ./cmd/fixturegen -out "$RUN_DIR_NATIVE/upload-src" -preset cover >/dev/null)
(cd "$E2E_DIR/../server" && go build -o "$RUN_DIR_NATIVE/waxflow-catalog" ./cmd/waxflow-catalog)
(cd "$E2E_DIR/../fixtures" && go build -o "$RUN_DIR_NATIVE/testidp" ./cmd/testidp)
(cd "$E2E_DIR/../fixtures" && go build -o "$RUN_DIR_NATIVE/feedserv" ./cmd/feedserv)

# A station logo for the radio journey's logo proxy: what is under test
# is the fetch, sniffed type, and validator, so a 1x1 PNG is enough.
base64 -d >"$RUN_DIR/feed/station-logo.png" <<'PNG'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==
PNG

# Roots from a file rather than WAXFLOW_ROOTS: only file-based roots wire
# /roots/reload, which the admin-ops spec's runtime-created library needs.
cat >"$RUN_DIR/waxflow.json" <<JSON
{
  "roots": [
    { "name": "lib", "path": "$RUN_DIR_NATIVE/library" },
    { "name": "podcasts", "path": "$RUN_DIR_NATIVE/podcasts" }
  ]
}
JSON

WAXFLOW_ADDR=127.0.0.1:4418 \
WAXFLOW_CONFIG="$RUN_DIR_NATIVE/waxflow.json" \
WAXFLOW_DATA_DIR="$RUN_DIR_NATIVE/waxflow-data" \
WAXFLOW_CACHE_DIR="$RUN_DIR_NATIVE/waxflow-cache" \
WAXFLOW_API_KEYS=e2e-test-key \
	"$RUN_DIR/waxflow-catalog" server &
SIDECAR=$!

# The fixture podcast host the podcast scenarios subscribe to.
"$RUN_DIR/feedserv" -addr 127.0.0.1:4421 -dir "$RUN_DIR_NATIVE/feed" -generate &
FEEDSERV=$!

# The test IdP for the SSO scenario; waxdeck discovers the issuer at
# startup and fails fast, so wait for it. Launched even when the OIDC
# vars point at a real dex - cheaper than a second code path here.
"$RUN_DIR/testidp" -addr 127.0.0.1:4419 -issuer http://127.0.0.1:4419 &
IDP=$!
for _ in $(seq 1 50); do
	curl -fsS http://127.0.0.1:4419/.well-known/openid-configuration >/dev/null 2>&1 && break
	sleep 0.1
done

WAXDECK_DATA_DIR="$RUN_DIR_NATIVE/waxdeck-data" \
WAXDECK_LIBRARY_ROOTS="lib=$RUN_DIR_NATIVE/library" \
WAXDECK_MANAGED_ROOTS="lib" \
WAXDECK_MATCHING=false \
WAXDECK_ARTIST_ART=false \
WAXDECK_PODCAST_DIR="$RUN_DIR_NATIVE/podcasts" \
WAXDECK_ALLOW_PRIVATE_FEED_HOSTS=true \
WAXDECK_ALLOW_PRIVATE_RADIO_HOSTS=true \
WAXDECK_FLOW_URL=http://127.0.0.1:4418 \
WAXDECK_FLOW_API_KEY=e2e-test-key \
WAXDECK_FLOW_CONFIG="$RUN_DIR_NATIVE/waxflow.json" \
WAXDECK_PUBLIC_BASE=http://localhost:4420 \
WAXDECK_WORKER_TOKENS=e2e-worker-token \
WAXDECK_OIDC_ISSUER=${WAXDECK_OIDC_ISSUER:-http://127.0.0.1:4419} \
WAXDECK_OIDC_ID=${WAXDECK_OIDC_ID:-testidp} \
WAXDECK_OIDC_NAME=${WAXDECK_OIDC_NAME:-Test SSO} \
WAXDECK_OIDC_CLIENT_ID=${WAXDECK_OIDC_CLIENT_ID:-waxdeck-e2e} \
WAXDECK_OIDC_CLIENT_SECRET=${WAXDECK_OIDC_CLIENT_SECRET:-} \
	"$E2E_DIR/../server/waxdeck" &
SERVER=$!

# Not exec: the script stays alive to forward its death to the children,
# so killing it cannot orphan the sidecar, the IdP, or the server.
cleanup() { kill "$SERVER" "$SIDECAR" "$IDP" "$FEEDSERV" 2>/dev/null || true; }
trap cleanup EXIT INT TERM HUP
wait "$SERVER"
