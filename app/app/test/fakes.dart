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

  final List<({String username, String password, String? deviceName})>
  loginCalls = [];
  final List<({String username, String password, String? displayName})>
  bootstrapCalls = [];
  final List<({String code, String? verifier, String? deviceName})>
  oidcExchangeCalls = [];
  final List<String> revokedSessionIds = [];
  final List<({String pid, int positionMs})> putPlayStateCalls = [];
  final List<ListenSession> reportedSessions = [];
  int refreshCalls = 0;

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
  Future<PlayInfo> getPlayInfo(String pid) async {
    final error = playInfoError;
    if (error != null) throw error;
    return PlayInfo(
      pid: pid,
      url: '/media/stream?pid=$pid&mt=test-token',
      mimeType: 'audio/flac',
      durationMs: 214000,
      seekable: true,
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );
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

  @override
  Future<PlayState> setStar(String pid, bool starred, {DateTime? recordedAt}) {
    final error = playStateError;
    if (error != null) return _failLikeANetwork(error);
    starredByPid[pid] = starred;
    return getPlayState(pid);
  }

  @override
  Future<PlayState> setRating(String pid, int? rating, {DateTime? recordedAt}) {
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
  Future<List<AppPassword>> listAppPasswords() async => const [];

  @override
  Future<AppPasswordCreated> createAppPassword(String label) async {
    return AppPasswordCreated(
      id: 'ap-01JZX5N8QW3F4V9T2B7KD3M9R6',
      label: label,
      createdAt: DateTime.now().toUtc(),
      secret: 'FAKESECRETFAKESECRETFAKESE',
    );
  }

  @override
  Future<void> revokeAppPassword(String id) async {}

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
