import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';

/// Ranges the stats surfaces can aggregate over, in display order.
const statsRanges = ['7d', '30d', '90d', '365d', 'all'];

/// Chart bucket sizes, in display order.
const statsBuckets = ['day', 'week', 'month'];

/// Top-list kinds, in display order.
const topListKinds = ['artists', 'albums', 'genres', 'shows'];

/// Compact listening-time label: hours and minutes once an hour is
/// reached, minutes below that, seconds only under a minute.
String formatListenTime(int ms) {
  final d = Duration(milliseconds: ms);
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m';
  return '${d.inSeconds}s';
}

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
  final range = ref.watch(statsRangeProvider);
  final bucket = ref.watch(statsBucketProvider);
  return ref
      .watch(repositoryProvider)
      .getListeningStats(range: range, bucket: bucket);
});

/// The current year's per-day listening plus streaks.
final listeningHeatmapProvider = FutureProvider<ListeningHeatmap>(
  (ref) => ref.watch(repositoryProvider).getListeningHeatmap(),
);

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
  final kind = ref.watch(topKindProvider);
  final range = ref.watch(statsRangeProvider);
  return ref
      .watch(repositoryProvider)
      .getTopList(kind: kind, range: range, limit: 20);
});

/// One user's recap for one calendar year.
final yearInReviewProvider = FutureProvider.family<YearInReview, int>(
  (ref, year) => ref.watch(repositoryProvider).getYearInReview(year: year),
);

/// The server-wide recap for one calendar year.
final serverYearInReviewProvider =
    FutureProvider.family<ServerYearInReview, int>(
      (ref, year) =>
          ref.watch(repositoryProvider).getServerYearInReview(year: year),
    );

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

  ListenLogState copyWith({bool? loadingMore}) => ListenLogState(
    entries: entries,
    nextCursor: nextCursor,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// Pages the caller's listen log with keyset cursors, newest first.
/// Changing the client filter re-runs [build], starting over from the
/// first page.
class ListenLogController extends AsyncNotifier<ListenLogState> {
  static const pageSize = 50;

  /// Bumped by every [build] so an in-flight [loadMore] can tell its
  /// listing was replaced and drop its result.
  var _generation = 0;

  @override
  Future<ListenLogState> build() async {
    _generation++;
    final client = ref.watch(listenLogClientProvider);
    final page = await ref
        .watch(repositoryProvider)
        .listListenLog(client: client, limit: pageSize);
    return ListenLogState(entries: page.sessions, nextCursor: page.nextCursor);
  }

  /// Fetches the next page and appends it. No-op while a fetch is
  /// running or once the last page was reached.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref
          .read(repositoryProvider)
          .listListenLog(
            client: ref.read(listenLogClientProvider),
            cursor: current.nextCursor,
            limit: pageSize,
          );
      if (generation != _generation) return;
      state = AsyncData(
        ListenLogState(
          entries: [...current.entries, ...page.sessions],
          nextCursor: page.nextCursor,
        ),
      );
    } on WaxDeckApiException {
      if (generation != _generation) return;
      // Keep what we have; scrolling near the end again retries.
      state = AsyncData(current.copyWith(loadingMore: false));
    }
  }
}

final listenLogProvider =
    AsyncNotifierProvider<ListenLogController, ListenLogState>(
      ListenLogController.new,
    );
