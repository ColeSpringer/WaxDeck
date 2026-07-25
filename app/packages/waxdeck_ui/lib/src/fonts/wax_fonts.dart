import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The bundled type: family names, the fallback chain, and the loader for
/// the scripts too large to ship in the default chain.
///
/// Fonts are assets, never runtime fetches. Native platforms would fall
/// back per glyph to system faces, but Flutter web resolves missing
/// glyphs by fetching Noto from Google's CDN, which a LAN-only or
/// air-gapped instance cannot reach: Arabic, Hebrew, and Thai metadata
/// would render as boxes. So the chain is owned, and the one family too
/// large to load eagerly (CJK) is served from WaxDeck's own origin and
/// loaded on demand.
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

  /// The CJK family, loaded on demand by [ensureCjk] rather than bundled
  /// into the eager chain: it is an order of magnitude larger than every
  /// other face combined.
  static const String cjk = 'NotoSansCJK';

  static const String _cjkAsset = 'assets/fonts/NotoSansCJK.ttf';

  /// The owned fallback chain, in resolution order. Latin, Greek, and
  /// Cyrillic are covered by the primary faces; these carry the scripts
  /// they do not.
  static const List<String> fallbacks = <String>[_arabic, _hebrew, _thai, cjk];

  static Future<void>? _cjkLoad;

  /// Whether [ensureCjk] has completed with a font actually installed.
  static bool get cjkLoaded => _cjkLoaded;
  static bool _cjkLoaded = false;

  /// Loads the CJK face from WaxDeck's own origin, once.
  ///
  /// Call it when the locale or the metadata on screen needs Han, kana,
  /// or hangul. It is safe to call repeatedly and safe to call on a build
  /// that ships without the asset: a missing font degrades to the
  /// platform's own fallback (native) or to the browser's (web), which is
  /// the same behaviour as not calling it at all.
  static Future<void> ensureCjk() {
    return _cjkLoad ??= () async {
      try {
        // The family name must match what TextStyle's `package:` argument
        // produces for the fallback entry, or the chain never reaches it.
        final loader = FontLoader('packages/$package/$cjk')
          ..addFont(rootBundle.load('packages/$package/$_cjkAsset'));
        await loader.load();
        _cjkLoaded = true;
      } on Object {
        // Absent asset or a decode failure: fall through quietly. Font
        // loading is never the reason a screen fails to render.
        _cjkLoaded = false;
      }
    }();
  }

  @visibleForTesting
  static void resetCjkForTest() {
    _cjkLoad = null;
    _cjkLoaded = false;
  }
}
