#!/usr/bin/env bash
# The Android engine conformance run, as the emulator job's script.
#
#   android-conformance.sh <out-dir> <tone-url> <saf-probe-dir> [serial]
#
# Two flutter test suites and the SAF picker probe, each under its own
# budget (run-suite.sh), with logcat collected from before the first
# install to after the last exit. A suite that fails is followed by the
# next; a suite that hangs is probed where it stands (probe-android.sh)
# and ends the attempt, because a device that hung once answers little
# when asked again and the retry's fresh emulator runs every suite
# anyway - so one stuck launch costs one budget, not three. The exit
# status says whether every suite passed. Everything lands under
# <out-dir>, which the workflow uploads whatever happened.
#
# The budgets are multiples of a green run, not measurements of one:
# with the Gradle build warmed before the emulator boots, a suite is a
# minute or two of real-time playback, and one that is still going ten
# minutes later has stopped. The launch that hung took 51 minutes to be
# cancelled and left nothing; this is what it leaves now.
set -euo pipefail

usage="usage: android-conformance.sh <out-dir> <tone-url> <saf-probe-dir> [serial]"
OUT=${1:?$usage}
TONE=${2:?$usage}
SAF=${3:?$usage}
SERIAL=${4:-emulator-5554}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
mkdir -p "$OUT"
export WAX_SERIAL="$SERIAL"
export WAX_LOGCAT="$OUT/logcat.txt"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '\n## Android conformance: %s\n' "$(basename "$OUT")" >> "$GITHUB_STEP_SUMMARY"
fi

# The device, for the record: image, API level, hardware.
{
  adb -s "$SERIAL" devices -l
  adb -s "$SERIAL" shell getprop |
    grep -E 'ro\.build\.(version|fingerprint)|ro\.product\.(model|cpu)|ro\.hardware|qemu\.' || true
} > "$OUT/device.txt" 2>&1 || true

# Every buffer, from now until the end: the app announces its VM
# service here, and a launch that never does is a hang's first fact.
adb -s "$SERIAL" logcat -v threadtime -b all > "$WAX_LOGCAT" 2>&1 &
LOGCAT=$!
cleanup() {
  kill "$LOGCAT" 2> /dev/null || true
}
trap cleanup EXIT

cd "$ROOT/app/app"
failed=()
skipped=()
hung=""
suite() {
  local name=$1 budget=$2 status=0
  shift 2
  if [ -n "$hung" ]; then
    skipped+=("$name")
    return 0
  fi
  # Where logcat stands as this suite starts: the probe reads the VM
  # service URL from here on, never from an earlier suite's lines.
  WAX_LOGCAT_FROM=$(( $(wc -l < "$WAX_LOGCAT") + 1 ))
  export WAX_LOGCAT_FROM
  "$HERE/run-suite.sh" "$name" "$budget" "$OUT" "$HERE/probe-android.sh" -- "$@" || status=$?
  [ "$status" -eq 124 ] && hung=$name
  [ "$status" -eq 0 ] || failed+=("$name")
  return 0
}
FLAGS=(-v --reporter expanded -d "$SERIAL" "--dart-define=WAXDECK_CONFORMANCE_MEDIA=$TONE")

suite real_engine_conformance 720 flutter test "${FLAGS[@]}" \
  --file-reporter "json:$OUT/real_engine_conformance.report.json" \
  integration_test/real_engine_conformance_test.dart
suite load_fault 600 flutter test "${FLAGS[@]}" \
  --file-reporter "json:$OUT/load_fault.report.json" \
  integration_test/load_fault_test.dart
# The picker probe runs its own flutter test; the reporter flags reach
# it through the environment, and its device capture lands with the rest.
WAX_FLUTTER_TEST_FLAGS="-v --reporter expanded --file-reporter json:$OUT/saf_channel.report.json" \
  SAF_ARTIFACTS="$OUT/saf-capture" \
  suite saf_channel 600 bash "$ROOT/e2e/tools/run-saf-probe.sh" "$SAF" "$SERIAL"

kill "$LOGCAT" 2> /dev/null || true
wait "$LOGCAT" 2> /dev/null || true
trap - EXIT

if [ ${#skipped[@]} -gt 0 ]; then
  echo "android-conformance: skipped after $hung hung: ${skipped[*]}" >&2
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '\nSkipped after %s hung: %s.\n' "$hung" "${skipped[*]}" >> "$GITHUB_STEP_SUMMARY"
  fi
fi
if [ ${#failed[@]} -eq 0 ]; then
  echo "android-conformance: every suite passed"
  exit 0
fi
echo "android-conformance: failed: ${failed[*]}" >&2
exit 1
