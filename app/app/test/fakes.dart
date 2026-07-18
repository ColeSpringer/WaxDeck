import 'package:waxdeck_api/waxdeck_api.dart';

/// In-memory repository for widget tests. Pagination uses the item index as
/// the cursor, which is enough to exercise keyset-style paging end to end.
class FakeRepository implements WaxDeckRepository {
  FakeRepository({
    SessionState? sessionState,
    List<ItemSummary> items = const [],
    this.recentlyPlayed,
  }) : sessionState = sessionState ?? const SessionState(authenticated: false),
       libraryItems = List.of(items);

  SessionState sessionState;
  List<ItemSummary> libraryItems;

  /// Item surfaced by the recently-played browse list, if any.
  ItemSummary? recentlyPlayed;

  /// Saved resume positions by pid.
  final Map<String, int> playPositions = {};

  /// Thrown by [login] when set, to exercise the error path.
  WaxDeckApiException? loginError;

  /// Thrown by [reportListens] when set, to exercise the retry path.
  WaxDeckApiException? reportError;

  final List<({String username, String password})> loginCalls = [];
  final List<({String pid, int positionMs})> putPlayStateCalls = [];
  final List<ListenSession> reportedSessions = [];

  static const _user = WaxDeckUser(
    id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
    username: 'admin',
    roles: ['admin'],
  );

  @override
  Future<ServerHealth> health() async =>
      const ServerHealth(status: 'ok', version: 'test', apiVersion: 1);

  @override
  Future<LoginResult> login({
    required String username,
    required String password,
  }) async {
    loginCalls.add((username: username, password: password));
    final error = loginError;
    if (error != null) throw error;
    sessionState = const SessionState(authenticated: true, user: _user);
    return const LoginResult(user: _user, token: 'test-token');
  }

  @override
  Future<SessionState> getSession() async => sessionState;

  @override
  Future<void> logout() async {
    sessionState = const SessionState(authenticated: false);
  }

  @override
  Future<ItemPage> listItems({
    MediaType? mediaType,
    String? cursor,
    int? limit,
  }) async {
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
  Future<PlayInfo> getPlayInfo(String pid) async => PlayInfo(
    pid: pid,
    url: '/media/stream?pid=$pid&mt=test-token',
    mimeType: 'audio/flac',
    durationMs: 214000,
    seekable: true,
    expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
  );

  @override
  Future<PlayState> getPlayState(String pid) async => PlayState(
    pid: pid,
    positionMs: playPositions[pid] ?? 0,
    played: false,
    finished: false,
    playCount: 0,
    starred: false,
  );

  @override
  Future<void> putPlayState(String pid, int positionMs) async {
    putPlayStateCalls.add((pid: pid, positionMs: positionMs));
    playPositions[pid] = positionMs;
  }

  @override
  Future<ListenOutcome> reportListens(List<ListenSession> sessions) async {
    final error = reportError;
    if (error != null) throw error;
    reportedSessions.addAll(sessions);
    return ListenOutcome(accepted: sessions.length, duplicates: 0);
  }
}

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
