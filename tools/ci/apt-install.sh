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
# A mirror the resolver has no address for is looked up at a public
# resolver instead and held in /etc/hosts until a try fails or the
# script exits. When ubuntu.com's nameservers stop answering, a runner's
# resolver times out on every mirror for the whole job, while the
# mirrors are up and the public resolvers still serve the records they
# hold.
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

# No SRV lookup: apt makes one before it asks for a host's address, no
# host in the runner's sources has the record, and a resolver that is
# failing takes ten seconds over each one.
APT=(apt-get -o Acquire::Retries=1 -o Acquire::http::Timeout=15 -o Acquire::https::Timeout=15
  -o DPkg::Lock::Timeout=60 -o Acquire::EnableSrvRecords=false)
WINDOW=90
FLOOR=$((100 * 1024))
MIRRORS=/etc/apt/apt-mirrors.txt
HOSTS=/etc/hosts
PIN="# apt-install.sh"
# Asked by address over HTTPS, so reaching one takes no lookup.
RESOLVERS=(1.1.1.1 9.9.9.9 8.8.8.8)
# Mirrors no resolver had an address for. They are not asked about
# again: each costs up to thirty-five seconds to find out.
declare -A unplaced=()

# Pins each mirror in the runner's list that the resolver gives no
# address for in five seconds. curl does the lookup and the proof in one
# request: it resolves through the public resolver, fetches the mirror's
# root, and reports the address that answered.
pin_unresolved_mirrors() {
  local uri host resolver ip lead
  [ -s "$MIRRORS" ] && command -v curl > /dev/null || return 0
  # The last line counts with or without its newline.
  while read -r uri _ <&3 || [ -n "$uri" ]; do
    [[ $uri == http://* || $uri == https://* ]] || continue
    host=${uri#*://}
    host=${host%%[:/]*}
    [ -z "${unplaced[$host]:-}" ] || continue
    timeout 5 getent ahosts "$host" > /dev/null 2>&1 && continue
    ip=""
    for resolver in "${RESOLVERS[@]}"; do
      ip=$(curl -sS --doh-url "https://$resolver/dns-query" --connect-timeout 5 --max-time 10 \
        -o /dev/null -w '%{remote_ip}' "$uri" 2> /dev/null) && [ -n "$ip" ] && break
      ip=""
    done
    if [ -z "$ip" ]; then
      unplaced[$host]=1
      echo "apt-install: the resolver has no address for $host, nor has any of ${RESOLVERS[*]}" >&2
      continue
    fi
    lead=""
    [ -z "$(tail -c 1 "$HOSTS")" ] || lead=$'\n'
    printf '%s%s %s %s\n' "$lead" "$ip" "$host" "$PIN" >> "$HOSTS" || {
      echo "apt-install: could not write $HOSTS" >&2
      return 0
    }
    echo "apt-install: the resolver has no address for $host; using $ip, from $resolver" >&2
  done 3< "$MIRRORS"
}

# Drops the pins and never fails, so the exit status stays apt's. By
# rename where /etc/hosts can be replaced, so it is never seen cut
# short; a container's is a mount, and a link is not ours to replace,
# so those are rewritten in place.
unpin_mirrors() {
  grep -qF " $PIN" "$HOSTS" 2> /dev/null || return 0
  if { grep -vF " $PIN" "$HOSTS" || [ $? -eq 1 ]; } > "$HOSTS.next"; then
    if [ ! -L "$HOSTS" ] && chmod --reference="$HOSTS" "$HOSTS.next" &&
      chown --reference="$HOSTS" "$HOSTS.next" && mv "$HOSTS.next" "$HOSTS" 2> /dev/null; then
      return 0
    fi
    if cat "$HOSTS.next" > "$HOSTS"; then
      rm -f "$HOSTS.next"
      return 0
    fi
  fi
  rm -f "$HOSTS.next" 2> /dev/null || true
  echo "apt-install: could not take its pins out of $HOSTS" >&2
}
trap unpin_mirrors EXIT
# A killed run leaves its pins, and they would pass for the resolver's
# answer here.
unpin_mirrors

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
# SIGTERM to apt-get and its fetch methods, then SIGKILL to whatever is
# left of the group fifteen seconds on. Until setsid has run there is no
# group, only the child.
end_apt() {
  local left=15
  kill -TERM -- "-$pid" 2> /dev/null || {
    kill -TERM "$pid" 2> /dev/null || true
    return 0
  }
  while kill -0 -- "-$pid" 2> /dev/null; do
    if (( left-- == 0 )); then
      kill -KILL -- "-$pid" 2> /dev/null || true
      return 0
    fi
    sleep 1
  done
}

# Ends apt with the script, exiting as the signal would have.
on_signal() {
  [ -z "$pid" ] || end_apt
  exit $((128 + $1))
}
trap 'on_signal 1' HUP
trap 'on_signal 2' INT
trap 'on_signal 15' TERM

# apt-get with the arguments after <bytes>, ended once fewer than <bytes>
# have been written in $WINDOW seconds. setsid gives apt-get a process
# group of its own, which its fetch methods join, so one signal reaches
# them all. Not timeout for that: with no duration, the Rust coreutils
# one (Ubuntu 26.04) drops a SIGTERM instead of passing it on.
watched() {
  local need=$1 base since now status=0
  shift
  setsid "${APT[@]}" "$@" &
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
      end_apt
      break
    fi
  done
  wait "$pid" || status=$?
  pid=""
  return "$status"
}

# watched, three tries at most; only a stall ends the last. Each try
# starts with every mirror it can give an address, and a failed one
# takes its pins with it: the next looks the mirrors up afresh instead
# of going back to an address that may be what stalled.
fetch() {
  local what=$1 attempt need demoted
  shift
  for attempt in 1 2 3; do
    pin_unresolved_mirrors
    need=$((attempt < 3 ? FLOOR * WINDOW : 1))
    if watched "$need" "$@"; then
      return 0
    fi
    if [ "$attempt" -eq 3 ]; then
      echo "apt-install: $what did not finish in three tries" >&2
      exit 1
    fi
    unpin_mirrors
    demoted=$(demote_first_mirror || true)
    echo "apt-install: $what did not finish (try $attempt of 3); retrying${demoted:+ with $demoted last}" >&2
    sleep 10
  done
}

fetch "apt-get update" update
fetch "the download" install -y --no-install-recommends --download-only "$@"
"${APT[@]}" install -y --no-install-recommends --no-download "$@"
