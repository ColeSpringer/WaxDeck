import 'dart:async';
import 'dart:io';

import 'package:alchemist/alchemist.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Golden harness for the composites.
///
/// Same contract as the design system's own harness: CI goldens (blocked
/// text) run everywhere, and the readable Linux goldens are what prove
/// the type is the type. Fonts come from the parent package, where they
/// are bundled.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const families = <String, String>{
    'Archivo': '../fonts/Archivo-Variable.ttf',
    'Inter': '../fonts/Inter-Variable.ttf',
    'SplineSansMono': '../fonts/SplineSansMono-Variable.ttf',
    'NotoSansArabic': '../fonts/NotoSansArabic-Variable.ttf',
    'NotoSansHebrew': '../fonts/NotoSansHebrew-Variable.ttf',
    'NotoSansThai': '../fonts/NotoSansThai-Variable.ttf',
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
