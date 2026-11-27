#!/usr/bin/env bash
# Leaves the e2e suite's browsers able to start and play, asking apt only
# for what is missing. A launch answers it for Chromium alone: every
# package `playwright install-deps` names for it is a library its binary
# links, and a hosted runner carries them all, so nothing is fetched.
# WebKit and Firefox also name media plugins they load only to decode,
# which a launch never reaches, so their list is read from the dry run.
# Missing packages go through apt-install.sh, which outlasts a stalled
# mirror; `install-deps` itself, which does not, is for a report this
# cannot read.
#
#   playwright-deps.sh [browser...]   (after `npm ci` in e2e/; default chromium)
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
cd "$here/../../e2e"

browsers=("${@:-chromium}")
if [ "${browsers[*]}" = chromium ] && node tools/browsers-start.mjs chromium; then
  exit 0
fi

# The dry run prints what `apt-get install -s` would add, one indented
# package to a line, and exits 1 when that is anything.
report=$(npx playwright install-deps --dry-run "${browsers[@]}" 2> /dev/null || true)
mapfile -t packages < <(sed -n 's/^  \([a-z0-9][a-z0-9.+:-]*\)$/\1/p' <<< "$report")
if (( ${#packages[@]} )); then
  "$here/apt-install.sh" "${packages[@]}"
elif ! grep -q '^All system dependencies are installed' <<< "$report"; then
  npx playwright install-deps "${browsers[@]}"
fi
node tools/browsers-start.mjs "${browsers[@]}"
