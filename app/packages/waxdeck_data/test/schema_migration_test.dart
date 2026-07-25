import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import 'sync_engine_test.dart';

/// The schema as v1 shipped it, verbatim from that version's generated
/// DDL. Migrations are tested against real old bytes, not against a
/// re-derived guess at what v1 looked like.
const _v1Schema = [
  'CREATE TABLE "mirror_items" ("pid" TEXT NOT NULL, "ulid" TEXT NOT NULL, '
      '"media_type" TEXT NOT NULL, "title" TEXT NOT NULL, "artist" TEXT NULL, '
      '"album" TEXT NULL, "duration_ms" INTEGER NOT NULL, '
      '"sort_key" TEXT NOT NULL, PRIMARY KEY ("pid"), UNIQUE ("ulid"));',
  'CREATE TABLE "mirror_play_states" ("pid" TEXT NOT NULL, '
      '"position_ms" INTEGER NOT NULL DEFAULT 0, '
      '"played" INTEGER NOT NULL DEFAULT 0 CHECK ("played" IN (0, 1)), '
      '"finished" INTEGER NOT NULL DEFAULT 0 CHECK ("finished" IN (0, 1)), '
      '"play_count" INTEGER NOT NULL DEFAULT 0, '
      '"starred" INTEGER NOT NULL DEFAULT 0 CHECK ("starred" IN (0, 1)), '
      '"rating" INTEGER NULL, "updated_at" INTEGER NULL, PRIMARY KEY ("pid"));',
  'CREATE TABLE "sync_cursors" ("id" INTEGER NOT NULL DEFAULT 1, '
      '"catalog_since" TEXT NULL, "server_since" TEXT NULL, PRIMARY KEY ("id"));',
  'CREATE TABLE "outbox_mutations" ("id" INTEGER NOT NULL PRIMARY KEY '
      'AUTOINCREMENT, "kind" TEXT NOT NULL, "pid" TEXT NOT NULL, '
      '"position_ms" INTEGER NULL, '
      '"starred" INTEGER NULL CHECK ("starred" IN (0, 1)), '
      '"rating" INTEGER NULL, "recorded_at" INTEGER NOT NULL);',
  'CREATE TABLE "outbox_listens" ("session_id" TEXT NOT NULL, '
      '"pid" TEXT NOT NULL, "started_at" INTEGER NOT NULL, '
      '"ms_played" INTEGER NOT NULL, '
      '"finished" INTEGER NOT NULL DEFAULT 0 CHECK ("finished" IN (0, 1)), '
      '"client" TEXT NOT NULL DEFAULT \'\', PRIMARY KEY ("session_id"));',
  'CREATE TABLE "download_records" ("pid" TEXT NOT NULL, '
      '"file_index" INTEGER NOT NULL, "essence_hash" TEXT NOT NULL, '
      '"etag" TEXT NOT NULL, "file_name" TEXT NOT NULL, '
      '"local_path" TEXT NOT NULL, "size_bytes" INTEGER NOT NULL, '
      '"state" TEXT NOT NULL, "span_start_ms" INTEGER NULL, '
      '"span_end_ms" INTEGER NULL, PRIMARY KEY ("pid", "file_index"));',
];

/// A database holding what a v1 install would hold, opened through the
/// current schema so the upgrade path runs on first use.
MirrorDatabase _upgradedFromV1() {
  return MirrorDatabase(
    NativeDatabase.memory(
      setup: (raw) {
        for (final statement in _v1Schema) {
          raw.execute(statement);
        }
        raw.execute(
          'INSERT INTO outbox_listens (session_id, pid, started_at, ms_played, '
          "finished, client) VALUES ('ls-1', 'tr-A', 1700000000, 42000, 1, "
          "'waxdeck-flutter-android');",
        );
        raw.execute(
          'INSERT INTO mirror_items (pid, ulid, media_type, title, duration_ms, '
          "sort_key) VALUES ('tr-A', 'A', 'music', 'Blue in Green', 337000, "
          "'blue in green');",
        );
        raw.userVersion = 1;
      },
    ),
  );
}

/// Every table's columns, as sqlite reports them: name, type, and
/// whether it is required. What a migration has to end up matching.
Future<Map<String, List<String>>> _columns(MirrorDatabase db) async {
  final tables = await db
      .customSelect(
        "select name from sqlite_master where type = 'table' "
        "and name not like 'sqlite_%' order by name",
      )
      .get();
  return {
    for (final t in tables)
      t.data['name'] as String: [
        for (final c
            in await db
                .customSelect('pragma table_info("${t.data['name']}")')
                .get())
          '${c.data['name']} ${c.data['type']} ${c.data['notnull']}',
      ],
  };
}

void main() {
  test('an upgraded schema is the schema a fresh install gets', () async {
    // The v1 statements below are transcribed, so they are only as
    // trustworthy as the transcription. This is what makes them
    // trustworthy: whatever they built, plus the migration, has to be
    // indistinguishable from what the current code creates from
    // nothing. A dropped column in either one shows up here.
    final upgraded = _upgradedFromV1();
    final fresh = inMemoryMirrorDatabase();
    addTearDown(upgraded.close);
    addTearDown(fresh.close);

    // Touch each database so the create and the upgrade both run.
    await upgraded.select(upgraded.mirrorItems).get();
    await fresh.select(fresh.mirrorItems).get();

    expect(await _columns(upgraded), await _columns(fresh));
  });

  test('v1 upgrades: rows survive, the new surfaces exist', () async {
    final db = _upgradedFromV1();
    addTearDown(db.close);

    // Any query drives the migration.
    final listens = await db.select(db.outboxListens).get();
    expect(listens, hasLength(1));
    expect(listens.single.pid, 'tr-A');
    // The added column reads null on rows written before it existed,
    // which is exactly what "nothing was trimmed" means on the wire.
    expect(listens.single.skippedMs, isNull);
    expect(await db.select(db.mirrorItems).get(), hasLength(1));

    expect(await db.select(db.queueEntries).get(), isEmpty);
    expect(await db.select(db.queueMeta).get(), isEmpty);
    expect(await db.select(db.artworkPins).get(), isEmpty);

    final version = await db.customSelect('pragma user_version').getSingle();
    expect(version.data.values.first, 2);
  });

  test('an upgraded database takes queue and artwork writes', () async {
    final db = _upgradedFromV1();
    addTearDown(db.close);

    await DriftQueueStore(db).save(
      StoredQueue(
        entries: const [
          StoredQueueEntry(queueId: 'q1', pid: 'tr-A', sourceRank: 0),
        ],
        currentIndex: 0,
        shuffled: false,
        repeat: 'off',
        sourceKind: 'album',
        sourceLabel: 'Kind of Blue',
        nextQueueId: 1,
        updatedAt: DateTime.utc(2026, 7, 25),
      ),
    );
    expect((await DriftQueueStore(db).load())!.entries.single.pid, 'tr-A');

    await db
        .into(db.artworkPins)
        .insert(
          ArtworkPinsCompanion.insert(
            pid: 'tr-A',
            sizePx: 256,
            artUrl: '/items/tr-A/art',
            etag: 'W/"1"',
            localPath: '/tmp/art/tr-A-256.jpg',
            sizeBytes: 9001,
            pinnedAt: DateTime.utc(2026, 7, 25),
          ),
        );
    expect(await db.select(db.artworkPins).get(), hasLength(1));
  });

  test('a queued listen keeps the time it saved', () async {
    final db = inMemoryMirrorDatabase();
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

    await engine.queueListen(
      ListenSession(
        sessionId: 'ls-9',
        pid: 'tr-A',
        startedAt: DateTime.utc(2026, 7, 25),
        msPlayed: 600000,
        skippedMs: 45000,
        finished: true,
        client: 'waxdeck-flutter-android',
      ),
    );
    expect((await db.select(db.outboxListens).getSingle()).skippedMs, 45000);

    await engine.flushOutbox();
    expect(repo.reportedSkippedMs['ls-9'], 45000);
  });
}
