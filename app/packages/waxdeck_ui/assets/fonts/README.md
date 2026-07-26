# On-demand fonts

Fonts here are **not** declared in `pubspec.yaml`'s `fonts:` section: they
are plain assets, loaded at runtime from WaxDeck's own origin by
`WaxFonts.ensureFor` (or `ensureScript`) the first time the text on
screen needs their script. Startup pays only for the eager chain in
`../../fonts/`; an all-Latin library never downloads any of these.

Four faces live here, produced by `tools/fetch-fonts.sh`:

- `NotoSansArabic-Variable.ttf`, `NotoSansHebrew-Variable.ttf`,
  `NotoSansThai-Variable.ttf`: subsets, moved out of the eager chain
  because together they cost 750 KB of startup on libraries that mostly
  never show those scripts.
- `NotoSansCJK.otf`: the full Noto Sans CJK SC face, deliberately not
  subset. A curated "common hanzi" core still renders boxes for any name
  outside it, which is the failure this asset exists to close; one
  regional face carries Han, kana, and hangul alike. It is an order of
  magnitude larger than everything else combined, which is why it (and
  the whole directory) loads on demand.

With a file absent, `WaxFonts` degrades to the platform's own fallback,
which is what a build without the asset would have done anyway.
