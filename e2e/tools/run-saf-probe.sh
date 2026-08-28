#!/usr/bin/env bash
# The waxdeck/saf channel test with its picker driven from outside.
#
#   run-saf-probe.sh <probe-dir> [serial]
#
# <probe-dir> is the WaxProbe folder `fixturegen -preset saf-probe`
# wrote. Pushes it onto the device, starts drive-saf-picker.sh beside
# the test, and runs integration_test/saf_channel_test.dart.
#
# On failure it captures what the device looked like - a screenshot and
# a final view hierarchy - into $SAF_ARTIFACTS, because a picker whose
# strings drifted is unreadable from the test's timeout alone. The
# directory is emptied first, so a retry never uploads the previous
# attempt's device as evidence for this one.
set -euo pipefail

PROBE="${1:?usage: run-saf-probe.sh <probe-dir> [serial]}"
SERIAL="${2:-emulator-5554}"
TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$(cd "$TOOLS/../../app/app" && pwd)"
ARTIFACTS="${SAF_ARTIFACTS:-${RUNNER_TEMP:-/tmp}/wax-saf-artifacts}"

driver=""
capture() {
  mkdir -p "$ARTIFACTS"
  adb -s "$SERIAL" exec-out screencap -p >"$ARTIFACTS/picker.png" 2>/dev/null || true
  adb -s "$SERIAL" shell uiautomator dump /data/local/tmp/wax-failure.xml \
    >/dev/null 2>&1 || true
  adb -s "$SERIAL" exec-out cat /data/local/tmp/wax-failure.xml \
    >"$ARTIFACTS/picker.xml" 2>/dev/null || true
  echo "run-saf-probe: captured the device into $ARTIFACTS" >&2
}

cleanup() {
  local status=$?
  # Cleared first: everything below is written not to fail, but a
  # second EXIT would report the trap's own status as the run's.
  trap - EXIT
  if [ -n "$driver" ]; then
    kill "$driver" 2>/dev/null || true
  fi
  if [ "$status" -ne 0 ]; then
    capture
  fi
  exit "$status"
}
trap cleanup EXIT

rm -rf "$ARTIFACTS"

# Removed first, so a retry on the same emulator walks the tree this
# run pushed rather than one a half-finished attempt left behind.
adb -s "$SERIAL" shell rm -rf /sdcard/Music/WaxProbe
adb -s "$SERIAL" shell mkdir -p /sdcard/Music
adb -s "$SERIAL" push "$PROBE" /sdcard/Music/WaxProbe

"$TOOLS/drive-saf-picker.sh" "$SERIAL" &
driver=$!

cd "$APP"
status=0
flutter test integration_test/saf_channel_test.dart -d "$SERIAL" || status=$?

# The driver's own fate, which is otherwise invisible: `set -e` says
# nothing about a background job, so one that died on the first adb
# call looks exactly like one that tapped everything correctly - and
# the test's failure would read as the channel's.
#
# Given a moment first, because it legitimately lags: the grant is what
# ends the test, and the picker closing is what the driver is still
# waiting to see one poll later.
for _ in 1 2 3 4 5; do
  kill -0 "$driver" 2>/dev/null || break
  sleep 1
done
if kill -0 "$driver" 2>/dev/null; then
  echo "run-saf-probe: the picker driver is still running - it never saw" \
    "the picker close" >&2
  kill "$driver" 2>/dev/null || true
else
  driver_status=0
  wait "$driver" || driver_status=$?
  if [ "$driver_status" -ne 0 ]; then
    echo "run-saf-probe: the picker driver exited $driver_status" >&2
  fi
fi
driver=""
exit "$status"
