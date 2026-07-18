import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
