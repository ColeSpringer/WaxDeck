import 'dart:typed_data';

import '../models.dart';

/// Upload sessions, batches and targets.
abstract interface class UploadsApi {
  /// `GET /uploads`: keyset-paginated upload sessions visible to the
  /// caller.
  Future<UploadPage> listUploads({String? cursor, int? limit});

  /// `POST /uploads`: opens a resumable upload session. [sha256] lets
  /// the server flag byte-identical duplicates before any transfer.
  /// [batchId] joins the session to an open batch; [batchPath] is the
  /// file's directory relative to the picked folder, the `auto`
  /// grouping's clustering hint. [identify] decides whether the review
  /// entry is matched against MusicBrainz; absent means the account's
  /// own default, and a batch member's value is ignored for the
  /// batch's.
  Future<UploadSession> createUpload({
    required String fileName,
    required int sizeBytes,
    required String mediaType,
    String? libraryPid,
    String? sha256,
    String? batchId,
    String? batchPath,
    bool? identify,
  });

  /// `GET /uploads/targets`: the libraries this caller may name as an
  /// upload's or acquisition's target. Needs upload rights. A server
  /// too old for the route answers 404, which callers degrade to an
  /// empty list: no picker, and the server routes as it always did.
  Future<List<UploadTarget>> listUploadTargets();

  /// `POST /uploads/batches`: opens a batch grouping several sessions
  /// into review units by the declared intent. [identify] decides
  /// identification for every entry the batch opens; absent means the
  /// account's own default.
  Future<UploadBatch> createUploadBatch({
    required UploadGrouping grouping,
    required String mediaType,
    String? libraryPid,
    bool? identify,
  });

  /// `POST /uploads/batches/{batchId}/complete`: finalizes a batch -
  /// members staged so far are grouped and their review entries open.
  /// Idempotent.
  Future<UploadBatch> completeUploadBatch(String batchId);

  /// `GET /uploads/{uploadId}`: one session's progress and state.
  Future<UploadSession> getUpload(String uploadId);

  /// `DELETE /uploads/{uploadId}`: discards a session and its staged
  /// bytes.
  Future<void> deleteUpload(String uploadId);

  /// `PUT /uploads/{uploadId}/data`: appends one chunk at byte
  /// [offset], returning the updated session. Resume by re-reading
  /// the session's receivedBytes and continuing from there.
  Future<UploadSession> putUploadData(
    String uploadId, {
    required int offset,
    required Uint8List bytes,
  });

  /// `POST /uploads/{uploadId}/complete`: seals a fully received
  /// session and hands it to the review pipeline.
  Future<UploadSession> completeUpload(String uploadId);

  /// `POST /acquisitions`: downloads audio from a source URL (a
  /// single video, or a playlist or channel) through the acquisition
  /// bridge as a background task; the files stage like uploads and
  /// flow through the review pipeline. [identify] decides whether the
  /// entries it opens are matched; absent means the account's default.
  Future<ToolTask> createAcquisition({
    required String url,
    required MediaType mediaType,
    String? libraryPid,
    String? format,
    bool? identify,
  });
}
