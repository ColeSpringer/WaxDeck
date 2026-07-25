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
}

final subscriptionsProvider =
    AsyncNotifierProvider<SubscriptionsController, List<Subscription>>(
      SubscriptionsController.new,
    );

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
