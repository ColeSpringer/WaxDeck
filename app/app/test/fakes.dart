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
  Future<BootstrapStatus> bootstrapStatus() async =>
      BootstrapStatus(required: bootstrapNeeded);

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

  @override
  Future<Prefs> putPrefs(Prefs next) async => prefs = next;

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

  /// Push registrations served and mutated by the push endpoints.
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
      pid: 'pr-FAKE${pushRegistrations.length}',
      endpoint: endpoint,
      label: label,
      createdAt: DateTime.utc(2026),
    );
    pushRegistrations.add(reg);
    return reg;
  }

  @override
  Future<void> deletePushRegistration(String pid) async {
    pushRegistrations.removeWhere((r) => r.pid == pid);
  }

  /// Notification configuration served and replaced by the admin
  /// endpoints.
  NotificationConfig notificationConfig = const NotificationConfig(
    appriseUrl: '',
    enabledEvents: [],
    knownEvents: ['test', 'episode-downloaded', 'feed-disabled'],
  );

  /// Count of admin test notifications requested.
  int notificationTests = 0;

  @override
  Future<NotificationConfig> getNotificationConfig() async =>
      notificationConfig;

  @override
  Future<NotificationConfig> putNotificationConfig({
    required String appriseUrl,
    String? targets,
    required List<String> enabledEvents,
  }) async {
    notificationConfig = NotificationConfig(
      appriseUrl: appriseUrl,
      targets: targets,
      enabledEvents: enabledEvents,
      knownEvents: notificationConfig.knownEvents,
    );
    return notificationConfig;
  }

  @override
  Future<void> testNotifications() async {
    notificationTests++;
  }
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
}) => PodcastShow(
  pid: pid,
  title: title,
  author: author,
  feedUrl: feedUrl,
  descriptionHtml: descriptionHtml,
  sourceType: 'rss',
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
