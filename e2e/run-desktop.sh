#!/usr/bin/env bash
# Runs the Linux desktop integration tests: the app journey against the
# same cold stack the playwright suite uses (fixture library, waxflow
# sidecar, server), the engine conformance suite over a synthesized
# tone, and the fault taxonomy every way a load can fail. Needs a
# display and an audio sink; on a headless machine wrap the invocation
# in xvfb-run and point PULSE_SINK at a null sink.
set -euo pipefail

# No arguments: linux is the only desktop this runs on, and a named but
# silently ignored device would green-light a suite that never ran.
[ $# -eq 0 ] || {
  echo "usage: $(basename "$0")" >&2
  exit 2
}

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
# album must be searchable before the app launches. The server accepts no
# credentials until its first administrator exists, so each attempt first
# bootstraps that account (a no-op 409 once it exists) and then logs in
# with it; the login fallback covers a stack reusing an existing DB.
READY=
for _ in $(seq 1 120); do
  curl -sf -X POST "$BASE/api/v1/auth/bootstrap" \
    -H 'Content-Type: application/json' \
    -d '{"username":"admin","password":"wax-e2e-pass"}' >/dev/null 2>&1 || true
  TOKEN=$(curl -sf -X POST "$BASE/api/v1/auth/login" \
    -H 'Content-Type: application/json' \
    -d '{"username":"admin","password":"wax-e2e-pass"}' |
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
#
# Every suite runs whatever the ones before it did, and the failures are
# reported together at the end. They answer for different halves of the
# stack - the app journey, the engine's format conformance, the fault
# taxonomy - so stopping at the first hides the other two behind it for
# as long as that failure stands, which is exactly what one stale
# journey did. The cost is paid by a runner broken for all three (no
# display, no audio sink, a stack that died): it spends three timeouts
# saying so where fail-fast spent one.
#
# The tone is exported rather than named per suite: the journey ignores
# it, and the two that need it fail loudly when it is missing. The fault
# taxonomy is the one only a real player can answer for - mpv reports no
# failed load at all, so that is where the engine's load deadline is
# measured rather than assumed, with the tone as its control and its
# recovery case's good load.
cd "$E2E_DIR/../app/app"
export WAXDECK_CONFORMANCE_MEDIA="$CONF_DIR/conformance-tone.flac"
FAILED=()
for suite in desktop_playback real_engine_conformance load_fault; do
  flutter test "integration_test/${suite}_test.dart" -d linux ||
    FAILED+=("$suite")
done
[ ${#FAILED[@]} -eq 0 ] || {
  echo "desktop suites failed: ${FAILED[*]}" >&2
  exit 1
}
