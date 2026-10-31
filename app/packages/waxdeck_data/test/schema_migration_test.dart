import 'package:drift/drift.dart' show driftRuntimeOptions;
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

/// The schema as v5 shipped it, verbatim from that version's generated
/// DDL: every table current but the outbox, which carries no payload
/// column yet. The path v6's one-column step runs on.
const _v5Schema = [
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
      '"span_end_ms" INTEGER NULL, "duration_ms" INTEGER NULL, '
      'PRIMARY KEY ("pid", "file_index"));',
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
      '"rating" INTEGER NULL, "updated_at" INTEGER NULL, '
      '"last_played_at" INTEGER NULL, PRIMARY KEY ("pid"));',
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

/// The schema as v6 shipped it: v5's, with the outbox's payload column
/// appended the way its migration appends it. The path v7 runs on.
final _v6Schema = [
  for (final statement in _v5Schema)
    statement.replaceFirst(
      '"recorded_at" INTEGER NOT NULL);',
      '"recorded_at" INTEGER NOT NULL, "payload" TEXT NULL);',
    ),
];

/// The schema as v7 shipped it: v6's with the account stamp on the
/// cursor, the owner on both outboxes, and the bookmark table, as their
/// migration builds them. The path v8 runs on, and no table differs
/// between the two: what v8 changes is what a mirror row's key means.
final _v7Schema = [
  for (final statement in _v6Schema)
    statement
        .replaceFirst(
          '"server_since" TEXT NULL, PRIMARY KEY ("id"));',
          '"server_since" TEXT NULL, "server_account" TEXT NULL, '
              'PRIMARY KEY ("id"));',
        )
        .replaceFirst(
          '"payload" TEXT NULL);',
          '"payload" TEXT NULL, "owner" TEXT NULL);',
        )
        .replaceFirst(
          '"skipped_ms" INTEGER NULL, PRIMARY KEY ("session_id"));',
          '"skipped_ms" INTEGER NULL, "owner" TEXT NULL, '
              'PRIMARY KEY ("session_id"));',
        ),
  'CREATE TABLE "mirror_bookmarks" ("id" TEXT NOT NULL, '
      '"owner" TEXT NOT NULL, "book_pid" TEXT NOT NULL, '
      '"position_ms" INTEGER NOT NULL, "note" TEXT NULL, '
      '"created_at" INTEGER NOT NULL, "sync_state" TEXT NOT NULL, '
      '"refusal" TEXT NULL, "refusal_code" TEXT NULL, PRIMARY KEY ("id"));',
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
/// disk, whose records carry no per-file durations because v3 had none,
/// and a cursor pair, which is what an install that skipped the releases
/// since still has to have its catalog half cleared.
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
        raw.execute(
          'INSERT INTO sync_cursors (id, catalog_since, server_since) '
          "VALUES (1, 'cur-1', 'scur-1');",
        );
        raw.userVersion = 3;
      },
    ),
  );
}

/// The same, for a v5 install: a star queued offline and not yet sent,
/// which is what the outbox's new column must not cost.
MirrorDatabase _upgradedFromV5() {
  return MirrorDatabase(
    NativeDatabase.memory(
      setup: (raw) {
        for (final statement in _v5Schema) {
          raw.execute(statement);
        }
        raw.execute(
          'INSERT INTO outbox_mutations (kind, pid, starred, recorded_at) '
          "VALUES ('star', 'tr-A', 1, 1758931200);",
        );
        raw.userVersion = 5;
      },
    ),
  );
}

/// The same, for a v6 install: a preference patch queued offline, which
/// the bookmark table's arrival must not cost.
MirrorDatabase _upgradedFromV6() {
  return MirrorDatabase(
    NativeDatabase.memory(
      setup: (raw) {
        for (final statement in _v6Schema) {
          raw.execute(statement);
        }
        raw.execute(
          'INSERT INTO outbox_mutations (kind, pid, recorded_at, payload) '
          "VALUES ('prefs', 'us-1', 1758931200, '{\"locale\":\"es\"}');",
        );
        raw.userVersion = 6;
      },
    ),
  );
}

/// The same, for a v7 install: a mirror filed under bare lowercase titles
/// beside everything else the device keeps for its user (a download, a
/// play state, a queued star and listen, a bookmark, a saved queue, a
/// setting), none of which the move to the catalog's keys may cost.
MirrorDatabase _upgradedFromV7() {
  return MirrorDatabase(
    NativeDatabase.memory(
      setup: (raw) {
        for (final statement in _v7Schema) {
          raw.execute(statement);
        }
        raw.execute(
          'INSERT INTO mirror_items (pid, ulid, media_type, title, duration_ms, '
          "sort_key) VALUES ('tr-Z', 'Z', 'music', 'The Zebra Song', 1000, "
          "'the zebra song'), ('tr-A', 'A', 'music', 'apple tune', 1000, "
          "'apple tune');",
        );
        raw.execute(
          'INSERT INTO sync_cursors (id, catalog_since, server_since, '
          "server_account) VALUES (1, 'cur-7', 'scur-7', 'us-1');",
        );
        raw.execute(
          'INSERT INTO download_records (pid, file_index, essence_hash, etag, '
          'file_name, local_path, size_bytes, state, duration_ms) VALUES '
          "('tr-Z', 0, 'ess', '1-1', 'zebra.flac', '/tmp/media/ess.flac', "
          "4096, 'complete', 1000);",
        );
        raw.execute(
          'INSERT INTO mirror_play_states (pid, position_ms, starred) '
          "VALUES ('tr-Z', 1234, 1);",
        );
        raw.execute(
          'INSERT INTO outbox_mutations (kind, pid, starred, recorded_at, '
          "owner) VALUES ('star', 'tr-A', 1, 1758931200, 'us-1');",
        );
        raw.execute(
          'INSERT INTO outbox_listens (session_id, pid, started_at, ms_played, '
          'finished, client, skipped_ms, owner) VALUES ('
          "'ls-7', 'tr-Z', 1700000000, 42000, 1, 'waxdeck-flutter-android', "
          "3000, 'us-1');",
        );
        raw.execute(
          'INSERT INTO mirror_bookmarks (id, owner, book_pid, position_ms, '
          'note, created_at, sync_state) VALUES ('
          "'bm-7', 'us-1', 'bk-A', 61000, 'the good part', 1758931200, "
          "'pending');",
        );
        raw.execute(
          'INSERT INTO queue_entries (queue_id, pid, position, source_rank) '
          "VALUES ('q1', 'tr-Z', 0, 0);",
        );
        raw.execute(
          'INSERT INTO client_settings (key, value) VALUES '
          "('${ClientSettingKeys.sidebarCollapsed}', 'true');",
        );
        raw.userVersion = 7;
      },
    ),
  );
}

/// The same, for a v8 install, whose tables are v7's: a download from
/// before the device kept where one came from.
MirrorDatabase _upgradedFromV8() {
  return MirrorDatabase(
    NativeDatabase.memory(
      setup: (raw) {
        for (final statement in _v7Schema) {
          raw.execute(statement);
        }
        raw.execute(
          'INSERT INTO download_records (pid, file_index, essence_hash, etag, '
          'file_name, local_path, size_bytes, state, duration_ms) VALUES '
          "('tr-Z', 0, 'ess', '1-1', 'zebra.flac', '/tmp/media/ess.flac', "
          "4096, 'complete', 1000);",
        );
        raw.execute(
          'INSERT INTO sync_cursors (id, catalog_since, server_since, '
          "server_account) VALUES (1, 'cur-8', 'scur-8', 'us-1');",
        );
        raw.userVersion = 8;
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

/// A server whose catalog has not changed since the device last looked:
/// it has no delta to send, and answers a snapshot with [snapshot].
class _CatalogByKind extends ScriptedRepository {
  CatalogSyncPage snapshot = const CatalogSyncPage(nextSince: 'cur-0');
  final deltaCalls = <String>[];

  @override
  Future<CatalogSyncPage> syncCatalog({
    String? since,
    String? cursor,
    int? limit,
  }) async {
    if (since == null) return snapshot;
    deltaCalls.add(since);
    return CatalogSyncPage(nextSince: since);
  }
}

void main() {
  test('an upgraded schema is the schema a fresh install gets', () async {
    // The v1 statements below are transcribed, so they are only as
    // trustworthy as the transcription. This is what makes them
    // trustworthy: whatever they built, plus the migration, has to be
    // indistinguishable from what the current code creates from
    // nothing. A dropped column in either one shows up here.
    final fresh = inMemoryMirrorDatabase();
    final Map<String, List<String>> target;
    try {
      // Touch it so the create runs.
      await fresh.select(fresh.mirrorItems).get();
      target = await _columns(fresh);
    } finally {
      await fresh.close();
    }

    // Every supported starting point converges on the same schema, so
    // an install that skipped a version is not a shape of its own. One
    // at a time: the comparison needs no two open together.
    for (final (label, open) in [
      ('v1', _upgradedFromV1),
      ('v2', _upgradedFromV2),
      ('v3', _upgradedFromV3),
      ('v5', _upgradedFromV5),
      ('v6', _upgradedFromV6),
      ('v7', _upgradedFromV7),
      ('v8', _upgradedFromV8),
    ]) {
      final upgraded = open();
      try {
        // Touch it so the upgrade runs.
        await upgraded.select(upgraded.mirrorItems).get();
        expect(
          await _columns(upgraded),
          target,
          reason: 'an install upgraded from $label',
        );
      } finally {
        await upgraded.close();
      }
    }
  });

  test('two mirrors open at once still warn after the schema comparison', () {
    // A test that flags drift's multiple-database check off skews its
    // count for the rest of the file, which blinds the check without a
    // sound; this fails if any test above does that.
    final warnings = <String>[];
    final printed = driftRuntimeOptions.debugPrint;
    driftRuntimeOptions.debugPrint = warnings.add;
    addTearDown(() => driftRuntimeOptions.debugPrint = printed);
    final first = inMemoryMirrorDatabase();
    final second = inMemoryMirrorDatabase();
    addTearDown(first.close);
    addTearDown(second.close);

    expect(warnings, hasLength(1));
  });

  test(
    'v7 upgrades: what the device keeps stays, the mirror is asked for again',
    () async {
      final db = _upgradedFromV7();
      addTearDown(db.close);

      // The one thing cleared is the cursor that said the mirror was caught
      // up, so the next sync snapshots it afresh; the account's own cursor
      // stays where it was.
      final cursors = await db.select(db.syncCursors).getSingle();
      expect(cursors.catalogSince, isNull);
      expect(cursors.serverSince, 'scur-7');
      expect(cursors.serverAccount, 'us-1');

      // Everything else the device holds for its user is untouched.
      expect(
        (await db.select(db.downloadRecords).getSingle()).localPath,
        '/tmp/media/ess.flac',
      );
      expect(
        (await db.select(db.mirrorPlayStates).getSingle()).positionMs,
        1234,
      );
      expect((await db.select(db.outboxMutations).getSingle()).kind, 'star');
      final listen = await db.select(db.outboxListens).getSingle();
      expect(
        (listen.sessionId, listen.msPlayed, listen.skippedMs),
        ('ls-7', 42000, 3000),
      );
      final mark = await db.select(db.mirrorBookmarks).getSingle();
      expect(
        (mark.id, mark.positionMs, mark.note, mark.syncState),
        ('bm-7', 61000, 'the good part', 'pending'),
      );
      expect((await db.select(db.queueEntries).getSingle()).pid, 'tr-Z');
      expect(
        await DriftClientSettingsStore(
          db,
        ).read(ClientSettingKeys.sidebarCollapsed),
        'true',
      );
      // The mirror waits for that snapshot, rows and all, and no row is
      // filed under a new key beside the old ones before it comes.
      expect(
        (await db.select(db.mirrorItems).get()).map((r) => r.sortKey),
        unorderedEquals(['the zebra song', 'apple tune']),
      );

      final version = await db.customSelect('pragma user_version').getSingle();
      expect(version.data.values.first, db.schemaVersion);
    },
  );

  test(
    'the first sync after a v7 upgrade files every row under the catalog key',
    () async {
      final db = _upgradedFromV7();
      final repo = _CatalogByKind();
      final engine = SyncEngine(
        db: db,
        repository: repo,
        channelFactory: neverConnects(),
      );
      addTearDown(() async {
        engine.dispose();
        await db.close();
      });
      repo.snapshot = CatalogSyncPage(
        entries: [
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-Z',
            item: repo.item('tr-Z', 'The Zebra Song', sortKey: 'zebra song'),
          ),
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-A',
            item: repo.item('tr-A', 'apple tune', sortKey: 'apple tune'),
          ),
        ],
        nextSince: 'cur-8',
      );

      await engine.pullCatalog();

      // The server has no delta to send: nothing changed since the device
      // last looked. The upgrade is what asks it for the whole catalog, so
      // no bare lowercase title is left to sort beside a catalog key.
      expect(repo.deltaCalls, isEmpty);
      final page = await mirrorItemsPage(db);
      expect(page.items.map((i) => (i.pid, i.sortKey)), [
        ('tr-A', 'apple tune'),
        ('tr-Z', 'zebra song'),
      ]);
      expect(
        (await db.select(db.syncCursors).getSingle()).catalogSince,
        'cur-8',
      );
      // And the device's own rows were not part of it.
      expect(await db.select(db.downloadRecords).get(), hasLength(1));
      expect(await db.select(db.mirrorPlayStates).get(), hasLength(1));
      expect(await db.select(db.outboxMutations).get(), hasLength(1));
      expect(await db.select(db.queueEntries).get(), hasLength(1));
    },
  );

  test(
    'v8 upgrades: a download stands, naming no server, and the mirror stays',
    () async {
      final db = _upgradedFromV8();
      addTearDown(db.close);

      final row = await db.select(db.downloadRecords).getSingle();
      expect(
        (row.pid, row.localPath, row.server),
        ('tr-Z', '/tmp/media/ess.flac', null),
      );
      expect(
        (await db.select(db.syncCursors).getSingle()).catalogSince,
        'cur-8',
      );
      final version = await db.customSelect('pragma user_version').getSingle();
      expect(version.data.values.first, db.schemaVersion);
    },
  );

  test(
    'the first sync after an upgrade keeps the downloads it cannot place',
    () async {
      // The upgrade sends every install through a full re-mirror, which
      // carries no tombstones. A download from before the device kept
      // where one came from may be another server's, so it is asked about
      // by no server; one the snapshot lists is this server's from then
      // on, and a later re-mirror asks after it once it is gone.
      final db = _upgradedFromV7();
      final repo = _CatalogByKind();
      final engine = SyncEngine(
        db: db,
        repository: repo,
        channelFactory: neverConnects(),
      );
      addTearDown(() async {
        engine.dispose();
        await db.close();
      });
      for (final pid in ['tr-GONE', 'tr-TRASH']) {
        await db
            .into(db.downloadRecords)
            .insert(
              DownloadRecordsCompanion.insert(
                pid: pid,
                fileIndex: 0,
                essenceHash: pid,
                etag: '1-1',
                fileName: '$pid.flac',
                localPath: '/tmp/media/$pid.flac',
                sizeBytes: 4096,
                state: 'complete',
              ),
            );
      }
      repo.removedForGood.addAll(['tr-GONE', 'tr-Z']);
      repo.snapshot = CatalogSyncPage(
        entries: [
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-Z',
            item: repo.item('tr-Z', 'The Zebra Song', sortKey: 'zebra song'),
          ),
        ],
        nextSince: 'cur-8',
      );
      final reclaimed = <String>[];
      final sub = engine.itemsRemoved.listen(reclaimed.add);
      addTearDown(sub.cancel);

      await engine.pullCatalog();
      await pumpEventQueue();

      expect(repo.removedAsked, isEmpty);
      expect(reclaimed, isEmpty);
      expect(
        {
          for (final r in await db.select(db.downloadRecords).get())
            r.pid: r.server,
        },
        {'tr-Z': repo.baseUrl, 'tr-GONE': null, 'tr-TRASH': null},
      );

      // The zebra song deleted outright while the device was away.
      repo.snapshot = const CatalogSyncPage(nextSince: 'cur-9');
      await engine.resyncCatalog();
      await pumpEventQueue();

      expect(repo.removedAsked, [
        ['tr-Z'],
      ]);
      expect(reclaimed, ['tr-Z']);
    },
  );

  test('v6 upgrades: a queued patch survives, bookmarks can be held', () async {
    final db = _upgradedFromV6();
    addTearDown(db.close);

    final queued = await db.select(db.outboxMutations).getSingle();
    expect(queued.kind, 'prefs');
    expect(queued.payload, '{"locale":"es"}');
    expect(await db.select(db.mirrorBookmarks).get(), isEmpty);

    final version = await db.customSelect('pragma user_version').getSingle();
    expect(version.data.values.first, db.schemaVersion);
  });

  test('v5 upgrades: a queued mutation survives with no payload', () async {
    final db = _upgradedFromV5();
    addTearDown(db.close);

    final queued = await db.select(db.outboxMutations).getSingle();
    expect(queued.kind, 'star');
    expect(queued.pid, 'tr-A');
    expect(queued.starred, isTrue);
    expect(queued.payload, isNull);

    final version = await db.customSelect('pragma user_version').getSingle();
    expect(version.data.values.first, db.schemaVersion);
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

    // Skipping versions still runs the last step: the catalog cursor is
    // cleared so the mirror is asked for again, the account's is kept.
    final cursors = await db.select(db.syncCursors).getSingle();
    expect(cursors.catalogSince, isNull);
    expect(cursors.serverSince, 'scur-1');

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
    for (final open in [_upgradedFromV1, _upgradedFromV2]) {
      final db = open();
      try {
        final store = DriftClientSettingsStore(db);

        expect(await store.read(ClientSettingKeys.sidebarCollapsed), isNull);
        await store.write(ClientSettingKeys.sidebarCollapsed, 'true');
        expect(await store.read(ClientSettingKeys.sidebarCollapsed), 'true');
      } finally {
        await db.close();
      }
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
