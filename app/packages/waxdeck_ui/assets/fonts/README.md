# On-demand fonts

Fonts here are **not** declared in `pubspec.yaml`'s `fonts:` section: they
are loaded at runtime by `WaxFonts.ensureCjk()` from WaxDeck's own origin,
so a build pays their download only when the locale or the metadata on
screen actually needs them.

`NotoSansCJK.ttf` is the one such face. It is an order of magnitude larger
than the whole eager chain, and most instances never render a Han glyph,
so it stays out of the startup path. Drop a build of it here (family name
`NotoSansCJK`) and `WaxFonts.ensureCjk()` picks it up; with the file
absent, the loader degrades to the platform's own fallback, which is what
a build without it would have done anyway.
