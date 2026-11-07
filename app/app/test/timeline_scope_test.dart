import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/playback_session.dart';
import 'package:waxdeck/src/player/timeline_scope.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'app_host.dart';
import 'fakes.dart';

Duration _s(int seconds) => Duration(seconds: seconds);

const _chapters = <ChapterMark>[
  ChapterMark(index: 0, title: 'Opening', startMs: 10000),
  ChapterMark(index: 1, title: 'Middle', startMs: 60000),
  ChapterMark(index: 2, title: 'Ending', startMs: 100000),
];

void main() {
  group('the window a book bar draws', () {
    test('is the chapter the position stands in', () {
      final window = bookWindow(
        chapters: _chapters,
        at: _s(75),
        total: _s(150),
        scope: BookTimelineScope.chapter,
      );
      expect(window.start, _s(60));
      expect(window.span, _s(40));
      expect(window.chapter, same(_chapters[1]));
      expect(withinWindow(_s(75), window), _s(15));
    });

    test('holds an intro before the first chapter at that chapter\'s '
        'start', () {
      final window = bookWindow(
        chapters: _chapters,
        at: _s(3),
        total: _s(150),
        scope: BookTimelineScope.chapter,
      );
      expect(window.chapter, same(_chapters[0]));
      expect(window.start, _s(10));
      expect(window.span, _s(50));
      expect(withinWindow(_s(3), window), Duration.zero);
    });

    test('ends the last chapter at the end of the book', () {
      final window = bookWindow(
        chapters: _chapters,
        at: _s(120),
        total: _s(150),
        scope: BookTimelineScope.chapter,
      );
      expect(window.start, _s(100));
      expect(window.start + window.span, _s(150));
      expect(withinWindow(_s(200), window), _s(50));
    });

    test('is the whole book for a book with no chapters', () {
      final window = bookWindow(
        chapters: const <ChapterMark>[],
        at: _s(75),
        total: _s(150),
        scope: BookTimelineScope.chapter,
      );
      expect(window.start, Duration.zero);
      expect(window.span, _s(150));
      expect(window.chapter, isNull);
      expect(withinWindow(_s(75), window), _s(75));
    });

    test('is the whole book when the book is asked for', () {
      final window = bookWindow(
        chapters: _chapters,
        at: _s(75),
        total: _s(150),
        scope: BookTimelineScope.book,
      );
      expect(window.start, Duration.zero);
      expect(window.span, _s(150));
      expect(window.chapter, isNull);
      expect(withinWindow(_s(75), window), _s(75));
    });
  });

  group('the scope', () {
    test('starts at the chapter, toggles, and is read back by the next '
        'launch', () async {
      final store = MemoryClientSettingsStore();
      ProviderContainer launch() => appContainer(settings: store);

      final first = launch();
      expect(first.read(bookTimelineScopeProvider), BookTimelineScope.chapter);
      first.read(bookTimelineScopeProvider.notifier).toggle();
      expect(first.read(bookTimelineScopeProvider), BookTimelineScope.book);
      await Future<void>.delayed(Duration.zero);
      expect(
        await store.read(ClientSettingKeys.bookTimelineScope),
        BookTimelineScope.book.name,
      );

      final next = launch();
      next.read(bookTimelineScopeProvider);
      await Future<void>.delayed(Duration.zero);
      expect(next.read(bookTimelineScopeProvider), BookTimelineScope.book);
      next.read(bookTimelineScopeProvider.notifier).toggle();
      expect(next.read(bookTimelineScopeProvider), BookTimelineScope.chapter);
    });
  });

  group('the feed the deck and the mini window follow', () {
    const bookPid = 'bk-01JZX5N8QW3F4V9T2B7KDFEED01';
    late FakeEngine engine;

    Future<PlaybackSession> started(
      ItemSummary item,
      FakeRepository repo,
    ) async {
      final session = PlaybackSession(
        repository: repo,
        engine: engine,
        item: item,
        clientId: 'test',
        initialPositionMs: 0,
      );
      addTearDown(session.dispose);
      await session.start(autoplay: true);
      return session;
    }

    BookWindowFeed feedOf(PlaybackSession session, BookTimelineScope scope) {
      final feed = BookWindowFeed()..follow(session, scope);
      addTearDown(feed.dispose);
      return feed;
    }

    setUp(() => engine = FakeEngine(mediaDuration: const Duration(minutes: 2)));

    test('moves its window at a chapter crossing, not on every tick', () async {
      final repo = FakeRepository()
        ..books[bookPid] = testBook(
          bookPid,
          durationMs: 120000,
          chapters: const [
            ChapterMark(index: 0, title: 'Prologue', startMs: 0),
            ChapterMark(index: 1, title: 'The Road', startMs: 30000),
          ],
        );
      final session = await started(
        testItem(bookPid, mediaType: MediaType.audiobook, durationMs: 120000),
        repo,
      );
      final feed = feedOf(session, BookTimelineScope.chapter);
      var moves = 0;
      feed.window.addListener(() => moves++);
      expect(feed.span, _s(30));

      for (var i = 0; i < 5; i++) {
        engine.advance(_s(5));
        await pumpEventQueue();
      }
      expect(feed.value, _s(25), reason: 'the position ticks');
      expect(moves, 0, reason: 'inside one chapter the window holds');

      engine.advance(_s(10));
      await pumpEventQueue();
      expect(moves, 1);
      expect(feed.window.value.start, _s(30));
      expect(feed.span, _s(90));
      expect(feed.value, _s(5));
      expect(feed.seekTarget(_s(45)), _s(75));
    });

    test('passes anything but a book through, its length read live', () async {
      final session = await started(testItem('tr-A'), FakeRepository());
      final feed = feedOf(session, BookTimelineScope.chapter);
      var moves = 0;
      feed.window.addListener(() => moves++);

      engine.advance(_s(70));
      await pumpEventQueue();
      expect(feed.value, _s(70));
      expect(feed.span, session.mediaDuration);
      expect(feed.seekTarget(_s(10)), _s(10));
      expect(moves, 0);

      // A stream learns its length after it starts; the span follows.
      engine.mediaDuration = _s(500);
      await engine.load('https://example.test/stream');
      expect(feed.span, _s(500));
    });

    test('following what it already follows does nothing', () async {
      final repo = FakeRepository()
        ..books[bookPid] = testBook(
          bookPid,
          durationMs: 120000,
          chapters: const [
            ChapterMark(index: 0, title: 'Prologue', startMs: 0),
            ChapterMark(index: 1, title: 'The Road', startMs: 30000),
          ],
        );
      final session = await started(
        testItem(bookPid, mediaType: MediaType.audiobook, durationMs: 120000),
        repo,
      );
      final feed = feedOf(session, BookTimelineScope.chapter);
      var notified = 0;
      feed.addListener(() => notified++);
      feed.window.addListener(() => notified++);

      feed.follow(session, BookTimelineScope.chapter);
      expect(notified, 0);

      feed.follow(session, BookTimelineScope.book);
      expect(feed.span, _s(120), reason: 'a scope switch moves the window');
    });
  });
}
