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
# - the deferred scripts. Startup pays only for the primary chain.
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

# googlefonts/noto-emoji for the colour emoji face. This repo and not
# google/fonts: the CBDT/CBLC bitmap build is published here, and the
# one on google/fonts is the outline flavour, which renders emoji as
# monochrome glyphs.
NOTO_EMOJI_SHA=8998f5dd683424a73e2314a8c1f1e359c19e8742
NOTO_EMOJI_RAW="https://raw.githubusercontent.com/googlefonts/noto-emoji/$NOTO_EMOJI_SHA"

# Latin plus the scripts Inter covers natively: Latin Extended A/B and
# Additional, combining marks, Greek, Cyrillic (with supplement),
# punctuation, currency, and the handful of symbols an interface uses.
LATIN_PLUS='U+0000-00FF,U+0100-024F,U+0259,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0300-036F,U+0370-03FF,U+0400-052F,U+1E00-1EFF,U+2000-206F,U+2070-209F,U+20A0-20BF,U+2100-214F,U+2190-2199,U+2212,U+2215,U+25A0-25CF,U+2605-2606,U+FEFF,U+FFFD'
ARABIC='U+0600-06FF,U+0750-077F,U+08A0-08FF,U+FB50-FDFF,U+FE70-FEFF,U+200C-200E,U+2010-2011,U+204F,U+2E41'
HEBREW='U+0590-05FF,U+200C-2010,U+20AA,U+25CC,U+FB1D-FB4F'
THAI='U+0E01-0E5B,U+200C-200D,U+25CC'

# What every Indic face needs beyond its own block: the danda pair that
# ends a sentence in most of them, the joiners that drive conjunct
# formation, and the dotted circle a renderer draws around an orphaned
# combining mark. Subsetting these out is how a face comes back rendering
# its own script wrongly rather than not at all.
INDIC_SHARED='U+0964-0965,U+200C-200D,U+25CC'
DEVANAGARI="U+0900-097F,U+A8E0-A8FF,$INDIC_SHARED"
BENGALI="U+0980-09FF,$INDIC_SHARED"
GURMUKHI="U+0A00-0A7F,$INDIC_SHARED"
GUJARATI="U+0A80-0AFF,$INDIC_SHARED"
TAMIL="U+0B80-0BFF,$INDIC_SHARED"
TELUGU="U+0C00-0C7F,$INDIC_SHARED"
KANNADA="U+0C80-0CFF,$INDIC_SHARED"
MALAYALAM="U+0D00-0D7F,$INDIC_SHARED"
SINHALA="U+0D80-0DFF,$INDIC_SHARED"
KHMER='U+1780-17FF,U+19E0-19FF,U+200C-200D,U+25CC'
LAO='U+0E80-0EFF,U+200C-200D,U+25CC'
MYANMAR='U+1000-109F,U+A9E0-A9FF,U+AA60-AA7F,U+200C-200D,U+25CC'
GEORGIAN='U+10A0-10FF,U+1C90-1CBF,U+2D00-2D2F,U+200C-200D'
ARMENIAN='U+0530-058F,U+FB13-FB17,U+200C-200D'
ETHIOPIC='U+1200-137F,U+1380-139F,U+2D80-2DDF,U+AB00-AB2F,U+200C-200D'

# The emoji face is subset too, and the ranges are wider than "the emoji
# blocks" for a reason: emoji predate their own blocks. Clock faces,
# transport arrows and the play glyphs turn up in real podcast and track
# titles, and they live scattered through the symbol blocks and the
# legacy pictographic ranges that came before U+1F300. The scatter below
# is the Extended_Pictographic set outside the contiguous ranges.
EMOJI='U+200D,U+20E3,U+2600-27BF,U+2B00-2B5F,U+FE0F,U+1F000-1FAFF'
EMOJI="$EMOJI,U+203C,U+2049,U+2122,U+2139,U+2194-21AA,U+231A-231B,U+2328"
EMOJI="$EMOJI,U+23CF,U+23E9-23FA,U+24C2,U+25AA-25AB,U+25B6,U+25C0"
EMOJI="$EMOJI,U+25FB-25FE,U+2934-2935,U+3030,U+303D,U+3297,U+3299"

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

  # Coverage gate. A subset that silently lost the glyphs it exists for
  # is indistinguishable from a working one until somebody's library
  # renders boxes, so every face states what it must map and fails here
  # instead. The pairs are chosen per script: a base letter proves the
  # block arrived, and a virama, a vowel sign or a joiner proves the
  # marks that make it readable came with it.
  gate() {
    local file="$1" what="$2"
    shift 2
    PYTHONPATH="$VENV" python3 - "$file" "$what" "$@" <<'PYEOF'
import sys
from fontTools.ttLib import TTFont

path, what, *wanted = sys.argv[1:]
cmap = TTFont(path).getBestCmap()
missing = [w for w in wanted if int(w.split(':')[0], 16) not in cmap]
if missing:
    sys.exit(f'fetch-fonts: {what} coverage gate failed, missing: ' + ', '.join(missing))
print(f'fetch-fonts: {what} coverage gate ok ({len(cmap)} mapped codepoints)', file=sys.stderr)
PYEOF
  }

  fetch archivo        'Archivo%5Bwdth,wght%5D.ttf'      Archivo-Variable.ttf        "$LATIN_PLUS" "$OUT"
  fetch inter          'Inter%5Bopsz,wght%5D.ttf'        Inter-Variable.ttf          "$LATIN_PLUS" "$OUT"
  fetch splinesansmono 'SplineSansMono%5Bwght%5D.ttf'    SplineSansMono-Variable.ttf "$LATIN_PLUS" "$OUT"
  fetch notosansarabic 'NotoSansArabic%5Bwdth,wght%5D.ttf' NotoSansArabic-Variable.ttf "$ARABIC" "$OUT_DEFER"
  fetch notosanshebrew 'NotoSansHebrew%5Bwdth,wght%5D.ttf' NotoSansHebrew-Variable.ttf "$HEBREW" "$OUT_DEFER"
  fetch notosansthai   'NotoSansThai%5Bwdth,wght%5D.ttf'   NotoSansThai-Variable.ttf   "$THAI" "$OUT_DEFER"

  # The scripts a real library needs beyond those three. All fifteen
  # publish a [wdth,wght] variable build, so the file names agree and the
  # weight axis the type tokens select through survives subsetting.
  fetch notosansdevanagari 'NotoSansDevanagari%5Bwdth,wght%5D.ttf' NotoSansDevanagari-Variable.ttf "$DEVANAGARI" "$OUT_DEFER"
  fetch notosansbengali    'NotoSansBengali%5Bwdth,wght%5D.ttf'    NotoSansBengali-Variable.ttf    "$BENGALI"    "$OUT_DEFER"
  fetch notosansgurmukhi   'NotoSansGurmukhi%5Bwdth,wght%5D.ttf'   NotoSansGurmukhi-Variable.ttf   "$GURMUKHI"   "$OUT_DEFER"
  fetch notosansgujarati   'NotoSansGujarati%5Bwdth,wght%5D.ttf'   NotoSansGujarati-Variable.ttf   "$GUJARATI"   "$OUT_DEFER"
  fetch notosanstamil      'NotoSansTamil%5Bwdth,wght%5D.ttf'      NotoSansTamil-Variable.ttf      "$TAMIL"      "$OUT_DEFER"
  fetch notosanstelugu     'NotoSansTelugu%5Bwdth,wght%5D.ttf'     NotoSansTelugu-Variable.ttf     "$TELUGU"     "$OUT_DEFER"
  fetch notosanskannada    'NotoSansKannada%5Bwdth,wght%5D.ttf'    NotoSansKannada-Variable.ttf    "$KANNADA"    "$OUT_DEFER"
  fetch notosansmalayalam  'NotoSansMalayalam%5Bwdth,wght%5D.ttf'  NotoSansMalayalam-Variable.ttf  "$MALAYALAM"  "$OUT_DEFER"
  fetch notosanssinhala    'NotoSansSinhala%5Bwdth,wght%5D.ttf'    NotoSansSinhala-Variable.ttf    "$SINHALA"    "$OUT_DEFER"
  fetch notosanskhmer      'NotoSansKhmer%5Bwdth,wght%5D.ttf'      NotoSansKhmer-Variable.ttf      "$KHMER"      "$OUT_DEFER"
  fetch notosanslao        'NotoSansLao%5Bwdth,wght%5D.ttf'        NotoSansLao-Variable.ttf        "$LAO"        "$OUT_DEFER"
  fetch notosansmyanmar    'NotoSansMyanmar%5Bwdth,wght%5D.ttf'    NotoSansMyanmar-Variable.ttf    "$MYANMAR"    "$OUT_DEFER"
  fetch notosansgeorgian   'NotoSansGeorgian%5Bwdth,wght%5D.ttf'   NotoSansGeorgian-Variable.ttf   "$GEORGIAN"   "$OUT_DEFER"
  fetch notosansarmenian   'NotoSansArmenian%5Bwdth,wght%5D.ttf'   NotoSansArmenian-Variable.ttf   "$ARMENIAN"   "$OUT_DEFER"
  fetch notosansethiopic   'NotoSansEthiopic%5Bwdth,wght%5D.ttf'   NotoSansEthiopic-Variable.ttf   "$ETHIOPIC"   "$OUT_DEFER"

  # One base letter and one mark per script: the letter says the block
  # arrived, the mark says the shaping came with it.
  gate "$OUT_DEFER/NotoSansDevanagari-Variable.ttf" Devanagari 0915:ka 094D:virama 0964:danda
  gate "$OUT_DEFER/NotoSansBengali-Variable.ttf"    Bengali    0995:ka 09CD:virama
  gate "$OUT_DEFER/NotoSansGurmukhi-Variable.ttf"   Gurmukhi   0A15:ka 0A4D:virama
  gate "$OUT_DEFER/NotoSansGujarati-Variable.ttf"   Gujarati   0A95:ka 0ACD:virama
  gate "$OUT_DEFER/NotoSansTamil-Variable.ttf"      Tamil      0B95:ka 0BCD:virama
  gate "$OUT_DEFER/NotoSansTelugu-Variable.ttf"     Telugu     0C15:ka 0C4D:virama
  gate "$OUT_DEFER/NotoSansKannada-Variable.ttf"    Kannada    0C95:ka 0CCD:virama
  gate "$OUT_DEFER/NotoSansMalayalam-Variable.ttf"  Malayalam  0D15:ka 0D4D:virama
  gate "$OUT_DEFER/NotoSansSinhala-Variable.ttf"    Sinhala    0D9A:ka 0DCA:virama
  gate "$OUT_DEFER/NotoSansKhmer-Variable.ttf"      Khmer      1780:ka 17D2:coeng
  gate "$OUT_DEFER/NotoSansLao-Variable.ttf"        Lao        0E81:ko 0EB2:sign-aa
  gate "$OUT_DEFER/NotoSansMyanmar-Variable.ttf"    Myanmar    1000:ka 1039:virama
  gate "$OUT_DEFER/NotoSansGeorgian-Variable.ttf"   Georgian   10D0:an 1C90:mtavruli-an
  gate "$OUT_DEFER/NotoSansArmenian-Variable.ttf"   Armenian   0531:ayb 0561:small-ayb
  gate "$OUT_DEFER/NotoSansEthiopic-Variable.ttf"   Ethiopic   1200:ha 1361:wordspace

  # The CJK face ships verbatim: full coverage is its whole purpose.
  echo "fetch-fonts: NotoSansCJK.otf (full face, no subsetting)" >&2
  curl -fsSL -o "$OUT_DEFER/NotoSansCJK.otf" \
    "$NOTO_CJK_RAW/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf"
  curl -fsSL -o "$OUT/licenses/noto-cjk-OFL.txt" "$NOTO_CJK_RAW/LICENSE"

  gate "$OUT_DEFER/NotoSansCJK.otf" CJK \
    4E2D:han-uro 3400:han-ext-a 9FA5:han-uro-end 3042:hiragana \
    30A2:katakana FF71:halfwidth-katakana AC00:hangul-first \
    D7A3:hangul-last 1112:hangul-jamo 3001:cjk-punctuation FF01:fullwidth

  # Colour emoji. Subset like the text faces, but the layout tables are
  # not optional decoration here: a flag is two regional indicators
  # ligated into one glyph and a family is a ZWJ sequence, so dropping
  # GSUB would leave a face that maps every codepoint and draws none of
  # the sequences people actually send.
  echo "fetch-fonts: NotoColorEmoji.ttf" >&2
  curl -fsSL -o "$work/emoji.src.ttf" "$NOTO_EMOJI_RAW/fonts/NotoColorEmoji.ttf"
  curl -fsSL -o "$OUT/licenses/noto-emoji-LICENSE.txt" "$NOTO_EMOJI_RAW/LICENSE"
  subset "$work/emoji.src.ttf" \
    --output-file="$OUT_DEFER/NotoColorEmoji.ttf" \
    --unicodes="$EMOJI" \
    --layout-features='*' \
    --name-IDs='*' --name-legacy --name-languages='*' \
    --notdef-outline --recommended-glyphs \
    --drop-tables+=DSIG

  # No FE0F here: the upstream face does not map the variation selector
  # at all (the shaper consumes it and picks the emoji presentation),
  # so asserting it would fail on a font that is working correctly.
  gate "$OUT_DEFER/NotoColorEmoji.ttf" emoji \
    1F600:grinning 1F1E6:regional-a 2764:heart 200D:zwj 20E3:keycap \
    231A:watch 25B6:play

  # What a cmap gate cannot see. The colour lives in CBDT/CBLC and the
  # flag and ZWJ sequences live in GSUB: a subset that kept every
  # codepoint and lost either would pass above and still be the wrong
  # font on screen.
  PYTHONPATH="$VENV" python3 - "$OUT_DEFER/NotoColorEmoji.ttf" <<'PYEOF'
import sys
from fontTools.ttLib import TTFont

tables = set(TTFont(sys.argv[1]).keys())
missing = [t for t in ('CBDT', 'CBLC', 'GSUB') if t not in tables]
if missing:
    sys.exit('fetch-fonts: emoji build gate failed, missing tables: ' + ', '.join(missing))
print('fetch-fonts: emoji build gate ok (CBDT/CBLC bitmaps and GSUB survived)', file=sys.stderr)
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
