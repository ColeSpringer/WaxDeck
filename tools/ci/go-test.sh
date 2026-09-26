#!/usr/bin/env bash
# go test, with the digest a long log needs.
#
#   go-test.sh <log-file> <go test arguments...>
#
# Runs `go test` in the current directory with its output mirrored to
# <log-file>, and on failure names what failed where a reader looks
# first: an error annotation per failed test; for a run that hit its
# -timeout, the tests that were still running when it did - the line
# the goroutine dump after it is written to explain; for a panic
# outside a test (TestMain, an init, a stray goroutine), the panic
# line; and for a package that produced none of those (a build or vet
# failure), its FAIL line. The job summary gets the same. Exit status
# is go test's own.
set -uo pipefail

LOG=${1:?usage: go-test.sh <log-file> <go test arguments...>}
shift
mkdir -p "$(dirname "$LOG")"

go test "$@" 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}
[ "$status" -eq 0 ] && exit 0

# A workflow command is one line, so a message's newlines travel as
# %0A (and its percent signs as %25, so they survive the decoding).
annotate() {
  local title=$1 msg=$2
  msg=${msg//'%'/%25}
  msg=${msg//$'\r'/%0D}
  msg=${msg//$'\n'/%0A}
  echo "::error title=$title::$msg"
}

failed=$(grep -E '^\s*--- FAIL: ' "$LOG" | sed -E 's/^\s*--- FAIL: //' | sort -u || true)
packages=$(grep -E '^FAIL\s+\S+' "$LOG" | sed -E 's/^FAIL\s+//; s/\s+[0-9.]+s$//' | sort -u || true)
timed_out=$(grep -m1 -E '^panic: test timed out' "$LOG" || true)
running=$(sed -n '/^\s*running tests:/,/^\s*$/p' "$LOG" | sed -E 's/^\s+//' | head -n 40 || true)
panics=$(grep -E '^panic: ' "$LOG" | grep -v -E '^panic: test timed out' | head -n 5 || true)

while read -r t; do
  [ -n "$t" ] && annotate "Go test failed" "$t"
done <<< "$failed"
if [ -n "$timed_out" ]; then
  annotate "Go test timed out" "$timed_out"$'\n'"${running:-no running-tests block in the log}"
fi
while read -r p; do
  [ -n "$p" ] && annotate "Go test panicked" "$p"
done <<< "$panics"
if [ -z "$failed" ] && [ -z "$timed_out" ] && [ -z "$panics" ]; then
  if [ -n "$packages" ]; then
    while read -r p; do
      [ -n "$p" ] && annotate "Go package failed" "$p"
    done <<< "$packages"
  else
    annotate "Go test failed" "exit $status with no FAIL line in the log"
  fi
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Go tests: exit $status"
    echo
    if [ -n "$packages" ]; then
      echo "Failed packages:"
      echo
      sed 's/^/- `/; s/$/`/' <<< "$packages"
      echo
    fi
    if [ -n "$failed" ]; then
      echo "Failed tests:"
      echo
      sed 's/^/- `/; s/$/`/' <<< "$failed"
      echo
    fi
    if [ -n "$panics" ]; then
      echo "Panics outside a test:"
      echo
      sed 's/^/- `/; s/$/`/' <<< "$panics"
      echo
    fi
    if [ -n "$timed_out" ]; then
      echo "$timed_out"
      echo
      echo '```'
      echo "${running:-no running-tests block in the log}"
      echo '```'
      echo
    fi
    echo "The full log, goroutine dump included, is the \`server-test-log\` artifact."
  } >> "$GITHUB_STEP_SUMMARY"
fi

exit "$status"
