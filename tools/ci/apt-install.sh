#!/usr/bin/env bash
# apt-get update, then install the packages named, on a hosted runner
# whose mirror sometimes stalls outright and sometimes crawls at a
# hundredth of its usual speed. apt is ended when it writes under 100
# KiB/s to its lists and archives for ninety seconds, and an ended or
# failed run is tried again, three times in all, starting on the next
# mirror in the runner's list; a download resumes where the last one
# stopped. The last try is ended only when it writes nothing at all, so
# a crawl on every mirror is waited out, up to the job's cap. Every
# package is fetched before any is installed, so ending apt never cuts
# dpkg off. apt's own retry is one, after fifteen silent seconds, as the
# runner image sets it: apt spends its retries on one mirror before it
# tries the next (actions/runner-images#14594).
#
#   apt-install.sh <package>...
set -euo pipefail

[ $# -gt 0 ] || {
  echo "usage: apt-install.sh <package>..." >&2
  exit 2
}
# Root from here, so the watchdog can read apt's partial downloads and
# signal apt itself: sudo ignores a signal sent from its own process group.
[ "$EUID" -eq 0 ] || exec sudo -- "$0" "$@"

APT=(apt-get -o Acquire::Retries=1 -o Acquire::http::Timeout=15 -o Acquire::https::Timeout=15
  -o DPkg::Lock::Timeout=60)
WINDOW=90
FLOOR=$((100 * 1024))
MIRRORS=/etc/apt/apt-mirrors.txt

# Never fails: a file apt renames mid-count only skews one sample.
written() {
  du -sb /var/lib/apt/lists /var/cache/apt/archives 2> /dev/null | awk '{ n += $1 } END { print n }' || true
}

# Gives the mirror apt starts on, the lowest priority number, a number
# past every other, and prints it. A failing first mirror can leave
# `apt-get update` waiting forever on index files it never requests, and
# a rerun that starts on the same mirror does the same. The list keeps
# its mode: apt reads it as the unprivileged _apt.
demote_first_mirror() {
  local uri
  [ -s "$MIRRORS" ] || return 0
  if uri=$(awk -v out="$MIRRORS.next" '
    { line[NR] = $0 }
    !/^#/ && match($0, /[\t ]priority:[0-9]+/) {
      p = substr($0, RSTART + 10, RLENGTH - 10) + 0
      if (first == "" || p < low) { low = p; first = NR }
      if (p > high) high = p
    }
    END {
      if (first != "") {
        sub(/[\t ]priority:[0-9]+/, "\tpriority:" (high + 1), line[first])
        split(line[first], uri, /[\t ]/)
        print uri[1]
      }
      for (i = 1; i <= NR; i++) print line[i] > out
    }
  ' "$MIRRORS") &&
    chmod --reference="$MIRRORS" "$MIRRORS.next" &&
    chown --reference="$MIRRORS" "$MIRRORS.next" &&
    mv "$MIRRORS.next" "$MIRRORS"; then
    echo "$uri"
  else
    rm -f "$MIRRORS.next"
    return 1
  fi
}

pid=""
# Ends apt with the script, exiting as the signal would have.
on_signal() {
  [ -z "$pid" ] || kill -TERM "$pid" 2> /dev/null || true
  exit $((128 + $1))
}
trap 'on_signal 1' HUP
trap 'on_signal 2' INT
trap 'on_signal 15' TERM

# apt-get with the arguments after <bytes>, ended once fewer than <bytes>
# have been written in $WINDOW seconds. timeout is there for its process
# group: a SIGTERM to it reaches apt-get and its fetch methods, and
# SIGKILL follows.
watched() {
  local need=$1 base since now status=0
  shift
  timeout --kill-after=15 0 "${APT[@]}" "$@" &
  pid=$!
  base=$(written)
  since=$SECONDS
  while kill -0 "$pid" 2> /dev/null; do
    sleep 1
    now=$(written)
    if (( now < base )); then
      # A list replaced or a partial file dropped: count from here.
      base=$now
    elif (( now - base >= need )); then
      base=$now
      since=$SECONDS
    elif (( SECONDS - since >= WINDOW )); then
      echo "apt-install: $(( (now - base) / 1024 )) KiB written in ${WINDOW}s; ending apt-get" >&2
      kill -TERM "$pid" 2> /dev/null || true
      break
    fi
  done
  wait "$pid" || status=$?
  pid=""
  return "$status"
}

# watched, three tries at most; only a stall ends the last.
fetch() {
  local what=$1 attempt need demoted
  shift
  for attempt in 1 2 3; do
    need=$((attempt < 3 ? FLOOR * WINDOW : 1))
    if watched "$need" "$@"; then
      return 0
    fi
    if [ "$attempt" -eq 3 ]; then
      echo "apt-install: $what did not finish in three tries" >&2
      exit 1
    fi
    demoted=$(demote_first_mirror || true)
    echo "apt-install: $what did not finish (try $attempt of 3); retrying${demoted:+ with $demoted last}" >&2
    sleep 10
  done
}

fetch "apt-get update" update
fetch "the download" install -y --no-install-recommends --download-only "$@"
"${APT[@]}" install -y --no-install-recommends --no-download "$@"
