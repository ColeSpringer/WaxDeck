import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import 'file_picker_port.dart';
import 'local_file_reader.dart';

/// The upload-format sets in force: the server-reported ones where the
/// health payload carries them, the hardcoded mirrors where a server
/// predates the fields. A failed read throws through - consumers go
/// through [resolveUploadFormats], which answers the mirror for that
/// one ask and retires the failure so the next ask fetches fresh,
/// rather than memoizing a network blip as the mirror for the rest of
/// the session. retry: null because the resolver's invalidate is the
/// retry: the ladder would hold `.future` unsettled for seconds while
/// every ask times out against it.
final uploadFormatSetsProvider = FutureProvider<UploadFormatSets>(
  retry: (_, _) => null,
  (ref) async {
    final health = await ref.watch(repositoryProvider).health();
    return UploadFormatSets(
      accepted: switch (health.uploadFormats) {
        final formats? when formats.isNotEmpty => formats.toSet(),
        _ => kAcceptedAudioExtensions,
      },
      rejected: switch (health.rejectedFormats) {
        final formats? when formats.isNotEmpty => formats.toSet(),
        _ => kRejectedAudioExtensions,
      },
    );
  },
);

/// The libraries this account may file an upload or an acquisition
/// under.
///
/// Empty is the honest answer for three different servers: one too old
/// for the route, one that refused the read, and one where this account
/// has nothing writable. All three want the same thing from the client -
/// no picker, and the server routing as it always did - so the failure
/// is degraded here rather than surfaced.
///
/// autoDispose because the picker is the only reader and a dialog is a
/// short life; `retry: null` because a failure here is final by
/// construction (there is nothing to show either way) and the backoff
/// would hold `.future` unsettled while a dialog waits on it.
final uploadTargetsProvider = FutureProvider.autoDispose<List<UploadTarget>>(
  retry: (_, _) => null,
  (ref) async {
    try {
      return await ref.watch(repositoryProvider).listUploadTargets();
    } on WaxDeckApiException {
      return const <UploadTarget>[];
    }
  },
);

/// The candidates for one media type, in the order the picker offers
/// them. A single candidate is not a choice, which is what the picker
/// keys its own visibility on.
List<UploadTarget> uploadTargetsFor(
  List<UploadTarget> targets,
  MediaType mediaType,
) => targets.where((t) => t.mediaTypes.contains(mediaType)).toList();

/// How long a pick or drop waits on the health read before filtering
/// with the mirror. Short on purpose: on the web the picker dialog
/// must open inside the tap's transient user activation, and a wait
/// longer than that budget produces no dialog at all.
const _formatsWait = Duration(seconds: 2);

/// The sets for one pick or drop, bounded. Still loading past the
/// budget answers the mirror and leaves the fetch to finish for the
/// next ask; a settled failure answers the mirror and invalidates, so
/// the next ask retries instead of reading the memoized miss.
Future<UploadFormatSets> resolveUploadFormats(WidgetRef ref) async {
  try {
    return await ref
        .read(uploadFormatSetsProvider.future)
        .timeout(_formatsWait);
  } on TimeoutException {
    return const UploadFormatSets();
  } on Object {
    ref.invalidate(uploadFormatSetsProvider);
    return const UploadFormatSets();
  }
}

/// The sets for a drop zone, resolved when a drop lands rather than at
/// build - the zone never rebuilds for the health read, and a drop on
/// a cold start waits the read out instead of filtering with a guess.
Future<UploadFormatSets> Function() dropFormats(WidgetRef ref) =>
    () => resolveUploadFormats(ref);

/// Local file paths retained for resuming a failed path-backed
/// transfer, keyed by upload id. Container-scoped so an event
/// invalidation mid-upload cannot drop the retry affordance with the
/// controller rebuild. Paths, never bytes: an audiobook-sized share
/// must not live in heap memory for the life of a retry affordance.
final _retryPathsProvider = Provider<Map<String, String>>((_) => {});

/// Windowed read accessors retained for resuming a failed
/// reader-backed transfer (web picks and drops), keyed by upload id.
/// The accessor holds a browser file handle, not bytes.
final _retryReadersProvider =
    Provider<Map<String, Stream<List<int>> Function([int? start, int? end])>>(
      (_) => {},
    );

/// Accumulated pages of the caller's upload sessions, the caller's
/// quota snapshot, plus which sessions failed locally mid-transfer and
/// can retry.
class UploadsState {
  const UploadsState({
    required this.uploads,
    this.nextCursor,
    this.quota,
    this.loadingMore = false,
    this.failed = const {},
  });

  final List<UploadSession> uploads;
  final String? nextCursor;

  /// The caller's own allowance, from the freshest page.
  final UploadQuota? quota;

  final bool loadingMore;

  /// Upload ids whose transfer failed in this app session; their
  /// source reference is retained so Retry can resume from what the
  /// server received.
  final Set<String> failed;

  bool get hasMore => nextCursor != null;
}

/// Lists upload sessions and drives the create, chunk, complete flow.
class UploadsController extends AsyncNotifier<UploadsState> {
  static const pageSize = 50;

  /// Chunk size for the resumable transfer loop: 1 MiB. Also the most
  /// of any file that sits in memory at once - sources are lazy
  /// references windowed through here.
  static const chunkBytes = 1024 * 1024;

  var _generation = 0;

  @override
  Future<UploadsState> build() async {
    _generation++;
    final page = await ref
        .watch(repositoryProvider)
        .listUploads(limit: pageSize);
    return UploadsState(
      uploads: page.uploads,
      nextCursor: page.nextCursor,
      quota: page.quota,
      failed: {
        for (final id in [
          ...ref.read(_retryPathsProvider).keys,
          ...ref.read(_retryReadersProvider).keys,
        ])
          if (page.uploads.any((u) => u.id == id)) id,
      },
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;
    state = AsyncData(_copy(current, loadingMore: true));
    try {
      final page = await ref
          .read(repositoryProvider)
          .listUploads(cursor: current.nextCursor, limit: pageSize);
      if (generation != _generation) return;
      state = AsyncData(
        UploadsState(
          uploads: [...current.uploads, ...page.uploads],
          nextCursor: page.nextCursor,
          quota: page.quota ?? current.quota,
          failed: current.failed,
        ),
      );
    } on WaxDeckApiException {
      // An expected transport or server error. Keep what we have;
      // scrolling near the end again retries.
      if (generation != _generation) return;
      state = AsyncData(_copy(current, loadingMore: false));
    } catch (_) {
      // Anything else is a defect, not a hiccup: a decode failure,
      // a bad cast. Release the paging guard first - loadingMore is
      // what keeps two fetches from racing, so leaving it set would
      // wedge paging permanently and silently - then let the error
      // reach the app's error handler instead of vanishing here.
      if (generation == _generation) {
        state = AsyncData(_copy(current, loadingMore: false));
      }
      rethrow;
    }
  }

  /// Uploads one picked file, dispatching on how its bytes are
  /// reachable: path-backed sources stream from disk, reader-backed
  /// ones window through their lazy accessor. [batchId] and
  /// [batchPath] join the session to a batch; [identify] is the
  /// submission's identification choice, which a batch overrides with
  /// its own.
  Future<void> uploadPicked(
    PickedAudioFile file, {
    required String mediaType,
    String? libraryPid,
    String? batchId,
    bool? identify,
  }) async {
    final path = file.path;
    if (path != null) {
      await uploadFromPath(
        fileName: file.name,
        path: path,
        mediaType: mediaType,
        libraryPid: libraryPid,
        batchId: batchId,
        batchPath: file.relativeDir,
        sizeBytes: file.size,
        identify: identify,
      );
      return;
    }
    final openRead = file.openRead;
    if (openRead == null) {
      throw StateError('picked file carries neither a path nor a reader');
    }
    await uploadFromReader(
      fileName: file.name,
      size: file.size,
      openRead: openRead,
      mediaType: mediaType,
      libraryPid: libraryPid,
      batchId: batchId,
      batchPath: file.relativeDir,
      identify: identify,
    );
  }

  /// Opens a session for one local file and streams it up in
  /// [chunkBytes] windows read straight from disk, so the file never
  /// sits whole in memory. A transfer failure marks the row failed
  /// and keeps the path for [retry]; the create failure itself
  /// propagates to the caller since no row exists yet. [sizeBytes]
  /// skips a redundant stat when the pick already measured the file.
  Future<void> uploadFromPath({
    required String fileName,
    required String path,
    required String mediaType,
    String? libraryPid,
    String? batchId,
    String? batchPath,
    int? sizeBytes,
    bool? identify,
  }) async {
    final size = sizeBytes ?? await localFileLength(path);
    final session = await ref
        .read(repositoryProvider)
        .createUpload(
          fileName: fileName,
          sizeBytes: size,
          mediaType: mediaType,
          libraryPid: libraryPid,
          batchId: batchId,
          batchPath: _cleanBatchPath(batchId, batchPath),
          identify: identify,
        );
    _upsert(session);
    ref.read(_retryPathsProvider)[session.id] = path;
    await _transferFromPath(session.id, path, size, from: 0);
  }

  /// Opens a session for a reader-backed source (web picks and drops)
  /// and streams it up in [chunkBytes] windows pulled lazily from the
  /// accessor - only the window in flight materializes. Failure
  /// handling matches [uploadFromPath], with the accessor retained
  /// for [retry].
  Future<void> uploadFromReader({
    required String fileName,
    required int size,
    required Stream<List<int>> Function([int? start, int? end]) openRead,
    required String mediaType,
    String? libraryPid,
    String? batchId,
    String? batchPath,
    bool? identify,
  }) async {
    final session = await ref
        .read(repositoryProvider)
        .createUpload(
          fileName: fileName,
          sizeBytes: size,
          mediaType: mediaType,
          libraryPid: libraryPid,
          batchId: batchId,
          batchPath: _cleanBatchPath(batchId, batchPath),
          identify: identify,
        );
    _upsert(session);
    ref.read(_retryReadersProvider)[session.id] = openRead;
    await _transferFromReader(session.id, openRead, size, from: 0);
  }

  /// batchPath only travels with a batch, and an empty hint rides as
  /// absent.
  static String? _cleanBatchPath(String? batchId, String? batchPath) {
    if (batchId == null || batchPath == null || batchPath.isEmpty) return null;
    return batchPath;
  }

  /// Resumes a failed transfer from what the server already received.
  Future<void> retry(String uploadId) async {
    final path = ref.read(_retryPathsProvider)[uploadId];
    if (path != null) {
      final session = await ref.read(repositoryProvider).getUpload(uploadId);
      final size = await localFileLength(path);
      await _transferFromPath(
        uploadId,
        path,
        size,
        from: session.receivedBytes,
      );
      return;
    }
    final openRead = ref.read(_retryReadersProvider)[uploadId];
    if (openRead == null) return;
    final session = await ref.read(repositoryProvider).getUpload(uploadId);
    await _transferFromReader(
      uploadId,
      openRead,
      session.sizeBytes,
      from: session.receivedBytes,
    );
  }

  /// Discards a session and its staged bytes.
  Future<void> discard(String uploadId) async {
    await ref.read(repositoryProvider).deleteUpload(uploadId);
    ref.read(_retryPathsProvider).remove(uploadId);
    ref.read(_retryReadersProvider).remove(uploadId);
    if (!ref.mounted) return;
    ref.invalidateSelf();
  }

  Future<void> _transferFromPath(
    String uploadId,
    String path,
    int size, {
    required int from,
  }) async {
    await _transferWindows(
      uploadId,
      size,
      from: from,
      read: (offset, want) => readLocalFileRange(path, offset, want),
      onSealed: () => ref.read(_retryPathsProvider).remove(uploadId),
    );
  }

  Future<void> _transferFromReader(
    String uploadId,
    Stream<List<int>> Function([int? start, int? end]) openRead,
    int size, {
    required int from,
  }) async {
    await _transferWindows(
      uploadId,
      size,
      from: from,
      read: (offset, want) => _collectRange(openRead, offset, offset + want),
      onSealed: () => ref.read(_retryReadersProvider).remove(uploadId),
    );
  }

  /// The shared transfer loop: reads [chunkBytes] windows from the
  /// source, appends each at its offset, then seals the session.
  Future<void> _transferWindows(
    String uploadId,
    int size, {
    required int from,
    required Future<Uint8List> Function(int offset, int want) read,
    required void Function() onSealed,
  }) async {
    final repository = ref.read(repositoryProvider);
    try {
      var offset = from;
      while (offset < size) {
        final want = (size - offset).clamp(0, chunkBytes);
        final window = await read(offset, want);
        if (window.isEmpty) {
          throw StateError('the picked file shrank mid-upload');
        }
        final session = await repository.putUploadData(
          uploadId,
          offset: offset,
          bytes: window,
        );
        offset += window.length;
        _upsert(session);
      }
      final sealed = await repository.completeUpload(uploadId);
      onSealed();
      _upsert(sealed);
      _markFailed(uploadId, failed: false);
    } catch (_) {
      // Marked failed whatever threw - a server refusal, but also a
      // source that stopped answering (a SAF document moved
      // mid-transfer arrives as a PlatformException, a deleted local
      // file as a FileSystemException, a shrunk one as the StateError
      // above). Without the mark the row sits in "uploading" forever
      // with no Retry.
      _markFailed(uploadId, failed: true);
      rethrow;
    }
  }

  /// Collects one `[start, end)` window from a lazy read accessor.
  static Future<Uint8List> _collectRange(
    Stream<List<int>> Function([int? start, int? end]) openRead,
    int start,
    int end,
  ) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in openRead(start, end)) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  void _upsert(UploadSession session) {
    if (!ref.mounted) return;
    final current = state.value;
    if (current == null) return;
    final present = current.uploads.any((u) => u.id == session.id);
    state = AsyncData(
      UploadsState(
        uploads: present
            ? [
                for (final u in current.uploads)
                  if (u.id == session.id) session else u,
              ]
            : [session, ...current.uploads],
        nextCursor: current.nextCursor,
        quota: current.quota,
        loadingMore: current.loadingMore,
        failed: current.failed,
      ),
    );
  }

  void _markFailed(String uploadId, {required bool failed}) {
    if (!ref.mounted) return;
    final current = state.value;
    if (current == null) return;
    final set = {...current.failed};
    failed ? set.add(uploadId) : set.remove(uploadId);
    state = AsyncData(
      UploadsState(
        uploads: current.uploads,
        nextCursor: current.nextCursor,
        quota: current.quota,
        loadingMore: current.loadingMore,
        failed: set,
      ),
    );
  }

  static UploadsState _copy(UploadsState s, {required bool loadingMore}) =>
      UploadsState(
        uploads: s.uploads,
        nextCursor: s.nextCursor,
        quota: s.quota,
        loadingMore: loadingMore,
        failed: s.failed,
      );
}

final uploadsProvider = AsyncNotifierProvider<UploadsController, UploadsState>(
  UploadsController.new,
);
