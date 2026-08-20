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
    DiscoveryList.neverPlayed => gen.DiscoveryList.neverPlayed,
    DiscoveryList.rediscover => gen.DiscoveryList.rediscover,
  };
}

gen.FacetSort facetSortToGen(FacetSort sort) {
  return switch (sort) {
    FacetSort.count => gen.FacetSort.count,
    FacetSort.label => gen.FacetSort.label,
  };
}

WaxDeckUser userFromGen(gen.User user) {
  return WaxDeckUser(
    id: user.id,
    username: user.username,
    displayName: user.displayName,
    roles: user.roles.toList(),
    uploadEnabled: user.uploadEnabled,
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
  // Deprecated on the wire and still read here on purpose: the theme is
  // a per-device setting now, and a device with none of its own adopts
  // the account's once so a choice made before the move is not reset.
  // ignore: deprecated_member_use
  final theme = prefs.theme;
  final favorites = prefs.radioFavorites;
  final sorts = prefs.browseSorts;
  return Prefs(
    timezone: prefs.timezone,
    locale: prefs.locale,
    theme: theme == null ? null : themePrefFromGen(theme),
    sharedStatsOptOut: prefs.sharedStatsOptOut,
    radioFavorites: favorites == null
        ? null
        : favorites.toList(growable: false),
    pinned: prefs.pinned?.toList(growable: false),
    crossfadeSeconds: prefs.crossfadeSeconds,
    replayGain: prefs.replayGain,
    radioScrobbleOptOut: prefs.radioScrobbleOptOut,
    identifyOptOut: prefs.identifyOptOut,
    browseShowUnknown: prefs.browseShowUnknown,
    // Carried in wire form: see Prefs.browseSorts.
    browseSorts: sorts == null
        ? null
        : <String, String>{
            for (final entry in sorts.entries)
              // A sort this build does not know arrives as the
              // generator's sentinel, whose name would go back out as a
              // wire value the server rejects, failing the whole save.
              // Dropped instead; that facet opens in the default.
              if (entry.value != gen.PrefsBrowseSortsEnum.unknownDefaultOpenApi)
                entry.key: entry.value.name,
          },
    autoplay: prefs.autoplay,
  );
}

gen.Prefs prefsToGen(Prefs prefs) {
  final theme = prefs.theme;
  final favorites = prefs.radioFavorites;
  final pinned = prefs.pinned;
  final sorts = prefs.browseSorts;
  return gen.Prefs(
    (b) => b
      ..timezone = prefs.timezone
      ..locale = prefs.locale
      ..theme = theme == null ? null : themePrefToGen(theme)
      ..sharedStatsOptOut = prefs.sharedStatsOptOut
      // Faithful either way: an absent list is sent absent and an empty one
      // is sent as `[]`. PUT replaces the whole document, so both clear the
      // field - which is what makes the last unpin stick, and why nothing
      // here has to invent one shape for the other.
      ..radioFavorites = favorites == null
          ? null
          : ListBuilder<String>(favorites)
      ..pinned = pinned == null ? null : ListBuilder<String>(pinned)
      ..crossfadeSeconds = prefs.crossfadeSeconds
      ..replayGain = prefs.replayGain
      ..radioScrobbleOptOut = prefs.radioScrobbleOptOut
      ..identifyOptOut = prefs.identifyOptOut
      ..browseShowUnknown = prefs.browseShowUnknown
      ..browseSorts = sorts == null
          ? null
          : MapBuilder<String, gen.PrefsBrowseSortsEnum>(
              <String, gen.PrefsBrowseSortsEnum>{
                for (final entry in sorts.entries)
                  entry.key: gen.PrefsBrowseSortsEnum.valueOf(entry.value),
              },
            )
      ..autoplay = prefs.autoplay,
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
    artistPid: item.artistPid,
    albumPid: item.albumPid,
    trackNumber: item.trackNumber,
    discNumber: item.discNumber,
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

FacetPage facetPageFromGen(gen.FacetPage page) {
  return FacetPage(
    dimension: page.dimension,
    buckets: page.buckets
        .map(
          (bucket) => FacetBucket(
            key: bucket.key,
            label: bucket.label,
            count: bucket.count,
            entityPid: bucket.entityPid,
            unknown: bucket.unknown ?? false,
            letter: bucket.letter,
          ),
        )
        .toList(),
    nextCursor: page.nextCursor,
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
    artistPid: item.artistPid,
    albumPid: item.albumPid,
    trackNumber: item.trackNumber,
    discNumber: item.discNumber,
    durationMs: item.durationMs,
    artUrl: artUrl == null ? null : resolveMediaUrl(baseUrl, artUrl),
    genres: item.genres?.toList() ?? const [],
    year: item.year,
    codec: item.codec,
    container: item.container,
    sampleRate: item.sampleRate,
    bitrate: item.bitrate,
    addedAt: item.addedAt,
  );
}

/// Null for a kind this build does not know: a card whose kind names no
/// screen has nowhere to tap, and dropping it is better than drawing it,
/// which is a shape callers already handle because the endpoint omits
/// what it cannot resolve.
///
/// A kind a newer server added deserializes to the generator's sentinel
/// rather than throwing, so it reaches this switch and takes the same
/// drop: one card missing from a shelf instead of a failed page.
EntityCardKind? entityCardKindFromGen(gen.EntityCardKindEnum kind) =>
    switch (kind) {
      gen.EntityCardKindEnum.album => EntityCardKind.album,
      gen.EntityCardKindEnum.artist => EntityCardKind.artist,
      gen.EntityCardKindEnum.releaseGroup => EntityCardKind.releaseGroup,
      gen.EntityCardKindEnum.playlist => EntityCardKind.playlist,
      gen.EntityCardKindEnum.podcast => EntityCardKind.podcast,
      gen.EntityCardKindEnum.book => EntityCardKind.book,
      gen.EntityCardKindEnum.unknownDefaultOpenApi => null,
      _ => null,
    };

EntityCard? entityCardFromGen(gen.EntityCard card) {
  final kind = entityCardKindFromGen(card.kind);
  if (kind == null) return null;
  return EntityCard(
    pid: card.pid,
    kind: kind,
    title: card.title,
    artist: card.artist,
    year: card.year,
    itemCount: card.itemCount,
  );
}

AlbumDetail albumDetailFromGen(gen.AlbumDetail album) => AlbumDetail(
  pid: album.pid,
  title: album.title,
  sortKey: album.sortKey,
  mbid: album.mbid,
  year: album.year,
  releaseGroupPid: album.releaseGroupPid,
  barcode: album.barcode,
  label: album.label,
  catalogNumber: album.catalogNumber,
  media: album.media,
  country: album.country,
  itemCount: album.itemCount,
  totalDurationMs: album.totalDurationMs,
);

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

EntityPlayState entityPlayStateFromGen(gen.EntityPlayState state) {
  return EntityPlayState(
    pid: state.pid,
    starred: state.starred,
    starredAt: state.starredAt,
    rating: state.rating,
    updatedAt: state.updatedAt,
  );
}

StarredEntities starredEntitiesFromGen(gen.StarredEntities entities) {
  return StarredEntities(
    artists: entities.artists.map(searchHitFromGen).toList(),
    albums: entities.albums.map(searchHitFromGen).toList(),
  );
}

gen.ListenSession listenSessionToGen(ListenSession session) {
  return gen.ListenSession(
    (b) => b
      ..sessionId = session.sessionId
      ..pid = session.pid
      ..startedAt = session.startedAt.toUtc()
      ..msPlayed = session.msPlayed
      ..skippedMs = session.skippedMs
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
            reason: e.reason,
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
            durationMs: f.durationMs,
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
  final funding = show.funding;
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
    explicit: show.explicit ?? false,
    funding: funding == null
        ? null
        : PodcastFunding(url: funding.url, message: funding.message),
    medium: show.medium,
    persons: show.persons?.map(feedPersonFromGen).toList() ?? const [],
  );
}

FeedPerson feedPersonFromGen(gen.FeedPerson person) {
  return FeedPerson(
    name: person.name,
    role: person.role,
    group: person.group,
    img: person.img,
    href: person.href,
  );
}

Soundbite soundbiteFromGen(gen.Soundbite bite) {
  return Soundbite(
    startMs: bite.startMs,
    durationMs: bite.durationMs,
    title: bite.title,
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
    autoDownloadFilter: episodeFilterFromGen(settings.autoDownloadFilter),
  );
}

EpisodeFilter? episodeFilterFromGen(gen.EpisodeFilter? filter) {
  if (filter == null) return null;
  return EpisodeFilter(
    include: filter.include?.toList() ?? const [],
    exclude: filter.exclude?.toList() ?? const [],
  );
}

gen.SubscriptionSettings subscriptionSettingsToGen(
  SubscriptionSettings settings,
) {
  final filter = settings.autoDownloadFilter;
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
      ..skipOutroSeconds = settings.skipOutroSeconds
      // Carried through even though nothing in the UI sets it yet: the
      // PUT replaces the whole document, so omitting it here would wipe
      // a filter the moment anyone saved a speed or a trim toggle.
      // Each side is sent only when it has terms, matching what the
      // server puts on the wire.
      ..autoDownloadFilter = filter == null || filter.isEmpty
          ? null
          : (gen.EpisodeFilterBuilder()
              ..include = filter.include.isEmpty
                  ? null
                  : ListBuilder<String>(filter.include)
              ..exclude = filter.exclude.isEmpty
                  ? null
                  : ListBuilder<String>(filter.exclude)),
  );
}

Subscription subscriptionFromGen(gen.Subscription sub, {String baseUrl = ''}) {
  return Subscription(
    show: podcastShowFromGen(sub.show_, baseUrl: baseUrl),
    settings: subscriptionSettingsFromGen(sub.settings),
    subscribedAt: sub.subscribedAt,
    unplayedCount: sub.unplayedCount,
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
    hasEnclosure: episode.hasEnclosure ?? false,
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
    hasEnclosure: episode.hasEnclosure ?? false,
    descriptionHtml: episode.descriptionHtml,
    link: episode.link,
    chapters: episode.chapters?.map(chapterMarkFromGen).toList() ?? const [],
    persons: episode.persons?.map(feedPersonFromGen).toList() ?? const [],
    soundbites: episode.soundbites?.map(soundbiteFromGen).toList() ?? const [],
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

Bookmark bookmarkFromGen(gen.Bookmark mark) => Bookmark(
  id: mark.id,
  positionMs: mark.positionMs,
  note: mark.note,
  createdAt: mark.createdAt,
);

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

Waveform waveformFromGen(gen.Waveform waveform) {
  return Waveform(
    state: waveform.state,
    peaks: waveform.peaks?.toList() ?? const [],
    resolution: waveform.resolution,
    essenceHash: waveform.essenceHash,
  );
}

Lyrics lyricsFromGen(gen.Lyrics lyrics) {
  return Lyrics(
    pid: lyrics.pid,
    source: lyrics.source_,
    // Sorted here rather than trusted: the contract says ordered by
    // `timeMs` and the karaoke view walks the list assuming it, so an
    // out-of-order sidecar would light the wrong line rather than
    // simply reading oddly.
    synced:
        (lyrics.synced?.map(
                  (line) => SyncedLine(timeMs: line.timeMs, text: line.text),
                ) ??
                const <SyncedLine>[])
            .toList()
          ..sort((a, b) => a.timeMs.compareTo(b.timeMs)),
    unsynced: lyrics.unsynced,
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
    limitMode: rule.limitMode ?? '',
    limitSeed: rule.limitSeed ?? 0,
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
      ..limit = rule.limit > 0 ? rule.limit : null
      ..limitMode = rule.limitMode.isEmpty ? null : rule.limitMode
      ..limitSeed = rule.limitSeed != 0 ? rule.limitSeed : null,
  );
}

Playlist playlistFromGen(gen.Playlist pl, {String baseUrl = ''}) {
  final rule = pl.rule;
  // The wire carries hasArt rather than a URL: a playlist's cover lives
  // at the shared art endpoint under the playlist's own pid, so there is
  // nothing for the server to say that the pid does not already.
  final artUrl = pl.hasArt == true
      ? resolveMediaUrl(baseUrl, '/api/v1/items/${pl.pid}/art')
      : null;
  return Playlist(
    // previousPid is retired: rule edits apply in place, so the server
    // never sets it. The wrapper field stays null.
    pid: pl.pid,
    name: pl.name,
    kind: pl.kind,
    visibility: pl.visibility,
    ownerName: pl.ownerName,
    isOwner: pl.isOwner,
    itemCount: pl.itemCount,
    rule: rule == null ? null : smartRuleFromGen(rule),
    artUrl: artUrl,
    createdAt: pl.createdAt.toUtc(),
    updatedAt: pl.updatedAt.toUtc(),
  );
}

PlaylistPage playlistPageFromGen(gen.PlaylistPage page, {String baseUrl = ''}) {
  return PlaylistPage(
    playlists: page.playlists
        .map((p) => playlistFromGen(p, baseUrl: baseUrl))
        .toList(),
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

M3uImportResult m3uImportResultFromGen(
  gen.M3uImportResult res, {
  String baseUrl = '',
}) {
  return M3uImportResult(
    playlist: playlistFromGen(res.playlist, baseUrl: baseUrl),
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

RadioSavedSong radioSavedSongFromGen(gen.RadioSavedSong s) {
  return RadioSavedSong(
    pid: s.pid,
    nowPlaying: s.nowPlaying,
    artist: s.artist,
    title: s.title,
    stationPid: s.stationPid,
    stationName: s.stationName,
    heardAt: s.heardAt.toUtc(),
    inLibraryPid: s.inLibraryPid,
    hasArt: s.hasArt,
  );
}

RadioSavedSongPage radioSavedSongPageFromGen(gen.RadioSavedSongPage p) {
  return RadioSavedSongPage(
    songs: p.songs.map(radioSavedSongFromGen).toList(growable: false),
    nextCursor: p.nextCursor,
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

PodcastDirectoryEntry podcastDirectoryEntryFromGen(
  gen.PodcastDirectoryEntry e,
) {
  return PodcastDirectoryEntry(
    name: e.name,
    feedUrl: e.feedUrl,
    author: e.author,
    artworkUrl: e.artworkUrl,
    genre: e.genre,
    episodeCount: e.episodeCount,
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

NotifyEvent notifyEventFromGen(gen.NotificationEvent e) {
  return NotifyEvent(
    name: e.name,
    scope: e.scope.name,
    description: e.description,
  );
}

NotificationTarget notificationTargetFromGen(gen.NotificationTarget t) {
  return NotificationTarget(
    pid: t.pid,
    kind: t.kind.name,
    scope: t.scope.name,
    label: t.label,
    config: {for (final e in t.config.entries) e.key: e.value?.value},
    enabledEvents: t.enabledEvents.toList(),
    createdAt: t.createdAt.toUtc(),
    lastSuccessAt: t.lastSuccessAt?.toUtc(),
    lastError: t.lastError,
    lastErrorAt: t.lastErrorAt?.toUtc(),
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

// The generated names carry trailing underscores: `base` and `source`
// collide with built_value's own members, so the generator escapes them.
CastPreflightBase castPreflightBaseFromGen(gen.CastPreflightBase b) {
  return CastPreflightBase(
    base: b.base_,
    source: b.source_,
    reachable: b.reachable,
    notes: b.notes.toList(growable: false),
  );
}

CandidateSummary candidateSummaryFromGen(gen.CandidateSummary s) {
  return CandidateSummary(
    mbid: s.mbid,
    title: s.title,
    artist: s.artist,
    year: s.year,
    similarityPct: s.similarityPct,
  );
}

ReviewEntry reviewEntryFromGen(gen.ReviewEntry entry) {
  final best = entry.best;
  return ReviewEntry(
    id: entry.id,
    kind: entry.kind,
    status: entry.status,
    mediaType: mediaTypeFromGen(entry.mediaType),
    origin: entry.origin,
    title: entry.title,
    artist: entry.artist,
    trackCount: entry.trackCount,
    libraryPid: entry.libraryPid,
    uploadedBy: entry.uploadedBy,
    identifying: entry.identifying,
    best: best == null ? null : candidateSummaryFromGen(best),
    appliedMbid: entry.appliedMbid,
    createdAt: entry.createdAt.toUtc(),
    decidedAt: entry.decidedAt?.toUtc(),
    decidedBy: entry.decidedBy,
  );
}

ReviewTrack reviewTrackFromGen(gen.ReviewTrack track) {
  return ReviewTrack(
    pid: track.pid,
    path: track.path,
    title: track.title,
    artist: track.artist,
    trackNo: track.trackNo,
    discNo: track.discNo,
    durationMs: track.durationMs,
  );
}

ReviewCandidate reviewCandidateFromGen(gen.ReviewCandidate c) {
  return ReviewCandidate(
    mbid: c.mbid,
    releaseGroupMbid: c.releaseGroupMbid,
    title: c.title,
    artist: c.artist,
    year: c.year,
    mediaCount: c.mediaCount,
    trackCount: c.trackCount,
    country: c.country,
    label: c.label,
    catalogNumber: c.catalogNumber,
    compilation: c.compilation,
    similarityPct: c.similarityPct,
    components:
        c.components
            ?.map(
              (comp) => CandidateComponent(
                name: comp.name,
                distance: comp.distance,
                weight: comp.weight,
              ),
            )
            .toList() ??
        const [],
    pairings: c.pairings
        .map(
          (p) => CandidatePairing(
            trackIndex: p.trackIndex,
            position: p.position,
            disc: p.disc,
            title: p.title,
            artist: p.artist,
            durationMs: p.durationMs,
            recordingMbid: p.recordingMbid,
            distance: p.distance,
          ),
        )
        .toList(),
    missingTitles: c.missingTitles?.toList() ?? const [],
    extraTrackIndexes: c.extraTrackIndexes?.toList() ?? const [],
  );
}

ReviewEntryDetail reviewEntryDetailFromGen(gen.ReviewEntryDetail detail) {
  final best = detail.best;
  return ReviewEntryDetail(
    id: detail.id,
    kind: detail.kind,
    status: detail.status,
    mediaType: mediaTypeFromGen(detail.mediaType),
    origin: detail.origin,
    title: detail.title,
    artist: detail.artist,
    trackCount: detail.trackCount,
    libraryPid: detail.libraryPid,
    uploadedBy: detail.uploadedBy,
    identifying: detail.identifying,
    best: best == null ? null : candidateSummaryFromGen(best),
    appliedMbid: detail.appliedMbid,
    createdAt: detail.createdAt.toUtc(),
    decidedAt: detail.decidedAt?.toUtc(),
    decidedBy: detail.decidedBy,
    candidates: detail.candidates.map(reviewCandidateFromGen).toList(),
    tracks: detail.tracks.map(reviewTrackFromGen).toList(),
    identifyDeclined: detail.identifyDeclined ?? false,
    identifyOverride: reviewOverrideFromGen(detail.identifyOverride),
    suggested: reviewOverrideFromGen(detail.suggested),
  );
}

ReviewOverride? reviewOverrideFromGen(gen.ReviewIdentifyRequest? o) {
  if (o == null) return null;
  return ReviewOverride(artist: o.artist, album: o.album, title: o.title);
}

ReviewEntryPage reviewEntryPageFromGen(gen.ReviewEntryPage page) {
  return ReviewEntryPage(
    entries: page.entries.map(reviewEntryFromGen).toList(),
    nextCursor: page.nextCursor,
  );
}

ReviewStats reviewStatsFromGen(gen.ReviewStats stats) {
  return ReviewStats(
    pending: stats.pending,
    identifying: stats.identifying ?? 0,
    applied: stats.applied,
    autoApplied: stats.autoApplied,
    asIs: stats.asIs ?? 0,
    unofficial: stats.unofficial ?? 0,
    skipped: stats.skipped ?? 0,
    reverted: stats.reverted,
    revertedAutoApplied: stats.revertedAutoApplied,
  );
}

ReviewBulkOutcome reviewBulkOutcomeFromGen(gen.ReviewBulkOutcome o) {
  return ReviewBulkOutcome(entryId: o.entryId, ok: o.ok, error: o.error);
}

/// Bridges a wire action string (`approve`, `as-is`, `unofficial`,
/// `skip`, `discard`) to the generated enum, whose Dart name for
/// `as-is` is `asIs`.
gen.ReviewDecisionActionEnum reviewActionToGen(String action) =>
    gen.ReviewDecisionActionEnum.valueOf(action == 'as-is' ? 'asIs' : action);

gen.ReviewBulkDecisionActionEnum reviewBulkActionToGen(String action) =>
    gen.ReviewBulkDecisionActionEnum.valueOf(
      action == 'as-is' ? 'asIs' : action,
    );

/// Bridges the matching mode to its wire name; the generated Dart name
/// for `false` is `false_`.
LibraryInfo libraryInfoFromGen(gen.ModelLibrary l) => LibraryInfo(
  pid: l.pid,
  name: l.name,
  media: l.media,
  path: l.path,
  itemCount: l.itemCount,
);

/// The create response is the same library plus what creating it left
/// degraded, so it maps through the listing's own conversion.
LibraryInfo libraryCreatedFromGen(gen.LibraryCreated l) => LibraryInfo(
  pid: l.pid,
  name: l.name,
  media: l.media,
  path: l.path,
  itemCount: l.itemCount,
  streamingWarning: l.streamingWarning,
);

GenreNode genreNodeFromGen(gen.GenreNode n) => GenreNode(
  name: n.name,
  parent: (n.parent ?? '').isEmpty ? null : n.parent,
  aliases: n.aliases?.toList(growable: false) ?? const <String>[],
);

gen.GenreNode genreNodeToGen(GenreNode n) => gen.GenreNode(
  (b) => b
    ..name = n.name
    ..parent = n.parent
    ..aliases = n.aliases.isEmpty
        ? null
        : (ListBuilder<String>()..addAll(n.aliases)),
);

GenreTree genreTreeFromGen(gen.GenreTree t) => GenreTree(
  source: t.source_.name,
  genres: t.genres.map(genreNodeFromGen).toList(growable: false),
);

/// A mode this build predates arrives as the generator's sentinel name:
/// fine to show, never to send back, since the server rejects its wire
/// value. Writes pick from a fixed option list, so nothing does.
String libraryMatchingModeFromGen(gen.LibraryMatching m) => m.mode.name;

gen.LibraryMatching libraryMatchingModeToGen(String mode) {
  return gen.LibraryMatching(
    (b) => b..mode = gen.LibraryMatchingModeEnum.valueOf(mode),
  );
}

DuplicateWarning duplicateWarningFromGen(gen.DuplicateWarning w) {
  return DuplicateWarning(
    itemPid: w.itemPid,
    kind: w.kind,
    title: w.title,
    artist: w.artist,
  );
}

UploadSession uploadSessionFromGen(gen.Upload upload) {
  final duplicate = upload.duplicate;
  return UploadSession(
    id: upload.id,
    fileName: upload.fileName,
    sizeBytes: upload.sizeBytes,
    receivedBytes: upload.receivedBytes,
    mediaType: mediaTypeFromGen(upload.mediaType),
    libraryPid: upload.libraryPid,
    batchId: upload.batchId,
    state: upload.state,
    reviewEntryId: upload.reviewEntryId,
    duplicate: duplicate == null ? null : duplicateWarningFromGen(duplicate),
    uploadedBy: upload.uploadedBy,
    createdAt: upload.createdAt.toUtc(),
    expiresAt: upload.expiresAt?.toUtc(),
  );
}

UploadPage uploadPageFromGen(gen.UploadPage page) {
  final quota = page.quota;
  return UploadPage(
    uploads: page.uploads.map(uploadSessionFromGen).toList(),
    nextCursor: page.nextCursor,
    quota: quota == null ? null : uploadQuotaFromGen(quota),
  );
}

UploadQuota uploadQuotaFromGen(gen.UploadQuota quota) {
  return UploadQuota(
    bytesInUse: quota.bytesInUse,
    quotaBytes: quota.quotaBytes,
  );
}

UploadGrouping uploadGroupingFromGen(gen.UploadGrouping grouping) {
  return UploadGrouping.values.firstWhere(
    (g) => g.wireName == grouping.name,
    orElse: () => UploadGrouping.auto,
  );
}

gen.UploadGrouping uploadGroupingToGen(UploadGrouping grouping) {
  return switch (grouping) {
    UploadGrouping.auto => gen.UploadGrouping.auto,
    UploadGrouping.album => gen.UploadGrouping.album,
    UploadGrouping.tracks => gen.UploadGrouping.tracks,
  };
}

UploadBatch uploadBatchFromGen(gen.UploadBatch batch) {
  return UploadBatch(
    id: batch.id,
    grouping: uploadGroupingFromGen(batch.grouping),
    mediaType: mediaTypeFromGen(batch.mediaType),
    libraryPid: batch.libraryPid,
    state: batch.state,
    reviewEntryIds: batch.reviewEntryIds.toList(),
    createdAt: batch.createdAt.toUtc(),
    expiresAt: batch.expiresAt.toUtc(),
  );
}

EditableField editableFieldFromGen(gen.EditableField f) =>
    EditableField(name: f.name, writeBack: f.writeBack);

MetadataFields metadataFieldsFromGen(gen.MetadataFields fields) {
  return MetadataFields(
    kinds: fields.kinds
        .map(
          (k) => KindFields(
            kind: mediaTypeFromGen(k.kind),
            fields: k.fields.map(editableFieldFromGen).toList(),
            creditRoles: k.creditRoles.map(editableFieldFromGen).toList(),
          ),
        )
        .toList(),
    entityTypes: fields.entityTypes
        .map(
          (t) => EntityTypeFields(
            entityType: t.entityType,
            fields: t.fields.map(editableFieldFromGen).toList(),
          ),
        )
        .toList(),
  );
}

Credit creditFromGen(gen.Credit c) =>
    Credit(role: c.role, names: c.names.toList());

ItemMetadata itemMetadataFromGen(gen.ItemMetadata meta) {
  final lyrics = meta.lyrics;
  return ItemMetadata(
    pid: meta.pid,
    mediaType: mediaTypeFromGen(meta.mediaType),
    fields: meta.fields.toMap(),
    lockedFields: meta.lockedFields.toList(),
    provenance: meta.provenance
        .map(
          (p) => FieldProvenance(
            field: p.field,
            source: p.source_,
            provider: p.provider,
            locked: p.locked,
            updatedAt: p.updatedAt?.toUtc(),
          ),
        )
        .toList(),
    credits: meta.credits.map(creditFromGen).toList(),
    lyrics: lyrics == null
        ? null
        : LyricsState(
            synced: lyrics.synced,
            source: lyrics.source_,
            lrc: lyrics.lrc,
          ),
    chapters: meta.chapters?.map(chapterMarkFromGen).toList() ?? const [],
    customTags: meta.customTags
        .map((t) => CustomTag(key: t.key, values: t.values.toList()))
        .toList(),
    unofficial: meta.unofficial,
    virtualTrack: meta.virtualTrack,
    hasArtwork: meta.hasArtwork,
    hasOwnArtwork: meta.hasOwnArtwork,
    albumPid: meta.albumPid,
    artistPid: meta.artistPid,
    releaseGroupPid: meta.releaseGroupPid,
    writeBackIssues: meta.writeBackIssues
        .map(
          (i) => WriteBackIssue(
            filePid: i.filePid,
            code: i.code,
            tagKey: i.tagKey,
            detail: i.detail,
          ),
        )
        .toList(),
    mayCurate: meta.mayCurate,
  );
}

WriteBackFailure writeBackFailureFromGen(gen.WriteBackFailure f) =>
    WriteBackFailure(filePid: f.filePid, path: f.path, reason: f.reason);

MetadataEditResult metadataEditResultFromGen(gen.MetadataEditResult result) {
  return MetadataEditResult(
    applied: result.applied,
    writeBackFailures:
        result.writeBackFailures?.map(writeBackFailureFromGen).toList() ??
        const [],
    warnings: result.warnings?.toList() ?? const [],
  );
}

BulkEditResult bulkEditResultFromGen(gen.BulkEditResult result) {
  return BulkEditResult(
    edited: result.edited.toList(),
    skipped: result.skipped.toList(),
    writeBackFailures:
        result.writeBackFailures?.map(writeBackFailureFromGen).toList() ??
        const [],
  );
}

TagEditResult tagEditResultFromGen(gen.TagEditResult result) =>
    TagEditResult(key: result.key, stored: result.stored);

EntityCuratedField entityCuratedFieldFromGen(gen.EntityCuratedField f) {
  return EntityCuratedField(
    field: f.field,
    value: f.value,
    source: f.source_,
    locked: f.locked,
    updatedAt: f.updatedAt?.toUtc(),
  );
}

gen.ChapterMark chapterEditToGen(ChapterEdit chapter) {
  return gen.ChapterMark(
    (b) => b
      ..index = chapter.index
      ..title = chapter.title
      ..startMs = chapter.startMs
      ..endMs = chapter.endMs,
  );
}

EnrichItemResult enrichItemResultFromGen(gen.EnrichItemResult result) {
  return EnrichItemResult(
    applied: result.applied.toList(),
    skipped: result.skipped.toList(),
  );
}

HealthSummary healthSummaryFromGen(gen.HealthSummary summary) {
  return HealthSummary(
    score: summary.score,
    totalItems: summary.totalItems,
    evaluatedItems: summary.evaluatedItems,
    warmingUp: summary.warmingUp,
    sweptAt: summary.sweptAt?.toUtc(),
    rules: summary.rules
        .map(
          (r) => HealthRuleCount(
            rule: r.rule,
            label: r.label,
            failing: r.failing,
            fixable: r.fixable,
          ),
        )
        .toList(),
  );
}

HealthIssue healthIssueFromGen(gen.HealthIssue issue) {
  return HealthIssue(
    pid: issue.pid,
    title: issue.title,
    artist: issue.artist,
    mediaType: mediaTypeFromGen(issue.mediaType),
    rules: issue.rules.toList(),
  );
}

HealthIssuePage healthIssuePageFromGen(gen.HealthIssuePage page) {
  return HealthIssuePage(
    items: page.items.map(healthIssueFromGen).toList(),
    nextCursor: page.nextCursor,
  );
}

FileDiagnostic fileDiagnosticFromGen(gen.FileDiagnostic d) => FileDiagnostic(
  path: d.path,
  origin: d.origin,
  code: d.code,
  severity: d.severity,
  seenAt: d.seenAt,
  tagKey: d.tagKey,
  detail: d.detail,
);

FileDiagnosticPage fileDiagnosticPageFromGen(gen.FileDiagnosticPage page) =>
    FileDiagnosticPage(
      diagnostics: page.diagnostics.map(fileDiagnosticFromGen).toList(),
      nextCursor: page.nextCursor,
    );

DiagnosticCount diagnosticCountFromGen(gen.DiagnosticCount c) =>
    DiagnosticCount(
      origin: c.origin,
      code: c.code,
      severity: c.severity,
      count: c.count,
    );

ArtRoleInfo artRoleInfoFromGen(gen.ArtRoleInfo r) => ArtRoleInfo(
  role: r.role.name,
  format: r.format,
  width: r.width,
  height: r.height,
);

DuplicateEntity duplicateEntityFromGen(gen.DuplicateEntity e) =>
    DuplicateEntity(pid: e.pid, name: e.name, itemCount: e.itemCount);

DuplicateGroup duplicateGroupFromGen(gen.DuplicateGroup group) {
  return DuplicateGroup(
    entityType: group.entityType,
    survivor: duplicateEntityFromGen(group.survivor),
    losers: group.losers.map(duplicateEntityFromGen).toList(),
    detail: group.detail,
  );
}

/// Bridges a wire entity type (`album`, `artist`, `release-group`,
/// `genre`) to the generated enum, whose Dart name for
/// `release-group` is `releaseGroup`.
gen.MergeRequestEntityTypeEnum mergeEntityTypeToGen(String entityType) =>
    gen.MergeRequestEntityTypeEnum.valueOf(
      entityType == 'release-group' ? 'releaseGroup' : entityType,
    );

UpgradeMember upgradeMemberFromGen(gen.UpgradeMember m) {
  return UpgradeMember(
    itemPid: m.itemPid,
    title: m.title,
    artist: m.artist,
    codec: m.codec,
    bitrate: m.bitrate,
    sampleRate: m.sampleRate,
    bitDepth: m.bitDepth,
    lossless: m.lossless,
    best: m.best,
  );
}

UpgradeGroup upgradeGroupFromGen(gen.UpgradeGroup group) =>
    UpgradeGroup(members: group.members.map(upgradeMemberFromGen).toList());

OrganizeProfile organizeProfileFromGen(gen.OrganizeProfile profile) {
  return OrganizeProfile(
    name: profile.name,
    musicTemplate: profile.musicTemplate,
    audiobookTemplate: profile.audiobookTemplate,
    podcastTemplate: profile.podcastTemplate,
    tagWrite: profile.tagWrite ?? false,
  );
}

OrganizePlan organizePlanFromGen(gen.OrganizePlan plan) {
  return OrganizePlan(
    profile: plan.profile,
    totalActions: plan.totalActions,
    actions: plan.actions
        .map((a) => OrganizeAction(itemPid: a.itemPid, from: a.from, to: a.to))
        .toList(),
    tagWrite: plan.tagWrite ?? false,
  );
}

OrganizeReport organizeReportFromGen(gen.OrganizeReport report) {
  return OrganizeReport(
    moved: report.moved,
    skipped: report.skipped,
    failed: report.failed,
    failures:
        report.failures
            ?.map((f) => OrganizeFailure(path: f.path, reason: f.reason))
            .toList() ??
        const [],
  );
}

ToolTask toolTaskFromGen(gen.ToolTask task) {
  return ToolTask(
    id: task.id,
    type: task.type,
    state: task.state,
    itemPid: task.itemPid,
    progressPct: task.progressPct,
    error: task.error,
    resultPids: task.resultPids?.toList() ?? const [],
    createdAt: task.createdAt.toUtc(),
    finishedAt: task.finishedAt?.toUtc(),
    summary: task.summary?.toMap().map<String, Object?>(
      (key, value) => MapEntry(key, value?.value),
    ),
  );
}

ToolTaskPage toolTaskPageFromGen(gen.ToolTaskPage page) {
  return ToolTaskPage(
    tasks: page.tasks.map(toolTaskFromGen).toList(),
    nextCursor: page.nextCursor,
  );
}

CoverageCount coverageCountFromGen(gen.CoverageCount c) =>
    CoverageCount(enriched: c.enriched, total: c.total);

EnrichmentStatus enrichmentStatusFromGen(gen.EnrichmentStatus status) {
  return EnrichmentStatus(
    providers: status.providers
        .map(
          (p) => EnrichmentProvider(
            name: p.name,
            capabilities: p.capabilities.toList(),
            configured: p.configured,
            builtin: p.builtin,
          ),
        )
        .toList(),
    coverage: EnrichmentCoverage(
      artists: coverageCountFromGen(status.coverage.artists),
      releaseGroups: coverageCountFromGen(status.coverage.releaseGroups),
      books: coverageCountFromGen(status.coverage.books),
      lyrics: coverageCountFromGen(status.coverage.lyrics),
    ),
    running: status.running,
  );
}

/// A mode this build predates lands in [LibraryAccess.mode] as the
/// generator's sentinel name: fine to show, never to send back. The
/// screens that write access build the mode from literals, so nothing does.
LibraryAccess libraryAccessFromGen(gen.LibraryAccess access) {
  return LibraryAccess(
    mode: access.mode.name,
    libraryPids: access.libraryPids?.toList() ?? const [],
  );
}

gen.LibraryAccess libraryAccessToGen(LibraryAccess access) {
  return gen.LibraryAccess(
    (b) => b
      ..mode = gen.LibraryAccessModeEnum.valueOf(access.mode)
      ..libraryPids = access.libraryPids.isEmpty
          ? null
          : ListBuilder<String>(access.libraryPids),
  );
}

UserAccount userAccountFromGen(gen.UserAccount account) {
  return UserAccount(
    id: account.id,
    username: account.username,
    displayName: account.displayName,
    roles: account.roles.toList(),
    createdAt: account.createdAt.toUtc(),
    identities:
        account.identities
            ?.map((i) => LinkedIdentity(provider: i.provider, email: i.email))
            .toList() ??
        const [],
    libraryAccess: libraryAccessFromGen(account.libraryAccess),
    uploadEnabled: account.uploadEnabled,
    uploadQuotaBytes: account.uploadQuotaBytes,
    disabled: account.disabled,
    hasPassword: account.hasPassword ?? true,
    pending: account.pending,
    permissions: permissionsFromGen(account.permissions),
  );
}

UserPage userPageFromGen(gen.UserPage page) {
  return UserPage(
    users: page.users.map(userAccountFromGen).toList(),
    nextCursor: page.nextCursor,
  );
}

ListBuilder<gen.Role>? rolesToGen(List<String>? roles) =>
    roles == null ? null : ListBuilder<gen.Role>(roles.map(gen.Role.valueOf));

PlaybackSessionHistoryEntry playbackHistoryFromGen(
  gen.PlaybackSessionHistoryEntry s,
) {
  return PlaybackSessionHistoryEntry(
    id: s.id,
    endpointId: s.endpointId,
    endpointName: s.endpointName,
    authority: s.authority,
    index: s.index,
    positionMs: s.positionMs,
    positionAt: s.positionAt.toUtc(),
    rate: s.rate,
    repeat: s.repeat,
    shuffle: s.shuffle ?? false,
    entries: s.entries
        .map(
          (e) => PlaybackSessionEntry(
            pid: e.pid,
            title: e.title,
            artist: e.artist,
            durationMs: e.durationMs,
          ),
        )
        .toList(growable: false),
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

TagRule tagRuleFromGen(gen.TagRule rule) =>
    TagRule(key: rule.key, value: rule.value);

gen.TagRule tagRuleToGen(TagRule rule) => gen.TagRule(
  (b) => b
    ..key = rule.key
    ..value = rule.value,
);

Permissions permissionsFromGen(gen.Permissions p) {
  return Permissions(
    download: p.download,
    delete: p.delete,
    explicitContent: p.explicitContent,
    sharedOutputs: p.sharedOutputs,
    managePodcasts: p.managePodcasts,
    maxTranscodeKbps: p.maxTranscodeKbps,
    tagAllow: p.tagAllow?.map(tagRuleFromGen).toList() ?? const [],
    tagDeny: p.tagDeny?.map(tagRuleFromGen).toList() ?? const [],
  );
}

gen.Permissions permissionsToGen(Permissions p) {
  return gen.Permissions(
    (b) => b
      ..download = p.download
      ..delete = p.delete
      ..explicitContent = p.explicitContent
      ..sharedOutputs = p.sharedOutputs
      ..managePodcasts = p.managePodcasts
      ..maxTranscodeKbps = p.maxTranscodeKbps
      ..tagAllow = p.tagAllow.isEmpty
          ? null
          : ListBuilder<gen.TagRule>(p.tagAllow.map(tagRuleToGen))
      ..tagDeny = p.tagDeny.isEmpty
          ? null
          : ListBuilder<gen.TagRule>(p.tagDeny.map(tagRuleToGen)),
  );
}

Invite inviteFromGen(gen.Invite invite) {
  return Invite(
    id: invite.id,
    note: invite.note,
    roles: invite.roles.map((r) => r.name).toList(),
    libraryAccess: invite.libraryAccess == null
        ? null
        : libraryAccessFromGen(invite.libraryAccess!),
    permissions: invite.permissions == null
        ? null
        : permissionsFromGen(invite.permissions!),
    uploadEnabled: invite.uploadEnabled,
    maxUses: invite.maxUses,
    usedCount: invite.usedCount,
    revoked: invite.revoked,
    expiresAt: invite.expiresAt?.toUtc(),
    createdAt: invite.createdAt.toUtc(),
    createdBy: invite.createdBy,
  );
}

InviteCreated inviteCreatedFromGen(gen.InviteCreated created) {
  final invite = inviteFromGen(created);
  return InviteCreated(
    id: invite.id,
    note: invite.note,
    roles: invite.roles,
    libraryAccess: invite.libraryAccess,
    permissions: invite.permissions,
    uploadEnabled: invite.uploadEnabled,
    maxUses: invite.maxUses,
    usedCount: invite.usedCount,
    revoked: invite.revoked,
    expiresAt: invite.expiresAt,
    createdAt: invite.createdAt,
    createdBy: invite.createdBy,
    token: created.token,
  );
}

AdminSettings adminSettingsFromGen(gen.AdminSettings settings) {
  return AdminSettings(
    signupEnabled: settings.signupEnabled,
    readOnly: settings.readOnly,
    // Optional on the wire only so PUT writers can omit it (absent
    // keeps the current value); responses always carry it.
    sonicAnalysis: settings.sonicAnalysis ?? true,
    backupKeepCount: settings.backupKeepCount,
    backupKeepBytes: settings.backupKeepBytes,
    trashRetentionDays: settings.trashRetentionDays ?? 0,
    // Absent is a server predating the field, whose prune ran on 30 days.
    taskRetentionDays: settings.taskRetentionDays ?? 30,
    // Absent is a server predating the field, which made no outbound
    // lookups at all - so off is what it was doing.
    radioExternalArt: settings.radioExternalArt ?? false,
  );
}

gen.AdminSettings adminSettingsToGen(AdminSettings settings) {
  return gen.AdminSettings(
    (b) => b
      ..signupEnabled = settings.signupEnabled
      ..readOnly = settings.readOnly
      ..sonicAnalysis = settings.sonicAnalysis
      ..backupKeepCount = settings.backupKeepCount
      ..backupKeepBytes = settings.backupKeepBytes
      ..trashRetentionDays = settings.trashRetentionDays
      ..taskRetentionDays = settings.taskRetentionDays
      ..radioExternalArt = settings.radioExternalArt,
  );
}

TranscodingLimits transcodingLimitsFromGen(gen.TranscodingLimits limits) {
  return TranscodingLimits(
    maxConcurrent: limits.maxConcurrent,
    maxConcurrentPerUser: limits.maxConcurrentPerUser,
    defaultMaxBitrateKbps: limits.defaultMaxBitrateKbps,
  );
}

TranscodingActivity transcodingActivityFromGen(gen.TranscodingActivity a) {
  return TranscodingActivity(activeSessions: a.activeSessions);
}

gen.TranscodingLimits transcodingLimitsToGen(TranscodingLimits limits) {
  return gen.TranscodingLimits(
    (b) => b
      ..maxConcurrent = limits.maxConcurrent
      ..maxConcurrentPerUser = limits.maxConcurrentPerUser
      ..defaultMaxBitrateKbps = limits.defaultMaxBitrateKbps,
  );
}

ScrobblingAdminConfig scrobblingAdminConfigFromGen(
  gen.ScrobblingAdminConfig config,
) {
  return ScrobblingAdminConfig(
    lastfmConfigured: config.lastfmConfigured,
    lastfmSource: config.lastfmSource,
    lastfmApiKey: config.lastfmApiKey,
    lastfmSecretSet: config.lastfmSecretSet,
  );
}

Schedule scheduleFromGen(gen.Schedule schedule) {
  return Schedule(
    kind: schedule.kind.name,
    cron: schedule.cron,
    enabled: schedule.enabled,
    lastRunAt: schedule.lastRunAt?.toUtc(),
    lastStatus: schedule.lastStatus,
    lastError: schedule.lastError,
    nextRunAt: schedule.nextRunAt?.toUtc(),
  );
}

Backup backupFromGen(gen.Backup backup) {
  return Backup(
    id: backup.id,
    state: backup.state,
    trigger: backup.trigger,
    fileName: backup.fileName,
    sizeBytes: backup.sizeBytes,
    error: backup.error,
    createdAt: backup.createdAt.toUtc(),
    finishedAt: backup.finishedAt?.toUtc(),
  );
}

RestorePlan restorePlanFromGen(gen.RestorePlan plan) {
  return RestorePlan(
    backupId: plan.backupId,
    stagedAt: plan.stagedAt.toUtc(),
    keyfilePresent: plan.keyfilePresent,
    keyfileMatches: plan.keyfileMatches,
    sealedCasualties: plan.sealedCasualties
        .map((c) => SealedCasualty(kind: c.kind, name: c.name))
        .toList(),
    warnings: plan.warnings.toList(),
  );
}

Job jobFromGen(gen.Job job) {
  return Job(
    pid: job.pid,
    kind: job.kind,
    state: job.state,
    progress: job.progress,
    message: job.message,
    error: job.error,
  );
}

AuditEvent auditEventFromGen(gen.AuditEvent event) {
  return AuditEvent(
    id: event.id,
    actorId: event.actorId,
    actorName: event.actorName,
    action: event.action,
    targetKind: event.targetKind,
    targetPid: event.targetPid,
    targetName: event.targetName,
    detail:
        event.detail?.toMap().map<String, Object?>(
          (key, value) => MapEntry(key, value?.value),
        ) ??
        const {},
    createdAt: event.createdAt.toUtc(),
  );
}

AuditEventPage auditEventPageFromGen(gen.AuditEventPage page) {
  return AuditEventPage(
    events: page.events.map(auditEventFromGen).toList(),
    nextCursor: page.nextCursor,
  );
}

TrashEntry trashEntryFromGen(gen.TrashEntry entry) {
  return TrashEntry(
    id: entry.id,
    itemPid: entry.itemPid,
    name: entry.name,
    reason: entry.reason,
    sizeBytes: entry.sizeBytes,
    trashedAt: entry.trashedAt.toUtc(),
    restoredAt: entry.restoredAt?.toUtc(),
  );
}

DeleteItemsResult deleteItemsResultFromGen(gen.DeleteItemsResult result) {
  return DeleteItemsResult(
    applied: result.applied,
    mode: result.mode,
    entries: result.entries
        .map(
          (e) => DeletePlanEntry(
            pid: e.pid,
            name: e.name,
            files: e.files,
            bytes: e.bytes,
          ),
        )
        .toList(),
  );
}

gen.MigrationOptions migrationOptionsToGen(MigrationOptions options) {
  return gen.MigrationOptions(
    (b) => b
      ..stars = options.stars
      ..ratings = options.ratings
      ..history = options.history
      ..progress = options.progress,
  );
}

MixBasis mixBasisFromGen(gen.MixBasis basis) {
  return MixBasis.values.firstWhere(
    (b) => b.wireName == basis.name,
    orElse: () => MixBasis.metadata,
  );
}

SimilarTracks similarTracksFromGen(
  gen.SimilarTracks tracks, {
  String baseUrl = '',
}) {
  return SimilarTracks(
    basis: mixBasisFromGen(tracks.basis),
    items: tracks.items
        .map((i) => itemSummaryFromGen(i, baseUrl: baseUrl))
        .toList(growable: false),
  );
}

gen.InstantMixRequest instantMixRequestToGen({
  String? seedPid,
  String? genre,
  double? adventurousness,
  int? size,
  List<String> excludePids = const [],
}) {
  return gen.InstantMixRequest(
    (b) => b
      ..seedPid = seedPid
      ..genre = genre
      ..adventurousness = adventurousness
      ..size = size
      ..excludePids = excludePids.isEmpty
          ? null
          : ListBuilder<String>(excludePids),
  );
}

InstantMix instantMixFromGen(gen.InstantMix mix, {String baseUrl = ''}) {
  return InstantMix(
    basis: mixBasisFromGen(mix.basis),
    items: mix.items
        .map((i) => itemSummaryFromGen(i, baseUrl: baseUrl))
        .toList(growable: false),
  );
}

SonicPath sonicPathFromGen(gen.SonicPath path, {String baseUrl = ''}) {
  return SonicPath(
    complete: path.complete,
    items: path.items
        .map((i) => itemSummaryFromGen(i, baseUrl: baseUrl))
        .toList(growable: false),
  );
}

/// Bridges a generated range or bucket enum's Dart name back to its wire
/// form: the generator prefixes names that start with a digit with `n`
/// (`7d` becomes `n7d`).
String _rangeWireName(String name) => switch (name) {
  'n7d' => '7d',
  'n30d' => '30d',
  'n90d' => '90d',
  'n365d' => '365d',
  _ => name,
};

ListeningBucket listeningBucketFromGen(gen.ListeningBucket bucket) {
  return ListeningBucket(
    start: bucket.start.toDateTime(utc: true),
    ms: bucket.ms,
    sessions: bucket.sessions,
  );
}

MediaTypeListening mediaTypeListeningFromGen(gen.MediaTypeListening m) {
  return MediaTypeListening(
    mediaType: mediaTypeFromGen(m.mediaType),
    ms: m.ms,
    sessions: m.sessions,
  );
}

ListeningStats listeningStatsFromGen(gen.ListeningStats stats) {
  return ListeningStats(
    range: _rangeWireName(stats.range.name),
    bucket: stats.bucket.name,
    timezone: stats.timezone,
    totalMs: stats.totalMs,
    sessions: stats.sessions,
    timeSavedMs: stats.timeSavedMs,
    buckets: stats.buckets.map(listeningBucketFromGen).toList(growable: false),
    byMediaType: stats.byMediaType
        .map(mediaTypeListeningFromGen)
        .toList(growable: false),
  );
}

ListeningHeatmap listeningHeatmapFromGen(gen.ListeningHeatmap heatmap) {
  return ListeningHeatmap(
    year: heatmap.year,
    timezone: heatmap.timezone,
    days: heatmap.days
        .map(
          (d) => HeatmapDay(
            date: d.date.toDateTime(utc: true),
            ms: d.ms,
            sessions: d.sessions,
          ),
        )
        .toList(growable: false),
    currentStreakDays: heatmap.currentStreakDays,
    longestStreakDays: heatmap.longestStreakDays,
  );
}

TopEntry topEntryFromGen(gen.TopEntry entry, {String baseUrl = ''}) {
  final artUrl = entry.artUrl;
  return TopEntry(
    name: entry.name,
    pid: entry.pid,
    artUrl: artUrl == null ? null : resolveMediaUrl(baseUrl, artUrl),
    plays: entry.plays,
    ms: entry.ms,
  );
}

TopList topListFromGen(gen.TopList list, {String baseUrl = ''}) {
  return TopList(
    kind: list.kind.name,
    range: _rangeWireName(list.range.name),
    entries: list.entries
        .map((e) => topEntryFromGen(e, baseUrl: baseUrl))
        .toList(growable: false),
  );
}

ListenLogEntry listenLogEntryFromGen(gen.ListenLogEntry entry) {
  return ListenLogEntry(
    pid: entry.pid,
    title: entry.title,
    artist: entry.artist,
    mediaType: mediaTypeFromGen(entry.mediaType),
    startedAt: entry.startedAt.toUtc(),
    msPlayed: entry.msPlayed,
    skippedMs: entry.skippedMs,
    finished: entry.finished,
    client: entry.client,
    // The generated Dart name for the wire value `import` is `import_`
    // (a keyword escape); bridge back to the wire form.
    source: entry.source_ == gen.ListenLogEntrySource_Enum.import_
        ? 'import'
        : entry.source_.name,
  );
}

ListenLogPage listenLogPageFromGen(gen.ListenLogPage page) {
  return ListenLogPage(
    sessions: page.sessions.map(listenLogEntryFromGen).toList(growable: false),
    nextCursor: page.nextCursor,
  );
}

YearInReview yearInReviewFromGen(
  gen.YearInReview review, {
  String baseUrl = '',
}) {
  List<TopEntry> top(Iterable<gen.TopEntry> entries) => entries
      .map((e) => topEntryFromGen(e, baseUrl: baseUrl))
      .toList(growable: false);
  return YearInReview(
    year: review.year,
    timezone: review.timezone,
    totalMs: review.totalMs,
    sessions: review.sessions,
    distinctItems: review.distinctItems,
    newInLibrary: review.newInLibrary,
    timeSavedMs: review.timeSavedMs,
    longestStreakDays: review.longestStreakDays,
    byMonth: review.byMonth
        .map(
          (m) => MonthListening(month: m.month, ms: m.ms, sessions: m.sessions),
        )
        .toList(growable: false),
    byMediaType: review.byMediaType
        .map(mediaTypeListeningFromGen)
        .toList(growable: false),
    topArtists: top(review.topArtists),
    topTracks: top(review.topTracks),
    topGenres: top(review.topGenres),
    topShows: top(review.topShows),
  );
}

ServerYearInReview serverYearInReviewFromGen(
  gen.ServerYearInReview review, {
  String baseUrl = '',
}) {
  List<TopEntry> top(Iterable<gen.TopEntry> entries) => entries
      .map((e) => topEntryFromGen(e, baseUrl: baseUrl))
      .toList(growable: false);
  return ServerYearInReview(
    year: review.year,
    participants: review.participants,
    totalMs: review.totalMs,
    sessions: review.sessions,
    topArtists: top(review.topArtists),
    topTracks: top(review.topTracks),
    topGenres: top(review.topGenres),
  );
}

Share shareFromGen(gen.Share share, {String baseUrl = ''}) {
  return Share(
    pid: share.pid,
    url: resolveMediaUrl(baseUrl, share.url),
    targetPid: share.targetPid,
    targetKind: share.targetKind,
    targetTitle: share.targetTitle,
    allowDownload: share.allowDownload,
    positionMs: share.positionMs,
    createdAt: share.createdAt.toUtc(),
    expiresAt: share.expiresAt?.toUtc(),
    plays: share.plays,
    owner: share.owner,
  );
}

SharePage sharePageFromGen(gen.SharePage page, {String baseUrl = ''}) {
  return SharePage(
    shares: page.shares
        .map((s) => shareFromGen(s, baseUrl: baseUrl))
        .toList(growable: false),
    nextCursor: page.nextCursor,
  );
}

PlaylistImportResult playlistImportResultFromGen(gen.PlaylistImportResult res) {
  return PlaylistImportResult(
    playlistPid: res.playlistPid,
    name: res.name,
    requested: res.requested,
    resolved: res.resolved,
    missing: res.missing
        .map(
          (m) => PlaylistImportMiss(
            artist: m.artist,
            title: m.title,
            album: m.album,
            durationMs: m.durationMs,
          ),
        )
        .toList(growable: false),
    rungs: ResolveRungCounts(
      essence: res.rungs.essence,
      strongId: res.rungs.strongId,
      fingerprint: res.rungs.fingerprint,
      descriptive: res.rungs.descriptive,
    ),
  );
}

PortableRef portableRefFromGen(gen.PortableRef ref) {
  return PortableRef(
    kind: ref.kind.name,
    essence: ref.essence,
    fingerprint: ref.fingerprint,
    fingerprintAlgo: ref.fingerprintAlgo,
    mbid: ref.mbid,
    asin: ref.asin,
    isbn: ref.isbn,
    isrc: ref.isrc,
    artist: ref.artist,
    title: ref.title,
    album: ref.album,
    durationMs: ref.durationMs,
  );
}

gen.PortableRef portableRefToGen(PortableRef ref) {
  return gen.PortableRef(
    (b) => b
      ..kind = gen.PortableRefKindEnum.valueOf(ref.kind)
      ..essence = ref.essence
      ..fingerprint = ref.fingerprint
      ..fingerprintAlgo = ref.fingerprintAlgo
      ..mbid = ref.mbid
      ..asin = ref.asin
      ..isbn = ref.isbn
      ..isrc = ref.isrc
      ..artist = ref.artist
      ..title = ref.title
      ..album = ref.album
      ..durationMs = ref.durationMs,
  );
}

PortablePlaylist portablePlaylistFromGen(gen.PortablePlaylist playlist) {
  return PortablePlaylist(
    name: playlist.name,
    refs: playlist.refs.map(portableRefFromGen).toList(growable: false),
  );
}

SimilarityStatus similarityStatusFromGen(gen.SimilarityStatus status) {
  return SimilarityStatus(
    enabled: status.enabled,
    model: status.model,
    dims: status.dims,
    embeddedTracks: status.embeddedTracks,
    totalTracks: status.totalTracks,
    coveragePct: status.coveragePct.toDouble(),
    queueDepth: status.queueDepth,
    lastIngestAt: status.lastIngestAt?.toUtc(),
  );
}
