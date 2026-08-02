import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'player_host.dart';

const bookPid = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';

ItemSummary _bookItem() => const ItemSummary(
  pid: bookPid,
  mediaType: MediaType.audiobook,
  title: 'There And Back Again',
  durationMs: 120000,
);

void main() {
  testWidgets('completing a part rolls into the next with book-timeline '
      'checkpoints', (tester) async {
    // Two parts of one minute each; the fake engine plays 60s files.
    final repo = FakeRepository()
      ..books[bookPid] = testBook(bookPid, durationMs: 120000, partCount: 2);
    final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: _bookItem(),
    );

    expect(engine.loadedUrl, contains('part=0'));

    // Run part 0 off its end; the session resolves part 1 at book
    // position 60000 and keeps playing from the top of that file.
    engine.advance(const Duration(minutes: 1, seconds: 1));
    await tester.pumpAndSettle();

    expect(engine.loadedUrl, contains('part=1'));
    expect(engine.playing, isTrue);
    expect(engine.position, Duration.zero);
    expect(repo.playInfoCalls.map((c) => c.positionMs), [0, 60000]);
    // The part-boundary checkpoint is a book-timeline position.
    expect(repo.putPlayStateCalls.last.positionMs, 60000);

    // Listen into part 1, then let the queue go: the final checkpoint
    // lands past the whole of part 0 on the book timeline.
    engine.advance(const Duration(seconds: 5));
    await tester.pump();
    await harness.endPlayback(tester);

    expect(repo.putPlayStateCalls.last.positionMs, 65000);
    expect(repo.putPlayStateCalls.last.positionMs, greaterThan(60000));
  });

  testWidgets('a seek outside the loaded part re-resolves play-info', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..books[bookPid] = testBook(bookPid, durationMs: 120000, partCount: 2);
    final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: _bookItem(),
    );
    expect(engine.loadedUrl, contains('part=0'));

    // Seek to 90s on the book timeline (part 1 at 30s in) through the
    // seek bar, which speaks book-timeline positions for books. Driven
    // as a press on the bar rather than through a widget's callback:
    // the bar is a painted track, so three quarters along it is what a
    // reader would do and what the fraction means.
    final bar = tester.getRect(
      find.bySemanticsIdentifier(SemanticsIds.playerSeek),
    );
    await tester.tapAt(Offset(bar.left + bar.width * 0.75, bar.center.dy));
    await tester.pumpAndSettle();

    expect(engine.loadedUrl, contains('part=1'));
    expect(engine.position, const Duration(seconds: 30));
    expect(repo.playInfoCalls.last.positionMs, 90000);
    await harness.endPlayback(tester);
  });

  testWidgets('a chapter jump never writes a part-shifted checkpoint', (
    tester,
  ) async {
    // A load stops the transport first, and the stop publishes a pause
    // whose handler checkpoints. With the session's timeline state
    // written before the load, that checkpoint added the NEW part's
    // start to the OLD part's engine position: jump from part 0 at 10s
    // into part 1 and 70000 went to the server - a resume an entire
    // part ahead if it was the last write to land. The state moves
    // after the load now, so every checkpoint inside the window reads
    // the timeline the engine still plays.
    final repo = FakeRepository()
      ..books[bookPid] = testBook(bookPid, durationMs: 120000, partCount: 2);
    final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: _bookItem(),
    );
    expect(engine.loadedUrl, contains('part=0'));

    for (var i = 0; i < 5; i++) {
      engine.advance(const Duration(seconds: 2));
      await tester.pump();
    }

    final bar = tester.getRect(
      find.bySemanticsIdentifier(SemanticsIds.playerSeek),
    );
    await tester.tapAt(Offset(bar.left + bar.width * 0.75, bar.center.dy));
    await tester.pumpAndSettle();
    expect(engine.loadedUrl, contains('part=1'));

    final written = repo.putPlayStateCalls.map((c) => c.positionMs).toList();
    expect(
      written,
      contains(10000),
      reason: 'the mid-load pause checkpoints where part 0 stood',
    );
    expect(
      written,
      isNot(contains(70000)),
      reason: 'nothing may mix part 1\'s start with part 0\'s position',
    );
    await harness.endPlayback(tester);
  });

  testWidgets('a part that will not open surfaces the error and stops', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..books[bookPid] = testBook(bookPid, durationMs: 120000, partCount: 2);
    final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: _bookItem(),
    );
    expect(engine.loadedUrl, contains('part=0'));

    // Listen a little so the session has something to report, then run
    // part 0 out with part 1's media refusing to open. The roll used to
    // escape its unawaited zone as an unhandled async error: the book
    // stopped dead with the session still installed and nothing on
    // screen saying why.
    for (var i = 0; i < 3; i++) {
      engine.advance(const Duration(seconds: 2));
      await tester.pump();
    }
    engine.failNextLoad = true;
    engine.advance(const Duration(seconds: 56));
    await tester.pumpAndSettle();

    final playing = harness.container.read(nowPlayingProvider);
    expect(playing.error, isNotNull);
    expect(playing.session, isNull);
    expect(engine.playing, isFalse);
    // Checkpointed at the boundary this play actually reached, on the
    // book timeline - not shifted onto the part that refused - and the
    // listen reported unfinished, because the book is not over.
    expect(repo.putPlayStateCalls.last.positionMs, 60000);
    expect(repo.reportedSessions.last.finished, isFalse);
    await harness.endPlayback(tester);
  });

  testWidgets('a disposed session\'s late part load never starts the engine', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem('tr-A')])
      ..books[bookPid] = testBook(bookPid, durationMs: 120000, partCount: 2);
    final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: _bookItem(),
    );
    expect(engine.loadedUrl, contains('part=0'));

    // A cross-part jump parks inside its load, with the book playing...
    final gate = Completer<void>();
    engine.loadGate = gate;
    final session = harness.container.read(nowPlayingProvider).session!;
    final jump = session.seek(const Duration(milliseconds: 90000));
    await tester.pump();

    // ...and a restored queue takes the engine, standing paused.
    harness.container
        .read(nowPlayingProvider.notifier)
        .restore(
          QueueState.fromStored(
            StoredQueue(
              entries: const [
                StoredQueueEntry(queueId: 'q9', pid: 'tr-A', sourceRank: 0),
              ],
              currentIndex: 0,
              shuffled: false,
              repeat: 'off',
              sourceKind: 'album',
              sourceLabel: 'Kind of Blue',
              nextQueueId: 10,
              updatedAt: DateTime.utc(2026, 7, 25),
            ),
          ),
        );
    await tester.pumpAndSettle();
    expect(engine.loadedUrl, contains('tr-A'));
    expect(engine.playing, isFalse);

    gate.complete();
    await jump;
    await tester.pumpAndSettle();

    expect(
      engine.playing,
      isFalse,
      reason: 'the stale part load must not start what a newer session loaded',
    );
    expect(engine.loadedUrl, contains('tr-A'));
    await harness.endPlayback(tester);
  });

  testWidgets('a multi-part book resumes into the right part', (tester) async {
    final repo = FakeRepository()
      ..books[bookPid] = testBook(bookPid, durationMs: 120000, partCount: 2)
      ..playPositions[bookPid] = 75000;
    final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: _bookItem(),
    );

    expect(engine.loadedUrl, contains('part=1'));
    expect(engine.position, const Duration(seconds: 15));
    await harness.endPlayback(tester);
  });
}
