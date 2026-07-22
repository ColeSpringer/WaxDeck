import 'dart:typed_data';

import 'package:waxdeck_api/waxdeck_api.dart';

/// In-memory repository for widget tests. Pagination uses the item index as
/// the cursor, which is enough to exercise keyset-style paging end to end.
class FakeRepository implements WaxDeckRepository {
  FakeRepository({
    SessionState? sessionState,
    List<ItemSummary> items = const [],
    this.recentlyPlayed,
    this.bootstrapNeeded = false,
    List<DeviceSession> sessions = const [],
    List<OidcProvider> providers = const [],
  }) : sessionState = sessionState ?? const SessionState(authenticated: false),
       libraryItems = List.of(items),
       deviceSessions = List.of(sessions),
       ssoProviders = List.of(providers);

  SessionState sessionState;
  List<ItemSummary> libraryItems;

  /// Item surfaced by the recently-played browse list, if any.
  ItemSummary? recentlyPlayed;

  /// Whether the server still needs its first administrator.
  bool bootstrapNeeded;

  /// The device list served by [listSessions].
  List<DeviceSession> deviceSessions;

  /// SSO providers served by [oidcProviders].
  List<OidcProvider> ssoProviders;

  @override
  String? authToken;

  /// Saved resume positions by pid.
  final Map<String, int> playPositions = {};

  /// Star and rating state by pid.
  final Map<String, bool> starredByPid = {};
  final Map<String, int?> ratingByPid = {};

  /// Stored preferences, served and replaced by the prefs endpoints.
  Prefs prefs = const Prefs();

  /// Thrown by [login] when set, to exercise the error path.
  WaxDeckApiException? loginError;

  /// Thrown by [bootstrap] when set, to exercise the error path.
  WaxDeckApiException? bootstrapError;

  /// Thrown by [reportListens] when set, to exercise the retry path.
  WaxDeckApiException? reportError;

  /// Thrown by [refreshToken] when set, to exercise rotation failures.
  WaxDeckApiException? refreshError;

  /// Thrown by [setStar] and [setRating] when set, before any state
  /// changes, to exercise the optimistic rollback path.
  WaxDeckApiException? playStateError;

  /// When set, listing calls fail with it (a dead network in tests).
  WaxDeckApiException? listError;

  /// When set, play-info resolution fails with it.
  WaxDeckApiException? playInfoError;

  /// When set, position checkpoints fail with it.
  WaxDeckApiException? putPlayStateError;

  /// When set, [subscribePodcast] fails with it (bad feeds in tests).
  WaxDeckApiException? subscribeError;

  /// Cataloged shows by pid, subscribed or not.
  final Map<String, PodcastShow> shows = {};

  /// The caller's subscriptions by show pid.
  final Map<String, Subscription> subscriptions = {};

  /// Episodes per show pid, newest first.
  final Map<String, List<EpisodeSummary>> episodesByShow = {};

  /// Full episode details by pid; absent pids derive from the summary.
  final Map<String, EpisodeDetail> episodeDetails = {};

  /// Transcripts by episode pid.
  final Map<String, Transcript> transcripts = {};

  /// Audiobooks by pid.
  final Map<String, BookDetail> books = {};

  /// Stored per-book settings by pid; falls back to the book's own.
  final Map<String, BookSettings> storedBookSettings = {};

  /// Resume points by book pid; falls back to [playPositions].
  final Map<String, BookResume> bookResumes = {};

  /// Skip maps by pid (single file) or 'pid#partIndex' (book parts).
  final Map<String, SkipMap> skipMaps = {};

  final List<({String username, String password, String? deviceName})>
  loginCalls = [];
  final List<({String username, String password, String? displayName})>
  bootstrapCalls = [];
  final List<({String code, String? verifier, String? deviceName})>
  oidcExchangeCalls = [];
  final List<String> revokedSessionIds = [];
  final List<({String pid, int positionMs})> putPlayStateCalls = [];
  final List<ListenSession> reportedSessions = [];
  final List<({String url, String? sourceType})> subscribeCalls = [];
  final List<String> unsubscribeCalls = [];
  final List<String> unsubscribeRemoveDownloadsCalls = [];
  final List<({String pid, SubscriptionSettings settings})>
  putSubscriptionSettingsCalls = [];
  final List<String> fetchEpisodeCalls = [];
  final List<
    ({String endpointId, List<String> itemPids, int index, int positionMs})
  >
  createPlaybackSessionCalls = [];
  final List<({String sessionId, String endpointId})>
  transferPlaybackSessionCalls = [];
  final List<String> deletePlaybackSessionCalls = [];
  List<PlayerEndpoint> playerEndpoints = [];
  List<PlaybackSessionInfo> playbackSessions = [];
  final List<String> removeDownloadCalls = [];
  final List<({String pid, BookSettings settings})> putBookSettingsCalls = [];
  final List<({String pid, int? positionMs})> playInfoCalls = [];
  final List<String> importedOpml = [];
  int refreshCalls = 0;
  int _subscribeCounter = 0;

  static const _user = WaxDeckUser(
    id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
    username: 'admin',
    roles: ['admin'],
  );

  LoginResult _signIn({WaxDeckUser user = _user, String token = 'test-token'}) {
    sessionState = SessionState(authenticated: true, user: user);
    authToken = token;
    return LoginResult(user: user, token: token);
  }

  @override
  Future<ServerHealth> health() async =>
      const ServerHealth(status: 'ok', version: 'test', apiVersion: 1);

  @override
  Future<BootstrapStatus> bootstrapStatus() async => BootstrapStatus(
    required: bootstrapNeeded,
    signupEnabled: adminSettings.signupEnabled,
  );

  @override
  Future<LoginResult> bootstrap({
    required String username,
    required String password,
    String? displayName,
  }) async {
    bootstrapCalls.add((
      username: username,
      password: password,
      displayName: displayName,
    ));
    final error = bootstrapError;
    if (error != null) throw error;
    bootstrapNeeded = false;
    return _signIn(
      user: WaxDeckUser(
        id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
        username: username,
        displayName: displayName,
        roles: const ['admin'],
      ),
    );
  }

  @override
  Future<LoginResult> login({
    required String username,
    required String password,
    String? deviceName,
  }) async {
    loginCalls.add((
      username: username,
      password: password,
      deviceName: deviceName,
    ));
    final error = loginError;
    if (error != null) throw error;
    return _signIn();
  }

  @override
  Future<SessionState> getSession() async => sessionState;

  @override
  Future<LoginResult> refreshToken() async {
    refreshCalls++;
    final error = refreshError;
    if (error != null) throw error;
    return _signIn(token: 'rotated-token');
  }

  @override
  Future<void> logout() async {
    sessionState = const SessionState(authenticated: false);
    authToken = null;
  }

  @override
  Future<List<DeviceSession>> listSessions() async => List.of(deviceSessions);

  @override
  Future<void> revokeSession(String sessionId) async {
    revokedSessionIds.add(sessionId);
    deviceSessions.removeWhere((s) => s.id == sessionId);
  }

  @override
  Future<List<OidcProvider>> oidcProviders() async => List.of(ssoProviders);

  @override
  Future<LoginResult> oidcExchange({
    required String code,
    String? verifier,
    String? deviceName,
  }) async {
    oidcExchangeCalls.add((
      code: code,
      verifier: verifier,
      deviceName: deviceName,
    ));
    return _signIn(token: 'oidc-token');
  }

  @override
  Future<ItemPage> listItems({
    MediaType? mediaType,
    String? cursor,
    int? limit,
  }) async {
    final error = listError;
    if (error != null) throw error;
    final filtered = mediaType == null
        ? libraryItems
        : libraryItems.where((i) => i.mediaType == mediaType).toList();
    final start = cursor == null ? 0 : int.parse(cursor);
    final pageSize = limit ?? 100;
    final end = (start + pageSize).clamp(0, filtered.length);
    return ItemPage(
      items: filtered.sublist(start.clamp(0, filtered.length), end),
      nextCursor: end < filtered.length ? '$end' : null,
    );
  }

  @override
  Future<ItemPage> browse(
    DiscoveryList list, {
    String? cursor,
    int? limit,
    int? seed,
  }) async {
    if (list == DiscoveryList.recentlyPlayed) {
      final item = recentlyPlayed;
      return ItemPage(items: item == null ? const [] : [item]);
    }
    return listItems(cursor: cursor, limit: limit);
  }

  @override
  Future<SearchResults> search(String q, {int? limit}) async =>
      SearchResults(query: q);

  @override
  Future<ItemDetail> getItem(String pid) async {
    final item = libraryItems.firstWhere((i) => i.pid == pid);
    return ItemDetail(
      pid: item.pid,
      mediaType: item.mediaType,
      title: item.title,
      artist: item.artist,
      album: item.album,
      durationMs: item.durationMs,
      artUrl: item.artUrl,
    );
  }

  @override
  Future<PlayInfo> getPlayInfo(
    String pid, {
    int? positionMs,
    bool? voiceBoost,
  }) async {
    final error = playInfoError;
    if (error != null) throw error;
    playInfoCalls.add((pid: pid, positionMs: positionMs));
    final episode = _findEpisode(pid);
    if (episode != null && !episode.downloaded) {
      throw const WaxDeckApiException(
        code: 'conflict',
        message: 'episode audio not fetched yet',
        statusCode: 409,
      );
    }
    final book = books[pid];
    if (book != null && book.parts.isNotEmpty) {
      final parts = book.parts;
      var part = parts.first;
      for (final p in parts) {
        if ((positionMs ?? 0) >= p.startMs) part = p;
      }
      return PlayInfo(
        pid: pid,
        url: '/media/stream?pid=$pid&part=${part.index}&mt=test-token',
        mimeType: 'audio/mp4',
        durationMs: part.durationMs,
        seekable: true,
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
        partIndex: part.index,
        partCount: parts.length,
        partStartMs: part.startMs,
      );
    }
    final span = playInfoSpans[pid];
    return PlayInfo(
      pid: pid,
      url: '/media/stream?pid=$pid&mt=test-token',
      mimeType: 'audio/flac',
      durationMs: episode?.durationMs ?? 214000,
      seekable: true,
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
      spanStartMs: span?.startMs,
      spanEndMs: span?.endMs,
    );
  }

  /// Span windows served by [getPlayInfo], keyed by pid: the direct
  /// playback shape for tracks carved out of a larger file.
  final Map<String, ({int startMs, int endMs})> playInfoSpans = {};

  EpisodeSummary? _findEpisode(String pid) {
    for (final episodes in episodesByShow.values) {
      for (final episode in episodes) {
        if (episode.pid == pid) return episode;
      }
    }
    return null;
  }

  @override
  Future<PlayState> getPlayState(String pid) async => PlayState(
    pid: pid,
    positionMs: playPositions[pid] ?? 0,
    played: false,
    finished: false,
    playCount: 0,
    starred: starredByPid[pid] ?? false,
    rating: ratingByPid[pid],
  );

  @override
  Future<void> putPlayState(
    String pid,
    int positionMs, {
    DateTime? recordedAt,
  }) async {
    final error = putPlayStateError;
    if (error != null) throw error;
    putPlayStateCalls.add((pid: pid, positionMs: positionMs));
    playPositions[pid] = positionMs;
  }

  /// When set, [setStar] and [setRating] wait on it before applying,
  /// so tests can hold a mutation in flight while they race something
  /// against it (a provider invalidation, another mutation).
  Future<void>? mutationGate;

  @override
  Future<PlayState> setStar(
    String pid,
    bool starred, {
    DateTime? recordedAt,
  }) async {
    await (mutationGate ?? Future<void>.value());
    final error = playStateError;
    if (error != null) return _failLikeANetwork(error);
    starredByPid[pid] = starred;
    return getPlayState(pid);
  }

  @override
  Future<PlayState> setRating(
    String pid,
    int? rating, {
    DateTime? recordedAt,
  }) async {
    await (mutationGate ?? Future<void>.value());
    final error = playStateError;
    if (error != null) return _failLikeANetwork(error);
    ratingByPid[pid] = rating;
    return getPlayState(pid);
  }

  @override
  Future<List<PlayState>> listPlayStates(List<String> pids) async {
    return [for (final pid in pids) await getPlayState(pid)];
  }

  @override
  Future<CatalogSyncPage> syncCatalog({
    String? since,
    String? cursor,
    int? limit,
  }) async {
    return CatalogSyncPage(
      entries: [
        for (final item in libraryItems)
          CatalogSyncEntry(op: 'upsert', pid: item.pid, item: item),
      ],
      nextSince: 'fake-catalog-cursor',
    );
  }

  @override
  Future<ServerSyncPage> syncServer({String? since, int? limit}) async {
    return const ServerSyncPage(nextSince: 'fake-server-cursor');
  }

  @override
  Future<DownloadInfo> getDownloadInfo(String pid) async {
    return DownloadInfo(
      pid: pid,
      files: [
        DownloadFileInfo(
          url: '/media/download?pid=$pid&mt=test-token',
          mimeType: 'audio/flac',
          sizeBytes: 1024,
          fileName: '$pid.flac',
          essenceHash: 'essence-$pid',
          etag: '1024-1',
        ),
      ],
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );
  }

  @override
  Future<List<AppPassword>> listAppPasswords() async => List.of(appPasswords);

  /// App passwords created through the fake, served by the listing.
  final List<AppPassword> appPasswords = [];

  @override
  Future<AppPasswordCreated> createAppPassword(String label) async {
    final created = AppPasswordCreated(
      id: 'ap-FAKE${appPasswords.length}',
      label: label,
      createdAt: DateTime.now().toUtc(),
      secret: 'FAKESECRETFAKESECRETFAKESE',
    );
    appPasswords.add(created);
    return created;
  }

  @override
  Future<void> revokeAppPassword(String id) async {
    appPasswords.removeWhere((ap) => ap.id == id);
  }

  // A beat of latency before the failure, so tests can observe the
  // optimistic frame a real network round trip would leave on screen.
  static Future<PlayState> _failLikeANetwork(WaxDeckApiException error) =>
      Future<PlayState>.delayed(
        const Duration(milliseconds: 10),
        () => throw error,
      );

  @override
  Future<ListenOutcome> reportListens(List<ListenSession> sessions) async {
    final error = reportError;
    if (error != null) throw error;
    reportedSessions.addAll(sessions);
    return ListenOutcome(accepted: sessions.length, duplicates: 0);
  }

  @override
  Future<Prefs> getPrefs() async => prefs;

  /// Thrown by [putPrefs] when set, to exercise validation feedback
  /// (a rejected timezone, for instance).
  WaxDeckApiException? putPrefsError;

  @override
  Future<Prefs> putPrefs(Prefs next) async {
    final error = putPrefsError;
    if (error != null) throw error;
    return prefs = next;
  }

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
    final items = subscriptions.values.toList()
      ..sort((a, b) => a.show.title.compareTo(b.show.title));
    return SubscriptionPage(items: items);
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
    subscriptions.remove(pid);
    if (!removeDownloads) return;
    unsubscribeRemoveDownloadsCalls.add(pid);
    for (final e in List.of(episodesByShow[pid] ?? const <EpisodeSummary>[])) {
      if (e.downloaded) _markUndownloaded(e.pid);
    }
  }

  @override
  Future<Subscription> putSubscriptionSettings(
    String pid,
    SubscriptionSettings settings,
  ) async {
    putSubscriptionSettingsCalls.add((pid: pid, settings: settings));
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
    final error = listError;
    if (error != null) throw error;
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
    final canned = episodeDetails[pid];
    if (canned != null) return canned;
    final summary = _findEpisode(pid);
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
    );
  }

  @override
  Future<Transcript> getEpisodeTranscript(String pid) async {
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
  Future<void> removeEpisodeDownload(String pid) async {
    removeDownloadCalls.add(pid);
    _markUndownloaded(pid);
  }

  void _markUndownloaded(String pid) {
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
              downloaded: false,
              explicit: e.explicit,
              hasTranscript: e.hasTranscript,
            )
          else
            e,
      ];
    }
  }

  @override
  Future<void> fetchEpisode(String pid) async {
    fetchEpisodeCalls.add(pid);
  }

  @override
  Future<BookDetail> getBook(String pid) async {
    final book = books[pid];
    if (book == null) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such book',
        statusCode: 404,
      );
    }
    final settings = storedBookSettings[pid] ?? book.settings;
    return BookDetail(
      pid: book.pid,
      title: book.title,
      subtitle: book.subtitle,
      authors: book.authors,
      narrators: book.narrators,
      series: book.series,
      seriesSequence: book.seriesSequence,
      publisher: book.publisher,
      asin: book.asin,
      isbn: book.isbn,
      edition: book.edition,
      abridged: book.abridged,
      descriptionHtml: book.descriptionHtml,
      durationMs: book.durationMs,
      artUrl: book.artUrl,
      chapters: book.chapters,
      parts: book.parts,
      settings: settings,
    );
  }

  @override
  Future<BookResume> getBookResume(String pid) async {
    return bookResumes[pid] ?? BookResume(positionMs: playPositions[pid] ?? 0);
  }

  @override
  Future<BookSettings> putBookSettings(
    String pid,
    BookSettings settings,
  ) async {
    putBookSettingsCalls.add((pid: pid, settings: settings));
    storedBookSettings[pid] = settings;
    return settings;
  }

  @override
  Future<SkipMap> getSkipMap(String pid, {int? partIndex}) async {
    final keyed = partIndex == null ? null : skipMaps['$pid#$partIndex'];
    return keyed ?? skipMaps[pid] ?? const SkipMap(state: 'unavailable');
  }

  @override
  Future<String> exportOpml() async => '<opml version="2.0"><body/></opml>';

  @override
  Future<void> importOpml(String opml) async {
    importedOpml.add(opml);
  }

  /// Playlists by pid, with static members alongside.
  final Map<String, Playlist> playlistsByPid = {};
  final Map<String, List<String>> playlistMembers = {};

  /// Preview served by [previewSmartRule]; tests seed it.
  PlaylistPreview previewResult = const PlaylistPreview(items: [], total: 0);

  /// Rule vocabulary served by [getRuleFields].
  RuleFields ruleFields = const RuleFields(
    fields: [
      RuleField(
        name: 'title',
        kind: 'text',
        ops: [
          'is',
          'isNot',
          'contains',
          'startsWith',
          'endsWith',
          'isPresent',
          'isMissing',
        ],
        userState: false,
        sortable: true,
      ),
      RuleField(
        name: 'rating',
        kind: 'number',
        ops: [
          'is',
          'isNot',
          'gt',
          'lt',
          'gte',
          'lte',
          'inTheRange',
          'isPresent',
          'isMissing',
        ],
        userState: true,
        sortable: true,
      ),
      RuleField(
        name: 'starred',
        kind: 'boolean',
        ops: ['is'],
        userState: true,
        sortable: true,
      ),
      RuleField(
        name: 'mediaType',
        kind: 'mediaType',
        ops: ['is', 'isNot'],
        userState: false,
        sortable: false,
      ),
    ],
    tagKeys: [RuleTagKey(key: 'MOOD', itemCount: 3)],
  );

  int _playlistSeq = 0;

  ItemSummary _itemByPid(String pid) {
    return libraryItems.firstWhere(
      (i) => i.pid == pid,
      orElse: () => throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such item',
      ),
    );
  }

  @override
  Future<PlaylistPage> listPlaylists({
    String? cursor,
    int? limit,
    String? containsItem,
  }) async {
    var rows = playlistsByPid.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (containsItem != null) {
      rows = rows
          .where(
            (p) =>
                !p.isSmart &&
                (playlistMembers[p.pid] ?? const []).contains(containsItem),
          )
          .toList();
    }
    return PlaylistPage(playlists: rows);
  }

  @override
  Future<Playlist> createPlaylist({
    required String name,
    required String kind,
    String? visibility,
    SmartRule? rule,
    List<String> itemPids = const [],
  }) async {
    final pid = 'pl-FAKE${_playlistSeq++}';
    final pl = Playlist(
      pid: pid,
      name: name,
      kind: kind,
      visibility: visibility ?? 'private',
      ownerName: 'me',
      isOwner: true,
      itemCount: kind == 'static' ? itemPids.length : null,
      rule: rule,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    playlistsByPid[pid] = pl;
    playlistMembers[pid] = List.of(itemPids);
    return pl;
  }

  @override
  Future<Playlist> getPlaylist(String pid) async {
    final pl = playlistsByPid[pid];
    if (pl == null) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such playlist',
      );
    }
    return pl;
  }

  @override
  Future<Playlist> updatePlaylist(
    String pid, {
    String? name,
    String? visibility,
    SmartRule? rule,
  }) async {
    final pl = await getPlaylist(pid);
    var next = Playlist(
      pid: pl.pid,
      name: name ?? pl.name,
      kind: pl.kind,
      visibility: visibility ?? pl.visibility,
      ownerName: pl.ownerName,
      isOwner: pl.isOwner,
      itemCount: pl.itemCount,
      rule: rule ?? pl.rule,
      createdAt: pl.createdAt,
      updatedAt: DateTime.utc(2026, 2),
    );
    if (rule != null) {
      // A rule replace reissues the pid, like the real server.
      playlistsByPid.remove(pid);
      next = Playlist(
        pid: 'pl-FAKE${_playlistSeq++}',
        previousPid: pid,
        name: next.name,
        kind: next.kind,
        visibility: next.visibility,
        ownerName: next.ownerName,
        isOwner: next.isOwner,
        rule: rule,
        createdAt: DateTime.utc(2026, 2),
        updatedAt: DateTime.utc(2026, 2),
      );
    }
    playlistsByPid[next.pid] = next;
    return next;
  }

  @override
  Future<void> deletePlaylist(String pid) async {
    playlistsByPid.remove(pid);
    playlistMembers.remove(pid);
  }

  @override
  Future<PlaylistItemsPage> listPlaylistItems(
    String pid, {
    String? cursor,
    int? limit,
  }) async {
    final pl = await getPlaylist(pid);
    if (pl.isSmart) {
      return PlaylistItemsPage(
        entries: [
          for (final it in previewResult.items) PlaylistEntry(item: it),
        ],
      );
    }
    final members = playlistMembers[pid] ?? const [];
    return PlaylistItemsPage(
      entries: [
        for (var i = 0; i < members.length; i++)
          PlaylistEntry(position: i, item: _itemByPid(members[i])),
      ],
    );
  }

  @override
  Future<void> replacePlaylistItems(
    String pid,
    List<String> itemPids, {
    DateTime? baseUpdatedAt,
  }) async {
    await getPlaylist(pid);
    playlistMembers[pid] = List.of(itemPids);
  }

  @override
  Future<void> addPlaylistItems(String pid, List<String> itemPids) async {
    await getPlaylist(pid);
    (playlistMembers[pid] ??= []).addAll(itemPids);
  }

  @override
  Future<void> removePlaylistItemAt(String pid, int position) async {
    await getPlaylist(pid);
    final members = playlistMembers[pid];
    if (members != null && position >= 0 && position < members.length) {
      members.removeAt(position);
    }
  }

  /// Rules passed to [previewSmartRule], newest last.
  final List<SmartRule> previewedRules = [];

  @override
  Future<PlaylistPreview> previewSmartRule(SmartRule rule, {int? limit}) async {
    previewedRules.add(rule);
    return previewResult;
  }

  @override
  Future<RuleFields> getRuleFields() async => ruleFields;

  /// What [exportPlaylistM3u] serves, and the pids it was asked for.
  String exportM3uResult = '#EXTM3U\n';
  final List<String> exportedM3uPids = [];

  /// The documents [importPlaylistM3u] received, and the counts its
  /// result reports.
  final List<String> importedM3uContents = [];
  int importMatched = 0;
  int importUnmatched = 0;

  @override
  Future<String> exportPlaylistM3u(String pid) async {
    exportedM3uPids.add(pid);
    return exportM3uResult;
  }

  @override
  Future<M3uImportResult> importPlaylistM3u({
    required String name,
    required String content,
    String? visibility,
  }) async {
    importedM3uContents.add(content);
    final pl = await createPlaylist(
      name: name,
      kind: 'static',
      visibility: visibility,
    );
    return M3uImportResult(
      playlist: pl,
      matched: importMatched,
      unmatched: importUnmatched,
    );
  }

  /// Radio stations by pid.
  final Map<String, RadioStation> radioStationsByPid = {};

  /// Directory entries served by [searchRadioDirectory].
  List<RadioDirectoryEntry> directoryEntries = const [];

  int _stationSeq = 0;

  @override
  Future<List<PlayerEndpoint>> listPlayerEndpoints() async {
    return List.of(playerEndpoints);
  }

  @override
  Future<List<PlaybackSessionInfo>> listPlaybackSessions() async {
    return List.of(playbackSessions);
  }

  @override
  Future<PlaybackSessionInfo> createPlaybackSession({
    required String endpointId,
    required List<String> itemPids,
    int index = 0,
    int positionMs = 0,
    bool play = true,
  }) async {
    createPlaybackSessionCalls.add((
      endpointId: endpointId,
      itemPids: itemPids,
      index: index,
      positionMs: positionMs,
    ));
    return PlaybackSessionInfo(
      id: 'ps-created',
      endpointId: endpointId,
      mine: true,
      authority: 'remote',
      playing: play,
      index: index,
      positionMs: positionMs,
      positionAt: DateTime.now().toUtc(),
      rate: 1,
      queueVersion: 1,
      entries: [
        for (final pid in itemPids) PlaybackSessionEntry(pid: pid, title: pid),
      ],
    );
  }

  @override
  Future<PlaybackSessionInfo> getPlaybackSession(String sessionId) async {
    final match = playbackSessions.where((s) => s.id == sessionId);
    if (match.isEmpty) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such session',
        statusCode: 404,
      );
    }
    return match.first;
  }

  @override
  Future<void> deletePlaybackSession(String sessionId) async {
    deletePlaybackSessionCalls.add(sessionId);
  }

  @override
  Future<PlaybackSessionInfo> transferPlaybackSession(
    String sessionId,
    String endpointId,
  ) async {
    transferPlaybackSessionCalls.add((
      sessionId: sessionId,
      endpointId: endpointId,
    ));
    return PlaybackSessionInfo(
      id: sessionId,
      endpointId: endpointId,
      mine: true,
      authority: 'remote',
      playing: true,
      index: 0,
      positionMs: 0,
      positionAt: DateTime.now().toUtc(),
      rate: 1,
      queueVersion: 1,
      entries: const [],
    );
  }

  @override
  Future<List<RadioStation>> listRadioStations() async {
    final rows = radioStationsByPid.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return rows;
  }

  @override
  Future<RadioStation> createRadioStation({
    required String name,
    required String streamUrl,
    String? homepageUrl,
    String? logoUrl,
  }) async {
    final st = RadioStation(
      pid: 'rs-FAKE${_stationSeq++}',
      name: name,
      streamUrl: streamUrl,
      homepageUrl: homepageUrl,
      logoUrl: logoUrl,
      createdAt: DateTime.utc(2026),
    );
    radioStationsByPid[st.pid] = st;
    return st;
  }

  @override
  Future<RadioStation> updateRadioStation(
    String pid, {
    required String name,
    required String streamUrl,
    String? homepageUrl,
    String? logoUrl,
  }) async {
    final st = RadioStation(
      pid: pid,
      name: name,
      streamUrl: streamUrl,
      homepageUrl: homepageUrl,
      logoUrl: logoUrl,
      createdAt: DateTime.utc(2026),
    );
    radioStationsByPid[pid] = st;
    return st;
  }

  @override
  Future<void> deleteRadioStation(String pid) async {
    radioStationsByPid.remove(pid);
  }

  @override
  Future<RadioPlayInfo> getRadioPlayInfo(String pid) async {
    return RadioPlayInfo(url: '/media/radio/$pid?mt=fake');
  }

  @override
  Future<List<RadioDirectoryEntry>> searchRadioDirectory(
    String query, {
    int? limit,
  }) async => directoryEntries;

  /// Scrobbler slots served by [listScrobblers]; connect and disconnect
  /// mutate them.
  List<Scrobbler> scrobblers = const [
    Scrobbler(service: 'lastfm', available: false, connected: false),
    Scrobbler(service: 'listenbrainz', available: true, connected: false),
  ];

  /// Thrown by [connectListenBrainz] when set.
  WaxDeckApiException? connectError;

  @override
  Future<List<Scrobbler>> listScrobblers() async => scrobblers;

  @override
  Future<Scrobbler> connectListenBrainz(String token, {String? apiUrl}) async {
    final error = connectError;
    if (error != null) throw error;
    final connected = Scrobbler(
      service: 'listenbrainz',
      available: true,
      connected: true,
      username: 'listener',
      apiUrl: apiUrl,
    );
    scrobblers = [
      for (final s in scrobblers)
        if (s.service == 'listenbrainz') connected else s,
    ];
    return connected;
  }

  @override
  Future<void> disconnectListenBrainz() async {
    scrobblers = [
      for (final s in scrobblers)
        if (s.service == 'listenbrainz')
          const Scrobbler(
            service: 'listenbrainz',
            available: true,
            connected: false,
          )
        else
          s,
    ];
  }

  @override
  Future<String> startLastfmConnect() async =>
      'https://last.fm/api/auth/?api_key=fake';

  @override
  Future<void> disconnectLastfm() async {
    scrobblers = [
      for (final s in scrobblers)
        if (s.service == 'lastfm')
          const Scrobbler(service: 'lastfm', available: true, connected: false)
        else
          s,
    ];
  }

  /// Server-level Last.fm credential state served and replaced by the
  /// admin scrobbling endpoints.
  ScrobblingAdminConfig scrobblingConfig = const ScrobblingAdminConfig(
    lastfmConfigured: false,
    lastfmSource: 'none',
    lastfmSecretSet: false,
  );

  @override
  Future<ScrobblingAdminConfig> getScrobblingConfig() async => scrobblingConfig;

  @override
  Future<ScrobblingAdminConfig> putScrobblingConfig({
    required String apiKey,
    required String secret,
  }) async {
    final error = adminError;
    if (error != null) throw error;
    // The server refuses a half-set pair, like it does.
    if (apiKey.isEmpty != secret.isEmpty) {
      throw const WaxDeckApiException(
        code: 'invalid-request',
        message: 'set both the API key and the secret, or neither',
        statusCode: 400,
      );
    }
    scrobblingConfig = apiKey.isEmpty
        ? const ScrobblingAdminConfig(
            lastfmConfigured: false,
            lastfmSource: 'none',
            lastfmSecretSet: false,
          )
        : ScrobblingAdminConfig(
            lastfmConfigured: true,
            lastfmSource: 'settings',
            lastfmApiKey: apiKey,
            lastfmSecretSet: true,
          );
    // The Last.fm slot's availability follows the credential state.
    scrobblers = [
      for (final s in scrobblers)
        if (s.service == 'lastfm')
          Scrobbler(
            service: s.service,
            available: scrobblingConfig.lastfmConfigured,
            connected: s.connected,
            username: s.username,
            apiUrl: s.apiUrl,
            lastSuccessAt: s.lastSuccessAt,
            lastError: s.lastError,
            lastErrorAt: s.lastErrorAt,
          )
        else
          s,
    ];
    return scrobblingConfig;
  }

  /// Push registrations served and mutated by the legacy push
  /// endpoints; rows mirror into [myNotificationTargets] as
  /// unifiedpush targets, like the server.
  final List<PushRegistration> pushRegistrations = [];

  @override
  Future<List<PushRegistration>> listPushRegistrations() async =>
      List.of(pushRegistrations);

  @override
  Future<PushRegistration> createPushRegistration({
    required String endpoint,
    String? label,
  }) async {
    final reg = PushRegistration(
      pid: 'nt-FAKEUP${pushRegistrations.length}',
      endpoint: endpoint,
      label: label,
      createdAt: DateTime.utc(2026),
    );
    pushRegistrations.add(reg);
    myNotificationTargets.add(
      NotificationTarget(
        pid: reg.pid,
        kind: 'unifiedpush',
        scope: 'user',
        label: label,
        config: {'endpoint': endpoint},
        enabledEvents: const ['episode-downloaded', 'feed-disabled'],
        createdAt: reg.createdAt,
      ),
    );
    return reg;
  }

  @override
  Future<void> deletePushRegistration(String pid) async {
    pushRegistrations.removeWhere((r) => r.pid == pid);
    myNotificationTargets.removeWhere((t) => t.pid == pid);
  }

  /// The notification event catalog, server scope first.
  List<NotifyEvent> notifyEvents = const [
    NotifyEvent(
      name: 'signup-requested',
      scope: 'server',
      description: 'A new account request is waiting for approval.',
    ),
    NotifyEvent(
      name: 'backup-completed',
      scope: 'server',
      description: 'A backup archive finished building.',
    ),
    NotifyEvent(
      name: 'episode-downloaded',
      scope: 'user',
      description: 'A new episode finished downloading.',
    ),
    NotifyEvent(
      name: 'feed-disabled',
      scope: 'user',
      description: 'A subscribed feed kept failing and was disabled.',
    ),
  ];

  /// Notification targets per scope, plus per-pid test counts.
  final List<NotificationTarget> serverNotificationTargets = [];
  final List<NotificationTarget> myNotificationTargets = [];
  final Map<String, int> notificationTargetTests = {};
  var _notificationTargetSeq = 0;

  /// When set, target saves throw this (the server-rejection path).
  WaxDeckApiException? notificationTargetError;

  @override
  Future<List<NotifyEvent>> listNotificationEvents() async =>
      List.of(notifyEvents);

  NotificationTarget _storeTarget(
    List<NotificationTarget> into, {
    required String scope,
    required String kind,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
  }) {
    final target = NotificationTarget(
      pid: 'nt-FAKE${_notificationTargetSeq++}',
      kind: kind,
      scope: scope,
      label: label,
      config: Map.of(config),
      enabledEvents: List.of(enabledEvents),
      createdAt: DateTime.utc(2026),
    );
    into.insert(0, target);
    return target;
  }

  NotificationTarget _replaceTarget(
    List<NotificationTarget> into,
    String pid, {
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
  }) {
    final index = into.indexWhere((t) => t.pid == pid);
    if (index < 0) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no notification target',
        statusCode: 404,
      );
    }
    final old = into[index];
    final updated = NotificationTarget(
      pid: old.pid,
      kind: old.kind,
      scope: old.scope,
      label: label,
      config: Map.of(config),
      enabledEvents: List.of(enabledEvents),
      createdAt: old.createdAt,
      lastSuccessAt: old.lastSuccessAt,
      lastError: old.lastError,
      lastErrorAt: old.lastErrorAt,
    );
    into[index] = updated;
    return updated;
  }

  @override
  Future<List<NotificationTarget>> listServerNotificationTargets() async =>
      List.of(serverNotificationTargets);

  @override
  Future<NotificationTarget> createServerNotificationTarget({
    required String kind,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
  }) async {
    if (notificationTargetError != null) throw notificationTargetError!;
    return _storeTarget(
      serverNotificationTargets,
      scope: 'server',
      kind: kind,
      label: label,
      config: config,
      enabledEvents: enabledEvents,
    );
  }

  @override
  Future<NotificationTarget> updateServerNotificationTarget({
    required String pid,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
  }) async {
    if (notificationTargetError != null) throw notificationTargetError!;
    return _replaceTarget(
      serverNotificationTargets,
      pid,
      label: label,
      config: config,
      enabledEvents: enabledEvents,
    );
  }

  @override
  Future<void> deleteServerNotificationTarget(String pid) async {
    serverNotificationTargets.removeWhere((t) => t.pid == pid);
  }

  @override
  Future<void> testServerNotificationTarget(String pid) async {
    notificationTargetTests[pid] = (notificationTargetTests[pid] ?? 0) + 1;
  }

  @override
  Future<List<NotificationTarget>> listMyNotificationTargets() async =>
      List.of(myNotificationTargets);

  @override
  Future<NotificationTarget> createMyNotificationTarget({
    required String kind,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
  }) async {
    if (notificationTargetError != null) throw notificationTargetError!;
    return _storeTarget(
      myNotificationTargets,
      scope: 'user',
      kind: kind,
      label: label,
      config: config,
      enabledEvents: enabledEvents,
    );
  }

  @override
  Future<NotificationTarget> updateMyNotificationTarget({
    required String pid,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
  }) async {
    if (notificationTargetError != null) throw notificationTargetError!;
    return _replaceTarget(
      myNotificationTargets,
      pid,
      label: label,
      config: config,
      enabledEvents: enabledEvents,
    );
  }

  @override
  Future<void> deleteMyNotificationTarget(String pid) async {
    myNotificationTargets.removeWhere((t) => t.pid == pid);
  }

  @override
  Future<void> testMyNotificationTarget(String pid) async {
    notificationTargetTests[pid] = (notificationTargetTests[pid] ?? 0) + 1;
  }

  /// Review entries served by the queue endpoints.
  List<ReviewEntry> reviewEntries = [];

  /// Full details by entry id; absent ids derive from the entry.
  final Map<String, ReviewEntryDetail> reviewEntryDetails = {};

  /// Thrown by the review endpoints when set.
  WaxDeckApiException? reviewError;

  final List<({String entryId, String action, String? candidateMbid})>
  decideReviewCalls = [];
  final List<String> revertedReviewEntryIds = [];

  /// Matching modes by library pid; unset libraries answer `auto`.
  final Map<String, String> matchingModes = {};

  /// Catalog libraries the fake reports.
  final List<LibraryInfo> libraries = [];

  ReviewEntry _reviewEntryById(String entryId) {
    return reviewEntries.firstWhere(
      (e) => e.id == entryId,
      orElse: () => throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such review entry',
        statusCode: 404,
      ),
    );
  }

  ReviewEntry _withStatus(ReviewEntry e, String status) => ReviewEntry(
    id: e.id,
    kind: e.kind,
    status: status,
    mediaType: e.mediaType,
    origin: e.origin,
    title: e.title,
    artist: e.artist,
    trackCount: e.trackCount,
    libraryPid: e.libraryPid,
    uploadedBy: e.uploadedBy,
    identifying: false,
    best: e.best,
    appliedMbid: e.appliedMbid,
    createdAt: e.createdAt,
    decidedAt: status == 'pending' ? null : DateTime.utc(2026, 7, 2),
    decidedBy: status == 'pending' ? null : 'admin',
  );

  static String _statusForAction(String action) => switch (action) {
    'approve' => 'applied',
    'skip' => 'skipped',
    'discard' => 'discarded',
    _ => action,
  };

  @override
  Future<ReviewEntryPage> listReviewQueue({
    String? status,
    String? cursor,
    int? limit,
  }) async {
    final error = reviewError;
    if (error != null) throw error;
    final filtered = status == null
        ? reviewEntries
        : reviewEntries.where((e) => e.status == status).toList();
    final start = cursor == null ? 0 : int.parse(cursor);
    final pageSize = limit ?? 50;
    final end = (start + pageSize).clamp(0, filtered.length);
    return ReviewEntryPage(
      entries: filtered.sublist(start.clamp(0, filtered.length), end),
      nextCursor: end < filtered.length ? '$end' : null,
    );
  }

  @override
  Future<ReviewEntryDetail> getReviewEntry(String entryId) async {
    final error = reviewError;
    if (error != null) throw error;
    final canned = reviewEntryDetails[entryId];
    if (canned != null) return canned;
    final e = _reviewEntryById(entryId);
    return ReviewEntryDetail(
      id: e.id,
      kind: e.kind,
      status: e.status,
      mediaType: e.mediaType,
      origin: e.origin,
      title: e.title,
      artist: e.artist,
      trackCount: e.trackCount,
      libraryPid: e.libraryPid,
      uploadedBy: e.uploadedBy,
      identifying: e.identifying,
      best: e.best,
      appliedMbid: e.appliedMbid,
      createdAt: e.createdAt,
      decidedAt: e.decidedAt,
      decidedBy: e.decidedBy,
    );
  }

  ReviewEntry _decide(String entryId, String action) {
    final updated = _withStatus(
      _reviewEntryById(entryId),
      _statusForAction(action),
    );
    reviewEntries = [
      for (final e in reviewEntries)
        if (e.id == entryId) updated else e,
    ];
    return updated;
  }

  @override
  Future<ReviewDecideResult> decideReviewEntry(
    String entryId, {
    required String action,
    String? candidateMbid,
  }) async {
    decideReviewCalls.add((
      entryId: entryId,
      action: action,
      candidateMbid: candidateMbid,
    ));
    final error = reviewError;
    if (error != null) throw error;
    return ReviewDecideResult(entry: _decide(entryId, action));
  }

  @override
  Future<ReviewEntry> revertReviewEntry(String entryId) async {
    final error = reviewError;
    if (error != null) throw error;
    revertedReviewEntryIds.add(entryId);
    final updated = _withStatus(_reviewEntryById(entryId), 'pending');
    reviewEntries = [
      for (final e in reviewEntries)
        if (e.id == entryId) updated else e,
    ];
    return updated;
  }

  @override
  Future<List<ReviewBulkOutcome>> decideReviewBulk(
    List<String> entryIds, {
    required String action,
  }) async {
    final error = reviewError;
    if (error != null) throw error;
    return [
      for (final id in entryIds)
        if (reviewEntries.any((e) => e.id == id))
          ReviewBulkOutcome(entryId: (_decide(id, action)).id, ok: true)
        else
          ReviewBulkOutcome(entryId: id, ok: false, error: 'not-found'),
    ];
  }

  @override
  Future<ReviewStats> getReviewStats() async {
    int count(String status) =>
        reviewEntries.where((e) => e.status == status).length;
    return ReviewStats(
      pending: count('pending'),
      identifying: reviewEntries.where((e) => e.identifying).length,
      applied: count('applied'),
      autoApplied: count('auto-applied'),
      asIs: count('as-is'),
      unofficial: count('unofficial'),
      skipped: count('skipped'),
      reverted: count('reverted'),
      revertedAutoApplied: 0,
    );
  }

  @override
  Future<List<LibraryInfo>> listLibraries() async =>
      List.unmodifiable(libraries);

  @override
  Future<String> getLibraryMatching(String libraryPid) async =>
      matchingModes[libraryPid] ?? 'auto';

  @override
  Future<String> setLibraryMatching(String libraryPid, String mode) async =>
      matchingModes[libraryPid] = mode;

  /// Upload sessions by id.
  final Map<String, UploadSession> uploadsById = {};

  /// Thrown by the upload endpoints when set.
  WaxDeckApiException? uploadError;

  /// Runs before each putUploadData, ahead of the [uploadError] check;
  /// tests use it to trip failures at a chosen chunk.
  void Function()? onPutUploadData;

  /// Runs before each createUpload, ahead of the [uploadError] check;
  /// tests use it to fail a chosen file in a multi-file flow.
  void Function(String fileName)? onCreateUpload;

  final List<({String uploadId, int offset, int byteCount})>
  putUploadDataCalls = [];
  int _uploadSeq = 0;

  UploadSession _uploadById(String uploadId) {
    final upload = uploadsById[uploadId];
    if (upload == null) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such upload',
        statusCode: 404,
      );
    }
    return upload;
  }

  UploadSession _uploadWith(
    UploadSession u, {
    int? receivedBytes,
    String? state,
  }) => UploadSession(
    id: u.id,
    fileName: u.fileName,
    sizeBytes: u.sizeBytes,
    receivedBytes: receivedBytes ?? u.receivedBytes,
    mediaType: u.mediaType,
    libraryPid: u.libraryPid,
    batchId: u.batchId,
    state: state ?? u.state,
    reviewEntryId: u.reviewEntryId,
    duplicate: u.duplicate,
    uploadedBy: u.uploadedBy,
    createdAt: u.createdAt,
    expiresAt: u.expiresAt,
  );

  /// The quota snapshot every uploads page carries.
  UploadQuota? uploadPageQuota;

  @override
  Future<UploadPage> listUploads({String? cursor, int? limit}) async {
    final error = uploadError;
    if (error != null) throw error;
    return UploadPage(
      uploads: uploadsById.values.toList(),
      quota: uploadPageQuota,
    );
  }

  /// Batches by id, and the member joins each session declared.
  final Map<String, UploadBatch> batchesById = {};
  final List<({String uploadId, String batchId, String? batchPath})>
  batchJoins = [];
  final List<String> completedBatchIds = [];
  int _batchSeq = 0;

  @override
  Future<UploadBatch> createUploadBatch({
    required UploadGrouping grouping,
    required String mediaType,
    String? libraryPid,
  }) async {
    final error = uploadError;
    if (error != null) throw error;
    final batch = UploadBatch(
      id: 'ub-FAKE${_batchSeq++}',
      grouping: grouping,
      mediaType: MediaType.values.firstWhere(
        (m) => m.wireName == mediaType,
        orElse: () => MediaType.music,
      ),
      libraryPid: libraryPid,
      state: 'open',
      createdAt: DateTime.utc(2026, 7, 1),
      expiresAt: DateTime.utc(2026, 7, 2),
    );
    batchesById[batch.id] = batch;
    return batch;
  }

  @override
  Future<UploadBatch> completeUploadBatch(String batchId) async {
    final error = uploadError;
    if (error != null) throw error;
    final batch = batchesById[batchId];
    if (batch == null) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such upload batch',
        statusCode: 404,
      );
    }
    completedBatchIds.add(batchId);
    final done = UploadBatch(
      id: batch.id,
      grouping: batch.grouping,
      mediaType: batch.mediaType,
      libraryPid: batch.libraryPid,
      state: 'finalized',
      reviewEntryIds: [
        for (final join in batchJoins)
          if (join.batchId == batchId) 'rv-of-${join.uploadId}',
      ],
      createdAt: batch.createdAt,
      expiresAt: batch.expiresAt,
    );
    batchesById[batchId] = done;
    return done;
  }

  @override
  Future<UploadSession> createUpload({
    required String fileName,
    required int sizeBytes,
    required String mediaType,
    String? libraryPid,
    String? sha256,
    String? batchId,
    String? batchPath,
  }) async {
    onCreateUpload?.call(fileName);
    final error = uploadError;
    if (error != null) throw error;
    final upload = UploadSession(
      id: 'up-FAKE${_uploadSeq++}',
      fileName: fileName,
      sizeBytes: sizeBytes,
      receivedBytes: 0,
      mediaType: MediaType.values.firstWhere(
        (m) => m.wireName == mediaType,
        orElse: () => MediaType.music,
      ),
      libraryPid: libraryPid,
      batchId: batchId,
      state: 'receiving',
      createdAt: DateTime.utc(2026, 7, 1),
    );
    if (batchId != null) {
      batchJoins.add((
        uploadId: upload.id,
        batchId: batchId,
        batchPath: batchPath,
      ));
    }
    uploadsById[upload.id] = upload;
    return upload;
  }

  @override
  Future<UploadSession> getUpload(String uploadId) async =>
      _uploadById(uploadId);

  @override
  Future<void> deleteUpload(String uploadId) async {
    uploadsById.remove(uploadId);
  }

  @override
  Future<UploadSession> putUploadData(
    String uploadId, {
    required int offset,
    required Uint8List bytes,
  }) async {
    onPutUploadData?.call();
    final error = uploadError;
    if (error != null) throw error;
    putUploadDataCalls.add((
      uploadId: uploadId,
      offset: offset,
      byteCount: bytes.length,
    ));
    final updated = _uploadWith(
      _uploadById(uploadId),
      receivedBytes: offset + bytes.length,
    );
    uploadsById[uploadId] = updated;
    return updated;
  }

  final List<({String url, MediaType mediaType, String? format})>
  acquisitionCalls = [];

  @override
  Future<ToolTask> createAcquisition({
    required String url,
    required MediaType mediaType,
    String? libraryPid,
    String? format,
  }) async {
    final error = uploadError;
    if (error != null) throw error;
    acquisitionCalls.add((url: url, mediaType: mediaType, format: format));
    final task = ToolTask(
      id: 'tt-FAKE${_toolTaskSeq++}',
      type: 'acquire',
      state: 'queued',
      createdAt: DateTime.utc(2026, 7, 1),
    );
    toolTasksById[task.id] = task;
    return task;
  }

  @override
  Future<UploadSession> completeUpload(String uploadId) async {
    final error = uploadError;
    if (error != null) throw error;
    final upload = _uploadById(uploadId);
    if (upload.receivedBytes < upload.sizeBytes) {
      throw const WaxDeckApiException(
        code: 'conflict',
        message: 'upload incomplete',
        statusCode: 409,
      );
    }
    final updated = _uploadWith(upload, state: 'staged');
    uploadsById[uploadId] = updated;
    return updated;
  }

  /// Thrown by the metadata endpoints when set.
  WaxDeckApiException? metadataError;

  /// Editor state by item pid.
  final Map<String, Map<String, String>> itemFieldsByPid = {};
  final Map<String, Set<String>> lockedFieldsByPid = {};
  final Map<String, List<Credit>> creditsByPid = {};
  final Map<String, LyricsState> lyricsByPid = {};
  final Map<String, Map<String, List<String>>> tagsByPid = {};
  final Map<String, List<ChapterEdit>> chapterEditsByPid = {};
  final Set<String> artworkPids = {};
  final Set<String> unofficialPids = {};

  /// Entity curation by `entityType/entityPid`.
  final Map<String, Map<String, String>> entityEditsByKey = {};
  final Map<String, List<EntityCuratedField>> entityCurationByKey = {};

  final List<({String pid, Map<String, String> fields, bool writeBack})>
  editItemMetadataCalls = [];
  final List<({String entityType, String entityPid, int byteCount})>
  entityArtworkCalls = [];
  final List<String> rematchCalls = [];
  final List<({String pid, List<String> want})> enrichItemCalls = [];
  final List<({String pid, List<String> fields, bool locked})>
  setItemLocksCalls = [];
  final List<({String pid, bool unofficial})> setReleaseStatusCalls = [];

  /// The editor vocabulary served by [getMetadataFields].
  MetadataFields metadataFields = const MetadataFields(
    kinds: [
      KindFields(
        kind: MediaType.music,
        fields: [
          EditableField(name: 'title', writeBack: true),
          EditableField(name: 'artist', writeBack: true),
          EditableField(name: 'album', writeBack: true),
          EditableField(name: 'year', writeBack: true),
        ],
        creditRoles: [EditableField(name: 'composer', writeBack: true)],
      ),
    ],
    entityTypes: [
      EntityTypeFields(
        entityType: 'artist',
        fields: [EditableField(name: 'name', writeBack: false)],
      ),
    ],
  );

  void _requireUnlocked(String pid, Iterable<String> fields, bool force) {
    if (force) return;
    final locked = lockedFieldsByPid[pid] ?? const {};
    if (fields.any(locked.contains)) {
      throw const WaxDeckApiException(
        code: 'conflict',
        message: 'field locked',
        statusCode: 409,
      );
    }
  }

  @override
  Future<MetadataFields> getMetadataFields() async => metadataFields;

  @override
  Future<ItemMetadata> getItemMetadata(String pid) async {
    final error = metadataError;
    if (error != null) throw error;
    final item = libraryItems.where((i) => i.pid == pid).firstOrNull;
    return ItemMetadata(
      pid: pid,
      mediaType: item?.mediaType ?? MediaType.music,
      fields: Map.of(itemFieldsByPid[pid] ?? const {}),
      lockedFields: (lockedFieldsByPid[pid] ?? const <String>{}).toList()
        ..sort(),
      credits: creditsByPid[pid] ?? const [],
      lyrics: lyricsByPid[pid],
      customTags: [
        for (final entry in (tagsByPid[pid] ?? const {}).entries)
          CustomTag(key: entry.key, values: entry.value),
      ],
      unofficial: unofficialPids.contains(pid),
      hasArtwork: artworkPids.contains(pid),
    );
  }

  @override
  Future<MetadataEditResult> editItemMetadata(
    String pid, {
    required Map<String, String> fields,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    editItemMetadataCalls.add((
      pid: pid,
      fields: Map.of(fields),
      writeBack: writeBack,
    ));
    _requireUnlocked(pid, fields.keys, force);
    (itemFieldsByPid[pid] ??= {}).addAll(fields);
    if (lock) (lockedFieldsByPid[pid] ??= {}).addAll(fields.keys);
    return const MetadataEditResult(applied: true);
  }

  @override
  Future<BulkEditResult> bulkEditMetadata({
    required List<String> itemPids,
    required Map<String, String> fields,
    bool writeBack = false,
    bool skipLocked = false,
    bool force = false,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    final edited = <String>[];
    final skipped = <String>[];
    for (final pid in itemPids) {
      final locked = lockedFieldsByPid[pid] ?? const {};
      if (!force && skipLocked && fields.keys.any(locked.contains)) {
        skipped.add(pid);
        continue;
      }
      _requireUnlocked(pid, fields.keys, force);
      (itemFieldsByPid[pid] ??= {}).addAll(fields);
      edited.add(pid);
    }
    return BulkEditResult(edited: edited, skipped: skipped);
  }

  @override
  Future<MetadataEditResult> setItemCredits(
    String pid, {
    required String role,
    required List<String> names,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    final credits = creditsByPid[pid] ?? const <Credit>[];
    creditsByPid[pid] = [
      for (final c in credits)
        if (c.role != role) c,
      Credit(role: role, names: List.of(names)),
    ];
    return const MetadataEditResult(applied: true);
  }

  @override
  Future<MetadataEditResult> setItemLyrics(
    String pid, {
    String? lrc,
    String? plain,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    lyricsByPid[pid] = LyricsState(
      synced: lrc != null,
      source: 'user',
      lrc: lrc,
    );
    return const MetadataEditResult(applied: true);
  }

  @override
  Future<void> clearItemLyrics(String pid) async {
    lyricsByPid.remove(pid);
  }

  @override
  Future<MetadataEditResult> setBookChapters(
    String pid, {
    required List<ChapterEdit> chapters,
    bool lock = true,
    bool force = false,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    chapterEditsByPid[pid] = List.of(chapters);
    return const MetadataEditResult(applied: true);
  }

  @override
  Future<MetadataEditResult> setItemArtwork(
    String pid, {
    required Uint8List bytes,
    bool writeBack = false,
    bool lock = true,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    artworkPids.add(pid);
    return const MetadataEditResult(applied: true);
  }

  @override
  Future<void> clearItemArtwork(String pid) async {
    artworkPids.remove(pid);
  }

  @override
  Future<MetadataEditResult> setEntityArtwork(
    String entityType,
    String entityPid, {
    required Uint8List bytes,
    bool writeBack = false,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    entityArtworkCalls.add((
      entityType: entityType,
      entityPid: entityPid,
      byteCount: bytes.length,
    ));
    return const MetadataEditResult(applied: true);
  }

  @override
  Future<TagEditResult> setItemTag(
    String pid,
    String key, {
    required List<String> values,
    bool lock = true,
    bool force = false,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    (tagsByPid[pid] ??= {})[key] = List.of(values);
    return TagEditResult(key: key, stored: values.length);
  }

  @override
  Future<void> clearItemTag(String pid, String key) async {
    tagsByPid[pid]?.remove(key);
  }

  @override
  Future<List<String>> setItemLocks(
    String pid, {
    required List<String> fields,
    required bool locked,
  }) async {
    setItemLocksCalls.add((pid: pid, fields: List.of(fields), locked: locked));
    final locks = lockedFieldsByPid[pid] ??= {};
    locked ? locks.addAll(fields) : locks.removeAll(fields);
    return locks.toList()..sort();
  }

  @override
  Future<MetadataEditResult> editEntity(
    String entityType,
    String entityPid, {
    required Map<String, String> edits,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    (entityEditsByKey['$entityType/$entityPid'] ??= {}).addAll(edits);
    return const MetadataEditResult(applied: true);
  }

  @override
  Future<List<EntityCuratedField>> getEntityCuration(
    String entityType,
    String entityPid,
  ) async {
    final key = '$entityType/$entityPid';
    final canned = entityCurationByKey[key];
    if (canned != null) return canned;
    return [
      for (final entry in (entityEditsByKey[key] ?? const {}).entries)
        EntityCuratedField(
          field: entry.key,
          value: entry.value,
          source: 'user',
          locked: true,
        ),
    ];
  }

  @override
  Future<MetadataEditResult> setReleaseStatus(
    String pid, {
    required bool unofficial,
  }) async {
    setReleaseStatusCalls.add((pid: pid, unofficial: unofficial));
    unofficial ? unofficialPids.add(pid) : unofficialPids.remove(pid);
    return const MetadataEditResult(applied: true);
  }

  @override
  Future<String> rematchItem(String pid) async {
    final error = metadataError;
    if (error != null) throw error;
    rematchCalls.add(pid);
    final entry = ReviewEntry(
      id: 're-FAKE${reviewEntries.length}',
      kind: 'match',
      status: 'pending',
      mediaType: MediaType.music,
      origin: 'rematch',
      trackCount: 1,
      identifying: true,
      createdAt: DateTime.utc(2026, 7, 1),
    );
    reviewEntries = [...reviewEntries, entry];
    return entry.id;
  }

  @override
  Future<EnrichItemResult> enrichItem(
    String pid, {
    required List<String> want,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    enrichItemCalls.add((pid: pid, want: List.of(want)));
    return EnrichItemResult(applied: List.of(want));
  }

  /// Health state served by the health endpoints.
  HealthSummary healthSummary = const HealthSummary(
    score: 100,
    totalItems: 0,
    evaluatedItems: 0,
  );
  List<HealthIssue> healthIssues = [];

  /// Thrown by the health endpoints when set.
  WaxDeckApiException? healthError;

  int sweepCalls = 0;
  final List<({String rule, List<String>? itemPids})> fixHealthCalls = [];

  List<DuplicateGroup> duplicateGroups = const [];
  final List<({String entityType, String survivorPid, List<String> loserPids})>
  mergeDuplicatesCalls = [];

  List<UpgradeGroup> upgradeGroups = const [];
  final List<({String keepItemPid, List<String> removeItemPids})>
  resolveUpgradeCalls = [];

  @override
  Future<HealthSummary> getLibraryHealth() async {
    final error = healthError;
    if (error != null) throw error;
    return healthSummary;
  }

  @override
  Future<HealthIssuePage> listHealthIssues({
    String? rule,
    String? cursor,
    int? limit,
  }) async {
    final error = healthError;
    if (error != null) throw error;
    final filtered = rule == null
        ? healthIssues
        : healthIssues.where((i) => i.rules.contains(rule)).toList();
    final start = cursor == null ? 0 : int.parse(cursor);
    final pageSize = limit ?? 100;
    final end = (start + pageSize).clamp(0, filtered.length);
    return HealthIssuePage(
      items: filtered.sublist(start.clamp(0, filtered.length), end),
      nextCursor: end < filtered.length ? '$end' : null,
    );
  }

  @override
  Future<void> sweepLibraryHealth() async {
    sweepCalls++;
  }

  @override
  Future<int> fixHealthIssues({
    required String rule,
    List<String>? itemPids,
  }) async {
    final error = healthError;
    if (error != null) throw error;
    fixHealthCalls.add((rule: rule, itemPids: itemPids));
    return itemPids?.length ??
        healthIssues.where((i) => i.rules.contains(rule)).length;
  }

  @override
  Future<List<DuplicateGroup>> listDuplicates() async =>
      List.of(duplicateGroups);

  @override
  Future<MergeOutcome> mergeDuplicates({
    required String entityType,
    required String survivorPid,
    required List<String> loserPids,
  }) async {
    final error = healthError;
    if (error != null) throw error;
    mergeDuplicatesCalls.add((
      entityType: entityType,
      survivorPid: survivorPid,
      loserPids: List.of(loserPids),
    ));
    duplicateGroups = [
      for (final g in duplicateGroups)
        if (g.survivor.pid != survivorPid) g,
    ];
    return MergeOutcome(merged: loserPids.length, childrenMoved: 0);
  }

  @override
  Future<List<UpgradeGroup>> listUpgrades() async => List.of(upgradeGroups);

  @override
  Future<int> resolveUpgrade({
    required String keepItemPid,
    required List<String> removeItemPids,
  }) async {
    final error = healthError;
    if (error != null) throw error;
    resolveUpgradeCalls.add((
      keepItemPid: keepItemPid,
      removeItemPids: List.of(removeItemPids),
    ));
    upgradeGroups = [
      for (final g in upgradeGroups)
        if (!g.members.any((m) => m.itemPid == keepItemPid)) g,
    ];
    return removeItemPids.length;
  }

  /// Organize profiles and canned results.
  List<OrganizeProfile> organizeProfiles = const [
    OrganizeProfile(name: 'default'),
  ];
  OrganizePlan? organizePlanResult;
  OrganizeReport organizeReportResult = const OrganizeReport(
    moved: 0,
    skipped: 0,
    failed: 0,
  );

  final List<({String profile, List<String>? itemPids})> previewOrganizeCalls =
      [];
  final List<({String profile, List<String>? itemPids})> applyOrganizeCalls =
      [];

  @override
  Future<List<OrganizeProfile>> listOrganizeProfiles() async =>
      List.of(organizeProfiles);

  @override
  Future<OrganizePlan> previewOrganize({
    required String profile,
    List<String>? itemPids,
  }) async {
    previewOrganizeCalls.add((profile: profile, itemPids: itemPids));
    return organizePlanResult ??
        OrganizePlan(profile: profile, totalActions: 0);
  }

  @override
  Future<OrganizeReport> applyOrganize({
    required String profile,
    List<String>? itemPids,
  }) async {
    applyOrganizeCalls.add((profile: profile, itemPids: itemPids));
    return organizeReportResult;
  }

  /// Tool tasks by id, in creation order.
  final Map<String, ToolTask> toolTasksById = {};

  /// Thrown by the tool endpoints when set.
  WaxDeckApiException? toolError;

  final List<({String pid, List<String>? titles, bool keepOriginals})>
  mergeBookCalls = [];
  final List<({String pid, bool keepOriginals})> splitBookCalls = [];
  final List<({String pid, bool keepOriginals})> splitCueCalls = [];
  int _toolTaskSeq = 0;

  ToolTask _startToolTask(String type, String pid) {
    final task = ToolTask(
      id: 'tt-FAKE${_toolTaskSeq++}',
      type: type,
      state: 'queued',
      itemPid: pid,
      createdAt: DateTime.utc(2026, 7, 1),
    );
    toolTasksById[task.id] = task;
    return task;
  }

  @override
  Future<ToolTask> mergeBook(
    String pid, {
    List<String>? titles,
    bool keepOriginals = false,
  }) async {
    final error = toolError;
    if (error != null) throw error;
    mergeBookCalls.add((
      pid: pid,
      titles: titles,
      keepOriginals: keepOriginals,
    ));
    return _startToolTask('book-merge', pid);
  }

  @override
  Future<ToolTask> splitBook(String pid, {bool keepOriginals = false}) async {
    final error = toolError;
    if (error != null) throw error;
    splitBookCalls.add((pid: pid, keepOriginals: keepOriginals));
    return _startToolTask('book-split', pid);
  }

  @override
  Future<ToolTask> splitCueRip(String pid, {bool keepOriginals = false}) async {
    final error = toolError;
    if (error != null) throw error;
    splitCueCalls.add((pid: pid, keepOriginals: keepOriginals));
    return _startToolTask('cue-split', pid);
  }

  @override
  Future<ToolTaskPage> listToolTasks({String? cursor, int? limit}) async {
    final error = toolError;
    if (error != null) throw error;
    return ToolTaskPage(tasks: toolTasksById.values.toList());
  }

  @override
  Future<ToolTask> getToolTask(String taskId) async {
    final task = toolTasksById[taskId];
    if (task == null) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such task',
        statusCode: 404,
      );
    }
    return task;
  }

  /// Enrichment status served by [getEnrichmentStatus].
  EnrichmentStatus enrichmentStatus = const EnrichmentStatus(
    coverage: EnrichmentCoverage(
      artists: CoverageCount(enriched: 0, total: 0),
      releaseGroups: CoverageCount(enriched: 0, total: 0),
      books: CoverageCount(enriched: 0, total: 0),
      lyrics: CoverageCount(enriched: 0, total: 0),
    ),
    running: false,
  );

  /// The force flags passed to [runEnrichment], in order.
  final List<bool> runEnrichmentCalls = [];

  @override
  Future<EnrichmentStatus> getEnrichmentStatus() async => enrichmentStatus;

  @override
  Future<String> runEnrichment({bool force = false}) async {
    runEnrichmentCalls.add(force);
    return 'jb-FAKEENRICH';
  }

  /// Accounts by id, served and mutated by the admin user endpoints.
  final Map<String, UserAccount> usersById = {};
  int _userSeq = 0;

  @override
  Future<UserPage> listUsers({String? cursor, int? limit}) async {
    final error = listError;
    if (error != null) throw error;
    return UserPage(users: usersById.values.toList());
  }

  @override
  Future<UserAccount> createUser({
    required String username,
    required String password,
    String? displayName,
    List<String>? roles,
    LibraryAccess? libraryAccess,
    bool? uploadEnabled,
    int? uploadQuotaBytes,
    Permissions? permissions,
  }) async {
    final account = UserAccount(
      id: 'us-FAKE${_userSeq++}',
      username: username,
      displayName: displayName,
      roles: roles ?? const ['user'],
      createdAt: DateTime.utc(2026, 7, 1),
      libraryAccess: libraryAccess ?? const LibraryAccess(mode: 'all'),
      uploadEnabled: uploadEnabled ?? false,
      uploadQuotaBytes: uploadQuotaBytes,
      permissions: permissions ?? const Permissions(),
    );
    usersById[account.id] = account;
    return account;
  }

  @override
  Future<UserAccount> updateUser(
    String userId, {
    String? displayName,
    List<String>? roles,
    bool? disabled,
    LibraryAccess? libraryAccess,
    bool? uploadEnabled,
    int? uploadQuotaBytes,
    Permissions? permissions,
  }) async {
    final current = usersById[userId];
    if (current == null) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such user',
        statusCode: 404,
      );
    }
    final updated = UserAccount(
      id: current.id,
      username: current.username,
      displayName: displayName ?? current.displayName,
      roles: roles ?? current.roles,
      createdAt: current.createdAt,
      identities: current.identities,
      libraryAccess: libraryAccess ?? current.libraryAccess,
      uploadEnabled: uploadEnabled ?? current.uploadEnabled,
      uploadQuotaBytes: uploadQuotaBytes ?? current.uploadQuotaBytes,
      disabled: disabled ?? current.disabled,
      hasPassword: current.hasPassword,
      pending: current.pending,
      permissions: permissions ?? current.permissions,
    );
    usersById[userId] = updated;
    return updated;
  }

  @override
  Future<UserAccount> getUser(String userId) async {
    final account = usersById[userId];
    if (account == null) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such user',
        statusCode: 404,
      );
    }
    return account;
  }

  /// Ids removed by [deleteUser], in order.
  final List<String> deletedUserIds = [];

  @override
  Future<void> deleteUser(String userId) async {
    deletedUserIds.add(userId);
    usersById.remove(userId);
  }

  /// Administrator password resets, in order.
  final List<({String userId, String newPassword})> setUserPasswordCalls = [];

  @override
  Future<void> setUserPassword(String userId, String newPassword) async {
    setUserPasswordCalls.add((userId: userId, newPassword: newPassword));
  }

  /// Ids whose sessions were revoked wholesale, in order.
  final List<String> revokeUserSessionsCalls = [];

  @override
  Future<void> revokeUserSessions(String userId) async {
    revokeUserSessionsCalls.add(userId);
  }

  /// Thrown by [signup] when set.
  WaxDeckApiException? signupError;

  final List<
    ({
      String username,
      String password,
      String? displayName,
      String? inviteToken,
    })
  >
  signupCalls = [];

  @override
  Future<SignupResult> signup({
    required String username,
    required String password,
    String? displayName,
    String? inviteToken,
  }) async {
    signupCalls.add((
      username: username,
      password: password,
      displayName: displayName,
      inviteToken: inviteToken,
    ));
    final error = signupError;
    if (error != null) throw error;
    // An invite activates the account immediately; open signup queues it.
    final active = inviteToken != null;
    final account = UserAccount(
      id: 'us-FAKE${_userSeq++}',
      username: username,
      displayName: displayName,
      roles: const ['user'],
      createdAt: DateTime.utc(2026, 7, 15),
      libraryAccess: const LibraryAccess(mode: 'all'),
      pending: !active,
    );
    usersById[account.id] = account;
    return SignupResult(state: active ? 'active' : 'pending');
  }

  @override
  Future<UserPage> listSignupRequests({String? cursor, int? limit}) async {
    final error = listError;
    if (error != null) throw error;
    final pending = usersById.values.where((u) => u.pending).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return UserPage(users: pending);
  }

  final List<
    ({
      String userId,
      List<String>? roles,
      LibraryAccess? libraryAccess,
      Permissions? permissions,
      bool? uploadEnabled,
    })
  >
  approveSignupCalls = [];

  @override
  Future<UserAccount> approveSignupRequest(
    String userId, {
    List<String>? roles,
    LibraryAccess? libraryAccess,
    Permissions? permissions,
    bool? uploadEnabled,
    int? uploadQuotaBytes,
  }) async {
    approveSignupCalls.add((
      userId: userId,
      roles: roles,
      libraryAccess: libraryAccess,
      permissions: permissions,
      uploadEnabled: uploadEnabled,
    ));
    final current = usersById[userId];
    if (current == null || !current.pending) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such signup request',
        statusCode: 404,
      );
    }
    final approved = UserAccount(
      id: current.id,
      username: current.username,
      displayName: current.displayName,
      roles: roles ?? current.roles,
      createdAt: current.createdAt,
      libraryAccess: libraryAccess ?? current.libraryAccess,
      uploadEnabled: uploadEnabled ?? current.uploadEnabled,
      uploadQuotaBytes: uploadQuotaBytes ?? current.uploadQuotaBytes,
      permissions: permissions ?? current.permissions,
    );
    usersById[userId] = approved;
    return approved;
  }

  /// Ids rejected, in order.
  final List<String> rejectSignupCalls = [];

  @override
  Future<void> rejectSignupRequest(String userId) async {
    rejectSignupCalls.add(userId);
    usersById.remove(userId);
  }

  /// Invites by id.
  final Map<String, Invite> invitesById = {};
  int _inviteSeq = 0;

  @override
  Future<List<Invite>> listInvites() async {
    final error = listError;
    if (error != null) throw error;
    return invitesById.values.toList();
  }

  @override
  Future<InviteCreated> createInvite({
    String? note,
    List<String>? roles,
    LibraryAccess? libraryAccess,
    Permissions? permissions,
    bool? uploadEnabled,
    int? maxUses,
    DateTime? expiresAt,
  }) async {
    final seq = _inviteSeq++;
    final created = InviteCreated(
      id: 'iv-FAKE$seq',
      note: note,
      roles: roles ?? const ['user'],
      libraryAccess: libraryAccess,
      permissions: permissions,
      uploadEnabled: uploadEnabled ?? false,
      maxUses: maxUses ?? 1,
      createdAt: DateTime.utc(2026, 7, 15),
      token: 'invite-token-$seq',
    );
    invitesById[created.id] = created;
    return created;
  }

  /// Ids revoked, in order.
  final List<String> revokeInviteCalls = [];

  @override
  Future<void> revokeInvite(String inviteId) async {
    revokeInviteCalls.add(inviteId);
    final current = invitesById[inviteId];
    if (current == null) return;
    invitesById[inviteId] = Invite(
      id: current.id,
      note: current.note,
      roles: current.roles,
      libraryAccess: current.libraryAccess,
      permissions: current.permissions,
      uploadEnabled: current.uploadEnabled,
      maxUses: current.maxUses,
      usedCount: current.usedCount,
      revoked: true,
      expiresAt: current.expiresAt,
      createdAt: current.createdAt,
      createdBy: current.createdBy,
    );
  }

  /// Audit events, newest first, served by [listAuditEvents].
  List<AuditEvent> auditEvents = [];

  @override
  Future<AuditEventPage> listAuditEvents({
    String? cursor,
    int? limit,
    String? action,
    String? actorId,
    String? targetPid,
  }) async {
    final error = listError;
    if (error != null) throw error;
    final filtered = auditEvents
        .where((e) => action == null || e.action.startsWith(action))
        .where((e) => actorId == null || e.actorId == actorId)
        .where((e) => targetPid == null || e.targetPid == targetPid)
        .toList();
    final start = cursor == null ? 0 : int.parse(cursor);
    final pageSize = limit ?? 100;
    final end = (start + pageSize).clamp(0, filtered.length);
    return AuditEventPage(
      events: filtered.sublist(start.clamp(0, filtered.length), end),
      nextCursor: end < filtered.length ? '$end' : null,
    );
  }

  /// Server-wide switches served and replaced by the settings endpoints.
  AdminSettings adminSettings = const AdminSettings(
    signupEnabled: false,
    readOnly: false,
    sonicAnalysis: true,
    backupKeepCount: 5,
    backupKeepBytes: 0,
  );

  /// Thrown by the admin mutation endpoints when set.
  WaxDeckApiException? adminError;

  @override
  Future<AdminSettings> getAdminSettings() async => adminSettings;

  @override
  Future<AdminSettings> putAdminSettings(AdminSettings settings) async {
    final error = adminError;
    if (error != null) throw error;
    adminSettings = settings;
    return settings;
  }

  TranscodingLimits transcodingLimits = const TranscodingLimits(
    maxConcurrent: 2,
    maxConcurrentPerUser: 1,
    defaultMaxBitrateKbps: 0,
  );

  @override
  Future<TranscodingLimits> getTranscodingLimits() async => transcodingLimits;

  @override
  Future<TranscodingLimits> putTranscodingLimits(
    TranscodingLimits limits,
  ) async {
    final error = adminError;
    if (error != null) throw error;
    transcodingLimits = limits;
    return limits;
  }

  /// Maintenance schedules by kind.
  final Map<String, Schedule> schedules = {
    for (final kind in const ['scan', 'backup', 'prune'])
      kind: Schedule(kind: kind, cron: '0 3 * * *', enabled: false),
  };

  final List<({String kind, String cron, bool enabled})> putScheduleCalls = [];

  @override
  Future<List<Schedule>> listSchedules() async => schedules.values.toList();

  @override
  Future<Schedule> putSchedule(
    String kind, {
    required String cron,
    required bool enabled,
  }) async {
    putScheduleCalls.add((kind: kind, cron: cron, enabled: enabled));
    final error = adminError;
    if (error != null) throw error;
    // The server validates the cron expression; five fields, like it does.
    if (cron.trim().split(RegExp(r'\s+')).length != 5) {
      throw const WaxDeckApiException(
        code: 'validation',
        message: 'invalid cron expression',
        statusCode: 400,
      );
    }
    final current = schedules[kind]!;
    final stored = Schedule(
      kind: kind,
      cron: cron,
      enabled: enabled,
      lastRunAt: current.lastRunAt,
      lastStatus: current.lastStatus,
      lastError: current.lastError,
      nextRunAt: enabled ? DateTime.utc(2026, 7, 22, 3) : null,
    );
    schedules[kind] = stored;
    return stored;
  }

  /// Backup archives by id, newest last.
  final Map<String, Backup> backupsById = {};
  int _backupSeq = 0;
  int createBackupCalls = 0;

  @override
  Future<List<Backup>> listBackups() async {
    final error = listError;
    if (error != null) throw error;
    return backupsById.values.toList().reversed.toList();
  }

  @override
  Future<Backup> createBackup() async {
    final error = adminError;
    if (error != null) throw error;
    createBackupCalls++;
    final backup = Backup(
      id: 'ba-FAKE${_backupSeq++}',
      state: 'running',
      trigger: 'manual',
      fileName: 'waxdeck-2026-07-20-$_backupSeq.tar.zst',
      createdAt: DateTime.utc(2026, 7, 20, 12),
    );
    backupsById[backup.id] = backup;
    return backup;
  }

  @override
  Future<Backup> getBackup(String backupId) async {
    final backup = backupsById[backupId];
    if (backup == null) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such backup',
        statusCode: 404,
      );
    }
    return backup;
  }

  /// Ids deleted, in order.
  final List<String> deleteBackupCalls = [];

  @override
  Future<void> deleteBackup(String backupId) async {
    final error = adminError;
    if (error != null) throw error;
    deleteBackupCalls.add(backupId);
    backupsById.remove(backupId);
  }

  /// Byte counts of each imported archive, drained from its stream.
  final List<int> importBackupByteCounts = [];

  @override
  Future<Backup> importBackup({
    required int sizeBytes,
    required Stream<List<int>> Function() openRead,
  }) async {
    final error = adminError;
    if (error != null) throw error;
    var received = 0;
    await for (final chunk in openRead()) {
      received += chunk.length;
    }
    importBackupByteCounts.add(received);
    final backup = Backup(
      id: 'ba-FAKE${_backupSeq++}',
      state: 'done',
      trigger: 'imported',
      fileName: 'imported-$_backupSeq.zip',
      sizeBytes: received,
      createdAt: DateTime.utc(2026, 7, 20, 12),
    );
    backupsById[backup.id] = backup;
    return backup;
  }

  @override
  String backupArchiveUrl(String backupId) =>
      '/api/v1/admin/backups/$backupId/archive';

  /// Preset restore plans by backup id; [stageRestore] falls back to a
  /// clean plan.
  final Map<String, RestorePlan> restorePlans = {};

  /// The staged restore served by [getStagedRestore].
  RestorePlan? stagedRestore;

  /// Ids staged, in order.
  final List<String> stageRestoreCalls = [];
  int cancelStagedRestoreCalls = 0;

  @override
  Future<RestorePlan> stageRestore(String backupId) async {
    final error = adminError;
    if (error != null) throw error;
    stageRestoreCalls.add(backupId);
    final plan =
        restorePlans[backupId] ??
        RestorePlan(
          backupId: backupId,
          stagedAt: DateTime.utc(2026, 7, 20, 13),
          keyfilePresent: true,
          keyfileMatches: true,
        );
    stagedRestore = plan;
    return plan;
  }

  @override
  Future<RestorePlan?> getStagedRestore() async => stagedRestore;

  @override
  Future<void> cancelStagedRestore() async {
    cancelStagedRestoreCalls++;
    stagedRestore = null;
  }

  final List<
    ({
      String source,
      String serverUrl,
      String? username,
      String? password,
      String? token,
      MigrationOptions? options,
      bool dryRun,
    })
  >
  createMigrationCalls = [];

  @override
  Future<ToolTask> createMigration({
    required String source,
    required String serverUrl,
    String? username,
    String? password,
    String? token,
    MigrationOptions? options,
    bool dryRun = false,
  }) async {
    final error = adminError;
    if (error != null) throw error;
    createMigrationCalls.add((
      source: source,
      serverUrl: serverUrl,
      username: username,
      password: password,
      token: token,
      options: options,
      dryRun: dryRun,
    ));
    final task = ToolTask(
      id: 'tt-FAKE${_toolTaskSeq++}',
      type: 'import-$source',
      state: 'queued',
      createdAt: DateTime.utc(2026, 7, 20, 14),
    );
    toolTasksById[task.id] = task;
    return task;
  }

  /// Trash entries served by [listTrash].
  final List<TrashEntry> trashEntries = [];

  @override
  Future<TrashList> listTrash({
    bool includeRestored = false,
    int? limit,
  }) async {
    final error = listError;
    if (error != null) throw error;
    final entries = trashEntries
        .where((e) => includeRestored || e.restoredAt == null)
        .take(limit ?? 200)
        .toList();
    return TrashList(entries: entries);
  }

  /// Ids restored, in order.
  final List<String> restoreTrashCalls = [];
  int emptyTrashCalls = 0;

  @override
  Future<void> restoreTrashEntry(String trashId) async {
    final error = adminError;
    if (error != null) throw error;
    restoreTrashCalls.add(trashId);
    final index = trashEntries.indexWhere((e) => e.id == trashId);
    if (index < 0) return;
    final entry = trashEntries[index];
    trashEntries[index] = TrashEntry(
      id: entry.id,
      itemPid: entry.itemPid,
      name: entry.name,
      reason: entry.reason,
      sizeBytes: entry.sizeBytes,
      trashedAt: entry.trashedAt,
      restoredAt: DateTime.utc(2026, 7, 20, 15),
    );
  }

  @override
  Future<TrashEmptyResult> emptyTrash() async {
    final error = adminError;
    if (error != null) throw error;
    emptyTrashCalls++;
    final purgeable = trashEntries.where((e) => e.restoredAt == null).toList();
    trashEntries.removeWhere((e) => e.restoredAt == null);
    return TrashEmptyResult(
      purged: purgeable.length,
      errored: 0,
      reclaimedBytes: purgeable.fold(0, (sum, e) => sum + e.sizeBytes),
    );
  }

  /// Background jobs served by [listJobs].
  List<Job> jobs = [];

  @override
  Future<List<Job>> listJobs() async => List.of(jobs);

  /// Per-library read-only flags; absent means false.
  final Map<String, bool> libraryReadOnlyByPid = {};

  final List<({String libraryPid, bool readOnly})> setLibraryReadOnlyCalls = [];

  @override
  Future<bool> getLibraryReadOnly(String libraryPid) async =>
      libraryReadOnlyByPid[libraryPid] ?? false;

  @override
  Future<bool> setLibraryReadOnly(String libraryPid, bool readOnly) async {
    final error = adminError;
    if (error != null) throw error;
    setLibraryReadOnlyCalls.add((libraryPid: libraryPid, readOnly: readOnly));
    libraryReadOnlyByPid[libraryPid] = readOnly;
    return readOnly;
  }

  /// Preset delete plans by pid; absent pids get one file of 1 MiB.
  final Map<String, DeletePlanEntry> deletePlansByPid = {};

  /// Thrown by [deleteLibraryItems] when set.
  WaxDeckApiException? deleteItemsError;

  final List<({List<String> pids, String? mode, bool dryRun})>
  deleteItemsCalls = [];

  @override
  Future<DeleteItemsResult> deleteLibraryItems({
    required List<String> pids,
    String? mode,
    bool dryRun = false,
  }) async {
    final error = deleteItemsError;
    if (error != null) throw error;
    deleteItemsCalls.add((pids: pids, mode: mode, dryRun: dryRun));
    final entries = [
      for (final pid in pids)
        deletePlansByPid[pid] ??
            DeletePlanEntry(pid: pid, files: 1, bytes: 1048576),
    ];
    if (!dryRun) {
      libraryItems.removeWhere((item) => pids.contains(item.pid));
    }
    return DeleteItemsResult(
      applied: !dryRun,
      mode: mode ?? 'trash',
      entries: entries,
    );
  }

  /// Thrown by the discovery endpoints (similar tracks, instant mix,
  /// sonic path) when set.
  WaxDeckApiException? discoveryError;

  /// Canned results served by the discovery endpoints.
  SimilarTracks similarTracksResult = const SimilarTracks(
    basis: MixBasis.metadata,
  );
  InstantMix instantMixResult = const InstantMix(basis: MixBasis.metadata);
  SonicPath sonicPathResult = const SonicPath(complete: false);

  final List<({String pid, int? limit})> similarTracksCalls = [];
  final List<
    ({
      String? seedPid,
      String? genre,
      double? adventurousness,
      int? size,
      List<String> excludePids,
    })
  >
  instantMixCalls = [];
  final List<({String from, String to, int? length})> sonicPathCalls = [];

  @override
  Future<SimilarTracks> getSimilarTracks(String pid, {int? limit}) async {
    similarTracksCalls.add((pid: pid, limit: limit));
    final error = discoveryError;
    if (error != null) throw error;
    return similarTracksResult;
  }

  @override
  Future<InstantMix> createInstantMix({
    String? seedPid,
    String? genre,
    double? adventurousness,
    int? size,
    List<String> excludePids = const [],
  }) async {
    instantMixCalls.add((
      seedPid: seedPid,
      genre: genre,
      adventurousness: adventurousness,
      size: size,
      excludePids: List.of(excludePids),
    ));
    final error = discoveryError;
    if (error != null) throw error;
    return instantMixResult;
  }

  @override
  Future<SonicPath> getSonicPath({
    required String from,
    required String to,
    int? length,
  }) async {
    sonicPathCalls.add((from: from, to: to, length: length));
    final error = discoveryError;
    if (error != null) throw error;
    return sonicPathResult;
  }

  /// Thrown by the stats endpoints when set.
  WaxDeckApiException? statsError;

  /// Canned aggregates served by the stats endpoints.
  ListeningStats listeningStats = const ListeningStats(
    range: '30d',
    bucket: 'day',
    timezone: 'UTC',
    totalMs: 0,
    sessions: 0,
    timeSavedMs: 0,
  );
  ListeningHeatmap heatmap = const ListeningHeatmap(
    year: 2026,
    timezone: 'UTC',
    currentStreakDays: 0,
    longestStreakDays: 0,
  );

  /// Top lists by kind; unset kinds answer an empty list.
  final Map<String, TopList> topLists = {};

  /// Listen log entries, newest first, paged like the other lists.
  List<ListenLogEntry> listenLog = [];

  /// Year-in-review recaps; null answers an all-zero recap for the
  /// requested year.
  YearInReview? yearInReview;
  ServerYearInReview? serverYearInReview;

  final List<({String? range, String? bucket})> listeningStatsCalls = [];
  final List<int?> heatmapCalls = [];
  final List<({String kind, String? range, int? limit})> topListCalls = [];
  final List<({String? client, String? cursor, int? limit})> listenLogCalls =
      [];
  final List<int?> yearInReviewCalls = [];
  final List<int?> serverYearInReviewCalls = [];

  @override
  Future<ListeningStats> getListeningStats({
    String? range,
    String? bucket,
  }) async {
    listeningStatsCalls.add((range: range, bucket: bucket));
    final error = statsError;
    if (error != null) throw error;
    return listeningStats;
  }

  @override
  Future<ListeningHeatmap> getListeningHeatmap({int? year}) async {
    heatmapCalls.add(year);
    final error = statsError;
    if (error != null) throw error;
    return heatmap;
  }

  @override
  Future<TopList> getTopList({
    required String kind,
    String? range,
    int? limit,
  }) async {
    topListCalls.add((kind: kind, range: range, limit: limit));
    final error = statsError;
    if (error != null) throw error;
    return topLists[kind] ?? TopList(kind: kind, range: range ?? '30d');
  }

  @override
  Future<ListenLogPage> listListenLog({
    String? client,
    String? cursor,
    int? limit,
  }) async {
    listenLogCalls.add((client: client, cursor: cursor, limit: limit));
    final error = statsError;
    if (error != null) throw error;
    final filtered = client == null
        ? listenLog
        : listenLog.where((e) => e.client == client).toList();
    final start = cursor == null ? 0 : int.parse(cursor);
    final pageSize = limit ?? 50;
    final end = (start + pageSize).clamp(0, filtered.length);
    return ListenLogPage(
      sessions: filtered.sublist(start.clamp(0, filtered.length), end),
      nextCursor: end < filtered.length ? '$end' : null,
    );
  }

  @override
  Future<YearInReview> getYearInReview({int? year}) async {
    yearInReviewCalls.add(year);
    final error = statsError;
    if (error != null) throw error;
    return yearInReview ??
        YearInReview(
          year: year ?? 2026,
          timezone: 'UTC',
          totalMs: 0,
          sessions: 0,
          distinctItems: 0,
          newInLibrary: 0,
          timeSavedMs: 0,
          longestStreakDays: 0,
          byMonth: [
            for (var month = 1; month <= 12; month++)
              MonthListening(month: month, ms: 0, sessions: 0),
          ],
        );
  }

  @override
  Future<ServerYearInReview> getServerYearInReview({int? year}) async {
    serverYearInReviewCalls.add(year);
    final error = statsError;
    if (error != null) throw error;
    return serverYearInReview ??
        ServerYearInReview(
          year: year ?? 2026,
          participants: 0,
          totalMs: 0,
          sessions: 0,
        );
  }

  /// Thrown by the share endpoints when set.
  WaxDeckApiException? shareError;

  /// Share links, newest first; create and revoke mutate it.
  final List<Share> shares = [];
  int _shareSeq = 0;

  final List<
    ({String pid, int? expiresInHours, bool allowDownload, int? positionMs})
  >
  createShareCalls = [];
  final List<String> revokeShareCalls = [];

  @override
  Future<SharePage> listShares({String? cursor, int? limit}) async {
    final error = shareError;
    if (error != null) throw error;
    return SharePage(shares: List.of(shares));
  }

  @override
  Future<Share> createShare({
    required String pid,
    int? expiresInHours,
    bool allowDownload = false,
    int? positionMs,
  }) async {
    createShareCalls.add((
      pid: pid,
      expiresInHours: expiresInHours,
      allowDownload: allowDownload,
      positionMs: positionMs,
    ));
    final error = shareError;
    if (error != null) throw error;
    final seq = _shareSeq++;
    final createdAt = DateTime.utc(2026, 7, 20, 12);
    final target = libraryItems.where((i) => i.pid == pid).firstOrNull;
    final share = Share(
      pid: 'sh-FAKE$seq',
      url: '/s/FAKESECRET$seq',
      targetPid: pid,
      targetKind: pid.startsWith('pl-')
          ? 'playlist'
          : pid.startsWith('bk-')
          ? 'book'
          : pid.startsWith('ep-')
          ? 'episode'
          : 'track',
      targetTitle: target?.title ?? 'Shared item',
      allowDownload: allowDownload,
      positionMs: positionMs,
      createdAt: createdAt,
      expiresAt: expiresInHours == null
          ? null
          : createdAt.add(Duration(hours: expiresInHours)),
      plays: 0,
    );
    shares.insert(0, share);
    return share;
  }

  @override
  Future<void> revokeShare(String shareId) async {
    final error = shareError;
    if (error != null) throw error;
    revokeShareCalls.add(shareId);
    shares.removeWhere((s) => s.pid == shareId);
  }

  /// The canned import report; null derives an empty one from the
  /// request.
  PlaylistImportResult? playlistImportResult;

  final List<
    ({String source, String? name, String? payload, List<PortableRef>? refs})
  >
  importPlaylistCalls = [];

  @override
  Future<PlaylistImportResult> importPlaylist({
    required String source,
    String? name,
    String? payload,
    List<PortableRef>? refs,
  }) async {
    importPlaylistCalls.add((
      source: source,
      name: name,
      payload: payload,
      refs: refs == null ? null : List.of(refs),
    ));
    return playlistImportResult ??
        PlaylistImportResult(
          name: name ?? 'Imported playlist',
          requested: 0,
          resolved: 0,
          rungs: const ResolveRungCounts(
            essence: 0,
            strongId: 0,
            fingerprint: 0,
            descriptive: 0,
          ),
        );
  }

  /// The portable export served by [exportPlaylistPortable], and the
  /// pids it was asked for.
  PortablePlaylist portableExport = const PortablePlaylist(
    name: 'Portable playlist',
  );
  final List<String> exportedPortablePids = [];

  @override
  Future<PortablePlaylist> exportPlaylistPortable(String pid) async {
    exportedPortablePids.add(pid);
    return portableExport;
  }

  /// Similarity coverage served by [getSimilarityStatus].
  SimilarityStatus similarityStatus = const SimilarityStatus(
    enabled: false,
    embeddedTracks: 0,
    totalTracks: 0,
    coveragePct: 0,
    queueDepth: 0,
  );

  @override
  Future<SimilarityStatus> getSimilarityStatus() async => similarityStatus;
}

/// Handy device-session factory for tests.
DeviceSession testSession(
  String id, {
  SessionKind kind = SessionKind.device,
  String? deviceName = 'Study desktop',
  String? client,
  bool current = false,
}) => DeviceSession(
  id: id,
  kind: kind,
  deviceName: deviceName,
  client: client,
  createdAt: DateTime.utc(2026, 7, 1, 8),
  current: current,
);

/// Handy summary factory for tests.
ItemSummary testItem(
  String pid, {
  MediaType mediaType = MediaType.music,
  String title = 'Prancing Pony Blues',
  String? artist = 'The Bree Trio',
  int durationMs = 214000,
}) => ItemSummary(
  pid: pid,
  mediaType: mediaType,
  title: title,
  artist: artist,
  durationMs: durationMs,
);

/// Handy show factory for tests.
PodcastShow testShow(
  String pid, {
  String title = 'The Prancing Pony Hour',
  String? author = 'Barliman Butterbur',
  String? feedUrl = 'https://pony.example/feed.xml',
  String? descriptionHtml,
  bool explicit = false,
}) => PodcastShow(
  pid: pid,
  title: title,
  author: author,
  feedUrl: feedUrl,
  descriptionHtml: descriptionHtml,
  sourceType: 'rss',
  explicit: explicit,
);

/// Handy episode factory for tests.
EpisodeSummary testEpisode(
  String pid, {
  String showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01',
  String title = 'Pipeweed Economics',
  String? artist = 'Barliman Butterbur',
  int durationMs = 214000,
  DateTime? publishedAt,
  bool downloaded = true,
  String? fetchState,
  bool hasTranscript = false,
  bool explicit = false,
}) => EpisodeSummary(
  pid: pid,
  mediaType: MediaType.podcast,
  title: title,
  artist: artist,
  durationMs: durationMs,
  showPid: showPid,
  publishedAt: publishedAt ?? DateTime.utc(2026, 7, 10, 6),
  downloaded: downloaded,
  fetchState: fetchState,
  hasTranscript: hasTranscript,
  explicit: explicit,
);

/// Handy review-entry factory for tests.
ReviewEntry testReviewEntry(
  String id, {
  String kind = 'match',
  String status = 'pending',
  MediaType mediaType = MediaType.music,
  String origin = 'scan',
  String? title = 'Neon Meridian',
  String? artist = 'The Cardinal Waves',
  int trackCount = 10,
  String? uploadedBy,
  bool identifying = false,
  CandidateSummary? best,
}) => ReviewEntry(
  id: id,
  kind: kind,
  status: status,
  mediaType: mediaType,
  origin: origin,
  title: title,
  artist: artist,
  trackCount: trackCount,
  uploadedBy: uploadedBy,
  identifying: identifying,
  best: best,
  createdAt: DateTime.utc(2026, 7, 1),
);

/// Handy upload-session factory for tests.
UploadSession testUpload(
  String id, {
  String fileName = 'neon-meridian.flac',
  int sizeBytes = 4194304,
  int receivedBytes = 0,
  MediaType mediaType = MediaType.music,
  String? batchId,
  String state = 'receiving',
  String? reviewEntryId,
  DuplicateWarning? duplicate,
  String? uploadedBy,
}) => UploadSession(
  id: id,
  fileName: fileName,
  sizeBytes: sizeBytes,
  receivedBytes: receivedBytes,
  mediaType: mediaType,
  batchId: batchId,
  state: state,
  reviewEntryId: reviewEntryId,
  duplicate: duplicate,
  uploadedBy: uploadedBy,
  createdAt: DateTime.utc(2026, 7, 1),
);

/// A signed-in session whose user holds effective upload rights, for
/// screens gating their upload affordances.
SessionState testUploaderSession({List<String> roles = const ['user']}) =>
    SessionState(
      authenticated: true,
      user: WaxDeckUser(
        id: 'us-uploader',
        username: 'uploader',
        roles: roles,
        uploadEnabled: true,
      ),
    );

/// Handy audiobook factory for tests. With [partCount] above one the
/// book splits into equal parts of [durationMs] / [partCount] each.
BookDetail testBook(
  String pid, {
  String title = 'There And Back Again',
  List<String> authors = const ['B. Baggins'],
  List<String> narrators = const ['Frodo'],
  int durationMs = 3600000,
  int partCount = 1,
  List<ChapterMark>? chapters,
  BookSettings? settings,
  String? descriptionHtml,
}) {
  final partMs = durationMs ~/ partCount;
  return BookDetail(
    pid: pid,
    title: title,
    authors: authors,
    narrators: narrators,
    durationMs: durationMs,
    descriptionHtml: descriptionHtml,
    chapters: chapters ?? const [],
    parts: [
      for (var i = 0; i < partCount; i++)
        BookPart(index: i, startMs: i * partMs, durationMs: partMs),
    ],
    settings: settings,
  );
}
