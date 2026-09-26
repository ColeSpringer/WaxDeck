#!/usr/bin/env bash
# What the desktop app and the tool looked like when a suite hung.
#
#   probe-linux.sh <out-dir> <suite-log>
#
# Run by run-suite.sh after the suite's budget expired and before the
# stack is torn down. Native thread stacks come from gdb: mpv's threads
# are where a desktop playback hang lives, and nothing else can see
# them. Yama's ptrace scope lets a process trace only its descendants,
# so gdb runs under sudo where sudo answers without a password (the
# runner) and is skipped where it does not. The suite log is the
# flutter tool's verbose trace, which names the VM service and DDS to
# ask about isolates. Every capture is best-effort and bounded.
set -uo pipefail

OUT=${1:?usage: probe-linux.sh <out-dir> <suite-log>}
LOG=${2:-}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$OUT"

cap() {
  local name=$1 status=0
  shift
  "$@" > "$OUT/$name" 2>&1 || status=$?
  if [ "$status" -ne 0 ]; then
    echo "$name: exit $status from: $*" >> "$OUT/probe-errors.txt"
  fi
}

echo "probe-linux: into $OUT"
cap host-ps.txt ps -ef --forest
cap host-listeners.txt ss -ltnp
cap pulse-sinks.txt pactl list short sinks
cap pulse-sink-inputs.txt pactl list sink-inputs
# Binary, so stderr stays out of the file.
if [ -n "${DISPLAY:-}" ] && command -v xwd > /dev/null 2>&1; then
  timeout 30 xwd -root -silent > "$OUT/screen.xwd" 2>> "$OUT/probe-errors.txt" ||
    echo "screen.xwd: exit $?" >> "$OUT/probe-errors.txt"
fi

# The app under test and the tool driving it.
pids=$( { pgrep -f 'bundle/waxdeck' || true; pgrep -f 'flutter_tools.snapshot' || true; } | sort -u)
if [ -z "$pids" ]; then
  echo "probe-linux: neither the app nor the flutter tool has a process"
fi
for pid in $pids; do
  comm=$(ps -o comm= -p "$pid" 2> /dev/null || echo unknown)
  args=$(ps -o args= -p "$pid" 2> /dev/null | cut -c1-160 || true)
  echo "probe-linux: pid $pid ($comm): $args"
  cap "status-$comm-$pid.txt" cat "/proc/$pid/status"
  cap "wchan-$comm-$pid.txt" cat "/proc/$pid/wchan"
  if command -v gdb > /dev/null 2>&1 && sudo -n true 2> /dev/null; then
    cap "stacks-$comm-$pid.txt" timeout --kill-after=10 120 sudo -n gdb -batch -p "$pid" \
      -ex 'thread apply all bt'
  else
    echo "probe-linux: no gdb under a passwordless sudo; native stacks of $pid not taken"
  fi
done

if [ -n "$LOG" ] && [ -f "$LOG" ]; then
  while read -r url; do
    label="vm-$(sed -E 's#http://127\.0\.0\.1:([0-9]+)/.*#\1#' <<< "$url")"
    "$HERE/probe-vm-service.sh" "$url" "$OUT" "$label" || true
  done < <(grep -oE 'http://127\.0\.0\.1:[0-9]+/[A-Za-z0-9_=-]+/' "$LOG" | sort -u)
fi

# The app would otherwise still hold the display and the sink when the
# next suite launches its own.
pkill -f 'bundle/waxdeck' > /dev/null 2>&1 || true
echo "probe-linux: done; $(find "$OUT" -type f | wc -l) files"
[ -f "$OUT/probe-errors.txt" ] && sed 's/^/probe-linux:   missed: /' "$OUT/probe-errors.txt"
exit 0
