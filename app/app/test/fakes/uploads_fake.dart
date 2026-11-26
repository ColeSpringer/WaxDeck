import 'dart:async';
import 'dart:typed_data';

import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [UploadsApi] for `FakeRepository`.
mixin FakeUploads on FakeRepositoryState implements UploadsApi {
  /// Held open, the uploads and tool-task listings wait on theirs, for
  /// the same reason `listItemsGate` exists.
  Completer<void>? listUploadsGate;

  /// Upload sessions by id.
  final Map<String, UploadSession> uploadsById = {};

  /// Thrown by the upload endpoints when set.
  WaxDeckApiException? uploadError;

  /// Runs before each putUploadData, ahead of the [uploadError] check;
  /// tests use it to trip failures at a chosen chunk.
  void Function()? onPutUploadData;

  /// When set, the [putUploadDataGateAt]th chunk (counting from one)
  /// waits on it before it is taken, and [putUploadDataReached] completes
  /// as it arrives: a transfer stood up mid-file.
  Completer<void>? putUploadDataGate;
  int putUploadDataGateAt = 1;
  final putUploadDataReached = Completer<void>();
  var _chunksSeen = 0;

  /// Runs before each createUpload, ahead of the [uploadError] check;
  /// tests use it to fail a chosen file in a multi-file flow.
  void Function(String fileName)? onCreateUpload;

  /// Thrown by createUpload alone, so the session list (and the
  /// allowance it carries) still reads: one file refused, nothing else.
  WaxDeckApiException? createUploadRefusal;

  /// Holds every createUpload until completed, when set.
  Completer<void>? createUploadGate;

  final List<({String uploadId, int offset, int byteCount})>
  putUploadDataCalls = [];
  int _uploadSeq = 0;

  UploadSession _uploadById(String uploadId) {
    final upload = uploadsById[uploadId];
    if (upload == null) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such upload',
        statusCode: 404,
      );
    }
    return upload;
  }

  UploadSession _uploadWith(
    UploadSession u, {
    int? receivedBytes,
    Duration? idle,
    String? state,
  }) => UploadSession(
    id: u.id,
    fileName: u.fileName,
    sizeBytes: u.sizeBytes,
    receivedBytes: receivedBytes ?? u.receivedBytes,
    idle: idle ?? u.idle,
    mediaType: u.mediaType,
    libraryPid: u.libraryPid,
    batchId: u.batchId,
    state: state ?? u.state,
    reviewEntryId: u.reviewEntryId,
    duplicate: u.duplicate,
    uploadedBy: u.uploadedBy,
    createdAt: u.createdAt,
    expiresAt: u.expiresAt,
  );

  /// The quota snapshot every uploads page carries.
  UploadQuota? uploadPageQuota;

  /// The cursor every uploads page answers, so the screen offers more.
  String? uploadsNextCursor;

  /// How many times [listUploads] was asked.
  int listUploadsCalls = 0;

  @override
  Future<UploadPage> listUploads({String? cursor, int? limit}) async {
    listUploadsCalls++;
    final error = uploadError;
    if (error != null) throw error;
    await listUploadsGate?.future;
    return UploadPage(
      uploads: uploadsById.values.toList(),
      nextCursor: uploadsNextCursor,
      quota: uploadPageQuota,
    );
  }

  /// Batches by id, and the member joins each session declared.
  final Map<String, UploadBatch> batchesById = {};
  final List<({String uploadId, String batchId, String? batchPath})>
  batchJoins = [];
  final List<String> completedBatchIds = [];
  int _batchSeq = 0;

  /// The identification choice each create carried, in call order; null
  /// is a submission that said nothing and left the account default.
  final List<bool?> batchIdentifyCalls = [];
  final List<bool?> uploadIdentifyCalls = [];

  /// The accept-best choice each create carried, same shape.
  final List<bool?> batchAcceptBestCalls = [];
  final List<bool?> uploadAcceptBestCalls = [];

  @override
  Future<UploadBatch> createUploadBatch({
    required UploadGrouping grouping,
    required String mediaType,
    String? libraryPid,
    bool? identify,
    bool? acceptBestMatch,
  }) async {
    final error = uploadError;
    if (error != null) throw error;
    batchIdentifyCalls.add(identify);
    batchAcceptBestCalls.add(acceptBestMatch);
    final batch = UploadBatch(
      id: 'ub-FAKE${_batchSeq++}',
      grouping: grouping,
      mediaType: MediaType.values.firstWhere(
        (m) => m.wireName == mediaType,
        orElse: () => MediaType.music,
      ),
      libraryPid: libraryPid,
      state: 'open',
      createdAt: DateTime.utc(2026, 7, 1),
      expiresAt: DateTime.utc(2026, 7, 2),
    );
    batchesById[batch.id] = batch;
    return batch;
  }

  /// Asked to complete, in order, before [completeUploadBatchGate].
  final List<String> completeUploadBatchCalls = [];

  /// Holds [completeUploadBatch] until completed.
  Completer<void>? completeUploadBatchGate;

  @override
  Future<UploadBatch> completeUploadBatch(String batchId) async {
    completeUploadBatchCalls.add(batchId);
    await completeUploadBatchGate?.future;
    final error = uploadError;
    if (error != null) throw error;
    final batch = batchesById[batchId];
    if (batch == null) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such upload batch',
        statusCode: 404,
      );
    }
    completedBatchIds.add(batchId);
    final done = UploadBatch(
      id: batch.id,
      grouping: batch.grouping,
      mediaType: batch.mediaType,
      libraryPid: batch.libraryPid,
      state: 'finalized',
      reviewEntryIds: [
        for (final join in batchJoins)
          if (join.batchId == batchId) 'rv-of-${join.uploadId}',
      ],
      createdAt: batch.createdAt,
      expiresAt: batch.expiresAt,
    );
    batchesById[batchId] = done;
    return done;
  }

  @override
  Future<UploadSession> createUpload({
    required String fileName,
    required int sizeBytes,
    required String mediaType,
    String? libraryPid,
    String? sha256,
    String? batchId,
    String? batchPath,
    bool? identify,
    bool? acceptBestMatch,
  }) async {
    await createUploadGate?.future;
    onCreateUpload?.call(fileName);
    final error = uploadError ?? createUploadRefusal;
    if (error != null) throw error;
    uploadIdentifyCalls.add(identify);
    uploadAcceptBestCalls.add(acceptBestMatch);
    final upload = UploadSession(
      id: 'up-FAKE${_uploadSeq++}',
      fileName: fileName,
      sizeBytes: sizeBytes,
      receivedBytes: 0,
      // Just opened: the server has taken it this moment.
      idle: Duration.zero,
      mediaType: MediaType.values.firstWhere(
        (m) => m.wireName == mediaType,
        orElse: () => MediaType.music,
      ),
      libraryPid: libraryPid,
      batchId: batchId,
      state: 'receiving',
      createdAt: DateTime.utc(2026, 7, 1),
    );
    if (batchId != null) {
      batchJoins.add((
        uploadId: upload.id,
        batchId: batchId,
        batchPath: batchPath,
      ));
    }
    uploadsById[upload.id] = upload;
    return upload;
  }

  /// A refusal [completeUpload] answers after releasing the session,
  /// as the server does for bytes that do not read as audio.
  WaxDeckApiException? completeRefusal;

  /// How many times [getUpload] was asked.
  int getUploadCalls = 0;

  @override
  Future<UploadSession> getUpload(String uploadId) async {
    getUploadCalls++;
    return _uploadById(uploadId);
  }

  /// Holds [deleteUpload] until completed.
  Completer<void>? deleteUploadGate;

  /// Thrown by [deleteUpload] when set.
  WaxDeckApiException? deleteUploadError;

  @override
  Future<void> deleteUpload(String uploadId) async {
    await deleteUploadGate?.future;
    if (deleteUploadError case final error?) throw error;
    uploadsById.remove(uploadId);
  }

  @override
  Future<UploadSession> putUploadData(
    String uploadId, {
    required int offset,
    required Uint8List bytes,
  }) async {
    final gate = putUploadDataGate;
    if (++_chunksSeen == putUploadDataGateAt && gate != null) {
      putUploadDataReached.complete();
      await gate.future;
    }
    onPutUploadData?.call();
    final error = uploadError;
    if (error != null) throw error;
    putUploadDataCalls.add((
      uploadId: uploadId,
      offset: offset,
      byteCount: bytes.length,
    ));
    final updated = _uploadWith(
      _uploadById(uploadId),
      receivedBytes: offset + bytes.length,
      idle: Duration.zero,
    );
    uploadsById[uploadId] = updated;
    return updated;
  }

  final List<
    ({
      String url,
      MediaType mediaType,
      bool? playlist,
      String? format,
      bool? identify,
      bool? acceptBestMatch,
    })
  >
  acquisitionCalls = [];

  /// Holds every createAcquisition until completed, when set.
  Completer<void>? createAcquisitionGate;

  /// What the queued task names, when set: its title, and whether the
  /// link was a `video`, `playlist` or `channel`.
  String? acquireItemTitle;
  String? acquireSource;

  /// Thrown by createAcquisition ahead of everything else, when set: a
  /// failure that is not the server's answer.
  Object? acquireFailure;

  @override
  Future<ToolTask> createAcquisition({
    required String url,
    required MediaType mediaType,
    bool? playlist,
    String? libraryPid,
    String? format,
    bool? identify,
    bool? acceptBestMatch,
  }) async {
    await createAcquisitionGate?.future;
    if (acquireFailure case final failure?) throw failure;
    final error = uploadError;
    if (error != null) throw error;
    acquisitionCalls.add((
      url: url,
      mediaType: mediaType,
      playlist: playlist,
      format: format,
      identify: identify,
      acceptBestMatch: acceptBestMatch,
    ));
    final task = ToolTask(
      id: 'tt-FAKE${toolTaskSeq++}',
      type: 'acquire',
      state: 'queued',
      itemTitle: acquireItemTitle,
      summary: switch (acquireSource) {
        final source? => {'url': url, 'source': source},
        null => null,
      },
      createdAt: DateTime.utc(2026, 7, 1),
    );
    toolTasksById[task.id] = task;
    return task;
  }

  @override
  Future<UploadSession> completeUpload(String uploadId) async {
    final error = uploadError;
    if (error != null) throw error;
    final refusal = completeRefusal;
    if (refusal != null) {
      // The server ends a session whose bytes no retry can mend.
      uploadsById.remove(uploadId);
      throw refusal;
    }
    final upload = _uploadById(uploadId);
    if (upload.receivedBytes < upload.sizeBytes) {
      throw const WaxDeckApiException(
        code: 'conflict',
        message: 'upload incomplete',
        statusCode: 409,
      );
    }
    final updated = _uploadWith(upload, state: 'staged');
    uploadsById[uploadId] = updated;
    return updated;
  }

  /// The libraries the fake server offers as upload targets. Empty is
  /// also what a server too old for the route looks like to a caller.
  final List<UploadTarget> uploadTargets = [];

  /// When set, the targets read throws it, which is a server that has
  /// the route and refused the read.
  WaxDeckApiException? uploadTargetsError;

  @override
  Future<List<UploadTarget>> listUploadTargets() async {
    final error = uploadTargetsError;
    if (error != null) throw error;
    return List.of(uploadTargets);
  }
}
