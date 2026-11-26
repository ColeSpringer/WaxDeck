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

/// The top-list kinds of one medium, in display order.
List<String> topListKindsFor(StatsMediaType media) => switch (media) {
  StatsMediaType.music => const ['artists', 'albums', 'tracks', 'genres'],
  StatsMediaType.podcast => const ['shows', 'episodes'],
  StatsMediaType.audiobook => const ['books', 'authors'],
  StatsMediaType.radio => const ['stations'],
};

/// The medium every figure, the chart, the heatmap and the top lists
/// count, held for the session like the range.
class StatsMediaController extends Notifier<StatsMediaType> {
  @override
  StatsMediaType build() => StatsMediaType.music;

  void select(StatsMediaType media) => state = media;
}

final statsMediaProvider =
    NotifierProvider<StatsMediaController, StatsMediaType>(
      StatsMediaController.new,
    );

/// Every [bucket]-sized bucket from the first of [buckets] to the last,
/// the ones the wire leaves out (no listening) at zero, so a chart of
/// them spaces its bars in time. Starts are calendar dates, stepped by
/// the calendar: a day, a week (the server's start on a Monday), a month.
List<ListeningBucket> evenBuckets(
  List<ListeningBucket> buckets,
  String bucket,
) {
  if (buckets.length < 2) return buckets;
  final sorted = [...buckets]..sort((a, b) => a.start.compareTo(b.start));
  DateTime step(DateTime d) => switch (bucket) {
    'week' => DateTime.utc(d.year, d.month, d.day + 7),
    'month' => DateTime.utc(d.year, d.month + 1, d.day),
    'day' => DateTime.utc(d.year, d.month, d.day + 1),
    // A size this build does not know draws as the wire has it.
    _ => sorted.last.start.add(const Duration(days: 1)),
  };
  final byStart = {for (final b in sorted) b.start: b};
  final out = <ListeningBucket>[];
  final last = sorted.last.start;
  for (var at = sorted.first.start; !at.isAfter(last); at = step(at)) {
    out.add(
      byStart.remove(at) ?? ListeningBucket(start: at, ms: 0, sessions: 0),
    );
  }
  // A start off the grid still draws, in its place.
  if (byStart.isNotEmpty) {
    out
      ..addAll(byStart.values)
      ..sort((a, b) => a.start.compareTo(b.start));
  }
  return out;
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

/// One medium's aggregated listening, with the medium it was asked for:
/// the answer names no medium, and the one selected moves before the
/// next answer lands.
class MediaListening {
  const MediaListening({required this.media, required this.stats});

  final StatsMediaType media;
  final ListeningStats stats;
}

/// Aggregated listening for the selected medium, range and bucket.
final listeningStatsProvider = FutureProvider<MediaListening>((ref) async {
  // Keyed on the account: the repository moves only with the server.
  ref.watch(signedInAccountProvider);
  final range = ref.watch(statsRangeProvider);
  final bucket = ref.watch(statsBucketProvider);
  final media = ref.watch(statsMediaProvider);
  final stats = await ref
      .watch(repositoryProvider)
      .getListeningStats(range: range, bucket: bucket, mediaType: media);
  return MediaListening(media: media, stats: stats);
});

/// The current year's per-day listening plus streaks.
final listeningHeatmapProvider = FutureProvider<ListeningHeatmap>((ref) {
  ref.watch(signedInAccountProvider);
  final media = ref.watch(statsMediaProvider);
  return ref.watch(repositoryProvider).getListeningHeatmap(mediaType: media);
});

/// Which top list is showing: the medium's first until one is chosen,
/// and the first again whenever the medium changes.
class TopKindController extends Notifier<String> {
  @override
  String build() => topListKindsFor(ref.watch(statsMediaProvider)).first;

  void select(String kind) => state = kind;
}

final topKindProvider = NotifierProvider<TopKindController, String>(
  TopKindController.new,
);

/// The selected top list over the selected range. The kind names its
/// medium, so this watches the kind rather than the medium: a medium
/// change costs one read, with the new medium's kind.
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
