#!/usr/bin/env bash
# Runs the desktop integration tests on a named device: the app journey
# against the same cold stack the playwright suite uses (fixture library,
# waxflow sidecar, server), and the engine conformance suite over a
# synthesized tone. Needs a display and an audio sink; on a headless
# machine wrap the invocation in xvfb-run and point PULSE_SINK at a null
# sink.
#
# Usage: run-desktop.sh [linux|macos]   (linux by default)
#
# The tone reaches the app differently per device. On linux it is a path
# in the environment. The macos app is sandboxed - it holds
# network.client but nothing that opens an arbitrary temp directory - so
# there the tone is served over loopback HTTP instead, which the sandbox
# will fetch and which is the shape a real library stream takes anyway.
set -euo pipefail

E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE=http://localhost:4420

DEVICE="${1:-linux}"
case "$DEVICE" in
linux | macos) ;;
*)
  echo "usage: $(basename "$0") [linux|macos]" >&2
  exit 2
  ;;
esac

(cd "$E2E_DIR/../server" && go build -o waxdeck ./cmd/waxdeck)

CONF_DIR=$(mktemp -d)
(cd "$E2E_DIR/../fixtures" &&
  go run ./cmd/fixturegen -out "$CONF_DIR" -preset conformance >/dev/null)

# feedserv rather than python's http.server, which speaks HTTP/1.0 and
# ignores Range: AVPlayer refuses such a source outright and every case
# fails at load with AVErrorServerIncorrectlyConfigured (-11850). The
# fixture host already serves ranges and conditional GETs, which is what
# a real stream looks like anyway.
#
# 8089 rather than 8000: this runs on development machines, where 8000 is
# the port everything else has already claimed.
TONE_PID=
if [ "$DEVICE" = macos ]; then
  (cd "$E2E_DIR/../fixtures" && go build -o "$CONF_DIR/feedserv" ./cmd/feedserv)
  "$CONF_DIR/feedserv" -addr 127.0.0.1:8089 -dir "$CONF_DIR" \
    >"$CONF_DIR/tone-server.log" 2>&1 &
  TONE_PID=$!
  TONE_URL=http://127.0.0.1:8089/conformance-tone.flac
else
  TONE_URL="$CONF_DIR/conformance-tone.flac"
fi

# The stack runs in its own process group so cleanup can take the whole
# tree down at once. setsid does that on linux and macOS does not ship
# it, so there bash job control stands in: with -m a background job gets
# a process group of its own, whose id is the pid $! reports.
if command -v setsid >/dev/null 2>&1; then
  setsid bash "$E2E_DIR/run-stack.sh" &
else
  set -m
  bash "$E2E_DIR/run-stack.sh" &
  set +m
fi
STACK=$!
cleanup() {
  kill -- "-$STACK" 2>/dev/null || true
  [ -n "$TONE_PID" ] && kill "$TONE_PID" 2>/dev/null || true
  rm -rf "$CONF_DIR"
}
trap cleanup EXIT INT TERM HUP

if [ -n "$TONE_PID" ]; then
  TONE_READY=
  for _ in $(seq 1 30); do
    # Liveness before reachability: if 8089 was already taken, feedserv
    # exited on the bind and the curl below would pass against whatever
    # else is listening - and the suite would then run against that
    # process's idea of the tone.
    if ! kill -0 "$TONE_PID" 2>/dev/null; then
      echo "the tone server exited; is 8089 already in use?" >&2
      cat "$CONF_DIR/tone-server.log" >&2
      exit 1
    fi
    if curl -sfo /dev/null "$TONE_URL"; then
      TONE_READY=1
      break
    fi
    sleep 1
  done
  [ "$TONE_READY" = 1 ] || {
    echo "the tone server never answered" >&2
    cat "$CONF_DIR/tone-server.log" >&2
    exit 1
  }
fi

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
cd "$E2E_DIR/../app/app"
flutter test integration_test/desktop_playback_test.dart -d "$DEVICE"
WAXDECK_CONFORMANCE_MEDIA="$TONE_URL" \
	flutter test integration_test/real_engine_conformance_test.dart -d "$DEVICE"
