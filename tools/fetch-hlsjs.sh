#!/usr/bin/env bash
# Re-vendor the hls.js build the web app serves from its own origin.
#
# A browser's <audio> element takes one source, so a queue played
# gaplessly is Media Source Extensions fed by hls.js. It is served from
# this origin rather than a CDN - no third-party fetch, and it works on
# a server with no route out - and injected only when a listener
# switches gapless playback on, so an ordinary session never fetches it.
#
# The license travels beside it and is picked up by noticegen, which
# puts it in the notices the binary prints; a vendored file with no
# <name>-LICENSE.txt beside it fails that generator.
#
#   tools/fetch-hlsjs.sh [version]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/app/app/web/vendor"

# The pinned version. Passed as an argument to move it; edited here to
# keep it moved.
VERSION="${1:-1.7.2}"
TARBALL="https://registry.npmjs.org/hls.js/-/hls.js-$VERSION.tgz"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "fetch-hlsjs: $TARBALL"
curl -fsSL "$TARBALL" -o "$WORK/hls.tgz"
tar -xzf "$WORK/hls.tgz" -C "$WORK" package/dist/hls.min.js package/LICENSE

mkdir -p "$OUT"
cp "$WORK/package/dist/hls.min.js" "$OUT/hls.min.js"

# The upstream license, then the note that says what this copy is. The
# note is regenerated rather than preserved, so the version in it cannot
# drift from the file beside it.
{
  cat "$WORK/package/LICENSE"
  cat <<NOTE

--------------------------------------------------------------------------------

hls.js $VERSION, vendored from the npm registry as dist/hls.min.js and served
from this origin. It is loaded only when a listener switches gapless
playback on, so an ordinary web session never fetches it.

Regenerating: tools/fetch-hlsjs.sh [version], or by hand - fetch
$TARBALL, take package/dist/hls.min.js
and package/LICENSE, and re-add this note.
NOTE
} >"$OUT/hls-LICENSE.txt"

echo "fetch-hlsjs: wrote $(wc -c <"$OUT/hls.min.js") bytes to $OUT/hls.min.js"
