#!/usr/bin/env bash
# Launches the end-to-end playback stack for playwright: synthesizes the
# fixture library (no binary media in git), builds and starts the WaxFlow
# streaming sidecar, then execs the waxdeck server binary (built by
# `make build` beforehand) so playwright owns the process tree.
set -euo pipefail

E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$E2E_DIR/.run"

rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR"/{library,waxdeck-data,waxflow-data,waxflow-cache,podcasts,feed}

(cd "$E2E_DIR/../fixtures" && go run ./cmd/fixturegen -out "$RUN_DIR/library" -preset all >/dev/null)
(cd "$E2E_DIR/../server" && go build -o "$RUN_DIR/waxflow-catalog" ./cmd/waxflow-catalog)
(cd "$E2E_DIR/../fixtures" && go build -o "$RUN_DIR/testidp" ./cmd/testidp)
(cd "$E2E_DIR/../fixtures" && go build -o "$RUN_DIR/feedserv" ./cmd/feedserv)

WAXFLOW_ADDR=127.0.0.1:4418 \
WAXFLOW_ROOTS="lib=$RUN_DIR/library,podcasts=$RUN_DIR/podcasts" \
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
WAXDECK_FLOW_URL=http://127.0.0.1:4418 \
WAXDECK_FLOW_API_KEY=e2e-test-key \
WAXDECK_PUBLIC_BASE=http://localhost:4420 \
WAXDECK_OIDC_ISSUER=http://127.0.0.1:4419 \
WAXDECK_OIDC_ID=testidp \
WAXDECK_OIDC_NAME="Test SSO" \
WAXDECK_OIDC_CLIENT_ID=waxdeck-e2e \
	"$E2E_DIR/../server/waxdeck" &
SERVER=$!

# Not exec: the script stays alive as the process the supervisor tracks
# and forwards its own death to the children, so killing it can never
# leave the sidecar, the IdP, or the server behind as an orphan. Group
# kills still work the same as before.
cleanup() { kill "$SERVER" "$SIDECAR" "$IDP" "$FEEDSERV" 2>/dev/null || true; }
trap cleanup EXIT INT TERM HUP
wait "$SERVER"
