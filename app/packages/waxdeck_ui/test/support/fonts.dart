import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Registers the bundled faces with the test binding.
///
/// Tests render with the same font bytes the app ships, so a golden that
/// says "Archivo Expanded 640" is showing Archivo Expanded 640 and not
/// the test binding's fallback. Families are registered under the names
/// [TextStyle.package] produces (`packages/waxdeck_ui/<family>`), which
/// is what the type tokens resolve against.
///
/// The files are read from disk rather than from the asset bundle: tests
/// run with the package root as the working directory, and reading the
/// real files keeps the golden harness independent of asset-manifest
/// plumbing.
Future<void> loadWaxFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const families = <String, String>{
    'Archivo': 'fonts/Archivo-Variable.ttf',
    'Inter': 'fonts/Inter-Variable.ttf',
    'SplineSansMono': 'fonts/SplineSansMono-Variable.ttf',
    'NotoSansArabic': 'fonts/NotoSansArabic-Variable.ttf',
    'NotoSansHebrew': 'fonts/NotoSansHebrew-Variable.ttf',
    'NotoSansThai': 'fonts/NotoSansThai-Variable.ttf',
    // The icon subsets: without them every glyph renders as a notdef box
    // and a golden quietly stops proving anything about the icons.
    'PhosphorRegular': 'fonts/PhosphorRegular-Subset.ttf',
    'PhosphorFill': 'fonts/PhosphorFill-Subset.ttf',
  };
  for (final entry in families.entries) {
    final bytes = File(entry.value).readAsBytesSync();
    final loader = FontLoader('packages/waxdeck_ui/${entry.key}')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}

/// The bytes of one bundled face, for tests that inspect the file itself.
Uint8List waxFontBytes(String fileName) =>
    File('fonts/$fileName').readAsBytesSync();
