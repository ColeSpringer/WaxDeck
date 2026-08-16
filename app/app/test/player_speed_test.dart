import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/settings/client_prefs.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'player_host.dart';

const showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const episodePid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';

void main() {
  testWidgets('the speed sheet reaches any rate in one tap and persists it', (
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
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playerSpeedSheet),
      findsOneWidget,
    );

    // 1.75x from 1x without walking through what is between: the whole
    // point of replacing the cycling button.
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playerSpeedPreset(175)),
    );
    await tester.pumpAndSettle();

    expect(engine.speed, closeTo(1.75, 0.001));
    expect(repo.putSubscriptionSettingsCalls, hasLength(1));
    expect(repo.putSubscriptionSettingsCalls.single.pid, showPid);
    expect(
      repo.putSubscriptionSettingsCalls.single.settings.speed,
      closeTo(1.75, 0.001),
    );

    // A preset is a decision, so it lands and the sheet leaves: the
    // chip behind it is what a listener looks at next.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playerSpeedSheet),
      findsNothing,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsIdentifier(SemanticsIds.playerSpeed))
          .label,
      contains('1.75x'),
    );

    // The stepper reaches what the presets do not, one step at a time,
    // and keeps the sheet up while it is being walked.
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerSpeed));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playerSpeedSlower),
    );
    await tester.pumpAndSettle();
    expect(engine.speed, closeTo(1.70, 0.001));
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playerSpeedSheet),
      findsOneWidget,
    );
    await harness.endPlayback(tester);
  });

  testWidgets('a rate picked before the show settings landed still persists', (
    tester,
  ) async {
    // The regression an e2e run caught: the persist rebuilds the whole
    // settings object, so it read the copy the session had fetched and
    // gave up when there was none - with the engine already at the new
    // rate and the sheet's footer promising the show would remember it.
    // Here the session's own load answers not-found, which is the same
    // null the race leaves behind, and the write still has to land.
    final repo = FakeRepository()
      ..episodesByShow[showPid] = [testEpisode(episodePid)];
    final engine = FakeEngine();
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testEpisode(episodePid),
    );
    repo.addSubscription(testShow(showPid));

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerSpeed));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playerSpeedPreset(175)),
    );
    await tester.pumpAndSettle();

    expect(engine.speed, closeTo(1.75, 0.001));
    expect(repo.putSubscriptionSettingsCalls, hasLength(1));
    expect(
      repo.putSubscriptionSettingsCalls.single.settings.speed,
      closeTo(1.75, 0.001),
    );
    await harness.endPlayback(tester);
  });

  testWidgets('the stepper stops at the band the contract allows', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..addSubscription(
        testShow(showPid),
        settings: const SubscriptionSettings(speed: 3.5),
      )
      ..episodesByShow[showPid] = [testEpisode(episodePid)];
    final engine = FakeEngine();
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testEpisode(episodePid),
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerSpeed));
    await tester.pumpAndSettle();

    // The top of the band is where the stepper stops. The server
    // refuses anything past 3.5, so a press that appeared to work and
    // then failed to persist would be the worst of both.
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playerSpeedFaster),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(engine.speed, closeTo(3.5, 0.001));

    // And down from there is a real step, so the control is disabled
    // rather than inert.
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playerSpeedSlower),
    );
    await tester.pumpAndSettle();
    expect(engine.speed, closeTo(3.45, 0.001));
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

  testWidgets('the device defaults open a choiceless show with effects on', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..addSubscription(testShow(showPid))
      ..episodesByShow[showPid] = [testEpisode(episodePid)];
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final container = playbackContainer(repo: repo, engine: engine);
    container.read(trimSilenceDefaultProvider.notifier).set(true);
    container.read(voiceBoostDefaultProvider.notifier).set(true);
    final harness = PlayerHarness(container);
    harness.play([testEpisode(episodePid)]);
    await tester.pumpAndSettle();

    final session = container.read(nowPlayingProvider).session!;
    expect(session.trimEnabled.value, isTrue);
    expect(session.voiceBoost.value, isTrue);
    await harness.endPlayback(tester);
  });

  testWidgets('a stored per-show choice beats the device default', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..addSubscription(
        testShow(showPid),
        settings: const SubscriptionSettings(
          trimSilence: false,
          voiceBoost: false,
        ),
      )
      ..episodesByShow[showPid] = [testEpisode(episodePid)];
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final container = playbackContainer(repo: repo, engine: engine);
    container.read(trimSilenceDefaultProvider.notifier).set(true);
    container.read(voiceBoostDefaultProvider.notifier).set(true);
    final harness = PlayerHarness(container);
    harness.play([testEpisode(episodePid)]);
    await tester.pumpAndSettle();

    final session = container.read(nowPlayingProvider).session!;
    expect(session.trimEnabled.value, isFalse);
    expect(session.voiceBoost.value, isFalse);
    await harness.endPlayback(tester);
  });

  testWidgets('music never opens with the spoken-word defaults', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem('tr-A')]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final container = playbackContainer(repo: repo, engine: engine);
    container.read(trimSilenceDefaultProvider.notifier).set(true);
    container.read(voiceBoostDefaultProvider.notifier).set(true);
    final harness = PlayerHarness(container);
    harness.play([testItem('tr-A')]);
    await tester.pumpAndSettle();

    final session = container.read(nowPlayingProvider).session!;
    expect(session.trimEnabled.value, isFalse);
    expect(session.voiceBoost.value, isFalse);
    await harness.endPlayback(tester);
  });
}
