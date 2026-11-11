#!/usr/bin/env bash
# Leaves the e2e suite's Chromium able to start, asking apt only when it
# cannot. A hosted runner carries every library Chromium links against,
# so the probe passes there and nothing is fetched. When it fails, the
# packages Playwright reports missing go through apt-install.sh, which
# outlasts a stalled mirror; `install-deps` itself, which does not, is
# for a report this cannot read.
#
#   playwright-deps.sh        (after `npm ci` in e2e/)
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
cd "$here/../../e2e"

if node tools/chromium-starts.mjs; then
  exit 0
fi

# The dry run prints what `apt-get install -s` would add, one indented
# package to a line, and exits 1 when that is anything.
report=$(npx playwright install-deps --dry-run chromium 2> /dev/null || true)
mapfile -t packages < <(sed -n 's/^  \([a-z0-9][a-z0-9.+:-]*\)$/\1/p' <<< "$report")
if (( ${#packages[@]} )); then
  "$here/apt-install.sh" "${packages[@]}"
else
  npx playwright install-deps chromium
fi
node tools/chromium-starts.mjs
