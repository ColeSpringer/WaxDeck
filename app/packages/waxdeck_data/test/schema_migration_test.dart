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

/// The schema as v2 shipped it, again verbatim from that version's
/// generated DDL. v1 is kept beside it rather than replaced: an install
/// that skipped a release upgrades in one step, and that is the path
/// with two migration steps running back to back.
const _v2Schema = [
  'CREATE TABLE "artwork_pins" ("pid" TEXT NOT NULL, '
      '"size_px" INTEGER NOT NULL, "art_url" TEXT NOT NULL, '
      '"etag" TEXT NOT NULL, "local_path" TEXT NOT NULL, '
      '"size_bytes" INTEGER NOT NULL, "pinned_at" INTEGER NOT NULL, '
      'PRIMARY KEY ("pid", "size_px"));',
  'CREATE TABLE "download_records" ("pid" TEXT NOT NULL, '
      '"file_index" INTEGER NOT NULL, "essence_hash" TEXT NOT NULL, '
      '"etag" TEXT NOT NULL, "file_name" TEXT NOT NULL, '
      '"local_path" TEXT NOT NULL, "size_bytes" INTEGER NOT NULL, '
      '"state" TEXT NOT NULL, "span_start_ms" INTEGER NULL, '
      '"span_end_ms" INTEGER NULL, PRIMARY KEY ("pid", "file_index"));',
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
  'CREATE TABLE "outbox_listens" ("session_id" TEXT NOT NULL, '
      '"pid" TEXT NOT NULL, "started_at" INTEGER NOT NULL, '
      '"ms_played" INTEGER NOT NULL, '
      '"finished" INTEGER NOT NULL DEFAULT 0 CHECK ("finished" IN (0, 1)), '
      '"client" TEXT NOT NULL DEFAULT \'\', "skipped_ms" INTEGER NULL, '
      'PRIMARY KEY ("session_id"));',
  'CREATE TABLE "outbox_mutations" ("id" INTEGER NOT NULL PRIMARY KEY '
      'AUTOINCREMENT, "kind" TEXT NOT NULL, "pid" TEXT NOT NULL, '
      '"position_ms" INTEGER NULL, '
      '"starred" INTEGER NULL CHECK ("starred" IN (0, 1)), '
      '"rating" INTEGER NULL, "recorded_at" INTEGER NOT NULL);',
  'CREATE TABLE "queue_entries" ("queue_id" TEXT NOT NULL, '
      '"pid" TEXT NOT NULL, "position" INTEGER NOT NULL, '
      '"source_rank" INTEGER NOT NULL, PRIMARY KEY ("queue_id"));',
  'CREATE TABLE "queue_meta" ("id" INTEGER NOT NULL DEFAULT 1, '
      '"current_index" INTEGER NOT NULL DEFAULT 0, '
      '"shuffled" INTEGER NOT NULL DEFAULT 0 CHECK ("shuffled" IN (0, 1)), '
      '"repeat" TEXT NOT NULL DEFAULT \'off\', '
      '"source_kind" TEXT NOT NULL DEFAULT \'unknown\', '
      '"source_label" TEXT NOT NULL DEFAULT \'\', "source_pid" TEXT NULL, '
      '"source_rolling" INTEGER NOT NULL DEFAULT 0 '
      'CHECK ("source_rolling" IN (0, 1)), '
      '"next_queue_id" INTEGER NOT NULL DEFAULT 0, '
      '"updated_at" INTEGER NOT NULL, PRIMARY KEY ("id"));',
  'CREATE TABLE "sync_cursors" ("id" INTEGER NOT NULL DEFAULT 1, '
      '"catalog_since" TEXT NULL, "server_since" TEXT NULL, PRIMARY KEY ("id"));',
];

/// The schema as v3 shipped it. The only version where download_records
/// carries no per-file duration while everything else is current, which
/// is the path v4's one-column step actually runs on.
const _v3Schema = [
  'CREATE TABLE "artwork_pins" ("pid" TEXT NOT NULL, '
      '"size_px" INTEGER NOT NULL, "art_url" TEXT NOT NULL, '
      '"etag" TEXT NOT NULL, "local_path" TEXT NOT NULL, '
      '"size_bytes" INTEGER NOT NULL, "pinned_at" INTEGER NOT NULL, '
      'PRIMARY KEY ("pid", "size_px"));',
  'CREATE TABLE "client_settings" ("key" TEXT NOT NULL, '
      '"value" TEXT NOT NULL, PRIMARY KEY ("key"));',
  'CREATE TABLE "download_records" ("pid" TEXT NOT NULL, '
      '"file_index" INTEGER NOT NULL, "essence_hash" TEXT NOT NULL, '
      '"etag" TEXT NOT NULL, "file_name" TEXT NOT NULL, '
      '"local_path" TEXT NOT NULL, "size_bytes" INTEGER NOT NULL, '
      '"state" TEXT NOT NULL, "span_start_ms" INTEGER NULL, '
      '"span_end_ms" INTEGER NULL, PRIMARY KEY ("pid", "file_index"));',
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
  'CREATE TABLE "outbox_listens" ("session_id" TEXT NOT NULL, '
      '"pid" TEXT NOT NULL, "started_at" INTEGER NOT NULL, '
      '"ms_played" INTEGER NOT NULL, '
      '"finished" INTEGER NOT NULL DEFAULT 0 CHECK ("finished" IN (0, 1)), '
      '"client" TEXT NOT NULL DEFAULT \'\', "skipped_ms" INTEGER NULL, '
      'PRIMARY KEY ("session_id"));',
  'CREATE TABLE "outbox_mutations" ("id" INTEGER NOT NULL PRIMARY KEY '
      'AUTOINCREMENT, "kind" TEXT NOT NULL, "pid" TEXT NOT NULL, '
      '"position_ms" INTEGER NULL, '
      '"starred" INTEGER NULL CHECK ("starred" IN (0, 1)), '
      '"rating" INTEGER NULL, "recorded_at" INTEGER NOT NULL);',
  'CREATE TABLE "queue_entries" ("queue_id" TEXT NOT NULL, '
      '"pid" TEXT NOT NULL, "position" INTEGER NOT NULL, '
      '"source_rank" INTEGER NOT NULL, PRIMARY KEY ("queue_id"));',
  'CREATE TABLE "queue_meta" ("id" INTEGER NOT NULL DEFAULT 1, '
      '"current_index" INTEGER NOT NULL DEFAULT 0, '
      '"shuffled" INTEGER NOT NULL DEFAULT 0 CHECK ("shuffled" IN (0, 1)), '
      '"repeat" TEXT NOT NULL DEFAULT \'off\', '
      '"source_kind" TEXT NOT NULL DEFAULT \'unknown\', '
      '"source_label" TEXT NOT NULL DEFAULT \'\', "source_pid" TEXT NULL, '
      '"source_rolling" INTEGER NOT NULL DEFAULT 0 '
      'CHECK ("source_rolling" IN (0, 1)), '
      '"next_queue_id" INTEGER NOT NULL DEFAULT 0, '
      '"updated_at" INTEGER NOT NULL, '
      '"source_cursor" TEXT NOT NULL DEFAULT \'\', PRIMARY KEY ("id"));',
  'CREATE TABLE "sync_cursors" ("id" INTEGER NOT NULL DEFAULT 1, '
      '"catalog_since" TEXT NULL, "server_since" TEXT NULL, PRIMARY KEY ("id"));',
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

/// The same, for a v2 install: a saved queue and a pinned cover already
/// on disk, since v2 is the first version that had them to lose.
MirrorDatabase _upgradedFromV2() {
  return MirrorDatabase(
    NativeDatabase.memory(
      setup: (raw) {
        for (final statement in _v2Schema) {
          raw.execute(statement);
        }
        raw.execute(
          'INSERT INTO queue_entries (queue_id, pid, position, source_rank) '
          "VALUES ('q1', 'tr-A', 0, 0);",
        );
        raw.execute(
          'INSERT INTO queue_meta (id, current_index, shuffled, repeat, '
          'source_kind, source_label, source_rolling, next_queue_id, '
          "updated_at) VALUES (1, 0, 0, 'off', 'album', 'Kind of Blue', 0, 1, "
          '1753401600);',
        );
        raw.execute(
          'INSERT INTO artwork_pins (pid, size_px, art_url, etag, local_path, '
          "size_bytes, pinned_at) VALUES ('tr-A', 256, '/items/tr-A/art', "
          "'W/\"1\"', '/tmp/art/tr-A-256.jpg', 9001, 1753401600);",
        );
        raw.userVersion = 2;
      },
    ),
  );
}

/// The same, for a v3 install: a downloaded multi-part book already on
/// disk, whose records carry no per-file durations because v3 had none.
MirrorDatabase _upgradedFromV3() {
  return MirrorDatabase(
    NativeDatabase.memory(
      setup: (raw) {
        for (final statement in _v3Schema) {
          raw.execute(statement);
        }
        for (var i = 0; i < 2; i++) {
          raw.execute(
            'INSERT INTO download_records (pid, file_index, essence_hash, '
            'etag, file_name, local_path, size_bytes, state) VALUES '
            "('bk-A', $i, 'ess$i', '9-9', 'part$i.m4b', "
            "'/tmp/media/ess$i.m4b', 4194304, 'complete');",
          );
        }
        raw.userVersion = 3;
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
    final fromV2 = _upgradedFromV2();
    final fromV3 = _upgradedFromV3();
    final fresh = inMemoryMirrorDatabase();
    addTearDown(upgraded.close);
    addTearDown(fromV2.close);
    addTearDown(fromV3.close);
    addTearDown(fresh.close);

    // Touch each database so the create and the upgrade both run.
    await upgraded.select(upgraded.mirrorItems).get();
    await fromV2.select(fromV2.mirrorItems).get();
    await fromV3.select(fromV3.mirrorItems).get();
    await fresh.select(fresh.mirrorItems).get();

    final target = await _columns(fresh);
    expect(await _columns(upgraded), target);
    // Every supported starting point converges on the same schema, so
    // an install that skipped a version is not a shape of its own.
    expect(await _columns(fromV2), target);
    expect(await _columns(fromV3), target);
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
    expect(await db.select(db.clientSettings).get(), isEmpty);

    final version = await db.customSelect('pragma user_version').getSingle();
    expect(version.data.values.first, db.schemaVersion);
  });

  test('v3 upgrades: downloaded parts survive without durations', () async {
    final db = _upgradedFromV3();
    addTearDown(db.close);

    // The bytes a v3 install already fetched are what an upgrade must
    // not cost it, and the added column reads null on them - which is
    // what makes the book unsequenceable rather than misplaced. Asking
    // for it again is what fills them in.
    final records = await db.select(db.downloadRecords).get();
    expect(records, hasLength(2));
    expect(records.map((r) => r.durationMs), everyElement(isNull));
    expect(records.first.localPath, '/tmp/media/ess0.m4b');

    final version = await db.customSelect('pragma user_version').getSingle();
    expect(version.data.values.first, db.schemaVersion);
  });

  test('v2 upgrades: the queue survives and gains its cursor', () async {
    final db = _upgradedFromV2();
    addTearDown(db.close);

    // The rows a v2 install had are the ones an upgrade must not cost
    // it: the saved queue is what the next launch offers to resume.
    final restored = await DriftQueueStore(db).load();
    expect(restored!.entries.single.pid, 'tr-A');
    expect(restored.sourceLabel, 'Kind of Blue');
    expect(await db.select(db.artworkPins).get(), hasLength(1));

    // The added column reads as its default on a row written before it
    // existed, which is the honest answer: nothing was ever paged.
    expect((await db.select(db.queueMeta).getSingle()).sourceCursor, isEmpty);
    expect(await db.select(db.clientSettings).get(), isEmpty);

    final version = await db.customSelect('pragma user_version').getSingle();
    expect(version.data.values.first, db.schemaVersion);
  });

  test('an upgraded database holds per-device settings', () async {
    for (final db in [_upgradedFromV1(), _upgradedFromV2()]) {
      addTearDown(db.close);
      final store = DriftClientSettingsStore(db);

      expect(await store.read(ClientSettingKeys.sidebarCollapsed), isNull);
      await store.write(ClientSettingKeys.sidebarCollapsed, 'true');
      expect(await store.read(ClientSettingKeys.sidebarCollapsed), 'true');
    }
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
