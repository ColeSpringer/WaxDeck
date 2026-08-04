import 'dart:async';
import 'dart:io';

import 'package:alchemist/alchemist.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Reached by path rather than by package, because it lives in the parent
// package's `test/` and test code is deliberately not on its release
// surface. The fonts a few lines down are read the same way and for the
// same reason.
// ignore: avoid_relative_lib_imports
import '../../test/support/tolerant_goldens.dart';

/// Golden harness for the composites.
///
/// Same contract as the design system's own harness: CI goldens (blocked
/// text, compared with a tolerance for host rasterisation) run
/// everywhere, and the readable Linux goldens are what prove the type is
/// the type. The comparator is the parent package's, for the same reason
/// the fonts are: one answer, in the package that owns the question.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  useTolerantGoldenComparator();
  const families = <String, String>{
    'Archivo': '../fonts/Archivo-Variable.ttf',
    'Inter': '../fonts/Inter-Variable.ttf',
    'SplineSansMono': '../fonts/SplineSansMono-Variable.ttf',
    'NotoSansArabic': '../assets/fonts/NotoSansArabic-Variable.ttf',
    'NotoSansHebrew': '../assets/fonts/NotoSansHebrew-Variable.ttf',
    'NotoSansThai': '../assets/fonts/NotoSansThai-Variable.ttf',
    'NotoSansCJK': '../assets/fonts/NotoSansCJK.otf',
    'PhosphorRegular': '../fonts/PhosphorRegular-Subset.ttf',
    'PhosphorFill': '../fonts/PhosphorFill-Subset.ttf',
  };
  for (final entry in families.entries) {
    final bytes = File(entry.value).readAsBytesSync();
    final loader = FontLoader('packages/waxdeck_ui/${entry.key}')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
  }

  return AlchemistConfig.runWithConfig(
    config: AlchemistConfig(
      platformGoldensConfig: PlatformGoldensConfig(
        platforms: <HostPlatform>{HostPlatform.linux},
      ),
    ),
    run: testMain,
  );
}
