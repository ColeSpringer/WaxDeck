import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';

/// The caller's podcast subscriptions, first page. The subscription list
/// is small (it is the user's own follows), so one generous page covers
/// it; refresh re-fetches from the top.
class SubscriptionsController extends AsyncNotifier<List<Subscription>> {
  static const pageSize = 100;

  @override
  Future<List<Subscription>> build() async {
    final page = await ref
        .watch(repositoryProvider)
        .listSubscriptions(limit: pageSize);
    return page.items;
  }

  /// Subscribes and reloads the list. Errors propagate to the caller so
  /// the dialog can surface the server message (feed-unreachable text
  /// matters to the user).
  Future<Subscription> subscribe({
    required String url,
    String? sourceType,
  }) async {
    final subscription = await ref
        .read(repositoryProvider)
        .subscribePodcast(url: url, sourceType: sourceType);
    ref.invalidateSelf();
    await future;
    return subscription;
  }

  /// Imports an OPML document and reloads, so the shows that resolved
  /// are on screen before the per-feed outcomes are reported.
  Future<void> importOpml(String opml) async {
    await ref.read(repositoryProvider).importOpml(opml);
    ref.invalidateSelf();
    await future;
  }
}

final subscriptionsProvider =
    AsyncNotifierProvider<SubscriptionsController, List<Subscription>>(
      SubscriptionsController.new,
    );

/// How the hub orders the subscription grid.
enum SubscriptionSort {
  /// Newest episode first: what a listener opening the app wants.
  recent('recent', 'Recent'),
  title('title', 'Title'),
  added('added', 'Added');

  const SubscriptionSort(this.name, this.label);

  final String name;
  final String label;
}

/// The chosen order. Screen-local state rather than a stored preference:
/// the settings registry that would own a durable one lands with the
/// settings phase, and a sort nobody can find again is worse than one
/// that resets.
class SubscriptionSortController extends Notifier<SubscriptionSort> {
  @override
  SubscriptionSort build() => SubscriptionSort.recent;

  void select(SubscriptionSort sort) => state = sort;
}

final subscriptionSortProvider =
    NotifierProvider<SubscriptionSortController, SubscriptionSort>(
      SubscriptionSortController.new,
    );

/// The subscriptions in the chosen order.
///
/// Sorted here rather than in the grid so the folder groups and the flat
/// list order the same way, and so a show with no publication date on
/// record still lands somewhere stable (last, by title) instead of
/// wherever a comparator on a null happened to put it.
List<Subscription> sortSubscriptions(
  List<Subscription> items,
  SubscriptionSort sort,
) {
  final sorted = List<Subscription>.of(items);
  int byTitle(Subscription a, Subscription b) =>
      a.show.title.toLowerCase().compareTo(b.show.title.toLowerCase());
  switch (sort) {
    case SubscriptionSort.title:
      sorted.sort(byTitle);
    case SubscriptionSort.added:
      sorted.sort((a, b) {
        final at = b.subscribedAt.compareTo(a.subscribedAt);
        return at != 0 ? at : byTitle(a, b);
      });
    case SubscriptionSort.recent:
      sorted.sort((a, b) {
        final left = a.show.lastPublishedAt;
        final right = b.show.lastPublishedAt;
        if (left == null && right == null) return byTitle(a, b);
        if (left == null) return 1;
        if (right == null) return -1;
        final at = right.compareTo(left);
        return at != 0 ? at : byTitle(a, b);
      });
  }
  return sorted;
}

/// The folders a subscription list declares, in display order, with the
/// shows filed under each. The empty string keys the shows in no folder.
///
/// Folder paths round-trip through OPML outline nesting, so they arrive
/// as `/`-joined segments; the hub groups by the whole path rather than
/// by the first segment, because a two-level folder is a folder the user
/// made and flattening it would merge two of them.
Map<String, List<Subscription>> groupByFolder(List<Subscription> items) {
  final groups = <String, List<Subscription>>{};
  for (final subscription in items) {
    final folder = subscription.settings.folder?.trim() ?? '';
    groups.putIfAbsent(folder, () => <Subscription>[]).add(subscription);
  }
  return groups;
}

/// One show's detail with the caller's subscription state, editable.
class PodcastDetailController extends AsyncNotifier<PodcastDetail> {
  PodcastDetailController(this.pid);

  final String pid;

  @override
  Future<PodcastDetail> build() =>
      ref.watch(repositoryProvider).getPodcast(pid);

  Future<void> subscribe() async {
    final detail = state.value;
    final feedUrl = detail?.show.feedUrl;
    if (feedUrl == null) return;
    final subscription = await ref
        .read(repositoryProvider)
        .subscribePodcast(url: feedUrl, sourceType: detail!.show.sourceType);
    state = AsyncData(
      PodcastDetail(
        show: subscription.show,
        subscribed: true,
        settings: subscription.settings,
      ),
    );
    ref.invalidate(subscriptionsProvider);
  }

  Future<void> unsubscribe({bool removeDownloads = false}) async {
    await ref
        .read(repositoryProvider)
        .unsubscribePodcast(pid, removeDownloads: removeDownloads);
    final detail = state.value;
    if (detail != null) {
      state = AsyncData(PodcastDetail(show: detail.show, subscribed: false));
    }
    ref.invalidate(subscriptionsProvider);
    if (removeDownloads) {
      ref.invalidate(episodesProvider(pid));
    }
  }

  Future<void> saveSettings(SubscriptionSettings settings) async {
    final saved = await ref
        .read(repositoryProvider)
        .putSubscriptionSettings(pid, settings);
    state = AsyncData(
      PodcastDetail(
        show: saved.show,
        subscribed: true,
        settings: saved.settings,
      ),
    );
    ref.invalidate(subscriptionsProvider);
  }
}

final podcastDetailProvider =
    AsyncNotifierProvider.family<
      PodcastDetailController,
      PodcastDetail,
      String
    >(PodcastDetailController.new);

/// Accumulated pages of one show's episode listing.
class EpisodeListState {
  const EpisodeListState({
    required this.items,
    this.nextCursor,
    this.loadingMore = false,
  });

  final List<EpisodeSummary> items;
  final String? nextCursor;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;

  EpisodeListState copyWith({List<EpisodeSummary>? items, bool? loadingMore}) =>
      EpisodeListState(
        items: items ?? this.items,
        nextCursor: nextCursor,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

/// Pages one show's episodes with keyset cursors, mirroring the library
/// controller's load-more-on-scroll pattern.
class EpisodesController extends AsyncNotifier<EpisodeListState> {
  EpisodesController(this.showPid);

  final String showPid;
  static const pageSize = 50;

  /// Bumped by every [build] so an in-flight [loadMore] can tell its
  /// listing was replaced and drop its result.
  var _generation = 0;

  @override
  Future<EpisodeListState> build() async {
    _generation++;
    final page = await ref
        .watch(repositoryProvider)
        .listEpisodes(showPid, limit: pageSize);
    return EpisodeListState(items: page.items, nextCursor: page.nextCursor);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref
          .read(repositoryProvider)
          .listEpisodes(showPid, cursor: current.nextCursor, limit: pageSize);
      if (generation != _generation) return;
      state = AsyncData(
        EpisodeListState(
          items: [...current.items, ...page.items],
          nextCursor: page.nextCursor,
        ),
      );
    } on WaxDeckApiException {
      // An expected transport or server error. Keep what we have;
      // scrolling near the end again retries.
      if (generation != _generation) return;
      state = AsyncData(current.copyWith(loadingMore: false));
    } catch (_) {
      // Anything else is a defect, not a hiccup: a decode failure,
      // a bad cast. Release the paging guard first — loadingMore is
      // what keeps two fetches from racing, so leaving it set would
      // wedge paging permanently and silently — then let the error
      // reach the zone's handler instead of vanishing here.
      if (generation == _generation) {
        state = AsyncData(current.copyWith(loadingMore: false));
      }
      rethrow;
    }
  }

  /// Queues a server-side fetch and optimistically marks the episode
  /// queued; the real state arrives with the next listing refresh.
  Future<void> fetchEpisode(String pid) async {
    await ref.read(repositoryProvider).fetchEpisode(pid);
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        items: [
          for (final e in current.items)
            if (e.pid == pid && !e.downloaded) _asQueued(e) else e,
        ],
      ),
    );
  }

  /// Removes the episode's server download, then refetches the list so
  /// the row reflects the settled server state.
  Future<void> removeEpisodeDownload(String pid) async {
    await ref.read(repositoryProvider).removeEpisodeDownload(pid);
    ref.invalidateSelf();
  }

  static EpisodeSummary _asQueued(EpisodeSummary e) => EpisodeSummary(
    pid: e.pid,
    mediaType: e.mediaType,
    title: e.title,
    artist: e.artist,
    album: e.album,
    durationMs: e.durationMs,
    artUrl: e.artUrl,
    showPid: e.showPid,
    season: e.season,
    episodeNumber: e.episodeNumber,
    episodeType: e.episodeType,
    publishedAt: e.publishedAt,
    downloaded: e.downloaded,
    fetchState: 'queued',
    fetchError: null,
    explicit: e.explicit,
    hasTranscript: e.hasTranscript,
    hasEnclosure: e.hasEnclosure,
  );
}

final episodesProvider =
    AsyncNotifierProvider.family<EpisodesController, EpisodeListState, String>(
      EpisodesController.new,
    );

/// One episode's full detail.
final episodeDetailProvider = FutureProvider.autoDispose
    .family<EpisodeDetail, String>(
      (ref, pid) => ref.watch(repositoryProvider).getEpisode(pid),
    );

/// How far through an episode the caller is, as the rows draw it.
class EpisodeProgress {
  const EpisodeProgress({
    required this.positionMs,
    required this.played,
    required this.finished,
  });

  static const none = EpisodeProgress(
    positionMs: 0,
    played: false,
    finished: false,
  );

  final int positionMs;

  /// Past the server's played threshold, which is what the unplayed dot
  /// reads. Derived server-side from position against duration, so a
  /// speed change or a silence skip cannot distort it.
  final bool played;

  final bool finished;

  /// Started and not finished: the state the resume label and the hub's
  /// Up next strip are about.
  bool get inProgress => positionMs > 0 && !finished;

  /// How far through [durationMs] this is, from 0 to 1, or null when
  /// there is no duration to be a fraction of (a feed that declared
  /// none on an episode nobody has fetched).
  double? fractionOf(int durationMs) {
    if (durationMs <= 0 || positionMs <= 0) return null;
    return (positionMs / durationMs).clamp(0.0, 1.0);
  }
}

/// The caller's play state for a set of episodes, in one batch read.
///
/// Keyed by the pid set rather than held per episode: a listing draws
/// fifty rows and each of them wants a position, and fifty single reads
/// on every page is what the batch endpoint exists to avoid. An absent
/// pid is a zero state, which is what the endpoint means by omitting it.
///
/// The key is one string rather than a list, and that is load-bearing: a
/// family keys its instances by `==`, a `List` has identity equality, and
/// a screen that built its key in `build` would mint a fresh provider on
/// every frame, each one fetching and settling into a rebuild.
/// Callers go through [episodeProgressKey], which sorts and deduplicates
/// so the same rows in a different order are the same read.
class EpisodeProgressController
    extends AsyncNotifier<Map<String, EpisodeProgress>> {
  EpisodeProgressController(this.key);

  /// The sorted, deduplicated pids, joined. Safe as one string because a
  /// pid is a prefixed ULID: the separator cannot occur inside one.
  final String key;

  static const separator = ',';

  List<String> get pids =>
      key.isEmpty ? const <String>[] : key.split(separator);

  /// How many pids one read carries. The endpoint documents pages of
  /// 500; a listing page is fifty, so this only bites where something
  /// accumulated many pages before asking.
  static const batchSize = 500;

  @override
  Future<Map<String, EpisodeProgress>> build() async {
    final all = pids;
    if (all.isEmpty) return const <String, EpisodeProgress>{};
    final repository = ref.watch(repositoryProvider);
    final out = <String, EpisodeProgress>{};
    for (var at = 0; at < all.length; at += batchSize) {
      final slice = all.sublist(at, (at + batchSize).clamp(0, all.length));
      for (final state in await repository.listPlayStates(slice)) {
        out[state.pid] = EpisodeProgress(
          positionMs: state.positionMs,
          played: state.played,
          finished: state.finished,
        );
      }
    }
    return out;
  }

  /// Records [pid] as played by checkpointing at its full duration.
  ///
  /// Played is server-derived from the position reached, so this is the
  /// only way to say it: there is no played flag to set. A zero duration
  /// (a feed that declared none on an unfetched episode) has no position
  /// that means finished, so those are refused rather than checkpointed
  /// at zero, which would read as "not started".
  Future<bool> markPlayed(String pid, int durationMs) async {
    if (durationMs <= 0) return false;
    await ref.read(repositoryProvider).putPlayState(pid, durationMs);
    final current = state.value;
    if (current != null) {
      state = AsyncData(<String, EpisodeProgress>{
        ...current,
        pid: EpisodeProgress(
          positionMs: durationMs,
          played: true,
          finished: true,
        ),
      });
    }
    return true;
  }
}

/// `autoDispose`, because the key is the set of rows on screen: a
/// listing that pages mints a new key per page, and a family that held
/// every one of them would keep a read alive for every page anybody has
/// ever scrolled through.
final episodeProgressProvider = AsyncNotifierProvider.autoDispose
    .family<EpisodeProgressController, Map<String, EpisodeProgress>, String>(
      EpisodeProgressController.new,
    );

/// The progress family's key for [episodes]: sorted, deduplicated, and
/// joined, so the same set of rows in a different order is the same
/// provider rather than a second read of the same pids.
String episodeProgressKey(Iterable<EpisodeSummary> episodes) =>
    episodePidsKey(<String>[for (final episode in episodes) episode.pid]);

/// How many rows one progress read covers.
///
/// The same size the listing pages at, and the two are the same
/// decision: a read keyed by the whole accumulated list would mint a new
/// provider on every page and re-read every pid before it, so the fifth
/// page of a show costs five pages of play states. Windows are stable
/// because the listing only ever appends, so a completed window is
/// answered once and a new page disturbs at most the last one.
const int kEpisodeProgressWindow = EpisodesController.pageSize;

/// The keys covering [loaded], in windows.
List<String> episodeProgressKeys(List<EpisodeSummary> loaded) => <String>[
  for (var at = 0; at < loaded.length; at += kEpisodeProgressWindow)
    episodeProgressKey(
      loaded.sublist(at, (at + kEpisodeProgressWindow).clamp(0, loaded.length)),
    ),
];

/// The same, for a caller holding pids rather than rows.
String episodePidsKey(Iterable<String> pids) =>
    (pids.toSet().toList()..sort()).join(EpisodeProgressController.separator);

/// How far through each of [episodes] the caller is; an episode with no
/// state reads as [EpisodeProgress.none] rather than as missing, so call
/// sites never branch on null.
class EpisodeProgressView {
  const EpisodeProgressView(this._states);

  final Map<String, EpisodeProgress> _states;

  static const empty = EpisodeProgressView(<String, EpisodeProgress>{});

  EpisodeProgress operator [](String pid) =>
      _states[pid] ?? EpisodeProgress.none;
}
