import 'package:drift/drift.dart';

import 'database.dart';

/// One pinned cover: the bytes kept on disk for an item that was
/// downloaded, so its grid cell and its player draw artwork with the
/// server unreachable.
///
/// Pins are not a cache. The HTTP cache holds whatever was looked at
/// recently and evicts under pressure; a pin is a promise made when the
/// listener downloaded the item and is only broken when they undownload
/// it.
class ArtworkPinRecord {
  const ArtworkPinRecord({
    required this.pid,
    required this.sizePx,
    required this.artUrl,
    required this.etag,
    required this.localPath,
    required this.sizeBytes,
    required this.pinnedAt,
  });

  final String pid;

  /// The rung the bytes were fetched at.
  final int sizePx;

  /// The URL the bytes came from, so a re-pin asks for the same variant
  /// rather than whatever the item's front slot has become.
  final String artUrl;

  /// The validator the server gave these bytes; a re-pin presents it and
  /// skips the transfer when nothing changed.
  final String etag;

  final String localPath;
  final int sizeBytes;
  final DateTime pinnedAt;
}

/// Where pinned artwork is recorded. The files themselves are the
/// caller's: this store knows their paths, not their bytes.
abstract class ArtworkPinStore {
  /// Every pin held for [pid], largest rung first, so a caller can take
  /// the first one at least as big as it needs.
  Future<List<ArtworkPinRecord>> pinsFor(String pid);

  Future<void> put(ArtworkPinRecord pin);

  /// Drops every pin for [pid] and answers what was dropped, so the
  /// caller can unlink the files it just stopped promising.
  Future<List<ArtworkPinRecord>> remove(String pid);

  /// Drops every pin there is, for a sign-out: the next account has no
  /// business reading the last one's covers.
  Future<List<ArtworkPinRecord>> clear();
}

/// The pin store over the local mirror database (native builds).
class DriftArtworkPinStore implements ArtworkPinStore {
  DriftArtworkPinStore(this.db);

  final MirrorDatabase db;

  @override
  Future<List<ArtworkPinRecord>> pinsFor(String pid) async {
    final rows =
        await (db.select(db.artworkPins)
              ..where((t) => t.pid.equals(pid))
              ..orderBy([(t) => OrderingTerm.desc(t.sizePx)]))
            .get();
    return rows.map(_record).toList();
  }

  @override
  Future<void> put(ArtworkPinRecord pin) {
    return db
        .into(db.artworkPins)
        .insertOnConflictUpdate(
          ArtworkPinsCompanion.insert(
            pid: pin.pid,
            sizePx: pin.sizePx,
            artUrl: pin.artUrl,
            etag: pin.etag,
            localPath: pin.localPath,
            sizeBytes: pin.sizeBytes,
            pinnedAt: pin.pinnedAt,
          ),
        );
  }

  @override
  Future<List<ArtworkPinRecord>> remove(String pid) async {
    final going = await pinsFor(pid);
    await (db.delete(db.artworkPins)..where((t) => t.pid.equals(pid))).go();
    return going;
  }

  @override
  Future<List<ArtworkPinRecord>> clear() async {
    final going = (await db.select(db.artworkPins).get()).map(_record).toList();
    await db.delete(db.artworkPins).go();
    return going;
  }

  ArtworkPinRecord _record(ArtworkPin row) => ArtworkPinRecord(
    pid: row.pid,
    sizePx: row.sizePx,
    artUrl: row.artUrl,
    etag: row.etag,
    localPath: row.localPath,
    sizeBytes: row.sizeBytes,
    pinnedAt: row.pinnedAt,
  );
}

/// The pin store where nothing is pinned: the web build, which has no
/// mirror and no offline mode to pin for, and tests that do not care.
class NoArtworkPinStore implements ArtworkPinStore {
  const NoArtworkPinStore();

  @override
  Future<List<ArtworkPinRecord>> pinsFor(String pid) async => const [];

  @override
  Future<void> put(ArtworkPinRecord pin) async {}

  @override
  Future<List<ArtworkPinRecord>> remove(String pid) async => const [];

  @override
  Future<List<ArtworkPinRecord>> clear() async => const [];
}
