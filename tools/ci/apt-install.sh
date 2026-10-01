#!/usr/bin/env bash
# apt-get update, then install the packages named, on a hosted runner
# whose mirror stalls now and then: one Package run sat in `apt-get
# update` for its job's whole twenty-minute cap, the index fetch neither
# finishing nor failing. So apt gives up on a silent connection in
# thirty seconds and retries the file, a fetch still going after ninety
# is killed and the update tried again, three times, and the install
# gets the same treatment with room for a real one. Bounded to fit
# inside the smallest job cap that calls this, twenty minutes, next to
# a build of a few. The timeout runs under sudo so its signals reach
# apt itself, not just the sudo in front of it.
#
#   apt-install.sh <package>...
set -euo pipefail

[ $# -gt 0 ] || {
  echo "usage: apt-install.sh <package>..." >&2
  exit 2
}

APT=(apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30)

for attempt in 1 2 3; do
  if sudo timeout --kill-after=15 90 "${APT[@]}" update; then
    break
  fi
  if [ "$attempt" -eq 3 ]; then
    echo "apt-install: apt-get update failed three times" >&2
    exit 1
  fi
  echo "apt-install: apt-get update stalled or failed (attempt $attempt of 3); retrying" >&2
  sleep 10
done

for attempt in 1 2; do
  if sudo timeout --kill-after=30 240 "${APT[@]}" install -y --no-install-recommends "$@"; then
    exit 0
  fi
  if [ "$attempt" -eq 2 ]; then
    echo "apt-install: apt-get install failed twice" >&2
    exit 1
  fi
  echo "apt-install: apt-get install stalled or failed; retrying" >&2
  sleep 10
done
