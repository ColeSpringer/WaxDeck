import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'font_marker_io.dart'
    if (dart.library.js_interop) 'font_marker_web.dart';

/// The scripts whose faces load on demand rather than at startup.
enum WaxScript { arabic, hebrew, thai, cjk }

/// The bundled type: family names, the fallback chain, and the loader for
/// the scripts that do not ship in the eager chain.
///
/// Fonts are assets, never runtime fetches from third parties. Native
/// platforms would fall back per glyph to system faces, but Flutter web
/// resolves missing glyphs by fetching Noto from Google's CDN, which a
/// LAN-only or air-gapped instance cannot reach: Arabic, Hebrew, Thai,
/// and CJK metadata would render as boxes. So the chain is owned, and
/// every non-Latin face is served from WaxDeck's own origin, loaded the
/// first time the locale or the text on screen needs its script. Startup
/// pays only for the primary faces.
abstract final class WaxFonts {
  /// Fonts live in this package, so every [TextStyle] naming one passes
  /// `package: WaxFonts.package` (which prefixes the family and the
  /// fallbacks alike).
  static const String package = 'waxdeck_ui';

  /// Archivo: the identity face.
  static const String display = 'Archivo';

  /// Inter: lists, labels, buttons, settings, forms.
  static const String ui = 'Inter';

  /// Spline Sans Mono: the equipment-readout voice.
  static const String mono = 'SplineSansMono';

  static const String _arabic = 'NotoSansArabic';
  static const String _hebrew = 'NotoSansHebrew';
  static const String _thai = 'NotoSansThai';

  /// The CJK family. Loaded by [ensureFor] or [ensureScript]; the full face
  /// is an order of magnitude larger than every other face combined,
  /// which is why it (like the other fallback scripts) never loads until
  /// something needs it.
  static const String cjk = 'NotoSansCJK';

  /// The owned fallback chain, in resolution order, for [TextStyle]s
  /// created with `package: WaxFonts.package`. Latin, Greek, and
  /// Cyrillic are covered by the primary faces; these carry the scripts
  /// they do not. Naming a family that has not loaded yet is harmless:
  /// resolution skips it until [ensureFor] installs it.
  static const List<String> fallbacks = <String>[_arabic, _hebrew, _thai, cjk];

  /// The same chain with explicit package prefixes, for styles and
  /// themes built outside this package (a `ThemeData.fontFamilyFallback`
  /// cannot use `TextStyle.package`).
  static const List<String> fallbacksQualified = <String>[
    'packages/$package/$_arabic',
    'packages/$package/$_hebrew',
    'packages/$package/$_thai',
    'packages/$package/$cjk',
  ];

  /// Inter with the package prefix, for use as a theme-level
  /// `fontFamily` outside this package.
  static const String uiQualified = 'packages/$package/$ui';

  static const Map<WaxScript, (String, String)> _faces =
      <WaxScript, (String, String)>{
        WaxScript.arabic: (_arabic, 'assets/fonts/NotoSansArabic-Variable.ttf'),
        WaxScript.hebrew: (_hebrew, 'assets/fonts/NotoSansHebrew-Variable.ttf'),
        WaxScript.thai: (_thai, 'assets/fonts/NotoSansThai-Variable.ttf'),
        WaxScript.cjk: (cjk, 'assets/fonts/NotoSansCJK.otf'),
      };

  static final Map<WaxScript, Future<void>> _loads =
      <WaxScript, Future<void>>{};
  static final Set<WaxScript> _loaded = <WaxScript>{};

  /// Whether [script]'s face has finished loading.
  static bool isLoaded(WaxScript script) => _loaded.contains(script);

  /// Loads [script]'s face from WaxDeck's own origin, once.
  ///
  /// Safe to call repeatedly and safe to call on a build that ships
  /// without the asset: a missing font degrades to the platform's own
  /// fallback (native) or the browser's (web), the same behaviour as not
  /// calling it at all. Font loading is never the reason a screen fails
  /// to render.
  static Future<void> ensureScript(WaxScript script) {
    return _loads[script] ??= () async {
      final (family, asset) = _faces[script]!;
      try {
        // The family name must match what TextStyle's `package:`
        // argument produces for the fallback entry, or the chain never
        // reaches it.
        final loader = FontLoader('packages/$package/$family')
          ..addFont(rootBundle.load('packages/$package/$asset'));
        await loader.load();
        _loaded.add(script);
        markFontLoaded(family);
      } on Object {
        // Absent asset or a decode failure: fall through quietly.
      }
    }();
  }

  /// Scans [text] and starts loading every deferred face its runes need.
  ///
  /// The scan is a cheap range check per rune with an early exit once
  /// every script is accounted for; call it with whatever metadata is
  /// about to render (titles, artists, a search query). Loading is
  /// asynchronous: text that raced ahead of its face re-lays out when
  /// the loader completes, which is the deliberate trade for an eager
  /// chain that stays small.
  static Future<void> ensureFor(String text) {
    final needed = scriptsIn(text);
    if (needed.isEmpty) return Future<void>.value();
    return Future.wait(needed.map(ensureScript));
  }

  /// The deferred scripts in [text] whose faces have not been asked for
  /// yet.
  ///
  /// A script counts as handled once a load has started for it,
  /// successful or not: [ensureScript] never retries, so re-reporting a
  /// failed face would only re-scan every later page of metadata for a
  /// load that is never coming. The scan skips handled scripts as it
  /// goes and stops as soon as nothing more is actionable, so once the
  /// faces a library needs are in, calls cost near nothing.
  static Set<WaxScript> scriptsIn(String text) {
    if (_loads.length == _faces.length) return const <WaxScript>{};
    final found = <WaxScript>{};
    for (final rune in text.runes) {
      final script = _scriptOf(rune);
      if (script != null && !_loads.containsKey(script) && found.add(script)) {
        if (found.length + _loads.length == _faces.length) break;
      }
    }
    return found;
  }

  static WaxScript? _scriptOf(int rune) {
    if (rune < 0x0590) return null;
    if (rune < 0x0600) return WaxScript.hebrew;
    if (rune <= 0x06FF) return WaxScript.arabic;
    if (rune >= 0x0750 && rune <= 0x077F) return WaxScript.arabic;
    if (rune >= 0x08A0 && rune <= 0x08FF) return WaxScript.arabic;
    if (rune >= 0x0E00 && rune <= 0x0E7F) return WaxScript.thai;
    // Hangul jamo (with extensions), radicals and ideographic
    // description characters, the symbol and punctuation blocks through
    // enclosed letters and CJK compatibility (track listings lean on
    // things like circled numbers and squared units), kana, the Han
    // blocks, hangul syllables, compatibility ideographs, vertical
    // forms, and the full/halfwidth forms: any of them means CJK text
    // is on screen.
    if (rune >= 0x1100 && rune <= 0x11FF) return WaxScript.cjk;
    if (rune >= 0x2E80 && rune <= 0x2FFF) return WaxScript.cjk;
    if (rune >= 0x3000 && rune <= 0x33FF) return WaxScript.cjk;
    if (rune >= 0x3400 && rune <= 0x4DBF) return WaxScript.cjk;
    if (rune >= 0x4E00 && rune <= 0x9FFF) return WaxScript.cjk;
    if (rune >= 0xA960 && rune <= 0xA97F) return WaxScript.cjk;
    if (rune >= 0xAC00 && rune <= 0xD7FF) return WaxScript.cjk;
    if (rune >= 0xF900 && rune <= 0xFAFF) return WaxScript.cjk;
    if (rune >= 0xFB1D && rune <= 0xFB4F) return WaxScript.hebrew;
    if (rune >= 0xFB50 && rune <= 0xFDFF) return WaxScript.arabic;
    if (rune >= 0xFE30 && rune <= 0xFE4F) return WaxScript.cjk;
    // Ends at U+FEFE: U+FEFF is the byte-order mark, not an Arabic
    // presentation form, and BOMs routinely survive UTF-16 taggers into
    // ID3 text; one stray BOM must not download the Arabic face.
    if (rune >= 0xFE70 && rune <= 0xFEFE) return WaxScript.arabic;
    if (rune >= 0xFF00 && rune <= 0xFFEF) return WaxScript.cjk;
    if (rune >= 0x20000 && rune <= 0x3134F) return WaxScript.cjk;
    return null;
  }

  @visibleForTesting
  static void resetForTest() {
    _loads.clear();
    _loaded.clear();
  }
}
