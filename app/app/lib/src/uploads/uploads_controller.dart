import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import 'local_file_reader.dart';

/// Bytes retained for resuming a failed transfer, keyed by upload id.
/// Container-scoped so an event invalidation mid-upload cannot drop the
/// retry buffer with the controller rebuild. Only the byte-backed flow
/// (small picks, web) lands here; path-backed uploads retain the path.
final _retryBytesProvider = Provider<Map<String, Uint8List>>((_) => {});

/// Local file paths retained for resuming a failed path-backed
/// transfer, keyed by upload id. Paths, never bytes: an audiobook-
/// sized share must not live in heap memory for the life of a retry
/// affordance.
final _retryPathsProvider = Provider<Map<String, String>>((_) => {});

/// Accumulated pages of the caller's upload sessions, plus which of
/// them failed locally mid-transfer and can retry.
class UploadsState {
  const UploadsState({
    required this.uploads,
    this.nextCursor,
    this.loadingMore = false,
    this.failed = const {},
  });

  final List<UploadSession> uploads;
  final String? nextCursor;
  final bool loadingMore;

  /// Upload ids whose transfer failed in this app session; their bytes
  /// are retained so Retry can resume from what the server received.
  final Set<String> failed;

  bool get hasMore => nextCursor != null;
}

/// Lists upload sessions and drives the create, chunk, complete flow.
class UploadsController extends AsyncNotifier<UploadsState> {
  static const pageSize = 50;

  /// Chunk size for the resumable transfer loop: 1 MiB.
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
      failed: {
        for (final id in [
          ...ref.read(_retryBytesProvider).keys,
          ...ref.read(_retryPathsProvider).keys,
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
          failed: current.failed,
        ),
      );
    } on WaxDeckApiException {
      if (generation != _generation) return;
      state = AsyncData(_copy(current, loadingMore: false));
    }
  }

  /// Opens a session for one picked file and streams its bytes up in
  /// [chunkBytes] chunks, then seals it. A transfer failure marks the
  /// row failed and keeps the bytes for [retry]; the create failure
  /// itself propagates to the caller since no row exists yet.
  Future<void> upload({
    required String fileName,
    required Uint8List bytes,
    required String mediaType,
  }) async {
    final session = await ref
        .read(repositoryProvider)
        .createUpload(
          fileName: fileName,
          sizeBytes: bytes.length,
          mediaType: mediaType,
        );
    _upsert(session);
    ref.read(_retryBytesProvider)[session.id] = bytes;
    await _transfer(session.id, bytes, from: 0);
  }

  /// Opens a session for one local file and streams it up in
  /// [chunkBytes] windows read straight from disk, so the file never
  /// sits whole in memory. Failure handling matches [upload], with the
  /// path retained for [retry] instead of bytes.
  Future<void> uploadFromPath({
    required String fileName,
    required String path,
    required String mediaType,
  }) async {
    final size = await localFileLength(path);
    final session = await ref
        .read(repositoryProvider)
        .createUpload(
          fileName: fileName,
          sizeBytes: size,
          mediaType: mediaType,
        );
    _upsert(session);
    ref.read(_retryPathsProvider)[session.id] = path;
    await _transferFromPath(session.id, path, size, from: 0);
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
    final bytes = ref.read(_retryBytesProvider)[uploadId];
    if (bytes == null) return;
    final session = await ref.read(repositoryProvider).getUpload(uploadId);
    await _transfer(uploadId, bytes, from: session.receivedBytes);
  }

  /// Discards a session and its staged bytes.
  Future<void> discard(String uploadId) async {
    await ref.read(repositoryProvider).deleteUpload(uploadId);
    ref.read(_retryBytesProvider).remove(uploadId);
    ref.read(_retryPathsProvider).remove(uploadId);
    if (!ref.mounted) return;
    ref.invalidateSelf();
  }

  Future<void> _transferFromPath(
    String uploadId,
    String path,
    int size, {
    required int from,
  }) async {
    final repository = ref.read(repositoryProvider);
    try {
      var offset = from;
      while (offset < size) {
        final want = (size - offset).clamp(0, chunkBytes);
        final window = await readLocalFileRange(path, offset, want);
        if (window.isEmpty) {
          throw StateError('the shared file shrank mid-upload: $path');
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
      ref.read(_retryPathsProvider).remove(uploadId);
      _upsert(sealed);
      _markFailed(uploadId, failed: false);
    } on WaxDeckApiException {
      _markFailed(uploadId, failed: true);
      rethrow;
    }
  }

  Future<void> _transfer(
    String uploadId,
    Uint8List bytes, {
    required int from,
  }) async {
    final repository = ref.read(repositoryProvider);
    final retained = ref.read(_retryBytesProvider);
    try {
      var offset = from;
      while (offset < bytes.length) {
        final end = (offset + chunkBytes).clamp(0, bytes.length);
        final session = await repository.putUploadData(
          uploadId,
          offset: offset,
          bytes: Uint8List.sublistView(bytes, offset, end),
        );
        offset = end;
        _upsert(session);
      }
      final sealed = await repository.completeUpload(uploadId);
      retained.remove(uploadId);
      _upsert(sealed);
      _markFailed(uploadId, failed: false);
    } on WaxDeckApiException {
      _markFailed(uploadId, failed: true);
      rethrow;
    }
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
        loadingMore: current.loadingMore,
        failed: set,
      ),
    );
  }

  static UploadsState _copy(UploadsState s, {required bool loadingMore}) =>
      UploadsState(
        uploads: s.uploads,
        nextCursor: s.nextCursor,
        loadingMore: loadingMore,
        failed: s.failed,
      );
}

final uploadsProvider = AsyncNotifierProvider<UploadsController, UploadsState>(
  UploadsController.new,
);
