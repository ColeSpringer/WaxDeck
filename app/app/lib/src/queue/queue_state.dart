import 'package:waxdeck_data/waxdeck_data.dart';

/// The most items a local queue holds, mirroring the server's Connect
/// session cap so a queue can always be handed to an endpoint whole.
const int kQueueCap = 500;

/// What happens at the end of an item.
enum QueueRepeat {
  off('off'),
  all('all'),
  one('one');

  const QueueRepeat(this.wireName);

  /// The vocabulary the Connect command bus speaks (`set-repeat`).
  final String wireName;

  static QueueRepeat fromWire(String value) {
    for (final r in QueueRepeat.values) {
      if (r.wireName == value) return r;
    }
    return QueueRepeat.off;
  }
}

/// What a queue was built from, for the "Playing from" line, the queue
/// screen's header, and the restore offer.
enum QueueSourceKind {
  album('album'),

  /// A release group: the work rather than the edition, so the queue is
  /// every pressing's tracks. Not [album], which is one edition and is
  /// what a queue captioned with an album title should mean.
  releaseGroup('releaseGroup'),
  artist('artist'),
  playlist('playlist'),
  genre('genre'),

  /// One year's worth of the library. Not [library]: a queue built from
  /// the 1997 bucket captioned as the whole collection is a wrong answer
  /// on the queue screen and a wrong scope for anything that refills
  /// against the source.
  year('year'),
  mix('mix'),
  shelf('shelf'),
  search('search'),
  library('library'),
  show('show'),
  book('book'),

  /// One item tapped with no context around it: an episode, a track
  /// played from a grid or a search result row. A book started from its
  /// own screen is [book] rather than this, since the entity it came
  /// from is exactly what the queue surface should name.
  single('single'),

  /// A restored queue whose provenance predates this field, or one
  /// assembled by something that did not say.
  unknown('unknown');

  const QueueSourceKind(this.wireName);

  final String wireName;

  static QueueSourceKind fromWire(String value) {
    for (final k in QueueSourceKind.values) {
      if (k.wireName == value) return k;
    }
    return QueueSourceKind.unknown;
  }
}

/// Where the queue came from. [label] is the display name as the source
/// screen knows it ("Kind of Blue"); rendering it into a sentence is the
/// UI's job, not this layer's.
class QueueSource {
  const QueueSource({
    required this.kind,
    required this.label,
    this.pid,
    this.rolling = false,
    this.cursor = '',
    this.seed,
  });

  static const QueueSource none = QueueSource(
    kind: QueueSourceKind.unknown,
    label: '',
  );

  final QueueSourceKind kind;
  final String label;

  /// The entity the queue was built from, when there is one.
  final String? pid;

  /// True when the queue is a window over a scope larger than it holds,
  /// drawn from again as it drains. The queue surface says so, so the
  /// window is not mistaken for the whole scope, and it goes false when
  /// the scope runs out.
  final bool rolling;

  /// Where the source's own listing stands at the queue's tail, so a
  /// draw resumes rather than restarts. Opaque: the server shapes its
  /// cursors and this only carries them.
  ///
  /// Empty means the frontier is not known - an ordered window cut short
  /// of what its caller had loaded, or a restored queue whose cursor was
  /// never written. A draw against an empty cursor finds its place from
  /// the queue's last entry instead, which costs a page per cap's worth
  /// of scope passed and is exact where a stale cursor would not be.
  final String cursor;

  /// The seed a random draw pages under, so later pages walk the same
  /// permutation. Null for an ordered draw, and for the sources whose
  /// listings have no random order to ask for.
  final int? seed;

  QueueSource copyWith({
    bool? rolling,
    String? cursor,
    int? seed,
    bool clearSeed = false,
  }) => QueueSource(
    kind: kind,
    label: label,
    pid: pid,
    rolling: rolling ?? this.rolling,
    cursor: cursor ?? this.cursor,
    seed: clearSeed ? null : (seed ?? this.seed),
  );

  @override
  bool operator ==(Object other) =>
      other is QueueSource &&
      other.kind == kind &&
      other.label == label &&
      other.pid == pid &&
      other.rolling == rolling &&
      other.cursor == cursor &&
      other.seed == seed;

  @override
  int get hashCode => Object.hash(kind, label, pid, rolling, cursor, seed);

  @override
  String toString() => 'QueueSource(${kind.wireName}, $label, $pid)';
}

/// The separator between a seeded draw's seed and its cursor in the one
/// stored string the two travel in.
///
/// Both halves are the same fact - where the source's listing stands -
/// and a cursor issued under one seed is invalid under another, so they
/// are stored together or not at all. Safe as a separator because a
/// cursor is base64url and never contains one.
const String _seedSeparator = '|';

/// The stored form of a source's continuation: the cursor, with the
/// seed in front of it when the draw has one.
String encodeQueueCursor(QueueSource source) {
  final seed = source.seed;
  return seed == null ? source.cursor : '$seed$_seedSeparator${source.cursor}';
}

/// The reverse. A value that carries no seed reads back as a plain
/// cursor, which is what everything written before seeded draws existed
/// (and every unseeded draw since) looks like.
({String cursor, int? seed}) decodeQueueCursor(String stored) {
  final at = stored.indexOf(_seedSeparator);
  if (at < 0) return (cursor: stored, seed: null);
  final seed = int.tryParse(stored.substring(0, at));
  if (seed == null) return (cursor: stored, seed: null);
  return (cursor: stored.substring(at + 1), seed: seed);
}

/// One place in the queue. [queueId] is stable for the entry's life, so
/// a reorder moves an entry rather than replacing it, and the same pid
/// may sit in the queue more than once.
class QueueEntry {
  const QueueEntry({required this.queueId, required this.pid});

  final String queueId;
  final String pid;

  @override
  String toString() => 'QueueEntry($queueId, $pid)';
}

/// The queue that [QueueController.undoReplace] would put back: what was
/// playing before a tap replaced it, and where it stood.
class QueueUndo {
  const QueueUndo({required this.queue, required this.positionMs});

  final QueueState queue;
  final int positionMs;
}

/// The queue, as one immutable value.
///
/// [entries] is play order: what the queue screen renders top to bottom
/// and what a Connect load serializes to. [sourceOrder] is the same
/// entries by their queue ids in the order the queue was built in, which
/// is what un-shuffling restores; while shuffle is off the two agree.
///
/// Deliberately no value equality: the lists would have to be compared
/// element by element on every notification, and the controller only
/// ever assigns a new state when something actually changed. Tests
/// assert on fields rather than on whole states.
class QueueState {
  const QueueState({
    required this.entries,
    required this.sourceOrder,
    required this.currentIndex,
    required this.shuffled,
    required this.repeat,
    required this.source,
    required this.nextQueueId,
    this.undo,
  });

  static const QueueState empty = QueueState(
    entries: [],
    sourceOrder: [],
    currentIndex: 0,
    shuffled: false,
    repeat: QueueRepeat.off,
    source: QueueSource.none,
    nextQueueId: 0,
  );

  final List<QueueEntry> entries;
  final List<String> sourceOrder;
  final int currentIndex;
  final bool shuffled;
  final QueueRepeat repeat;
  final QueueSource source;

  /// The next queue id to mint. Persisted, so a restored queue cannot
  /// hand a live id to a new entry.
  final int nextQueueId;

  /// The queue a replacement displaced, for the Undo on the "Playing
  /// from" toast. Never persisted: a relaunch is not an accident to
  /// take back.
  final QueueUndo? undo;

  bool get isEmpty => entries.isEmpty;
  bool get isNotEmpty => entries.isNotEmpty;
  int get length => entries.length;

  QueueEntry? get currentEntry =>
      entries.isEmpty ? null : entries[currentIndex];

  String? get currentPid => currentEntry?.pid;

  /// Ordered pids, which is what `POST /player/sessions`, `set-queue`,
  /// and a timeline mint all consume.
  List<String> get pids => [for (final e in entries) e.pid];

  /// How many entries have not played yet, which is what decides when a
  /// rolling window draws again.
  int get unplayed => entries.isEmpty ? 0 : entries.length - 1 - currentIndex;

  /// The entry standing at the source's frontier: the last one taken
  /// from the scope, in the order the scope handed them over rather
  /// than the order they play in. A draw with no cursor finds its place
  /// in the source by this.
  String? get frontierPid {
    if (sourceOrder.isEmpty) return null;
    final id = sourceOrder.last;
    for (final e in entries) {
      if (e.queueId == id) return e.pid;
    }
    return null;
  }

  /// The entry an advance would land on, or null when it would end the
  /// queue or repeat the current item. This is what the engine may
  /// preload, so it must answer without changing anything, and it must
  /// never name the item already playing: a lone entry on repeat-all
  /// wraps onto itself, which is a repeat and not something to preload.
  QueueEntry? get nextEntry {
    if (entries.isEmpty || repeat == QueueRepeat.one) return null;
    if (currentIndex + 1 < entries.length) return entries[currentIndex + 1];
    if (repeat == QueueRepeat.all && entries.length > 1) return entries.first;
    return null;
  }

  QueueState copyWith({
    List<QueueEntry>? entries,
    List<String>? sourceOrder,
    int? currentIndex,
    bool? shuffled,
    QueueRepeat? repeat,
    QueueSource? source,
    int? nextQueueId,
    QueueUndo? undo,
    bool clearUndo = false,
  }) {
    return QueueState(
      entries: entries ?? this.entries,
      sourceOrder: sourceOrder ?? this.sourceOrder,
      currentIndex: currentIndex ?? this.currentIndex,
      shuffled: shuffled ?? this.shuffled,
      repeat: repeat ?? this.repeat,
      source: source ?? this.source,
      nextQueueId: nextQueueId ?? this.nextQueueId,
      undo: clearUndo ? null : (undo ?? this.undo),
    );
  }

  /// The persistable shape: ordered pids, where they stand, and what
  /// they came from. [sourceOrder] rides as a rank per entry.
  StoredQueue toStored({required DateTime updatedAt}) {
    final ranks = {
      for (var i = 0; i < sourceOrder.length; i++) sourceOrder[i]: i,
    };
    return StoredQueue(
      entries: [
        // An entry missing from the source order should be impossible
        // (every edit writes both lists), so it falls back to its own
        // play position rather than collapsing every orphan onto one
        // rank, where they would come back in whatever order a sort
        // happened to leave them.
        for (var i = 0; i < entries.length; i++)
          StoredQueueEntry(
            queueId: entries[i].queueId,
            pid: entries[i].pid,
            sourceRank: ranks[entries[i].queueId] ?? sourceOrder.length + i,
          ),
      ],
      currentIndex: currentIndex,
      shuffled: shuffled,
      repeat: repeat.wireName,
      sourceKind: source.kind.wireName,
      sourceLabel: source.label,
      sourcePid: source.pid,
      sourceRolling: source.rolling,
      sourceCursor: encodeQueueCursor(source),
      nextQueueId: nextQueueId,
      updatedAt: updatedAt,
    );
  }

  /// Rebuilds a queue from what was persisted. Entry ids and ranks come
  /// back as written; a rank that repeats (an older build, a torn
  /// write) breaks the tie on play position rather than on whatever
  /// order an unstable sort leaves behind, which is what makes the
  /// degradation to play order real rather than nominal.
  factory QueueState.fromStored(StoredQueue stored) {
    final continuation = decodeQueueCursor(stored.sourceCursor);
    final byRank = [for (var i = 0; i < stored.entries.length; i++) i]
      ..sort((a, b) {
        final rank = stored.entries[a].sourceRank.compareTo(
          stored.entries[b].sourceRank,
        );
        return rank != 0 ? rank : a.compareTo(b);
      });
    // The counter is written with the entries, but a torn write could
    // leave it behind them; minting from it must still never collide
    // with an id already in the queue.
    var next = stored.nextQueueId;
    for (final e in stored.entries) {
      final n = queueIdOrdinal(e.queueId);
      if (n != null && n >= next) next = n + 1;
    }
    return QueueState(
      entries: [
        for (final e in stored.entries)
          QueueEntry(queueId: e.queueId, pid: e.pid),
      ],
      sourceOrder: [for (final i in byRank) stored.entries[i].queueId],
      currentIndex: stored.entries.isEmpty
          ? 0
          : stored.currentIndex.clamp(0, stored.entries.length - 1),
      shuffled: stored.shuffled,
      repeat: QueueRepeat.fromWire(stored.repeat),
      source: QueueSource(
        kind: QueueSourceKind.fromWire(stored.sourceKind),
        label: stored.sourceLabel,
        pid: stored.sourcePid,
        rolling: stored.sourceRolling,
        cursor: continuation.cursor,
        seed: continuation.seed,
      ),
      nextQueueId: next,
    );
  }
}

/// The counter value behind a minted queue id, or null when the id came
/// from somewhere else.
int? queueIdOrdinal(String queueId) {
  if (!queueId.startsWith(kQueueIdPrefix)) return null;
  return int.tryParse(queueId.substring(kQueueIdPrefix.length));
}

/// Queue ids are local and disposable; the prefix only keeps them from
/// reading like pids in a log line.
const String kQueueIdPrefix = 'q';
