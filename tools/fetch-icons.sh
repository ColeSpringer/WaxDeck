#!/usr/bin/env bash
# Rebuild the vendored icon subsets waxdeck_ui ships.
#
# WaxDeck draws Phosphor (MIT) in two weights: regular for inactive and
# fill for active. The upstream Flutter package cannot be used on Flutter
# 3.44 (it subclasses IconData, which is now a final class), so the fonts
# are vendored directly and WaxIcon wraps them, which is the swap the
# wrapper existed for.
#
# The glyph list is not configured here: it is read out of
# lib/src/icons/wax_icon.dart, the file that declares which icons exist.
# Add an icon there, re-run this, and the subsets follow.
#
#   tools/fetch-icons.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UI="$ROOT/app/packages/waxdeck_ui"
OUT="$UI/fonts"
CACHE="$ROOT/tools/.cache/fonttools"

# phosphor-icons/web revision the vendored glyphs come from (2026-07-24).
ICONS_REV=3d40a3eaa73b25d20d263f0e1e55c9fed3e66809
RAW="https://raw.githubusercontent.com/phosphor-icons/web/$ICONS_REV"

if [ ! -f "$CACHE/fontTools/subset/__init__.py" ]; then
  echo "fetch-icons: run tools/fetch-fonts.sh first (it provisions fonttools)" >&2
  exit 1
fi

codepoints=$(grep -o 'IconData(0x[0-9A-Fa-f]\{4\}' "$UI/lib/src/icons/wax_icon.dart" \
  | sed 's/IconData(0x/U+/' | sort -u | paste -sd, -)
count=$(printf '%s\n' "$codepoints" | tr ',' '\n' | wc -l)
echo "fetch-icons: subsetting $count glyphs" >&2

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$OUT" "$OUT/licenses"

curl -fsSL -o "$work/regular.ttf" "$RAW/src/regular/Phosphor.ttf"
curl -fsSL -o "$work/fill.ttf" "$RAW/src/fill/Phosphor-Fill.ttf"
curl -fsSL -o "$OUT/licenses/phosphor-LICENSE.txt" "$RAW/LICENSE"

subset() {
  PYTHONPATH="$CACHE" python3 -m fontTools.subset "$1" \
    --output-file="$2" \
    --unicodes="$codepoints" \
    --no-layout-closure \
    --drop-tables+=DSIG
}
subset "$work/regular.ttf" "$OUT/PhosphorRegular-Subset.ttf"
subset "$work/fill.ttf" "$OUT/PhosphorFill-Subset.ttf"

# The manifest is what test/icons_test.dart checks the Dart declarations
# against, so a glyph can never be named in code but missing from the
# font that has to draw it.
PYTHONPATH="$CACHE" python3 - "$OUT" <<'PY'
import json, sys
from fontTools.ttLib import TTFont

out = sys.argv[1]
manifest = {}
for name, path in (
    ('PhosphorRegular', f'{out}/PhosphorRegular-Subset.ttf'),
    ('PhosphorFill', f'{out}/PhosphorFill-Subset.ttf'),
):
    font = TTFont(path)
    manifest[name] = sorted(font.getBestCmap())
with open(f'{out}/phosphor-subset.json', 'w') as fh:
    json.dump(manifest, fh, indent=2)
    fh.write('\n')
PY

ls -l "$OUT"/Phosphor*.ttf | awk '{ printf "  %-32s %7.1f KB\n", $NF, $5/1024 }' | sed "s|$OUT/||"
