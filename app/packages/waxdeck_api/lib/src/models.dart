/// Plain-Dart views over the generated built_value DTOs.
///
/// These are the types feature code sees. They are deliberately boring:
/// no built_value, no generator idioms, easy to construct in tests.
library;

/// Server liveness/version snapshot (`GET /health`).
class ServerHealth {
  const ServerHealth({
    required this.status,
    required this.version,
    required this.apiVersion,
  });

  final String status;
  final String version;
  final int apiVersion;

  bool get ok => status == 'ok';
}

/// Structured API error (the spec's `Error` schema), thrown by the client.
class WaxDeckApiException implements Exception {
  const WaxDeckApiException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  /// Stable machine-readable code (`unauthenticated`, `not-found`, and so on).
  final String code;

  /// Human-readable explanation; not stable, never parse it.
  final String message;

  final int? statusCode;

  @override
  String toString() => 'WaxDeckApiException($code, $statusCode): $message';
}

/// The three first-class media types.
enum MediaType {
  music('music'),
  podcast('podcast'),
  audiobook('audiobook');

  const MediaType(this.wireName);

  /// Value as it appears on the wire.
  final String wireName;
}

/// Discovery lists servable by the browse endpoint. Play-derived lists
/// reflect the calling user's own listening state.
enum DiscoveryList {
  newest('newest'),
  recentlyAdded('recently-added'),
  mostPlayed('most-played'),
  recentlyPlayed('recently-played'),
  random('random'),
  starred('starred'),
  alphabetical('alphabetical');

  const DiscoveryList(this.wireName);

  /// Value as it appears on the wire.
  final String wireName;
}

/// A WaxDeck account as visible to its owner.
class WaxDeckUser {
  const WaxDeckUser({
    required this.id,
    required this.username,
    this.displayName,
    this.roles = const [],
  });

  final String id;
  final String username;
  final String? displayName;
  final List<String> roles;

  /// Name to show in UI chrome.
  String get label => displayName ?? username;
}

/// Established session plus the bearer token for native clients.
class LoginResult {
  const LoginResult({required this.user, required this.token});

  final WaxDeckUser user;

  /// Opaque bearer token equivalent to the session cookie. Web builds can
  /// ignore it and rely on the HttpOnly cookie instead.
  final String token;
}

/// Whether the caller is authenticated, and as whom.
class SessionState {
  const SessionState({required this.authenticated, this.user});

  final bool authenticated;
  final WaxDeckUser? user;
}

/// Whether the server is waiting for its first administrator account.
class BootstrapStatus {
  const BootstrapStatus({required this.required});

  /// True while the server has no accounts; clients route to the setup
  /// screen instead of the login screen while this holds.
  final bool required;
}

/// How a session authenticates: web sessions with the cookie, device
/// sessions with a bearer token.
enum SessionKind {
  web('web'),
  device('device');

  const SessionKind(this.wireName);

  /// Value as it appears on the wire.
  final String wireName;
}

/// One live session belonging to the calling user, as shown in the
/// device list.
class DeviceSession {
  const DeviceSession({
    required this.id,
    required this.kind,
    required this.createdAt,
    required this.current,
    this.deviceName,
    this.client,
    this.lastSeenAt,
  });

  /// Session PID.
  final String id;

  final SessionKind kind;

  /// Client-supplied label, when the login provided one.
  final String? deviceName;

  /// Client software hint derived from the login's user agent.
  final String? client;

  final DateTime createdAt;

  /// When the session last made a request; coarse, minutes.
  final DateTime? lastSeenAt;

  /// True for the session serving the listing request.
  final bool current;

  /// Name to show in UI chrome.
  String get label => deviceName ?? client ?? kind.wireName;
}

/// One configured single-sign-on provider, for rendering login buttons.
class OidcProvider {
  const OidcProvider({
    required this.id,
    required this.displayName,
    required this.startUrl,
  });

  /// Stable provider id, passed back to the start endpoint.
  final String id;

  /// Human-readable name for the login button.
  final String displayName;

  /// URL that starts this provider's login flow, already resolved against
  /// the client base URL. With an empty base (web builds) it stays
  /// origin-relative. Web mode as-is; other modes append their query
  /// parameters.
  final String startUrl;
}

/// Preferred app theme, synced across clients.
enum ThemePref {
  system('system'),
  dark('dark'),
  light('light'),
  oled('oled');

  const ThemePref(this.wireName);

  /// Value as it appears on the wire.
  final String wireName;
}

/// Per-user preferences that sync across clients. Unset fields are absent
/// and clients apply their own defaults. The PUT endpoint replaces the
/// whole document, so senders start from the stored value.
class Prefs {
  const Prefs({this.timezone, this.locale, this.theme});

  /// IANA timezone name, for example Europe/Amsterdam.
  final String? timezone;

  /// Preferred BCP 47 locale tag, for example en-US.
  final String? locale;

  final ThemePref? theme;

  /// Copy with individual fields replaced. Passing null keeps the current
  /// value; clearing a stored field is not something the UI needs yet.
  Prefs copyWith({String? timezone, String? locale, ThemePref? theme}) {
    return Prefs(
      timezone: timezone ?? this.timezone,
      locale: locale ?? this.locale,
      theme: theme ?? this.theme,
    );
  }
}

/// Compact item representation used by list endpoints.
class ItemSummary {
  const ItemSummary({
    required this.pid,
    required this.mediaType,
    required this.title,
    required this.durationMs,
    this.artist,
    this.album,
    this.artUrl,
  });

  /// Type-prefixed ULID.
  final String pid;
  final MediaType mediaType;
  final String title;

  /// Primary display artist, author, or show name.
  final String? artist;

  /// Album, series, or podcast title, when applicable.
  final String? album;

  final int durationMs;

  /// Artwork URL, already resolved against the client base URL so it can be
  /// loaded directly on any platform.
  final String? artUrl;
}

/// Full detail for a single library item.
class ItemDetail extends ItemSummary {
  const ItemDetail({
    required super.pid,
    required super.mediaType,
    required super.title,
    required super.durationMs,
    super.artist,
    super.album,
    super.artUrl,
    this.genres = const [],
    this.year,
    this.trackNumber,
    this.discNumber,
    this.codec,
    this.container,
    this.sampleRate,
    this.bitrate,
    this.addedAt,
  });

  final List<String> genres;
  final int? year;
  final int? trackNumber;
  final int? discNumber;
  final String? codec;
  final String? container;
  final int? sampleRate;
  final int? bitrate;
  final DateTime? addedAt;
}

/// One keyset-paginated page of items.
class ItemPage {
  const ItemPage({required this.items, this.nextCursor, this.seed});

  final List<ItemSummary> items;

  /// Opaque cursor for the next page; null on the last page.
  final String? nextCursor;

  /// Effective shuffle seed, present only on random browse pages. Pass it
  /// back with the cursor so later pages keep the same order.
  final int? seed;

  bool get hasMore => nextCursor != null;
}

/// Everything a client needs to begin playback of one item.
class PlayInfo {
  const PlayInfo({
    required this.pid,
    required this.url,
    required this.mimeType,
    required this.durationMs,
    required this.seekable,
    required this.expiresAt,
    this.partIndex,
    this.partCount,
    this.partStartMs,
    this.voiceBoost = false,
    this.spanStartMs,
    this.spanEndMs,
  });

  final String pid;

  /// Stream URL, already resolved against the client base URL. With an empty
  /// base (web builds) it stays origin-relative, which the browser resolves
  /// against the single origin serving the SPA.
  final String url;

  final String mimeType;

  /// Duration of the served stream: for a multi-file audiobook this is
  /// the resolved part's duration, not the book total.
  final int durationMs;
  final bool seekable;

  /// When the embedded media token stops being accepted; re-request
  /// play-info after this instant.
  final DateTime expiresAt;

  /// Zero-based index of the resolved part of a multi-file audiobook;
  /// null for single-file items.
  final int? partIndex;

  /// Total number of parts of a multi-file audiobook; null for
  /// single-file items.
  final int? partCount;

  /// Book-timeline millisecond where the resolved part begins; null for
  /// single-file items.
  final int? partStartMs;

  /// Whether server-side voice boost is actually applied to the stream.
  final bool voiceBoost;

  /// Playback window within the served audio, present only when the
  /// url carries the item's whole backing file and the item is a
  /// window into it (direct playback of a carved track): the player
  /// clips to [spanStartMs, spanEndMs). Null when the server cuts.
  final int? spanStartMs;
  final int? spanEndMs;
}

/// The calling user's playback state for one item.
class PlayState {
  const PlayState({
    required this.pid,
    required this.positionMs,
    required this.played,
    required this.finished,
    required this.playCount,
    required this.starred,
    this.rating,
    this.updatedAt,
  });

  final String pid;
  final int positionMs;
  final bool played;
  final bool finished;
  final int playCount;
  final bool starred;

  /// The caller's rating, 0 to 100; null when unrated.
  final int? rating;

  final DateTime? updatedAt;
}

/// One listen session as reported by this client.
///
/// [sessionId] is a client-generated idempotency ID, unique per playback
/// session; replaying a session with the same ID never double-counts, so
/// retrying a failed report is always safe.
class ListenSession {
  const ListenSession({
    required this.sessionId,
    required this.pid,
    required this.startedAt,
    required this.msPlayed,
    this.finished = false,
    this.client,
  });

  final String sessionId;
  final String pid;

  /// When playback started, in UTC.
  final DateTime startedAt;

  /// Milliseconds actually heard, excluding pauses and seeks.
  final int msPlayed;

  /// Whether playback reached the end of the item.
  final bool finished;

  /// Client identifier, for example waxdeck-flutter-web.
  final String? client;
}

/// One session the server refused, and why.
class RejectedListen {
  const RejectedListen({
    required this.sessionId,
    required this.code,
    required this.message,
  });

  final String sessionId;
  final String code;
  final String message;
}

/// Outcome of a listen ingest batch.
class ListenOutcome {
  const ListenOutcome({
    required this.accepted,
    required this.duplicates,
    this.rejected = const [],
  });

  /// Sessions recorded for the first time.
  final int accepted;

  /// Replays of known session IDs, ignored without error.
  final int duplicates;

  final List<RejectedListen> rejected;
}

/// One ranked search hit.
class SearchHit {
  const SearchHit({
    required this.pid,
    required this.kind,
    required this.title,
    this.subtitle,
  });

  final String pid;

  /// What the hit is: artist, album, track, book, or episode.
  final String kind;

  final String title;
  final String? subtitle;
}

/// Search results grouped by kind, ranked within each group.
class SearchResults {
  const SearchResults({
    required this.query,
    this.artists = const [],
    this.albums = const [],
    this.tracks = const [],
    this.books = const [],
    this.episodes = const [],
    this.truncated = false,
  });

  final String query;
  final List<SearchHit> artists;
  final List<SearchHit> albums;
  final List<SearchHit> tracks;
  final List<SearchHit> books;
  final List<SearchHit> episodes;

  /// True when any group was capped at the requested limit.
  final bool truncated;
}

/// One mirrored catalog change: an upsert carrying the item's current
/// summary, or a delete tombstone. Tombstone pids identify the item by
/// ULID; the prefix is not significant once the item is gone, so
/// mirrors match deletes on the ULID part.
class CatalogSyncEntry {
  const CatalogSyncEntry({
    required this.op,
    required this.pid,
    this.item,
    this.episode,
    this.show,
  });

  /// `upsert`, `upsert-show`, or `delete`. Entries with an unrecognized
  /// op are dropped.
  final String op;
  final String pid;
  final ItemSummary? item;

  /// Episode payload accompanying podcast-episode upserts, when present.
  final EpisodeSummary? episode;

  /// Show payload of an `upsert-show` entry, when present.
  final PodcastShow? show;
}

/// One page of catalog sync entries (snapshot or delta).
class CatalogSyncPage {
  const CatalogSyncPage({
    this.entries = const [],
    this.nextCursor,
    required this.nextSince,
    this.more = false,
  });

  final List<CatalogSyncEntry> entries;

  /// Keyset cursor for the next snapshot page; null on the last
  /// snapshot page and on delta pages.
  final String? nextCursor;

  /// Opaque change cursor to sync from next.
  final String nextSince;

  /// True when another delta page should be fetched immediately.
  final bool more;
}

/// One change to the calling user's server-side state, hydrated fresh.
class ServerSyncEvent {
  const ServerSyncEvent({
    required this.kind,
    this.pid,
    this.playState,
    this.prefs,
    this.subscription,
    this.bookSettings,
  });

  /// `play-state`, `prefs`, `subscription`, or `book-settings`; events
  /// with an unrecognized kind are skipped.
  final String kind;
  final String? pid;
  final PlayState? playState;
  final Prefs? prefs;
  final Subscription? subscription;
  final BookSettings? bookSettings;
}

/// One page of the caller's server-side state changes.
class ServerSyncPage {
  const ServerSyncPage({
    this.events = const [],
    required this.nextSince,
    this.more = false,
  });

  final List<ServerSyncEvent> events;
  final String nextSince;
  final bool more;
}

/// One downloadable backing file of an item.
class DownloadFileInfo {
  const DownloadFileInfo({
    required this.url,
    required this.mimeType,
    required this.sizeBytes,
    required this.fileName,
    required this.essenceHash,
    required this.etag,
  });

  /// Media-token-authenticated download URL, resolved against the
  /// client base URL.
  final String url;
  final String mimeType;
  final int sizeBytes;
  final String fileName;

  /// Content hash of the audio essence: the download-store key, stable
  /// across retags and moves.
  final String essenceHash;

  /// Strong validator of the exact file bytes; a mismatch means restart
  /// this file's transfer instead of resuming a range.
  final String etag;
}

/// Everything needed to download one item's original bytes.
class DownloadInfo {
  const DownloadInfo({
    required this.pid,
    required this.files,
    this.spanStartMs,
    this.spanEndMs,
    required this.expiresAt,
  });

  final String pid;

  /// Backing files in playback order (one per part for a multi-file
  /// audiobook).
  final List<DownloadFileInfo> files;

  /// Playback window for items carved out of a larger file (CUE-backed
  /// virtual tracks); offline playback plays the window.
  final int? spanStartMs;
  final int? spanEndMs;
  final DateTime expiresAt;
}

/// One app password, without its secret.
class AppPassword {
  const AppPassword({
    required this.id,
    required this.label,
    required this.createdAt,
    this.lastUsedAt,
  });

  final String id;
  final String label;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
}

/// A newly created app password; [secret] is visible exactly once.
class AppPasswordCreated extends AppPassword {
  const AppPasswordCreated({
    required super.id,
    required super.label,
    required super.createdAt,
    super.lastUsedAt,
    required this.secret,
  });

  final String secret;
}

/// One podcast show as cataloged on the server.
class PodcastShow {
  const PodcastShow({
    required this.pid,
    required this.title,
    this.author,
    this.descriptionHtml,
    this.feedUrl,
    this.link,
    required this.sourceType,
    this.artUrl,
    this.episodeCount,
    this.lastPublishedAt,
    this.refreshDisabled = false,
  });

  final String pid;
  final String title;
  final String? author;

  /// Show description as sanitized HTML (server-side allowlist).
  final String? descriptionHtml;
  final String? feedUrl;
  final String? link;

  /// Where the show comes from: `rss` or `youtube`.
  final String sourceType;

  /// Artwork URL, already resolved against the client base URL.
  final String? artUrl;
  final int? episodeCount;
  final DateTime? lastPublishedAt;

  /// True when scheduled refresh was auto-disabled after repeated
  /// failures; a successful manual refresh re-enables it.
  final bool refreshDisabled;
}

/// The caller's per-subscription settings. The PUT endpoint replaces the
/// whole document, so senders start from the stored value.
class SubscriptionSettings {
  const SubscriptionSettings({
    this.retentionKeep,
    this.autoDownload = false,
    this.folder,
    this.private = false,
    this.speed,
    this.trimSilence,
    this.voiceBoost,
    this.skipIntroSeconds,
    this.skipOutroSeconds,
  });

  /// Episodes to keep on the server; null means the server default and
  /// 0 means keep all.
  final int? retentionKeep;
  final bool autoDownload;
  final String? folder;
  final bool private;

  /// Remembered playback speed for this show; null means the default.
  final double? speed;
  final bool? trimSilence;
  final bool? voiceBoost;
  final int? skipIntroSeconds;
  final int? skipOutroSeconds;
}

/// One of the caller's podcast subscriptions.
class Subscription {
  const Subscription({
    required this.show,
    required this.settings,
    required this.subscribedAt,
  });

  final PodcastShow show;
  final SubscriptionSettings settings;
  final DateTime subscribedAt;
}

/// Show detail with the caller's subscription state.
class PodcastDetail {
  const PodcastDetail({
    required this.show,
    required this.subscribed,
    this.settings,
  });

  final PodcastShow show;
  final bool subscribed;

  /// The caller's settings, present only when subscribed.
  final SubscriptionSettings? settings;
}

/// One keyset-paginated page of subscriptions.
class SubscriptionPage {
  const SubscriptionPage({required this.items, this.nextCursor});

  final List<Subscription> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// Compact episode representation used by list endpoints.
class EpisodeSummary extends ItemSummary {
  const EpisodeSummary({
    required super.pid,
    required super.mediaType,
    required super.title,
    required super.durationMs,
    super.artist,
    super.album,
    super.artUrl,
    required this.showPid,
    this.season,
    this.episodeNumber,
    this.episodeType,
    required this.publishedAt,
    required this.downloaded,
    this.fetchState,
    this.fetchError,
    this.explicit = false,
    this.hasTranscript = false,
  });

  /// The show this episode belongs to.
  final String showPid;
  final int? season;
  final int? episodeNumber;

  /// Feed-declared type (`full`, `trailer`, `bonus`); open set, treat
  /// unknown values like `full`.
  final String? episodeType;
  final DateTime publishedAt;

  /// Whether the audio is on the server; play-info for a not-yet-fetched
  /// episode answers `conflict`.
  final bool downloaded;

  /// `queued` or `failed` while a server-side fetch is pending or after
  /// one failed; null otherwise. Open set, treat unknown as `queued`.
  final String? fetchState;
  final String? fetchError;
  final bool explicit;
  final bool hasTranscript;
}

/// One keyset-paginated page of episodes.
class EpisodePage {
  const EpisodePage({required this.items, this.nextCursor});

  final List<EpisodeSummary> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// Full detail for one episode.
class EpisodeDetail extends EpisodeSummary {
  const EpisodeDetail({
    required super.pid,
    required super.mediaType,
    required super.title,
    required super.durationMs,
    super.artist,
    super.album,
    super.artUrl,
    required super.showPid,
    super.season,
    super.episodeNumber,
    super.episodeType,
    required super.publishedAt,
    required super.downloaded,
    super.fetchState,
    super.fetchError,
    super.explicit,
    super.hasTranscript,
    this.descriptionHtml,
    this.link,
    this.chapters = const [],
  });

  /// Show notes as sanitized HTML (server-side allowlist).
  final String? descriptionHtml;
  final String? link;
  final List<ChapterMark> chapters;
}

/// One chapter mark, ordered by [startMs].
class ChapterMark {
  const ChapterMark({
    required this.index,
    this.title,
    required this.startMs,
    this.endMs,
  });

  final int index;
  final String? title;
  final int startMs;
  final int? endMs;
}

/// One time-coded transcript cue.
class TranscriptCue {
  const TranscriptCue({
    required this.startMs,
    this.endMs,
    required this.text,
    this.speaker,
  });

  final int startMs;
  final int? endMs;
  final String text;
  final String? speaker;
}

/// An episode's transcript as time-coded cues.
class Transcript {
  const Transcript({required this.format, required this.cues});

  final String format;
  final List<TranscriptCue> cues;
}

/// One backing file of a multi-file audiobook, in reading order.
class BookPart {
  const BookPart({
    required this.index,
    required this.startMs,
    required this.durationMs,
    this.displayName,
  });

  final int index;

  /// Book-timeline millisecond where this part begins.
  final int startMs;
  final int durationMs;
  final String? displayName;
}

/// The caller's per-book playback settings. The PUT endpoint replaces
/// the whole document.
class BookSettings {
  const BookSettings({this.speed, this.voiceBoost, this.trimSilence});

  final double? speed;
  final bool? voiceBoost;
  final bool? trimSilence;
}

/// Full audiobook detail. Positions are book-timeline milliseconds
/// spanning all parts.
class BookDetail {
  const BookDetail({
    required this.pid,
    required this.title,
    this.subtitle,
    this.authors = const [],
    this.narrators = const [],
    this.series,
    this.seriesSequence,
    this.publisher,
    this.asin,
    this.isbn,
    this.edition,
    this.abridged,
    this.descriptionHtml,
    required this.durationMs,
    this.artUrl,
    this.chapters = const [],
    this.parts = const [],
    this.settings,
  });

  final String pid;
  final String title;
  final String? subtitle;
  final List<String> authors;
  final List<String> narrators;
  final String? series;
  final String? seriesSequence;
  final String? publisher;
  final String? asin;
  final String? isbn;
  final String? edition;
  final bool? abridged;

  /// Description as sanitized HTML (server-side allowlist).
  final String? descriptionHtml;

  /// Book total across all parts.
  final int durationMs;
  final String? artUrl;
  final List<ChapterMark> chapters;
  final List<BookPart> parts;

  /// The caller's per-book playback settings, when any are stored.
  final BookSettings? settings;
}

/// The caller's resume point on the book timeline.
class BookResume {
  const BookResume({required this.positionMs, this.chapter, this.updatedAt});

  final int positionMs;

  /// The chapter [positionMs] falls in, when the book has chapters.
  final ChapterMark? chapter;
  final DateTime? updatedAt;
}

/// One silence span, in the mapped file's own timeline.
class SkipSpan {
  const SkipSpan({required this.startMs, required this.endMs});

  final int startMs;
  final int endMs;
}

/// Precomputed silence spans for client-side trimming.
class SkipMap {
  const SkipMap({
    required this.state,
    this.essenceHash,
    this.partIndex,
    this.version,
    this.spans = const [],
  });

  /// `ready`, `pending`, or `unavailable`; spans are empty unless ready.
  final String state;
  final String? essenceHash;
  final int? partIndex;
  final String? version;
  final List<SkipSpan> spans;

  bool get ready => state == 'ready';
}

/// One node of a smart rule's condition tree. [type] selects the shape:
/// `all` and `any` carry [nodes], `not` carries [node], `condition`
/// compares [field] with [op] against [value] (or [values] for
/// `inTheRange`). Values are strings on the wire regardless of the
/// field's kind.
class RuleNode {
  const RuleNode({
    required this.type,
    this.nodes = const [],
    this.node,
    this.field,
    this.op,
    this.value,
    this.values = const [],
  });

  const RuleNode.all([this.nodes = const []])
    : type = 'all',
      node = null,
      field = null,
      op = null,
      value = null,
      values = const [];

  const RuleNode.any([this.nodes = const []])
    : type = 'any',
      node = null,
      field = null,
      op = null,
      value = null,
      values = const [];

  const RuleNode.condition({
    required String this.field,
    required String this.op,
    this.value,
    this.values = const [],
  }) : type = 'condition',
       nodes = const [],
       node = null;

  final String type;
  final List<RuleNode> nodes;
  final RuleNode? node;
  final String? field;
  final String? op;
  final String? value;
  final List<String> values;
}

/// One sort key of a smart rule.
class RuleSort {
  const RuleSort({required this.field, this.desc = false});

  final String field;
  final bool desc;
}

/// A smart playlist rule: condition tree, sort order, and row limit
/// (0 means unlimited).
class SmartRule {
  const SmartRule({required this.root, this.sorts = const [], this.limit = 0});

  final RuleNode root;
  final List<RuleSort> sorts;
  final int limit;
}

/// A playlist: `static` (manual ordered members) or `smart` (rule
/// evaluated on read). [itemCount] is null when omitted (smart playlists
/// on list pages). [rule] is null for static playlists.
class Playlist {
  const Playlist({
    required this.pid,
    required this.name,
    required this.kind,
    required this.visibility,
    required this.ownerName,
    required this.isOwner,
    required this.createdAt,
    required this.updatedAt,
    this.previousPid,
    this.itemCount,
    this.rule,
  });

  final String pid;

  /// Set after a rule replace reissued the pid; clients relink instead of
  /// treating the reissue as a delete and create.
  final String? previousPid;
  final String name;

  /// `static` or `smart`; unknown kinds render read-only.
  final String kind;

  /// `private` or `shared`.
  final String visibility;
  final String ownerName;

  /// True when the caller owns the playlist and may edit it.
  final bool isOwner;
  final int? itemCount;
  final SmartRule? rule;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isSmart => kind == 'smart';
  bool get isShared => visibility == 'shared';
}

/// One page of playlists.
class PlaylistPage {
  const PlaylistPage({required this.playlists, this.nextCursor});

  final List<Playlist> playlists;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// One playlist member. [position] is the stored order for static
/// playlists (the removal endpoint takes it); null for smart playlists.
class PlaylistEntry {
  const PlaylistEntry({required this.item, this.position});

  final int? position;
  final ItemSummary item;
}

/// One page of playlist members.
class PlaylistItemsPage {
  const PlaylistItemsPage({required this.entries, this.nextCursor});

  final List<PlaylistEntry> entries;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// A stateless rule evaluation: the first matching items plus the total
/// match count ignoring the rule's own limit.
class PlaylistPreview {
  const PlaylistPreview({required this.items, required this.total});

  final List<ItemSummary> items;
  final int total;
}

/// One rule field the editor may offer.
class RuleField {
  const RuleField({
    required this.name,
    required this.kind,
    required this.ops,
    required this.userState,
    required this.sortable,
    this.description,
  });

  final String name;

  /// `text`, `number`, `date`, `boolean`, or `mediaType`.
  final String kind;
  final List<String> ops;

  /// True when the field reads the evaluating user's playback state.
  final bool userState;
  final bool sortable;
  final String? description;
}

/// One custom tag key usable as a `tag.KEY` rule field.
class RuleTagKey {
  const RuleTagKey({required this.key, required this.itemCount});

  final String key;
  final int itemCount;
}

/// The rule vocabulary for smart rule editors. Tag fields are text-kind,
/// accept the unordered text operators, and never sort.
class RuleFields {
  const RuleFields({required this.fields, required this.tagKeys});

  final List<RuleField> fields;
  final List<RuleTagKey> tagKeys;
}

/// Outcome of an M3U8 import.
class M3uImportResult {
  const M3uImportResult({
    required this.playlist,
    required this.matched,
    required this.unmatched,
    this.unmatchedPaths = const [],
  });

  final Playlist playlist;
  final int matched;
  final int unmatched;
  final List<String> unmatchedPaths;
}

/// One internet radio station in the shared library.
class RadioStation {
  const RadioStation({
    required this.pid,
    required this.name,
    required this.streamUrl,
    required this.createdAt,
    this.homepageUrl,
    this.logoUrl,
  });

  final String pid;
  final String name;
  final String streamUrl;
  final String? homepageUrl;
  final String? logoUrl;
  final DateTime createdAt;
}

/// One station directory match.
class RadioDirectoryEntry {
  const RadioDirectoryEntry({
    required this.name,
    required this.streamUrl,
    this.homepageUrl,
    this.logoUrl,
    this.tags,
    this.country,
    this.codec,
    this.bitrateKbps,
  });

  final String name;
  final String streamUrl;
  final String? homepageUrl;
  final String? logoUrl;
  final String? tags;
  final String? country;
  final String? codec;
  final int? bitrateKbps;
}

/// A resolved, tokenized station stream, absolute against the client
/// base URL.
class RadioPlayInfo {
  const RadioPlayInfo({required this.url, this.nowPlaying});

  final String url;

  /// The station's current in-stream title, present only while a
  /// proxied listener has the stream open. Poll play-info while
  /// playing to keep it fresh; keep the open stream and ignore the
  /// fresh url.
  final String? nowPlaying;
}

/// One outbound scrobbling connection slot.
class Scrobbler {
  const Scrobbler({
    required this.service,
    required this.available,
    required this.connected,
    this.username,
    this.apiUrl,
    this.lastSuccessAt,
    this.lastError,
    this.lastErrorAt,
  });

  /// `lastfm` or `listenbrainz`; clients skip unknown services.
  final String service;
  final bool available;
  final bool connected;
  final String? username;
  final String? apiUrl;

  /// Delivery health: the last successful delivery, and the standing
  /// error while the connection is unhealthy (cleared by the next
  /// success and by reconnecting).
  final DateTime? lastSuccessAt;
  final String? lastError;
  final DateTime? lastErrorAt;
}

/// The server's notification relay configuration (administrators).
class NotificationConfig {
  const NotificationConfig({
    required this.appriseUrl,
    required this.enabledEvents,
    required this.knownEvents,
    this.targets,
  });

  final String appriseUrl;
  final String? targets;
  final List<String> enabledEvents;
  final List<String> knownEvents;
}

/// One UnifiedPush endpoint registration.
class PushRegistration {
  const PushRegistration({
    required this.pid,
    required this.endpoint,
    required this.createdAt,
    this.label,
  });

  final String pid;
  final String endpoint;
  final String? label;
  final DateTime createdAt;
}
