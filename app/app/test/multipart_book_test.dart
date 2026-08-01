import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
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
