import 'dart:async';

import 'package:alchemist/alchemist.dart';

import 'support/fonts.dart';
import 'support/tolerant_goldens.dart';

/// Golden harness configuration for the design system.
///
/// Two kinds of golden run here, and both are committed:
///
/// * **CI goldens** (`goldens/ci/`) obscure text as coloured blocks and
///   are compared with a tolerance for host rasterisation, so they are
///   a gate on every machine rather than only on the one that baselined
///   them. They catch layout, spacing, and colour regressions. See
///   `support/tolerant_goldens.dart` for what the tolerance is and how
///   the two numbers in it were measured.
/// * **Platform goldens** (`goldens/linux/`) render real type with the
///   bundled fonts, which is the only way a wrong weight or a lost
///   variable axis is visible. That is the same difference host font
///   rasterisation makes on its own, so no tolerance can tell them
///   apart: these stay baselined on Linux (the CI platform) and skipped
///   elsewhere rather than failing there.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await loadWaxFonts();
  useTolerantGoldenComparator();
  return AlchemistConfig.runWithConfig(
    config: AlchemistConfig(
      platformGoldensConfig: PlatformGoldensConfig(
        platforms: <HostPlatform>{HostPlatform.linux},
      ),
    ),
    run: testMain,
  );
}
