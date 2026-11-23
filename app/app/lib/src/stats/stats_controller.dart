import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../auth/auth_controller.dart';
import '../providers.dart';
import '../sync/refresh_in_place.dart';

/// Ranges the stats surfaces can aggregate over, in display order.
const statsRanges = ['7d', '30d', '90d', '365d', 'all'];

/// Chart bucket sizes, in display order.
const statsBuckets = ['day', 'week', 'month'];

/// Top-list kinds, in display order.
const topListKinds = ['artists', 'albums', 'genres', 'shows', 'stations'];

/// The range the listening chart and top lists aggregate over.
class StatsRangeController extends Notifier<String> {
  @override
  String build() => '30d';

  void select(String range) => state = range;
}

final statsRangeProvider = NotifierProvider<StatsRangeController, String>(
  StatsRangeController.new,
);

/// The chart bucket size.
class StatsBucketController extends Notifier<String> {
  @override
  String build() => 'day';

  void select(String bucket) => state = bucket;
}

final statsBucketProvider = NotifierProvider<StatsBucketController, String>(
  StatsBucketController.new,
);

/// Aggregated listening for the selected range and bucket.
final listeningStatsProvider = FutureProvider<ListeningStats>((ref) {
  // Keyed on the account: the repository moves only with the server.
  ref.watch(signedInAccountProvider);
  final range = ref.watch(statsRangeProvider);
  final bucket = ref.watch(statsBucketProvider);
  return ref
      .watch(repositoryProvider)
      .getListeningStats(range: range, bucket: bucket);
});

/// The current year's per-day listening plus streaks.
final listeningHeatmapProvider = FutureProvider<ListeningHeatmap>((ref) {
  ref.watch(signedInAccountProvider);
  return ref.watch(repositoryProvider).getListeningHeatmap();
});

/// Which top list is showing.
class TopKindController extends Notifier<String> {
  @override
  String build() => 'artists';

  void select(String kind) => state = kind;
}

final topKindProvider = NotifierProvider<TopKindController, String>(
  TopKindController.new,
);

/// The selected top list over the selected range.
final topListProvider = FutureProvider<TopList>((ref) {
  ref.watch(signedInAccountProvider);
  final kind = ref.watch(topKindProvider);
  final range = ref.watch(statsRangeProvider);
  return ref
      .watch(repositoryProvider)
      .getTopList(kind: kind, range: range, limit: 20);
});

/// One user's recap for one calendar year.
final yearInReviewProvider = FutureProvider.family<YearInReview, int>((
  ref,
  year,
) {
  ref.watch(signedInAccountProvider);
  return ref.watch(repositoryProvider).getYearInReview(year: year);
}, retry: retryUnlessRefused);

/// The server-wide recap for one calendar year, less what the caller's
/// library grants and tag rules hide.
final serverYearInReviewProvider =
    FutureProvider.family<ServerYearInReview, int>((ref, year) {
      ref.watch(signedInAccountProvider);
      return ref.watch(repositoryProvider).getServerYearInReview(year: year);
    }, retry: retryUnlessRefused);

/// The reporting-client filter on the listen log; null shows every
/// client.
class ListenLogClientController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? client) => state = client;
}

final listenLogClientProvider =
    NotifierProvider<ListenLogClientController, String?>(
      ListenLogClientController.new,
    );

/// Accumulated pages of the listen log.
class ListenLogState {
  const ListenLogState({
    required this.entries,
    this.nextCursor,
    this.loadingMore = false,
  });

  final List<ListenLogEntry> entries;
  final String? nextCursor;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;
}

/// Pages the caller's listen log with keyset cursors, newest first, and
/// refreshes it in place: a sweep reads again what is loaded, where the
/// log stands. Changing the client filter starts it over.
class ListenLogController extends AsyncNotifier<ListenLogState>
    with RefreshedInPlace<ListenLogEntry, ListenLogState> {
  static const pageSize = 50;

  @override
  ProviderBase<Object?> get self => listenLogProvider;

  @override
  int get pageRows => pageSize;

  @override
  int? get walkLimit => 1;

  /// One listen, by its own id: two of one item from one start and one
  /// client (an untimed scrobble naming a song twice) are two.
  @override
  Object rowKey(ListenLogEntry row) => row.sessionId;

  @override
  ListenLogState shape(
    PagedRows<ListenLogEntry> held, {
    required bool loadingMore,
  }) => ListenLogState(
    entries: held.rows,
    nextCursor: held.nextCursor,
    loadingMore: loadingMore,
  );

  @override
  Future<PagedRows<ListenLogEntry>> readRows({
    required int want,
    String? from,
    int? maxPages,
    bool Function()? stop,
  }) {
    final repository = ref.read(repositoryProvider);
    final client = ref.read(listenLogClientProvider);
    return walkRows(
      (cursor) async {
        final page = await repository.listListenLog(
          client: client,
          cursor: cursor,
          limit: pageSize,
        );
        return (rows: page.sessions, nextCursor: page.nextCursor);
      },
      want: want,
      from: from,
      maxPages: maxPages,
      stop: stop,
    );
  }

  @override
  Future<ListenLogState> build() {
    final account = ref.watch(signedInAccountProvider);
    final client = ref.watch(listenLogClientProvider);
    final repository = ref.watch(repositoryProvider);
    return buildInPlace(source: (account, repository, client));
  }

  /// Fetches the next page and appends it. No-op while a fetch is
  /// running or once the last page was reached.
  Future<void> loadMore() => loadMoreInPlace();
}

final listenLogProvider =
    AsyncNotifierProvider<ListenLogController, ListenLogState>(
      ListenLogController.new,
      retry: retryUnlessRefused,
    );
