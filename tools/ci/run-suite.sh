#!/usr/bin/env bash
# Runs one hang-prone suite under a budget and keeps what a failure
# needs to be read without a reproduction.
#
#   run-suite.sh <name> <budget-seconds> <out-dir> <probe|-> [<lost>] -- <command...>
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
# A run can also be over before it stops: the tool waiting on a device
# link that is gone waits out the whole budget. The optional <lost>
# command is polled while the run goes - `<lost> <log-path>`, exiting 0
# with the reason on stdout once the run can no longer finish - and a
# run it calls lost is ended there and then, without the probe, whose
# subject is a hang nobody can explain. A run that exits non-zero is
# asked about once more, as `<lost> <log-path> ended`: a tool that
# noticed the link go and gave up is the same harness failure as one
# that waited. Each ask is bounded, so a check that blocks cannot stand
# in for the hang it exists to catch.
#
# A <name>.report.json beside the log (`flutter test --file-reporter
# json:...`) names the last test that started, which is the one line a
# hang needs most. Verdicts: `passed`; `failed`, any non-zero exit, a
# death by signal named as such; `hung`, the budget ran out, reported as
# exit 124 the way `timeout` would; `died`, a non-zero exit before the
# report named a first test - the harness, not the suite - which a
# caller may run again, so it gets a warning annotation where the other
# two get an error, and the caller decides whether it ends up one;
# `lost`, ended by <lost> or an exit it accounts for, exit 75 (sysexits'
# EX_TEMPFAIL), which is the harness too and warned the same way. The
# verdict is written to
# <name>.verdict for that caller; a run ended by a signal leaves none.
# The failing kinds get the log's tail in a collapsed group and a
# summary row.
set -euo pipefail

usage() {
  echo "usage: run-suite.sh <name> <budget-seconds> <out-dir> <probe|-> [<lost>] -- <command...>" >&2
  exit 2
}
[ $# -ge 6 ] || usage
NAME=$1
BUDGET=$2
OUT=$3
PROBE=$4
shift 4
LOST=-
if [ "$1" != "--" ]; then
  LOST=$1
  shift
fi
{ [ $# -ge 2 ] && [ "$1" = "--" ]; } || usage
shift
# A check that cannot run would answer "not lost" forever.
if [ "$LOST" != - ] && ! command -v "$LOST" > /dev/null; then
  echo "run-suite: <lost> is not a command: $LOST" >&2
  exit 2
fi

# The probe's own bound: a probe of a hung device can hang too, and
# every minute here is a minute off the job's cap.
PROBE_BUDGET=480

# How often <lost> is asked, and how long one ask may take. A lost run
# is caught within seconds of the moment it could be, against a budget
# of ten minutes.
LOST_EVERY=5
LOST_BUDGET=30

mkdir -p "$OUT"
LOG="$OUT/$NAME.log"
REPORT="$OUT/$NAME.report.json"
VERDICT="$OUT/$NAME.verdict"
rm -f "$VERDICT"

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

# SIGTERM to the whole tree, and SIGKILL to whatever is left thirty
# seconds later.
end_child() {
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
}

hung=0
lost=""
asked=$SECONDS
while kill -0 "$child" 2> /dev/null; do
  if (( SECONDS - start >= BUDGET )); then
    hung=1
    break
  fi
  if [ "$LOST" != - ] && (( SECONDS - asked >= LOST_EVERY )); then
    asked=$SECONDS
    if reason=$(timeout --kill-after=5 "$LOST_BUDGET" "$LOST" "$LOG" 2> /dev/null); then
      # A run that ended while the check was asked has its own verdict.
      kill -0 "$child" 2> /dev/null || break
      lost=${reason:-its check said so}
      break
    fi
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
  end_child
elif [ -n "$lost" ]; then
  verdict=lost
  status=75
  echo "run-suite: $NAME can no longer finish: $lost; ending it now"
  end_child
else
  set +e
  wait "$child"
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    verdict=passed
  elif [ "$LOST" != - ] &&
    reason=$(timeout --kill-after=5 "$LOST_BUDGET" "$LOST" "$LOG" ended 2> /dev/null); then
    verdict=lost
    lost="it exited $status after ${reason:-its check said it lost its link}"
    status=75
  else
    verdict=failed
  fi
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
# A failure the report names no test for is the harness dying before
# the suite began: no device, no VM service, a build that never ran.
# Without jq the report is unreadable and the verdict stays `failed`.
if [ "$verdict" = failed ] && [ -z "$last_test" ] && command -v jq > /dev/null 2>&1; then
  verdict=died
fi
echo "$verdict" > "$VERDICT"

detail="exit $status after ${elapsed}s"
if [ "$status" -gt 128 ]; then
  detail="$detail (killed by signal $((status - 128)))"
fi
[ -n "$last_test" ] && detail="$detail; last test started: $last_test"
[ "$verdict" = lost ] && detail="$detail; $lost"
[ "$verdict" != passed ] && [ -z "$finished" ] && [ -s "$REPORT" ] &&
  detail="$detail; the reporter never wrote its end-of-run record"

echo "run-suite: $NAME $verdict ($detail)"

if [ "$verdict" != passed ]; then
  echo "::group::$NAME: last 120 lines of $LOG"
  tail -n 120 "$LOG" || true
  echo "::endgroup::"
  if [ "$verdict" = died ] || [ "$verdict" = lost ]; then
    echo "::warning title=$NAME $verdict::$detail"
  else
    echo "::error title=$NAME $verdict::$detail"
  fi
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
