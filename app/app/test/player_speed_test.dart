import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/player_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

const showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const episodePid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';

Widget _host(FakeRepository repo, FakeEngine engine, Widget home) =>
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        audioEngineProvider.overrideWithValue(engine),
      ],
      child: MaterialApp(home: home),
    );

void main() {
  testWidgets('the speed button steps the engine and persists per show', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..addSubscription(testShow(showPid))
      ..episodesByShow[showPid] = [testEpisode(episodePid)];
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    await tester.pumpWidget(
      _host(repo, engine, PlayerScreen(item: testEpisode(episodePid))),
    );
    await tester.pumpAndSettle();

    expect(engine.speed, closeTo(1.0, 0.001));
    await tester.tap(find.byKey(const Key('player-speed')));
    await tester.pumpAndSettle();

    expect(engine.speed, closeTo(1.25, 0.001));
    expect(repo.putSubscriptionSettingsCalls, hasLength(1));
    expect(repo.putSubscriptionSettingsCalls.single.pid, showPid);
    expect(
      repo.putSubscriptionSettingsCalls.single.settings.speed,
      closeTo(1.25, 0.001),
    );
  });

  testWidgets('a remembered show speed applies on start', (tester) async {
    final repo = FakeRepository()
      ..addSubscription(
        testShow(showPid),
        settings: const SubscriptionSettings(speed: 1.5),
      )
      ..episodesByShow[showPid] = [testEpisode(episodePid)];
    final engine = FakeEngine();
    await tester.pumpWidget(
      _host(repo, engine, PlayerScreen(item: testEpisode(episodePid))),
    );
    await tester.pumpAndSettle();

    expect(engine.speed, closeTo(1.5, 0.001));
  });

  testWidgets('music speed changes are session-only, never persisted', (
    tester,
  ) async {
    const pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine();
    await tester.pumpWidget(
      _host(repo, engine, PlayerScreen(item: testItem(pid))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('player-speed')));
    await tester.pumpAndSettle();

    expect(engine.speed, closeTo(1.25, 0.001));
    expect(repo.putSubscriptionSettingsCalls, isEmpty);
    expect(repo.putBookSettingsCalls, isEmpty);
  });

  testWidgets('skip-intro starts an episode past the intro', (tester) async {
    final repo = FakeRepository()
      ..addSubscription(
        testShow(showPid),
        settings: const SubscriptionSettings(skipIntroSeconds: 30),
      )
      ..episodesByShow[showPid] = [testEpisode(episodePid)];
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    await tester.pumpWidget(
      _host(repo, engine, PlayerScreen(item: testEpisode(episodePid))),
    );
    await tester.pumpAndSettle();

    expect(engine.position, const Duration(seconds: 30));
    expect(engine.playing, isTrue);
  });

  testWidgets('a resume point past the intro wins over the intro skip', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..addSubscription(
        testShow(showPid),
        settings: const SubscriptionSettings(skipIntroSeconds: 30),
      )
      ..episodesByShow[showPid] = [testEpisode(episodePid)]
      ..playPositions[episodePid] = 90000;
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    await tester.pumpWidget(
      _host(repo, engine, PlayerScreen(item: testEpisode(episodePid))),
    );
    await tester.pumpAndSettle();

    expect(engine.position, const Duration(seconds: 90));
  });
}
