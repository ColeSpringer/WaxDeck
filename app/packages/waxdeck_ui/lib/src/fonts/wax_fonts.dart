import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'font_marker_io.dart'
    if (dart.library.js_interop) 'font_marker_web.dart';

/// The scripts whose faces load on demand rather than at startup.
///
/// Grown one face at a time as real libraries need them: a script is on
/// this list when somebody's metadata would otherwise render as boxes,
/// and the cost of each is bytes nobody downloads until then. Oriya,
/// Tibetan and the rest wait for the same evidence.
enum WaxScript {
  arabic,
  hebrew,
  thai,
  cjk,
  devanagari,
  bengali,
  gurmukhi,
  gujarati,
  tamil,
  telugu,
  kannada,
  malayalam,
  sinhala,
  khmer,
  lao,
  myanmar,
  georgian,
  armenian,
  ethiopic,
  emoji,
}

/// The bundled type: family names, the fallback chain, and the loader for
/// the scripts that do not ship in the eager chain.
///
/// Fonts are assets, never runtime fetches from third parties. Native
/// platforms would fall back per glyph to system faces, but Flutter web
/// resolves missing glyphs by fetching Noto from Google's CDN, which a
/// LAN-only or air-gapped instance cannot reach: every script outside
/// the eager faces would render as boxes. So the chain is owned, and
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
  static const String _devanagari = 'NotoSansDevanagari';
  static const String _bengali = 'NotoSansBengali';
  static const String _gurmukhi = 'NotoSansGurmukhi';
  static const String _gujarati = 'NotoSansGujarati';
  static const String _tamil = 'NotoSansTamil';
  static const String _telugu = 'NotoSansTelugu';
  static const String _kannada = 'NotoSansKannada';
  static const String _malayalam = 'NotoSansMalayalam';
  static const String _sinhala = 'NotoSansSinhala';
  static const String _khmer = 'NotoSansKhmer';
  static const String _lao = 'NotoSansLao';
  static const String _myanmar = 'NotoSansMyanmar';
  static const String _georgian = 'NotoSansGeorgian';
  static const String _armenian = 'NotoSansArmenian';
  static const String _ethiopic = 'NotoSansEthiopic';

  /// The colour emoji face. CBDT/CBLC bitmaps, so it is the second
  /// largest thing here after CJK and never loads until emoji are on
  /// screen.
  static const String _emoji = 'NotoColorEmoji';

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
  ///
  /// Emoji sits ahead of CJK deliberately: the CJK face carries
  /// monochrome text forms of the symbol block, so with it first a heart
  /// or a watch would resolve there and draw as an outline.
  static const List<String> fallbacks = <String>[
    _arabic,
    _hebrew,
    _thai,
    _devanagari,
    _bengali,
    _gurmukhi,
    _gujarati,
    _tamil,
    _telugu,
    _kannada,
    _malayalam,
    _sinhala,
    _khmer,
    _lao,
    _myanmar,
    _georgian,
    _armenian,
    _ethiopic,
    _emoji,
    cjk,
  ];

  /// The same chain with explicit package prefixes, for styles and
  /// themes built outside this package (a `ThemeData.fontFamilyFallback`
  /// cannot use `TextStyle.package`).
  static const List<String> fallbacksQualified = <String>[
    'packages/$package/$_arabic',
    'packages/$package/$_hebrew',
    'packages/$package/$_thai',
    'packages/$package/$_devanagari',
    'packages/$package/$_bengali',
    'packages/$package/$_gurmukhi',
    'packages/$package/$_gujarati',
    'packages/$package/$_tamil',
    'packages/$package/$_telugu',
    'packages/$package/$_kannada',
    'packages/$package/$_malayalam',
    'packages/$package/$_sinhala',
    'packages/$package/$_khmer',
    'packages/$package/$_lao',
    'packages/$package/$_myanmar',
    'packages/$package/$_georgian',
    'packages/$package/$_armenian',
    'packages/$package/$_ethiopic',
    'packages/$package/$_emoji',
    'packages/$package/$cjk',
  ];

  /// Inter with the package prefix, for use as a theme-level
  /// `fontFamily` outside this package.
  static const String uiQualified = 'packages/$package/$ui';

  static const Map<WaxScript, (String, String)>
  _faces = <WaxScript, (String, String)>{
    WaxScript.arabic: (_arabic, 'assets/fonts/NotoSansArabic-Variable.ttf'),
    WaxScript.hebrew: (_hebrew, 'assets/fonts/NotoSansHebrew-Variable.ttf'),
    WaxScript.thai: (_thai, 'assets/fonts/NotoSansThai-Variable.ttf'),
    WaxScript.cjk: (cjk, 'assets/fonts/NotoSansCJK.otf'),
    WaxScript.devanagari: (
      _devanagari,
      'assets/fonts/NotoSansDevanagari-Variable.ttf',
    ),
    WaxScript.bengali: (_bengali, 'assets/fonts/NotoSansBengali-Variable.ttf'),
    WaxScript.gurmukhi: (
      _gurmukhi,
      'assets/fonts/NotoSansGurmukhi-Variable.ttf',
    ),
    WaxScript.gujarati: (
      _gujarati,
      'assets/fonts/NotoSansGujarati-Variable.ttf',
    ),
    WaxScript.tamil: (_tamil, 'assets/fonts/NotoSansTamil-Variable.ttf'),
    WaxScript.telugu: (_telugu, 'assets/fonts/NotoSansTelugu-Variable.ttf'),
    WaxScript.kannada: (_kannada, 'assets/fonts/NotoSansKannada-Variable.ttf'),
    WaxScript.malayalam: (
      _malayalam,
      'assets/fonts/NotoSansMalayalam-Variable.ttf',
    ),
    WaxScript.sinhala: (_sinhala, 'assets/fonts/NotoSansSinhala-Variable.ttf'),
    WaxScript.khmer: (_khmer, 'assets/fonts/NotoSansKhmer-Variable.ttf'),
    WaxScript.lao: (_lao, 'assets/fonts/NotoSansLao-Variable.ttf'),
    WaxScript.myanmar: (_myanmar, 'assets/fonts/NotoSansMyanmar-Variable.ttf'),
    WaxScript.georgian: (
      _georgian,
      'assets/fonts/NotoSansGeorgian-Variable.ttf',
    ),
    WaxScript.armenian: (
      _armenian,
      'assets/fonts/NotoSansArmenian-Variable.ttf',
    ),
    WaxScript.ethiopic: (
      _ethiopic,
      'assets/fonts/NotoSansEthiopic-Variable.ttf',
    ),
    WaxScript.emoji: (_emoji, 'assets/fonts/NotoColorEmoji.ttf'),
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
    // Armenian is the lowest block owned here, so the early-out moved
    // down to it from Hebrew's 0x0590.
    if (rune < 0x0530) return null;
    if (rune <= 0x058F) return WaxScript.armenian;
    if (rune < 0x0600) return WaxScript.hebrew;
    if (rune <= 0x06FF) return WaxScript.arabic;
    if (rune >= 0x0750 && rune <= 0x077F) return WaxScript.arabic;
    if (rune >= 0x08A0 && rune <= 0x08FF) return WaxScript.arabic;
    // The Indic ladder, in block order. The danda pair (U+0964-0965) is
    // shared punctuation that every Indic face carries, and it falls
    // inside Devanagari's block: a Bengali title ending in one warms the
    // Devanagari face too, which costs a load nobody sees and never
    // leaves a box on screen.
    if (rune >= 0x0900 && rune <= 0x097F) return WaxScript.devanagari;
    if (rune >= 0x0980 && rune <= 0x09FF) return WaxScript.bengali;
    if (rune >= 0x0A00 && rune <= 0x0A7F) return WaxScript.gurmukhi;
    if (rune >= 0x0A80 && rune <= 0x0AFF) return WaxScript.gujarati;
    // 0x0B00-0x0B7F is Oriya, which is not bundled: no face to warm.
    if (rune >= 0x0B80 && rune <= 0x0BFF) return WaxScript.tamil;
    if (rune >= 0x0C00 && rune <= 0x0C7F) return WaxScript.telugu;
    if (rune >= 0x0C80 && rune <= 0x0CFF) return WaxScript.kannada;
    if (rune >= 0x0D00 && rune <= 0x0D7F) return WaxScript.malayalam;
    if (rune >= 0x0D80 && rune <= 0x0DFF) return WaxScript.sinhala;
    if (rune >= 0x0E00 && rune <= 0x0E7F) return WaxScript.thai;
    if (rune >= 0x0E80 && rune <= 0x0EFF) return WaxScript.lao;
    if (rune >= 0x1000 && rune <= 0x109F) return WaxScript.myanmar;
    if (rune >= 0x10A0 && rune <= 0x10FF) return WaxScript.georgian;
    if (rune >= 0x1200 && rune <= 0x139F) return WaxScript.ethiopic;
    if (rune >= 0x1780 && rune <= 0x17FF) return WaxScript.khmer;
    if (rune >= 0x19E0 && rune <= 0x19FF) return WaxScript.khmer;
    if (rune >= 0x1C90 && rune <= 0x1CBF) return WaxScript.georgian;
    // Hangul jamo (with extensions), radicals and ideographic
    // description characters, the symbol and punctuation blocks through
    // enclosed letters and CJK compatibility (track listings lean on
    // things like circled numbers and squared units), kana, the Han
    // blocks, hangul syllables, compatibility ideographs, vertical
    // forms, and the full/halfwidth forms: any of them means CJK text
    // is on screen.
    if (rune >= 0x1100 && rune <= 0x11FF) return WaxScript.cjk;
    if (rune >= 0x2D00 && rune <= 0x2D2F) return WaxScript.georgian;
    if (rune >= 0x2D80 && rune <= 0x2DDF) return WaxScript.ethiopic;
    // The symbol scatter routes by what the owned faces can actually
    // draw, not by block: the colour emoji face maps 116 of the 448
    // codepoints in Miscellaneous Symbols and Dingbats, so routing the
    // block wholesale downloaded ten megabytes to draw tofu while the
    // CJK face silently held the glyph (a title's musical note was the
    // reproducer). Eager-drawn symbols (the stars, the play triangle,
    // the trademark sign) fall through to the Latin subset, and what no
    // owned face draws falls through to tofu rather than pulling a face
    // that cannot help. An explicit VS16 still warms the emoji face
    // through the check below.
    if (rune >= 0x2000 && rune <= 0x2BFF) {
      if (_inScatter(rune, _emojiScatter)) return WaxScript.emoji;
      if (_inScatter(rune, _cjkScatter)) return WaxScript.cjk;
    }
    if (rune >= 0x2E80 && rune <= 0x2FFF) return WaxScript.cjk;
    if (rune >= 0x3000 && rune <= 0x33FF) return WaxScript.cjk;
    if (rune >= 0x3400 && rune <= 0x4DBF) return WaxScript.cjk;
    if (rune >= 0x4E00 && rune <= 0x9FFF) return WaxScript.cjk;
    if (rune >= 0xA8E0 && rune <= 0xA8FF) return WaxScript.devanagari;
    if (rune >= 0xA960 && rune <= 0xA97F) return WaxScript.cjk;
    if (rune >= 0xA9E0 && rune <= 0xA9FF) return WaxScript.myanmar;
    if (rune >= 0xAA60 && rune <= 0xAA7F) return WaxScript.myanmar;
    if (rune >= 0xAB00 && rune <= 0xAB2F) return WaxScript.ethiopic;
    if (rune >= 0xAC00 && rune <= 0xD7FF) return WaxScript.cjk;
    if (rune >= 0xF900 && rune <= 0xFAFF) return WaxScript.cjk;
    if (rune >= 0xFB13 && rune <= 0xFB17) return WaxScript.armenian;
    if (rune >= 0xFB1D && rune <= 0xFB4F) return WaxScript.hebrew;
    if (rune >= 0xFB50 && rune <= 0xFDFF) return WaxScript.arabic;
    if (rune == 0xFE0F) return WaxScript.emoji;
    if (rune >= 0xFE30 && rune <= 0xFE4F) return WaxScript.cjk;
    // Ends at U+FEFE: U+FEFF is the byte-order mark, not an Arabic
    // presentation form, and BOMs routinely survive UTF-16 taggers into
    // ID3 text; one stray BOM must not download the Arabic face.
    if (rune >= 0xFE70 && rune <= 0xFEFE) return WaxScript.arabic;
    if (rune >= 0xFF00 && rune <= 0xFFEF) return WaxScript.cjk;
    if (rune >= 0x1F000 && rune <= 0x1FAFF) return WaxScript.emoji;
    if (rune >= 0x20000 && rune <= 0x3134F) return WaxScript.cjk;
    return null;
  }

  /// Symbol-scatter routing tables: flat (start, end) pairs, ascending.
  /// The entries are the committed faces' cmaps, not a curated list -
  /// `tools/font-coverage.py` rederives both tables (and the eager
  /// carve-outs they imply) from the font files, so run it and paste
  /// whenever `make fonts` changes a face.
  static const List<int> _emojiScatter = <int>[
    0x2139, 0x2139, 0x21A9, 0x21AA, 0x231A, 0x231B, 0x2328, 0x2328, //
    0x23CF, 0x23CF, 0x23E9, 0x23F3, 0x23F8, 0x23FA, 0x24C2, 0x24C2,
    0x25AB, 0x25AB, 0x25FB, 0x25FE, 0x2600, 0x2604, 0x260E, 0x260E,
    0x2611, 0x2611, 0x2614, 0x2615, 0x2618, 0x2618, 0x261D, 0x261D,
    0x2620, 0x2620, 0x2622, 0x2623, 0x2626, 0x2626, 0x262A, 0x262A,
    0x262E, 0x262F, 0x2638, 0x263A, 0x2640, 0x2640, 0x2642, 0x2642,
    0x2648, 0x2653, 0x265F, 0x2660, 0x2663, 0x2663, 0x2665, 0x2666,
    0x2668, 0x2668, 0x267B, 0x267B, 0x267E, 0x267F, 0x2692, 0x2697,
    0x2699, 0x2699, 0x269B, 0x269C, 0x26A0, 0x26A1, 0x26A7, 0x26A7,
    0x26AA, 0x26AB, 0x26B0, 0x26B1, 0x26BD, 0x26BE, 0x26C4, 0x26C5,
    0x26C8, 0x26C8, 0x26CE, 0x26CF, 0x26D1, 0x26D1, 0x26D3, 0x26D4,
    0x26E9, 0x26EA, 0x26F0, 0x26F5, 0x26F7, 0x26FA, 0x26FD, 0x26FD,
    0x2702, 0x2702, 0x2705, 0x2705, 0x2708, 0x270D, 0x270F, 0x270F,
    0x2712, 0x2712, 0x2714, 0x2714, 0x2716, 0x2716, 0x271D, 0x271D,
    0x2721, 0x2721, 0x2728, 0x2728, 0x2733, 0x2734, 0x2744, 0x2744,
    0x2747, 0x2747, 0x274C, 0x274C, 0x274E, 0x274E, 0x2753, 0x2755,
    0x2757, 0x2757, 0x2763, 0x2764, 0x2795, 0x2797, 0x27A1, 0x27A1,
    0x27B0, 0x27B0, 0x27BF, 0x27BF, 0x2934, 0x2935, 0x2B05, 0x2B07,
    0x2B1B, 0x2B1C, 0x2B50, 0x2B50, 0x2B55, 0x2B55,
  ];

  static const List<int> _cjkScatter = <int>[
    0x2609, 0x2609, 0x260F, 0x260F, 0x2616, 0x2617, 0x261C, 0x261C, //
    0x261E, 0x261F, 0x2641, 0x2641, 0x2661, 0x2662, 0x2664, 0x2664,
    0x2667, 0x2667, 0x2669, 0x266F, 0x2672, 0x267A, 0x267C, 0x267D,
    0x2713, 0x2713, 0x271A, 0x271A, 0x273D, 0x273D, 0x273F, 0x2740,
    0x2756, 0x2756, 0x2776, 0x2793, 0x2B1A, 0x2B1A,
  ];

  static bool _inScatter(int rune, List<int> table) {
    var lo = 0;
    var hi = (table.length >> 1) - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (rune < table[mid << 1]) {
        hi = mid - 1;
      } else if (rune > table[(mid << 1) + 1]) {
        lo = mid + 1;
      } else {
        return true;
      }
    }
    return false;
  }

  @visibleForTesting
  static void resetForTest() {
    _loads.clear();
    _loaded.clear();
  }
}
