import 'dart:io';

import 'package:flutter/services.dart';

/// Registers the faces the design system ships under the names its type
/// tokens resolve to, read from its own files: tests run from the app
/// package's root, beside the design system's.
///
/// flutter_test otherwise draws text in square glyphs an em wide, about
/// twice what the bundled faces take: what fits there fits anywhere, and
/// what overflows there may not overflow at all for a listener. A test
/// about what a listener sees at large type loads these first.
Future<void> loadBundledType() async {
  for (final (family, file) in const [
    ('Archivo', 'Archivo-Variable.ttf'),
    ('Inter', 'Inter-Variable.ttf'),
    ('SplineSansMono', 'SplineSansMono-Variable.ttf'),
    ('PhosphorRegular', 'PhosphorRegular-Subset.ttf'),
    ('PhosphorFill', 'PhosphorFill-Subset.ttf'),
  ]) {
    final bytes = File('../packages/waxdeck_ui/fonts/$file').readAsBytesSync();
    final loader = FontLoader('packages/waxdeck_ui/$family')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}
