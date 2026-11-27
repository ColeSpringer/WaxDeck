#!/usr/bin/env bash
# The web bundle, built the one way every caller builds it: `make web`,
# the CI, release and soak workflows, and the server image. Output lands
# in app/app/build/web.
#
# --web-content-hash: entrypoints and assets are named after their
# content, which is what lets the server cache them for good
# (server/internal/web); index.html and flutter_bootstrap.js keep their
# names and revalidate.
#
# No --no-deprecated-js-interop: the wasm compile already refuses
# dart:html, dart:js and dart:js_util, and in the JavaScript build the
# flag makes the engine's isWasm read true.
set -euo pipefail
cd "$(dirname "$0")/../app/app"
exec flutter build web --wasm --web-content-hash "$@"
