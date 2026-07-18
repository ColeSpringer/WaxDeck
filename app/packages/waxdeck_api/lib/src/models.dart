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
  });

  final String pid;

  /// Stream URL, already resolved against the client base URL. With an empty
  /// base (web builds) it stays origin-relative, which the browser resolves
  /// against the single origin serving the SPA.
  final String url;

  final String mimeType;
  final int durationMs;
  final bool seekable;

  /// When the embedded media token stops being accepted; re-request
  /// play-info after this instant.
  final DateTime expiresAt;
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
