import 'package:drift/drift.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'database.dart';

/// Offline listing over the local mirror, shaped like the server's item
/// pages so the library controller swaps sources without caring. The
/// cursor is a plain offset: the mirror is local, so keyset stability
/// against concurrent writers is not a concern.
const _mirrorCursorPrefix = 'mirror:';

bool isMirrorCursor(String cursor) => cursor.startsWith(_mirrorCursorPrefix);

Future<ItemPage> mirrorItemsPage(
  MirrorDatabase db, {
  MediaType? mediaType,
  String? cursor,
  int limit = 60,
}) async {
  var offset = 0;
  if (cursor != null && isMirrorCursor(cursor)) {
    offset = int.tryParse(cursor.substring(_mirrorCursorPrefix.length)) ?? 0;
  }
  final query = db.select(db.mirrorItems)
    ..orderBy([
      (t) => OrderingTerm.asc(t.sortKey),
      (t) => OrderingTerm.asc(t.pid),
    ])
    ..limit(limit + 1, offset: offset);
  if (mediaType != null) {
    query.where((t) => t.mediaType.equals(mediaType.wireName));
  }
  final rows = await query.get();
  final hasMore = rows.length > limit;
  final page = rows.take(limit).toList();
  return ItemPage(
    items: [
      for (final r in page)
        ItemSummary(
          pid: r.pid,
          mediaType: MediaType.values.firstWhere(
            (m) => m.wireName == r.mediaType,
            orElse: () => MediaType.music,
          ),
          title: r.title,
          artist: r.artist,
          album: r.album,
          durationMs: r.durationMs,
          // No artUrl offline: the grid's placeholder renders instead of
          // a dead request.
        ),
    ],
    nextCursor: hasMore ? '$_mirrorCursorPrefix${offset + limit}' : null,
  );
}

/// Pids with a completed download, newest first. Feeds the Auto browse
/// tree's Downloads folder; join back through the mirror for titles.
Future<List<String>> mirrorDownloadedPids(
  MirrorDatabase db, {
  int limit = 200,
}) async {
  final rows =
      await (db.select(db.downloadRecords)
            ..where((t) => t.state.equals('complete'))
            ..limit(limit))
          .get();
  final seen = <String>{};
  return [
    for (final r in rows)
      if (seen.add(r.pid)) r.pid,
  ];
}

/// Pids with listening progress (a position past the start, not yet
/// finished), most recently updated first. Feeds the Auto browse
/// tree's Continue folder.
Future<List<String>> mirrorInProgressPids(
  MirrorDatabase db, {
  int limit = 50,
}) async {
  final rows =
      await (db.select(db.mirrorPlayStates)
            ..where((t) => t.positionMs.isBiggerThanValue(0))
            ..where((t) => t.finished.equals(false))
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
            ..limit(limit))
          .get();
  return [for (final r in rows) r.pid];
}

/// One mirror row by pid, for hydrating id lists into entries.
Future<ItemSummary?> mirrorItemByPid(MirrorDatabase db, String pid) async {
  final row = await (db.select(
    db.mirrorItems,
  )..where((t) => t.pid.equals(pid))).getSingleOrNull();
  if (row == null) return null;
  return ItemSummary(
    pid: row.pid,
    mediaType: MediaType.values.firstWhere(
      (m) => m.wireName == row.mediaType,
      orElse: () => MediaType.music,
    ),
    title: row.title,
    artist: row.artist,
    album: row.album,
    durationMs: row.durationMs,
  );
}
