import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import 'fakes.dart';

/// The shared fake answers as the server does where tests lean on it.
void main() {
  const show = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
  const held = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';
  const failed = 'tr-01JZX5N8QW3F4V9T2B7KDEP0002';

  test('a fetch or a removal keeps an episode\'s sort key, and a fetch '
      'clears its last error', () async {
    final repo = FakeRepository()
      ..episodesByShow[show] = <EpisodeSummary>[
        testEpisode(held, title: 'The Held One', sortKey: 'held one'),
        testEpisode(
          failed,
          title: 'A Failed One',
          sortKey: 'failed one',
          downloaded: false,
          fetchState: 'failed',
          fetchError: 'the host refused',
        ),
      ];

    await repo.removeEpisodeDownload(held);
    await repo.fetchEpisode(failed);

    final [removed, queued] = repo.episodesByShow[show]!;
    expect(removed.sortKey, 'held one');
    expect(removed.downloaded, isFalse);
    expect(queued.sortKey, 'failed one');
    expect(queued.fetchState, 'queued');
    // Queued again, the server starts the fetch over with no error.
    expect(queued.fetchError, isNull);
  });

  test('a cleared job leaves its own account\'s list and still answers by '
      'pid', () async {
    const admin = WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']);
    const other = WaxDeckUser(id: 'us-2', username: 'ops', roles: ['admin']);
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: admin),
    )..jobs = const [Job(pid: 'jb-scan', kind: 'scan', state: 'done')];

    expect(await repo.clearFinishedJobs(), 1);
    expect(await repo.listJobs(), isEmpty);
    expect((await repo.getJob('jb-scan')).state, 'done');
    // Nothing left to clear here, and another administrator's list is
    // their own.
    expect(await repo.clearFinishedJobs(), 0);
    repo.sessionState = const SessionState(authenticated: true, user: other);
    expect([for (final job in await repo.listJobs()) job.pid], ['jb-scan']);
  });

  group('the downloads fake says stopped as the manager does', () {
    const book = 'bk-01JZX5N8QW3F4V9T2B7KD3M9R6';

    Future<List<DownloadProgress>> stops(
      Future<void> Function(FakeDownloads downloads) act, {
      FakeDownloads? downloads,
    }) async {
      final fake = downloads ?? FakeDownloads();
      addTearDown(fake.dispose);
      final seen = <DownloadProgress>[];
      final sub = fake.progress.listen(seen.add);
      addTearDown(sub.cancel);
      await act(fake);
      await pumpEventQueue();
      return seen.where((p) => p.stopped).toList();
    }

    test('only for what it still holds', () async {
      final seen = await stops((d) async {
        await d.download(book);
        await d.cancel(book);
        await d.cancel(book);
      });
      expect(seen, hasLength(1));
    });

    test('never for a download that threw before it held anything', () async {
      final seen = await stops((d) async {
        await expectLater(d.download(book), throwsA(isA<StateError>()));
        await d.cancel(book);
      }, downloads: FakeDownloads()..downloadError = StateError('no info'));
      expect(seen, isEmpty);
    });

    test('a canceled finished item is no longer on disk', () async {
      final downloads = FakeDownloads(local: {book: testLocal('/b.m4b')});
      final seen = await stops((d) => d.cancel(book), downloads: downloads);
      expect(seen, hasLength(1));
      expect(await downloads.isComplete(book), isFalse);
    });
  });
}
