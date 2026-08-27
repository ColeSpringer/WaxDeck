import 'package:drift/drift.dart';
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import 'sync_engine_test.dart';

void main() {
  test('a disposed engine keeps queueing while the mirror is open', () async {
    final db = MirrorDatabase(DatabaseConnection(NativeDatabase.memory()));
    addTearDown(db.close);
    final engine = SyncEngine(
      db: db,
      repository: ScriptedRepository(),
      channelFactory: neverConnects(),
    );

    // A server address change rebuilds the engine while the mirror stays
    // open, and a playback session started earlier holds the old engine
    // for its whole life. Its checkpoints still have somewhere to land -
    // the replacement engine replays this same outbox - so disposal must
    // not drop them.
    engine.dispose();
    await engine.queueCheckpoint('tr-A', 1000);

    expect(await db.select(db.outboxMutations).get(), hasLength(1));
    final mirrored = await db
        .customSelect('SELECT position_ms FROM mirror_play_states')
        .get();
    expect(mirrored.single.read<int>('position_ms'), 1000);
  });

  test(
    'outbox writes after the mirror closed are dropped, not crashed',
    () async {
      final db = MirrorDatabase(DatabaseConnection(NativeDatabase.memory()));
      final engine = SyncEngine(
        db: db,
        repository: ScriptedRepository(),
        channelFactory: neverConnects(),
      );

      engine.dispose();
      await db.close();

      // The teardown race in one line each: the container disposed the
      // engine and closed the mirror, and a playback session's unawaited
      // shutdown checkpoint arrives afterwards. Nowhere to land is a drop,
      // never an uncaught error.
      await engine.queueCheckpoint('tr-A', 1000);
      await engine.queueStar('tr-A', true);
      await engine.queueRating('tr-A', 5);
      await engine.queueEntityStar('al-A', true);
      await engine.queueEntityRating('al-A', 4);
      await engine.queueListen(
        ListenSession(
          sessionId: 's-1',
          pid: 'tr-A',
          startedAt: DateTime.utc(2026),
          msPlayed: 1000,
          finished: true,
        ),
      );
    },
  );

  test(
    'a write in flight when the mirror closes under it is dropped',
    () async {
      // The desktop e2e teardown, faithfully: the mirror lives on a drift
      // isolate, and its channel closing mid-write is what surfaced as
      // "Channel was closed before receiving a response" after the test.
      final isolate = await DriftIsolate.spawn(NativeDatabase.memory);
      final db = MirrorDatabase(DatabaseConnection(await isolate.connect()));
      final engine = SyncEngine(
        db: db,
        repository: ScriptedRepository(),
        channelFactory: neverConnects(),
      );
      // A write the schema exists for, so the in-flight one below races
      // only the shutdown and not the first migration.
      await engine.queueCheckpoint('tr-A', 500);

      final inFlight = engine.queueCheckpoint('tr-A', 1000);
      engine.dispose();
      await db.close();
      await isolate.shutdownAll();

      await inFlight;
    },
  );
}
