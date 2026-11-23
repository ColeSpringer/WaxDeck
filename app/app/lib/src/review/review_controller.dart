import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../providers.dart';
import '../sync/catalog_writes.dart';
import '../sync/refresh_in_place.dart';

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
}

/// Pages the review queue with keyset cursors, filtered by lifecycle
/// state. Decisions refetch the queue and the stats so rows and chip
/// counts stay in agreement.
///
/// A refetch is in place: the rows loaded are kept, so a pane open on an
/// entry far down the queue still has its neighbours once it is decided.
class ReviewQueueController extends AsyncNotifier<ReviewQueueState>
    with RefreshedInPlace<ReviewEntry, ReviewQueueState> {
  static const pageSize = 50;

  /// Whether the last page fetch failed.
  var _loadError = false;

  @override
  ProviderBase<Object?> get self => reviewQueueProvider;

  @override
  int get pageRows => pageSize;

  @override
  int? get walkLimit => 1;

  @override
  Object rowKey(ReviewEntry row) => row.id;

  @override
  ReviewQueueState shape(
    PagedRows<ReviewEntry> held, {
    required bool loadingMore,
  }) => ReviewQueueState(
    entries: held.rows,
    nextCursor: held.nextCursor,
    loadingMore: loadingMore,
    loadError: _loadError,
  );

  @override
  void startingOver() => _loadError = false;

  @override
  Future<PagedRows<ReviewEntry>> readRows({
    required int want,
    String? from,
    int? maxPages,
    bool Function()? stop,
  }) {
    final repository = ref.read(repositoryProvider);
    final status = ref.read(reviewFilterProvider).status;
    return walkRows(
      (cursor) async {
        final page = await repository.listReviewQueue(
          status: status,
          cursor: cursor,
          limit: pageSize,
        );
        return (rows: page.entries, nextCursor: page.nextCursor);
      },
      want: want,
      from: from,
      maxPages: maxPages,
      stop: stop,
    );
  }

  @override
  Future<ReviewQueueState> build() {
    // Keyed on the account: the repository moves only with the server,
    // and the next account starts from its own first page. So does
    // another filter.
    final account = ref.watch(signedInAccountProvider);
    final filter = ref.watch(reviewFilterProvider);
    final repository = ref.watch(repositoryProvider);
    return buildInPlace(source: (account, filter, repository));
  }

  /// Fetches the next page and appends it. No-op while a fetch is
  /// running or once the last page was reached. A fetch that fails keeps
  /// the rows and flags the failure, which the screen surfaces as a
  /// transient notice; scrolling near the end again retries.
  Future<void> loadMore() async {
    await loadMoreInPlace(
      started: () => _loadError = false,
      failed: () => _loadError = true,
    );
  }

  /// Decides one entry and returns the server's answer: the entry as
  /// decided, and its warnings.
  Future<ReviewDecideResult> decide(
    String entryId,
    String action, {
    String? candidateMbid,
  }) async {
    final writes = ref.read(catalogWritesProvider);
    final result = await ref
        .read(repositoryProvider)
        .decideReviewEntry(
          entryId,
          action: action,
          candidateMbid: candidateMbid,
        );
    // A decision applied rewrites the items it was about.
    writes.landed();
    _refresh([entryId]);
    return result;
  }

  /// Applies one action to many entries, reporting per-entry outcomes.
  Future<List<ReviewBulkOutcome>> decideBulk(
    List<String> entryIds,
    String action,
  ) async {
    final writes = ref.read(catalogWritesProvider);
    final outcomes = await ref
        .read(repositoryProvider)
        .decideReviewBulk(entryIds, action: action);
    writes.landed();
    _refresh([
      for (final outcome in outcomes)
        if (outcome.ok) outcome.entryId,
    ]);
    return outcomes;
  }

  /// Reads the queue again, and each of [decided]: a pane showing one
  /// draws it decided now rather than once it is moved off.
  void _refresh(List<String> decided) {
    if (!ref.mounted) return;
    for (final id in decided) {
      ref.invalidate(reviewEntryProvider(id));
    }
    ref.invalidate(reviewStatsProvider);
    // Home's count must move with the decision, not wait for the user
    // stream: deciding the last entry and going home would otherwise
    // leave the banner standing over an empty queue.
    ref.invalidate(pendingReviewCountProvider);
    // A decision made here can be on any row loaded.
    owe(CatalogRefresh.loaded);
    ref.invalidateSelf();
  }
}

final reviewQueueProvider =
    AsyncNotifierProvider<ReviewQueueController, ReviewQueueState>(
      ReviewQueueController.new,
    );

/// Queue counters for the filter chips. Keyed on the account, as the
/// queue is.
final reviewStatsProvider = FutureProvider<ReviewStats>((ref) {
  ref.watch(signedInAccountProvider);
  return ref.watch(repositoryProvider).getReviewStats();
}, retry: retryUnlessRefused);

/// How many pending entries the caller can see.
///
/// Feeds home's review notice, which says "your additions are waiting
/// here", not the census: the stats count the caller's own scope, every
/// entry for an administrator and their own uploads' entries for
/// everybody else. Its own read rather than [reviewStatsProvider],
/// which retries: this is a decoration that renders as nothing on
/// failure, and the retry ladder would hammer the endpoint from every
/// home mount that cannot read it. Rides the user stream (the binder
/// invalidates it) and the decision paths' [_refresh]es, so an upload
/// finishing or a decision landing anywhere moves it. Keyed on the
/// account as well: the repository moves only with the server, so a
/// same-server sign-in would otherwise show the last account's count.
final pendingReviewCountProvider = FutureProvider<int>((ref) async {
  ref.watch(signedInAccountProvider);
  return (await ref.watch(repositoryProvider).getReviewStats()).pending;
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

  /// Decides this entry and returns the server's answer; the detail,
  /// the queue, and the stats all refetch.
  Future<ReviewDecideResult> decide(
    String action, {
    String? candidateMbid,
  }) async {
    final writes = ref.read(catalogWritesProvider);
    final result = await ref
        .read(repositoryProvider)
        .decideReviewEntry(
          entryId,
          action: action,
          candidateMbid: candidateMbid,
        );
    writes.landed();
    _refresh();
    return result;
  }

  /// Undoes an applied decision: the metadata it changed is restored and
  /// the entry is marked reverted, which is final.
  Future<void> revert() async {
    final writes = ref.read(catalogWritesProvider);
    await ref.read(repositoryProvider).revertReviewEntry(entryId);
    writes.landed();
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
    // Through the ledger, not the queue's notifier: reading that would
    // build a queue nobody has open.
    ref
        .read(owedDepthsProvider)
        .owe(reviewQueueProvider, CatalogRefresh.loaded);
    ref.invalidate(reviewQueueProvider);
    ref.invalidate(reviewStatsProvider);
    // See ReviewQueueController._refresh: home's banner rides these.
    ref.invalidate(pendingReviewCountProvider);
    ref.invalidateSelf();
  }
}

/// A refusal is final: an entry decided and filed away answers 404, and
/// retrying that would hold the pane on its skeleton for the backoff.
final reviewEntryProvider = AsyncNotifierProvider.autoDispose
    .family<ReviewEntryController, ReviewEntryDetail, String>(
      ReviewEntryController.new,
      retry: retryUnlessRefused,
    );

// The catalog libraries and their matching modes moved to
// `admin/admin_providers.dart` when the console gained a libraries
// screen: the review screen's matching menu is one reader of that state
// and the libraries table is the other, and two declarations of it would
// be two caches disagreeing about what a library is set to.
