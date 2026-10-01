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

# The logcat follower's pid once it runs, and the way it stops: the
# loop and whichever adb it is waiting on, together, because the loop
# alone would leave its logcat writing on.
LOGCAT=""
stop_logcat() {
  local current
  [ -n "$LOGCAT" ] || return 0
  current=$(pgrep -P "$LOGCAT" || true)
  # shellcheck disable=SC2086 # the pids are the words
  kill "$LOGCAT" $current 2> /dev/null || true
  wait "$LOGCAT" 2> /dev/null || true
  LOGCAT=""
}
# Whatever ends the script, the device gate giving up included: the
# follower stops, and the adb server's own log joins the diagnostics -
# the host-side half of a transport drop, of which the guest's adbd
# lines in logcat show only the other end.
on_exit() {
  stop_logcat
  cp "${TMPDIR:-/tmp}"/adb.*.log "$OUT/" 2> /dev/null || true
}
trap on_exit EXIT

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '\n## Android conformance: %s\n' "$(basename "$OUT")" >> "$GITHUB_STEP_SUMMARY"
fi

# A device that has just reported sys.boot_completed is not one a suite
# can start on. On every CI boot on record, the emulator's adb transport
# was torn down and rebuilt once after boot - at +0.9s, +1.4s and +1.4s
# in three attempts, and once at +65s, mid-launch - and the runner
# action hands the device over inside that first second. `flutter test
# -d` reads `adb devices` once and takes an offline device for no
# device, so a whole run failed twice without a test running, both
# attempts inside the first ten seconds. Ready therefore means online
# and booted for five seconds straight, which outlasts the rebuild with
# margin; the late one is the harness death suite() tries again below.
# Each adb call is bounded, since one blocked on a half-open transport
# would otherwise outlast the gate itself.
await_device() {
  local stable=0 start=$SECONDS state booted
  while (( SECONDS - start < 180 )); do
    state=$(timeout 5 adb -s "$SERIAL" get-state 2> /dev/null || true)
    booted=$(timeout 5 adb -s "$SERIAL" shell getprop sys.boot_completed 2> /dev/null | tr -d '\r' || true)
    if [ "$state" = device ] && [ "$booted" = 1 ]; then
      if (( ++stable >= 10 )); then
        echo "android-conformance: $SERIAL ready after $(( SECONDS - start ))s"
        return 0
      fi
    else
      stable=0
    fi
    sleep 0.5
  done
  echo "android-conformance: $SERIAL did not settle in 180s (last: ${state:-gone}, boot_completed=${booted:-?})" >&2
  return 1
}
await_device

# The device, for the record: image, API level, hardware.
{
  adb -s "$SERIAL" devices -l
  adb -s "$SERIAL" shell getprop |
    grep -E 'ro\.build\.(version|fingerprint)|ro\.product\.(model|cpu)|ro\.hardware|qemu\.' || true
} > "$OUT/device.txt" 2>&1 || true

# Every buffer, from now until the end: the app announces its VM
# service here, and a launch that never does is a hang's first fact.
#
# Rejoined whenever it ends, because logcat exits with the device's
# connection: a transport that dropped for a moment as a launch began
# once took the log for the rest of the attempt with it, leaving the
# later suites unlogged and a hung one's probe reading the silence as
# an app that never announced. A rejoin resumes at the last kept line's
# timestamp: what was logged while the link was down comes back from the
# ring buffer, the rest of the ring is not written out again, and only
# that one millisecond's lines repeat (-T is inclusive).
follow_logcat() {
  local since
  while :; do
    since=$(grep -oE '^[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}' "$WAX_LOGCAT" |
      tail -n 1 || true)
    adb -s "$SERIAL" logcat -v threadtime -b all ${since:+-T "$since"} || true
    sleep 1
    adb -s "$SERIAL" wait-for-device || true
  done
}
: > "$WAX_LOGCAT"
follow_logcat >> "$WAX_LOGCAT" 2>&1 &
LOGCAT=$!

# A line of this suite's own in the device log, and its number in the
# file: where the probe and the retry decision start reading. The
# file's current end would not do, because the follower is still
# writing out the ring buffer's history as the first suite starts, and
# a drop from before the gate would then read as one under the suite.
# When the device will not take the line, the end is what there is.
mark_logcat() {
  local marker line
  marker="suite $1 starts at $(date +%s.%N)"
  adb -s "$SERIAL" shell log -t wax-ci "$marker" 2> /dev/null || true
  for _ in $(seq 1 10); do
    line=$(grep -nF "$marker" "$WAX_LOGCAT" | tail -n 1 | cut -d: -f1 || true)
    if [ -n "$line" ]; then
      echo "$line"
      return 0
    fi
    sleep 0.5
  done
  echo $(( $(wc -l < "$WAX_LOGCAT") + 1 ))
}

# Whether the guest's adbd logged its host transport dying on or after
# logcat line $1 - "connection terminated" and "destroying transport"
# are what every observed drop left. When the drop took the logcat
# stream with it the lines arrive seconds late, from the ring buffer
# the follower rejoins through, so this looks for up to ten seconds.
transport_dropped_since() {
  local from=$1
  for _ in $(seq 1 10); do
    if tail -n "+$from" "$WAX_LOGCAT" |
      grep -E ' adbd +: .*(connection terminated|destroying transport)' > /dev/null; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# The first try's record stays beside the retry's, under its own name -
# the picker probe's capture included, which run-saf-probe.sh clears as
# it starts.
keep_first_try() {
  local name=$1
  [ -e "$OUT/$name.log" ] && mv "$OUT/$name.log" "$OUT/$name.first-try.log"
  [ -e "$OUT/$name.report.json" ] && mv "$OUT/$name.report.json" "$OUT/$name.first-try.report.json"
  [ -e "$OUT/$name.verdict" ] && mv "$OUT/$name.verdict" "$OUT/$name.first-try.verdict"
  [ -d "$OUT/saf-capture" ] && mv "$OUT/saf-capture" "$OUT/saf-capture.first-try"
  return 0
}

cd "$ROOT/app/app"
failed=()
skipped=()
hung=""

# A suite whose verdict is `died` - run-suite.sh found no test started
# before the exit - with the device's adb transport rebuilt under it is
# the drop above arriving late: no device found, the app's VM service
# lost as the launch began, the Dart Development Service refusing to
# start. That is the harness dying, not the suite failing, and it gets
# one more try on the same device once that has settled again. A death
# with the transport intact is not retried - a build that does not
# compile or an app that crashes at launch would only fail twice, and
# twice the time - and run-suite.sh's warning becomes the attempt's
# error. The budget stands per try; a hang is still the end of the
# attempt, and a suite that ran a test and failed is a failure.
suite() {
  local name=$1 budget=$2 status=0 verdict retried=""
  shift 2
  if [ -n "$hung" ]; then
    skipped+=("$name")
    return 0
  fi
  # Where this suite starts in logcat: the probe reads the VM service
  # URL from here on, never from an earlier suite's lines.
  WAX_LOGCAT_FROM=$(mark_logcat "$name")
  export WAX_LOGCAT_FROM
  "$HERE/run-suite.sh" "$name" "$budget" "$OUT" "$HERE/probe-android.sh" -- "$@" || status=$?
  verdict=$(cat "$OUT/$name.verdict" 2> /dev/null || true)
  if [ "$verdict" = died ] && transport_dropped_since "$WAX_LOGCAT_FROM"; then
    retried=1
    echo "android-conformance: $name died before its first test as the device's adb transport was rebuilt; trying it once more"
    keep_first_try "$name"
    status=0
    verdict=""
    if await_device; then
      WAX_LOGCAT_FROM=$(mark_logcat "$name")
      "$HERE/run-suite.sh" "$name" "$budget" "$OUT" "$HERE/probe-android.sh" -- "$@" || status=$?
      verdict=$(cat "$OUT/$name.verdict" 2> /dev/null || true)
    else
      status=1
    fi
  fi
  if [ "$verdict" = died ]; then
    echo "::error title=$name died${retried:+ twice}::the harness died before the suite's first test${retried:+, again}; the warning above has the exit and the log's tail"
  fi
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

stop_logcat

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
