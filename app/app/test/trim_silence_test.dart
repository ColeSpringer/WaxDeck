import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'player_host.dart';

const showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const episodePid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';

/// Steps the fake clock one second at a time so each delta registers as
/// normal playback progress in the listen accounting.
Future<void> _listen(WidgetTester tester, FakeEngine engine, int secs) async {
  for (var i = 0; i < secs; i++) {
    engine.advance(const Duration(seconds: 1));
    await tester.pump();
  }
}

FakeRepository _repo() => FakeRepository()
  ..addSubscription(
    testShow(showPid),
    settings: const SubscriptionSettings(trimSilence: true),
  )
  ..episodesByShow[showPid] = [testEpisode(episodePid)]
  ..skipMaps[episodePid] = const SkipMap(
    state: 'ready',
    spans: [SkipSpan(startMs: 5000, endMs: 15000)],
  );

void main() {
  testWidgets('entering a span jumps to its end and counts hours saved', (
    tester,
  ) async {
    final repo = _repo();
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testEpisode(episodePid),
    );

    // Play up to the span: the fifth second lands inside it and the
    // session jumps forward to the span end.
    await _listen(tester, engine, 5);
    await tester.pump();

    expect(engine.position, const Duration(seconds: 15));
    // 10 seconds of silence were skipped; the chip shows the savings.
    expect(find.textContaining('saved 10s'), findsOneWidget);

    // The jump happened once; playback continues normally afterwards.
    await _listen(tester, engine, 2);
    expect(engine.position, const Duration(seconds: 17));
    await harness.endPlayback(tester);
  });

  testWidgets('the trim jump never distorts listen accounting', (tester) async {
    final repo = _repo();
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testEpisode(episodePid),
    );

    await _listen(tester, engine, 5); // jump to 15s fires on the 5th
    await tester.pump();
    await _listen(tester, engine, 3);

    await harness.endPlayback(tester);

    // 5 heard seconds before the jump, 3 after; the 10s jump itself is
    // a seek delta and never counts as listening.
    expect(repo.reportedSessions, hasLength(1));
    expect(repo.reportedSessions.single.msPlayed, 8000);
  });

  testWidgets('trim stays off when the map is unavailable', (tester) async {
    final repo = _repo()..skipMaps.clear();
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testEpisode(episodePid),
    );

    await _listen(tester, engine, 7);
    // No map: playback runs straight through the would-be span.
    expect(engine.position, const Duration(seconds: 7));
    await harness.endPlayback(tester);
  });

  testWidgets('the player chip toggles trimming at runtime', (tester) async {
    // Trim off in settings, but the map exists: enabling the chip loads
    // it and trimming starts working mid-session.
    final repo = _repo()
      ..addSubscription(
        testShow(showPid),
        settings: const SubscriptionSettings(trimSilence: false),
      );
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testEpisode(episodePid),
    );

    await tester.tap(find.byKey(const Key('player-trim')));
    await tester.pumpAndSettle();

    await _listen(tester, engine, 5);
    await tester.pump();
    expect(engine.position, const Duration(seconds: 15));
    await harness.endPlayback(tester);
  });
}
