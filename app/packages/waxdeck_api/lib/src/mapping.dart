/// Converters between generated built_value DTOs and the plain models.
///
/// Internal to this package: it is not exported by the barrel, so generated
/// types never escape into feature code. The package's own tests import it
/// directly to pin the mapping behavior.
library;

import 'package:waxdeck_api_gen/waxdeck_api_gen.dart' as gen;

import 'models.dart';

/// Joins an origin-relative media [url] onto [baseUrl].
///
/// With an empty base (web builds) the URL stays relative and the browser
/// resolves it against the origin serving the SPA. Absolute URLs pass
/// through untouched.
String resolveMediaUrl(String baseUrl, String url) {
  if (baseUrl.isEmpty) return url;
  if (url.contains('://')) return url;
  final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
  return url.startsWith('/') ? '$base$url' : '$base/$url';
}

MediaType mediaTypeFromGen(gen.MediaType type) {
  return MediaType.values.firstWhere(
    (m) => m.wireName == type.name,
    orElse: () => MediaType.music,
  );
}

gen.MediaType mediaTypeToGen(MediaType type) =>
    gen.MediaType.valueOf(type.wireName);

gen.DiscoveryList discoveryListToGen(DiscoveryList list) {
  return switch (list) {
    DiscoveryList.newest => gen.DiscoveryList.newest,
    DiscoveryList.recentlyAdded => gen.DiscoveryList.recentlyAdded,
    DiscoveryList.mostPlayed => gen.DiscoveryList.mostPlayed,
    DiscoveryList.recentlyPlayed => gen.DiscoveryList.recentlyPlayed,
    DiscoveryList.random => gen.DiscoveryList.random,
    DiscoveryList.starred => gen.DiscoveryList.starred,
    DiscoveryList.alphabetical => gen.DiscoveryList.alphabetical,
  };
}

WaxDeckUser userFromGen(gen.User user) {
  return WaxDeckUser(
    id: user.id,
    username: user.username,
    displayName: user.displayName,
    roles: user.roles.toList(),
  );
}

LoginResult loginResultFromGen(gen.LoginResponse response) {
  return LoginResult(user: userFromGen(response.user), token: response.token);
}

SessionState sessionStateFromGen(gen.SessionInfo info) {
  final user = info.user;
  return SessionState(
    authenticated: info.authenticated,
    user: user == null ? null : userFromGen(user),
  );
}

SessionKind sessionKindFromGen(gen.DeviceSessionKindEnum kind) {
  return SessionKind.values.firstWhere(
    (k) => k.wireName == kind.name,
    orElse: () => SessionKind.device,
  );
}

DeviceSession deviceSessionFromGen(gen.DeviceSession session) {
  return DeviceSession(
    id: session.id,
    kind: sessionKindFromGen(session.kind),
    deviceName: session.deviceName,
    client: session.client,
    createdAt: session.createdAt,
    lastSeenAt: session.lastSeenAt,
    current: session.current,
  );
}

OidcProvider oidcProviderFromGen(
  gen.OidcProvider provider, {
  String baseUrl = '',
}) {
  return OidcProvider(
    id: provider.id,
    displayName: provider.displayName,
    startUrl: resolveMediaUrl(baseUrl, provider.startUrl),
  );
}

ThemePref themePrefFromGen(gen.PrefsThemeEnum theme) {
  return ThemePref.values.firstWhere(
    (t) => t.wireName == theme.name,
    orElse: () => ThemePref.system,
  );
}

gen.PrefsThemeEnum themePrefToGen(ThemePref theme) =>
    gen.PrefsThemeEnum.valueOf(theme.wireName);

Prefs prefsFromGen(gen.Prefs prefs) {
  final theme = prefs.theme;
  return Prefs(
    timezone: prefs.timezone,
    locale: prefs.locale,
    theme: theme == null ? null : themePrefFromGen(theme),
  );
}

gen.Prefs prefsToGen(Prefs prefs) {
  final theme = prefs.theme;
  return gen.Prefs(
    (b) => b
      ..timezone = prefs.timezone
      ..locale = prefs.locale
      ..theme = theme == null ? null : themePrefToGen(theme),
  );
}

ItemSummary itemSummaryFromGen(gen.ItemSummary item, {String baseUrl = ''}) {
  final artUrl = item.artUrl;
  return ItemSummary(
    pid: item.pid,
    mediaType: mediaTypeFromGen(item.mediaType),
    title: item.title,
    artist: item.artist,
    album: item.album,
    durationMs: item.durationMs,
    artUrl: artUrl == null ? null : resolveMediaUrl(baseUrl, artUrl),
  );
}

ItemPage itemPageFromGen(gen.ItemPage page, {String baseUrl = ''}) {
  return ItemPage(
    items: page.items
        .map((item) => itemSummaryFromGen(item, baseUrl: baseUrl))
        .toList(),
    nextCursor: page.nextCursor,
    seed: page.seed,
  );
}

ItemDetail itemDetailFromGen(gen.Item item, {String baseUrl = ''}) {
  final artUrl = item.artUrl;
  return ItemDetail(
    pid: item.pid,
    mediaType: mediaTypeFromGen(item.mediaType),
    title: item.title,
    artist: item.artist,
    album: item.album,
    durationMs: item.durationMs,
    artUrl: artUrl == null ? null : resolveMediaUrl(baseUrl, artUrl),
    genres: item.genres?.toList() ?? const [],
    year: item.year,
    trackNumber: item.trackNumber,
    discNumber: item.discNumber,
    codec: item.codec,
    container: item.container,
    sampleRate: item.sampleRate,
    bitrate: item.bitrate,
    addedAt: item.addedAt,
  );
}

PlayInfo playInfoFromGen(gen.PlayInfo info, {String baseUrl = ''}) {
  return PlayInfo(
    pid: info.pid,
    url: resolveMediaUrl(baseUrl, info.url),
    mimeType: info.mimeType,
    durationMs: info.durationMs,
    seekable: info.seekable,
    expiresAt: info.expiresAt,
  );
}

PlayState playStateFromGen(gen.PlayState state) {
  return PlayState(
    pid: state.pid,
    positionMs: state.positionMs,
    played: state.played,
    finished: state.finished,
    playCount: state.playCount,
    starred: state.starred,
    rating: state.rating,
    updatedAt: state.updatedAt,
  );
}

gen.ListenSession listenSessionToGen(ListenSession session) {
  return gen.ListenSession(
    (b) => b
      ..sessionId = session.sessionId
      ..pid = session.pid
      ..startedAt = session.startedAt.toUtc()
      ..msPlayed = session.msPlayed
      ..finished = session.finished
      ..client = session.client
      ..source_ = gen.ListenSessionSource_Enum.live,
  );
}

ListenOutcome listenOutcomeFromGen(gen.ListenIngestResult result) {
  return ListenOutcome(
    accepted: result.accepted,
    duplicates: result.duplicates,
    rejected:
        result.rejected
            ?.map(
              (r) => RejectedListen(
                sessionId: r.sessionId,
                code: r.code,
                message: r.message,
              ),
            )
            .toList() ??
        const [],
  );
}

SearchHit searchHitFromGen(gen.SearchHit hit) {
  return SearchHit(
    pid: hit.pid,
    kind: hit.kind,
    title: hit.title,
    subtitle: hit.subtitle,
  );
}

SearchResults searchResultsFromGen(gen.SearchResults results) {
  List<SearchHit> hits(Iterable<gen.SearchHit> group) =>
      group.map(searchHitFromGen).toList();
  return SearchResults(
    query: results.query,
    artists: hits(results.artists),
    albums: hits(results.albums),
    tracks: hits(results.tracks),
    books: hits(results.books),
    episodes: hits(results.episodes),
    truncated: results.truncated ?? false,
  );
}

CatalogSyncPage catalogSyncPageFromGen(
  gen.CatalogSyncPage page, {
  String baseUrl = '',
}) {
  return CatalogSyncPage(
    entries: page.entries
        .map(
          (e) => CatalogSyncEntry(
            op: e.op,
            pid: e.pid,
            item: e.item == null
                ? null
                : itemSummaryFromGen(e.item!, baseUrl: baseUrl),
          ),
        )
        .toList(),
    nextCursor: page.nextCursor,
    nextSince: page.nextSince,
    more: page.more ?? false,
  );
}

ServerSyncPage serverSyncPageFromGen(gen.ServerSyncPage page) {
  return ServerSyncPage(
    events: page.events
        .map(
          (e) => ServerSyncEvent(
            kind: e.kind,
            pid: e.pid,
            playState: e.playState == null
                ? null
                : playStateFromGen(e.playState!),
            prefs: e.prefs == null ? null : prefsFromGen(e.prefs!),
          ),
        )
        .toList(),
    nextSince: page.nextSince,
    more: page.more ?? false,
  );
}

DownloadInfo downloadInfoFromGen(gen.DownloadInfo info, {String baseUrl = ''}) {
  return DownloadInfo(
    pid: info.pid,
    files: info.files
        .map(
          (f) => DownloadFileInfo(
            url: resolveMediaUrl(baseUrl, f.url),
            mimeType: f.mimeType,
            sizeBytes: f.sizeBytes,
            fileName: f.fileName,
            essenceHash: f.essenceHash,
            etag: f.etag,
          ),
        )
        .toList(),
    spanStartMs: info.spanStartMs,
    spanEndMs: info.spanEndMs,
    expiresAt: info.expiresAt,
  );
}

AppPassword appPasswordFromGen(gen.AppPassword ap) {
  return AppPassword(
    id: ap.id,
    label: ap.label,
    createdAt: ap.createdAt,
    lastUsedAt: ap.lastUsedAt,
  );
}
