#!/usr/bin/env bash
# Launches the end-to-end playback stack for playwright: synthesizes the
# fixture library (no binary media in git), builds and starts the WaxFlow
# streaming sidecar, then execs the waxdeck server binary (built by
# `make build` beforehand) so playwright owns the process tree.
set -euo pipefail

E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$E2E_DIR/.run"

rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR"/{library,waxdeck-data,waxflow-data,waxflow-cache,podcasts,feed,upload-src}

(cd "$E2E_DIR/../fixtures" && go run ./cmd/fixturegen -out "$RUN_DIR/library" -preset all >/dev/null)
# Source files for the manual-upload journey: outside the scanned
# library, so they only ever enter it through the upload pipeline.
(cd "$E2E_DIR/../fixtures" && go run ./cmd/fixturegen -out "$RUN_DIR/upload-src" -preset upload >/dev/null)
(cd "$E2E_DIR/../server" && go build -o "$RUN_DIR/waxflow-catalog" ./cmd/waxflow-catalog)
(cd "$E2E_DIR/../fixtures" && go build -o "$RUN_DIR/testidp" ./cmd/testidp)
(cd "$E2E_DIR/../fixtures" && go build -o "$RUN_DIR/feedserv" ./cmd/feedserv)

# A station logo for the radio journey, served by the same loopback host
# the podcast fixture uses. Written here rather than vendored: it is
# generated media, and the logo proxy's whole job is to fetch a picture
# from a station host and serve it from this origin, so the test needs a
# host with a picture on it. A 1x1 opaque PNG is enough - what is under
# test is the fetch, the sniffed type, and the validator, not the image.
base64 -d >"$RUN_DIR/feed/station-logo.png" <<'PNG'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==
PNG

# Roots come from a config file rather than WAXFLOW_ROOTS: the env form
# is read once at process start, so the sidecar only wires POST
# /roots/reload (and advertises delivery.rootsReload) when its roots come
# from a file. That is what lets the admin-ops spec create a library at
# runtime and have this same sidecar pick it up. WaxDeck owns the file
# from then on and rewrites its roots array in place.
cat >"$RUN_DIR/waxflow.json" <<JSON
{
  "roots": [
    { "name": "lib", "path": "$RUN_DIR/library" },
    { "name": "podcasts", "path": "$RUN_DIR/podcasts" }
  ]
}
JSON

WAXFLOW_ADDR=127.0.0.1:4418 \
WAXFLOW_CONFIG="$RUN_DIR/waxflow.json" \
WAXFLOW_DATA_DIR="$RUN_DIR/waxflow-data" \
WAXFLOW_CACHE_DIR="$RUN_DIR/waxflow-cache" \
WAXFLOW_API_KEYS=e2e-test-key \
	"$RUN_DIR/waxflow-catalog" server &
SIDECAR=$!

# The fixture podcast host: a generated feed with silence-padded
# episodes, served like any podcast host would (ranges, conditional
# GET). The podcast scenarios subscribe to it over loopback.
"$RUN_DIR/feedserv" -addr 127.0.0.1:4421 -dir "$RUN_DIR/feed" -generate &
FEEDSERV=$!

# The test identity provider backs the browser-driven single sign-on
# scenario. The server discovers the issuer at startup and fails fast,
# so wait for it to answer before launching waxdeck.
#
# It launches even when the OIDC variables below point somewhere else
# (run-sso-dex.sh points them at a real dex): one spare process on a
# loopback port is cheaper than a second code path through this script,
# and the default run is then byte-for-byte what it always was.
"$RUN_DIR/testidp" -addr 127.0.0.1:4419 -issuer http://127.0.0.1:4419 &
IDP=$!
for _ in $(seq 1 50); do
	curl -fsS http://127.0.0.1:4419/.well-known/openid-configuration >/dev/null 2>&1 && break
	sleep 0.1
done

WAXDECK_DATA_DIR="$RUN_DIR/waxdeck-data" \
WAXDECK_LIBRARY_ROOTS="lib=$RUN_DIR/library" \
WAXDECK_MANAGED_ROOTS="lib" \
WAXDECK_MATCHING=false \
WAXDECK_PODCAST_DIR="$RUN_DIR/podcasts" \
WAXDECK_ALLOW_PRIVATE_FEED_HOSTS=true \
WAXDECK_ALLOW_PRIVATE_RADIO_HOSTS=true \
WAXDECK_FLOW_URL=http://127.0.0.1:4418 \
WAXDECK_FLOW_API_KEY=e2e-test-key \
WAXDECK_FLOW_CONFIG="$RUN_DIR/waxflow.json" \
WAXDECK_PUBLIC_BASE=http://localhost:4420 \
WAXDECK_WORKER_TOKENS=e2e-worker-token \
WAXDECK_OIDC_ISSUER=${WAXDECK_OIDC_ISSUER:-http://127.0.0.1:4419} \
WAXDECK_OIDC_ID=${WAXDECK_OIDC_ID:-testidp} \
WAXDECK_OIDC_NAME=${WAXDECK_OIDC_NAME:-Test SSO} \
WAXDECK_OIDC_CLIENT_ID=${WAXDECK_OIDC_CLIENT_ID:-waxdeck-e2e} \
WAXDECK_OIDC_CLIENT_SECRET=${WAXDECK_OIDC_CLIENT_SECRET:-} \
	"$E2E_DIR/../server/waxdeck" &
SERVER=$!

# Not exec: the script stays alive as the process the supervisor tracks
# and forwards its own death to the children, so killing it can never
# leave the sidecar, the IdP, or the server behind as an orphan. Group
# kills still work the same as before.
cleanup() { kill "$SERVER" "$SIDECAR" "$IDP" "$FEEDSERV" 2>/dev/null || true; }
trap cleanup EXIT INT TERM HUP
wait "$SERVER"
