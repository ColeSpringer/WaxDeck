import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../providers.dart';
import '../sync/catalog_writes.dart';
import '../sync/refresh_in_place.dart';

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
    ref.watch(signedInAccountProvider);
    final page = await ref
        .watch(repositoryProvider)
        .listSubscriptions(limit: pageSize);
    return page.items;
  }

  /// Subscribes and reloads the list. Errors propagate to the caller so
  /// the dialog can surface the server message (feed-unreachable text
  /// matters to the user). Answers once the subscription lands, without
  /// waiting on the reload: a reload that fails, or sits in its retry
  /// backoff, is the list's to show and never the subscription's.
  Future<Subscription> subscribe({
    required String url,
    String? sourceType,
  }) async {
    final writes = ref.read(catalogWritesProvider);
    final subscription = await ref
        .read(repositoryProvider)
        .subscribePodcast(url: url, sourceType: sourceType);
    // A show and its episodes joined what this account's reads answer.
    writes.landed();
    return subscription;
  }

  /// Imports an OPML document and reloads the list, answering the
  /// per-feed outcomes once the import lands, for the reason [subscribe]
  /// gives: a failed reload never replaces the import's report.
  Future<List<OpmlImportOutcome>> importOpml(String opml) async {
    final writes = ref.read(catalogWritesProvider);
    final outcomes = await ref.read(repositoryProvider).importOpml(opml);
    writes.landed();
    return outcomes;
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

  /// What a write made here was just answered with, for the one build
  /// its landing prompts: see [_landed].
  PodcastDetail? _answered;

  @override
  Future<PodcastDetail> build() async {
    ref.watch(signedInAccountProvider);
    final repository = ref.watch(repositoryProvider);
    final answered = _answered;
    _answered = null;
    return answered ?? await repository.getPodcast(pid);
  }

  Future<void> subscribe() async {
    final detail = state.value;
    final feedUrl = detail?.show.feedUrl;
    if (feedUrl == null) return;
    final writes = ref.read(catalogWritesProvider);
    final subscription = await ref
        .read(repositoryProvider)
        .subscribePodcast(url: feedUrl, sourceType: detail!.show.sourceType);
    _landed(
      writes,
      PodcastDetail(
        show: subscription.show,
        subscribed: true,
        settings: subscription.settings,
      ),
    );
  }

  Future<void> unsubscribe({bool removeDownloads = false}) async {
    final writes = ref.read(catalogWritesProvider);
    await ref
        .read(repositoryProvider)
        .unsubscribePodcast(pid, removeDownloads: removeDownloads);
    // The show left this account's reads, its fetched audio with it when
    // that was asked.
    final detail = ref.mounted ? state.value : null;
    _landed(
      writes,
      detail == null
          ? null
          : PodcastDetail(show: detail.show, subscribed: false),
    );
  }

  /// Says a write made here landed. The sweep that follows reads every
  /// open read of the catalog again, this show among them; [answered] is
  /// what the write was just told the show is, so the build the sweep
  /// prompts answers that and asks the server nothing. Built in this
  /// turn, so the answer can wait for no later build to hand it over
  /// stale.
  void _landed(CatalogWrites writes, PodcastDetail? answered) {
    final here = ref.mounted;
    if (here) _answered = answered;
    try {
      writes.landed();
      if (here && ref.mounted) unawaited(future);
    } finally {
      // Only the build just run may take it, thrown past or not.
      _answered = null;
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
    >(PodcastDetailController.new, retry: retryUnlessRefused);

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
}

/// Pages one show's episodes with keyset cursors, and refreshes them in
/// place: a sweep reads again what is loaded, where the listing stands.
class EpisodesController extends AsyncNotifier<EpisodeListState>
    with RefreshedInPlace<EpisodeSummary, EpisodeListState> {
  EpisodesController(this.showPid);

  final String showPid;
  static const pageSize = 50;

  @override
  ProviderBase<Object?> get self => episodesProvider(showPid);

  @override
  int get pageRows => pageSize;

  @override
  int? get walkLimit => 1;

  @override
  Object rowKey(EpisodeSummary row) => row.pid;

  @override
  EpisodeListState shape(
    PagedRows<EpisodeSummary> held, {
    required bool loadingMore,
  }) => EpisodeListState(
    items: held.rows,
    nextCursor: held.nextCursor,
    loadingMore: loadingMore,
  );

  @override
  Future<PagedRows<EpisodeSummary>> readRows({
    required int want,
    String? from,
    int? maxPages,
    bool Function()? stop,
  }) {
    final repository = ref.read(repositoryProvider);
    return walkRows(
      (cursor) async {
        final page = await repository.listEpisodes(
          showPid,
          cursor: cursor,
          limit: pageSize,
        );
        return (rows: page.items, nextCursor: page.nextCursor);
      },
      want: want,
      from: from,
      maxPages: maxPages,
      stop: stop,
    );
  }

  @override
  Future<EpisodeListState> build() {
    // Keyed on the account: the repository moves only with the server.
    final account = ref.watch(signedInAccountProvider);
    final repository = ref.watch(repositoryProvider);
    return buildInPlace(source: (account, repository));
  }

  /// Fetches the next page and appends it. No-op while a fetch is
  /// running or once the last page was reached.
  Future<void> loadMore() => loadMoreInPlace();

  /// Queues a server-side fetch and marks the episode queued where it
  /// sits; the real state arrives with the next listing refresh.
  Future<void> fetchEpisode(String pid) async {
    await ref.read(repositoryProvider).fetchEpisode(pid);
    amendInPlace((e) => e.pid == pid && !e.downloaded ? _asQueued(e) : e);
  }

  /// Removes the episode's server download and says it landed, so this
  /// list and every other read that draws the episode is read again.
  Future<void> removeEpisodeDownload(String pid) async {
    final writes = ref.read(catalogWritesProvider);
    await ref.read(repositoryProvider).removeEpisodeDownload(pid);
    writes.landed();
  }

  static EpisodeSummary _asQueued(EpisodeSummary e) =>
      e.copyWith(fetchState: () => 'queued', fetchError: () => null);
}

final episodesProvider =
    AsyncNotifierProvider.family<EpisodesController, EpisodeListState, String>(
      EpisodesController.new,
      retry: retryUnlessRefused,
    );

/// One episode's full detail.
final episodeDetailProvider = FutureProvider.autoDispose
    .family<EpisodeDetail, String>(
      (ref, pid) => ref.watch(repositoryProvider).getEpisode(pid),
      retry: retryUnlessRefused,
    );
