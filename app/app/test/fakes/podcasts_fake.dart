import 'dart:async';

import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [PodcastsApi] for `FakeRepository`.
mixin FakePodcasts on FakeRepositoryState implements PodcastsApi {
  /// The same for [getPodcast], which is the show config a session
  /// reads at start. Holding it open is how a test sees whether the
  /// other two reads waited on it.
  Completer<void>? podcastGate;

  /// Held open, an episode listing waits on it: a reload in flight is
  /// what a screen's refresh test is about.
  Completer<void>? listEpisodesGate;

  /// Every show whose episode list was read, in order.
  final List<String> listEpisodesCalls = [];

  /// Held open, an episode's detail read waits on it.
  Completer<void>? getEpisodeGate;

  /// Every episode whose detail was read, in order.
  final List<String> getEpisodeCalls = [];

  /// When set, [subscribePodcast] fails with it (bad feeds in tests).
  WaxDeckApiException? subscribeError;

  /// Cataloged shows by pid, subscribed or not.
  final Map<String, PodcastShow> shows = {};

  /// The caller's subscriptions by show pid.
  final Map<String, Subscription> subscriptions = {};

  /// Full episode details by pid; absent pids derive from the summary.
  final Map<String, EpisodeDetail> episodeDetails = {};

  /// When set, [getEpisodeTranscript] waits for it.
  Completer<void>? getTranscriptGate;

  /// Transcripts by episode pid.
  final Map<String, Transcript> transcripts = {};

  final List<({String url, String? sourceType})> subscribeCalls = [];

  /// Held open, [subscribePodcast] waits on it before answering.
  Completer<void>? subscribeGate;
  final List<String> unsubscribeCalls = [];

  /// Holds [unsubscribePodcast] until completed, with the call recorded.
  Completer<void>? unsubscribeGate;
  final List<String> unsubscribeRemoveDownloadsCalls = [];
  final List<({String pid, SubscriptionSettings settings})>
  putSubscriptionSettingsCalls = [];
  final List<String> fetchEpisodeCalls = [];
  final List<String> captureTranscriptCalls = [];

  /// When set, [captureEpisodeTranscript] fails with it once recorded.
  Object? captureTranscriptError;

  final List<String> removeDownloadCalls = [];

  /// Show pids [getPodcast] was asked for, in order.
  final List<String> getPodcastCalls = [];
  final List<String> importedOpml = [];

  /// What an import answers per feed; empty imports nothing.
  List<OpmlImportOutcome> opmlOutcomes = const [];

  int _subscribeCounter = 0;

  /// The unplayed backlog each show reports, by show pid. Absent means
  /// the field is absent, which is what an older server answers.
  final Map<String, int> unplayedCounts = {};

  /// Registers a show and subscribes the test user to it.
  void addSubscription(
    PodcastShow show, {
    SubscriptionSettings settings = const SubscriptionSettings(),
  }) {
    shows[show.pid] = show;
    subscriptions[show.pid] = Subscription(
      show: show,
      settings: settings,
      subscribedAt: DateTime.utc(2026, 7, 1),
    );
  }

  /// Flips an episode to downloaded, like a completed server-side fetch.
  void completeEpisodeFetch(String pid) {
    for (final entry in episodesByShow.entries) {
      episodesByShow[entry.key] = [
        for (final e in entry.value)
          if (e.pid == pid)
            EpisodeSummary(
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
              downloaded: true,
              explicit: e.explicit,
              hasTranscript: e.hasTranscript,
              hasEnclosure: e.hasEnclosure,
            )
          else
            e,
      ];
    }
  }

  @override
  Future<SubscriptionPage> listSubscriptions({
    String? cursor,
    int? limit,
  }) async {
    final error = listError;
    if (error != null) throw error;
    // Applied on read rather than at registration, so a test can set a
    // count in the same cascade that adds the subscription.
    //
    // All three of the tile's numbers together, because the listing
    // computes them from one walk of the show's episodes: a
    // subscription row carrying a backlog and no size, or a size and no
    // publication date, is a shape the endpoint never sends, and a test
    // built on one would be testing nothing.
    final items = <Subscription>[
      for (final sub in subscriptions.values)
        Subscription(
          show: _countedShow(sub.show),
          settings: sub.settings,
          subscribedAt: sub.subscribedAt,
          unplayedCount:
              unplayedCounts[sub.show.pid] ?? _unplayed(sub.show.pid),
        ),
    ]..sort((a, b) => a.show.title.compareTo(b.show.title));
    return SubscriptionPage(items: items);
  }

  /// The show as a subscription row carries it: with the size and the
  /// newest publication that the counting walk fills in.
  PodcastShow _countedShow(PodcastShow show) {
    final eps = episodesByShow[show.pid] ?? const <EpisodeSummary>[];
    if (eps.isEmpty) return show;
    var latest = eps.first.publishedAt;
    for (final ep in eps) {
      if (ep.publishedAt.isAfter(latest)) latest = ep.publishedAt;
    }
    return PodcastShow(
      pid: show.pid,
      title: show.title,
      author: show.author,
      descriptionHtml: show.descriptionHtml,
      feedUrl: show.feedUrl,
      link: show.link,
      sourceType: show.sourceType,
      artUrl: show.artUrl,
      episodeCount: show.episodeCount ?? eps.length,
      lastPublishedAt: show.lastPublishedAt ?? latest,
      refreshDisabled: show.refreshDisabled,
      explicit: show.explicit,
      funding: show.funding,
      medium: show.medium,
      persons: show.persons,
    );
  }

  int? _unplayed(String showPid) {
    final eps = episodesByShow[showPid];
    if (eps == null) return null;
    return eps.where((e) => !finishedPids.contains(e.pid)).length;
  }

  @override
  Future<Subscription> subscribePodcast({
    required String url,
    String? sourceType,
    String? username,
    String? password,
    String? folder,
  }) async {
    subscribeCalls.add((url: url, sourceType: sourceType));
    await subscribeGate?.future;
    final error = subscribeError;
    if (error != null) throw error;
    // Re-subscribing to a known feed returns the existing subscription.
    for (final sub in subscriptions.values) {
      if (sub.show.feedUrl == url) return sub;
    }
    final existing = shows.values.where((s) => s.feedUrl == url).toList();
    final show = existing.isNotEmpty
        ? existing.first
        : PodcastShow(
            pid: 'pc-SUB${++_subscribeCounter}',
            title: 'Subscribed Show $_subscribeCounter',
            author: 'Some Host',
            sourceType: sourceType ?? 'rss',
            feedUrl: url,
          );
    addSubscription(show);
    return subscriptions[show.pid]!;
  }

  @override
  Future<PodcastDetail> getPodcast(String pid) async {
    getPodcastCalls.add(pid);
    await podcastGate?.future;
    final show = subscriptions[pid]?.show ?? shows[pid];
    if (show == null) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such show',
        statusCode: 404,
      );
    }
    return PodcastDetail(
      show: show,
      subscribed: subscriptions.containsKey(pid),
      settings: subscriptions[pid]?.settings,
    );
  }

  @override
  Future<void> unsubscribePodcast(
    String pid, {
    bool removeDownloads = false,
  }) async {
    unsubscribeCalls.add(pid);
    await unsubscribeGate?.future;
    subscriptions.remove(pid);
    if (!removeDownloads) return;
    unsubscribeRemoveDownloadsCalls.add(pid);
    for (final e in List.of(episodesByShow[pid] ?? const <EpisodeSummary>[])) {
      if (e.downloaded) _markUndownloaded(e.pid);
    }
  }

  /// Holds [putSubscriptionSettings] until completed, with the call
  /// already recorded.
  Completer<void>? putSubscriptionSettingsGate;

  @override
  Future<Subscription> putSubscriptionSettings(
    String pid,
    SubscriptionSettings settings,
  ) async {
    putSubscriptionSettingsCalls.add((pid: pid, settings: settings));
    if (putSubscriptionSettingsGate case final gate?) await gate.future;
    final current = subscriptions[pid];
    if (current == null) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'not subscribed',
        statusCode: 404,
      );
    }
    final updated = Subscription(
      show: current.show,
      settings: settings,
      subscribedAt: current.subscribedAt,
    );
    subscriptions[pid] = updated;
    return updated;
  }

  @override
  Future<EpisodePage> listEpisodes(
    String pid, {
    String? cursor,
    int? limit,
  }) async {
    listEpisodesCalls.add(pid);
    final error = listError;
    if (error != null) throw error;
    await listEpisodesGate?.future;
    final episodes = episodesByShow[pid] ?? const [];
    final start = cursor == null ? 0 : int.parse(cursor);
    final pageSize = limit ?? 100;
    final end = (start + pageSize).clamp(0, episodes.length);
    return EpisodePage(
      items: episodes.sublist(start.clamp(0, episodes.length), end),
      nextCursor: end < episodes.length ? '$end' : null,
    );
  }

  @override
  Future<EpisodeDetail> getEpisode(String pid) async {
    getEpisodeCalls.add(pid);
    await getEpisodeGate?.future;
    final canned = episodeDetails[pid];
    if (canned != null) return canned;
    final summary = findEpisode(pid);
    if (summary == null) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such episode',
        statusCode: 404,
      );
    }
    return EpisodeDetail(
      pid: summary.pid,
      mediaType: summary.mediaType,
      title: summary.title,
      artist: summary.artist,
      album: summary.album,
      durationMs: summary.durationMs,
      artUrl: summary.artUrl,
      showPid: summary.showPid,
      season: summary.season,
      episodeNumber: summary.episodeNumber,
      episodeType: summary.episodeType,
      publishedAt: summary.publishedAt,
      downloaded: summary.downloaded,
      fetchState: summary.fetchState,
      fetchError: summary.fetchError,
      explicit: summary.explicit,
      hasTranscript: summary.hasTranscript,
      hasEnclosure: summary.hasEnclosure,
    );
  }

  @override
  Future<Transcript> getEpisodeTranscript(String pid) async {
    await getTranscriptGate?.future;
    final transcript = transcripts[pid];
    if (transcript == null) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no transcript',
        statusCode: 404,
      );
    }
    return transcript;
  }

  @override
  Future<void> captureEpisodeTranscript(String pid) async {
    captureTranscriptCalls.add(pid);
    final error = captureTranscriptError;
    if (error != null) throw error;
  }

  @override
  Future<void> removeEpisodeDownload(String pid) async {
    removeDownloadCalls.add(pid);
    _markUndownloaded(pid);
  }

  void _markUndownloaded(String pid) => _rewriteEpisode(pid, downloaded: false);

  void _rewriteEpisode(
    String pid, {
    required bool downloaded,
    String? fetchState,
  }) {
    for (final entry in episodesByShow.entries) {
      episodesByShow[entry.key] = [
        for (final e in entry.value)
          if (e.pid == pid)
            EpisodeSummary(
              pid: e.pid,
              mediaType: e.mediaType,
              title: e.title,
              artist: e.artist,
              album: e.album,
              durationMs: e.durationMs,
              sortKey: e.sortKey,
              artUrl: e.artUrl,
              showPid: e.showPid,
              season: e.season,
              episodeNumber: e.episodeNumber,
              episodeType: e.episodeType,
              publishedAt: e.publishedAt,
              downloaded: downloaded,
              fetchState: fetchState,
              // No fetch error: the server pairs one with a failed fetch
              // only, and a queued fetch or a removal clears it.
              explicit: e.explicit,
              hasTranscript: e.hasTranscript,
              hasEnclosure: e.hasEnclosure,
            )
          else
            e,
      ];
    }
  }

  @override
  Future<void> fetchEpisode(String pid) async {
    fetchEpisodeCalls.add(pid);
    _rewriteEpisode(pid, downloaded: false, fetchState: 'queued');
  }

  /// How many new episodes a feed refresh reports, by show pid.
  final Map<String, int> refreshNewEpisodes = {};
  final List<String> refreshPodcastCalls = [];

  final List<SubscribedEpisodes> subscribedEpisodeCalls = [];

  @override
  Future<EpisodePage> listSubscribedEpisodes({
    SubscribedEpisodes filter = SubscribedEpisodes.latest,
    String? cursor,
    int? limit,
  }) async {
    subscribedEpisodeCalls.add(filter);
    final error = listError;
    if (error != null) throw error;
    // Every episode of every subscribed show, filtered and ordered the
    // way the endpoint documents, so a test that sets a position sees
    // the strip the real server would answer.
    final all = <EpisodeSummary>[
      for (final entry in episodesByShow.entries)
        if (subscriptions.containsKey(entry.key)) ...entry.value,
    ];
    final kept = <EpisodeSummary>[
      for (final episode in all)
        if (switch (filter) {
          SubscribedEpisodes.latest => true,
          SubscribedEpisodes.unplayed => !finishedPids.contains(episode.pid),
          SubscribedEpisodes.inProgress =>
            (playPositions[episode.pid] ?? 0) > 0 &&
                !finishedPids.contains(episode.pid),
        })
          episode,
    ]..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    final end = (limit ?? 100).clamp(0, kept.length);
    return EpisodePage(items: kept.sublist(0, end));
  }

  @override
  Future<RefreshResult> refreshPodcast(String pid) async {
    refreshPodcastCalls.add(pid);
    return RefreshResult(newEpisodes: refreshNewEpisodes[pid] ?? 0);
  }

  @override
  Future<String> exportOpml() async => '<opml version="2.0"><body/></opml>';

  @override
  Future<List<OpmlImportOutcome>> importOpml(String opml) async {
    importedOpml.add(opml);
    return opmlOutcomes;
  }

  /// Directory entries served by [searchPodcastDirectory], and the
  /// queries it was asked. Separate from the station directory's: the
  /// podcast chip asks both surfaces, so a shared spy could not say
  /// which one a query reached.
  List<PodcastDirectoryEntry> podcastDirectoryEntries = const [];
  final List<String> podcastDirectoryQueries = [];

  /// Thrown by [searchPodcastDirectory] when set.
  WaxDeckApiException? podcastDirectoryError;

  /// Holds [searchPodcastDirectory] until completed, with the call
  /// recorded.
  Completer<void>? podcastDirectoryGate;

  @override
  Future<List<PodcastDirectoryEntry>> searchPodcastDirectory(
    String query, {
    int? limit,
  }) async {
    podcastDirectoryQueries.add(query);
    if (podcastDirectoryGate case final gate?) await gate.future;
    final error = podcastDirectoryError;
    if (error != null) throw error;
    return podcastDirectoryEntries;
  }
}
