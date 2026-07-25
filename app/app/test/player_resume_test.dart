import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/player_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'player_host.dart';

/// Steps the fake clock one second at a time so each delta registers as
/// normal playback progress in the listen accounting.
Future<void> _listen(WidgetTester tester, FakeEngine engine, int secs) async {
  for (var i = 0; i < secs; i++) {
    engine.advance(const Duration(seconds: 1));
    await tester.pump();
  }
}

void main() {
  const pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';

  testWidgets('resumes from the saved play-state position', (tester) async {
    final repo = FakeRepository(items: [testItem(pid)])
      ..playPositions[pid] = 60000;
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );

    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
    );

    expect(engine.loadedUrl, '/media/stream?pid=$pid&mt=test-token');
    expect(engine.position, const Duration(seconds: 60));
    expect(engine.playing, isTrue);
    expect(find.byKey(const Key('player-toggle')), findsOneWidget);
    expect(find.byKey(const Key('player-seek')), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    await harness.endPlayback(tester);
  });

  testWidgets('starts from the top when nothing is saved', (tester) async {
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine();

    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
    );

    expect(engine.position, Duration.zero);
    expect(engine.playing, isTrue);
    await harness.endPlayback(tester);
  });

  testWidgets('playback survives the player screen being closed', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );

    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
    );
    await _listen(tester, engine, 3);

    // Leaving the player is not leaving the item: the session belongs to
    // the app now, so nothing here checkpoints or reports.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    expect(engine.playing, isTrue);
    expect(repo.reportedSessions, isEmpty);
    await harness.endPlayback(tester);
  });

  testWidgets('checkpoints and reports the listen session when the queue '
      'lets go', (tester) async {
    final repo = FakeRepository(items: [testItem(pid)])
      ..playPositions[pid] = 60000;
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );

    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
    );
    await _listen(tester, engine, 3);

    await harness.endPlayback(tester);

    expect(repo.putPlayStateCalls, isNotEmpty);
    expect(repo.putPlayStateCalls.last.pid, pid);
    expect(repo.putPlayStateCalls.last.positionMs, 63000);

    expect(repo.reportedSessions, hasLength(1));
    final session = repo.reportedSessions.single;
    expect(session.pid, pid);
    expect(session.sessionId, hasLength(26));
    expect(session.msPlayed, 3000);
    expect(session.finished, isFalse);
    expect(session.startedAt.isUtc, isTrue);
    expect(session.client, listenClientId);
  });

  testWidgets('a seek jump is not counted as listening', (tester) async {
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );

    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
    );

    await _listen(tester, engine, 2);
    await engine.seek(const Duration(seconds: 120));
    await tester.pump();
    await _listen(tester, engine, 2);

    await harness.endPlayback(tester);

    expect(repo.reportedSessions, hasLength(1));
    expect(repo.reportedSessions.single.msPlayed, 4000);
  });

  testWidgets('completion reports finished exactly once', (tester) async {
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(mediaDuration: const Duration(seconds: 10));

    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
    );
    await _listen(tester, engine, 11);

    expect(repo.reportedSessions, hasLength(1));
    final session = repo.reportedSessions.single;
    expect(session.finished, isTrue);
    expect(session.msPlayed, greaterThan(0));

    // Letting the queue go afterwards must not report the session again.
    await harness.endPlayback(tester);
    expect(repo.reportedSessions, hasLength(1));
  });

  testWidgets('a start failure renders on the player', (tester) async {
    final repo = FakeRepository(items: [testItem(pid)])
      ..playInfoError = const WaxDeckApiException(
        code: 'not-found',
        message: 'no item with that pid',
        statusCode: 404,
      );
    final engine = FakeEngine();

    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
    );

    expect(find.byKey(const Key('player-error')), findsOneWidget);
    expect(find.text('no item with that pid'), findsOneWidget);
    await harness.endPlayback(tester);
  });

  testWidgets('a failed start can be retried from the player', (tester) async {
    final repo = FakeRepository(items: [testItem(pid)])
      ..playInfoError = const WaxDeckApiException(
        code: 'transport',
        message: 'network unreachable',
      );
    final engine = FakeEngine();

    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
      positionMs: 30000,
    );
    expect(find.byKey(const Key('player-error')), findsOneWidget);
    // A start that never loaded records nothing: the engine's position
    // is not this item's, and a zero would lose the listener's place
    // for the retry to resume from.
    expect(repo.putPlayStateCalls, isEmpty);

    // The queue still holds the entry, so the same tap that failed is
    // one button away from playing — from where it was asked to start,
    // not from wherever the item was last checkpointed.
    repo.playInfoError = null;
    await tester.tap(find.byKey(const Key('player-retry')));
    await tester.pumpAndSettle();

    expect(engine.loadedUrl, contains(pid));
    expect(engine.playing, isTrue);
    expect(engine.position, const Duration(seconds: 30));
    expect(find.byKey(const Key('player-error')), findsNothing);
    await harness.endPlayback(tester);
  });

  testWidgets('the player says so when nothing is playing', (tester) async {
    final container = playbackContainer(
      repo: FakeRepository(),
      engine: FakeEngine(),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PlayerScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('player-idle')), findsOneWidget);
  });
}
