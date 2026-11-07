import 'package:flutter_riverpod/flutter_riverpod.dart';
// Override lives here rather than in the root library.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/home/home_screen.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart' hide QueueEntry;

import 'app_host.dart';
import 'fakes.dart';
import 'secondary_click.dart';

Finder _byId(String id) => find.bySemanticsIdentifier(id);

void main() {
  testWidgets('offline: the banner shows and what is downloaded is drawn', (
    tester,
  ) async {
    final db = inMemoryMirrorDatabase();
    addTearDown(db.close);

    // One mirrored item, as a previous online session left it, and the
    // download record that makes it playable with no network.
    await db
        .into(db.mirrorItems)
        .insert(
          MirrorItemsCompanion.insert(
            pid: 'tr-AAA',
            ulid: 'AAA',
            mediaType: 'music',
            title: 'Cached Song',
            artist: const Value('Fixture Artist'),
            album: const Value('Fixture Album'),
            durationMs: 1000,
            sortKey: 'cached song',
          ),
        );

    final downloads = FakeDownloads();
    addTearDown(downloads.dispose);
    downloads.setStored(<DownloadedItem>[
      const DownloadedItem(
        pid: 'tr-AAA',
        sizeBytes: 1024,
        files: 1,
        complete: true,
      ),
    ]);

    // The server is unreachable: every repository call fails like a
    // dead network, and the engine's channel cannot connect.
    final repo = FakeRepository();
    repo.listError = const WaxDeckApiException(
      code: 'transport',
      message: 'network unreachable',
    );
    final engine = SyncEngine(
      db: db,
      repository: repo,
      channelFactory: deadChannelFactory(),
    );
    addTearDown(engine.dispose);
    await engine.start();

    await mountApp(
      tester,
      const HomeScreen(),
      container: appContainer(
        repo: repo,
        mirror: db,
        downloads: downloads,
        sync: engine,
      ),
    );
    // Let the failed connect settle into offline status.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(_byId(SemanticsIds.offlineBanner), findsOneWidget);
    // The shelves are server reads and say nothing offline; what plays
    // with no network is what the screen offers instead.
    expect(_byId(SemanticsIds.shelf('downloaded')), findsOneWidget);
    expect(find.text('Cached Song'), findsOneWidget);
    expect(_byId(SemanticsIds.shelf('recent')), findsNothing);

    await engine.stop();
  });

  testWidgets('offline: a downloaded track starts at its head', (tester) async {
    final db = inMemoryMirrorDatabase();
    addTearDown(db.close);
    await db
        .into(db.mirrorItems)
        .insert(
          MirrorItemsCompanion.insert(
            pid: 'tr-AAA',
            ulid: 'AAA',
            mediaType: 'music',
            title: 'Cached Song',
            durationMs: 214000,
            sortKey: 'cached song',
          ),
        );
    // The position the mirror holds, which is the whole reason a
    // download row carries one: this shelf is the one most likely to be
    // tapped with no server to ask.
    await db
        .into(db.mirrorPlayStates)
        .insert(
          MirrorPlayStatesCompanion.insert(
            pid: 'tr-AAA',
            positionMs: const Value(90000),
          ),
        );

    final downloads = FakeDownloads();
    addTearDown(downloads.dispose);
    downloads.setStored(<DownloadedItem>[
      const DownloadedItem(
        pid: 'tr-AAA',
        sizeBytes: 1024,
        files: 1,
        complete: true,
      ),
    ]);

    final repo = FakeRepository();
    repo.listError = const WaxDeckApiException(
      code: 'transport',
      message: 'network unreachable',
    );
    final engine = SyncEngine(
      db: db,
      repository: repo,
      channelFactory: deadChannelFactory(),
    );
    addTearDown(engine.dispose);
    await engine.start();

    final queue = <({String pid, int? positionMs})>[];
    await mountApp(
      tester,
      const HomeScreen(),
      container: appContainer(
        repo: repo,
        mirror: db,
        downloads: downloads,
        sync: engine,
        extra: [
          nowPlayingProvider.overrideWith(() => _RecordingNowPlaying(queue)),
        ],
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(_byId(SemanticsIds.shelfCard('downloaded', 'tr-AAA')));
    await tester.pump();

    // A track starts at its head, as every other track's press does: the
    // mirror's position carries spoken word on, not music.
    expect(queue.single, (pid: 'tr-AAA', positionMs: null));
    await engine.stop();
  });
  testWidgets('offline: an episode played from its cover keeps its place', (
    tester,
  ) async {
    final queue = <({String pid, int? positionMs})>[];
    final engine = await _pumpOfflineEpisode(tester, queue);

    await hoverPlay(
      tester,
      _byId(SemanticsIds.shelfCard('downloaded', 'tr-EP1')),
      label: 'Resume Cached Episode',
    );
    expect(queue.single, (pid: 'tr-EP1', positionMs: 2400000));
    await engine.stop();
  });

  testWidgets('offline: a cover play on a parked entry asks for the park', (
    tester,
  ) async {
    final queue = <({String pid, int? positionMs})>[];
    final engine = await _pumpOfflineEpisode(
      tester,
      queue,
      extra: [
        parkedEntryProvider.overrideWithValue(
          const ParkedEntry(
            entry: QueueEntry(queueId: 'q-1', pid: 'tr-EP1'),
          ),
        ),
      ],
    );

    await hoverPlay(
      tester,
      _byId(SemanticsIds.shelfCard('downloaded', 'tr-EP1')),
      label: 'Resume Cached Episode',
    );
    expect(queue, isEmpty, reason: 'no fresh start over the park');
    final playback =
        ProviderScope.containerOf(
              tester.element(find.byType(HomeScreen)),
            ).read(nowPlayingProvider.notifier)
            as _RecordingNowPlaying;
    expect(playback.takenBack, hasLength(1));
    await engine.stop();
  });
}

/// A playback controller that records what it was asked to play rather
/// than playing it: what this test is about is the position the card
/// handed over.
class _RecordingNowPlaying extends NowPlayingController {
  _RecordingNowPlaying(this.queue);

  final List<({String pid, int? positionMs})> queue;

  /// The queue indexes taken back through [playEntryAt].
  final List<int> takenBack = <int>[];

  @override
  Future<void> playEntryAt(int index) async => takenBack.add(index);

  @override
  void play(
    List<ItemSummary> items, {
    required QueueSource source,
    int startIndex = 0,
    bool shuffle = false,
    int? positionMs,
  }) {
    for (final item in items) {
      queue.add((pid: item.pid, positionMs: positionMs));
    }
  }
}

/// Home offline over one downloaded episode, part way through on the
/// mirror, with playback recorded into [queue] rather than played.
Future<SyncEngine> _pumpOfflineEpisode(
  WidgetTester tester,
  List<({String pid, int? positionMs})> queue, {
  List<Override> extra = const <Override>[],
}) async {
  final db = inMemoryMirrorDatabase();
  addTearDown(db.close);
  await db
      .into(db.mirrorItems)
      .insert(
        MirrorItemsCompanion.insert(
          pid: 'tr-EP1',
          ulid: 'EP1',
          mediaType: 'podcast',
          title: 'Cached Episode',
          durationMs: 3600000,
          sortKey: 'cached episode',
        ),
      );
  // Ahead of anything the server heard, which is the point of the
  // mirror's copy: this shelf is played with no network.
  await db
      .into(db.mirrorPlayStates)
      .insert(
        MirrorPlayStatesCompanion.insert(
          pid: 'tr-EP1',
          positionMs: const Value(2400000),
        ),
      );
  final downloads = FakeDownloads();
  addTearDown(downloads.dispose);
  downloads.setStored(<DownloadedItem>[
    const DownloadedItem(
      pid: 'tr-EP1',
      sizeBytes: 1024,
      files: 1,
      complete: true,
    ),
  ]);
  final repo = FakeRepository();
  repo.listError = const WaxDeckApiException(
    code: 'transport',
    message: 'network unreachable',
  );
  final engine = SyncEngine(
    db: db,
    repository: repo,
    channelFactory: deadChannelFactory(),
  );
  addTearDown(engine.dispose);
  await engine.start();

  await mountApp(
    tester,
    const HomeScreen(),
    container: appContainer(
      repo: repo,
      mirror: db,
      downloads: downloads,
      sync: engine,
      extra: [
        nowPlayingProvider.overrideWith(() => _RecordingNowPlaying(queue)),
        ...extra,
      ],
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return engine;
}
