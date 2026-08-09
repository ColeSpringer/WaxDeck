#!/usr/bin/env bash
# Launches the rootless server the first-run wizard journey runs
# against. The main stack (run-stack.sh) boots with the fixture library
# already configured, so `GET /admin/libraries` is never empty there and
# the wizard's entry condition cannot hold; this stack starts with no
# roots at all, which is the product state the wizard exists for.
#
# One process, deliberately: no streaming sidecar (the journey never
# plays audio; the server runs sidecar-free the way a bare install
# does), no identity provider, no podcast host. What it does need is a
# folder of real audio for the administrator to add, synthesized here
# the same way the main library is.
set -euo pipefail

E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$E2E_DIR/.run-wizard"

rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR"/{waxdeck-data,library-src}

# The folder the wizard's administrator points WaxDeck at. The upload
# preset is the small one; the journey asserts the scan lands its
# files, not any particular catalog shape.
(cd "$E2E_DIR/../fixtures" && go run ./cmd/fixturegen -out "$RUN_DIR/library-src" -preset upload >/dev/null)

# Matching off, as the main stack sets it: it defaults on, and the
# journey's whole point is a scan finishing promptly. Left on, the scan
# this spec waits for would make paced MusicBrainz lookups against the
# real internet, which is the flake the rest of this harness designs
# out.
WAXDECK_ADDR=127.0.0.1:4430 \
WAXDECK_DATA_DIR="$RUN_DIR/waxdeck-data" \
WAXDECK_MATCHING=false \
WAXDECK_PUBLIC_BASE=http://localhost:4430 \
	exec "$E2E_DIR/../server/waxdeck"
