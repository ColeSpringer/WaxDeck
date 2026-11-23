import 'package:drift/drift.dart';

import 'database.dart';
import 'mirror_pages.dart';
import 'pending_frees.dart';

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

  /// The URL of the picture the bytes are of, so a re-pin asks for the
  /// same variant rather than whatever the item's front slot has become:
  /// where they came from, or where the server has named that picture
  /// since ([ArtworkPinStore.recordUrl]).
  final String artUrl;

  /// The validator the server gave these bytes; a re-pin presents it and
  /// skips the transfer when nothing changed.
  final String etag;

  final String localPath;
  final int sizeBytes;
  final DateTime pinnedAt;
}

/// A pin's place in the order [ArtworkPinStore.pinsAfter] reads them in.
typedef PinCursor = ({String pid, int sizePx});

/// Where pinned artwork is recorded. The files themselves are the
/// caller's: this store knows their paths, not their bytes.
abstract class ArtworkPinStore {
  /// Every pin held for [pid], largest rung first, so a caller can take
  /// the first one at least as big as it needs.
  Future<List<ArtworkPinRecord>> pinsFor(String pid);

  /// [pinsFor], for a draw: where [pid] holds none, those of the pid a
  /// kind change has given its item since, as a queue or a summary from
  /// before the change still names the old one. Never for a write, which
  /// acts on [pid] alone.
  Future<List<ArtworkPinRecord>> pinsToDraw(String pid);

  Future<void> put(ArtworkPinRecord pin);

  /// Records that the picture [pin] holds is at [artUrl] now, where it is
  /// still the pin held: of that size, pinned at that instant. One
  /// replaced or removed meanwhile is left alone, and no row is made.
  Future<void> recordUrl(ArtworkPinRecord pin, String artUrl);

  /// The next [limit] of every pin there is, past [after] or from the
  /// first, in an order that holds while pins come and go: a walk of
  /// them all can stop anywhere and pick up from its last pin.
  Future<List<ArtworkPinRecord>> pinsAfter(
    PinCursor? after, {
    required int limit,
  });

  /// Drops exactly the pins listed, each by its size and the instant it was
  /// pinned, and no others: a cover the device pinned since (another size,
  /// or the same size pinned again) is not what was listed and stays. For
  /// the free a commit promised, which takes what it recorded, and for an
  /// unpin, which takes what it read.
  Future<void> removeExactly(String pid, List<OwedPin> pins);

  /// Whether a cover may be kept for [pid] now: only while the device holds
  /// a download for it and no free is owed for it. A pin is a promise made
  /// when the listener downloaded the item, so one made for an item that
  /// is gone, or about to be freed, would be a promise about nothing that
  /// nothing would ever take back.
  Future<bool> mayPin(String pid);

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
  Future<List<ArtworkPinRecord>> pinsToDraw(String pid) async {
    final held = await pinsFor(pid);
    if (held.isNotEmpty) return held;
    final now = await mirrorRenamedPid(db, pid);
    return now == null ? held : pinsFor(now);
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
  Future<void> recordUrl(ArtworkPinRecord pin, String artUrl) async {
    // An update of the row as it was read, never an upsert: a pin taken
    // back meanwhile must not come back as a row with no file.
    await (db.update(db.artworkPins)..where(
          (t) =>
              t.pid.equals(pin.pid) &
              t.sizePx.equals(pin.sizePx) &
              t.pinnedAt.equals(pin.pinnedAt),
        ))
        .write(ArtworkPinsCompanion(artUrl: Value(artUrl)));
  }

  @override
  Future<List<ArtworkPinRecord>> pinsAfter(
    PinCursor? after, {
    required int limit,
  }) async {
    // The primary key's own order, so a page is a range read of it.
    final query = db.select(db.artworkPins)
      ..orderBy([
        (t) => OrderingTerm.asc(t.pid),
        (t) => OrderingTerm.asc(t.sizePx),
      ])
      ..limit(limit);
    if (after != null) {
      query.where(
        (t) =>
            t.pid.isBiggerThanValue(after.pid) |
            (t.pid.equals(after.pid) &
                t.sizePx.isBiggerThanValue(after.sizePx)),
      );
    }
    return (await query.get()).map(_record).toList();
  }

  @override
  Future<void> removeExactly(String pid, List<OwedPin> pins) async {
    for (final pin in pins) {
      await (db.delete(db.artworkPins)..where(
            (t) =>
                t.pid.equals(pid) &
                t.sizePx.equals(pin.sizePx) &
                t.pinnedAt.equals(pin.pinnedAt),
          ))
          .go();
    }
  }

  @override
  Future<bool> mayPin(String pid) async {
    final held =
        await (db.select(db.downloadRecords)
              ..where((t) => t.pid.equals(pid))
              ..limit(1))
            .getSingleOrNull();
    if (held == null) return false;
    // Asked of the promise rather than read off its row, so one that has
    // stopped being owed (the item is listed again) does not keep a cover
    // from a download that is the device's own.
    return (await PendingFrees(db).due(only: pid)).isEmpty;
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
  Future<List<ArtworkPinRecord>> pinsToDraw(String pid) async => const [];

  @override
  Future<void> put(ArtworkPinRecord pin) async {}

  @override
  Future<void> recordUrl(ArtworkPinRecord pin, String artUrl) async {}

  @override
  Future<List<ArtworkPinRecord>> pinsAfter(
    PinCursor? after, {
    required int limit,
  }) async => const [];

  @override
  Future<void> removeExactly(String pid, List<OwedPin> pins) async {}

  @override
  Future<bool> mayPin(String pid) async => false;

  @override
  Future<List<ArtworkPinRecord>> clear() async => const [];
}
