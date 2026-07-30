import 'dart:async';

/// One downloaded backing file of an item: a track's only file, or one
/// part of a multi-file audiobook.
class LocalPart {
  const LocalPart({required this.path, this.durationMs});

  final String path;

  /// This file's own duration, as download-info reported it. Null when
  /// the catalog did not know it, and on records written before the
  /// field existed.
  final int? durationMs;
}

/// Everything offline playback needs for one item: its local files in
/// playback order, and the window for items carved out of a larger file.
class LocalPlayback {
  const LocalPlayback({required this.parts, this.spanStartMs, this.spanEndMs})
    : assert(parts.length > 0, 'an item with no local files is not playable');

  final List<LocalPart> parts;
  final int? spanStartMs;
  final int? spanEndMs;

  /// Whether these parts can be placed on the item's own timeline.
  ///
  /// A multi-part book plays as one timeline and a part's offset in it is
  /// the sum of the durations before it, so a single missing duration
  /// puts every later part somewhere wrong. Better to say the item cannot
  /// be sequenced - which plays its first file, the behaviour before
  /// durations were stored at all - than to resume a listener two hours
  /// from where they were.
  bool get sequenced =>
      parts.length > 1 && parts.every((p) => (p.durationMs ?? 0) > 0);

  /// The part containing [ms] on the item's own timeline, and the offset
  /// that part begins at.
  ///
  /// The first part for an item that is one file or cannot be sequenced,
  /// and the last for a position past the end - which is where a
  /// checkpoint written against a longer edition of the same book lands.
  LocalPartAt partAt(int ms) {
    if (!sequenced) {
      return LocalPartAt(index: 0, startMs: 0, part: parts.first);
    }
    var offset = 0;
    for (var i = 0; i < parts.length; i++) {
      final duration = parts[i].durationMs!;
      if (ms < offset + duration || i == parts.length - 1) {
        return LocalPartAt(index: i, startMs: offset, part: parts[i]);
      }
      offset += duration;
    }
    // Unreachable: the loop above returns on its last iteration, and
    // `sequenced` guarantees there is one.
    throw StateError('no part for position $ms');
  }
}

/// Where one part sits on its item's timeline.
class LocalPartAt {
  const LocalPartAt({
    required this.index,
    required this.startMs,
    required this.part,
  });

  final int index;
  final int startMs;
  final LocalPart part;
}

/// Progress of one item's download, 0..1 across all its files.
class DownloadProgress {
  const DownloadProgress({
    required this.pid,
    required this.fraction,
    required this.complete,
    this.failed = false,
  });

  final String pid;
  final double fraction;
  final bool complete;

  /// A file of this item failed or was canceled; waiting for
  /// [complete] alone would wait forever.
  final bool failed;
}

/// What one downloaded or downloading item looks like to the manager
/// screen: what it holds on disk and how far along it is.
///
/// Deliberately per item rather than per file. The manager offers
/// removal, and removal is per item - a book's parts come and go
/// together - so a row is an item and its files are its bytes.
class DownloadedItem {
  const DownloadedItem({
    required this.pid,
    required this.sizeBytes,
    required this.files,
    required this.complete,
  });

  final String pid;

  /// Bytes this item's files occupy, as download-info declared them.
  /// Reported for pending files too, which is what makes the storage
  /// header add up to what the transfers are about to cost.
  final int sizeBytes;

  final int files;

  /// Every file is on disk.
  final bool complete;
}

/// The WaxDeck-owned downloads interface (the community plugin stays
/// behind it, per repo policy). Downloads fetch original bytes through
/// media-token URLs, so no auth header plumbing reaches the plugin.
abstract interface class DownloadManagerPort {
  Future<void> download(String pid);

  /// Drops the item's local audio and the records pointing at it.
  ///
  /// Not the whole of un-downloading: the artwork store pins the item's
  /// cover when it is downloaded, and that pin is kept by PID in a table
  /// this package owns but this port knows nothing about. A caller that
  /// removes the audio and leaves the cover behind leaves files nothing
  /// short of a sign-out will reclaim, so remove them together
  /// (`ArtworkStore.unpin`).
  Future<void> remove(String pid);
  Future<LocalPlayback?> localFor(String pid);
  Future<bool> isComplete(String pid);
  Stream<DownloadProgress> get progress;

  /// Everything this device holds or is fetching, in no promised order.
  ///
  /// No free-space figure beside it: nothing in Dart answers how much room
  /// a volume has left. Recorded in deferred work.
  Future<List<DownloadedItem>> stored();

  /// Stops an item's transfers, leaving what is on disk alone. The
  /// records go with them, so a canceled item reads as not downloaded
  /// rather than as a transfer nothing is driving.
  Future<void> cancel(String pid);

  /// Pauses an item's running transfers, keeping the bytes already
  /// fetched so [resume] can range past them. Answers whether anything
  /// was actually paused: a transfer the plugin cannot pause (a server
  /// with no range support) stays running rather than being canceled
  /// behind the caller's back.
  Future<bool> pause(String pid);

  Future<void> resume(String pid);
}
