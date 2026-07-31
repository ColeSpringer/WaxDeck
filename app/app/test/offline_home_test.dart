import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/home/home_screen.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'routed_host.dart';

/// A channel that never reaches a server: connecting fails immediately,
/// which is exactly what airplane mode looks like to the engine.
class _DeadChannel extends EventsChannel {
  _DeadChannel({
    required super.onFrame,
    required super.onDone,
    required super.subscribe,
  }) : super(url: 'ws://unreachable', authToken: null);

  @override
  Future<void> connect() => Future.error(Exception('unreachable'));

  @override
  Future<void> close() async {}
}

/// The factory tests hand the engine so it always lands offline.
EventsChannelFactory deadChannelFactory() {
  return ({required onFrame, required onDone, required subscribe}) =>
      _DeadChannel(onFrame: onFrame, onDone: onDone, subscribe: subscribe);
}

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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          mirrorDatabaseProvider.overrideWithValue(db),
          downloadManagerProvider.overrideWithValue(downloads),
          artworkStoreProvider.overrideWithValue(FakeArtworkStore()),
          syncEngineProvider.overrideWithValue(engine),
        ],
        child: routedHost(const HomeScreen()),
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

  testWidgets('offline: a half-heard download resumes where it stopped', (
    tester,
  ) async {
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          mirrorDatabaseProvider.overrideWithValue(db),
          downloadManagerProvider.overrideWithValue(downloads),
          artworkStoreProvider.overrideWithValue(FakeArtworkStore()),
          syncEngineProvider.overrideWithValue(engine),
          audioEngineProvider.overrideWithValue(FakeEngine()),
          nowPlayingProvider.overrideWith(() => _RecordingNowPlaying(queue)),
        ],
        child: routedHost(const HomeScreen()),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(_byId(SemanticsIds.shelfCard('downloaded', 'tr-AAA')));
    await tester.pump();

    expect(
      queue.single,
      (pid: 'tr-AAA', positionMs: 90000),
      reason: 'a downloaded track resumed at zero instead of where it stopped',
    );
    await engine.stop();
  });
}

/// A playback controller that records what it was asked to play rather
/// than playing it: what this test is about is the position the card
/// handed over.
class _RecordingNowPlaying extends NowPlayingController {
  _RecordingNowPlaying(this.queue);

  final List<({String pid, int? positionMs})> queue;

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
