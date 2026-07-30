import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';

/// Lifecycle filter above the review list. Each value maps to a
/// server-side status filter, including `decided` (a pseudo-status for
/// "everything not pending"), so keyset pagination returns full pages
/// and no client-side row hiding is needed.
enum ReviewFilter {
  pending('pending', 'Pending'),
  autoApplied('auto-applied', 'Auto-applied'),
  decided('decided', 'Decided');

  const ReviewFilter(this.status, this.label);

  /// Server-side status filter. 'decided' is a server pseudo-status meaning
  /// "every entry that is not pending", so the queue never pages through a
  /// head of pending entries only to render nothing.
  final String? status;

  final String label;
}

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
      // Anything else is a defect, not a hiccup: a decode failure,
      // a bad cast. Release the paging guard first - loadingMore is
      // what keeps two fetches from racing, so leaving it set would
      // wedge paging permanently and silently - then let the error
      // reach the zone's handler instead of vanishing here.
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

  void _refresh() {
    if (!ref.mounted) return;
    ref.invalidate(reviewQueueProvider);
    ref.invalidate(reviewStatsProvider);
    ref.invalidateSelf();
  }
}

final reviewEntryProvider = AsyncNotifierProvider.autoDispose
    .family<ReviewEntryController, ReviewEntryDetail, String>(
      ReviewEntryController.new,
    );

/// The catalog libraries, for the matching-mode control. Admin-only on
/// the server; a non-admin caller never opens the control that reads it.
final librariesProvider = FutureProvider<List<LibraryInfo>>(
  (ref) => ref.watch(repositoryProvider).listLibraries(),
);

/// One library's matching mode, keyed by pid.
final libraryMatchingProvider =
    AsyncNotifierProvider.family<LibraryMatchingController, String, String>(
      LibraryMatchingController.new,
    );

/// Reads and sets a library's automatic matching behavior.
class LibraryMatchingController extends AsyncNotifier<String> {
  LibraryMatchingController(this.libraryPid);

  final String libraryPid;

  @override
  Future<String> build() =>
      ref.watch(repositoryProvider).getLibraryMatching(libraryPid);

  Future<void> setMode(String mode) async {
    final stored = await ref
        .read(repositoryProvider)
        .setLibraryMatching(libraryPid, mode);
    state = AsyncData(stored);
  }
}
