import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import 'sync_engine_test.dart';

void main() {
  test('checkpoints coalesce per item: final intents, not history', () async {
    final db = MirrorDatabase(DatabaseConnection(NativeDatabase.memory()));
    final repo = ScriptedRepository();
    final engine = SyncEngine(
      db: db,
      repository: repo,
      channelFactory: neverConnects(),
    );
    addTearDown(() async {
      engine.dispose();
      await db.close();
    });

    for (var pos = 1000; pos <= 5000; pos += 1000) {
      await engine.queueCheckpoint('tr-A', pos);
    }
    await engine.queueCheckpoint('tr-B', 42);
    await engine.queueStar('tr-A', true);
    await engine.queueStar('tr-A', false);

    expect(await db.select(db.outboxMutations).get(), hasLength(3));
    await engine.flushOutbox();
    expect(repo.replayed, [
      'position:tr-A:5000:true',
      'position:tr-B:42:true',
      'star:tr-A:false:true',
    ]);
  });

  test('preference patches merge into one, later fields winning', () async {
    final db = MirrorDatabase(DatabaseConnection(NativeDatabase.memory()));
    final repo = ScriptedRepository()
      ..prefs = const Prefs(timezone: 'America/Denver');
    final engine = SyncEngine(
      db: db,
      repository: repo,
      channelFactory: neverConnects(),
    )..account = 'us-1';
    addTearDown(() async {
      engine.dispose();
      await db.close();
    });

    await engine.queuePrefsPatch({
      'pinned': ['AL-1'],
      'locale': 'es',
    }, owner: 'us-1');
    await engine.queuePrefsPatch({
      'pinned': ['AL-1', 'AL-2'],
    }, owner: 'us-1');

    expect(await db.select(db.outboxMutations).get(), hasLength(1));
    await engine.flushOutbox();
    expect(repo.prefsWrites, hasLength(1));
    final sent = repo.prefsWrites.single;
    expect(sent.pinned, ['AL-1', 'AL-2']);
    expect(sent.locale, 'es');
    expect(sent.timezone, 'America/Denver');
  });
}
