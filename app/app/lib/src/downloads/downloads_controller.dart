import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import '../artwork/artwork_providers.dart';
import '../settings/client_prefs.dart';
import '../sync/sync_providers.dart';

/// One row of the downloads manager: the bytes on disk, and who they
/// belong to.
class DownloadEntry {
  const DownloadEntry({required this.record, this.item, this.progress});

  final DownloadedItem record;

  /// The mirror's row for this pid, when it has one. Null where the
  /// catalog has moved on from an item still on disk, which is a real
  /// state and the one a listener most wants to reclaim: the row says so
  /// and offers removal rather than hiding it.
  final ItemSummary? item;

  /// The caller's saved position, from the mirror rather than the
  /// server: this screen is the one most likely to be open with no
  /// network, and a played dot that needs a round trip is no dot at all.
  final PlayState? progress;

  String get pid => record.pid;
  String get title => item?.title ?? pid;
  String? get subtitle => item?.artist;

  MediaType get mediaType => item?.mediaType ?? MediaType.music;

  bool get complete => record.complete;

  /// Listened to the end. What "Remove finished episodes" is about.
  bool get finished => progress?.finished ?? false;

  /// The stamp moves on any play-state write, not just the one that set
  /// `finished`, so this only ever keeps a file longer than asked.
  /// A missing stamp is not "long ago": it must not sweep.
  bool finishedBefore(DateTime cutoff) {
    if (!finished) return false;
    final at = progress?.updatedAt;
    return at != null && at.isBefore(cutoff);
  }
}

/// What this device holds, and what it is fetching.
class DownloadsState {
  const DownloadsState({required this.entries});

  static const empty = DownloadsState(entries: <DownloadEntry>[]);

  final List<DownloadEntry> entries;

  Iterable<DownloadEntry> get inFlight =>
      entries.where((e) => !e.record.complete);

  Iterable<DownloadEntry> get stored => entries.where((e) => e.record.complete);

  int get usedBytes =>
      entries.fold(0, (sum, e) => sum + (e.complete ? e.record.sizeBytes : 0));

  /// Bytes on disk per medium, biggest first, for the storage header.
  List<({MediaType mediaType, int bytes})> get byDomain {
    final totals = <MediaType, int>{};
    for (final entry in stored) {
      totals[entry.mediaType] =
          (totals[entry.mediaType] ?? 0) + entry.record.sizeBytes;
    }
    final types = totals.keys.toList()
      ..sort((a, b) => totals[b]!.compareTo(totals[a]!));
    return <({MediaType mediaType, int bytes})>[
      for (final type in types) (mediaType: type, bytes: totals[type]!),
    ];
  }

  /// The stored rows grouped by medium, in the same order the header
  /// lists them.
  List<({MediaType mediaType, List<DownloadEntry> entries})> get groups {
    final grouped = <MediaType, List<DownloadEntry>>{};
    for (final entry in stored) {
      (grouped[entry.mediaType] ??= <DownloadEntry>[]).add(entry);
    }
    for (final rows in grouped.values) {
      rows.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    }
    return <({MediaType mediaType, List<DownloadEntry> entries})>[
      for (final domain in byDomain)
        if (grouped[domain.mediaType] case final rows?)
          (mediaType: domain.mediaType, entries: rows),
    ];
  }
}

/// Reads what the download store holds and hydrates each row from the
/// mirror.
///
/// Rebuilt rather than streamed: the store answers a snapshot, and the
/// screen listens to the progress stream for the transfers in flight. A
/// verb that changes what is held refreshes through here.
class DownloadsController extends AsyncNotifier<DownloadsState> {
  DownloadManagerPort? get _port => ref.read(downloadManagerProvider);

  @override
  Future<DownloadsState> build() async {
    final port = ref.watch(downloadManagerProvider);
    if (port == null) return DownloadsState.empty;
    final db = ref.watch(mirrorDatabaseProvider);
    final sync = ref.watch(syncEngineProvider);
    final records = await port.stored();
    final entries = <DownloadEntry>[];
    for (final record in records) {
      entries.add(
        DownloadEntry(
          record: record,
          item: db == null ? null : await mirrorItemByPid(db, record.pid),
          progress: await sync?.localPlayState(record.pid),
        ),
      );
    }
    return DownloadsState(entries: entries);
  }

  /// Drops an item's audio and the cover pinned beside it.
  ///
  /// Two calls, not one. The download path pins the item's artwork so a
  /// downloaded item has a cover with the server unreachable,
  /// and that pin is kept by pid in a table the downloads port knows
  /// nothing about - so removing the audio alone leaves image files
  /// nothing short of a sign-out will reclaim. This is the only caller
  /// either half has ever had.
  Future<void> remove(String pid) async {
    final port = _port;
    if (port == null) return;
    await port.remove(pid);
    await ref.read(artworkStoreProvider).unpin(pid);
    ref.invalidateSelf();
    await future;
  }

  /// Everything on disk, in one sweep.
  ///
  /// Sequential on purpose, and not a `Future.wait`. `remove` decides
  /// whether to unlink a file by asking whether any *other* row still
  /// holds the same essence hash, so two items that share one file (CUE
  /// siblings share an image) removed at the same time would each see the
  /// other's row still present, each conclude the file is shared, and
  /// leave it on disk with nothing pointing at it. Clearing downloads is
  /// also not a latency-sensitive operation; correctness is the whole job.
  Future<void> removeAll() async {
    final port = _port;
    if (port == null) return;
    final store = ref.read(artworkStoreProvider);
    for (final entry in state.value?.entries ?? const <DownloadEntry>[]) {
      await port.remove(entry.pid);
      await store.unpin(entry.pid);
    }
    ref.invalidateSelf();
    await future;
  }

  /// Episodes only: a book played through is one somebody may want
  /// again. Sequential for [removeAll]'s reason. [finishedBefore] is the
  /// sweep's grace window; the menu item passes none.
  Future<int> removeFinishedEpisodes({DateTime? finishedBefore}) async {
    final port = _port;
    if (port == null) return 0;
    final store = ref.read(artworkStoreProvider);
    final done = <DownloadEntry>[
      for (final entry in state.value?.stored ?? const <DownloadEntry>[])
        if (entry.mediaType == MediaType.podcast &&
            (finishedBefore == null
                ? entry.finished
                : entry.finishedBefore(finishedBefore)))
          entry,
    ];
    for (final entry in done) {
      await port.remove(entry.pid);
      await store.unpin(entry.pid);
    }
    if (done.isNotEmpty) {
      ref.invalidateSelf();
      await future;
    }
    return done.length;
  }

  /// Asks for every held item again.
  ///
  /// This is the stale sweep. Nothing local can tell a stale file from a
  /// current one - staleness is a comparison against what the server has
  /// now - and `download` already makes exactly that comparison per
  /// file: it fetches download-info, keeps any file whose essence hash
  /// still matches, and re-transfers the rest. So refreshing everything
  /// costs one request per item and re-downloads only what actually
  /// moved. It is also what fills in the per-part durations an item
  /// downloaded before this release has none of.
  Future<void> refreshStale() async {
    final port = _port;
    if (port == null) return;
    for (final entry in state.value?.stored ?? const <DownloadEntry>[]) {
      try {
        await port.download(entry.pid);
      } on WaxDeckApiException {
        // An item the server no longer serves stays as it is; the row is
        // still playable from disk, which is the point of holding it.
        continue;
      }
    }
    ref.invalidateSelf();
    await future;
  }

  Future<void> cancel(String pid) async {
    await _port?.cancel(pid);
    ref.invalidateSelf();
    await future;
  }

  /// Answers whether the transfer actually paused: a server with no range
  /// support cannot be resumed, so the plugin refuses rather than
  /// canceling behind the caller's back.
  Future<bool> pause(String pid) async => await _port?.pause(pid) ?? false;

  Future<void> resume(String pid) async => _port?.resume(pid);
}

final downloadsProvider =
    AsyncNotifierProvider<DownloadsController, DownloadsState>(
      DownloadsController.new,
    );

/// Live progress per pid, for the transfers in flight.
///
/// A fold of the port's stream rather than a poll: the store's snapshot
/// says what is pending, and this says how far along each one is.
final downloadProgressProvider =
    StreamProvider.autoDispose<Map<String, double>>((ref) {
      final port = ref.watch(downloadManagerProvider);
      if (port == null) return const Stream<Map<String, double>>.empty();
      final fractions = <String, double>{};
      return port.progress.map((update) {
        if (update.complete) {
          fractions.remove(update.pid);
          // A finished transfer changes what is held, so the list behind
          // it is asked again.
          ref.invalidate(downloadsProvider);
        } else if (update.failed) {
          fractions.remove(update.pid);
          ref.invalidate(downloadsProvider);
        } else {
          fractions[update.pid] = update.fraction;
        }
        return Map<String, double>.unmodifiable(fractions);
      });
    });

/// As fine as an hours-long grace window can use.
const _tidyInterval = Duration(hours: 1);

/// Reclaims finished episodes, on the shell rather than on the downloads
/// screen: whoever turned this on did it to stop visiting that screen.
final downloadsTidyBinderProvider = Provider.autoDispose<void>((ref) {
  // Web has no local download manager, so nothing of its own to reclaim.
  if (ref.watch(downloadManagerProvider) == null) return;
  // Watched, so this holds no timer while the setting is off and sweeps
  // as soon as it goes on.
  if (!ref.watch(autoRemoveFinishedProvider)) return;
  final hours = ref.watch(autoRemoveFinishedAfterHoursProvider);

  Future<void> sweep() async {
    final cutoff = DateTime.now().subtract(Duration(hours: hours));
    try {
      // Awaited first: the sweep reads the loaded listing, and on a cold
      // start - or a switch flipped from Settings, where nothing built
      // this - there is none yet, so it would find nothing to reclaim.
      await ref.read(downloadsProvider.future);
      await ref
          .read(downloadsProvider.notifier)
          .removeFinishedEpisodes(finishedBefore: cutoff);
    } on Object {
      // Housekeeping with no surface to report on; the next pass retries.
    }
  }

  final timer = Timer.periodic(_tidyInterval, (_) => unawaited(sweep()));
  ref.onDispose(timer.cancel);
  unawaited(sweep());
});
