import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/library/library_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import 'fakes.dart';

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

void main() {
  testWidgets('offline: the banner shows and the mirror serves the grid', (
    tester,
  ) async {
    final db = inMemoryMirrorDatabase();
    addTearDown(db.close);

    // Two mirrored items, as a previous online session left them.
    await db.batch(
      (b) => b.insertAll(db.mirrorItems, [
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
        MirrorItemsCompanion.insert(
          pid: 'tr-BBB',
          ulid: 'BBB',
          mediaType: 'music',
          title: 'Other Cached Song',
          artist: const Value('Fixture Artist'),
          album: const Value('Fixture Album'),
          durationMs: 1000,
          sortKey: 'other cached song',
        ),
      ]),
    );

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
          syncEngineProvider.overrideWithValue(engine),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      ),
    );
    // Let the failed connect settle into offline status.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Offline: showing the local library'), findsOneWidget);
    expect(find.text('Cached Song'), findsOneWidget);
    expect(find.text('Other Cached Song'), findsOneWidget);

    await engine.stop();
  });
}
