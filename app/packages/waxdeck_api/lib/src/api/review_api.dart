import '../models.dart';

/// The identification review queue and library matching.
abstract interface class ReviewApi {
  /// `GET /review/queue`: keyset-paginated review entries, optionally
  /// filtered by lifecycle [status].
  Future<ReviewEntryPage> listReviewQueue({
    String? status,
    String? cursor,
    int? limit,
  });

  /// `GET /review/queue/{entryId}`: one entry with its local tracks
  /// and every candidate.
  Future<ReviewEntryDetail> getReviewEntry(String entryId);

  /// `POST /review/queue/{entryId}/decide`: decides one entry.
  /// [action] is `approve`, `as-is`, `unofficial`, `skip`, or
  /// `discard`; `approve` takes [candidateMbid] to pick a candidate
  /// other than the best.
  Future<ReviewDecideResult> decideReviewEntry(
    String entryId, {
    required String action,
    String? candidateMbid,
  });

  /// `POST /review/queue/{entryId}/revert`: undoes a decided entry's
  /// applied metadata and returns it to pending.
  Future<ReviewEntry> revertReviewEntry(String entryId);

  /// `POST /review/queue/{entryId}/identify`: searches again, for the
  /// given values in place of the ones the entry's files claim.
  ///
  /// Replace, not merge: what is passed becomes the whole override, and
  /// passing nothing (or only blanks) clears it and re-runs the plain
  /// derivation.
  Future<ReviewEntry> reidentifyReviewEntry(
    String entryId, {
    String? artist,
    String? album,
    String? title,
  });

  /// `POST /review/decide`: applies one [action] to many entries,
  /// reporting per-entry outcomes instead of failing the batch.
  Future<List<ReviewBulkOutcome>> decideReviewBulk(
    List<String> entryIds, {
    required String action,
  });

  /// `GET /review/stats`: queue counters by lifecycle state.
  Future<ReviewStats> getReviewStats();

  /// `GET /libraries/{pid}/matching`: the library's matching behavior
  /// (mode `auto`, `review`, or `off`, plus the singles auto-apply
  /// switch).
  Future<LibraryMatching> getLibraryMatching(String libraryPid);

  /// `PUT /libraries/{pid}/matching`: replaces the library's matching
  /// behavior whole, returning what is stored. Send every field - an
  /// omitted flag stores its default.
  Future<LibraryMatching> setLibraryMatching(
    String libraryPid,
    LibraryMatching matching,
  );
}
