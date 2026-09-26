#!/usr/bin/env bash
# Runs one hang-prone suite under a budget and keeps what a failure
# needs to be read without a reproduction.
#
#   run-suite.sh <name> <budget-seconds> <out-dir> <probe|-> -- <command...>
#
# The command's whole output lands in <out-dir>/<name>.log, and the
# console follows that file minus the flutter tool's verbose trace: the
# `[ +12 ms]` lines and the continuation lines indented under them.
# Anything else, a failure's multi-line Expected/Actual block included,
# reaches the console untouched, which is what lets `flutter test -v`
# ride every run.
#
# A watchdog rather than `timeout`, because the order matters: past the
# budget the suite is still running when <probe> is called - `<probe>
# <probe-dir> <log-path>` - so what it inspects is the hung state
# itself, the app process and the tool's forwards included. Only then
# does the process tree get SIGTERM, and SIGKILL thirty seconds later.
# The tree stays in this shell's process group, so a Ctrl-C reaches it
# the ordinary way, and a signal to this script is forwarded to it.
#
# A <name>.report.json beside the log (`flutter test --file-reporter
# json:...`) names the last test that started, which is the one line a
# hang needs most. Verdicts: `passed`; `failed`, any non-zero exit, a
# death by signal named as such; `hung`, the budget ran out, reported as
# exit 124 the way `timeout` would. The failing kinds get an error
# annotation, the log's tail in a collapsed group, and a summary row.
set -euo pipefail

usage() {
  echo "usage: run-suite.sh <name> <budget-seconds> <out-dir> <probe|-> -- <command...>" >&2
  exit 2
}
[ $# -ge 6 ] || usage
NAME=$1
BUDGET=$2
OUT=$3
PROBE=$4
shift 4
[ "$1" = "--" ] || usage
shift

# The probe's own bound: a probe of a hung device can hang too, and
# every minute here is a minute off the job's cap.
PROBE_BUDGET=480

mkdir -p "$OUT"
LOG="$OUT/$NAME.log"
REPORT="$OUT/$NAME.report.json"

# Every process under $1, then $1 itself.
descendants() {
  local pid=$1 child
  for child in $(pgrep -P "$pid" 2> /dev/null); do
    descendants "$child"
  done
  echo "$pid"
}

kill_tree() {
  local sig=$1 pid=$2
  # shellcheck disable=SC2046 # the pids are the words
  kill "-$sig" $(descendants "$pid") 2> /dev/null || true
}

child=""
on_signal() {
  trap - INT TERM HUP
  [ -n "$child" ] && kill_tree TERM "$child"
  exit 130
}
trap on_signal INT TERM HUP

echo "run-suite: $NAME, budget ${BUDGET}s: $*"
: > "$LOG"
"$@" > "$LOG" 2>&1 &
child=$!
start=$SECONDS

# The console view of the log. The verbose logger's prefix is a
# bracketed, right-aligned elapsed-time column eleven characters wide,
# and a multi-line message continues under it indented by that width;
# only lines inside such a message are dropped, so an indented line
# that follows reporter output is kept.
tail -n +1 -f -s 0.5 --pid="$child" "$LOG" | awk '
  /^\[ *(\+[0-9]+ ms)?\] / { inside = 1; next }
  inside && /^ {11}/ { next }
  { inside = 0; print; fflush() }
' &
follower=$!

hung=0
while kill -0 "$child" 2> /dev/null; do
  if (( SECONDS - start >= BUDGET )); then
    hung=1
    break
  fi
  sleep 1
done

if (( hung )); then
  verdict=hung
  status=124
  echo "run-suite: $NAME is still running after ${BUDGET}s; probing before the kill"
  if [ "$PROBE" != - ]; then
    probe_dir="$OUT/$NAME-probe"
    echo "::group::$NAME hung; probing into $probe_dir"
    timeout --kill-after=30 "$PROBE_BUDGET" "$PROBE" "$probe_dir" "$LOG" ||
      echo "run-suite: probe exited $?"
    echo "::endgroup::"
  fi
  kill_tree TERM "$child"
  for _ in $(seq 1 30); do
    kill -0 "$child" 2> /dev/null || break
    sleep 1
  done
  if kill -0 "$child" 2> /dev/null; then
    echo "run-suite: $NAME ignored SIGTERM for 30s; killing"
    kill_tree KILL "$child"
  fi
  wait "$child" 2> /dev/null || true
else
  set +e
  wait "$child"
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then verdict=passed; else verdict=failed; fi
fi
wait "$follower" 2> /dev/null || true
elapsed=$(( SECONDS - start ))

# What the JSON reporter saw: the last test to start, and whether the
# run reached its end. Tolerant of a file cut off mid-line, which is
# exactly what a killed run leaves.
last_test=""
finished=""
if [ -s "$REPORT" ] && command -v jq > /dev/null 2>&1; then
  last_test=$(jq -r 'select(.type == "testStart") | .test.name' "$REPORT" 2> /dev/null |
    grep -v '^loading ' | tail -n 1 || true)
  finished=$(jq -r 'select(.type == "done") | .success' "$REPORT" 2> /dev/null | tail -n 1 || true)
fi

detail="exit $status after ${elapsed}s"
if [ "$verdict" = failed ] && [ "$status" -gt 128 ]; then
  detail="$detail (killed by signal $((status - 128)))"
fi
[ -n "$last_test" ] && detail="$detail; last test started: $last_test"
[ "$verdict" != passed ] && [ -z "$finished" ] && [ -s "$REPORT" ] &&
  detail="$detail; the reporter never wrote its end-of-run record"

echo "run-suite: $NAME $verdict ($detail)"

if [ "$verdict" != passed ]; then
  echo "::group::$NAME: last 120 lines of $LOG"
  tail -n 120 "$LOG" || true
  echo "::endgroup::"
  echo "::error title=$NAME $verdict::$detail"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    if [ ! -f "$OUT/.summary-header" ]; then
      echo
      echo "| Suite | Result | Time | Last test started |"
      echo "| --- | --- | --- | --- |"
      touch "$OUT/.summary-header"
    fi
    echo "| $NAME | $verdict (exit $status) | ${elapsed}s | ${last_test//|/\\|} |"
  } >> "$GITHUB_STEP_SUMMARY"
fi

exit "$status"
