import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/settings/client_prefs.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'player_host.dart';

const _showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const _episodePid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';
const _bookPid = 'bk-01JZX5N8QW3F4V9T2B7KD3M9R6';

ItemSummary _book() => testItem(
  _bookPid,
  mediaType: MediaType.audiobook,
  title: 'There And Back Again',
  artist: 'B. Baggins',
  durationMs: 3600000,
);

void main() {
  group('the podcast face', () {
    testWidgets('names the show above the episode and opens it', (
      tester,
    ) async {
      final repo = FakeRepository()
        ..addSubscription(testShow(_showPid))
        ..episodesByShow[_showPid] = [testEpisode(_episodePid)];
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
        item: testEpisode(_episodePid),
      );

      final overline = find.bySemanticsIdentifier(SemanticsIds.playerShow);
      expect(overline, findsOneWidget);
      expect(
        tester.getSemantics(overline).label,
        contains('The Prancing Pony Hour'),
      );
      await harness.endPlayback(tester);
    });

    testWidgets('offers notes, chapters, and a transcript as regions', (
      tester,
    ) async {
      final repo = FakeRepository()
        ..addSubscription(testShow(_showPid))
        ..episodesByShow[_showPid] = [
          testEpisode(_episodePid, hasTranscript: true),
        ]
        ..episodeDetails[_episodePid] = EpisodeDetail(
          pid: _episodePid,
          mediaType: MediaType.podcast,
          title: 'Pipeweed Economics',
          durationMs: 214000,
          showPid: _showPid,
          publishedAt: DateTime.utc(2026, 7, 1),
          downloaded: true,
          hasTranscript: true,
          descriptionHtml: '<p>What the pipeweed trade was worth.</p>',
          chapters: const <ChapterMark>[
            ChapterMark(index: 0, title: 'Cold open', startMs: 0),
            ChapterMark(index: 1, title: 'The trade', startMs: 60000),
          ],
        )
        ..transcripts[_episodePid] = const Transcript(
          format: 'vtt',
          cues: <TranscriptCue>[
            TranscriptCue(startMs: 0, text: 'Welcome back.'),
            TranscriptCue(startMs: 12000, text: 'Now, the pipeweed.'),
          ],
        );
      final engine = FakeEngine(
        mediaDuration: const Duration(milliseconds: 214000),
      );
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: engine,
        item: testEpisode(_episodePid, hasTranscript: true),
      );

      // Chapters first, because a chaptered episode is one a listener
      // navigates rather than reads about.
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerChapters),
        findsOneWidget,
      );
      for (final region in const ['chapters', 'notes', 'transcript']) {
        expect(
          find.bySemanticsIdentifier(SemanticsIds.playerRegion(region)),
          findsOneWidget,
          reason: 'the $region region should be offered',
        );
      }

      // A chapter tap seeks; the region is a navigation surface, not a
      // table of contents.
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.playerChapter(1)),
      );
      await tester.pumpAndSettle();
      expect(engine.position, const Duration(milliseconds: 60000));

      // The transcript follows playback and its cues seek too.
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.playerRegion('transcript')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.transcriptCue(1)),
      );
      await tester.pumpAndSettle();
      expect(engine.position, const Duration(milliseconds: 12000));
      await harness.endPlayback(tester);
    });

    testWidgets('the transcript marks where a paused episode stands', (
      tester,
    ) async {
      final repo = FakeRepository()
        ..addSubscription(testShow(_showPid))
        ..episodesByShow[_showPid] = [
          testEpisode(_episodePid, hasTranscript: true),
        ]
        ..episodeDetails[_episodePid] = EpisodeDetail(
          pid: _episodePid,
          mediaType: MediaType.podcast,
          title: 'Pipeweed Economics',
          durationMs: 214000,
          showPid: _showPid,
          publishedAt: DateTime.utc(2026, 7, 1),
          downloaded: true,
          hasTranscript: true,
          // Notes as well, so the region opens on those and the
          // transcript is built by the tap below rather than by the
          // player: the whole point is a transcript first drawn while
          // nothing is playing.
          descriptionHtml: '<p>What the pipeweed trade was worth.</p>',
        )
        ..transcripts[_episodePid] = const Transcript(
          format: 'vtt',
          cues: <TranscriptCue>[
            TranscriptCue(startMs: 0, text: 'Welcome back.'),
            TranscriptCue(startMs: 12000, text: 'Now, the pipeweed.'),
          ],
        );
      final engine = FakeEngine(
        mediaDuration: const Duration(milliseconds: 214000),
      );
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: engine,
        item: testEpisode(_episodePid, hasTranscript: true),
      );

      // Stopped where a listener left it, which is where a transcript
      // is most often opened: to read back what was just said.
      engine.advance(const Duration(seconds: 20));
      await harness.container.read(nowPlayingProvider).session!.toggle();
      await tester.pumpAndSettle();
      expect(engine.playing, isFalse);

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.playerRegion('transcript')),
      );
      await tester.pumpAndSettle();

      // A paused episode produces no position ticks at all, so the
      // highlight has to be placed when the cues arrive rather than on
      // the next one.
      expect(
        tester.getSemantics(
          find.bySemanticsIdentifier(SemanticsIds.transcriptCue(1)),
        ),
        isSemantics(isSelected: true),
      );
      await harness.endPlayback(tester);
    });

    testWidgets('voice boost persists per show and reopens the stream', (
      tester,
    ) async {
      final repo = FakeRepository()
        ..addSubscription(testShow(_showPid))
        ..episodesByShow[_showPid] = [testEpisode(_episodePid)];
      final engine = FakeEngine(
        mediaDuration: const Duration(milliseconds: 214000),
      );
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: engine,
        item: testEpisode(_episodePid),
      );
      final mintsBefore = repo.playInfoCalls.length;

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.playerVoiceBoost),
      );
      await tester.pumpAndSettle();

      expect(repo.putSubscriptionSettingsCalls, hasLength(1));
      expect(
        repo.putSubscriptionSettingsCalls.single.settings.voiceBoost,
        true,
      );
      // The server applies the boost when it mints the stream, so the
      // toggle is only honest if what is playing is reopened: a fresh
      // play-info is the request that carries it.
      expect(repo.playInfoCalls.length, mintsBefore + 1);
      await harness.endPlayback(tester);
    });

    testWidgets('each effect explains itself once and then stops', (
      tester,
    ) async {
      final repo = FakeRepository()
        ..addSubscription(testShow(_showPid))
        ..episodesByShow[_showPid] = [testEpisode(_episodePid)];
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
        item: testEpisode(_episodePid),
      );

      expect(harness.container.read(trimSilenceExplainedProvider), isFalse);
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerTrim));
      await tester.pump();
      expect(
        find.textContaining('skips the mapped quiet parts'),
        findsOneWidget,
      );

      // Said once and remembered as said: the flag is what stops the
      // second press from repeating it, and it is written before the
      // message so a double press cannot say it twice.
      expect(harness.container.read(trimSilenceExplainedProvider), isTrue);

      // Turning it off says nothing at all - an effect being switched
      // off has already explained itself.
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerTrim));
      await tester.pumpAndSettle();
      expect(
        harness.container.read(voiceBoostExplainedProvider),
        isFalse,
        reason: 'the two effects explain themselves separately',
      );
      await harness.endPlayback(tester);
    });
  });

  group('the book face', () {
    testWidgets('spans the chapter by default and the book on request', (
      tester,
    ) async {
      final repo = FakeRepository()
        ..books[_bookPid] = testBook(
          _bookPid,
          durationMs: 3600000,
          chapters: const [
            ChapterMark(index: 0, title: 'An Unexpected Party', startMs: 0),
            ChapterMark(index: 1, title: 'Roast Mutton', startMs: 1800000),
          ],
        );
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(hours: 1)),
        item: _book(),
      );

      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerTimeline('chapter')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerTimeline('book')),
        findsOneWidget,
      );
      // The chapter is what the title block names, whichever bar is
      // drawn.
      expect(find.text('An Unexpected Party'), findsWidgets);
      // And the book's own progress reads beside it either way.
      expect(find.textContaining('percent'), findsOneWidget);

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.playerTimeline('book')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('percent'), findsOneWidget);
      await harness.endPlayback(tester);
    });

    testWidgets('reads zero, not a wrapped clock, before chapter one', (
      tester,
    ) async {
      final repo = FakeRepository()
        ..books[_bookPid] = testBook(
          _bookPid,
          durationMs: 3600000,
          // An intro before the first chapter, which is ordinary for a
          // book whose marks came from its own metadata.
          chapters: const [
            ChapterMark(index: 0, title: 'An Unexpected Party', startMs: 5000),
            ChapterMark(index: 1, title: 'Roast Mutton', startMs: 1800000),
          ],
        );
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(hours: 1)),
        item: _book(),
      );

      // At zero the book stands before its own opening chapter, so the
      // chapter-relative position is negative. `formatTimecode` does not
      // draw a negative as one - minus five seconds reads "0:55" - so
      // the bar has to hold the position inside the span it draws.
      expect(find.text('0:55'), findsNothing);
      expect(find.text('0:00'), findsWidgets);
      await harness.endPlayback(tester);
    });

    testWidgets('lists its chapters with the one playing marked', (
      tester,
    ) async {
      final repo = FakeRepository()
        ..books[_bookPid] = testBook(
          _bookPid,
          durationMs: 3600000,
          chapters: const [
            ChapterMark(index: 0, title: 'An Unexpected Party', startMs: 0),
            ChapterMark(index: 1, title: 'Roast Mutton', startMs: 1800000),
          ],
        );
      final engine = FakeEngine(mediaDuration: const Duration(hours: 1));
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: engine,
        item: _book(),
      );

      final playing = find.bySemanticsIdentifier(SemanticsIds.playerChapter(0));
      expect(tester.getSemantics(playing).label, contains('playing'));

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.playerChapter(1)),
      );
      await tester.pumpAndSettle();
      expect(engine.position, const Duration(milliseconds: 1800000));
      await harness.endPlayback(tester);
    });

    testWidgets('a chapter jump the server refuses surfaces the failure', (
      tester,
    ) async {
      final repo = FakeRepository()
        ..books[_bookPid] = testBook(
          _bookPid,
          durationMs: 3600000,
          partCount: 2,
          chapters: const [
            ChapterMark(index: 0, title: 'An Unexpected Party', startMs: 0),
            ChapterMark(index: 1, title: 'Roast Mutton', startMs: 1860000),
          ],
        );
      final engine = FakeEngine(mediaDuration: const Duration(minutes: 30));
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: engine,
        item: _book(),
      );
      expect(engine.loadedUrl, contains('part=0'));

      // The server goes away, then the listener taps a chapter in the
      // other part. The jump used to rethrow into an unawaited call
      // site and die unseen: a dead tap, with the book playing on as if
      // nothing had been asked.
      repo.playInfoError = const WaxDeckApiException(
        code: 'transport',
        message: 'network unreachable',
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.playerChapter(1)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('player-error')), findsOneWidget);
      expect(harness.container.read(nowPlayingProvider).session, isNull);
      expect(engine.playing, isFalse);
      // The final checkpoint reads on the loaded part's timeline, not
      // shifted onto the part that refused to resolve.
      expect(repo.putPlayStateCalls.last.positionMs, lessThan(1800000));
      await harness.endPlayback(tester);
    });

    testWidgets('carries the bookmark button, and the sheet is its own', (
      tester,
    ) async {
      final repo = FakeRepository()
        ..books[_bookPid] = testBook(_bookPid, durationMs: 3600000);
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(hours: 1)),
        item: _book(),
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerBookmarks),
        findsOneWidget,
      );

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.playerBookmarks),
      );
      await tester.pumpAndSettle();
      // The button and the sheet are both in the tree now, so they
      // cannot share a handle: one identifier over two nodes is a spec
      // that resolves to two elements and fails strict rather than
      // retrying.
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerBookmarks),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerBookmarkSheet),
        findsOneWidget,
      );
      await harness.endPlayback(tester);
    });

    testWidgets('an episode carries none', (tester) async {
      final repo = FakeRepository()
        ..addSubscription(testShow(_showPid))
        ..episodesByShow[_showPid] = [testEpisode(_episodePid)];
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
        item: testEpisode(_episodePid),
      );
      // A bookmark is a place in something long enough to lose your
      // place in, and the endpoints are the book's own.
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerBookmarks),
        findsNothing,
      );
      await harness.endPlayback(tester);
    });
  });

  group('bookmarks', () {
    testWidgets('mark where the book stands, list, jump, and delete', (
      tester,
    ) async {
      final repo = FakeRepository()
        ..books[_bookPid] = testBook(_bookPid, durationMs: 3600000);
      final engine = FakeEngine(mediaDuration: const Duration(hours: 1));
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: engine,
        item: _book(),
      );
      engine.advance(const Duration(minutes: 12));
      await tester.pump();

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.playerBookmarks),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.bySemanticsIdentifier(SemanticsIds.playerBookmarkNote),
        'the riddle',
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.playerBookmarkAdd),
      );
      await tester.pumpAndSettle();

      // Where the book stands at the press, not where it stood when the
      // sheet opened.
      expect(repo.createBookmarkCalls, hasLength(1));
      expect(repo.createBookmarkCalls.single.positionMs, 12 * 60 * 1000);
      expect(repo.createBookmarkCalls.single.note, 'the riddle');

      final row = find.bySemanticsIdentifier(SemanticsIds.playerBookmark(0));
      expect(row, findsOneWidget);
      expect(tester.getSemantics(row).label, contains('the riddle'));

      // Jumping closes the sheet and seeks.
      engine.advance(const Duration(minutes: 5));
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(engine.position, const Duration(minutes: 12));

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.playerBookmarks),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.playerBookmarkDelete(0)),
      );
      await tester.pumpAndSettle();
      expect(repo.deleteBookmarkCalls, hasLength(1));
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerBookmark(0)),
        findsNothing,
      );
      await harness.endPlayback(tester);
    });

    testWidgets('a new mark lands in timeline order, not at the end', (
      tester,
    ) async {
      final repo = FakeRepository()
        ..books[_bookPid] = testBook(_bookPid, durationMs: 3600000);
      final engine = FakeEngine(mediaDuration: const Duration(hours: 1));
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: engine,
        item: _book(),
      );

      var stood = Duration.zero;
      Future<void> markAt(Duration at) async {
        engine.advance(at - stood);
        stood = at;
        await tester.pump();
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.playerBookmarks),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.playerBookmarkAdd),
        );
        await tester.pumpAndSettle();
        // Out through the barrier, which is how a listener closes it.
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();
      }

      // Later first, then earlier: the placement has to sort rather
      // than append, or a mark made out of order reads at the bottom of
      // a list the server would have returned it at the top of.
      await markAt(const Duration(minutes: 30));
      await markAt(const Duration(minutes: 5));

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.playerBookmarks),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(
              find.bySemanticsIdentifier(SemanticsIds.playerBookmark(0)),
            )
            .label,
        contains('5:00'),
      );
      await harness.endPlayback(tester);
    });

    testWidgets('a mark made before the first read lands survives it', (
      tester,
    ) async {
      final repo = _SlowListRepo()
        ..books[_bookPid] = testBook(_bookPid, durationMs: 3600000);
      final engine = FakeEngine(mediaDuration: const Duration(hours: 1));
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: engine,
        item: _book(),
      );

      // The button is drawn while the listing is still in flight, so a
      // quick tap-and-mark reaches the controller first. Pumped by hand
      // rather than settled: the sheet is showing a spinner for the
      // read this test is deliberately holding open, and settling waits
      // for a spinner that never stops.
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.playerBookmarks),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.playerBookmarkAdd),
      );
      await tester.pump();

      // The read was issued before the mark existed and cannot carry
      // it; letting it answer must not take the mark back off screen.
      // The mark itself waits for that read rather than racing it, so
      // nothing has been created yet at this point.
      expect(repo.createBookmarkCalls, isEmpty);
      repo.listGate.complete();
      await tester.pumpAndSettle();

      expect(repo.createBookmarkCalls, hasLength(1));
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerBookmark(0)),
        findsOneWidget,
      );
      await harness.endPlayback(tester);
    });

    testWidgets('a sheet dismissed mid-flight does not touch its field', (
      tester,
    ) async {
      final repo = _SlowCreateRepo()
        ..books[_bookPid] = testBook(_bookPid, durationMs: 3600000);
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(hours: 1)),
        item: _book(),
      );

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.playerBookmarks),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.playerBookmarkAdd),
      );
      await tester.pump();

      // Out through the barrier while the mark is still in flight: the
      // sheet's state disposes its controller on the way.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      repo.createGate.complete();
      await tester.pumpAndSettle();
      // Clearing a disposed controller throws where the field is simply
      // no longer there to clear.
      expect(tester.takeException(), isNull);
      await harness.endPlayback(tester);
    });

    testWidgets('a refused mark says why rather than appearing to land', (
      tester,
    ) async {
      final repo = FakeRepository()
        ..books[_bookPid] = testBook(_bookPid, durationMs: 3600000)
        ..createBookmarkError = const WaxDeckApiException(
          code: 'invalid-request',
          message: 'this book already holds as many bookmarks as it can',
          statusCode: 400,
        );
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(hours: 1)),
        item: _book(),
      );

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.playerBookmarks),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.playerBookmarkAdd),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('as many bookmarks'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerBookmark(0)),
        findsNothing,
      );
      await harness.endPlayback(tester);
    });
  });
}

/// A repository whose bookmark listing is held open, so a test can act
/// while the first read is still in flight.
///
/// The answer is taken when the read is issued rather than when it
/// lands, which is what a real round trip does and what makes a
/// held-open read genuinely stale: a fake that re-read on the way out
/// would answer with whatever was created in the meantime and would
/// pass whether or not the race was handled.
class _SlowListRepo extends FakeRepository {
  final listGate = Completer<void>();

  @override
  Future<List<Bookmark>> listBookmarks(String pid) async {
    final answer = await super.listBookmarks(pid);
    await listGate.future;
    return answer;
  }
}

/// The same for the create, so a test can leave the sheet mid-flight.
class _SlowCreateRepo extends FakeRepository {
  final createGate = Completer<void>();

  @override
  Future<Bookmark> createBookmark(
    String pid,
    int positionMs, {
    String? note,
  }) async {
    await createGate.future;
    return super.createBookmark(pid, positionMs, note: note);
  }
}
