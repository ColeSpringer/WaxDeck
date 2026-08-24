import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../providers.dart';

/// Lifecycle filter above the review list. Each value is a server-side
/// status, `decided` included, so pages come back full rather than
/// being thinned client-side.
enum ReviewFilter {
  pending('pending'),
  autoApplied('auto-applied'),
  decided('decided');

  const ReviewFilter(this.status);

  /// Server-side status filter. 'decided' is a server pseudo-status meaning
  /// "every entry that is not pending", so the queue never pages through a
  /// head of pending entries only to render nothing.
  final String? status;

  String labelOf(AppLocalizations l10n) => switch (this) {
    ReviewFilter.pending => l10n.reviewFilterPending,
    ReviewFilter.autoApplied => l10n.reviewFilterAutoApplied,
    ReviewFilter.decided => l10n.reviewFilterDecided,
  };
}

/// Where a unit came from, worded. The vocabulary is the server's and
/// open (`api/spec/review.yaml` calls it a string, not an enum), so a
/// token this build has no word for is drawn as it arrived.
String reviewOriginLabel(AppLocalizations l10n, String origin) =>
    switch (origin) {
      'upload' => l10n.reviewOriginUpload,
      'acquisition' => l10n.reviewOriginAcquisition,
      _ => origin,
    };

/// An entry's lifecycle state, worded; open the same way. Every server
/// outcome is here, not only the ones this client can ask for.
String reviewStatusLabel(AppLocalizations l10n, String status) =>
    switch (status) {
      'pending' => l10n.reviewStatusPending,
      'applied' => l10n.reviewStatusApplied,
      'auto-applied' => l10n.reviewStatusAutoApplied,
      'as-is' => l10n.reviewStatusAsIs,
      'unofficial' => l10n.reviewStatusUnofficial,
      'skipped' => l10n.reviewStatusSkipped,
      'discarded' => l10n.reviewStatusDiscarded,
      'reverted' => l10n.reviewStatusReverted,
      _ => status,
    };

class ReviewFilterController extends Notifier<ReviewFilter> {
  @override
  ReviewFilter build() => ReviewFilter.pending;

  void select(ReviewFilter filter) => state = filter;
}

final reviewFilterProvider =
    NotifierProvider<ReviewFilterController, ReviewFilter>(
      ReviewFilterController.new,
    );

/// Accumulated pages of the review queue.
class ReviewQueueState {
  const ReviewQueueState({
    required this.entries,
    this.nextCursor,
    this.loadingMore = false,
    this.loadError = false,
  });

  final List<ReviewEntry> entries;
  final String? nextCursor;
  final bool loadingMore;

  /// True when the last page fetch failed. It flips back to false when the
  /// next fetch starts, so a listener sees each fresh failure as an edge.
  final bool loadError;

  bool get hasMore => nextCursor != null;

  ReviewQueueState copyWith({bool? loadingMore, bool? loadError}) =>
      ReviewQueueState(
        entries: entries,
        nextCursor: nextCursor,
        loadingMore: loadingMore ?? this.loadingMore,
        loadError: loadError ?? this.loadError,
      );
}

/// Pages the review queue with keyset cursors, filtered by lifecycle
/// state. Decisions refetch the queue and the stats so rows and chip
/// counts stay in agreement.
class ReviewQueueController extends AsyncNotifier<ReviewQueueState> {
  static const pageSize = 50;

  /// Bumped by every [build] so an in-flight [loadMore] can tell its
  /// listing was replaced and drop its result.
  var _generation = 0;

  @override
  Future<ReviewQueueState> build() async {
    _generation++;
    final filter = ref.watch(reviewFilterProvider);
    final page = await ref
        .watch(repositoryProvider)
        .listReviewQueue(status: filter.status, limit: pageSize);
    return ReviewQueueState(entries: page.entries, nextCursor: page.nextCursor);
  }

  /// Fetches the next page and appends it. No-op while a fetch is
  /// running or once the last page was reached.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true, loadError: false));
    try {
      final filter = ref.read(reviewFilterProvider);
      final page = await ref
          .read(repositoryProvider)
          .listReviewQueue(
            status: filter.status,
            cursor: current.nextCursor,
            limit: pageSize,
          );
      if (generation != _generation) return;
      state = AsyncData(
        ReviewQueueState(
          entries: [...current.entries, ...page.entries],
          nextCursor: page.nextCursor,
        ),
      );
    } on WaxDeckApiException {
      // An expected transport or server error. Keep what we have;
      // scrolling near the end again retries.
      if (generation != _generation) return;
      // Keep what we have and flag the failure; scrolling near the end again
      // retries, and the screen surfaces a transient notice on the flag.
      state = AsyncData(current.copyWith(loadingMore: false, loadError: true));
    } catch (_) {
      // A defect, not a hiccup. Release the paging guard first or it
      // wedges paging silently, then let the error out.
      if (generation == _generation) {
        state = AsyncData(
          current.copyWith(loadingMore: false, loadError: true),
        );
      }
      rethrow;
    }
  }

  /// Decides one entry and returns the server's warnings.
  Future<List<String>> decide(
    String entryId,
    String action, {
    String? candidateMbid,
  }) async {
    final result = await ref
        .read(repositoryProvider)
        .decideReviewEntry(
          entryId,
          action: action,
          candidateMbid: candidateMbid,
        );
    _refresh();
    return result.warnings;
  }

  /// Applies one action to many entries, reporting per-entry outcomes.
  Future<List<ReviewBulkOutcome>> decideBulk(
    List<String> entryIds,
    String action,
  ) async {
    final outcomes = await ref
        .read(repositoryProvider)
        .decideReviewBulk(entryIds, action: action);
    _refresh();
    return outcomes;
  }

  void _refresh() {
    if (!ref.mounted) return;
    ref.invalidate(reviewStatsProvider);
    // Home's count must move with the decision, not wait for the user
    // stream: deciding the last entry and going home would otherwise
    // leave the banner standing over an empty queue.
    ref.invalidate(pendingReviewCountProvider);
    ref.invalidateSelf();
  }
}

final reviewQueueProvider =
    AsyncNotifierProvider<ReviewQueueController, ReviewQueueState>(
      ReviewQueueController.new,
    );

/// Queue counters for the filter chips.
final reviewStatsProvider = FutureProvider<ReviewStats>(
  (ref) => ref.watch(repositoryProvider).getReviewStats(),
);

/// How many pending entries the caller can see.
///
/// Feeds home's review notice, which says "your additions are waiting
/// here", not the census - the endpoint scopes non-administrators to
/// their own uploads' entries, and an administrator owns the whole
/// queue anyway. An administrator reads the exact figure from the
/// stats (their scope is the server's, and a bulk import would pin a
/// page-length count at 50 while the real number was 900); everybody
/// else counts their own page, capped at its size, which their own
/// uploads rarely reach. Its own read rather than
/// [reviewQueueProvider]: the queue watches the review screen's
/// filter, and home's count must not change meaning when somebody
/// flips that filter to Decided. Rides the user stream (the binder
/// invalidates it) and the decision paths' [_refresh]es, so an upload
/// finishing or a decision landing anywhere moves it. Never retried:
/// it is a decoration that renders as nothing on failure, and the
/// retry ladder would hammer the endpoint from every home mount that
/// cannot read it.
final pendingReviewCountProvider = FutureProvider<int>((ref) async {
  final admin =
      ref.watch(authControllerProvider).value?.user?.roles.contains('admin') ??
      false;
  if (admin) {
    return (await ref.watch(reviewStatsProvider.future)).pending;
  }
  final page = await ref
      .watch(repositoryProvider)
      .listReviewQueue(
        status: 'pending',
        limit: ReviewQueueController.pageSize,
      );
  return page.entries.length;
}, retry: (_, _) => null);

/// Which candidate an entry is decided against. Shared state because
/// two controls read it: the pane's Approve, and the queue's `a` on the
/// row the pane is showing.
class SelectedCandidate extends Notifier<String?> {
  SelectedCandidate(this.entryId);

  final String entryId;

  @override
  String? build() => null;

  void select(String mbid) => state = mbid;
}

final selectedCandidateProvider =
    NotifierProvider.family<SelectedCandidate, String?, String>(
      SelectedCandidate.new,
    );

/// One entry's full detail (tracks and candidates), with the decisions
/// that act on it.
class ReviewEntryController extends AsyncNotifier<ReviewEntryDetail> {
  ReviewEntryController(this.entryId);

  final String entryId;

  @override
  Future<ReviewEntryDetail> build() =>
      ref.watch(repositoryProvider).getReviewEntry(entryId);

  /// Decides this entry and returns the server's warnings; the detail,
  /// the queue, and the stats all refetch.
  Future<List<String>> decide(String action, {String? candidateMbid}) async {
    final result = await ref
        .read(repositoryProvider)
        .decideReviewEntry(
          entryId,
          action: action,
          candidateMbid: candidateMbid,
        );
    _refresh();
    return result.warnings;
  }

  /// Undoes an applied decision and returns the entry to pending.
  Future<void> revert() async {
    await ref.read(repositoryProvider).revertReviewEntry(entryId);
    _refresh();
  }

  /// Searches again, for the given values in place of the ones the
  /// entry's files claim. Passing nothing clears a stored override and
  /// re-runs the plain derivation.
  Future<void> reidentify({
    String? artist,
    String? album,
    String? title,
  }) async {
    await ref
        .read(repositoryProvider)
        .reidentifyReviewEntry(
          entryId,
          artist: artist,
          album: album,
          title: title,
        );
    _refresh();
  }

  void _refresh() {
    if (!ref.mounted) return;
    ref.invalidate(reviewQueueProvider);
    ref.invalidate(reviewStatsProvider);
    // See ReviewQueueController._refresh: home's banner rides these.
    ref.invalidate(pendingReviewCountProvider);
    ref.invalidateSelf();
  }
}

final reviewEntryProvider = AsyncNotifierProvider.autoDispose
    .family<ReviewEntryController, ReviewEntryDetail, String>(
      ReviewEntryController.new,
    );

// The catalog libraries and their matching modes moved to
// `admin/admin_providers.dart` when the console gained a libraries
// screen: the review screen's matching menu is one reader of that state
// and the libraries table is the other, and two declarations of it would
// be two caches disagreeing about what a library is set to.
