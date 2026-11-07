import 'dart:async';

import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [ReviewApi] for `FakeRepository`.
mixin FakeReview on FakeRepositoryState implements ReviewApi {
  /// Full details by entry id; absent ids derive from the entry.
  final Map<String, ReviewEntryDetail> reviewEntryDetails = {};

  /// Thrown by the review endpoints when set.
  WaxDeckApiException? reviewError;

  final List<({String entryId, String action, String? candidateMbid})>
  decideReviewCalls = [];
  final List<String> revertedReviewEntryIds = [];

  /// Matching behavior by library pid; unset libraries answer the
  /// defaults (`auto`, singles off).
  final Map<String, LibraryMatching> matchingModes = {};

  ReviewEntry _reviewEntryById(String entryId) {
    return reviewEntries.firstWhere(
      (e) => e.id == entryId,
      orElse: () => throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such review entry',
        statusCode: 404,
      ),
    );
  }

  ReviewEntry _withStatus(ReviewEntry e, String status) => ReviewEntry(
    id: e.id,
    kind: e.kind,
    status: status,
    mediaType: e.mediaType,
    origin: e.origin,
    title: e.title,
    artist: e.artist,
    trackCount: e.trackCount,
    libraryPid: e.libraryPid,
    uploadedBy: e.uploadedBy,
    identifying: false,
    best: e.best,
    appliedMbid: e.appliedMbid,
    createdAt: e.createdAt,
    decidedAt: status == 'pending' ? null : DateTime.utc(2026, 7, 2),
    decidedBy: status == 'pending' ? null : 'admin',
  );

  static String _statusForAction(String action) => switch (action) {
    'approve' => 'applied',
    'skip' => 'skipped',
    'discard' => 'discarded',
    _ => action,
  };

  /// Holds [listReviewQueue] until completed.
  Completer<void>? reviewQueueGate;

  @override
  Future<ReviewEntryPage> listReviewQueue({
    String? status,
    String? cursor,
    int? limit,
  }) async {
    await reviewQueueGate?.future;
    final error = reviewError;
    if (error != null) throw error;
    // `decided` is the server's pseudo-status: everything not pending.
    final filtered = switch (status) {
      null => reviewEntries,
      'decided' => reviewEntries.where((e) => e.status != 'pending').toList(),
      _ => reviewEntries.where((e) => e.status == status).toList(),
    };
    final start = cursor == null ? 0 : int.parse(cursor);
    final pageSize = limit ?? 50;
    final end = (start + pageSize).clamp(0, filtered.length);
    return ReviewEntryPage(
      entries: filtered.sublist(start.clamp(0, filtered.length), end),
      nextCursor: end < filtered.length ? '$end' : null,
    );
  }

  @override
  Future<ReviewEntryDetail> getReviewEntry(String entryId) async {
    final error = reviewError;
    if (error != null) throw error;
    final canned = reviewEntryDetails[entryId];
    if (canned != null) return canned;
    final e = _reviewEntryById(entryId);
    return ReviewEntryDetail(
      id: e.id,
      kind: e.kind,
      status: e.status,
      mediaType: e.mediaType,
      origin: e.origin,
      title: e.title,
      artist: e.artist,
      trackCount: e.trackCount,
      libraryPid: e.libraryPid,
      uploadedBy: e.uploadedBy,
      identifying: e.identifying,
      best: e.best,
      appliedMbid: e.appliedMbid,
      createdAt: e.createdAt,
      decidedAt: e.decidedAt,
      decidedBy: e.decidedBy,
    );
  }

  ReviewEntry _decide(String entryId, String action) {
    final updated = _withStatus(
      _reviewEntryById(entryId),
      _statusForAction(action),
    );
    reviewEntries = [
      for (final e in reviewEntries)
        if (e.id == entryId) updated else e,
    ];
    return updated;
  }

  @override
  Future<ReviewDecideResult> decideReviewEntry(
    String entryId, {
    required String action,
    String? candidateMbid,
  }) async {
    decideReviewCalls.add((
      entryId: entryId,
      action: action,
      candidateMbid: candidateMbid,
    ));
    final error = reviewError;
    if (error != null) throw error;
    return ReviewDecideResult(entry: _decide(entryId, action));
  }

  @override
  Future<ReviewEntry> revertReviewEntry(String entryId) async {
    final error = reviewError;
    if (error != null) throw error;
    revertedReviewEntryIds.add(entryId);
    final updated = _withStatus(_reviewEntryById(entryId), 'pending');
    reviewEntries = [
      for (final e in reviewEntries)
        if (e.id == entryId) updated else e,
    ];
    return updated;
  }

  /// What each re-identify asked to search for, in call order.
  final List<({String entryId, String? artist, String? album, String? title})>
  reidentifyCalls = [];

  /// Stored by a re-identify instead of what it was sent, for the cases
  /// where the point is the server answering with something else.
  ReviewOverride? reidentifyStoresInstead;

  @override
  Future<ReviewEntry> reidentifyReviewEntry(
    String entryId, {
    String? artist,
    String? album,
    String? title,
  }) async {
    final error = reviewError;
    if (error != null) throw error;
    reidentifyCalls.add((
      entryId: entryId,
      artist: artist,
      album: album,
      title: title,
    ));
    // Stored, as the server does: recording the call alone let the
    // whole mapping be stubbed out with every test still green.
    // `identifying` is left alone - nothing here lowers it again, and a
    // permanent spinner is an animation pumpAndSettle never survives.
    final detail = reviewEntryDetails[entryId];
    String? kept(String? v) =>
        (v == null || v.trim().isEmpty) ? null : v.trim();
    final sent =
        (kept(artist) == null && kept(album) == null && kept(title) == null)
        ? null
        : ReviewOverride(
            artist: kept(artist),
            album: kept(album),
            title: kept(title),
          );
    final override = reidentifyStoresInstead ?? sent;
    if (detail != null) {
      reviewEntryDetails[entryId] = ReviewEntryDetail(
        id: detail.id,
        kind: detail.kind,
        status: detail.status,
        mediaType: detail.mediaType,
        origin: detail.origin,
        title: detail.title,
        artist: detail.artist,
        trackCount: detail.trackCount,
        libraryPid: detail.libraryPid,
        uploadedBy: detail.uploadedBy,
        identifying: detail.identifying,
        best: detail.best,
        appliedMbid: detail.appliedMbid,
        createdAt: detail.createdAt,
        decidedAt: detail.decidedAt,
        decidedBy: detail.decidedBy,
        candidates: detail.candidates,
        tracks: detail.tracks,
        suggested: detail.suggested,
        identifyOverride: override,
      );
    }
    return _reviewEntryById(entryId);
  }

  @override
  Future<List<ReviewBulkOutcome>> decideReviewBulk(
    List<String> entryIds, {
    required String action,
  }) async {
    decideBulkCalls.add((entryIds: entryIds, action: action));
    final error = reviewError;
    if (error != null) throw error;
    return [
      for (final id in entryIds)
        if (bulkOutcomes.remove(id) case final scripted?)
          scripted
        else if (reviewEntries.any((e) => e.id == id))
          ReviewBulkOutcome(entryId: (_decide(id, action)).id, ok: true)
        else
          ReviewBulkOutcome(entryId: id, ok: false, error: 'not-found'),
    ];
  }

  @override
  Future<ReviewStats> getReviewStats() async {
    int count(String status) =>
        reviewEntries.where((e) => e.status == status).length;
    return ReviewStats(
      pending: count('pending'),
      decided: reviewEntries.where((e) => e.status != 'pending').length,
      identifying: reviewEntries.where((e) => e.identifying).length,
      applied: count('applied'),
      autoApplied: count('auto-applied'),
      asIs: count('as-is'),
      unofficial: count('unofficial'),
      skipped: count('skipped'),
      reverted: count('reverted'),
      revertedAutoApplied: 0,
    );
  }

  @override
  Future<LibraryMatching> getLibraryMatching(String libraryPid) async =>
      matchingModes[libraryPid] ?? const LibraryMatching(mode: 'auto');

  @override
  Future<LibraryMatching> setLibraryMatching(
    String libraryPid,
    LibraryMatching matching,
  ) async => matchingModes[libraryPid] = matching;

  /// Every bulk decision sent, in order.
  final decideBulkCalls = <({List<String> entryIds, String action})>[];

  /// One-shot outcomes [decideReviewBulk] answers for these entries in
  /// place of deciding them.
  final bulkOutcomes = <String, ReviewBulkOutcome>{};
}
