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
OUT="$ROOT/app/packages/waxdeck_ui/fonts"
CACHE="$ROOT/tools/.cache"
VENV="$CACHE/fonttools"

# google/fonts revision the bundled files come from (2026-07-24).
FONTS_REV=7ff85c87f93ea6cca5f41c69f2e4edcb90240f26
RAW="https://raw.githubusercontent.com/google/fonts/$FONTS_REV"

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
  mkdir -p "$OUT" "$OUT/licenses"

  # family_dir  upstream_file  output_name  unicode_ranges
  fetch() {
    local dir="$1" file="$2" out="$3" ranges="$4"
    echo "fetch-fonts: $out" >&2
    curl -fsSL -o "$work/$out.src.ttf" "$RAW/ofl/$dir/$file"
    curl -fsSL -o "$OUT/licenses/$dir-OFL.txt" "$RAW/ofl/$dir/OFL.txt"
    # Keep layout features (kerning, ligatures, mark positioning) and the
    # variation tables; drop the glyphs outside the declared scripts.
    subset "$work/$out.src.ttf" \
      --output-file="$OUT/$out" \
      --unicodes="$ranges" \
      --layout-features='*' \
      --name-IDs='*' --name-legacy --name-languages='*' \
      --notdef-outline --recommended-glyphs \
      --drop-tables+=DSIG
  }

  fetch archivo        'Archivo%5Bwdth,wght%5D.ttf'      Archivo-Variable.ttf        "$LATIN_PLUS"
  fetch inter          'Inter%5Bopsz,wght%5D.ttf'        Inter-Variable.ttf          "$LATIN_PLUS"
  fetch splinesansmono 'SplineSansMono%5Bwght%5D.ttf'    SplineSansMono-Variable.ttf "$LATIN_PLUS"
  fetch notosansarabic 'NotoSansArabic%5Bwdth,wght%5D.ttf' NotoSansArabic-Variable.ttf "$ARABIC"
  fetch notosanshebrew 'NotoSansHebrew%5Bwdth,wght%5D.ttf' NotoSansHebrew-Variable.ttf "$HEBREW"
  fetch notosansthai   'NotoSansThai%5Bwdth,wght%5D.ttf'   NotoSansThai-Variable.ttf   "$THAI"
fi

echo
echo "bundled fonts (app/packages/waxdeck_ui/fonts):"
ls -l "$OUT"/*.ttf | awk '{ printf "  %-32s %7.1f KB\n", $NF, $5/1024 }' | sed "s|$OUT/||"
total=$(du -ck "$OUT"/*.ttf | tail -1 | cut -f1)
printf "  %-32s %7.1f KB\n" TOTAL "$total"
