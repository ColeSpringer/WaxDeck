import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'player_host.dart';

const showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const episodePid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';

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
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testEpisode(episodePid),
    );

    expect(engine.speed, closeTo(1.0, 0.001));
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerSpeed));
    await tester.pumpAndSettle();

    expect(engine.speed, closeTo(1.25, 0.001));
    expect(repo.putSubscriptionSettingsCalls, hasLength(1));
    expect(repo.putSubscriptionSettingsCalls.single.pid, showPid);
    expect(
      repo.putSubscriptionSettingsCalls.single.settings.speed,
      closeTo(1.25, 0.001),
    );
    await harness.endPlayback(tester);
  });

  testWidgets('a remembered show speed applies on start', (tester) async {
    final repo = FakeRepository()
      ..addSubscription(
        testShow(showPid),
        settings: const SubscriptionSettings(speed: 1.5),
      )
      ..episodesByShow[showPid] = [testEpisode(episodePid)];
    final engine = FakeEngine();
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testEpisode(episodePid),
    );

    expect(engine.speed, closeTo(1.5, 0.001));
    await harness.endPlayback(tester);
  });

  testWidgets('music has no speed chip, and its speed never persists', (
    tester,
  ) async {
    const pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine();
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
    );

    // The music face carries no speed control (5.3): a rate belongs to
    // spoken word, where it is a per-show or per-book setting, and the
    // per-domain default is a Settings row rather than a player chip.
    expect(find.bySemanticsIdentifier(SemanticsIds.playerSpeed), findsNothing);

    // Set through the session, which is the seam anything else that
    // changes a rate goes through, and nothing is written back: a music
    // item has no per-entity settings to write to.
    await harness.container.read(nowPlayingProvider).session!.setSpeed(1.25);
    await tester.pumpAndSettle();

    expect(engine.speed, closeTo(1.25, 0.001));
    expect(repo.putSubscriptionSettingsCalls, isEmpty);
    expect(repo.putBookSettingsCalls, isEmpty);
    await harness.endPlayback(tester);
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
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testEpisode(episodePid),
    );

    expect(engine.position, const Duration(seconds: 30));
    expect(engine.playing, isTrue);
    await harness.endPlayback(tester);
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
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testEpisode(episodePid),
    );

    expect(engine.position, const Duration(seconds: 90));
    await harness.endPlayback(tester);
  });
}
