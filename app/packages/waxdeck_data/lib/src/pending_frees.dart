import 'dart:convert';

import 'package:drift/drift.dart';

import 'database.dart';

/// A download file a promise lists: its place in the item and its audio.
typedef OwedFile = ({int index, String essence});

/// A pinned cover a promise lists: its size, and the instant it was pinned.
typedef OwedPin = ({int sizePx, DateTime pinnedAt});

/// What a promise still owes: the rows it lists that the device still
/// holds, and no others.
class Owed {
  const Owed({required this.files, required this.pins});

  final List<OwedFile> files;
  final List<OwedPin> pins;
}

/// The frees a commit has promised and nothing has yet finished.
///
/// Dropping an item from the mirror because the server can never give it
/// back (a `removed` tombstone, a re-mirror's answer, a kind change that
/// left a download under the old pid) is a promise to free what the device
/// holds for it: its downloaded files and its pinned covers. The promise is
/// a row written in the same transaction as the drop, so a kill between the
/// two cannot lose it, and it stays until the bytes are gone.
///
/// What is owed is exactly what the device held when the commit ran: each
/// download file by its index and essence hash, each pinned cover by its
/// size and the instant it was pinned. A free takes those rows and no
/// others.
///
/// A download the device holds for the pid beyond them (a file at another
/// index, or from other audio) came after the commit and is the device's
/// own: the promise is dropped and every byte kept, since an item half
/// freed would be worse than either. A cover is no take-up of its own. A
/// pin follows a download, so the download is what counts: a cover that
/// lands for a pid owed a free is not listed and a free leaves it, and
/// [ArtworkPinStore.mayPin] is what keeps one from landing. The mirror
/// listing the pid again drops the promise too. A request that changes
/// none of the rows (the same files already complete) leaves no trace and
/// is not an event.
///
/// One settings row per pid, so a promise is written and cleared alone
/// however many are owed. Forgetting the server forgets them (see
/// [MirrorDatabase.wipe]); a sign-out keeps them for the next session to
/// finish.
class PendingFrees {
  PendingFrees(this.db);

  final MirrorDatabase db;

  /// The key prefix of a promise; the pid follows. [keyPrefixEnd] is the
  /// first string past every key that starts with it, for a range scan.
  static const keyPrefix = 'waxdeck.sync.free.';
  static const keyPrefixEnd = 'waxdeck.sync.free/';

  static String _key(String pid) => '$keyPrefix$pid';

  /// Promises to free what the device holds for [pid] now. Called inside
  /// the commit's transaction, after anything the commit itself moves has
  /// moved. Nothing held, nothing owed: any earlier promise for the pid is
  /// cleared too.
  Future<void> condemn(String pid) async {
    final held = await _held(pid);
    if (held.isEmpty) {
      await _forget(pid);
      return;
    }
    await db
        .into(db.clientSettings)
        .insertOnConflictUpdate(
          ClientSettingsCompanion.insert(key: _key(pid), value: held.encode()),
        );
  }

  /// What [pid]'s promise still owes, or null when it owes nothing now: no
  /// promise, the mirror lists the pid again, the device holds a download
  /// for it that the commit did not find, or none of what was listed is
  /// still held. The promise is forgotten in each of those cases but the
  /// first, every byte kept.
  ///
  /// Run inside whatever serializes the downloads (the manager's own
  /// section), the answer cannot go stale before the free that acts on it.
  Future<Owed?> owed(String pid) async {
    final row = await (db.select(
      db.clientSettings,
    )..where((t) => t.key.equals(_key(pid)))).getSingleOrNull();
    return row == null ? null : _decide(pid, row.value);
  }

  /// Of the promises ([only] one pid's), those still owed, in pid order.
  /// A promise that stopped being owed is forgotten here (see [owed]).
  Future<List<String>> due({String? only}) async {
    final query = db.select(db.clientSettings);
    if (only != null) {
      query.where((t) => t.key.equals(_key(only)));
    } else {
      query.where(
        (t) =>
            t.key.isBiggerOrEqualValue(keyPrefix) &
            t.key.isSmallerThanValue(keyPrefixEnd),
      );
    }
    final due = <String>[];
    for (final row in await query.get()) {
      final pid = row.key.substring(keyPrefix.length);
      if (await _decide(pid, row.value) != null) due.add(pid);
    }
    due.sort();
    return due;
  }

  /// Clears [pid]'s promise once nothing it listed is still held, which is
  /// when the free it asked for is done. Bytes the device took up since do
  /// not hold it open. Answers whether it cleared.
  Future<bool> settle(String pid) async {
    final row = await (db.select(
      db.clientSettings,
    )..where((t) => t.key.equals(_key(pid)))).getSingleOrNull();
    if (row == null) return true;
    final promised = _Held.decode(row.value);
    if (promised != null && (await _held(pid)).overlaps(promised)) {
      return false;
    }
    await _forget(pid);
    return true;
  }

  Future<Owed?> _decide(String pid, String value) async {
    final promised = _Held.decode(value);
    if (promised == null || await _listed(pid)) {
      await _forget(pid);
      return null;
    }
    final held = await _held(pid);
    if (held.files.any((f) => !promised.files.contains(f))) {
      await _forget(pid);
      return null;
    }
    final files = [
      for (final f in promised.files)
        if (held.files.contains(f)) f,
    ]..sort((a, b) => a.index.compareTo(b.index));
    final pins = [
      for (final p in promised.pins)
        if (held.pins.contains(p)) p,
    ]..sort((a, b) => a.sizePx.compareTo(b.sizePx));
    if (files.isEmpty && pins.isEmpty) {
      await _forget(pid);
      return null;
    }
    return Owed(
      files: files,
      pins: [
        for (final p in pins)
          (
            sizePx: p.sizePx,
            pinnedAt: DateTime.fromMillisecondsSinceEpoch(p.at, isUtc: true),
          ),
      ],
    );
  }

  Future<bool> _listed(String pid) async =>
      await (db.select(db.mirrorItems)
            ..where((t) => t.pid.equals(pid))
            ..limit(1))
          .getSingleOrNull() !=
      null;

  Future<void> _forget(String pid) => (db.delete(
    db.clientSettings,
  )..where((t) => t.key.equals(_key(pid)))).go();

  Future<_Held> _held(String pid) async {
    final files = await (db.select(
      db.downloadRecords,
    )..where((t) => t.pid.equals(pid))).get();
    final pins = await (db.select(
      db.artworkPins,
    )..where((t) => t.pid.equals(pid))).get();
    return _Held(
      {for (final f in files) (index: f.fileIndex, essence: f.essenceHash)},
      {
        for (final p in pins)
          (sizePx: p.sizePx, at: p.pinnedAt.millisecondsSinceEpoch),
      },
    );
  }
}

/// A pin as a promise keeps it: its size and its instant, in milliseconds.
typedef _Pin = ({int sizePx, int at});

/// What the device held for one pid at one moment.
class _Held {
  const _Held(this.files, this.pins);

  final Set<OwedFile> files;
  final Set<_Pin> pins;

  bool get isEmpty => files.isEmpty && pins.isEmpty;

  /// Whether something [promised] listed is still held.
  bool overlaps(_Held promised) =>
      files.any(promised.files.contains) || pins.any(promised.pins.contains);

  String encode() => jsonEncode({
    'f': [
      for (final f in files.toList()..sort((a, b) => a.index - b.index))
        [f.index, f.essence],
    ],
    'p': [
      for (final p in pins.toList()..sort((a, b) => a.sizePx - b.sizePx))
        [p.sizePx, p.at],
    ],
  });

  /// Null for a value this build did not write.
  static _Held? decode(String value) {
    try {
      final json = jsonDecode(value) as Map<String, Object?>;
      final files = <OwedFile>{};
      for (final f in json['f']! as List<Object?>) {
        final pair = f! as List<Object?>;
        files.add((index: pair[0]! as int, essence: pair[1]! as String));
      }
      final pins = <_Pin>{};
      for (final p in json['p']! as List<Object?>) {
        final pair = p! as List<Object?>;
        pins.add((sizePx: pair[0]! as int, at: pair[1]! as int));
      }
      return _Held(files, pins);
    } on Object {
      return null;
    }
  }
}
