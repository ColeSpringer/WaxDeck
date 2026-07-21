/// Converters between generated built_value DTOs and the plain models.
///
/// Internal to this package: it is not exported by the barrel, so generated
/// types never escape into feature code. The package's own tests import it
/// directly to pin the mapping behavior.
library;

import 'package:built_collection/built_collection.dart';
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
    partIndex: info.partIndex,
    partCount: info.partCount,
    partStartMs: info.partStartMs,
    voiceBoost: info.voiceBoost ?? false,
    spanStartMs: info.spanStartMs,
    spanEndMs: info.spanEndMs,
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
            episode: e.episode == null
                ? null
                : episodeSummaryFromGen(e.episode!, baseUrl: baseUrl),
            show: e.show_ == null
                ? null
                : podcastShowFromGen(e.show_!, baseUrl: baseUrl),
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
            subscription: e.subscription == null
                ? null
                : subscriptionFromGen(e.subscription!),
            bookSettings: e.bookSettings == null
                ? null
                : bookSettingsFromGen(e.bookSettings!),
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

PodcastShow podcastShowFromGen(gen.PodcastShow show, {String baseUrl = ''}) {
  final artUrl = show.artUrl;
  return PodcastShow(
    pid: show.pid,
    title: show.title,
    author: show.author,
    descriptionHtml: show.descriptionHtml,
    feedUrl: show.feedUrl,
    link: show.link,
    sourceType: show.sourceType,
    artUrl: artUrl == null ? null : resolveMediaUrl(baseUrl, artUrl),
    episodeCount: show.episodeCount,
    lastPublishedAt: show.lastPublishedAt,
    refreshDisabled: show.refreshDisabled ?? false,
  );
}

SubscriptionSettings subscriptionSettingsFromGen(
  gen.SubscriptionSettings settings,
) {
  return SubscriptionSettings(
    retentionKeep: settings.retentionKeep,
    autoDownload: settings.autoDownload ?? false,
    folder: settings.folder,
    private: settings.private ?? false,
    speed: settings.speed,
    trimSilence: settings.trimSilence,
    voiceBoost: settings.voiceBoost,
    skipIntroSeconds: settings.skipIntroSeconds,
    skipOutroSeconds: settings.skipOutroSeconds,
  );
}

gen.SubscriptionSettings subscriptionSettingsToGen(
  SubscriptionSettings settings,
) {
  return gen.SubscriptionSettings(
    (b) => b
      ..retentionKeep = settings.retentionKeep
      ..autoDownload = settings.autoDownload
      ..folder = settings.folder
      ..private = settings.private
      ..speed = settings.speed
      ..trimSilence = settings.trimSilence
      ..voiceBoost = settings.voiceBoost
      ..skipIntroSeconds = settings.skipIntroSeconds
      ..skipOutroSeconds = settings.skipOutroSeconds,
  );
}

Subscription subscriptionFromGen(gen.Subscription sub, {String baseUrl = ''}) {
  return Subscription(
    show: podcastShowFromGen(sub.show_, baseUrl: baseUrl),
    settings: subscriptionSettingsFromGen(sub.settings),
    subscribedAt: sub.subscribedAt,
  );
}

PodcastDetail podcastDetailFromGen(
  gen.PodcastDetail detail, {
  String baseUrl = '',
}) {
  final settings = detail.settings;
  return PodcastDetail(
    show: podcastShowFromGen(detail.show_, baseUrl: baseUrl),
    subscribed: detail.subscribed,
    settings: settings == null ? null : subscriptionSettingsFromGen(settings),
  );
}

SubscriptionPage subscriptionPageFromGen(
  gen.SubscriptionPage page, {
  String baseUrl = '',
}) {
  return SubscriptionPage(
    items: page.items
        .map((s) => subscriptionFromGen(s, baseUrl: baseUrl))
        .toList(),
    nextCursor: page.nextCursor,
  );
}

EpisodeSummary episodeSummaryFromGen(
  gen.EpisodeSummary episode, {
  String baseUrl = '',
}) {
  final artUrl = episode.artUrl;
  return EpisodeSummary(
    pid: episode.pid,
    mediaType: mediaTypeFromGen(episode.mediaType),
    title: episode.title,
    artist: episode.artist,
    album: episode.album,
    durationMs: episode.durationMs,
    artUrl: artUrl == null ? null : resolveMediaUrl(baseUrl, artUrl),
    showPid: episode.showPid,
    season: episode.season,
    episodeNumber: episode.episodeNumber,
    episodeType: episode.episodeType,
    publishedAt: episode.publishedAt,
    downloaded: episode.downloaded,
    fetchState: episode.fetchState,
    fetchError: episode.fetchError,
    explicit: episode.explicit ?? false,
    hasTranscript: episode.hasTranscript ?? false,
  );
}

EpisodePage episodePageFromGen(gen.EpisodePage page, {String baseUrl = ''}) {
  return EpisodePage(
    items: page.items
        .map((e) => episodeSummaryFromGen(e, baseUrl: baseUrl))
        .toList(),
    nextCursor: page.nextCursor,
  );
}

ChapterMark chapterMarkFromGen(gen.ChapterMark mark) {
  return ChapterMark(
    index: mark.index,
    title: mark.title,
    startMs: mark.startMs,
    endMs: mark.endMs,
  );
}

EpisodeDetail episodeDetailFromGen(gen.Episode episode, {String baseUrl = ''}) {
  final artUrl = episode.artUrl;
  return EpisodeDetail(
    pid: episode.pid,
    mediaType: mediaTypeFromGen(episode.mediaType),
    title: episode.title,
    artist: episode.artist,
    album: episode.album,
    durationMs: episode.durationMs,
    artUrl: artUrl == null ? null : resolveMediaUrl(baseUrl, artUrl),
    showPid: episode.showPid,
    season: episode.season,
    episodeNumber: episode.episodeNumber,
    episodeType: episode.episodeType,
    publishedAt: episode.publishedAt,
    downloaded: episode.downloaded,
    fetchState: episode.fetchState,
    fetchError: episode.fetchError,
    explicit: episode.explicit ?? false,
    hasTranscript: episode.hasTranscript ?? false,
    descriptionHtml: episode.descriptionHtml,
    link: episode.link,
    chapters: episode.chapters?.map(chapterMarkFromGen).toList() ?? const [],
  );
}

Transcript transcriptFromGen(gen.Transcript transcript) {
  return Transcript(
    format: transcript.format,
    cues: transcript.cues
        .map(
          (c) => TranscriptCue(
            startMs: c.startMs,
            endMs: c.endMs,
            text: c.text,
            speaker: c.speaker,
          ),
        )
        .toList(),
  );
}

BookSettings bookSettingsFromGen(gen.BookSettings settings) {
  return BookSettings(
    speed: settings.speed,
    voiceBoost: settings.voiceBoost,
    trimSilence: settings.trimSilence,
  );
}

gen.BookSettings bookSettingsToGen(BookSettings settings) {
  return gen.BookSettings(
    (b) => b
      ..speed = settings.speed
      ..voiceBoost = settings.voiceBoost
      ..trimSilence = settings.trimSilence,
  );
}

BookDetail bookDetailFromGen(gen.BookDetail book, {String baseUrl = ''}) {
  final artUrl = book.artUrl;
  final settings = book.settings;
  return BookDetail(
    pid: book.pid,
    title: book.title,
    subtitle: book.subtitle,
    authors: book.authors.toList(),
    narrators: book.narrators.toList(),
    series: book.series,
    seriesSequence: book.seriesSequence,
    publisher: book.publisher,
    asin: book.asin,
    isbn: book.isbn,
    edition: book.edition,
    abridged: book.abridged,
    descriptionHtml: book.descriptionHtml,
    durationMs: book.durationMs,
    artUrl: artUrl == null ? null : resolveMediaUrl(baseUrl, artUrl),
    chapters: book.chapters.map(chapterMarkFromGen).toList(),
    parts: book.parts
        .map(
          (p) => BookPart(
            index: p.index,
            startMs: p.startMs,
            durationMs: p.durationMs,
            displayName: p.displayName,
          ),
        )
        .toList(),
    settings: settings == null ? null : bookSettingsFromGen(settings),
  );
}

BookResume bookResumeFromGen(gen.BookResume resume) {
  final chapter = resume.chapter;
  return BookResume(
    positionMs: resume.positionMs,
    chapter: chapter == null ? null : chapterMarkFromGen(chapter),
    updatedAt: resume.updatedAt,
  );
}

SkipMap skipMapFromGen(gen.SkipMap map) {
  return SkipMap(
    state: map.state,
    essenceHash: map.essenceHash,
    partIndex: map.partIndex,
    version: map.version,
    spans:
        map.spans
            ?.map((s) => SkipSpan(startMs: s.startMs, endMs: s.endMs))
            .toList() ??
        const [],
  );
}

RuleNode ruleNodeFromGen(gen.RuleNode node) {
  final inner = node.node;
  return RuleNode(
    type: node.type,
    nodes: node.nodes?.map(ruleNodeFromGen).toList() ?? const [],
    node: inner == null ? null : ruleNodeFromGen(inner),
    field: node.field,
    op: node.op,
    value: node.value,
    values: node.values?.toList() ?? const [],
  );
}

gen.RuleNode ruleNodeToGen(RuleNode node) {
  final inner = node.node;
  return gen.RuleNode(
    (b) => b
      ..type = node.type
      ..nodes = node.nodes.isEmpty
          ? null
          : ListBuilder<gen.RuleNode>(node.nodes.map(ruleNodeToGen))
      ..node = inner == null ? null : ruleNodeToGen(inner).toBuilder()
      ..field = node.field
      ..op = node.op
      ..value = node.value
      ..values = node.values.isEmpty ? null : ListBuilder<String>(node.values),
  );
}

SmartRule smartRuleFromGen(gen.SmartRule rule) {
  return SmartRule(
    root: ruleNodeFromGen(rule.root),
    sorts:
        rule.sorts
            ?.map((s) => RuleSort(field: s.field, desc: s.desc ?? false))
            .toList() ??
        const [],
    limit: rule.limit ?? 0,
  );
}

gen.SmartRule smartRuleToGen(SmartRule rule) {
  return gen.SmartRule(
    (b) => b
      ..root = ruleNodeToGen(rule.root).toBuilder()
      ..sorts = rule.sorts.isEmpty
          ? null
          : ListBuilder<gen.RuleSort>(
              rule.sorts.map(
                (s) => gen.RuleSort(
                  (sb) => sb
                    ..field = s.field
                    ..desc = s.desc ? true : null,
                ),
              ),
            )
      ..limit = rule.limit > 0 ? rule.limit : null,
  );
}

Playlist playlistFromGen(gen.Playlist pl) {
  final rule = pl.rule;
  return Playlist(
    pid: pl.pid,
    previousPid: pl.previousPid,
    name: pl.name,
    kind: pl.kind,
    visibility: pl.visibility,
    ownerName: pl.ownerName,
    isOwner: pl.isOwner,
    itemCount: pl.itemCount,
    rule: rule == null ? null : smartRuleFromGen(rule),
    createdAt: pl.createdAt.toUtc(),
    updatedAt: pl.updatedAt.toUtc(),
  );
}

PlaylistPage playlistPageFromGen(gen.PlaylistPage page) {
  return PlaylistPage(
    playlists: page.playlists.map(playlistFromGen).toList(),
    nextCursor: page.nextCursor,
  );
}

PlaylistItemsPage playlistItemsPageFromGen(
  gen.PlaylistItemsPage page, {
  String baseUrl = '',
}) {
  return PlaylistItemsPage(
    entries: page.entries
        .map(
          (e) => PlaylistEntry(
            position: e.position,
            item: itemSummaryFromGen(e.item, baseUrl: baseUrl),
          ),
        )
        .toList(),
    nextCursor: page.nextCursor,
  );
}

PlaylistPreview playlistPreviewFromGen(
  gen.PlaylistPreview preview, {
  String baseUrl = '',
}) {
  return PlaylistPreview(
    items: preview.items
        .map((i) => itemSummaryFromGen(i, baseUrl: baseUrl))
        .toList(),
    total: preview.total,
  );
}

RuleFields ruleFieldsFromGen(gen.RuleFields fields) {
  return RuleFields(
    fields: fields.fields
        .map(
          (f) => RuleField(
            name: f.name,
            kind: f.kind,
            ops: f.ops.toList(),
            userState: f.userState,
            sortable: f.sortable,
            description: f.description,
          ),
        )
        .toList(),
    tagKeys: fields.tagKeys
        .map((k) => RuleTagKey(key: k.key, itemCount: k.itemCount))
        .toList(),
  );
}

M3uImportResult m3uImportResultFromGen(gen.M3uImportResult res) {
  return M3uImportResult(
    playlist: playlistFromGen(res.playlist),
    matched: res.matched,
    unmatched: res.unmatched,
    unmatchedPaths: res.unmatchedPaths?.toList() ?? const [],
  );
}

RadioStation radioStationFromGen(gen.RadioStation st) {
  return RadioStation(
    pid: st.pid,
    name: st.name,
    streamUrl: st.streamUrl,
    homepageUrl: st.homepageUrl,
    logoUrl: st.logoUrl,
    createdAt: st.createdAt.toUtc(),
  );
}

gen.RadioStationEdit radioStationEditToGen({
  required String name,
  required String streamUrl,
  String? homepageUrl,
  String? logoUrl,
}) {
  return gen.RadioStationEdit(
    (b) => b
      ..name = name
      ..streamUrl = streamUrl
      ..homepageUrl = homepageUrl
      ..logoUrl = logoUrl,
  );
}

RadioDirectoryEntry radioDirectoryEntryFromGen(gen.RadioDirectoryEntry e) {
  return RadioDirectoryEntry(
    name: e.name,
    streamUrl: e.streamUrl,
    homepageUrl: e.homepageUrl,
    logoUrl: e.logoUrl,
    tags: e.tags,
    country: e.country,
    codec: e.codec,
    bitrateKbps: e.bitrateKbps,
  );
}

Scrobbler scrobblerFromGen(gen.Scrobbler s) {
  return Scrobbler(
    service: s.service,
    available: s.available,
    connected: s.connected,
    username: s.username,
    apiUrl: s.apiUrl,
    lastSuccessAt: s.lastSuccessAt,
    lastError: s.lastError,
    lastErrorAt: s.lastErrorAt,
  );
}

NotificationConfig notificationConfigFromGen(gen.NotificationConfig c) {
  return NotificationConfig(
    appriseUrl: c.appriseUrl,
    targets: c.targets,
    enabledEvents: c.enabledEvents.toList(),
    knownEvents: c.knownEvents.toList(),
  );
}

PushRegistration pushRegistrationFromGen(gen.PushRegistration r) {
  return PushRegistration(
    pid: r.pid,
    endpoint: r.endpoint,
    label: r.label,
    createdAt: r.createdAt.toUtc(),
  );
}

PlayerEndpoint playerEndpointFromGen(gen.PlayerEndpoint ep) {
  return PlayerEndpoint(
    id: ep.id,
    kind: ep.kind,
    name: ep.name,
    online: ep.online,
    shared: ep.shared,
    mine: ep.mine,
    volumeControl: ep.volumeControl,
    rateControl: ep.rateControl,
    activeSessionId: ep.activeSessionId,
  );
}

PlaybackSessionInfo playbackSessionFromGen(gen.PlaybackSession s) {
  return PlaybackSessionInfo(
    id: s.id,
    endpointId: s.endpointId,
    endpointName: s.endpointName,
    mine: s.mine,
    ownerName: s.ownerName,
    authority: s.authority,
    playing: s.playing,
    index: s.index,
    positionMs: s.positionMs,
    positionAt: s.positionAt.toUtc(),
    rate: s.rate,
    volume: s.volume,
    repeat: s.repeat,
    shuffle: s.shuffle ?? false,
    queueVersion: s.queueVersion,
    entries: (s.entries?.toList() ?? const [])
        .map(
          (e) => PlaybackSessionEntry(
            pid: e.pid,
            title: e.title,
            artist: e.artist,
            durationMs: e.durationMs,
          ),
        )
        .toList(growable: false),
    ended: s.ended ?? false,
    updatedAt: s.updatedAt.toUtc(),
  );
}
