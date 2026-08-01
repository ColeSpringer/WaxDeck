import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'player_host.dart';

const _first = 'tr-01JZX5N8QW3F4V9T2B7KDMUSIC1';
const _second = 'tr-01JZX5N8QW3F4V9T2B7KDMUSIC2';
const _bookPid = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';

ItemSummary _track(String pid, String title) =>
    testItem(pid, title: title, artist: 'Nightjar');

void main() {
  group('the music face', () {
    testWidgets('carries the transport the old screen never had', (
      tester,
    ) async {
      final repo = FakeRepository(items: [_track(_first, 'Salt Harbour')]);
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
        item: _track(_first, 'Salt Harbour'),
      );

      for (final id in <String>[
        SemanticsIds.playerPrevious,
        SemanticsIds.playerNext,
        SemanticsIds.playerShuffle,
        SemanticsIds.playerRepeat,
        SemanticsIds.playerQueue,
      ]) {
        expect(find.bySemanticsIdentifier(id), findsOneWidget, reason: id);
      }
      await harness.endPlayback(tester);
    });

    testWidgets('shuffle and repeat drive the queue, not the engine', (
      tester,
    ) async {
      final repo = FakeRepository(items: [_track(_first, 'Salt Harbour')]);
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
        item: _track(_first, 'Salt Harbour'),
      );

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerShuffle));
      await tester.pumpAndSettle();
      expect(harness.container.read(queueControllerProvider).shuffled, isTrue);

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerRepeat));
      await tester.pumpAndSettle();
      expect(
        harness.container.read(queueControllerProvider).repeat,
        QueueRepeat.all,
      );
      await harness.endPlayback(tester);
    });

    testWidgets('the up-next peek names what plays next', (tester) async {
      final repo = FakeRepository(
        items: [_track(_first, 'Salt Harbour'), _track(_second, 'Gullwing')],
      );
      final harness = PlayerHarness(
        playbackContainer(repo: repo, engine: FakeEngine()),
      );
      harness.play([
        _track(_first, 'Salt Harbour'),
        _track(_second, 'Gullwing'),
      ]);
      await pumpPlayerInto(tester, harness);

      expect(find.text('Gullwing'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.bySemanticsIdentifier(SemanticsIds.playerUpNext))
            .label,
        contains('Gullwing'),
      );
      await harness.endPlayback(tester);
    });

    testWidgets('repeat-one has no next, and the peek says so', (tester) async {
      // The item plays again; the track after it is not what comes next,
      // and naming it is what deriving "next" from the index did.
      final repo = FakeRepository(
        items: [_track(_first, 'Salt Harbour'), _track(_second, 'Gullwing')],
      );
      final harness = PlayerHarness(
        playbackContainer(repo: repo, engine: FakeEngine()),
      );
      harness.play([
        _track(_first, 'Salt Harbour'),
        _track(_second, 'Gullwing'),
      ]);
      harness.container
          .read(queueControllerProvider.notifier)
          .setRepeat(QueueRepeat.one);
      await pumpPlayerInto(tester, harness);

      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerUpNext),
        findsNothing,
      );
      await harness.endPlayback(tester);
    });

    testWidgets('repeat-all wraps, and the peek names the wrap', (
      tester,
    ) async {
      // Standing on the last entry with repeat-all, playback goes back to
      // the first - so there is a next, and a peek that vanished here was
      // telling the listener the queue was about to end.
      final repo = FakeRepository(
        items: [_track(_first, 'Salt Harbour'), _track(_second, 'Gullwing')],
      );
      final harness = PlayerHarness(
        playbackContainer(repo: repo, engine: FakeEngine()),
      );
      harness.play([
        _track(_first, 'Salt Harbour'),
        _track(_second, 'Gullwing'),
      ], startIndex: 1);
      harness.container
          .read(queueControllerProvider.notifier)
          .setRepeat(QueueRepeat.all);
      await pumpPlayerInto(tester, harness);

      expect(
        tester
            .getSemantics(find.bySemanticsIdentifier(SemanticsIds.playerUpNext))
            .label,
        contains('Salt Harbour'),
      );
      // And no count beside it: nothing is left unplayed, which is not
      // the same as nothing being next.
      expect(find.textContaining('left'), findsNothing);
      await harness.endPlayback(tester);
    });

    testWidgets('nothing next means no peek at all', (tester) async {
      final repo = FakeRepository(items: [_track(_first, 'Salt Harbour')]);
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(),
        item: _track(_first, 'Salt Harbour'),
      );

      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerUpNext),
        findsNothing,
      );
      await harness.endPlayback(tester);
    });

    testWidgets('the provenance line says where the queue came from', (
      tester,
    ) async {
      final repo = FakeRepository(items: [_track(_first, 'Salt Harbour')]);
      final harness = PlayerHarness(
        playbackContainer(repo: repo, engine: FakeEngine()),
      );
      harness.play(
        [_track(_first, 'Salt Harbour')],
        source: const QueueSource(
          kind: QueueSourceKind.album,
          label: 'Salt Harbour',
          pid: 'al-01JZX5N8QW3F4V9T2B7KDALBUM1',
        ),
      );
      await pumpPlayerInto(tester, harness);

      expect(find.text('Playing from Salt Harbour'), findsOneWidget);
      await harness.endPlayback(tester);
    });
  });

  group('the spoken-word face', () {
    testWidgets('swaps the transport for interval seeks', (tester) async {
      final repo = FakeRepository()..addSubscription(testShow('pc-1'));
      final episode = testItem(
        'tr-01JZX5N8QW3F4V9T2B7KDEP0001',
        mediaType: MediaType.podcast,
      );
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(minutes: 30)),
        item: episode,
      );

      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerSkipBack),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerSkipForward),
        findsOneWidget,
      );
      // Nothing to skip to and nothing to shuffle: an episode plays on
      // its own, and the controls that would say otherwise are absent
      // rather than disabled.
      expect(find.bySemanticsIdentifier(SemanticsIds.playerNext), findsNothing);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerShuffle),
        findsNothing,
      );
      // And it keeps the controls it had before the rebuild.
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerSpeed),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerTrim),
        findsOneWidget,
      );
      await harness.endPlayback(tester);
    });

    testWidgets('a book reaches its chapters', (tester) async {
      final repo = FakeRepository()
        ..books[_bookPid] = testBook(
          _bookPid,
          durationMs: 120000,
          chapters: const [
            ChapterMark(index: 0, title: 'An Unexpected Party', startMs: 0),
            ChapterMark(index: 1, title: 'Roast Mutton', startMs: 60000),
          ],
        );
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(minutes: 2)),
        item: testItem(_bookPid, mediaType: MediaType.audiobook),
      );

      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerChapters),
        findsOneWidget,
      );
      await harness.endPlayback(tester);
    });
  });

  group('the sleep timer', () {
    testWidgets('is offered on music as well as on spoken word', (
      tester,
    ) async {
      final repo = FakeRepository(items: [_track(_first, 'Salt Harbour')]);
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(),
        item: _track(_first, 'Salt Harbour'),
      );

      expect(
        find.bySemanticsIdentifier(SemanticsIds.sleepTimerOpen),
        findsOneWidget,
      );
      await harness.endPlayback(tester);
    });
  });
}
