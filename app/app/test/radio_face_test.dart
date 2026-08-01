import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/player/player_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck/src/settings/client_settings_providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

const _stationPid = 'rs-01JZX5N8QW3F4V9T2B7KDSTATN1';

RadioStation _station() => RadioStation(
  pid: _stationPid,
  name: 'Coastal FM',
  streamUrl: 'https://stream.example/coastal',
  homepageUrl: 'https://coastal.example',
  createdAt: DateTime.utc(2026, 7, 1),
);

/// Animations off: the platter ring turns forever, which is the point of
/// it and the end of `pumpAndSettle`.
Widget _stilled(Widget child) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child,
  ),
);

Future<ProviderContainer> _pumpTuned(
  WidgetTester tester, {
  required FakeRepository repo,
  required FakeEngine engine,
}) async {
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      audioEngineProvider.overrideWithValue(engine),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      clientSettingsStoreProvider.overrideWithValue(
        MemoryClientSettingsStore(),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(radioPlaybackProvider.notifier).play(_station());
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: routedHost(_stilled(const PlayerScreen())),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Lets the station go. The ICY poll is a live timer, and a test that
/// left one running fails on the pending timer rather than on what it
/// was checking.
Future<void> _stop(ProviderContainer container) =>
    container.read(radioPlaybackProvider.notifier).stop();

void main() {
  testWidgets('the player draws the station when radio has the engine', (
    tester,
  ) async {
    final repo = FakeRepository()..radioStationsByPid[_stationPid] = _station();
    final engine = FakeEngine();
    final container = await _pumpTuned(tester, repo: repo, engine: engine);

    expect(find.text('Coastal FM'), findsOneWidget);
    // Live, so there is no seek bar to lie with and no next to press.
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.bySemanticsIdentifier(SemanticsIds.playerSeek), findsNothing);
    expect(find.bySemanticsIdentifier(SemanticsIds.playerNext), findsNothing);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playerShuffle),
      findsNothing,
    );
    // The sleep timer is on every face: it is about the device rather
    // than the medium.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.sleepTimerOpen),
      findsOneWidget,
    );
    await _stop(container);
  });

  testWidgets('the one transport control stops the station', (tester) async {
    final repo = FakeRepository()..radioStationsByPid[_stationPid] = _station();
    final engine = FakeEngine();
    final container = await _pumpTuned(tester, repo: repo, engine: engine);

    expect(engine.playing, isTrue);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerToggle));
    await tester.pumpAndSettle();

    // Stop, not pause: a paused live stream resumes at the live edge
    // anyway, so the station is let go of entirely.
    expect(engine.playing, isFalse);
    expect(container.read(radioPlaybackProvider).station, isNull);
  });

  testWidgets('a named track offers a way into the library', (tester) async {
    final repo = FakeRepository()
      ..radioStationsByPid[_stationPid] = _station()
      ..radioNowPlaying[_stationPid] = 'Salt Harbour - The Bree Trio';
    final engine = FakeEngine();
    final container = await _pumpTuned(tester, repo: repo, engine: engine);

    expect(find.text('Salt Harbour - The Bree Trio'), findsOneWidget);
    final shortcut = find.bySemanticsIdentifier(
      SemanticsIds.playerFindInLibrary,
    );
    expect(shortcut, findsOneWidget);
    expect(tester.getSemantics(shortcut).label, contains('Salt Harbour'));
    await _stop(container);
  });

  testWidgets('a station nobody has named offers no search shortcut', (
    tester,
  ) async {
    final repo = FakeRepository()..radioStationsByPid[_stationPid] = _station();
    final container = await _pumpTuned(
      tester,
      repo: repo,
      engine: FakeEngine(),
    );

    expect(
      find.bySemanticsIdentifier(SemanticsIds.playerFindInLibrary),
      findsNothing,
    );
    await _stop(container);
  });

  testWidgets('the station can be pinned from the player', (tester) async {
    final repo = FakeRepository(
      sessionState: const SessionState(
        authenticated: true,
        user: WaxDeckUser(
          id: 'us-1',
          username: 'admin',
          roles: <String>['admin'],
        ),
      ),
    )..radioStationsByPid[_stationPid] = _station();
    final container = await _pumpTuned(
      tester,
      repo: repo,
      engine: FakeEngine(),
    );

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.radioFavorite(_stationPid)),
    );
    await tester.pumpAndSettle();
    expect(container.read(radioFavoritesProvider), contains(_stationPid));
    await _stop(container);
  });
}
