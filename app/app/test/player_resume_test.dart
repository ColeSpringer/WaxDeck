import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/player_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

Widget _host(FakeRepository repo, FakeEngine engine, Widget home) =>
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        audioEngineProvider.overrideWithValue(engine),
      ],
      child: MaterialApp(home: home),
    );

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

    await tester.pumpWidget(
      _host(repo, engine, PlayerScreen(item: testItem(pid))),
    );
    await tester.pumpAndSettle();

    expect(engine.loadedUrl, '/media/stream?pid=$pid&mt=test-token');
    expect(engine.position, const Duration(seconds: 60));
    expect(engine.playing, isTrue);
    expect(find.byKey(const Key('player-toggle')), findsOneWidget);
    expect(find.byKey(const Key('player-seek')), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);
  });

  testWidgets('starts from the top when nothing is saved', (tester) async {
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine();

    await tester.pumpWidget(
      _host(repo, engine, PlayerScreen(item: testItem(pid))),
    );
    await tester.pumpAndSettle();

    expect(engine.position, Duration.zero);
    expect(engine.playing, isTrue);
  });

  testWidgets('checkpoints and reports the listen session on close', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem(pid)])
      ..playPositions[pid] = 60000;
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );

    await tester.pumpWidget(
      _host(repo, engine, PlayerScreen(item: testItem(pid))),
    );
    await tester.pumpAndSettle();
    await _listen(tester, engine, 3);

    // Leave the player; dispose flushes a checkpoint and the session.
    await tester.pumpWidget(_host(repo, engine, const SizedBox()));
    await tester.pumpAndSettle();

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

    await tester.pumpWidget(
      _host(repo, engine, PlayerScreen(item: testItem(pid))),
    );
    await tester.pumpAndSettle();

    await _listen(tester, engine, 2);
    await engine.seek(const Duration(seconds: 120));
    await tester.pump();
    await _listen(tester, engine, 2);

    await tester.pumpWidget(_host(repo, engine, const SizedBox()));
    await tester.pumpAndSettle();

    expect(repo.reportedSessions, hasLength(1));
    expect(repo.reportedSessions.single.msPlayed, 4000);
  });

  testWidgets('completion reports finished exactly once', (tester) async {
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(mediaDuration: const Duration(seconds: 10));

    await tester.pumpWidget(
      _host(repo, engine, PlayerScreen(item: testItem(pid))),
    );
    await tester.pumpAndSettle();
    await _listen(tester, engine, 11);

    expect(repo.reportedSessions, hasLength(1));
    final session = repo.reportedSessions.single;
    expect(session.finished, isTrue);
    expect(session.msPlayed, greaterThan(0));

    // Closing the player afterwards must not report the session again.
    await tester.pumpWidget(_host(repo, engine, const SizedBox()));
    await tester.pumpAndSettle();
    expect(repo.reportedSessions, hasLength(1));
  });
}
