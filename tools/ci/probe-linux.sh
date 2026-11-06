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
#
# gdb goes last, and to the app last of all: attaching interrupts every
# blocked call in the process, which can end the hang being probed (one
# app resumed the moment gdb let go of it). So everything that only
# reads - each thread's state and kernel stack, the isolates - comes
# first.
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

SUDO=
sudo -n true 2> /dev/null && SUDO=1

# A line per thread of $1: id, run state, CPU ticks so far, kernel wait
# channel and name. Builtins only, so a pass takes milliseconds and every
# thread's second sample is a second after its first.
sample() {
  local pid=$1 task stat wchan comm f
  for task in /proc/"$pid"/task/*; do
    { read -r stat < "$task/stat"; } 2> /dev/null || continue
    # The name sits in parentheses and may hold anything, so the fixed
    # fields are counted from the last ')'.
    read -r -a f <<< "${stat##*) }"
    wchan='' comm=''
    { read -r wchan < "$task/wchan"; } 2> /dev/null
    { read -r comm < "$task/comm"; } 2> /dev/null
    echo "${task##*/} ${f[0]:-?} $((${f[11]:-0} + ${f[12]:-0})) ${wchan:--} $comm"
  done
}

# Every thread of $1 twice, a second apart, which tells one spinning (its
# ticks moved) from one parked, then their kernel stacks, in one sudo where
# sudo answers. Fails when not one thread could be read.
threads() {
  local pid=$1 first
  first=$(sample "$pid")
  if [ -z "$first" ]; then
    echo "no thread of $pid could be read: the process is gone"
    return 1
  fi
  echo "$first"
  sleep 1
  echo "# one second later"
  sample "$pid"
  if [ -n "$SUDO" ]; then
    echo "# kernel stacks"
    # shellcheck disable=SC2016 # expanded by the root shell, not this one
    sudo -n bash -c 'for t in /proc/"$1"/task/*; do
      echo "${t##*/}:"
      while IFS= read -r line; do echo "    $line"; done < "$t/stack"
    done' _ "$pid" 2> /dev/null
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

# The app under test, then the tool driving it. Each one's files are
# named after its process name, which can hold any character but '/';
# upload-artifact refuses a whole artifact over one ':' in a file name,
# and the tool's is "dart:flutter_to".
pids=$( { pgrep -f 'bundle/waxdeck' || true; pgrep -f 'flutter_tools.snapshot' || true; } | awk '!seen[$0]++')
if [ -z "$pids" ]; then
  echo "probe-linux: neither the app nor the flutter tool has a process"
fi
declare -A names
for pid in $pids; do
  comm=$(ps -o comm= -p "$pid" 2> /dev/null || echo unknown)
  names[$pid]=${comm//[^A-Za-z0-9._-]/_}
  args=$(ps -o args= -p "$pid" 2> /dev/null | cut -c1-160 || true)
  echo "probe-linux: pid $pid ($comm): $args"
  cap "status-${names[$pid]}-$pid.txt" cat "/proc/$pid/status"
  cap "threads-${names[$pid]}-$pid.txt" threads "$pid"
done

if [ -n "$LOG" ] && [ -f "$LOG" ]; then
  while read -r url; do
    label="vm-$(sed -E 's#http://127\.0\.0\.1:([0-9]+)/.*#\1#' <<< "$url")"
    "$HERE/probe-vm-service.sh" "$url" "$OUT" "$label" || true
  done < <(grep -oE 'http://127\.0\.0\.1:[0-9]+/[A-Za-z0-9_=-]+/' "$LOG" | sort -u)
fi

if command -v gdb > /dev/null 2>&1 && [ -n "$SUDO" ]; then
  # The runner has no debug symbols, so the stacks are mostly offsets;
  # the library map beside them is what resolves those afterwards. -c,
  # because by default one thread whose unwinding fails ends the rest.
  for pid in $(tac <<< "$pids"); do
    cap "stacks-${names[$pid]}-$pid.txt" timeout --kill-after=10 120 sudo -n gdb -batch -p "$pid" \
      -ex 'thread apply all -c bt' -ex 'info sharedlibrary'
  done
elif [ -n "$pids" ]; then
  echo "probe-linux: no gdb under a passwordless sudo; native stacks not taken"
fi

# The app would otherwise still hold the display and the sink when the
# next suite launches its own.
pkill -f 'bundle/waxdeck' > /dev/null 2>&1 || true
echo "probe-linux: done; $(find "$OUT" -type f | wc -l) files"
[ -f "$OUT/probe-errors.txt" ] && sed 's/^/probe-linux:   missed: /' "$OUT/probe-errors.txt"
exit 0
