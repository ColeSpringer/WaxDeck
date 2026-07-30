import 'package:drift/drift.dart';

part 'database.g.dart';

/// The catalog mirror: one row per item summary, the same shape the
/// sync endpoints deliver. The mirror mirrors the server's catalog
/// truth (missing items included); playability offline is a separate
/// question answered by the download records.
class MirrorItems extends Table {
  TextColumn get pid => text()();

  /// The bare ULID (the pid without its type prefix). Delete
  /// tombstones match on it, since a tombstone's prefix is not
  /// significant once the item is gone.
  TextColumn get ulid => text()();
  TextColumn get mediaType => text()();
  TextColumn get title => text()();
  TextColumn get artist => text().nullable()();
  TextColumn get album => text().nullable()();
  IntColumn get durationMs => integer()();

  /// Case-folded title for ordered offline browsing.
  TextColumn get sortKey => text()();

  @override
  Set<Column> get primaryKey => {pid};

  @override
  List<Set<Column>> get uniqueKeys => [
    {ulid},
  ];
}

/// The caller's own play states, fed by the server sync stream and by
/// optimistic local writes while offline.
class MirrorPlayStates extends Table {
  TextColumn get pid => text()();
  IntColumn get positionMs => integer().withDefault(const Constant(0))();
  BoolColumn get played => boolean().withDefault(const Constant(false))();
  BoolColumn get finished => boolean().withDefault(const Constant(false))();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
  BoolColumn get starred => boolean().withDefault(const Constant(false))();
  IntColumn get rating => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {pid};
}

/// The two opaque sync cursors; a single row.
class SyncCursors extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get catalogSince => text().nullable()();
  TextColumn get serverSince => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Queued offline mutations, replayed in insertion order on reconnect.
/// recordedAt rides the replay so the server reconciles per medium
/// instead of applying stale state blindly.
class OutboxMutations extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// `position`, `star`, or `rating`.
  TextColumn get kind => text()();
  TextColumn get pid => text()();
  IntColumn get positionMs => integer().nullable()();
  BoolColumn get starred => boolean().nullable()();

  /// The rating value for `rating` entries; null clears the rating.
  IntColumn get rating => integer().nullable()();
  DateTimeColumn get recordedAt => dateTime()();
}

/// Queued listen sessions. The session id is the idempotency key, so a
/// flush that races a retry can never double-count server-side.
class OutboxListens extends Table {
  TextColumn get sessionId => text()();
  TextColumn get pid => text()();
  DateTimeColumn get startedAt => dateTime()();
  IntColumn get msPlayed => integer()();
  BoolColumn get finished => boolean().withDefault(const Constant(false))();
  TextColumn get client => text().withDefault(const Constant(''))();

  /// Time the listener did not sit through (silence trimming, speed
  /// above 1x). Null when neither applied, matching the wire field.
  IntColumn get skippedMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {sessionId};
}

/// Downloaded originals, keyed by pid and file position. essenceHash is
/// the content key: a retag or move changes neither it nor the local
/// bytes, so neither forces a re-download.
class DownloadRecords extends Table {
  TextColumn get pid => text()();
  IntColumn get fileIndex => integer()();
  TextColumn get essenceHash => text()();
  TextColumn get etag => text()();
  TextColumn get fileName => text()();
  TextColumn get localPath => text()();
  IntColumn get sizeBytes => integer()();

  /// `pending` while the transfer runs, `complete` when the bytes are
  /// on disk.
  TextColumn get state => text()();
  IntColumn get spanStartMs => integer().nullable()();
  IntColumn get spanEndMs => integer().nullable()();

  /// This file's own duration, as download-info reported it. Null when
  /// the catalog did not know it, and on records written before the
  /// field existed. It is what places a book-timeline position in one
  /// part of a multi-file book with the server unreachable: a part's
  /// offset is the sum of the durations before it, so one missing value
  /// makes the whole item unsequenceable rather than slightly wrong.
  ///
  /// Last on purpose, like every other column a migration added:
  /// `ALTER TABLE ADD COLUMN` appends, so a column declared in the
  /// middle here would sit in a different position on an upgraded
  /// database than on a fresh one. The equivalence test in
  /// `schema_migration_test.dart` catches exactly that, and did.
  IntColumn get durationMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {pid, fileIndex};
}

/// The local play queue, one row per entry. Rows are the queue the
/// listener would see: [position] is the play order the queue screen
/// renders and the order a Connect load serializes to, [sourceRank] is
/// the order the queue was built in, which is what un-shuffling
/// restores. A pid may repeat (a playlist may name the same track
/// twice), so [queueId] is the identity; it is the in-memory queue's
/// own id, written through rather than minted here, and a save replaces
/// every row rather than working out which ones moved.
class QueueEntries extends Table {
  TextColumn get queueId => text()();
  TextColumn get pid => text()();
  IntColumn get position => integer()();
  IntColumn get sourceRank => integer()();

  @override
  Set<Column> get primaryKey => {queueId};
}

/// Everything about the persisted queue that is not an entry; a single
/// row. Positions are deliberately absent: the checkpointed play state
/// (server-side, mirrored locally) already answers where the current
/// item stands, and a second copy here could only disagree with it.
class QueueMeta extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  IntColumn get currentIndex => integer().withDefault(const Constant(0))();
  BoolColumn get shuffled => boolean().withDefault(const Constant(false))();

  /// `off`, `all`, or `one`, matching the Connect command vocabulary.
  TextColumn get repeat => text().withDefault(const Constant('off'))();

  /// Provenance: what the queue was built from, for the "Playing from
  /// [source]" line and the restore offer.
  TextColumn get sourceKind => text().withDefault(const Constant('unknown'))();
  TextColumn get sourceLabel => text().withDefault(const Constant(''))();
  TextColumn get sourcePid => text().nullable()();

  /// True for a window over a scope larger than the queue cap (shuffle
  /// all), which is refilled as it drains rather than being the whole
  /// truth.
  BoolColumn get sourceRolling =>
      boolean().withDefault(const Constant(false))();

  /// The next value the queue-id counter will mint, so a restored queue
  /// cannot hand an old id to a new entry.
  IntColumn get nextQueueId => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  /// Where the source's own listing stood when the window was cut, so a
  /// restored rolling queue can draw the next page instead of ending at
  /// the cap. Opaque: keyset cursors are the server's to shape, and the
  /// empty string means "no more was ever asked for".
  ///
  /// Read and written by [StoredQueue] already; what does not fill it
  /// yet is `QueueState.toStored`, since nothing on the queue side pages
  /// a source. That is the one remaining step, and it is a queue-UI one.
  ///
  /// Out of reading order, and deliberately: `ALTER TABLE ADD COLUMN`
  /// appends, so a column added after a table shipped goes last here too
  /// or an upgraded database and a fresh one differ in column order.
  /// (`skippedMs` on the listen outbox is the same, for the same
  /// reason.)
  TextColumn get sourceCursor => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Artwork kept on disk for offline use, one row per pid and size rung.
/// Written by the artwork store's pin path and read when the app is
/// offline; unpinned art is the HTTP cache's business, not this table's.
class ArtworkPins extends Table {
  TextColumn get pid => text()();
  IntColumn get sizePx => integer()();

  /// The art URL the bytes came from, so a revalidation asks for the
  /// same variant rather than whatever the item's front slot became.
  TextColumn get artUrl => text()();
  TextColumn get etag => text()();
  TextColumn get localPath => text()();
  IntColumn get sizeBytes => integer()();
  DateTimeColumn get pinnedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {pid, sizePx};
}

/// Per-device preferences, as opaque key/value pairs.
///
/// Deliberately not typed columns. The settings surface names ten of
/// these already and every phase adds more, and a typed column means a
/// schema migration per preference; the controller that reads a key is
/// the one place that knows what its value means, so that is where the
/// typing lives. Nothing synced belongs here — the server-side
/// preference document is a different store with a different scope.
class ClientSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// The client-side database behind the sync engine and downloads.
@DriftDatabase(
  tables: [
    MirrorItems,
    MirrorPlayStates,
    SyncCursors,
    OutboxMutations,
    OutboxListens,
    DownloadRecords,
    QueueEntries,
    QueueMeta,
    ArtworkPins,
    ClientSettings,
  ],
)
class MirrorDatabase extends _$MirrorDatabase {
  MirrorDatabase(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(outboxListens, outboxListens.skippedMs);
        await m.createTable(queueEntries);
        await m.createTable(queueMeta);
        await m.createTable(artworkPins);
      }
      if (from < 3) {
        await m.createTable(clientSettings);
        // Only for a database that already had the table. Guards are
        // cumulative, and `createTable` above builds today's shape, not
        // the shape v2 shipped — so a v1 install has just been given a
        // queue_meta that carries this column already, and adding it
        // again is a duplicate-column error rather than a no-op. Every
        // later step that adds a column to a table an earlier step
        // creates has to say which versions it means; the fresh-install
        // equivalence test is what catches forgetting to.
        if (from >= 2) {
          await m.addColumn(queueMeta, queueMeta.sourceCursor);
        }
      }
      if (from < 4) {
        // No version guard needed here, unlike the step above:
        // download_records is a v1 table, so every upgrade path arrives
        // with it already built and missing this column.
        await m.addColumn(downloadRecords, downloadRecords.durationMs);
      }
    },
  );
}
