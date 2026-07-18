#!/usr/bin/env bash
# Runs the Linux desktop integration tests: the app journey against the
# same cold stack the playwright suite uses (fixture library, waxflow
# sidecar, server), and the engine conformance suite over a synthesized
# tone. Needs a display and an audio sink; on a headless machine wrap
# the invocation in xvfb-run and point PULSE_SINK at a null sink.
set -euo pipefail

E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE=http://localhost:4420

(cd "$E2E_DIR/../server" && go build -o waxdeck ./cmd/waxdeck)

CONF_DIR=$(mktemp -d)
(cd "$E2E_DIR/../fixtures" &&
  go run ./cmd/fixturegen -out "$CONF_DIR" -preset conformance >/dev/null)

setsid bash "$E2E_DIR/run-stack.sh" &
STACK=$!
cleanup() {
  kill -- "-$STACK" 2>/dev/null || true
  rm -rf "$CONF_DIR"
}
trap cleanup EXIT INT TERM HUP

# Wait for the startup scan: the grid loads once at login, so the demo
# album must be searchable before the app launches.
READY=
for _ in $(seq 1 120); do
  TOKEN=$(curl -sf -X POST "$BASE/api/v1/auth/login" \
    -H 'Content-Type: application/json' \
    -d '{"username":"admin","password":"e2e"}' |
    sed -n 's/.*"token":"\([^"]*\)".*/\1/p') || true
  if [ -n "${TOKEN:-}" ] && curl -sf "$BASE/api/v1/library/search?q=Alpha" \
    -H "Authorization: Bearer $TOKEN" | grep -q '"tr-'; then
    READY=1
    break
  fi
  sleep 1
done
[ "$READY" = 1 ] || {
  echo "stack never became ready" >&2
  exit 1
}

# No exec here: it would replace the shell and drop the cleanup trap,
# leaving the stack running after the tests exit. One invocation per test
# file: launching the next file's app process on the heels of the last
# one's exit is flaky on linux desktop (the debug connection never comes
# up), and separate invocations give it room.
cd "$E2E_DIR/../app/app"
flutter test integration_test/desktop_playback_test.dart -d linux
WAXDECK_CONFORMANCE_MEDIA="$CONF_DIR/conformance-tone.flac" \
	flutter test integration_test/real_engine_conformance_test.dart -d linux
