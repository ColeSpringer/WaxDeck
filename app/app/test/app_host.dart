import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Override lives here rather than in the root library.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/artwork/artwork_store.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/client_settings_providers.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player/waxdeck_player.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'localized_host.dart';
import 'routed_host.dart';

/// A container with the ports the app reaches through a plugin or the
/// network faked, disposed when the test ends.
///
/// Pass a port to use that one in place of its fake, and [extra] for any
/// other override. [extra] must not name a provider this already
/// overrides - Riverpod refuses a second override of one - which is why
/// each port is a parameter. The downloads, settings, sync and mirror
/// providers keep their own test defaults unless given.
///
/// The credential store is in memory because the real one never answers
/// under test: the session would stay loading, where here it resolves to
/// whatever [repo] reports. The default repository is signed out, so a
/// test of the signed-in app passes `FakeRepository(sessionState: ...)`.
ProviderContainer appContainer({
  WaxDeckRepository? repo,
  AudioEnginePort? engine,
  CredentialStorePort? credentials,
  ArtworkStore? artwork,
  DownloadManagerPort? downloads,
  ClientSettingsStore? settings,
  SyncEngine? sync,
  MirrorDatabase? mirror,
  List<Override> extra = const <Override>[],
}) {
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo ?? FakeRepository()),
      audioEngineProvider.overrideWithValue(engine ?? FakeEngine()),
      credentialStoreProvider.overrideWithValue(
        credentials ?? InMemoryCredentialStore(),
      ),
      artworkStoreProvider.overrideWithValue(artwork ?? FakeArtworkStore()),
      if (downloads != null)
        downloadManagerProvider.overrideWithValue(downloads),
      if (settings != null)
        clientSettingsStoreProvider.overrideWithValue(settings),
      if (sync != null) syncEngineProvider.overrideWithValue(sync),
      if (mirror != null) mirrorDatabaseProvider.overrideWithValue(mirror),
      ...extra,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Mounts [screen] over [container] (a fresh [appContainer] if none is
/// given) and pumps one frame.
///
/// Routed by default, over the app's real route table; [pushed] and [at]
/// are `routedHost`'s. `routed: false` hosts it in `localizedHost`, for a
/// screen that never navigates, where they mean nothing.
Future<void> mountApp(
  WidgetTester tester,
  Widget screen, {
  ProviderContainer? container,
  bool routed = true,
  bool pushed = false,
  String? at,
  Locale locale = const Locale('en'),
}) async {
  assert(
    routed || (!pushed && at == null),
    'pushed and at belong to the routed host',
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container ?? appContainer(),
      child: routed
          ? routedHost(screen, pushed: pushed, at: at, locale: locale)
          : localizedHost(screen, locale: locale),
    ),
  );
}

/// [mountApp], then settled. Returns the container the screen runs over.
Future<ProviderContainer> pumpApp(
  WidgetTester tester,
  Widget screen, {
  ProviderContainer? container,
  bool routed = true,
  bool pushed = false,
  String? at,
  Locale locale = const Locale('en'),
}) async {
  final over = container ?? appContainer();
  await mountApp(
    tester,
    screen,
    container: over,
    routed: routed,
    pushed: pushed,
    at: at,
    locale: locale,
  );
  await tester.pumpAndSettle();
  return over;
}
