#!/usr/bin/env bash
# What the device and the tool looked like when a suite hung.
#
#   probe-android.sh <out-dir> <suite-log>
#
# Run by run-suite.sh when the suite's budget expires, while the suite
# and the app are still running. WAX_SERIAL names the device (default
# emulator-5554); WAX_LOGCAT is the logcat file the runner has been
# collecting, and WAX_LOGCAT_FROM the line it had reached when this
# suite started - only lines from there count, or a suite that hung
# before announcing its VM service would be probed at the previous
# suite's dead port and misreported. The suite log is the flutter
# tool's verbose trace, which names the host-side forward of that
# service and the DDS in front of it.
#
# Every capture is best-effort and bounded, because a probe of a hung
# device can hang too, and each writes one file under <out-dir> so a
# missing answer is visible as a missing file. The order is deliberate:
# cheap state first, then the VM service, then the bugreport (minutes,
# and it collects the app's thread traces, so it runs while the app is
# still there), and only then is the app force-stopped so the next
# launch attaches to a fresh process rather than this one.
set -uo pipefail

OUT=${1:?usage: probe-android.sh <out-dir> <suite-log>}
LOG=${2:-}
SERIAL=${WAX_SERIAL:-emulator-5554}
PKG=${WAX_ANDROID_PACKAGE:-com.colespringer.waxdeck}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$OUT"

adb_() {
  timeout --kill-after=5 20 adb -s "$SERIAL" "$@"
}

# cap <file> <command...>: the command's output, or a note of its exit.
cap() {
  local name=$1 status=0
  shift
  "$@" > "$OUT/$name" 2>&1 || status=$?
  if [ "$status" -ne 0 ]; then
    echo "$name: exit $status from: $*" >> "$OUT/probe-errors.txt"
  fi
}

echo "probe-android: $SERIAL, into $OUT"
cap host-ps.txt ps -ef --forest
cap host-listeners.txt ss -ltnp
cap adb-devices.txt adb_ devices -l
cap adb-forward.txt adb_ forward --list
cap device-ps.txt adb_ shell ps -A
cap app-pid.txt adb_ shell pidof "$PKG"
cap activities.txt adb_ shell dumpsys activity activities
cap window-focus.txt adb_ shell "dumpsys window | grep -E 'mCurrentFocus|mFocusedApp|mHoldScreen'"
cap meminfo.txt adb_ shell dumpsys meminfo "$PKG"
cap crash-buffer.txt adb_ logcat -d -b crash
cap anr-listing.txt adb_ shell ls -l /data/anr
# Binary, so stderr stays out of the file.
adb_ exec-out screencap -p > "$OUT/screen.png" 2>> "$OUT/probe-errors.txt" ||
  echo "screen.png: exit $?" >> "$OUT/probe-errors.txt"

if [ -s "$OUT/app-pid.txt" ]; then
  echo "probe-android: $PKG is alive as pid $(tr -d '[:space:]' < "$OUT/app-pid.txt")"
else
  echo "probe-android: $PKG has no process"
fi
grep -E 'mCurrentFocus|mFocusedApp' "$OUT/window-focus.txt" 2> /dev/null | sed 's/^/probe-android:   /' || true
grep -m1 -E 'topResumedActivity|ResumedActivity' "$OUT/activities.txt" 2> /dev/null | sed 's/^/probe-android:   /' || true

# The app's VM service, reached through a forward of our own: the
# tool's forward may be what is wedged. The token rides the URL.
if [ -n "${WAX_LOGCAT:-}" ] && [ -f "$WAX_LOGCAT" ]; then
  from=${WAX_LOGCAT_FROM:-1}
  dev_url=$(tail -n "+$from" "$WAX_LOGCAT" |
    grep -oE 'http://127\.0\.0\.1:[0-9]+/[A-Za-z0-9_=-]+/' | tail -n 1 || true)
  if [ -n "$dev_url" ]; then
    port=$(sed -E 's#http://127\.0\.0\.1:([0-9]+)/.*#\1#' <<< "$dev_url")
    token=$(sed -E 's#http://127\.0\.0\.1:[0-9]+/(.*)#\1#' <<< "$dev_url")
    local_port=$(adb_ forward tcp:0 "tcp:$port" 2> /dev/null | tr -d '[:space:]' || true)
    if [[ "$local_port" =~ ^[0-9]+$ ]]; then
      echo "probe-android: device VM service $dev_url forwarded to :$local_port"
      "$HERE/probe-vm-service.sh" "http://127.0.0.1:$local_port/$token" "$OUT" device-vm-service || true
      adb_ forward --remove "tcp:$local_port" > /dev/null 2>&1 || true
    else
      echo "probe-android: could not forward the device VM service port $port"
    fi
  else
    echo "probe-android: no VM service URL in logcat since this suite started (line $from): the app never announced one"
  fi
fi

# The tool's own forward and its DDS, both on the host.
if [ -n "$LOG" ] && [ -f "$LOG" ]; then
  while read -r url; do
    label="host-$(sed -E 's#http://127\.0\.0\.1:([0-9]+)/.*#\1#' <<< "$url")"
    "$HERE/probe-vm-service.sh" "$url" "$OUT" "$label" || true
  done < <(grep -oE 'http://127\.0\.0\.1:[0-9]+/[A-Za-z0-9_=-]+/' "$LOG" | sort -u)
fi

# Everything Android knows, thread traces of the app included.
echo "probe-android: collecting a bugreport"
cap bugreport.log timeout --kill-after=20 180 adb -s "$SERIAL" bugreport "$OUT/bugreport.zip"

adb_ shell am force-stop "$PKG" > /dev/null 2>&1 || true
echo "probe-android: done; $(find "$OUT" -type f | wc -l) files"
[ -f "$OUT/probe-errors.txt" ] && sed 's/^/probe-android:   missed: /' "$OUT/probe-errors.txt"
exit 0
