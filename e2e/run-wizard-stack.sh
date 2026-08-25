#!/usr/bin/env bash
# The rootless server for the first-run wizard journey: the main stack
# boots with libraries configured, so the wizard's entry condition can
# only hold here. One process, no sidecar - a bare install's shape.
set -euo pipefail

E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$E2E_DIR/.run-wizard"

# Native form for the server's env paths; see run-stack.sh.
RUN_DIR_NATIVE="$RUN_DIR"
command -v cygpath >/dev/null 2>&1 && RUN_DIR_NATIVE="$(cygpath -m "$RUN_DIR")"

rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR"/{waxdeck-data,library-src}

# The folder the wizard's administrator points WaxDeck at.
(cd "$E2E_DIR/../fixtures" && go run ./cmd/fixturegen -out "$RUN_DIR_NATIVE/library-src" -preset upload >/dev/null)

# Matching off or the scan this spec waits on would make paced
# MusicBrainz lookups against the real internet.
WAXDECK_ADDR=127.0.0.1:4430 \
WAXDECK_DATA_DIR="$RUN_DIR_NATIVE/waxdeck-data" \
WAXDECK_MATCHING=false \
WAXDECK_ARTIST_ART=false \
WAXDECK_PUBLIC_BASE=http://localhost:4430 \
	exec "$E2E_DIR/../server/waxdeck"
