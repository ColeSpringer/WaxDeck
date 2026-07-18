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

  @override
  Set<Column> get primaryKey => {pid, fileIndex};
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
  ],
)
class MirrorDatabase extends _$MirrorDatabase {
  MirrorDatabase(super.executor);

  @override
  int get schemaVersion => 1;
}
