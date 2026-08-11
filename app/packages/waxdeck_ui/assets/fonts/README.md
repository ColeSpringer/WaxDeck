# On-demand fonts

Fonts here are **not** declared in `pubspec.yaml`'s `fonts:` section: they
are plain assets, loaded at runtime from WaxDeck's own origin by
`WaxFonts.ensureFor` (or `ensureScript`) the first time the text on
screen needs their script. Startup pays only for the eager chain in
`../../fonts/`; an all-Latin library never downloads any of these.

Twenty faces live here, produced by `tools/fetch-fonts.sh`. About 34 MB
in total, and none of it is startup cost - a library reaches for one of
these only when a title, an artist, or a search query is written in that
script.

- The subset text faces: Arabic (612 KB), Hebrew (33 KB), Thai (90 KB),
  Devanagari (483 KB), Bengali (333 KB), Gurmukhi (103 KB), Gujarati
  (512 KB), Tamil (186 KB), Telugu (623 KB), Kannada (428 KB), Malayalam
  (346 KB), Sinhala (1013 KB), Khmer (253 KB), Lao (75 KB), Myanmar
  (544 KB), Georgian (128 KB), Armenian (88 KB), Ethiopic (849 KB). Each
  is subset to its own block plus what that script needs to shape
  correctly - the joiners, the dotted circle a renderer draws around an
  orphaned mark, and for the Indic faces the danda pair that ends a
  sentence.
- `NotoColorEmoji.ttf` (10.4 MB): the CBDT/CBLC bitmap build, subset to
  the emoji ranges plus the legacy pictographic scatter that real
  podcast and track titles use (clock faces, transport arrows). Its
  layout tables are kept: a flag is two regional indicators ligated into
  one glyph and a family is a ZWJ sequence, so a build without GSUB maps
  every codepoint and draws none of the sequences.
- `NotoSansCJK.otf` (16 MB): the full Noto Sans CJK SC face,
  deliberately not subset. A curated "common hanzi" core still renders
  boxes for any name outside it, which is the failure this asset exists
  to close; one regional face carries Han, kana, and hangul alike.

The set grows one face at a time, through the table in
`tools/fetch-fonts.sh` and a `WaxScript` entry beside it. A script earns
a place when a real library would otherwise render boxes, not before:
Oriya, Tibetan and the rest are absent for that reason rather than by
oversight.

With a file absent, `WaxFonts` degrades to the platform's own fallback,
which is what a build without the asset would have done anyway.
