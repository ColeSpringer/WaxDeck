#!/usr/bin/env bash
# Judges WaxSeal in a compose stack that is already up. The daemon turns
# healthy once YouTube has served its browser a watch page and exits when
# it has not (docs/upstream-requests.md), and YouTube does not serve every
# runner's address. That refusal is a warning; everything else about the
# daemon not coming up fails:
#
#   - no "startup checks failed" in its log: it never got past its flags,
#     its port or its browser's launch
#   - a startup failure that is not the refusal, or one that could not
#     reach YouTube while this runner can
#   - a browser that cannot render a page with no network at all under
#     the service's own limits (`doctor --stop-after-load`)
#
# The daemon restarts itself, so two failures are waited for: one slow
# page load is not a refusal. A refused daemon is stopped, or it would
# relaunch and ask again every half minute.
#
#   waxseal-starts.sh <compose-file>
set -euo pipefail

[ $# -eq 1 ] || {
  echo "usage: waxseal-starts.sh <compose-file>" >&2
  exit 2
}
file=$1
compose() { docker compose -f "$file" "$@"; }

id=$(compose ps -aq waxseal)
[ -n "$id" ] || {
  echo "::error::the stack has no WaxSeal container"
  exit 1
}

# Twice the daemon's own budget for a verdict: its warm-up is cut at 120s.
deadline=$((SECONDS + 240))
failed=()
while (( SECONDS < deadline )); do
  health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$id" 2> /dev/null || true)
  if [ "$health" = healthy ]; then
    echo "WaxSeal is healthy"
    exit 0
  fi
  mapfile -t failed < <(compose logs --no-color waxseal 2>&1 | grep 'startup checks failed' || true)
  (( ${#failed[@]} < 2 )) || break
  sleep 2
done
if (( ${#failed[@]} == 0 )); then
  echo "::error::WaxSeal neither turned healthy nor reached its startup checks"
  exit 1
fi

printf '%s\n' "${failed[@]}"
for line in "${failed[@]}"; do
  cause=${line##*err=}
  case $cause in
    *'ytcfg visitor_data not available'*) ;;
    *'navigate landing page'*'net::ERR_'*)
      # Host networking: what the daemon cannot reach, the runner cannot.
      if curl -sS -o /dev/null --max-time 15 https://www.youtube.com/; then
        echo "::error::WaxSeal cannot reach YouTube and this runner can: $cause"
        exit 1
      fi
      ;;
    *)
      echo "::error::WaxSeal's startup checks failed, and not on a refusal by YouTube: $cause"
      exit 1
      ;;
  esac
done

compose stop waxseal
compose run --rm --no-deps -T waxseal doctor --stop-after-load
echo "::warning::WaxSeal's browser runs, but YouTube did not serve it on this runner: $cause"
