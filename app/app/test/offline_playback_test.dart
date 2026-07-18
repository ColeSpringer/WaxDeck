import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/playback_session.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'offline_library_test.dart' show deadChannelFactory;

/// A downloads port with one completed item on "disk".
class _FakeDownloads implements DownloadManagerPort {
  _FakeDownloads(this.byPid);

  final Map<String, LocalPlayback> byPid;

  @override
  Future<LocalPlayback?> localFor(String pid) async => byPid[pid];

  @override
  Future<bool> isComplete(String pid) async => byPid.containsKey(pid);

  @override
  Future<void> download(String pid) async {}

  @override
  Future<void> remove(String pid) async {}

  @override
  Stream<DownloadProgress> get progress => const Stream.empty();
}

void main() {
  const unreachable = WaxDeckApiException(
    code: 'transport',
    message: 'network unreachable',
  );

  test('offline start plays the downloaded original from disk', () async {
    final repo = FakeRepository(items: [testItem('tr-AAA')]);
    repo.playInfoError = unreachable;
    final engine = FakeEngine();
    final session = PlaybackSession(
      repository: repo,
      engine: engine,
      item: testItem('tr-AAA'),
      clientId: 'test',
      downloads: _FakeDownloads({
        'tr-AAA': const LocalPlayback(paths: ['/downloads/AAA.flac']),
      }),
    );
    await session.start();
    expect(engine.loadedUrl, Uri.file('/downloads/AAA.flac').toString());
    expect(engine.playing, isTrue);
    await session.dispose();
  });

  test('without a download, an unreachable start propagates', () async {
    final repo = FakeRepository(items: [testItem('tr-AAA')]);
    repo.playInfoError = unreachable;
    final session = PlaybackSession(
      repository: repo,
      engine: FakeEngine(),
      item: testItem('tr-AAA'),
      clientId: 'test',
      downloads: _FakeDownloads(const {}),
    );
    await expectLater(session.start(), throwsA(unreachable));
  });

  test('failed checkpoints and listens queue in the outbox', () async {
    final db = inMemoryMirrorDatabase();
    final repo = FakeRepository(items: [testItem('tr-AAA')]);
    final sync = SyncEngine(
      db: db,
      repository: repo,
      channelFactory: deadChannelFactory(),
    );
    addTearDown(() async {
      sync.dispose();
      await db.close();
    });

    final engine = FakeEngine();
    final session = PlaybackSession(
      repository: repo,
      engine: engine,
      item: testItem('tr-AAA'),
      clientId: 'test',
      sync: sync,
      downloads: _FakeDownloads({
        'tr-AAA': const LocalPlayback(paths: ['/downloads/AAA.flac']),
      }),
    );
    repo.playInfoError = unreachable;
    await session.start();

    // Playback progresses; the server rejects every write like a dead
    // network would.
    repo.putPlayStateError = unreachable;
    repo.reportError = unreachable;
    for (var i = 0; i < 6; i++) {
      engine.advance(const Duration(seconds: 1));
      await pumpEventQueue();
    }
    await session.dispose();

    final queued = await db.select(db.outboxMutations).get();
    expect(queued, hasLength(1), reason: 'checkpoints coalesce per item');
    expect(queued.single.kind, 'position');
    expect(queued.single.pid, 'tr-AAA');
    final listens = await db.select(db.outboxListens).get();
    expect(listens, hasLength(1));
    expect(listens.single.pid, 'tr-AAA');
    expect(listens.single.msPlayed, greaterThan(0));
  });
}
