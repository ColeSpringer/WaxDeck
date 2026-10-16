#!/usr/bin/env bash
# Whether a suite has lost the app it launched.
#
#   lost-android.sh <suite-log> [ended]
#
# run-suite.sh's <lost> check: it exits 0 with the reason on stdout when
# the flutter tool's link to the app is gone, and 1 otherwise. The tool
# reaches the app's VM service through one adb forward, made once, with
# the Dart Development Service riding it; a rebuilt adb transport takes
# every forward with it, and the tool either fails or goes on waiting for
# an isolate event that can no longer arrive. One saf_channel launch
# waited out its whole ten-minute budget that way, a second after its
# forward was made.
#
# Lost means the tool names its forward in its verbose trace, and the
# guest's adbd logged its host transport dying after the app announced
# the forwarded port (WAX_LOGCAT, read from line WAX_LOGCAT_FROM). A
# rebuild before the announcement happened to a launch the tool then
# reached over the new transport. While the run goes, two more things
# have to hold before it is ended: the tool has not begun its own
# teardown, which is a run finishing however its forward fares, and adb
# no longer lists the forward. Asked with `ended`, after the run exited
# non-zero, it says whether that exit came of a lost link, waiting a
# little for drop lines a rejoining logcat brings late. WAX_SERIAL names
# the device.
set -uo pipefail

LOG=${1:?usage: lost-android.sh <suite-log> [ended]}
ENDED=${2:-}
SERIAL=${WAX_SERIAL:-emulator-5554}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=tools/ci/android-log.sh
. "$HERE/android-log.sh"

[ -n "${WAX_LOGCAT:-}" ] && [ -f "$WAX_LOGCAT" ] || exit 1
forward=$(tool_forward "$LOG")
[ -n "$forward" ] || exit 1
host=${forward% *}
device=${forward#* }
reason="the device's adb transport was rebuilt and took the tool's forward to the app (tcp:$host to tcp:$device) with it"

listed() {
  local forwards
  forwards=$(timeout 5 adb forward --list 2> /dev/null || true)
  grep -F "$SERIAL tcp:$host tcp:$device" <<< "$forwards" > /dev/null
}

if [ "$ENDED" = ended ]; then
  # A forward still listed is a transport that never dropped, which
  # answers at once what the wait below would only confirm.
  listed && exit 1
  for _ in $(seq 1 10); do
    if logcat_dropped "${WAX_LOGCAT_FROM:-1}" "$device"; then
      echo "$reason"
      exit 0
    fi
    sleep 1
  done
  exit 1
fi

# Cheapest first, since this is asked every few seconds of every run:
# the trace, then one adb round trip, and only for a forward that is
# gone the device log, which grows to tens of megabytes.
grep -E 'test [0-9]+: (Test harness is no longer needed|cleaning up)' "$LOG" > /dev/null 2>&1 && exit 1
listed && exit 1
logcat_dropped "${WAX_LOGCAT_FROM:-1}" "$device" || exit 1
echo "$reason"
