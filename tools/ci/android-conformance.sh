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

# The device gate below fetches the tone with a hand-written HTTP/1.0
# request over netcat, which is all the tone needs - it is served
# without TLS on purpose, and the workflow says why. A URL it cannot
# speak to is refused here, as the usage error it is, rather than
# reported later as a device that could not reach it.
tone_re='^http://([A-Za-z0-9.-]+)(:([0-9]+))?(/[A-Za-z0-9._~/-]*)?$'
if [[ ! $TONE =~ $tone_re ]]; then
  echo "android-conformance: the tone must be a plain http://host[:port]/path URL; got $TONE" >&2
  exit 2
fi
TONE_HOST=${BASH_REMATCH[1]}
TONE_PORT=${BASH_REMATCH[3]:-80}
TONE_PATH=${BASH_REMATCH[4]:-/}
TONE_HOSTPORT=$TONE_HOST:$TONE_PORT
# The same file as the host itself fetches it: 10.0.2.2 is the
# emulator's name for the host's loopback.
TONE_FROM_HOST=$TONE
if [ "$TONE_HOST" = 10.0.2.2 ]; then
  TONE_FROM_HOST=http://127.0.0.1:$TONE_PORT$TONE_PATH
fi

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
# shellcheck source=tools/ci/android-log.sh
. "$HERE/android-log.sh"
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

# A booted device is not yet one that can reach the tone. Once on record
# the emulator's Wi-Fi came up with no IPv4 route at all: DHCP re-set
# wlan0's address after netd had installed the network's routes, the
# kernel flushed them with the address, and the device spent its life
# unable to open 10.0.2.2 - so every load in both suites failed as a
# transport error, thirty times over, against an engine with nothing
# wrong with it. Ready therefore also means the device fetched the
# tone's headers itself, over the path the app takes. A network that
# never gets there has Wi-Fi cycled once, which provisions it afresh;
# one that still cannot is a device no suite can be run on, and the
# attempt ends here so the retry boots another. Each time the device
# fails, the host is asked too: a tone server that stopped answering is
# no fault of the device's network, and its routes would say nothing.

# One HEAD over toybox's netcat: a 200 means a route, a listener, and
# the file, which is everything a suite's first load needs. -w bounds
# the connect and -W an answer that stalls; the server closes after
# its headers, which is what ends the exchange otherwise. Only the
# answer is read, never how nc or adb exited.
tone_reachable() {
  local answer
  answer=$(timeout 15 adb -s "$SERIAL" shell \
    "printf 'HEAD $TONE_PATH HTTP/1.0\r\nHost: $TONE_HOSTPORT\r\n\r\n' | nc -w 5 -W 5 $TONE_HOST $TONE_PORT" \
    < /dev/null 2> /dev/null || true)
  grep -E '^HTTP/1\.[01] 200' <<< "$answer" > /dev/null
}

await_tone() {
  local budget=$1 start=$SECONDS
  while (( SECONDS - start < budget )); do
    tone_reachable && return 0
    sleep 2
  done
  return 1
}

# The device's own account of its networks, for a gate that failed or
# had to repair: the routing tables are where the flushed route shows.
record_network() {
  {
    echo "== $1"
    timeout 15 adb -s "$SERIAL" shell ip rule 2>&1 || true
    timeout 15 adb -s "$SERIAL" shell ip route show table all 2>&1 || true
    timeout 15 adb -s "$SERIAL" shell dumpsys connectivity 2>&1 | grep -E 'NetworkAgentInfo|Active default network' || true
  } >> "$OUT/network.txt"
}

host_serves_tone() {
  curl -fsS -o /dev/null --max-time 10 "$TONE_FROM_HOST" 2> /dev/null
}

# Ends the attempt before any suite, saying whose fault it was.
gate_fails() {
  local title=$1 message=$2
  echo "::error title=$title::$message"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '\n%s; no suite ran.\n' "$message" >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 1
}

gate_start=$SECONDS
if ! await_tone 45; then
  host_serves_tone ||
    gate_fails "tone server" "the host's own fetch of $TONE_FROM_HOST failed too, so the device's network is not the problem"
  echo "android-conformance: $SERIAL cannot fetch $TONE; cycling Wi-Fi"
  record_network "before cycling Wi-Fi"
  timeout 15 adb -s "$SERIAL" shell svc wifi disable < /dev/null || true
  sleep 3
  timeout 15 adb -s "$SERIAL" shell svc wifi enable < /dev/null || true
  if ! await_tone 90; then
    record_network "after cycling Wi-Fi"
    host_serves_tone ||
      gate_fails "tone server" "the host's own fetch of $TONE_FROM_HOST stopped answering while the device waited"
    gate_fails "device network" "$SERIAL could not fetch $TONE in $(( SECONDS - gate_start ))s while the host could, with Wi-Fi cycled once (network.txt has its routes)"
  fi
  record_network "after cycling Wi-Fi"
fi
echo "android-conformance: $SERIAL fetched the tone after $(( SECONDS - gate_start ))s"

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
# logcat line $1 (android-log.sh says what that looks like). When the
# drop took the logcat stream with it the lines arrive seconds late,
# from the ring buffer the follower rejoins through, so this looks for
# up to ten seconds.
transport_dropped_since() {
  local from=$1
  for _ in $(seq 1 10); do
    logcat_dropped "$from" && return 0
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

# The drop above, arriving late, kills a suite one of two ways. Before
# the tool reaches the app the suite dies - run-suite.sh's `died`, no
# test started: no device found, the Dart Development Service refusing
# to start. After, it is lost - the tool's forward to the app's VM
# service goes with the transport, and lost-android.sh tells
# run-suite.sh, which ends a tool still waiting for an isolate it can no
# longer hear from rather than let it wait out the budget, and counts a
# tool that gave up and exited the same way. Either is the harness
# failing, not the suite, and gets one more try on the same device once
# that has settled again. A death with the transport intact
# is not retried - a build that does not compile or an app that crashes
# at launch would only fail twice, and twice the time - and
# run-suite.sh's warning becomes the attempt's error. The budget stands
# per try; a hang is still the end of the attempt, and a suite that ran
# a test and failed is a failure.
suite() {
  local name=$1 budget=$2 status=0 verdict retried="" why=""
  shift 2
  if [ -n "$hung" ]; then
    skipped+=("$name")
    return 0
  fi
  # Where this suite starts in logcat: the probe reads the VM service
  # URL from here on, never from an earlier suite's lines.
  WAX_LOGCAT_FROM=$(mark_logcat "$name")
  export WAX_LOGCAT_FROM
  "$HERE/run-suite.sh" "$name" "$budget" "$OUT" "$HERE/probe-android.sh" "$HERE/lost-android.sh" -- "$@" || status=$?
  verdict=$(cat "$OUT/$name.verdict" 2> /dev/null || true)
  if [ "$verdict" = lost ]; then
    why="lost the app as the device's adb transport was rebuilt"
  elif [ "$verdict" = died ] && transport_dropped_since "$WAX_LOGCAT_FROM"; then
    why="died before its first test as the device's adb transport was rebuilt"
  fi
  if [ -n "$why" ]; then
    retried=1
    echo "android-conformance: $name $why; trying it once more"
    keep_first_try "$name"
    status=0
    verdict=""
    if await_device; then
      WAX_LOGCAT_FROM=$(mark_logcat "$name")
      "$HERE/run-suite.sh" "$name" "$budget" "$OUT" "$HERE/probe-android.sh" "$HERE/lost-android.sh" -- "$@" || status=$?
      verdict=$(cat "$OUT/$name.verdict" 2> /dev/null || true)
    else
      status=1
    fi
  fi
  if [ "$verdict" = died ]; then
    echo "::error title=$name died${retried:+ on its second try}::the harness died before the suite's first test${retried:+, again}; the warning above has the exit and the log's tail"
  elif [ "$verdict" = lost ]; then
    echo "::error title=$name lost the app${retried:+ on its second try}::the device's adb transport was rebuilt under the suite${retried:+, again}; the adb server log and logcat show the drop"
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
