import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_item.dart';
import 'package:waxdeck/src/queue/queue_recheck.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck/src/sync/sync_binder.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

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
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      audioEngineProvider.overrideWithValue(engine),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      mirrorDatabaseProvider.overrideWithValue(db),
      downloadManagerProvider.overrideWithValue(downloads),
      artworkStoreProvider.overrideWithValue(FakeArtworkStore()),
      syncEngineProvider.overrideWithValue(sync),
    ],
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
    // once, and the folded one, departed, leaves while what was playing
    // plays on.
    expect(s.repo.resolvedItemPids.last, unorderedEquals([_c, _a, _b]));
    expect(row.read().value?.mediaType, MediaType.audiobook);
    expect(_queued(s), [_c, _a]);
    expect(s.container.read(nowPlayingProvider).entry?.pid, _c);
    expect(s.engine.playing, isTrue);

    await playback.next();
    await tester.pump();
    final now = s.container.read(nowPlayingProvider);
    expect(now.entry?.pid, _a);
    expect(now.session?.item.mediaType, MediaType.audiobook);
    row.close();
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
    expect(s.container.read(shellMessengerProvider), isNull);
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
      shellMessageText(s.container.read(shellMessengerProvider)),
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
}
