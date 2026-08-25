import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../providers.dart';

/// Whether the signed-in account may curate podcasts.
///
/// The session's `managePodcasts` is the server's *effective* answer
/// (administrators always hold it), so this is the whole gate for
/// podcast-curation affordances - no admin check to compose in.
final canManagePodcastsProvider = Provider<bool>((ref) {
  final user = ref.watch(authControllerProvider).value?.user;
  return user?.managePodcasts ?? false;
});

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

/// What a directory match says under its name: who makes it, what it is
/// about, and how much of it there is, which is how a listener picks
/// between six shows sharing a word in their titles.
String? describePodcastDirectoryEntry(
  AppLocalizations l10n,
  PodcastDirectoryEntry entry,
) {
  final parts = <String>[
    if (entry.author != null && entry.author!.isNotEmpty) entry.author!,
    if (entry.genre != null && entry.genre!.isNotEmpty) entry.genre!,
    if (entry.episodeCount != null && entry.episodeCount! > 0)
      l10n.podcastDirectoryEpisodes(entry.episodeCount!),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// How the hub orders the subscription grid.
enum SubscriptionSort {
  /// Newest episode first: what a listener opening the app wants.
  recent('recent'),
  title('title'),
  added('added');

  const SubscriptionSort(this.name);

  /// The wire-ish handle the menu row selects on. What each order is
  /// called is copy, and lives in the row that draws it.
  final String name;
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
      // a bad cast. Release the paging guard first - loadingMore is
      // what keeps two fetches from racing, so leaving it set would
      // wedge paging permanently and silently - then let the error
      // reach the app's error handler instead of vanishing here.
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
