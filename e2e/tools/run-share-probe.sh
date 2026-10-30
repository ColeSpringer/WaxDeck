#!/usr/bin/env bash
# The waxdeck/share channel test with its chooser handled from outside.
#
#   run-share-probe.sh [serial]
#
# Runs integration_test/share_channel_test.dart, which shares a card twice.
# Each share opens the system chooser over the app; this sees it take the
# focus, checks the chooser holds a read grant on the card the app wrote
# (the grant a receiving app reads the image through), and dismisses it
# with BACK, which is what lets the test go on. Both shares must be seen
# and granted.
#
# On failure it captures what the device looked like - a screenshot, the
# view hierarchy, and the activity and URI grant dumps - into
# $SHARE_ARTIFACTS. The directory is emptied first, so a retry never
# uploads the previous attempt's device as evidence for this one.
set -euo pipefail

SERIAL="${1:-emulator-5554}"
TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$(cd "$TOOLS/../../app/app" && pwd)"
ARTIFACTS="${SHARE_ARTIFACTS:-${RUNNER_TEMP:-/tmp}/wax-share-artifacts}"
CARD="content://com.colespringer.waxdeck.shares/share-cards/wax-share-probe.png"
SHARES=2

test_pid=""
capture() {
  mkdir -p "$ARTIFACTS"
  adb -s "$SERIAL" exec-out screencap -p >"$ARTIFACTS/device.png" 2>/dev/null || true
  adb -s "$SERIAL" shell uiautomator dump /data/local/tmp/wax-failure.xml \
    >/dev/null 2>&1 || true
  adb -s "$SERIAL" exec-out cat /data/local/tmp/wax-failure.xml \
    >"$ARTIFACTS/device.xml" 2>/dev/null || true
  adb -s "$SERIAL" shell dumpsys activity activities >"$ARTIFACTS/activities.txt" 2>/dev/null || true
  adb -s "$SERIAL" shell dumpsys activity permissions >"$ARTIFACTS/uri-grants.txt" 2>/dev/null || true
  echo "run-share-probe: captured the device into $ARTIFACTS" >&2
}

cleanup() {
  local status=$?
  trap - EXIT
  if [ -n "$test_pid" ]; then
    kill "$test_pid" 2>/dev/null || true
  fi
  if [ "$status" -ne 0 ]; then
    capture
  fi
  exit "$status"
}
trap cleanup EXIT

rm -rf "$ARTIFACTS"

# Read whole, then matched: a `grep -q` in a pipeline under pipefail
# reads the producer's SIGPIPE as the pipeline failing.
focused_on_chooser() {
  local windows
  windows=$(adb -s "$SERIAL" shell dumpsys window windows 2>/dev/null || true)
  windows=$(printf '%s\n' "$windows" | grep -E 'mCurrentFocus|mFocusedApp' || true)
  [[ $windows == *ChooserActivity* ]]
}

granted() {
  local grants
  grants=$(adb -s "$SERIAL" shell dumpsys activity permissions 2>/dev/null || true)
  [[ $grants == *"$CARD"* ]]
}

cd "$APP"
# The reporter flags the CI runner asks for, split on purpose; a local run
# leaves them unset.
# shellcheck disable=SC2086
flutter test ${WAX_FLUTTER_TEST_FLAGS:-} integration_test/share_channel_test.dart -d "$SERIAL" &
test_pid=$!

seen=0
grants=0
while [ "$seen" -lt "$SHARES" ] && kill -0 "$test_pid" 2>/dev/null; do
  if focused_on_chooser; then
    seen=$((seen + 1))
    if granted; then
      grants=$((grants + 1))
    else
      echo "run-share-probe: chooser $seen holds no grant on $CARD" >&2
    fi
    adb -s "$SERIAL" shell input keyevent KEYCODE_BACK
    for _ in $(seq 1 20); do
      focused_on_chooser || break
      sleep 0.5
    done
  fi
  sleep 0.5
done

status=0
wait "$test_pid" || status=$?
test_pid=""
if [ "$seen" -ne "$SHARES" ]; then
  echo "run-share-probe: saw $seen of $SHARES choosers open" >&2
  [ "$status" -ne 0 ] || status=1
fi
if [ "$grants" -ne "$seen" ]; then
  [ "$status" -ne 0 ] || status=1
fi
exit "$status"
