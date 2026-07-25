import 'dart:async';

import 'package:alchemist/alchemist.dart';

import 'support/fonts.dart';

/// Golden harness configuration for the design system.
///
/// Two kinds of golden run here, and both are committed:
///
/// * **CI goldens** (`goldens/ci/`) obscure text as coloured blocks, so
///   they are identical on every host and can gate every machine. They
///   catch layout, spacing, and colour regressions.
/// * **Platform goldens** (`goldens/linux/`) render real type with the
///   bundled fonts, which is the only way a wrong weight or a lost
///   variable axis is visible. Font rasterisation differs between hosts,
///   so these are baselined on Linux (the development and CI platform)
///   and skipped elsewhere rather than failing there.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await loadWaxFonts();
  return AlchemistConfig.runWithConfig(
    config: AlchemistConfig(
      platformGoldensConfig: PlatformGoldensConfig(
        platforms: <HostPlatform>{HostPlatform.linux},
      ),
    ),
    run: testMain,
  );
}
