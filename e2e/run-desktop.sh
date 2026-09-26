#!/usr/bin/env bash
# Runs the Linux desktop integration tests: the app journey against the
# same cold stack the playwright suite uses (fixture library, waxflow
# sidecar, server), the engine conformance suite over a synthesized
# tone, and the fault taxonomy every way a load can fail. Needs a
# display and an audio sink; on a headless machine wrap the invocation
# in xvfb-run and point PULSE_SINK at a null sink. Each suite's verbose
# tool trace and JSON report, and the probe of one that hung, land in
# WAX_DIAG_DIR (a temporary directory when unset; the path is printed).
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
# journey did. The one exception is a hang: a suite that ran out its
# budget ends the run, because the stack or the display it hung on is
# what the next suite would inherit, and three budgets spent finding
# that out is what a job's cap is made of.
#
# The tone is exported rather than named per suite: the journey ignores
# it, and the two that need it fail loudly when it is missing. The fault
# taxonomy is the one only a real player can answer for - mpv reports no
# failed load at all, so that is where the engine's load deadline is
# measured rather than assumed, with the tone as its control and its
# recovery case's good load.
#
# Each suite runs under its own budget (tools/ci/run-suite.sh): a hung
# one is probed while it still stands - native thread stacks, VM service
# isolates, the display - where before it sat until the job's cap
# cancelled it with nothing kept. The budgets are multiples of a green
# run, whose suites take one to three minutes; the first carries the
# Linux build as well.
DIAG="${WAX_DIAG_DIR:-$(mktemp -d)}"
mkdir -p "$DIAG"
CI_TOOLS="$E2E_DIR/../tools/ci"
cd "$E2E_DIR/../app/app"
export WAXDECK_CONFORMANCE_MEDIA="$CONF_DIR/conformance-tone.flac"
FAILED=()
SKIPPED=()
HUNG=""
suite() {
  local name=$1 budget=$2 status=0
  if [ -n "$HUNG" ]; then
    SKIPPED+=("$name")
    return 0
  fi
  "$CI_TOOLS/run-suite.sh" "$name" "$budget" "$DIAG" "$CI_TOOLS/probe-linux.sh" -- \
    flutter test -v --reporter expanded --file-reporter "json:$DIAG/$name.report.json" \
    -d linux "integration_test/${name}_test.dart" || status=$?
  [ "$status" -eq 124 ] && HUNG=$name
  [ "$status" -eq 0 ] || FAILED+=("$name")
  return 0
}
suite desktop_playback 900
suite real_engine_conformance 600
suite load_fault 600
echo "desktop diagnostics: $DIAG"
if [ ${#SKIPPED[@]} -gt 0 ]; then
  echo "desktop suites skipped after $HUNG hung: ${SKIPPED[*]}" >&2
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '\nSkipped after %s hung: %s.\n' "$HUNG" "${SKIPPED[*]}" >> "$GITHUB_STEP_SUMMARY"
  fi
fi
[ ${#FAILED[@]} -eq 0 ] || {
  echo "desktop suites failed: ${FAILED[*]}" >&2
  exit 1
}
