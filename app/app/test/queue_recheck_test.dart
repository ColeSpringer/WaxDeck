import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/books/book_screen.dart';
import 'package:waxdeck/src/player/deck_bar_host.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_item.dart';
import 'package:waxdeck/src/queue/queue_recheck.dart';
import 'package:waxdeck/src/queue/queue_screen.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/queue/queue_view.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck/src/sync/catalog_writes.dart';
import 'package:waxdeck/src/sync/sync_binder.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

const _a = 'tr-01JZX5N8QW3F4V9T2B7KDRECHA';
const _b = 'tr-01JZX5N8QW3F4V9T2B7KDRECHB';
const _c = 'tr-01JZX5N8QW3F4V9T2B7KDRECHC';

const _album = QueueSource(
  kind: QueueSourceKind.album,
  label: 'Kind of Blue',
  pid: 'al-1',
);

/// A catalog walk that can be told to lose its place once.
class _Repository extends FakeRepository {
  _Repository({super.items});

  bool resetNext = false;

  @override
  Future<CatalogSyncPage> syncCatalog({
    String? since,
    String? cursor,
    int? limit,
  }) async {
    if (resetNext && since != null) {
      resetNext = false;
      throw const WaxDeckApiException(
        code: 'sync-reset',
        message: 'the cursor is too old',
        statusCode: 410,
      );
    }
    return super.syncCatalog(since: since, cursor: cursor, limit: limit);
  }
}

typedef _Session = ({
  ProviderContainer container,
  _Repository repo,
  SyncEngine sync,
  FakeEngine engine,
});

/// A native session: the binder over a sync engine's mirror, and
/// playback over a fake engine. Nothing here is a kind change's dialog.
_Session _session() {
  final db = inMemoryMirrorDatabase();
  addTearDown(db.close);
  final downloads = FakeDownloads();
  addTearDown(downloads.dispose);
  final repo = _Repository(items: [testItem(_a), testItem(_b), testItem(_c)]);
  final sync = SyncEngine(
    db: db,
    repository: repo,
    channelFactory: deadChannelFactory(),
  );
  addTearDown(sync.dispose);
  final engine = FakeEngine(
    mediaDuration: const Duration(milliseconds: 214000),
  );
  final container = appContainer(
    repo: repo,
    engine: engine,
    mirror: db,
    downloads: downloads,
    sync: sync,
  );
  container.listen(syncBinderProvider, (_, _) {});
  return (container: container, repo: repo, sync: sync, engine: engine);
}

/// Another device turns [_a] into a book and folds [folded] into it.
void _changedElsewhere(_Repository repo, {required String folded}) {
  repo.libraryItems
    ..removeWhere((i) => i.pid == _a || i.pid == folded)
    ..add(testItem(_a, mediaType: MediaType.audiobook));
}

/// Waits out the quiet the catalog's changes are read after, and the reads.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(kCatalogRefreshWindow);
  await tester.pump();
}

/// Another run of catalog changes, settled: a separate pass.
Future<void> _anotherPass(WidgetTester tester, _Session s) async {
  await s.sync.pullCatalog();
  await _settle(tester);
}

/// Ends the session inside the test: its pacers and the engine's
/// reconnect are timers.
Future<void> _end(WidgetTester tester, _Session s) async {
  s.container.read(queueControllerProvider.notifier).clear();
  await tester.pump(const Duration(seconds: 1));
  s.container.dispose();
  await tester.pump();
}

List<String> _queued(_Session s) => [
  for (final e in s.container.read(queueControllerProvider).entries) e.pid,
];

/// The server's row for [pid] becomes [item].
void _rewritten(FakeRepository repo, String pid, ItemSummary item) {
  repo.libraryItems
    ..removeWhere((i) => i.pid == pid)
    ..add(item);
}

/// The queue over the deck bar, with animations off: a playing row's bars
/// never settle.
Future<void> _pumpQueueAndDeck(
  WidgetTester tester,
  ProviderContainer container,
) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpApp(
    tester,
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: const Column(
          children: <Widget>[
            Expanded(child: QueueScreen()),
            DeckBarHost(),
          ],
        ),
      ),
    ),
    container: container,
  );
}

/// Two chapters of a book, the second named [second].
List<ChapterMark> _marks(String second) => [
  const ChapterMark(index: 0, title: 'An Unexpected Party', startMs: 0),
  ChapterMark(index: 1, title: second, startMs: 1800000),
];

Finder _onDeck(String text) =>
    find.descendant(of: find.byType(DeckBar), matching: find.text(text));

Finder _inQueue(String text) =>
    find.descendant(of: find.byType(QueueRow), matching: find.text(text));

void main() {
  testWidgets('a kind change made elsewhere reaches the queue once the '
      'catalog settles', (tester) async {
    final s = _session();
    final playback = s.container.read(nowPlayingProvider.notifier);
    playback.play([testItem(_c), testItem(_a), testItem(_b)], source: _album);
    await tester.pump();
    final row = s.container.listen(queueItemProvider(_a), (_, _) {});
    await tester.pump();
    expect(row.read().value?.mediaType, MediaType.music);

    _changedElsewhere(s.repo, folded: _b);
    await s.sync.pullCatalog();
    // Nothing is read while the catalog is still moving.
    await tester.pump(const Duration(seconds: 1));
    expect(_queued(s), [_c, _a, _b]);

    await _settle(tester);
    // One lookup for the queue: the converted item reads as what it is at
    // once and, being another kind than the queue now, leaves it, as the
    // folded one, departed, does; what was playing plays on.
    expect(s.repo.resolvedItemPids.last, unorderedEquals([_c, _a, _b]));
    expect(row.read().value?.mediaType, MediaType.audiobook);
    expect(_queued(s), [_c]);
    expect(s.container.read(nowPlayingProvider).entry?.pid, _c);
    expect(s.engine.playing, isTrue);
    row.close();
    await _end(tester, s);
  });

  testWidgets('a playing entry that changed kind plays on as what it is', (
    tester,
  ) async {
    final s = _session();
    final playback = s.container.read(nowPlayingProvider.notifier);
    playback.play([testItem(_a), testItem(_c)], source: _album);
    await tester.pump();

    _changedElsewhere(s.repo, folded: _b);
    await s.sync.pullCatalog();
    await _settle(tester);

    expect(_queued(s), [_a, _c]);
    expect(s.container.read(nowPlayingProvider).entry?.pid, _a);
    expect(playback.summaryFor(_a)?.mediaType, MediaType.audiobook);
    await _end(tester, s);
  });

  testWidgets('a playlist lets an entry that changed kind go too', (
    tester,
  ) async {
    // The conversion was somebody's act, as a watched one is: the list
    // it sat in does not keep it.
    final s = _session();
    final playback = s.container.read(nowPlayingProvider.notifier);
    playback.play(
      [testItem(_c), testItem(_a)],
      source: const QueueSource(
        kind: QueueSourceKind.playlist,
        label: 'Mine',
        pid: 'pl-1',
      ),
    );
    await tester.pump();

    _changedElsewhere(s.repo, folded: _b);
    await s.sync.pullCatalog();
    await _settle(tester);

    expect(_queued(s), [_c]);
    await _end(tester, s);
  });

  testWidgets('a folded item that is playing plays on', (tester) async {
    final s = _session();
    final playback = s.container.read(nowPlayingProvider.notifier);
    playback.play([testItem(_b), testItem(_c)], source: _album);
    await tester.pump();
    final loads = s.engine.loadedUrls.length;

    _changedElsewhere(s.repo, folded: _b);
    await _anotherPass(tester, s);
    await _anotherPass(tester, s);

    expect(_queued(s), [_b, _c]);
    expect(s.engine.loadedUrls, hasLength(loads));
    expect(s.engine.playing, isTrue);
    expect(s.container.read(shellMessagesProvider), isNull);
    await _end(tester, s);
  });

  testWidgets('a folded item standing paused gives way to the one after '
      'it, which waits', (tester) async {
    final s = _session();
    final playback = s.container.read(nowPlayingProvider.notifier);
    playback.play([testItem(_b), testItem(_c)], source: _album);
    await tester.pump();
    await playback.transportPause();
    await tester.pump();

    _changedElsewhere(s.repo, folded: _b);
    await _anotherPass(tester, s);

    expect(_queued(s), [_c]);
    expect(s.engine.loadedUrl, contains(_c));
    expect(s.engine.playing, isFalse);
    // Said, not swapped in silence.
    expect(
      shellMessageText(s.container.read(shellMessagesProvider)),
      'What was playing is no longer in the library.',
    );
    await _end(tester, s);
  });

  testWidgets('an entry out of sight stays, and one gone for everyone '
      'leaves', (tester) async {
    final s = _session();
    final playback = s.container.read(nowPlayingProvider.notifier);
    playback.play([testItem(_c), testItem(_b)], source: _album);
    await tester.pump();
    final recheck = s.container.read(queueRecheckProvider);

    s.repo.hiddenItemPids.add(_b);
    await recheck.run();
    expect(_queued(s), [_c, _b], reason: 'out of sight can come back');

    // A lookup that failed says nothing of the items it asked about.
    s.repo.hiddenItemPids.clear();
    s.repo.libraryItems.removeWhere((i) => i.pid == _b);
    s.repo.resolveItemsError = const WaxDeckApiException(
      code: 'internal',
      message: 'the server stumbled',
      statusCode: 500,
    );
    await recheck.run();
    expect(_queued(s), [_c, _b]);

    s.repo.resolveItemsError = null;
    await recheck.run();
    expect(_queued(s), [_c]);
    await _end(tester, s);
  });

  testWidgets('a pass looks the queue up a hundred items a call', (
    tester,
  ) async {
    final s = _session();
    final many = [
      for (var i = 0; i < 150; i++)
        testItem('tr-01JZX5N8QW3F4V9T2B7K${'$i'.padLeft(4, '0')}'),
    ];
    s.repo.libraryItems.addAll(many);
    final playback = s.container.read(nowPlayingProvider.notifier);
    playback.play(many, source: _album);
    await tester.pump();
    s.repo.resolvedItemPids.clear();

    await s.container.read(queueRecheckProvider).run();

    expect(
      [for (final call in s.repo.resolvedItemPids) call.length],
      [100, 50],
    );
    expect(
      {for (final call in s.repo.resolvedItemPids) ...call},
      {for (final item in many) item.pid},
    );
    expect(_queued(s), hasLength(150));
    await _end(tester, s);
  });

  testWidgets('a parked entry that changed kind is offered as what it is '
      'now', (tester) async {
    final s = _session();
    final playback = s.container.read(nowPlayingProvider.notifier);
    playback.play([testItem(_a), testItem(_c)], source: _album);
    await tester.pump();
    final radio = s.container.read(radioPlaybackProvider.notifier);
    await radio.play(
      RadioStation(
        pid: 'st-1',
        name: 'Prancing Pony FM',
        streamUrl: 'https://pony.example/stream',
        createdAt: DateTime.utc(2026, 7, 25),
      ),
    );
    await tester.pump();
    final offered = s.container.listen(parkedEntryProvider, (_, _) {});
    expect(offered.read()?.item?.mediaType, MediaType.music);

    _changedElsewhere(s.repo, folded: _b);
    await s.sync.pullCatalog();
    await _settle(tester);

    expect(offered.read()?.entry.pid, _a);
    expect(offered.read()?.item?.mediaType, MediaType.audiobook);
    offered.close();
    await radio.stop();
    await _end(tester, s);
  });

  testWidgets('a pass keeps the summaries an undo would bring back', (
    tester,
  ) async {
    final s = _session();
    final playback = s.container.read(nowPlayingProvider.notifier);
    playback.play([testItem(_c), testItem(_a)], source: _album);
    await tester.pump();
    // A tap replaces the queue; the one it displaced waits to be undone.
    playback.play([testItem(_b)], source: _album);
    await tester.pump();
    expect(s.container.read(queueControllerProvider).undo, isNotNull);

    await s.sync.pullCatalog();
    await _settle(tester);

    expect(playback.summaryFor(_c), isNotNull);
    expect(playback.summaryFor(_a), isNotNull);
    await _end(tester, s);
  });

  testWidgets('a catalog walk that lost its place still reaches the queue', (
    tester,
  ) async {
    final s = _session();
    // A walk already under way: the mirror holds a cursor.
    await s.sync.pullCatalog();
    await _settle(tester);
    final playback = s.container.read(nowPlayingProvider.notifier);
    playback.play([testItem(_c), testItem(_a)], source: _album);
    await tester.pump();
    final row = s.container.listen(queueItemProvider(_a), (_, _) {});
    await tester.pump();

    _changedElsewhere(s.repo, folded: _b);
    s.repo.resetNext = true;
    await s.sync.pullCatalog();
    await _settle(tester);

    expect(s.repo.resetNext, isFalse, reason: 'the walk was reset');
    expect(row.read().value?.mediaType, MediaType.audiobook);
    row.close();
    await _end(tester, s);
  });

  testWidgets('a playing item renamed elsewhere is named anew on the deck '
      'bar and in the queue, where it plays', (tester) async {
    final repo = FakeRepository(
      items: [
        testItem(_a, title: 'Rivendel'),
        testItem(_b, title: 'Moria'),
      ],
    );
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final container = appContainer(repo: repo, engine: engine);
    await _pumpQueueAndDeck(tester, container);
    final playback = container.read(nowPlayingProvider.notifier);
    playback.play([
      testItem(_a, title: 'Rivendel'),
      testItem(_b, title: 'Moria'),
    ], source: _album);
    await tester.pumpAndSettle();
    expect(_onDeck('Rivendel'), findsOneWidget);
    expect(_inQueue('Rivendel'), findsOneWidget);
    await engine.seek(const Duration(seconds: 42));
    final session = container.read(nowPlayingProvider).session;
    final loads = engine.loadedUrls.length;

    _rewritten(
      repo,
      _a,
      testItem(_a, title: 'Rivendell', artist: 'The Last Homely House'),
    );
    _rewritten(repo, _b, testItem(_b, title: 'Khazad-dum'));
    await container.read(queueRecheckProvider).run();
    await tester.pumpAndSettle();

    expect(_onDeck('Rivendell'), findsOneWidget);
    expect(_onDeck('The Last Homely House'), findsOneWidget);
    expect(_inQueue('Rivendell'), findsOneWidget);
    expect(_inQueue('Khazad-dum'), findsOneWidget);
    expect(find.text('Rivendel'), findsNothing);
    expect(find.text('Moria'), findsNothing);
    // The stream and its place are the engine's: neither moved.
    final now = container.read(nowPlayingProvider);
    expect(now.session, same(session));
    expect(now.entry?.pid, _a);
    expect(engine.loadedUrls, hasLength(loads));
    expect(engine.position, const Duration(seconds: 42));
    expect(engine.playing, isTrue);
    expect(playback.summaryFor(_a)?.title, 'Rivendell');

    container.read(queueControllerProvider.notifier).clear();
    await tester.pumpAndSettle();
  });

  testWidgets('a pass that reads the same rows again rebuilds nothing', (
    tester,
  ) async {
    final s = _session();
    final playback = s.container.read(nowPlayingProvider.notifier);
    playback.play([testItem(_c), testItem(_a)], source: _album);
    await tester.pump();
    var playing = 0;
    var rows = 0;
    final now = s.container.listen(nowPlayingProvider, (_, _) => playing++);
    final row = s.container.listen(queueItemProvider(_a), (_, _) => rows++);
    await tester.pump();
    final held = playback.summaryFor(_a);
    playing = rows = 0;

    // Equal rows, each a new object as every read answers.
    _rewritten(s.repo, _c, testItem(_c));
    _rewritten(s.repo, _a, testItem(_a));
    await s.container.read(queueRecheckProvider).run();
    await tester.pump();

    expect(s.repo.resolvedItemPids, isNotEmpty);
    expect((playing, rows), (0, 0));
    expect(playback.summaryFor(_a), same(held));
    now.close();
    row.close();
    await _end(tester, s);
  });

  testWidgets('a queued row is redrawn for each thing it shows', (
    tester,
  ) async {
    final s = _session();
    final playback = s.container.read(nowPlayingProvider.notifier);
    playback.play([testItem(_c), testItem(_a)], source: _album);
    await tester.pump();
    final row = s.container.listen(queueItemProvider(_a), (_, _) {});
    await tester.pump();

    ItemSummary moved({
      String title = 'Prancing Pony Blues',
      String? artist = 'The Bree Trio',
      String? album,
      String? albumPid,
      String? artistPid,
      int durationMs = 214000,
      int? trackNumber,
    }) => ItemSummary(
      pid: _a,
      mediaType: MediaType.music,
      title: title,
      artist: artist,
      album: album,
      albumPid: albumPid,
      artistPid: artistPid,
      durationMs: durationMs,
      trackNumber: trackNumber,
    );
    for (final (what, next) in [
      ('title', moved(title: 'Bree Blues')),
      ('artist', moved(artist: 'Butterbur')),
      ('album', moved(album: 'Last Orders')),
      ('album pid', moved(albumPid: 'al-2')),
      ('artist pid', moved(artistPid: 'ar-2')),
      ('duration', moved(durationMs: 1000)),
      ('track number', moved(trackNumber: 4)),
    ]) {
      _rewritten(s.repo, _a, next);
      await s.container.read(queueRecheckProvider).run();
      // A read starts the row's rebuild, which lands a turn later.
      row.read();
      await tester.pump();
      expect(row.read().value, same(next), reason: what);
      expect(playback.summaryFor(_a), same(next), reason: what);
    }
    row.close();
    await _end(tester, s);
  });

  testWidgets('an episode renamed elsewhere keeps the show its settings '
      'hang off', (tester) async {
    const episode = 'ep-01JZX5N8QW3F4V9T2B7KDRECHE';
    final s = _session();
    final playback = s.container.read(nowPlayingProvider.notifier);
    final held = testEpisode(episode, title: 'The Shire, part one');
    playback.play([held], source: _album);
    await tester.pump();
    final session = s.container.read(nowPlayingProvider).session;

    // The item lookup answers a plain row, which names no show.
    s.repo.libraryItems.add(
      ItemSummary(
        pid: episode,
        mediaType: MediaType.podcast,
        title: 'The Shire, part 1',
        artist: held.artist,
        album: held.album,
        durationMs: held.durationMs,
        artUrl: held.artUrl,
      ),
    );
    await s.container.read(queueRecheckProvider).run();
    await tester.pump();

    final now = s.container.read(nowPlayingProvider);
    expect(now.item?.title, 'The Shire, part 1');
    expect(now.session, same(session));
    final kept = playback.summaryFor(episode);
    expect(kept, isA<EpisodeSummary>());
    expect(kept?.title, 'The Shire, part 1');
    expect((kept! as EpisodeSummary).showPid, held.showPid);
    expect((kept as EpisodeSummary).publishedAt, held.publishedAt);
    await _end(tester, s);
  });

  testWidgets('a rename read while its item loads names the item once it '
      'plays', (tester) async {
    final s = _session();
    final playback = s.container.read(nowPlayingProvider.notifier);
    final gate = s.repo.playInfoGate = Completer<void>();
    playback.play([testItem(_a)], source: _album);
    await tester.pump();
    expect(s.container.read(nowPlayingProvider).loading, isTrue);

    _rewritten(s.repo, _a, testItem(_a, title: 'Bree Blues'));
    await s.container.read(queueRecheckProvider).run();
    gate.complete();
    await tester.pump();
    await tester.pump();

    final now = s.container.read(nowPlayingProvider);
    expect(now.session, isNotNull);
    expect(now.item?.title, 'Bree Blues');
    await _end(tester, s);
  });

  testWidgets('a write made here reaches the queue at once, ahead of any '
      'hint', (tester) async {
    final s = _session();
    final playback = s.container.read(nowPlayingProvider.notifier);
    playback.play([testItem(_c), testItem(_a)], source: _album);
    await tester.pump();
    s.repo.resolvedItemPids.clear();

    _rewritten(s.repo, _c, testItem(_c, title: 'Bree Blues'));
    s.container.read(catalogWritesProvider).landed();
    await tester.pump();

    expect(s.repo.resolvedItemPids, [
      unorderedEquals([_c, _a]),
    ]);
    expect(s.container.read(nowPlayingProvider).item?.title, 'Bree Blues');
    await _end(tester, s);
  });

  group('a write made here that the server\'s read lags', () {
    // The write's answer is in; the lookup it makes at once still reads
    // the row from before it, and the server catches up a moment later.
    Future<_Session> landedAhead(WidgetTester tester) async {
      final s = _session();
      s.container.read(nowPlayingProvider.notifier).play([
        testItem(_c),
        testItem(_a),
      ], source: _album);
      // Past the engine's own start and whatever it prompted.
      await tester.pump(kCatalogRefreshWindow * 3);
      s.container.read(catalogWritesProvider).landed();
      await tester.pump();
      expect(s.container.read(nowPlayingProvider).item?.title, isNot('Bree'));
      _rewritten(s.repo, _c, testItem(_c, title: 'Bree'));
      return s;
    }

    testWidgets('names the item anew with the pass it is owed', (tester) async {
      final s = await landedAhead(tester);

      await tester.pump(kCatalogRefreshWindow);
      await tester.pump();

      expect(s.container.read(nowPlayingProvider).item?.title, 'Bree');
      await _end(tester, s);
    });

    testWidgets('names the item anew with the server\'s echo of it, ahead '
        'of the quiet after it', (tester) async {
      final s = await landedAhead(tester);

      await s.sync.pullCatalog();
      await tester.pump();
      await tester.pump();

      expect(s.container.read(nowPlayingProvider).item?.title, 'Bree');
      await _settle(tester);
      await _end(tester, s);
    });
  });

  testWidgets('a write made here leaves a kind change and what it folded '
      'to the write and to the settled pass', (tester) async {
    final s = _session();
    final playback = s.container.read(nowPlayingProvider.notifier);
    playback.play([testItem(_c), testItem(_a), testItem(_b)], source: _album);
    await tester.pump();

    _changedElsewhere(s.repo, folded: _b);
    s.container.read(catalogWritesProvider).landed();
    await tester.pump();

    expect(_queued(s), [_c, _a, _b]);
    expect(playback.summaryFor(_a)?.mediaType, MediaType.music);

    await _anotherPass(tester, s);
    expect(_queued(s), [_c]);
    await _end(tester, s);
  });

  group('a book played from its screen', () {
    const book = 'bk-01JZX5N8QW3F4V9T2B7KDRECHD';
    const authors = 'J. R. R. Tolkien, Christopher Tolkien';

    // The server's row for the book names what its tags say; the row the
    // book's screen plays it with names its authors and its series.
    ItemSummary row({
      String title = 'The Hobbit',
      String artist = 'J. R. R. Tolkien',
    }) => ItemSummary(
      pid: book,
      mediaType: MediaType.audiobook,
      title: title,
      artist: artist,
      album: 'The Hobbit (Unabridged)',
      durationMs: 3600000,
    );

    Future<({ProviderContainer container, FakeRepository repo})> played(
      WidgetTester tester,
    ) async {
      final repo = FakeRepository(items: [row()]);
      repo.books[book] = testBook(
        book,
        title: 'The Hobbit',
        authors: const ['J. R. R. Tolkien', 'Christopher Tolkien'],
        series: 'Middle-earth',
        chapters: _marks('Roast Mutton'),
      );
      final container = appContainer(
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(hours: 1)),
      );
      await _pumpQueueAndDeck(tester, container);
      final ref = tester.element(find.byType(DeckBarHost)) as WidgetRef;
      playBook(ref, repo.books[book]!, positionMs: 0);
      await tester.pumpAndSettle();
      expect(_onDeck(authors), findsOneWidget);
      return (container: container, repo: repo);
    }

    Future<void> end(WidgetTester tester, ProviderContainer container) async {
      container.read(queueControllerProvider.notifier).clear();
      await tester.pumpAndSettle();
    }

    /// The server's row for the book becomes [now], and its detail with
    /// it, by [authors].
    void edited(
      FakeRepository repo,
      ItemSummary now, {
      List<String> authors = const ['J. R. R. Tolkien', 'Christopher Tolkien'],
    }) {
      _rewritten(repo, book, now);
      repo.books[book] = testBook(
        book,
        title: now.title,
        authors: authors,
        series: 'Middle-earth',
        chapters: _marks('Roast Mutton'),
      );
    }

    testWidgets('keeps the row it was played with while nothing about the '
        'book changes', (tester) async {
      final (:container, :repo) = await played(tester);
      final playback = container.read(nowPlayingProvider.notifier);
      final held = playback.summaryFor(book);

      await container.read(queueRecheckProvider).run();
      await tester.pumpAndSettle();
      container.read(catalogWritesProvider).landed();
      await tester.pumpAndSettle();
      await container.read(queueRecheckProvider).run();
      await tester.pumpAndSettle();

      expect(repo.resolvedItemPids, isNotEmpty);
      expect(_onDeck(authors), findsOneWidget);
      expect(_inQueue(authors), findsOneWidget);
      expect(playback.summaryFor(book), same(held));
      await end(tester, container);
    });

    testWidgets('follows a real change of the book', (tester) async {
      final (:container, :repo) = await played(tester);
      await container.read(queueRecheckProvider).run();
      await tester.pumpAndSettle();

      edited(
        repo,
        row(artist: 'Tolkien, J. R. R.'),
        authors: const ['Tolkien, J. R. R.'],
      );
      await container.read(queueRecheckProvider).run();
      await tester.pumpAndSettle();
      expect(_onDeck('Tolkien, J. R. R.'), findsOneWidget);
      expect(_inQueue('Tolkien, J. R. R.'), findsOneWidget);

      edited(repo, row(title: 'There and Back Again'));
      container.read(catalogWritesProvider).landed();
      await tester.pumpAndSettle();
      expect(_onDeck('There and Back Again'), findsOneWidget);
      await end(tester, container);
    });

    testWidgets('renamed on the server keeps the line it was played with, '
        'under the new title', (tester) async {
      final (:container, :repo) = await played(tester);
      await container.read(queueRecheckProvider).run();
      await tester.pumpAndSettle();

      edited(repo, row(title: 'There and Back Again'));
      container.read(catalogWritesProvider).landed();
      await tester.pumpAndSettle();

      expect(_onDeck('There and Back Again'), findsOneWidget);
      expect(_onDeck(authors), findsOneWidget);
      expect(_inQueue(authors), findsOneWidget);
      final playing = container.read(nowPlayingProvider).item;
      expect(playing?.album, 'Middle-earth');
      expect(
        container.read(nowPlayingProvider.notifier).summaryFor(book),
        isA<ItemSummary>()
            .having((s) => s.title, 'title', 'There and Back Again')
            .having((s) => s.album, 'album', 'Middle-earth'),
      );
      await end(tester, container);
    });

    testWidgets('draws chapter marks an edit renamed, once the write lands', (
      tester,
    ) async {
      final (:container, :repo) = await played(tester);
      final session = container.read(nowPlayingProvider).session!;
      expect(session.book?.chapters[1].title, 'Roast Mutton');
      var published = 0;
      final now = container.listen(nowPlayingProvider, (_, _) => published++);

      repo.books[book] = testBook(
        book,
        title: 'The Hobbit',
        authors: const ['J. R. R. Tolkien', 'Christopher Tolkien'],
        series: 'Middle-earth',
        chapters: _marks('Trolls'),
      );
      container.read(catalogWritesProvider).landed();
      await tester.pumpAndSettle();

      final playing = container.read(nowPlayingProvider);
      expect(playing.session, same(session));
      expect(playing.session?.book?.chapters[1].title, 'Trolls');
      expect(published, greaterThan(0), reason: 'what draws them redraws');
      now.close();
      await end(tester, container);
    });

    testWidgets('follows a change made between its play and the first '
        'lookup', (tester) async {
      final (:container, :repo) = await played(tester);

      edited(
        repo,
        row(artist: 'Tolkien, J. R. R.'),
        authors: const ['Tolkien, J. R. R.'],
      );
      await container.read(queueRecheckProvider).run();
      await tester.pumpAndSettle();
      expect(_onDeck('Tolkien, J. R. R.'), findsOneWidget);
      await end(tester, container);
    });
  });

  testWidgets('a write made where nothing has played asks nothing of the '
      'queue', (tester) async {
    final repo = FakeRepository(items: [testItem(_a)]);
    final container = appContainer(repo: repo);

    container.read(catalogWritesProvider).landed();
    await tester.pump();

    expect(repo.resolvedItemPids, isEmpty);
    expect(container.exists(nowPlayingProvider), isFalse);
    expect(container.exists(queueControllerProvider), isFalse);
  });
}
