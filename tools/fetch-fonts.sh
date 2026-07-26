#!/usr/bin/env bash
# Fetch and subset the fonts waxdeck_ui bundles.
#
# WaxDeck ships its type as assets: the app must render correctly
# offline, self-hosted, and air-gapped, so nothing is ever fetched from a
# third-party CDN at runtime (Flutter web's default Noto fallback does
# exactly that, which a LAN-only instance cannot reach).
#
# The output lands in app/packages/waxdeck_ui/fonts/ and is committed.
# Re-run this only to refresh or re-scope a family; the pinned upstream
# revision below makes the output reproducible.
#
#   tools/fetch-fonts.sh            # the bundled chain
#   tools/fetch-fonts.sh --report   # sizes only, no download
#
# Variable axes survive subsetting on purpose: the type tokens select
# weights through FontVariation (460/520/560/620) and Archivo's width
# axis, none of which are reachable through fontWeight's 100-step ladder.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Two destinations, one distinction: fonts/ holds the faces pubspec
# declares (loaded eagerly at startup), assets/fonts/ holds the faces
# WaxFonts loads on demand when the text on screen needs their script
# (Arabic, Hebrew, Thai, CJK). Startup pays only for the primary chain.
OUT="$ROOT/app/packages/waxdeck_ui/fonts"
OUT_DEFER="$ROOT/app/packages/waxdeck_ui/assets/fonts"
CACHE="$ROOT/tools/.cache"
VENV="$CACHE/fonttools"

# google/fonts revision the bundled files come from (2026-07-24).
FONTS_REV=7ff85c87f93ea6cca5f41c69f2e4edcb90240f26
RAW="https://raw.githubusercontent.com/google/fonts/$FONTS_REV"

# notofonts/noto-cjk commit for the CJK face (tag Sans2.004). The full
# face, not a subset: a curated "common hanzi" core still renders boxes
# for any name outside it, which is the exact failure this asset exists
# to close. One regional face carries the whole pan-CJK repertoire (Han
# with simplified defaults, kana, hangul); the variable and all-regions
# builds are twice the bytes for glyph variants nobody is missing.
NOTO_CJK_SHA=523d033d6cb47f4a80c58a35753646f5c3608a78
NOTO_CJK_RAW="https://raw.githubusercontent.com/notofonts/noto-cjk/$NOTO_CJK_SHA"

# Latin plus the scripts Inter covers natively: Latin Extended A/B and
# Additional, combining marks, Greek, Cyrillic (with supplement),
# punctuation, currency, and the handful of symbols an interface uses.
LATIN_PLUS='U+0000-00FF,U+0100-024F,U+0259,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0300-036F,U+0370-03FF,U+0400-052F,U+1E00-1EFF,U+2000-206F,U+2070-209F,U+20A0-20BF,U+2100-214F,U+2190-2199,U+2212,U+2215,U+25A0-25CF,U+2605-2606,U+FEFF,U+FFFD'
ARABIC='U+0600-06FF,U+0750-077F,U+08A0-08FF,U+FB50-FDFF,U+FE70-FEFF,U+200C-200E,U+2010-2011,U+204F,U+2E41'
HEBREW='U+0590-05FF,U+200C-2010,U+20AA,U+25CC,U+FB1D-FB4F'
THAI='U+0E01-0E5B,U+200C-200D,U+25CC'

report_only=false
[ "${1:-}" = "--report" ] && report_only=true

FONTTOOLS_WHEEL="https://files.pythonhosted.org/packages/9c/57/c2487c281dde03abb2dec244fd67059b8d118bd30a653cbf69e94084cb23/fonttools-4.62.0-py3-none-any.whl"

if ! $report_only; then
  # fonttools has no system package guarantee; the script owns its own
  # copy the way generate-dart.sh owns its JRE. The wheel is a zip of
  # pure Python, so unpacking it beats depending on pip or venv being
  # usable (Debian's python3 ships without ensurepip).
  if [ ! -f "$VENV/fontTools/subset/__init__.py" ]; then
    echo "fetch-fonts: provisioning fonttools into tools/.cache/fonttools" >&2
    mkdir -p "$VENV"
    curl -fsSL -o "$VENV/fonttools.whl" "$FONTTOOLS_WHEEL"
    python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" \
      "$VENV/fonttools.whl" "$VENV"
    rm -f "$VENV/fonttools.whl"
  fi
  subset() { PYTHONPATH="$VENV" python3 -m fontTools.subset "$@"; }

  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  mkdir -p "$OUT" "$OUT/licenses" "$OUT_DEFER"

  # family_dir  upstream_file  output_name  unicode_ranges  dest_dir
  fetch() {
    local dir="$1" file="$2" out="$3" ranges="$4" dest="$5"
    echo "fetch-fonts: $out" >&2
    curl -fsSL -o "$work/$out.src.ttf" "$RAW/ofl/$dir/$file"
    curl -fsSL -o "$OUT/licenses/$dir-OFL.txt" "$RAW/ofl/$dir/OFL.txt"
    # Keep layout features (kerning, ligatures, mark positioning) and the
    # variation tables; drop the glyphs outside the declared scripts.
    subset "$work/$out.src.ttf" \
      --output-file="$dest/$out" \
      --unicodes="$ranges" \
      --layout-features='*' \
      --name-IDs='*' --name-legacy --name-languages='*' \
      --notdef-outline --recommended-glyphs \
      --drop-tables+=DSIG
  }

  fetch archivo        'Archivo%5Bwdth,wght%5D.ttf'      Archivo-Variable.ttf        "$LATIN_PLUS" "$OUT"
  fetch inter          'Inter%5Bopsz,wght%5D.ttf'        Inter-Variable.ttf          "$LATIN_PLUS" "$OUT"
  fetch splinesansmono 'SplineSansMono%5Bwght%5D.ttf'    SplineSansMono-Variable.ttf "$LATIN_PLUS" "$OUT"
  fetch notosansarabic 'NotoSansArabic%5Bwdth,wght%5D.ttf' NotoSansArabic-Variable.ttf "$ARABIC" "$OUT_DEFER"
  fetch notosanshebrew 'NotoSansHebrew%5Bwdth,wght%5D.ttf' NotoSansHebrew-Variable.ttf "$HEBREW" "$OUT_DEFER"
  fetch notosansthai   'NotoSansThai%5Bwdth,wght%5D.ttf'   NotoSansThai-Variable.ttf   "$THAI" "$OUT_DEFER"

  # The CJK face ships verbatim: full coverage is its whole purpose.
  echo "fetch-fonts: NotoSansCJK.otf (full face, no subsetting)" >&2
  curl -fsSL -o "$OUT_DEFER/NotoSansCJK.otf" \
    "$NOTO_CJK_RAW/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf"
  curl -fsSL -o "$OUT/licenses/noto-cjk-OFL.txt" "$NOTO_CJK_RAW/LICENSE"

  # Coverage gate: the point of shipping the full face is that Han, kana,
  # and hangul all render. A wrong upstream file (a regional subset build
  # slips in, say) must fail here, not as tofu on someone's library.
  PYTHONPATH="$VENV" python3 - "$OUT_DEFER/NotoSansCJK.otf" <<'PYEOF'
import sys
from fontTools.ttLib import TTFont

need = {
    0x4E2D: 'han (URO)', 0x3400: 'han (ext A)', 0x9FA5: 'han (URO end)',
    0x3042: 'hiragana', 0x30A2: 'katakana', 0xFF71: 'halfwidth katakana',
    0xAC00: 'hangul first', 0xD7A3: 'hangul last', 0x1112: 'hangul jamo',
    0x3001: 'cjk punctuation', 0xFF01: 'fullwidth forms',
}
cmap = TTFont(sys.argv[1]).getBestCmap()
missing = [f'U+{cp:04X} {what}' for cp, what in need.items() if cp not in cmap]
if missing:
    sys.exit('fetch-fonts: CJK coverage gate failed, missing: ' + ', '.join(missing))
print(f'fetch-fonts: CJK coverage gate ok ({len(cmap)} mapped codepoints)', file=sys.stderr)
PYEOF
fi

# The report must survive a fresh checkout under set -euo pipefail: an
# unmatched glob would make ls exit non-zero and kill the script, so
# files are walked one by one and absent ones simply do not print.
total_bytes=0
report_dir() {
  local label="$1" dir="$2" f size any=false
  echo "$label ($dir):"
  for f in "$dir"/*.ttf "$dir"/*.otf; do
    [ -f "$f" ] || continue
    any=true
    size=$(wc -c <"$f")
    total_bytes=$((total_bytes + size))
    printf "  %-32s %7.1f KB\n" "$(basename "$f")" "$(echo "$size" | awk '{ print $1/1024 }')"
  done
  $any || echo "  (nothing fetched yet)"
}

echo
report_dir "eager chain" "$OUT"
report_dir "on-demand" "$OUT_DEFER"
printf "  %-32s %7.1f KB\n" TOTAL "$(echo "$total_bytes" | awk '{ print $1/1024 }')"
