import 'dart:async';

/// Everything offline playback needs for one item: local file paths in
/// playback order and the window for items carved out of a larger file.
class LocalPlayback {
  const LocalPlayback({required this.paths, this.spanStartMs, this.spanEndMs});

  final List<String> paths;
  final int? spanStartMs;
  final int? spanEndMs;
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
}
