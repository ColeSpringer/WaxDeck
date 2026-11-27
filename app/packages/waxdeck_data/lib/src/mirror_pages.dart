import 'package:drift/drift.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'database.dart';

/// Offline listing over the local mirror, shaped like the server's item
/// pages so the library controller swaps sources without caring. The
/// cursor is a plain offset: the mirror is local, so keyset stability
/// against concurrent writers is not a concern.
const _mirrorCursorPrefix = 'mirror:';

bool isMirrorCursor(String cursor) => cursor.startsWith(_mirrorCursorPrefix);

/// One page of the mirror's items. [artUrlFor] mints the art URL of an
/// item whose cover is pinned on disk; left out, by a reader that draws
/// nothing, no summary carries one.
Future<ItemPage> mirrorItemsPage(
  MirrorDatabase db, {
  MediaType? mediaType,
  String? cursor,
  int limit = 60,
  String Function(String pid)? artUrlFor,
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
  return ItemPage(
    items: await _summaries(db, rows.take(limit).toList(), artUrlFor),
    nextCursor: hasMore ? '$_mirrorCursorPrefix${offset + limit}' : null,
  );
}

/// [rows] as summaries. Given [artUrlFor], each carries the art URL of
/// the cover pinned for it on disk, and none where nothing is: a
/// placeholder rather than a request that may have nobody to answer it.
/// The URL is minted for the row's own pid at the server's address now,
/// not read off the pin: a pin keeps the URL its bytes came from, which
/// names the old pid after a kind change and the old host after the
/// server moved, and the store finds a pin by its pid alone.
Future<List<ItemSummary>> _summaries(
  MirrorDatabase db,
  List<MirrorItem> rows,
  String Function(String pid)? artUrlFor,
) async {
  if (rows.isEmpty) return const <ItemSummary>[];
  final pinned = <String>{};
  if (artUrlFor != null) {
    final t = db.artworkPins;
    final held = db.selectOnly(t, distinct: true)
      ..addColumns([t.pid])
      ..where(t.pid.isIn([for (final r in rows) r.pid]));
    pinned.addAll([for (final row in await held.get()) row.read(t.pid)!]);
  }
  return [
    for (final r in rows)
      ItemSummary(
        pid: r.pid,
        mediaType: MediaType.values.firstWhere(
          (m) => m.wireName == r.mediaType,
          orElse: () => MediaType.music,
        ),
        title: r.title,
        artist: r.artist,
        album: r.album,
        sortKey: r.sortKey,
        durationMs: r.durationMs,
        artUrl: artUrlFor != null && pinned.contains(r.pid)
            ? artUrlFor(r.pid)
            : null,
      ),
  ];
}

/// Pids of items with every file on disk, newest first. Feeds the Auto
/// browse tree's Downloads folder; join back through the mirror for
/// titles.
Future<List<String>> mirrorDownloadedPids(
  MirrorDatabase db, {
  int limit = 200,
}) async {
  final t = db.downloadRecords;
  final whole =
      t.state.min().equals('complete') & t.state.max().equals('complete');
  final query = db.selectOnly(t)
    ..addColumns([t.pid])
    ..groupBy([t.pid], having: whole)
    ..orderBy([OrderingTerm.desc(t.rowId.max())])
    ..limit(limit);
  return [for (final row in await query.get()) row.read(t.pid)!];
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

/// The pid the mirror holds for [pid]'s item when that is another one.
/// A kind change gives an item a new prefix on the same ULID, and what
/// was built before it (a saved queue, a summary read earlier) still
/// names the old pid. Null when the mirror holds [pid] itself, or
/// nothing under its ULID.
Future<String?> mirrorRenamedPid(MirrorDatabase db, String pid) async {
  final t = db.mirrorItems;
  final row =
      await (db.selectOnly(t)
            ..addColumns([t.pid])
            ..where(t.ulid.equals(ulidOf(pid))))
          .getSingleOrNull();
  final now = row?.read(t.pid);
  return now == pid ? null : now;
}

/// One mirror row by pid, for hydrating id lists into entries, its art
/// URL as [mirrorItemsPage] mints one.
Future<ItemSummary?> mirrorItemByPid(
  MirrorDatabase db,
  String pid, {
  String Function(String pid)? artUrlFor,
}) async {
  final row = await (db.select(
    db.mirrorItems,
  )..where((t) => t.pid.equals(pid))).getSingleOrNull();
  if (row == null) return null;
  return (await _summaries(db, [row], artUrlFor)).single;
}
