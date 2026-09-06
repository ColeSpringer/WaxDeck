/// Plain-Dart views over the generated built_value DTOs.
///
/// These are the types feature code sees. They are deliberately boring:
/// no built_value, no generator idioms, easy to construct in tests.
library;

import 'dart:typed_data';

/// Server liveness/version snapshot (`GET /health`).
class ServerHealth {
  const ServerHealth({
    required this.status,
    required this.version,
    required this.apiVersion,
    this.uploadFormats,
    this.rejectedFormats,
  });

  final String status;
  final String version;
  final int apiVersion;

  /// File extensions uploads accept (lowercase, no dot) - the server's
  /// effective set, so an operator's replacement is what appears here.
  /// Null on servers older than the field; callers fall back to their
  /// own mirror of the default set.
  final List<String>? uploadFormats;

  /// Extensions refused outright whatever [uploadFormats] says (DRM
  /// containers). Null on servers older than the field.
  final List<String>? rejectedFormats;

  bool get ok => status == 'ok';
}

/// Structured API error (the spec's `Error` schema), thrown by the client.
///
/// A failure with no answer to read a code out of still arrives as one
/// of these, so this package mints three of its own: `transport` (the
/// request did not complete), `transport-timeout` (no answer in time,
/// deliberately not the spec's `timeout`, which means a routed command
/// whose endpoint is still connected), and `transport-empty` (an answer
/// with no body). Stable client vocabulary, absent from the spec's list,
/// so a caller wording errors by code covers them alongside it.
class WaxDeckApiException implements Exception {
  const WaxDeckApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.params,
  });

  /// Stable machine-readable code (`unauthenticated`, `not-found`, and so
  /// on), or one of this package's own transport codes.
  final String code;

  /// Human-readable explanation; not stable, never parse it.
  final String message;

  final int? statusCode;

  /// Machine-readable detail for the codes that cover more than one
  /// cause, keyed as the contract documents per code
  /// (`feature-unavailable` carries `feature` and `pid`). Best-effort:
  /// null covers a refusal that mints none and a server older than the
  /// field alike, so refine on it, never require it.
  final Map<String, String>? params;

  @override
  String toString() => 'WaxDeckApiException($code, $statusCode): $message';
}

/// An error's `params` as a plain string map, or null for anything that
/// is not one. A key or value of another type is dropped rather than
/// stringified, and an empty result reads as absent: a caller branches
/// on these, and branching on a guess is worse than taking the fallback.
///
/// Public because the same field arrives on two transports - an HTTP
/// body and a socket error frame - and a refusal that read differently
/// on each would explain itself differently depending on how it got
/// here.
Map<String, String>? errorParamsFromWire(Object? raw) {
  if (raw is! Map) return null;
  final out = <String, String>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is String && value is String) out[key] = value;
  }
  return out.isEmpty ? null : out;
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

/// What a recorded listen was.
///
/// A sibling of [MediaType] rather than a widening of it, because the
/// two answer different questions. [MediaType] is the three first-class
/// *item* kinds - what browse, items, and uploads deal in, none of
/// which will ever answer `radio`. This is what the listening record
/// can hold, and radio is measured server-side in the stream proxy and
/// belongs to no item at all.
enum StatsMediaType {
  music('music'),
  podcast('podcast'),
  audiobook('audiobook'),
  radio('radio');

  const StatsMediaType(this.wireName);

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
  alphabetical('alphabetical'),

  /// Owned and never counted a play of: the collection shelf no
  /// streaming service can draw.
  neverPlayed('never-played'),

  /// Starred or well rated and not heard in six months.
  rediscover('rediscover');

  const DiscoveryList(this.wireName);

  /// Value as it appears on the wire.
  final String wireName;
}

/// How a browse dimension's buckets are ordered.
enum FacetSort {
  /// Biggest buckets first: what a hub's shelves and tiles want.
  count('count'),

  /// A to Z by display label: what an index with an alphabet rail
  /// scrolls through.
  label('label');

  const FacetSort(this.wireName);

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
    this.uploadEnabled = false,
    this.managePodcasts = false,
    this.canDelete = false,
  });

  final String id;
  final String username;
  final String? displayName;
  final List<String> roles;

  /// The *effective* upload right (administrators always hold it);
  /// upload affordances gate on this.
  final bool uploadEnabled;

  /// The *effective* podcast-curation right (administrators always
  /// hold it); podcast-curation affordances gate on this.
  final bool managePodcasts;

  /// The *effective* right to move library items to the trash
  /// (administrators always hold it); destructive affordances gate on
  /// this. False from a server too old to report it, where the admin
  /// role is the fallback gate.
  final bool canDelete;

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
  const BootstrapStatus({required this.required, this.signupEnabled = false});

  /// True while the server has no accounts; clients route to the setup
  /// screen instead of the login screen while this holds.
  final bool required;

  /// Whether open self-signup is switched on; invite-token signups work
  /// regardless.
  final bool signupEnabled;
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
  const Prefs({
    this.timezone,
    this.locale,
    this.theme,
    this.sharedStatsOptOut,
    this.radioFavorites,
    this.radioScrobbleMutedStations,
    this.pinned,
    this.crossfadeSeconds,
    this.replayGain,
    this.radioScrobbleOptOut,
    this.identifyOptOut,
    this.browseShowUnknown,
    this.browseSorts,
    this.autoplay,
  });

  /// IANA timezone name, for example Europe/Amsterdam.
  final String? timezone;

  /// Preferred BCP 47 locale tag, for example en-US.
  final String? locale;

  final ThemePref? theme;

  /// Leave the server-wide aggregate stats (the server year in review).
  /// Absent means enrolled, the default.
  final bool? sharedStatsOptOut;

  /// Radio stations this account has pinned, in dial order.
  ///
  /// The station library is shared by the household, so this is the one
  /// piece of per-user station state there is.
  ///
  /// Null is an absent list, which the server answers with when nothing is
  /// pinned - unpinning everything clears the field rather than storing
  /// `[]`. Nothing here defaults a pinned station out of an absent list, so
  /// absent and empty are the same answer on the way back, deliberately;
  /// what makes the last unpin stick is that an empty list is a *value* on
  /// the way out, which [copyWith] carries and null does not.
  final List<String>? radioFavorites;

  /// Stations whose segments this account does not scrobble, while it
  /// scrobbles radio at all.
  ///
  /// A set: nothing reads an order out of it. The same shape and the
  /// same absent-is-empty rule as [radioFavorites], and read only when
  /// [radioScrobbleOptOut] is unset, which is the whole dial at once.
  final List<String>? radioScrobbleMutedStations;

  /// What this account has pinned to home, in shelf order.
  ///
  /// Entity pids (`al-`, `ar-`, `rg-`, `pl-`, `pc-`, `bk-`), resolved to
  /// cards through `POST /library/entities`. Absent and empty are one
  /// answer here for [radioFavorites]' reason, and the last unpin sticks
  /// for the same one: an empty list is a value [copyWith] carries.
  final List<String>? pinned;

  /// Equal-power crossfade at every seam of a queue the server renders as
  /// one stream, in seconds. Absent or zero is a gapless butt join.
  ///
  /// On the account rather than in a client's own storage because the
  /// server applies it, and re-applies it on every queue edit a cast
  /// session takes, when no client is in the loop to supply a value.
  final double? crossfadeSeconds;

  /// Level a server-rendered queue to a common loudness, from the
  /// measurements the analyze pass stores. Same reason for living here as
  /// [crossfadeSeconds].
  final bool? replayGain;

  /// Stop reporting radio segments to this account's scrobblers. Absent
  /// means enrolled, the default.
  final bool? radioScrobbleOptOut;

  /// Stop identifying this account's own submissions by default. Absent
  /// means uploads and acquisitions are matched, the default; either
  /// sheet can still say so per submission.
  final bool? identifyOptOut;

  /// Whether a browse index draws the bucket for the items a dimension is
  /// absent from. Absent means shown. A presentation choice, not a server
  /// filter: the bucket still drills either way.
  final bool? browseShowUnknown;

  /// The order each browse index opens in, by dimension name, in wire
  /// form; read through [browseSortFor]. Strings rather than [FacetSort]
  /// so a value [FacetSort] does not name survives the round trip
  /// instead of being erased by the next write to another dimension.
  ///
  /// A value the *generated* client predates does not survive, and not
  /// only locally: it drops on the way in as the generator's sentinel,
  /// and since the PUT replaces the document, the next write of any
  /// preference takes that dimension's order off the server too.
  /// Dropping still beats keeping it, whose wire value fails every save;
  /// the real fix is the contract, and docs/deferred-work.md holds it.
  final Map<String, String>? browseSorts;

  /// The stored order for one dimension, or null when there is none and
  /// when this build does not know the one stored.
  FacetSort? browseSortFor(String dimension) {
    final stored = browseSorts?[dimension];
    if (stored == null) return null;
    for (final value in FacetSort.values) {
      if (value.wireName == stored) return value;
    }
    return null;
  }

  /// Whether playback may start with no gesture behind it. Absent is
  /// allowed.
  final bool? autoplay;

  /// Copy with individual fields replaced. Passing null keeps the current
  /// value; clearing a stored field is not something the UI needs yet.
  Prefs copyWith({
    String? timezone,
    String? locale,
    ThemePref? theme,
    bool? sharedStatsOptOut,
    List<String>? radioFavorites,
    List<String>? radioScrobbleMutedStations,
    List<String>? pinned,
    double? crossfadeSeconds,
    bool? replayGain,
    bool? radioScrobbleOptOut,
    bool? identifyOptOut,
    bool? browseShowUnknown,
    Map<String, String>? browseSorts,
    bool? autoplay,
  }) {
    return Prefs(
      timezone: timezone ?? this.timezone,
      locale: locale ?? this.locale,
      theme: theme ?? this.theme,
      sharedStatsOptOut: sharedStatsOptOut ?? this.sharedStatsOptOut,
      radioFavorites: radioFavorites ?? this.radioFavorites,
      radioScrobbleMutedStations:
          radioScrobbleMutedStations ?? this.radioScrobbleMutedStations,
      pinned: pinned ?? this.pinned,
      crossfadeSeconds: crossfadeSeconds ?? this.crossfadeSeconds,
      replayGain: replayGain ?? this.replayGain,
      radioScrobbleOptOut: radioScrobbleOptOut ?? this.radioScrobbleOptOut,
      identifyOptOut: identifyOptOut ?? this.identifyOptOut,
      browseShowUnknown: browseShowUnknown ?? this.browseShowUnknown,
      browseSorts: browseSorts ?? this.browseSorts,
      autoplay: autoplay ?? this.autoplay,
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
    this.artistPid,
    this.albumPid,
    this.trackNumber,
    this.discNumber,
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

  /// The artist entity behind [artist], so rows group and link by
  /// identity rather than by display text. Null when there is none.
  final String? artistPid;

  /// The album entity behind [album]. Tracks only: an episode's or a
  /// book's [album] is a show or series title with no album entity
  /// behind it.
  final String? albumPid;

  /// Track position within its disc, and the disc within the release.
  /// On the summary because a listing is where they are needed: an
  /// items page arrives in the catalog's own order, and these are what
  /// sort a release back into itself. Null when the item carries none.
  final int? trackNumber;
  final int? discNumber;

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
    super.artistPid,
    super.albumPid,
    super.trackNumber,
    super.discNumber,
    super.artUrl,
    this.genres = const [],
    this.year,
    this.bpm,
    this.codec,
    this.container,
    this.sampleRate,
    this.bitrate,
    this.addedAt,
    this.mbid,
    this.isrc,
    this.artSource,
  });

  final List<String> genres;
  final int? year;

  /// Stated tempo, whole. Null for an item carrying none, which is most
  /// of them; nothing measures it, so this is the tag's number rather
  /// than an analysis result.
  final int? bpm;
  final String? codec;
  final String? container;
  final int? sampleRate;
  final int? bitrate;
  final DateTime? addedAt;

  /// The recording's own identifiers, as tagged or matched. Null for
  /// the items carrying neither, which is most of an untagged library.
  final String? mbid;
  final String? isrc;

  /// Where the cover this item resolves came from, so a surface drawing
  /// it large can say so. Null when nothing is attributed.
  final ArtSource? artSource;
}

/// What an [EntityCard] is about, which is what a tap opens.
enum EntityCardKind { album, artist, releaseGroup, playlist, podcast, book }

/// The display facts behind one entity pid: what a card draws for
/// something a client holds only a handle for.
///
/// No artwork field, deliberately: the art endpoint takes every prefix
/// this answers for except a release group, which statically has none, so
/// a caller builds the URL from the pid it already had.
class EntityCard {
  const EntityCard({
    required this.pid,
    required this.kind,
    required this.title,
    this.artist,
    this.year,
    this.itemCount,
  });

  final String pid;
  final EntityCardKind kind;
  final String title;

  /// The context line: an album's or book's artist, a show's author, a
  /// playlist's owner. Absent for an artist, whose title is the name.
  final String? artist;

  final int? year;

  /// Member items, where counting one is cheap. Absent is not zero: a
  /// smart playlist's count is deliberately not taken.
  final int? itemCount;
}

/// What a batch entity resolve answered: the cards that drew, and the
/// pids that are gone for everyone.
class EntityResolution {
  const EntityResolution({required this.cards, this.departed = const []});

  /// Cards in request order, minus every pid the server could not
  /// answer for this caller.
  final List<EntityCard> cards;

  /// The requested pids that no longer name anything on the server, for
  /// anyone: deleted, merged away, or never real. A miss that is merely
  /// out of this caller's sight today - a grant, a lapsed subscription,
  /// the trash - is not here, because it can come back. This is the set
  /// a pinned list prunes.
  final List<String> departed;
}

/// One album entity's identity: the release facts the catalog keeps on
/// the entity rather than on any of its tracks.
///
/// A header derived from track rows can reach the title, the artist, and
/// the year. It cannot reach the five below [releaseGroupPid], which
/// describe the edition rather than the file.
class AlbumDetail {
  const AlbumDetail({
    required this.pid,
    required this.title,
    this.sortKey,
    this.mbid,
    this.year,
    this.releaseGroupPid,
    this.barcode,
    this.label,
    this.catalogNumber,
    this.media,
    this.country,
    this.itemCount,
    this.totalDurationMs,
    this.artSource,
  });

  final String pid;
  final String title;
  final String? sortKey;
  final String? mbid;
  final int? year;
  final String? releaseGroupPid;

  final String? barcode;
  final String? label;
  final String? catalogNumber;

  /// What the release was pressed on, as tagged ("CD", "2xVinyl"). A
  /// scan stores the tag verbatim, so this is a description, not an enum.
  final String? media;

  /// Release country, as tagged. A scan can store a value an edit would
  /// refuse ("US & Europe"), so it is displayed and never validated here.
  final String? country;

  final int? itemCount;
  final int? totalDurationMs;

  /// Where the cover this release resolves came from. For an album with
  /// no durable cover of its own that is a member track's, marked
  /// [ArtSource.derived].
  final ArtSource? artSource;

  /// Whether the release carries any identity at all. Most do not, and a
  /// header with five blank labels is worse than no block.
  bool get hasIdentity =>
      (barcode ?? label ?? catalogNumber ?? media ?? country) != null;
}

/// One bucket of a browse dimension: a value the library groups by, with
/// how many items carry it.
class FacetBucket {
  const FacetBucket({
    required this.key,
    required this.label,
    required this.count,
    this.entityPid,
    this.unknown = false,
    this.letter,
  });

  /// Stable handle to drill this bucket. Empty for [unknown].
  final String key;

  /// Display label. Genre labels are the server's canonical spelling.
  final String label;

  /// Items in this bucket, within the caller's libraries.
  final int count;

  /// The catalog entity behind the bucket, for the dimensions that have
  /// one (`artist`, `album-artist`, `album`).
  final String? entityPid;

  /// True for the bucket holding items the dimension is absent from
  /// (`[Non-Album]` and friends).
  final bool unknown;

  /// The alphabet-rail row this bucket files under, `A`-`Z` or `#`,
  /// computed by the server from the same fold that ordered the page.
  /// Null on the unknown bucket, which has no row, and from a server
  /// older than the field -- derive one from [label] then.
  final String? letter;
}

/// One page of a browse dimension's buckets.
class FacetPage {
  const FacetPage({
    required this.dimension,
    required this.buckets,
    this.nextCursor,
  });

  final String dimension;
  final List<FacetBucket> buckets;

  /// Opaque cursor for the next page; null on the last page.
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
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
    this.appliedBitrateKbps,
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

  /// The bitrate cap the minted stream carries, in kbps: the requested
  /// cap after the server clamps it to the caller's transcode ceiling.
  /// Null when no cap re-encodes the stream (none requested, or the
  /// source already sits inside it).
  final int? appliedBitrateKbps;

  /// Playback window within the served audio, present only when the
  /// url carries the item's whole backing file and the item is a
  /// window into it (direct playback of a carved track): the player
  /// clips to [spanStartMs, spanEndMs). Null when the server cuts.
  final int? spanStartMs;
  final int? spanEndMs;
}

/// One member's place on a minted [QueueTimeline].
///
/// Offsets and durations are in samples at the timeline's envelope
/// rate. Without crossfade members tile exactly; with one, consecutive
/// members overlap, so a position maps by offset and never by summing
/// durations.
class QueueTimelineMember {
  const QueueTimelineMember({
    required this.pid,
    required this.offsetSamples,
    required this.durationSamples,
  });

  final String pid;

  /// Where this member starts on the combined timeline.
  final int offsetSamples;

  /// The member's own length on the timeline.
  final int durationSamples;
}

/// A whole queue rendered as one gapless stream.
///
/// One HLS URL plays every member end to end with sample-exact seams;
/// [members] is what maps a position on it back to the item playing.
/// Timelines are immutable, so editing the queue means minting another.
class QueueTimeline {
  const QueueTimeline({
    required this.url,
    this.pid,
    required this.mimeType,
    required this.durationMs,
    required this.expiresAt,
    required this.envelopeRate,
    required this.members,
    this.crossfadeSeconds,
    this.format,
  });

  /// Identifies this rendering, for releasing it when playback stops;
  /// null from a server that does not offer the release, which leaves
  /// the server's idle sweep as the only way the slot comes back.
  final String? pid;

  /// HLS playlist URL for the whole queue, already resolved against the
  /// client base URL the way [PlayInfo.url] is.
  final String url;

  final String mimeType;

  /// The combined timeline's duration.
  final int durationMs;

  /// When the embedded media token stops being accepted.
  final DateTime expiresAt;

  /// Sample rate the member offsets are measured at.
  final int envelopeRate;

  /// Per-member placement, in queue order.
  final List<QueueTimelineMember> members;

  /// The crossfade the timeline was minted with, when nonzero.
  final double? crossfadeSeconds;

  /// The audio format it was rendered in; null from a server that does
  /// not say.
  final String? format;
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
    this.lastPlayedAt,
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

  /// When a play was last counted; null until one has been. A manual
  /// played mark does not set it, so this reads as the listening record
  /// rather than as the flag's age.
  final DateTime? lastPlayedAt;

  final DateTime? updatedAt;
}

/// The caller's star and rating for one catalog entity (an artist or an
/// album).
///
/// Entities carry no resume position or play count of their own; their
/// items keep those. An entity the caller has never starred or rated
/// reads back as the zero state rather than an error.
class EntityPlayState {
  const EntityPlayState({
    required this.pid,
    required this.starred,
    this.starredAt,
    this.rating,
    this.updatedAt,
  });

  final String pid;
  final bool starred;

  /// When the star was set, which is what orders the starred list; null
  /// when the entity is not starred.
  final DateTime? starredAt;

  /// The caller's rating, 0 to 100; null when unrated.
  final int? rating;

  final DateTime? updatedAt;
}

/// The caller's starred artists and albums, most recently starred first
/// within each group. Independent of item stars: starring an album does
/// not star its tracks.
class StarredEntities {
  const StarredEntities({required this.artists, required this.albums});

  final List<SearchHit> artists;
  final List<SearchHit> albums;
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
    this.skippedMs,
    this.finished = false,
    this.client,
  });

  final String sessionId;
  final String pid;

  /// When playback started, in UTC.
  final DateTime startedAt;

  /// Milliseconds actually heard, excluding pauses and seeks.
  final int msPlayed;

  /// Milliseconds of content the listener did not sit through, for the
  /// server's time-saved counter. The wire field covers both silence
  /// trimming and playback speed above 1x; this client reports trim
  /// savings only (speed accounting needs seek-aware wall-clock
  /// tracking the player does not do yet). Null when nothing was
  /// saved.
  final int? skippedMs;

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
    this.reason,
    this.item,
    this.episode,
    this.show,
  });

  /// `upsert`, `upsert-show`, or `delete`. Entries with an unrecognized
  /// op are dropped.
  final String op;
  final String pid;

  /// Why a delete arrived: `removed` when the catalog no longer holds it
  /// at all, `hidden` when it left this caller's view and could come
  /// back (trash, an unsubscribe, a grant they lost). Null on every
  /// other op, and on a delete from a server too old to say. Treat an
  /// unrecognized value as `hidden`, which is the half that reclaims
  /// nothing.
  final String? reason;
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
    this.durationMs,
  });

  /// Media-token-authenticated download URL, resolved against the
  /// client base URL.
  final String url;
  final String mimeType;
  final int sizeBytes;
  final String fileName;

  /// This file's own duration, null when the catalog does not know it.
  /// A part of a multi-file book reports the part's; a carved item
  /// reports the containing file's, with the span naming its window.
  final int? durationMs;

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

/// A show's funding pointer from its feed's `<podcast:funding>` tag.
class PodcastFunding {
  const PodcastFunding({required this.url, this.message});

  final String url;

  /// Suggested call-to-action label for the link.
  final String? message;
}

/// One person credited in a feed, from a `<podcast:person>` tag at the
/// show or episode level. An absent [role] reads as `host`.
class FeedPerson {
  const FeedPerson({
    required this.name,
    this.role,
    this.group,
    this.img,
    this.href,
  });

  final String name;
  final String? role;
  final String? group;

  /// Portrait image URL, when the feed declares one.
  final String? img;

  /// Profile or information URL, when the feed declares one.
  final String? href;
}

/// One highlight clip of an episode from a `<podcast:soundbite>` tag. An
/// absent [title] reuses the episode title.
class Soundbite {
  const Soundbite({
    required this.startMs,
    required this.durationMs,
    this.title,
  });

  final int startMs;
  final int durationMs;
  final String? title;
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
    this.explicit = false,
    this.funding,
    this.medium,
    this.persons = const [],
    this.artSource,
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

  /// Feed-declared explicit flag for the whole show; episodes carry
  /// their own flag, which wins where the feed sets both.
  final bool explicit;

  /// The show's funding/support pointer, when the feed declares one.
  final PodcastFunding? funding;

  /// The show's declared medium (`podcast`, `music`, `audiobook`, ...),
  /// lowercased. Open set; null when the feed declares none.
  final String? medium;

  /// Show-level person credits. Populated on the detail read only.
  final List<FeedPerson> persons;

  /// Where the show's cover came from - the feed, or a hand-set
  /// replacement. Detail reads only, beside [persons]: a subscription
  /// row draws no caption.
  final ArtSource? artSource;
}

/// Which new episodes auto-download takes, by keyword against the
/// episode title. An empty [include] takes everything; [exclude] wins
/// where both match. Titles only, and future arrivals only: editing a
/// filter never re-evaluates the backlog.
class EpisodeFilter {
  const EpisodeFilter({this.include = const [], this.exclude = const []});

  final List<String> include;
  final List<String> exclude;

  /// True when the filter admits every episode, which is what an unset
  /// one does.
  bool get isEmpty => include.isEmpty && exclude.isEmpty;
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
    this.autoDownloadFilter,
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

  /// Narrows what [autoDownload] takes; null means take everything.
  /// Carried here because the PUT replaces the whole document: a sender
  /// that dropped it would erase a filter set anywhere else.
  final EpisodeFilter? autoDownloadFilter;
}

/// One of the caller's podcast subscriptions.
class Subscription {
  const Subscription({
    required this.show,
    required this.settings,
    required this.subscribedAt,
    this.unplayedCount,
  });

  final PodcastShow show;
  final SubscriptionSettings settings;
  final DateTime subscribedAt;

  /// How many of the show's episodes the caller has not crossed the
  /// played threshold on: the whole backlog, not a window over it, so
  /// a tile can say it. Null from a server that predates the field.
  final int? unplayedCount;
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
    this.hasEnclosure = false,
  });

  /// The show this episode belongs to.
  final String showPid;
  final int? season;
  final int? episodeNumber;

  /// Feed-declared type (`full`, `trailer`, `bonus`); open set, treat
  /// unknown values like `full`.
  final String? episodeType;
  final DateTime publishedAt;

  /// Whether the audio is on the server. Not what decides playability:
  /// an episode that is not downloaded still plays when [hasEnclosure]
  /// is true, relayed from the feed's host. What fetching adds is local
  /// bytes and the analysis riding them, so silence trim, voice boost,
  /// and the skip map need it.
  final bool downloaded;

  /// `queued` or `failed` while a server-side fetch is pending or after
  /// one failed; null otherwise. Open set, treat unknown as `queued`.
  final String? fetchState;
  final String? fetchError;
  final bool explicit;
  final bool hasTranscript;

  /// Whether the feed named audio this server could relay. False with
  /// [downloaded] false is the one episode that cannot play at all, so
  /// read this rather than [downloaded] before offering play.
  final bool hasEnclosure;
}

/// Which episodes a cross-show listing keeps, and with it the order:
/// [latest] and [unplayed] are newest published first, [inProgress] is
/// most recently played first.
enum SubscribedEpisodes {
  latest('latest'),
  unplayed('unplayed'),
  inProgress('in-progress');

  const SubscribedEpisodes(this.wireName);

  /// Value as it appears on the wire.
  final String wireName;
}

/// What a manual feed refresh turned up.
class RefreshResult {
  const RefreshResult({required this.newEpisodes});

  /// Episodes that appeared in this refresh. Zero is the ordinary
  /// answer for a show that has published nothing since the last one.
  final int newEpisodes;
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
    super.hasEnclosure,
    this.descriptionHtml,
    this.link,
    this.chapters = const [],
    this.persons = const [],
    this.soundbites = const [],
  });

  /// Show notes as sanitized HTML (server-side allowlist).
  final String? descriptionHtml;
  final String? link;
  final List<ChapterMark> chapters;

  /// Episode-level person credits, layered on the show's credits.
  final List<FeedPerson> persons;

  /// Highlight clips the feed marks with `<podcast:soundbite>`.
  final List<Soundbite> soundbites;
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

/// One audiobook series: a name the books' tags carry rather than an
/// entity anyone curates, which is why it has a listing but no screen.
class BookSeries {
  const BookSeries({
    required this.pid,
    required this.name,
    this.bookCount = 0,
    this.totalDurationMs = 0,
  });

  final String pid;
  final String name;
  final int bookCount;
  final int totalDurationMs;
}

/// One book's place in a series.
class BookSeriesEntry {
  const BookSeriesEntry({required this.book, this.sequence});

  /// What the book's tags call its place ("2", "1.5", "II"), or null
  /// when they name the series without a number. A string because that
  /// is what a tag holds.
  final String? sequence;

  final ItemSummary book;
}

/// One series and the books in it, in the catalog's sequence order.
class BookSeriesDetail {
  const BookSeriesDetail({
    required this.pid,
    required this.name,
    this.bookCount = 0,
    this.totalDurationMs = 0,
    this.books = const [],
  });

  final String pid;
  final String name;

  /// Catalog-wide counts, answered only to an account that can see
  /// every library; zero otherwise. A restricted account reads
  /// [books].length instead, which is what it can open.
  final int bookCount;
  final int totalDurationMs;

  final List<BookSeriesEntry> books;
}

/// One keyset page of series.
class BookSeriesPage {
  const BookSeriesPage({this.series = const [], this.nextCursor});

  final List<BookSeries> series;
  final String? nextCursor;
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
    this.seriesPid,
    this.seriesSequence,
    this.publisher,
    this.asin,
    this.isbn,
    this.edition,
    this.abridged,
    this.descriptionHtml,
    required this.durationMs,
    this.artUrl,
    this.artSource,
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

  /// The series entity behind [series], so a caller can name it to a
  /// merge. Null when the book belongs to none.
  final String? seriesPid;
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

  /// Where the cover this book answers came from, for the mark under
  /// it. Null when the book has no artwork, or when the answering
  /// image carries no attribution.
  final ArtSource? artSource;
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

/// One place a listener marked in a book, on the book timeline.
///
/// Not the resume point: a book has one of those and any number of
/// these, and nothing here moves as playback does.
class Bookmark {
  const Bookmark({
    required this.id,
    required this.positionMs,
    this.note,
    required this.createdAt,
  });

  final String id;

  /// Book-timeline position, spanning every part.
  final int positionMs;
  final String? note;
  final DateTime createdAt;
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

/// One item's amplitude envelope, for the seek bar to paint.
///
/// The three states are not interchangeable. `ready` carries [peaks];
/// `pending` means the analyze pass has not reached this file, so asking
/// again later may answer differently; `unavailable` is final, and the
/// four populations that get it (podcast episodes, cue-carved tracks,
/// multi-file audiobooks, files the pass could not measure) will never
/// have one. A client draws its plain seek bar for the last of those
/// rather than spinning at it.
class Waveform {
  const Waveform({
    required this.state,
    this.peaks = const [],
    this.resolution,
    this.essenceHash,
  });

  /// `ready`, `pending`, or `unavailable`. An open set: anything else
  /// reads as unavailable.
  final String state;

  /// One amplitude per bucket in playback order, 0 silence and 255 full
  /// scale. Empty unless [ready].
  final List<int> peaks;

  /// How many buckets [peaks] carries, read rather than assumed: the
  /// catalog's 1000 is a constant an analysis-version bump may change.
  final int? resolution;

  final String? essenceHash;

  bool get ready => state == 'ready';

  /// Whether asking again could ever answer differently.
  bool get pending => state == 'pending';
}

/// One item's words, synced or not.
///
/// [synced] and [unsynced] are alternatives rather than both halves of
/// one answer: the contract promises at least one of them is non-empty,
/// and a source that carries timings gives the lines while a plain tag
/// gives the block.
class Lyrics {
  const Lyrics({
    required this.pid,
    required this.source,
    this.provider,
    this.synced = const [],
    this.unsynced,
  });

  final String pid;

  /// Where the words came from: `tag` (the file's own tags), `sidecar`
  /// (an `.lrc` beside the audio), `user`, or `enrichment` (a provider,
  /// named in [provider]). The same vocabulary artwork reports. An open
  /// vocabulary.
  final String source;

  /// The lyrics provider that supplied an `enrichment` copy. Null for
  /// every other source.
  final String? provider;

  /// Time-synced lines, ordered by [SyncedLine.timeMs]. Empty when the
  /// source carried no timings.
  final List<SyncedLine> synced;

  /// The plain block, when there are no synced lines.
  final String? unsynced;

  /// Whether these words can follow playback.
  bool get isSynced => synced.isNotEmpty;
}

/// One time-synced lyric line.
class SyncedLine {
  const SyncedLine({required this.timeMs, required this.text});

  final int timeMs;
  final String text;
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
  const SmartRule({
    required this.root,
    this.sorts = const [],
    this.limit = 0,
    this.limitMode = '',
    this.limitSeed = 0,
  });

  final RuleNode root;
  final List<RuleSort> sorts;
  final int limit;

  /// How [limit] is read: empty or `count` is a plain member cap;
  /// `random`, `minutes`, and `megabytes` are the shuffle and budget
  /// modes.
  final String limitMode;

  /// Pins a `random` or budget draw so the same rule yields the same
  /// members each read; 0 draws a fresh order per read.
  final int limitSeed;
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
    this.artUrl,
  });

  final String pid;

  /// Retired. Rule edits once reissued the pid and set this; edits now
  /// apply in place under a stable pid, so this is always null.
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

  /// The playlist's cover, when it has one: an owner's upload, or the
  /// mosaic the server builds from the members. Null means neither, so
  /// the client draws its own placeholder rather than fetching a 404.
  final String? artUrl;
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

/// A playlist's external source binding: what it follows, how, and how
/// the syncing has been going.
class PlaylistSource {
  const PlaylistSource({
    required this.source,
    this.url,
    this.title,
    required this.live,
    required this.mode,
    this.intervalHours,
    this.refCount,
    required this.disabled,
    required this.consecutiveFailures,
    this.lastError,
    this.lastAttemptAt,
    this.lastSyncedAt,
    this.lastRun,
  });

  /// `youtube` for a live URL binding, else the import source label.
  /// An open string; unknown sources render as opaque labels.
  final String source;

  /// The source playlist's URL (live bindings only).
  final String? url;

  /// The source playlist's own title, as last enumerated (live only).
  final String? title;

  /// True when the server re-fetches the source on the stored interval
  /// and downloads new entries; false for a matched export, which
  /// reconciles match-only and on demand.
  final bool live;

  /// `append`, `mirror`, or `mirror-trash`.
  final String mode;

  /// Hours between scheduled runs (live bindings only).
  final int? intervalHours;

  /// Portable refs the binding stores (matched bindings only).
  final int? refCount;

  /// True when repeated failures suspended the schedule; a successful
  /// manual sync re-enables it.
  final bool disabled;
  final int consecutiveFailures;
  final String? lastError;
  final DateTime? lastAttemptAt;
  final DateTime? lastSyncedAt;

  /// The last completed run's counts; null before the first success.
  final PlaylistSyncCounts? lastRun;
}

/// One completed sync run's counts.
class PlaylistSyncCounts {
  const PlaylistSyncCounts({
    required this.added,
    required this.removed,
    required this.trashed,
    required this.queued,
    required this.unavailable,
    required this.missing,
  });

  final int added;
  final int removed;
  final int trashed;
  final int queued;
  final int unavailable;
  final int missing;
}

/// What a sync would do right now, computed by the same reconciler
/// without writing anything.
class PlaylistSyncPreview {
  const PlaylistSyncPreview({
    required this.entries,
    required this.wouldAdd,
    required this.wouldDownload,
    required this.wouldRemove,
    required this.wouldTrash,
    required this.pending,
    required this.unavailable,
    required this.missing,
    this.misses = const [],
  });

  final int entries;
  final int wouldAdd;
  final int wouldDownload;
  final int wouldRemove;
  final int wouldTrash;
  final int pending;
  final int unavailable;
  final int missing;

  /// The unmatched refs themselves, matched bindings only.
  final List<PlaylistImportMiss> misses;
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

/// One podcast directory match, ready to subscribe to.
///
/// [feedUrl] is the whole point of a match: it is what a subscribe
/// request takes, which is why a directory result needs no source kind
/// to be chosen for it. [artworkUrl] is the directory's own URL, drawn
/// directly, because a show has no pid to address cover art by until it
/// is subscribed to.
class PodcastDirectoryEntry {
  const PodcastDirectoryEntry({
    required this.name,
    required this.feedUrl,
    this.author,
    this.artworkUrl,
    this.genre,
    this.episodeCount,
  });

  final String name;
  final String feedUrl;
  final String? author;
  final String? artworkUrl;
  final String? genre;
  final int? episodeCount;
}

/// A resolved, tokenized station stream, absolute against the client
/// base URL.
class RadioPlayInfo {
  const RadioPlayInfo({
    required this.url,
    this.nowPlaying,
    this.nowPlayingItemPid,
    this.nowPlayingArtKey,
    this.nowPlayingArtSource,
    this.nowPlayingSaved = false,
    this.nowPlayingSavedPid,
  });

  final String url;

  /// The station's current in-stream title, present only while a
  /// proxied listener has the stream open. Poll play-info while
  /// playing to keep it fresh; keep the open stream and ignore the
  /// fresh url.
  final String? nowPlaying;

  /// A library track the server matched [nowPlaying] to, when it
  /// recognised one, so a full-screen player can draw the song's own
  /// cover. Absent is the common case and not a failure: fall back to
  /// the station's artwork rather than showing a gap.
  final String? nowPlayingItemPid;

  /// The token naming the external cover the server holds for
  /// [nowPlaying], null when it holds none. The second artwork rung; it
  /// both says there is an image and makes its URL change with the
  /// announced title. Null until the asynchronous lookup behind it lands
  /// - so it appears on a later poll rather than on the one that started
  /// it - and null forever while the operator has the rung switched off.
  final String? nowPlayingArtKey;

  /// Which rung answered for [nowPlayingArtKey]: the station's own
  /// stream, or the provider a lookup asked. It is what lets a face
  /// caption the picture rather than presenting a third party's cover as
  /// the station's own.
  final ArtSource? nowPlayingArtSource;

  /// Whether the caller has already kept what the station is announcing,
  /// so the heart draws filled. Riding the poll is what keeps it honest
  /// across devices: a save made on the phone fills the desktop's heart
  /// within one poll, and a rollover empties it.
  final bool nowPlayingSaved;

  /// The saved song's pid, present exactly when [nowPlayingSaved] is
  /// true, so an untap needs no list fetch first.
  final String? nowPlayingSavedPid;
}

/// One song a listener kept off the air.
///
/// Deliberately not a library item: nothing here plays, and the rows
/// exist to be hunted down and crossed off. [inLibraryPid] is the
/// crossing-off - a read-time match against the caller's own library,
/// never stored, so a row saved before an album arrived marks itself the
/// day it does.
class RadioSavedSong {
  const RadioSavedSong({
    required this.pid,
    required this.nowPlaying,
    required this.stationName,
    required this.heardAt,
    required this.hasArt,
    this.artist,
    this.title,
    this.stationPid,
    this.inLibraryPid,
  });

  final String pid;

  /// The announcement as the station sent it. Plain display text from an
  /// untrusted host, and what a row draws when nothing parsed out of it.
  final String nowPlaying;

  /// The artist and song where the announced line split into them.
  /// Absent is ordinary: stations announce in every shape there is.
  ///
  /// There is deliberately no album. ICY metadata is one line, so a row
  /// naming an album would be guessing.
  final String? artist;
  final String? title;

  /// The station it was heard on, absent once that station is gone from
  /// the library - the row outlives it, because what was kept is the
  /// song. [stationName] is the snapshot and is always there.
  final String? stationPid;
  final String stationName;

  final DateTime heardAt;

  /// A library track the server matched this row to, resolved at read
  /// time. Present means the hunt is over; the match is best-effort text
  /// and is a marker rather than a playable handle.
  final String? inLibraryPid;

  /// Whether a cover was snapshotted with this row, and so whether the
  /// art endpoint has bytes. False is ordinary - draw a monogram.
  final bool hasArt;
}

/// One keyset page of saved songs, newest first.
class RadioSavedSongPage {
  const RadioSavedSongPage({required this.songs, this.nextCursor});

  final List<RadioSavedSong> songs;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
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

/// One notification event the server can emit: catalog entry for the
/// per-target event checklist.
class NotifyEvent {
  const NotifyEvent({
    required this.name,
    required this.scope,
    required this.description,
  });

  final String name;

  /// `server` (operations events, admin surfaces) or `user`.
  final String scope;
  final String description;
}

/// One notification delivery destination. [config] is the kind's
/// free-form configuration document, returned verbatim to the owner
/// so it round-trips through the editor; the server seals it at rest.
class NotificationTarget {
  const NotificationTarget({
    required this.pid,
    required this.kind,
    required this.scope,
    required this.config,
    required this.enabledEvents,
    required this.createdAt,
    this.label,
    this.muted = false,
    this.minIntervalSeconds = 0,
    this.lastSuccessAt,
    this.lastError,
    this.lastErrorAt,
  });

  final String pid;

  /// `pushover`, `ntfy`, `gotify`, `discord`, `webhook`, `apprise`,
  /// or `unifiedpush`; fixed at creation.
  final String kind;

  /// `server` (administrator-managed) or `user` (personal).
  final String scope;
  final String? label;
  final Map<String, Object?> config;
  final List<String> enabledEvents;

  /// A pause that keeps the configuration and the event selection:
  /// nothing but a per-target test is delivered while it is set.
  final bool muted;

  /// The shortest gap between two deliveries, in seconds; 0 paces
  /// nothing. A delivery inside the gap waits rather than failing, and
  /// a per-target test is exempt.
  final int minIntervalSeconds;

  final DateTime createdAt;

  /// Delivery health: the last successful delivery, and the standing
  /// error while the target is unhealthy (cleared by the next
  /// success).
  final DateTime? lastSuccessAt;
  final String? lastError;
  final DateTime? lastErrorAt;
}

/// One thing that happened to this account, as the server kept it.
///
/// [event] is the catalog event name and is the boundary: a client that
/// knows it words the row itself and stays localized, and [title] and
/// [body] are the server's own English for one it does not.
class ServerNotification {
  const ServerNotification({
    required this.id,
    required this.event,
    required this.title,
    required this.body,
    required this.createdAt,
    this.targetPid,
    this.readAt,
  });

  final String id;
  final String event;
  final String title;
  final String body;

  /// What the row is about, where the event names something: a show, an
  /// episode, a playlist, a review entry.
  final String? targetPid;

  final DateTime createdAt;

  /// When the row was marked read; null while unread.
  final DateTime? readAt;

  bool get read => readAt != null;
}

/// One page of the notification inbox.
class ServerNotificationPage {
  const ServerNotificationPage({
    required this.notifications,
    required this.unreadCount,
    this.nextCursor,
  });

  final List<ServerNotification> notifications;

  /// Unread rows in the whole inbox, not just this page: the badge.
  final int unreadCount;

  final String? nextCursor;

  bool get hasMore => nextCursor != null;
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

/// One controllable playback output: a registered client, a cast
/// device, a DLNA renderer, or the server's own audio output.
class PlayerEndpoint {
  const PlayerEndpoint({
    required this.id,
    required this.kind,
    required this.name,
    required this.online,
    required this.shared,
    required this.mine,
    required this.volumeControl,
    required this.rateControl,
    this.activeSessionId,
  });

  final String id;

  /// `client`, `cast`, `dlna`, or `jukebox`; open vocabulary.
  final String kind;
  final String name;
  final bool online;
  final bool shared;
  final bool mine;
  final bool volumeControl;
  final bool rateControl;
  final String? activeSessionId;
}

/// One candidate advertise base a cast device would fetch media from,
/// with the server's own verdict on reaching itself through it.
class CastPreflightBase {
  const CastPreflightBase({
    required this.base,
    required this.source,
    required this.reachable,
    required this.notes,
    this.device,
  });

  final String base;

  /// `configured` (the public base), `detected` (the auto-detected LAN
  /// address), or `loopback` (the server's own interface); open
  /// vocabulary.
  final String source;

  /// Whether the server could fetch its own health endpoint through this
  /// base. Unreachable predicts a cast failure; reachable does not
  /// promise the device agrees, because it is not on the server's side of
  /// the network.
  final bool reachable;

  /// Plain-language observations: scheme and certificate caveats, name
  /// resolution warnings, why a base is likely or unlikely to work.
  final List<String> notes;

  /// What a real device made of this base. Null on the server-side
  /// check, which has no device to ask.
  final CastDeviceVerdict? device;
}

/// One device's trial run against one advertise base.
class CastDeviceVerdict {
  const CastDeviceVerdict({
    required this.verdict,
    required this.latencyMs,
    this.detail,
  });

  /// `played`, `failed`, or `timeout`; open vocabulary.
  final String verdict;

  /// Milliseconds from handing the device the URL to its answer.
  final int latencyMs;

  /// What the device or the protocol said, where there was anything to
  /// quote.
  final String? detail;
}

/// A device probe's answer: an endpoint, and one row per candidate base
/// carrying both the server's reachability verdict and the device's.
class CastDeviceProbe {
  const CastDeviceProbe({
    required this.endpointId,
    required this.name,
    required this.kind,
    required this.bases,
  });

  final String endpointId;
  final String name;

  /// `cast` or `dlna`; open vocabulary.
  final String kind;
  final List<CastPreflightBase> bases;
}

/// One queue entry of a playback session, hydrated for display.
class PlaybackSessionEntry {
  const PlaybackSessionEntry({
    required this.pid,
    required this.title,
    this.artist,
    this.durationMs,
  });

  final String pid;
  final String title;
  final String? artist;
  final int? durationMs;

  factory PlaybackSessionEntry.fromWire(Map<String, dynamic> json) {
    return PlaybackSessionEntry(
      pid: json['pid'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String?,
      durationMs: (json['durationMs'] as num?)?.toInt(),
    );
  }
}

/// One playback session: a queue playing (or paused) on an endpoint.
/// Position is a snapshot: positionMs was true at positionAt; while
/// playing, render by extrapolating forward with rate against the
/// server clock offset.
class PlaybackSessionInfo {
  const PlaybackSessionInfo({
    required this.id,
    required this.endpointId,
    required this.mine,
    required this.authority,
    required this.playing,
    required this.index,
    required this.positionMs,
    required this.positionAt,
    required this.rate,
    required this.queueVersion,
    required this.entries,
    this.endpointName,
    this.ownerName,
    this.volume,
    this.repeat,
    this.shuffle = false,
    this.ended = false,
    this.updatedAt,
  });

  final String id;
  final String endpointId;
  final String? endpointName;
  final bool mine;
  final String? ownerName;

  /// `remote` or `mirror`; open vocabulary.
  final String authority;
  final bool playing;
  final int index;
  final int positionMs;
  final DateTime positionAt;
  final double rate;
  final double? volume;
  final String? repeat;
  final bool shuffle;
  final int queueVersion;

  /// Empty when a WebSocket frame omitted the unchanged queue.
  final List<PlaybackSessionEntry> entries;
  final bool ended;
  final DateTime? updatedAt;

  /// Decodes a WebSocket `session` frame payload (frames do not pass
  /// through the generated client).
  factory PlaybackSessionInfo.fromWire(Map<String, dynamic> json) {
    final entries = (json['entries'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PlaybackSessionEntry.fromWire)
        .toList(growable: false);
    return PlaybackSessionInfo(
      id: json['id'] as String? ?? '',
      endpointId: json['endpointId'] as String? ?? '',
      endpointName: json['endpointName'] as String?,
      mine: json['mine'] as bool? ?? false,
      ownerName: json['ownerName'] as String?,
      authority: json['authority'] as String? ?? 'remote',
      playing: json['playing'] as bool? ?? false,
      index: (json['index'] as num?)?.toInt() ?? 0,
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      positionAt:
          DateTime.tryParse(json['positionAt'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      rate: (json['rate'] as num?)?.toDouble() ?? 1.0,
      volume: (json['volume'] as num?)?.toDouble(),
      repeat: json['repeat'] as String?,
      shuffle: json['shuffle'] as bool? ?? false,
      queueVersion: (json['queueVersion'] as num?)?.toInt() ?? 0,
      entries: entries,
      ended: json['ended'] as bool? ?? false,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  /// The current entry, when the queue is known.
  PlaybackSessionEntry? get currentEntry =>
      index >= 0 && index < entries.length ? entries[index] : null;
}

/// One session that has stopped, as the state it stopped in.
///
/// Deliberately not a [PlaybackSessionInfo] carrying a flag: this has no
/// live half. Nothing extrapolates, the position is final, and there is
/// nothing to control - putting it back means starting a new session
/// from this queue, this index, and this position.
class PlaybackSessionHistoryEntry {
  const PlaybackSessionHistoryEntry({
    required this.id,
    required this.endpointId,
    required this.authority,
    required this.index,
    required this.positionMs,
    required this.positionAt,
    required this.rate,
    required this.entries,
    this.endpointName,
    this.repeat,
    this.shuffle = false,
  });

  /// The session's pid. It names a session that no longer exists; it is
  /// here to correlate with what was seen live, and to remember which
  /// offer a listener has already turned down.
  final String id;

  final String endpointId;

  /// Absent for an endpoint that has since gone away, which a client
  /// endpoint does on every sign-out.
  final String? endpointName;

  /// `remote` or `mirror`; open vocabulary.
  final String authority;

  final int index;
  final int positionMs;

  /// When the position was true. The list is newest first by this.
  final DateTime positionAt;

  final double rate;
  final String? repeat;
  final bool shuffle;

  /// The queue as it stood, in play order.
  final List<PlaybackSessionEntry> entries;

  PlaybackSessionEntry? get currentEntry =>
      index >= 0 && index < entries.length ? entries[index] : null;
}

/// Compact view of a review entry's best-scoring candidate.
class CandidateSummary {
  const CandidateSummary({
    required this.mbid,
    required this.title,
    required this.artist,
    this.year,
    required this.similarityPct,
  });

  final String mbid;
  final String title;
  final String artist;
  final int? year;

  /// Similarity in percent, 0 to 100.
  final double similarityPct;
}

/// One unit of work in the metadata review queue (usually an album).
class ReviewEntry {
  const ReviewEntry({
    required this.id,
    required this.kind,
    required this.status,
    required this.mediaType,
    required this.origin,
    this.title,
    this.artist,
    required this.trackCount,
    this.libraryPid,
    this.uploadedBy,
    this.identifying = false,
    this.best,
    this.appliedMbid,
    required this.createdAt,
    this.decidedAt,
    this.decidedBy,
  });

  final String id;

  /// `match` or `import`; open vocabulary.
  final String kind;

  /// Lifecycle state: `pending`, `applied`, `auto-applied`, `as-is`,
  /// `unofficial`, `skipped`, `discarded`, or `reverted`. Open
  /// vocabulary.
  final String status;
  final MediaType mediaType;

  /// Where the unit came from: `scan`, `upload`, or `rematch`. Open
  /// vocabulary.
  final String origin;
  final String? title;
  final String? artist;
  final int trackCount;
  final String? libraryPid;
  final String? uploadedBy;

  /// True while candidate lookup is still running for this entry.
  final bool identifying;

  /// The best-scoring candidate, when lookup produced any.
  final CandidateSummary? best;

  /// The release the decision applied, once decided.
  final String? appliedMbid;
  final DateTime createdAt;
  final DateTime? decidedAt;
  final String? decidedBy;
}

/// Full review entry detail: the local tracks plus every candidate.
class ReviewEntryDetail extends ReviewEntry {
  const ReviewEntryDetail({
    required super.id,
    required super.kind,
    required super.status,
    required super.mediaType,
    required super.origin,
    super.title,
    super.artist,
    required super.trackCount,
    super.libraryPid,
    super.uploadedBy,
    super.identifying,
    super.best,
    super.appliedMbid,
    required super.createdAt,
    super.decidedAt,
    super.decidedBy,
    this.candidates = const [],
    this.tracks = const [],
    this.identifyDeclined = false,
    this.identifyOverride,
    this.suggested,
  });

  final List<ReviewCandidate> candidates;
  final List<ReviewTrack> tracks;

  /// The submission asked not to be identified, so the entry never
  /// entered the match queue. What it tells a reader is why
  /// [candidates] is empty: nothing was searched.
  final bool identifyDeclined;

  /// What the last re-identify searched for in place of the files' own
  /// tags. Null when nothing was typed. [tracks] always reports the
  /// tags the files carry, never this.
  ///
  /// Not named `override`: the word shadows Dart's own annotation for
  /// any member declared after it, which is the same reason the wire
  /// field is spelled this way.
  final ReviewOverride? identifyOverride;

  /// What the matching parse read out of a loose acquisition's source
  /// title, offered as a starting point for a search rather than as a
  /// claim about the files. Null on anything else.
  /// [identifyOverride] supersedes it.
  final ReviewOverride? suggested;
}

/// Values searched for in place of what an entry's files claim.
class ReviewOverride {
  const ReviewOverride({this.artist, this.album, this.title});

  final String? artist;
  final String? album;
  final String? title;
}

/// One keyset-paginated page of review entries.
class ReviewEntryPage {
  const ReviewEntryPage({required this.entries, this.nextCursor});

  final List<ReviewEntry> entries;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// One local track inside a review entry.
class ReviewTrack {
  const ReviewTrack({
    this.pid,
    required this.path,
    required this.title,
    this.artist,
    this.trackNo,
    this.discNo,
    required this.durationMs,
  });

  /// Item pid, present once the track is cataloged.
  final String? pid;
  final String path;
  final String title;
  final String? artist;
  final int? trackNo;
  final int? discNo;
  final int durationMs;
}

/// One release candidate for a review entry.
class ReviewCandidate {
  const ReviewCandidate({
    required this.mbid,
    this.releaseGroupMbid,
    required this.title,
    required this.artist,
    this.year,
    this.mediaCount,
    this.trackCount,
    this.country,
    this.label,
    this.catalogNumber,
    this.compilation,
    required this.similarityPct,
    this.components = const [],
    this.pairings = const [],
    this.missingTitles = const [],
    this.extraTrackIndexes = const [],
  });

  final String mbid;
  final String? releaseGroupMbid;
  final String title;
  final String artist;
  final int? year;
  final int? mediaCount;
  final int? trackCount;
  final String? country;
  final String? label;
  final String? catalogNumber;
  final bool? compilation;

  /// Similarity in percent, 0 to 100.
  final double similarityPct;

  /// Per-field distance breakdown behind the similarity score.
  final List<CandidateComponent> components;

  /// Local-track-to-candidate-track pairings.
  final List<CandidatePairing> pairings;

  /// Candidate tracks with no local counterpart.
  final List<String> missingTitles;

  /// Local track indexes with no candidate counterpart.
  final List<int> extraTrackIndexes;
}

/// One component of a candidate's similarity score.
class CandidateComponent {
  const CandidateComponent({
    required this.name,
    required this.distance,
    required this.weight,
  });

  /// The field or penalty: `artist`, `album`, `year`, `tracks`,
  /// `missing`, `extra`. Open vocabulary.
  final String name;

  /// Distance in 0 to 1, where 0 is identical.
  final double distance;
  final double weight;
}

/// One pairing of a local track with a candidate track.
class CandidatePairing {
  const CandidatePairing({
    required this.trackIndex,
    required this.position,
    this.disc,
    required this.title,
    this.artist,
    this.durationMs,
    this.recordingMbid,
    required this.distance,
  });

  /// Index into the entry's local track list.
  final int trackIndex;

  /// The paired candidate track's position on its disc.
  final int position;
  final int? disc;
  final String title;
  final String? artist;
  final int? durationMs;
  final String? recordingMbid;

  /// Pairing distance in 0 to 1, where 0 is identical.
  final double distance;
}

/// Review queue counters by lifecycle state.
class ReviewStats {
  const ReviewStats({
    required this.pending,
    this.identifying = 0,
    required this.applied,
    required this.autoApplied,
    this.asIs = 0,
    this.unofficial = 0,
    this.skipped = 0,
    required this.reverted,
    required this.revertedAutoApplied,
  });

  final int pending;
  final int identifying;
  final int applied;
  final int autoApplied;
  final int asIs;
  final int unofficial;
  final int skipped;
  final int reverted;
  final int revertedAutoApplied;
}

/// A library's automatic matching behavior. The PUT replaces the whole
/// object, so writes always carry both fields.
class LibraryMatching {
  const LibraryMatching({required this.mode, this.singlesAutoApply = false});

  /// `auto`, `review`, or `off`; open vocabulary (a mode a newer server
  /// invents draws as itself, never sends back).
  final String mode;

  /// Whether a confident one-file unit may apply itself under `auto`.
  final bool singlesAutoApply;

  /// Field-wise replacement, the shape every setter goes through so a
  /// third field cannot be forgotten by one of them: an omission on a
  /// full-replace PUT silently resets that field on the server.
  LibraryMatching copyWith({String? mode, bool? singlesAutoApply}) =>
      LibraryMatching(
        mode: mode ?? this.mode,
        singlesAutoApply: singlesAutoApply ?? this.singlesAutoApply,
      );
}

/// Outcome of deciding one review entry.
class ReviewDecideResult {
  const ReviewDecideResult({required this.entry, this.warnings = const []});

  final ReviewEntry entry;
  final List<String> warnings;
}

/// Per-entry outcome of a bulk review decision.
class ReviewBulkOutcome {
  const ReviewBulkOutcome({
    required this.entryId,
    required this.ok,
    this.error,
  });

  final String entryId;
  final bool ok;
  final String? error;
}

/// An existing item the uploaded file appears to duplicate.
class DuplicateWarning {
  const DuplicateWarning({
    required this.itemPid,
    required this.kind,
    this.title,
    this.artist,
  });

  final String itemPid;

  /// Evidence level: `content` (byte-identical audio) or `fingerprint`
  /// (acoustically the same recording). Open vocabulary.
  final String kind;
  final String? title;
  final String? artist;
}

/// One resumable upload session.
class UploadSession {
  const UploadSession({
    required this.id,
    required this.fileName,
    required this.sizeBytes,
    required this.receivedBytes,
    required this.mediaType,
    this.libraryPid,
    this.batchId,
    required this.state,
    this.reviewEntryId,
    this.duplicate,
    this.uploadedBy,
    required this.createdAt,
    this.expiresAt,
  });

  final String id;
  final String fileName;
  final int sizeBytes;
  final int receivedBytes;
  final MediaType mediaType;
  final String? libraryPid;

  /// The upload batch the session joined, if any.
  final String? batchId;

  /// Session state: `receiving`, `staged`, `imported`, or `discarded`.
  /// Open vocabulary.
  final String state;

  /// The review entry the file landed in: at completion for a solo
  /// session, at batch finalize for a member.
  final String? reviewEntryId;
  final DuplicateWarning? duplicate;
  final String? uploadedBy;
  final DateTime createdAt;
  final DateTime? expiresAt;
}

/// How an upload batch's files reach the review queue.
enum UploadGrouping {
  /// Cluster into album units by tags and relative paths.
  auto('auto'),

  /// One multi-file review entry over every member.
  album('album'),

  /// One review entry per file.
  tracks('tracks');

  const UploadGrouping(this.wireName);

  /// Value as it appears on the wire.
  final String wireName;
}

/// One upload batch: several sessions grouped into review units by a
/// declared intent.
class UploadBatch {
  const UploadBatch({
    required this.id,
    required this.grouping,
    required this.mediaType,
    this.libraryPid,
    required this.state,
    this.reviewEntryIds = const [],
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final UploadGrouping grouping;
  final MediaType mediaType;
  final String? libraryPid;

  /// Batch state: `open`, `finalized`, or `expired`. Open vocabulary.
  final String state;

  /// The review entries finalization opened; empty while open.
  final List<String> reviewEntryIds;
  final DateTime createdAt;
  final DateTime expiresAt;
}

/// The caller's upload allowance: bytes of live sessions against the
/// account cap.
class UploadQuota {
  const UploadQuota({required this.bytesInUse, this.quotaBytes});

  final int bytesInUse;

  /// The cap on [bytesInUse]; null means no per-user cap.
  final int? quotaBytes;
}

/// One keyset-paginated page of upload sessions.
class UploadPage {
  const UploadPage({required this.uploads, this.nextCursor, this.quota});

  final List<UploadSession> uploads;
  final String? nextCursor;

  /// The caller's own allowance snapshot; null when unknown.
  final UploadQuota? quota;

  bool get hasMore => nextCursor != null;
}

/// One editable field and whether edits can write back to files.
class EditableField {
  const EditableField({required this.name, required this.writeBack});

  final String name;
  final bool writeBack;
}

/// The editable field vocabulary for one media kind.
class KindFields {
  const KindFields({
    required this.kind,
    required this.fields,
    this.creditRoles = const [],
  });

  final MediaType kind;
  final List<EditableField> fields;
  final List<EditableField> creditRoles;
}

/// The editable field vocabulary for one entity type.
class EntityTypeFields {
  const EntityTypeFields({required this.entityType, required this.fields});

  final String entityType;
  final List<EditableField> fields;
}

/// The metadata editor vocabulary: per-kind item fields plus per-type
/// entity fields.
class MetadataFields {
  const MetadataFields({
    required this.kinds,
    required this.entityTypes,
    this.reservedTagKeys = const [],
  });

  final List<KindFields> kinds;
  final List<EntityTypeFields> entityTypes;

  /// Custom-tag keys the catalog owns through a field of its own, so a
  /// tag editor can refuse one before the round trip. The server
  /// refuses them either way.
  final List<String> reservedTagKeys;
}

/// Where one metadata field's current value came from.
class FieldProvenance {
  const FieldProvenance({
    required this.field,
    required this.source,
    this.provider,
    this.sourceUrl,
    required this.locked,
    this.updatedAt,
  });

  /// The field, or `art` / `lyrics` for an artifact row.
  final String field;

  /// `tag`, `sidecar`, `user`, `enrichment`, `organize`, or `feed`.
  /// Open vocabulary.
  final String source;

  /// The provider name when [source] is `enrichment`.
  final String? provider;

  /// Where a fetched value's bytes came from, on the rows that have one.
  final String? sourceUrl;

  final bool locked;
  final DateTime? updatedAt;

  /// Whether this row describes an artifact (a cover, a lyrics sheet)
  /// rather than a scalar field. An artifact row carries no value,
  /// because the value is bytes, and appears whenever the item holds
  /// one - so a non-empty provenance list does not mean the item was
  /// curated.
  bool get isArtifact => field == 'art' || field == 'lyrics';
}

/// One credited role with its names, ordered as stored.
class Credit {
  const Credit({required this.role, required this.names});

  final String role;
  final List<String> names;
}

/// Whether an item has lyrics and where they came from.
class LyricsState {
  const LyricsState({
    required this.synced,
    required this.source,
    this.provider,
    this.lrc,
  });

  final bool synced;

  /// `tag`, `sidecar`, `user`, or `enrichment` - the same vocabulary
  /// artwork reports. Open vocabulary.
  final String source;

  /// The lyrics provider that supplied an `enrichment` copy.
  final String? provider;

  /// The stored LRC text, when synced.
  final String? lrc;
}

/// One custom tag key with its values.
class CustomTag {
  const CustomTag({required this.key, required this.values});

  final String key;
  final List<String> values;
}

/// One standing write-back limitation on a backing file.
class WriteBackIssue {
  const WriteBackIssue({
    required this.filePid,
    required this.code,
    this.tagKey,
    this.detail,
  });

  final String filePid;

  /// Stable machine-readable code. Open vocabulary.
  final String code;
  final String? tagKey;
  final String? detail;
}

/// One artwork slot an item, album, or artist holds at its own level.
class ArtRoleInfo {
  const ArtRoleInfo({
    required this.role,
    this.format,
    this.width,
    this.height,
    this.source,
    this.provider,
    this.sourceUrl,
    this.updatedAt,
    this.locked = false,
  });

  /// The slot: `front`, `back`, `disc`, `booklet`, or `background`.
  final String role;

  /// The stored image format (`jpeg`, `png`, `webp`, `gif`), when known.
  /// Absent when the slot holds no image, which happens only on a
  /// pinned-and-cleared `front`.
  final String? format;

  /// Pixel width, when the image decoded.
  final int? width;

  /// Pixel height, when the image decoded.
  final int? height;

  /// Where this slot's image came from: `tag`, `sidecar`, `user`,
  /// `enrichment`, or `feed`. Open vocabulary.
  final String? source;

  /// The provider that supplied an `enrichment` cover.
  final String? provider;

  /// Where a fetched cover's bytes came from.
  final String? sourceUrl;

  final DateTime? updatedAt;

  /// Whether the front cover is pinned against enrichment and scan
  /// re-derives. False on every other role.
  final bool locked;

  /// A pin with nothing behind it: the cover was cleared and the pin
  /// left standing, which says "do not refill this" rather than "no
  /// cover yet". It is the one artwork state nothing else surfaces.
  bool get pinnedEmpty => locked && (format ?? '').isEmpty;
}

/// Where a picture came from, for a surface drawing it large enough to
/// carry a caption.
class ArtSource {
  const ArtSource({
    required this.source,
    this.provider,
    this.sourceUrl,
    this.level,
    this.derived = false,
    this.updatedAt,
  });

  /// The producer: `tag`, `sidecar`, `user`, `enrichment`, or `feed`.
  /// Open vocabulary; an unrecognized value draws no mark.
  final String source;

  /// The provider that supplied an `enrichment` cover (`deezer`,
  /// `coverartarchive`, `fanarttv`).
  final String? provider;

  /// Where the bytes were fetched from, for a cover that came off the
  /// network.
  final String? sourceUrl;

  /// Which rung of the fallback chain answered (`track`, `album`, ...).
  final String? level;

  /// Whether the answering level borrowed a member's picture rather
  /// than holding one of its own - an album showing one of its tracks'
  /// covers. [source] is that member's.
  final bool derived;

  final DateTime? updatedAt;
}

/// An entity's own artwork slots, plus where the cover a front-cover
/// read would answer with came from.
class ArtRoles {
  const ArtRoles({required this.roles, this.artSource});

  final List<ArtRoleInfo> roles;

  /// The resolved cover's provenance, which for an entity holding none
  /// of its own is the rung it inherits from. Null when nothing is
  /// attributed, which reads as "draw no mark".
  final ArtSource? artSource;
}

/// The caller's permissions on one item: the metadata read's
/// `mayCurate` answer without the cost of the full editor document.
class ItemPermissions {
  const ItemPermissions({required this.mayCurate});

  /// Whether the caller may run the item-scoped metadata mutations:
  /// administrators always, everyone else exactly for the items their
  /// own uploads brought in.
  final bool mayCurate;
}

/// Everything the metadata editor shows for one item.
class ItemMetadata {
  const ItemMetadata({
    required this.pid,
    required this.mediaType,
    required this.fields,
    this.lockedFields = const [],
    this.provenance = const [],
    this.credits = const [],
    this.lyrics,
    this.chapters = const [],
    this.customTags = const [],
    this.unofficial = false,
    this.virtualTrack = false,
    this.hasArtwork = false,
    this.hasOwnArtwork = false,
    this.albumPid,
    this.artistPid,
    this.releaseGroupPid,
    this.writeBackIssues = const [],
    this.mayCurate,
    this.acquisition,
  });

  final String pid;
  final MediaType mediaType;
  final Map<String, String> fields;
  final List<String> lockedFields;
  final List<FieldProvenance> provenance;
  final List<Credit> credits;
  final LyricsState? lyrics;
  final List<ChapterMark> chapters;
  final List<CustomTag> customTags;
  final bool unofficial;

  /// True for tracks carved out of a larger file (CUE-backed), which
  /// never write back.
  final bool virtualTrack;

  /// Whether the item resolves any front cover, including one inherited
  /// from its album, release group, or artist.
  final bool hasArtwork;

  /// Whether the item holds its own front cover rather than inheriting one
  /// from the entity chain.
  final bool hasOwnArtwork;
  final String? albumPid;
  final String? artistPid;
  final String? releaseGroupPid;
  final List<WriteBackIssue> writeBackIssues;

  /// Whether this account may edit any of it. The read is open to
  /// everyone who can see the item and the edits are not, so a screen
  /// that offered Save on the strength of the read alone would offer it
  /// to callers every save refuses.
  ///
  /// Null is "the server did not say" - one too old to carry the field,
  /// or one whose ownership lookup failed - and it is a third answer
  /// rather than a no. Withholding a door on it costs nothing, since
  /// that server refuses the edit anyway; *refusing* on it would put a
  /// curator in front of a refusal screen for an item their next save
  /// would be given.
  final bool? mayCurate;

  /// How the item entered the library, when the catalog recorded it.
  /// Read-only evidence rather than a field: nothing in the edit
  /// surface writes it. Null on an older server as well as on an item
  /// with no origin row, which read the same to a caption.
  final ItemAcquisition? acquisition;
}

/// One item's recorded origin.
class ItemAcquisition {
  const ItemAcquisition({
    required this.sourceType,
    this.sourceUrl,
    this.sourceId,
    this.provider,
    this.acquiredAt,
    this.locked = false,
  });

  /// `local`, `rss`, `youtube`, `manual`, or whatever an acquisition
  /// provider stamped. Open set.
  final String sourceType;

  /// Where it came from, already redacted by the server: http(s) only,
  /// with userinfo and query gone. Null when the stored origin was not
  /// a shareable web address, which is not the same as unknown.
  final String? sourceUrl;

  /// The origin's identifier in the provider's namespace - a feed's
  /// guid, a video id. Unredacted, unlike [sourceUrl]: an id carries no
  /// credentials.
  final String? sourceId;

  final String? provider;

  /// When the catalog recorded the acquisition. Null where it holds no
  /// time, which is better said by absence than by a date at the start
  /// of the era.
  final DateTime? acquiredAt;

  /// Whether the origin is held against automatic rewrites - an import
  /// re-recording over it, a scan re-deriving it from tags still in the
  /// file. A correction sets it by default.
  final bool locked;
}

/// One file a write-back could not update.
class WriteBackFailure {
  const WriteBackFailure({
    required this.filePid,
    this.path,
    required this.reason,
  });

  final String filePid;
  final String? path;
  final String reason;
}

/// Outcome of one metadata edit.
class MetadataEditResult {
  const MetadataEditResult({
    required this.applied,
    this.writeBackFailures = const [],
    this.warnings = const [],
    this.mergedInto,
    this.movedAlbums = const [],
  });

  final bool applied;
  final List<WriteBackFailure> writeBackFailures;
  final List<String> warnings;

  /// The surviving entity when the edit re-keyed this one onto a key
  /// another entity already held, which only an `mbid` clear does. The
  /// edited pid is gone; a screen sitting on it follows this one.
  final String? mergedInto;

  /// Albums that left the edited release group because the clear
  /// re-keyed it and their titles put them in a group of their own.
  final List<String> movedAlbums;
}

/// Where a detached track came from and where it landed.
class DetachResult {
  const DetachResult({
    required this.itemPid,
    required this.oldAlbumPid,
    this.newAlbumPid,
    this.newReleaseGroupPid,
    this.writeBackFailures = const [],
  });

  final String itemPid;

  /// The album the track left.
  final String oldAlbumPid;

  /// The album it landed on, absent when its own tags carry no
  /// grouping evidence beyond the release id it gave up.
  final String? newAlbumPid;
  final String? newReleaseGroupPid;

  final List<WriteBackFailure> writeBackFailures;
}

/// What a rename did to an entity's identity key.
enum EntityRenameOutcome {
  /// The key moved and the row stayed, keeping its pid.
  renamed,

  /// The new key was already taken, so the row folded into the
  /// incumbent named by [EntityRenameResult.mergedInto].
  merged,

  /// The new key equals the old one, so only the display columns moved.
  /// A case-only rename lands here.
  refreshed,
}

/// The outcome of renaming a whole album, release group, or artist.
class EntityRenameResult {
  const EntityRenameResult({
    required this.entityPid,
    required this.outcome,
    required this.members,
    required this.credits,
    this.mergedInto,
    this.movedAlbums = const [],
    this.writeBackFailures = const [],
  });

  final String entityPid;
  final EntityRenameOutcome outcome;

  /// How many items carried the rename.
  final int members;

  /// How many contributor-role credits moved with an artist rename.
  final int credits;

  /// Where the entity went when [outcome] is [EntityRenameOutcome.merged].
  final String? mergedInto;

  /// Albums that came out under a different release group than they
  /// went in under.
  final List<String> movedAlbums;

  final List<WriteBackFailure> writeBackFailures;
}

/// One library an upload or acquisition may name.
///
/// Naming one selects the library whose settings govern the import (its
/// matching mode, its singles auto-apply) and whose read-only state
/// gates it. It does not choose where the file is placed: that is the
/// catalog's own routing by media type into a managed root.
class UploadTarget {
  const UploadTarget({
    required this.pid,
    required this.name,
    required this.mediaTypes,
    required this.managed,
  });

  final String pid;
  final String name;

  /// What the library accepts, already flattened: a mixed library lists
  /// every kind it takes.
  final List<MediaType> mediaTypes;

  /// Whether the library is a managed root, and so a place the catalog
  /// can put files. Reported, not required.
  final bool managed;
}

/// One editor draft's staged parts, for the compound save. Every part
/// is optional and at least one is required; the nullable collections
/// are the ones whose empty form means something (an empty chapter list
/// restores the embedded chapters).
///
/// The three write switches live here rather than on each part: a draft
/// is saved with one set of them.
class MetadataCommit {
  const MetadataCommit({
    this.fields,
    this.credits = const [],
    this.lyrics,
    this.clearLyrics = false,
    this.chapters,
    this.tagSets = const {},
    this.tagRemoves = const [],
    this.unofficial,
    this.writeBack = false,
    this.lock = true,
    this.force = false,
  });

  final Map<String, String>? fields;
  final List<CommitCredits> credits;
  final CommitLyrics? lyrics;
  final bool clearLyrics;
  final List<ChapterEdit>? chapters;
  final Map<String, List<String>> tagSets;
  final List<String> tagRemoves;
  final bool? unofficial;
  final bool writeBack;
  final bool lock;
  final bool force;
}

/// Replacement people for one credit role inside a compound commit.
class CommitCredits {
  const CommitCredits({required this.role, required this.names});

  final String role;
  final List<String> names;
}

/// Replacement lyrics inside a compound commit; at least one block
/// carries content.
class CommitLyrics {
  const CommitLyrics({this.lrc, this.plain});

  final String? lrc;
  final String? plain;
}

/// What a compound commit did, part by part in execution order.
///
/// Read [parts] rather than the absence of a thrown exception: a refused
/// part is a successful response, and [writeBackFailures] and [warnings]
/// belong to the parts that committed before it.
class MetadataCommitResult {
  const MetadataCommitResult({
    required this.parts,
    this.writeBackFailures = const [],
    this.warnings = const [],
  });

  final List<MetadataCommitPart> parts;
  final List<WriteBackFailure> writeBackFailures;
  final List<String> warnings;

  /// The refusal that stopped the commit, or null when every part
  /// committed.
  WaxDeckApiException? get refusal => parts
      .where((p) => p.status == MetadataCommitStatus.refused)
      .map((p) => p.refusal)
      .whereType<WaxDeckApiException>()
      .firstOrNull;
}

/// The staged parts a commit reports on. Open on the wire; an unknown
/// spelling reads as [unknown] rather than failing the parse, since the
/// envelope's own totals are what a client acts on.
enum MetadataCommitPartKind {
  fields,
  credit,
  lyrics,
  chapters,
  tagSet,
  tagRemove,
  releaseStatus,
  unknown,
}

/// What became of one part.
enum MetadataCommitStatus { committed, refused, skipped, unknown }

/// One part of a compound commit and what became of it.
class MetadataCommitPart {
  const MetadataCommitPart({
    required this.part,
    required this.status,
    this.detail,
    this.refusal,
  });

  final MetadataCommitPartKind part;
  final MetadataCommitStatus status;

  /// Which one, where the part repeats: the role for a credit, the tag
  /// key for a tag set or removal.
  final String? detail;

  /// Why this part was refused, carrying no status code because the
  /// response itself succeeded.
  final WaxDeckApiException? refusal;
}

/// Outcome of a bulk metadata edit.
class BulkEditResult {
  const BulkEditResult({
    required this.edited,
    this.skipped = const [],
    this.writeBackFailures = const [],
    this.resultingAlbumPid,
  });

  /// Pids that took the edit.
  final List<String> edited;

  /// Pids skipped over locks.
  final List<String> skipped;
  final List<WriteBackFailure> writeBackFailures;

  /// The album the edited items now sit on, reported when the edit
  /// rewrote a release-keying field (album, album artist, year) and
  /// every edited item landed on one album. Rewriting those regroups
  /// the members onto a fresh pid rather than renaming the release in
  /// place, so a caller showing the old album follows this to the new
  /// one. Null when no keying field was edited or the items split.
  final String? resultingAlbumPid;
}

/// Outcome of a custom tag edit.
class TagEditResult {
  const TagEditResult({required this.key, required this.stored});

  final String key;

  /// Number of values stored.
  final int stored;
}

/// One curated field override on a browse entity.
class EntityCuratedField {
  const EntityCuratedField({
    required this.field,
    this.value,
    required this.source,
    required this.locked,
    this.updatedAt,
  });

  final String field;
  final String? value;

  /// Open vocabulary.
  final String source;
  final bool locked;
  final DateTime? updatedAt;
}

/// One chapter mark as sent to the chapter editor.
class ChapterEdit {
  const ChapterEdit({
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

/// Outcome of a single-item enrichment request: which of the wanted
/// artifacts were applied and which were skipped.
class EnrichItemResult {
  const EnrichItemResult({this.applied = const [], this.skipped = const []});

  final List<String> applied;
  final List<String> skipped;
}

/// One field an enrichment provider would fill: a diff row, and the
/// commit's instruction when passed back inside an [EnrichProposal].
class EnrichFieldProposal {
  const EnrichFieldProposal({
    required this.name,
    this.current = '',
    required this.proposed,
    required this.provider,
  });

  final String name;

  /// Empty today by construction - enrichment only fills empty fields -
  /// but carried so the diff never has to trust that rule.
  final String current;
  final String proposed;
  final String provider;
}

/// One cover image an enrichment provider would store, bytes included
/// so the commit stores exactly the picture the preview showed.
class EnrichCoverProposal {
  const EnrichCoverProposal({
    required this.provider,
    required this.data,
    this.format,
    this.sourceUrl,
  });

  final String provider;
  final Uint8List data;
  final String? format;
  final String? sourceUrl;
}

/// A previewed enrichment handed back to commit as approved.
class EnrichProposal {
  const EnrichProposal({this.fields = const [], this.cover});

  final List<EnrichFieldProposal> fields;
  final EnrichCoverProposal? cover;
}

/// What a one-item enrichment would change, without having changed it.
class EnrichPreview {
  const EnrichPreview({
    this.fields = const [],
    this.cover,
    this.skipped = const [],
  });

  final List<EnrichFieldProposal> fields;
  final EnrichCoverProposal? cover;

  /// Wants nothing is proposed for, each naming why - the same reasons
  /// the blind fetch reports.
  final List<String> skipped;

  bool get isEmpty => fields.isEmpty && cover == null;

  /// The half to pass back on apply.
  EnrichProposal get proposal => EnrichProposal(fields: fields, cover: cover);
}

/// Failure count for one library health rule.
class HealthRuleCount {
  const HealthRuleCount({
    required this.rule,
    this.label,
    required this.failing,
    required this.fixable,
  });

  final String rule;
  final String? label;
  final int failing;

  /// True when the fix endpoint can queue automatic repairs.
  final bool fixable;
}

/// The library health scoreboard.
class HealthSummary {
  const HealthSummary({
    required this.score,
    required this.totalItems,
    required this.evaluatedItems,
    this.warmingUp = false,
    this.sweptAt,
    this.rules = const [],
  });

  /// Overall health in 0 to 100.
  final double score;
  final int totalItems;
  final int evaluatedItems;

  /// True while the first sweep is still filling in.
  final bool warmingUp;
  final DateTime? sweptAt;
  final List<HealthRuleCount> rules;
}

/// One item failing at least one health rule.
class HealthIssue {
  const HealthIssue({
    required this.pid,
    required this.title,
    this.artist,
    required this.mediaType,
    required this.rules,
  });

  final String pid;
  final String title;
  final String? artist;
  final MediaType mediaType;

  /// The rules this item fails.
  final List<String> rules;
}

/// One keyset-paginated page of health issues.
class HealthIssuePage {
  const HealthIssuePage({required this.items, this.nextCursor});

  final List<HealthIssue> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// One persisted per-file diagnostic (what scan, organize, replaygain, or
/// tag write-back recorded about a file), keyed for display by its path.
class FileDiagnostic {
  const FileDiagnostic({
    required this.path,
    required this.origin,
    required this.code,
    required this.severity,
    required this.seenAt,
    this.tagKey,
    this.detail,
  });

  /// The file's display path.
  final String path;

  /// The writer that recorded it (`scan`, `organize`, `replaygain`, `edit`).
  final String origin;

  /// What was observed (`unsupported_format`, `corrupt_audio`, ...).
  final String code;

  /// `info`, `warn`, or `error`.
  final String severity;

  /// When the diagnostic was last recorded.
  final DateTime seenAt;

  /// The tag key a key-specific diagnostic concerns, when any.
  final String? tagKey;

  /// The writer's own note, when it carries one.
  final String? detail;
}

/// One page of per-file diagnostics.
class FileDiagnosticPage {
  const FileDiagnosticPage({required this.diagnostics, this.nextCursor});

  final List<FileDiagnostic> diagnostics;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// One grouped bucket of the diagnostic summary: how many diagnostics one
/// writer recorded under one code and severity.
class DiagnosticCount {
  const DiagnosticCount({
    required this.origin,
    required this.code,
    required this.severity,
    required this.count,
  });

  final String origin;
  final String code;
  final String severity;
  final int count;
}

/// One entity in a duplicate group.
/// One catalog library (a scanned root).
class LibraryInfo {
  const LibraryInfo({
    required this.pid,
    required this.name,
    this.media,
    this.path,
    this.itemCount,
    this.streamingWarning,
  });

  final String pid;
  final String name;

  /// The content class the library holds (`music`, `audiobook`,
  /// `mixed`), when declared.
  final String? media;

  /// The root directory on the server, for the screen that manages it.
  /// Absent where the catalog holds a path it cannot render as text.
  final String? path;

  /// What the catalog holds under the root. Absent where nothing counted
  /// it, which is every answer but the listing's.
  final int? itemCount;

  /// Set on a freshly created library whose root the streaming sidecar
  /// did not take: the library works for browsing, downloading, and
  /// direct playback, and streaming waits for a sidecar restart.
  final String? streamingWarning;
}

/// One genre in the canonical vocabulary: its display spelling, the
/// top-level genre it groups under, and the spellings that fold onto it.
class GenreNode {
  const GenreNode({
    required this.name,
    this.parent,
    this.aliases = const <String>[],
  });

  final String name;

  /// The parent genre's canonical name, or null for a top-level genre.
  /// The tree is two levels deep, so a parent never has one of its own.
  final String? parent;

  final List<String> aliases;

  GenreNode copyWith({
    String? name,
    String? parent,
    bool clearParent = false,
    List<String>? aliases,
  }) => GenreNode(
    name: name ?? this.name,
    parent: clearParent ? null : (parent ?? this.parent),
    aliases: aliases ?? this.aliases,
  );
}

/// The vocabulary in force, and whether it is the shipped default or one
/// stored on this instance.
class GenreTree {
  const GenreTree({required this.source, required this.genres});

  /// `default` or `custom`.
  final String source;
  final List<GenreNode> genres;

  bool get isDefault => source == 'default';
}

class DuplicateEntity {
  const DuplicateEntity({
    required this.pid,
    required this.name,
    this.itemCount,
  });

  final String pid;
  final String name;
  final int? itemCount;
}

/// One detected duplicate cluster with a suggested survivor.
class DuplicateGroup {
  const DuplicateGroup({
    required this.entityType,
    required this.survivor,
    required this.losers,
    this.detail,
  });

  /// `album`, `artist`, `release-group`, or `genre`.
  final String entityType;
  final DuplicateEntity survivor;
  final List<DuplicateEntity> losers;
  final String? detail;
}

/// Outcome of a duplicate merge.
class MergeOutcome {
  const MergeOutcome({required this.merged, required this.childrenMoved});

  final int merged;
  final int childrenMoved;
}

/// One item in a quality upgrade group.
class UpgradeMember {
  const UpgradeMember({
    required this.itemPid,
    required this.title,
    this.artist,
    required this.codec,
    this.bitrate,
    this.sampleRate,
    this.bitDepth,
    required this.lossless,
    required this.best,
  });

  final String itemPid;
  final String title;
  final String? artist;
  final String codec;
  final int? bitrate;
  final int? sampleRate;
  final int? bitDepth;
  final bool lossless;

  /// True for the member the server suggests keeping.
  final bool best;
}

/// One recording present in more than one quality.
class UpgradeGroup {
  const UpgradeGroup({required this.members});

  final List<UpgradeMember> members;
}

/// One file organization profile.
class OrganizeProfile {
  const OrganizeProfile({
    required this.name,
    this.musicTemplate,
    this.audiobookTemplate,
    this.podcastTemplate,
    this.tagWrite = false,
  });

  final String name;
  final String? musicTemplate;
  final String? audiobookTemplate;
  final String? podcastTemplate;

  /// True when applying the profile also rewrites tags.
  final bool tagWrite;
}

/// One planned file move.
class OrganizeAction {
  const OrganizeAction({
    required this.itemPid,
    required this.from,
    required this.to,
  });

  final String itemPid;
  final String from;
  final String to;
}

/// A dry-run organize plan.
class OrganizePlan {
  const OrganizePlan({
    required this.profile,
    required this.totalActions,
    this.actions = const [],
    this.tagWrite = false,
  });

  final String profile;

  /// Total planned moves; [actions] may be a truncated preview.
  final int totalActions;
  final List<OrganizeAction> actions;
  final bool tagWrite;
}

/// One file an organize run could not move.
class OrganizeFailure {
  const OrganizeFailure({required this.path, required this.reason});

  final String path;
  final String reason;
}

/// Outcome of an applied organize run.
class OrganizeReport {
  const OrganizeReport({
    required this.moved,
    required this.skipped,
    required this.failed,
    this.failures = const [],
  });

  final int moved;
  final int skipped;
  final int failed;
  final List<OrganizeFailure> failures;
}

/// One long-running library tool task.
class ToolTask {
  const ToolTask({
    required this.id,
    required this.type,
    required this.state,
    this.itemPid,
    this.progressPct,
    this.error,
    this.resultPids = const [],
    required this.createdAt,
    this.finishedAt,
    this.summary,
  });

  final String id;

  /// `book-merge`, `book-split`, or `cue-split`. Open vocabulary.
  final String type;

  /// `queued`, `running`, `done`, or `failed`. Open vocabulary.
  final String state;
  final String? itemPid;
  final double? progressPct;
  final String? error;

  /// Pids the task produced, once done.
  final List<String> resultPids;
  final DateTime createdAt;
  final DateTime? finishedAt;

  /// Task-type-specific outcome counters (a migration's matched and
  /// unmatched counts, for example), once finished.
  final Map<String, Object?>? summary;
}

/// One keyset-paginated page of tool tasks.
class ToolTaskPage {
  const ToolTaskPage({required this.tasks, this.nextCursor});

  final List<ToolTask> tasks;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// One configured enrichment provider.
class EnrichmentProvider {
  const EnrichmentProvider({
    required this.name,
    this.capabilities = const [],
    required this.configured,
    required this.builtin,
  });

  final String name;
  final List<String> capabilities;
  final bool configured;
  final bool builtin;
}

/// Enriched-versus-total counts for one artifact class.
class CoverageCount {
  const CoverageCount({required this.enriched, required this.total});

  final int enriched;
  final int total;
}

/// How much of the library each enrichment artifact covers.
class EnrichmentCoverage {
  const EnrichmentCoverage({
    required this.artists,
    required this.releaseGroups,
    required this.books,
    required this.lyrics,
  });

  final CoverageCount artists;
  final CoverageCount releaseGroups;
  final CoverageCount books;
  final CoverageCount lyrics;
}

/// The enrichment subsystem's provider roster and coverage.
class EnrichmentStatus {
  const EnrichmentStatus({
    this.providers = const [],
    required this.coverage,
    required this.running,
  });

  final List<EnrichmentProvider> providers;
  final EnrichmentCoverage coverage;

  /// True while an enrichment job is running.
  final bool running;
}

/// Which libraries an account may see.
class LibraryAccess {
  const LibraryAccess({required this.mode, this.libraryPids = const []});

  /// `all` or `granted`.
  final String mode;

  /// The granted library pids when [mode] is `granted`.
  final List<String> libraryPids;
}

/// One linked single-sign-on identity on an account.
class LinkedIdentity {
  const LinkedIdentity({required this.provider, this.email});

  final String provider;
  final String? email;
}

/// A WaxDeck account as visible to administrators.
class UserAccount extends WaxDeckUser {
  const UserAccount({
    required super.id,
    required super.username,
    super.displayName,
    super.roles,
    required this.createdAt,
    this.identities = const [],
    required this.libraryAccess,
    this.uploadEnabled = false,
    this.uploadQuotaBytes,
    this.disabled = false,
    this.hasPassword = true,
    this.pending = false,
    this.permissions = const Permissions(),
  });

  final DateTime createdAt;
  final List<LinkedIdentity> identities;
  final LibraryAccess libraryAccess;

  /// Whether the account may create upload sessions.
  final bool uploadEnabled;

  /// Per-user cap on concurrent staged upload bytes; null means the
  /// server default.
  final int? uploadQuotaBytes;
  final bool disabled;
  final bool hasPassword;

  /// True while the account is a signup request awaiting approval.
  final bool pending;

  /// What the account is allowed to do beyond its roles.
  final Permissions permissions;
}

/// One keyset-paginated page of accounts.
class UserPage {
  const UserPage({required this.users, this.nextCursor});

  final List<UserAccount> users;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// One content tag pattern in a permission's allow or deny list. A null
/// [value] matches any value under the key.
class TagRule {
  const TagRule({required this.key, this.value});

  final String key;
  final String? value;
}

/// Per-account capability switches beyond the role split. The
/// constructor defaults mirror the server's new-account defaults
/// (everything on except delete), so a Permissions built without
/// explicit values encodes the documented contract.
class Permissions {
  const Permissions({
    this.download = true,
    this.delete = false,
    this.explicitContent = true,
    this.sharedOutputs = true,
    this.managePodcasts = true,
    this.maxTranscodeKbps,
    this.tagAllow = const [],
    this.tagDeny = const [],
  });

  final bool download;
  final bool delete;
  final bool explicitContent;
  final bool sharedOutputs;
  final bool managePodcasts;

  /// Transcode bitrate ceiling for this account; null means the server
  /// default applies.
  final int? maxTranscodeKbps;

  /// Content visible only when it matches one of these rules; empty
  /// means no allow filtering.
  final List<TagRule> tagAllow;

  /// Content hidden when it matches one of these rules.
  final List<TagRule> tagDeny;

  Permissions copyWith({
    bool? download,
    bool? delete,
    bool? explicitContent,
    bool? sharedOutputs,
    bool? managePodcasts,
    int? Function()? maxTranscodeKbps,
    List<TagRule>? tagAllow,
    List<TagRule>? tagDeny,
  }) => Permissions(
    download: download ?? this.download,
    delete: delete ?? this.delete,
    explicitContent: explicitContent ?? this.explicitContent,
    sharedOutputs: sharedOutputs ?? this.sharedOutputs,
    managePodcasts: managePodcasts ?? this.managePodcasts,
    maxTranscodeKbps: maxTranscodeKbps == null
        ? this.maxTranscodeKbps
        : maxTranscodeKbps(),
    tagAllow: tagAllow ?? this.tagAllow,
    tagDeny: tagDeny ?? this.tagDeny,
  );
}

/// Outcome of a signup request: `pending` awaits approval, `active`
/// means the account can log in now.
class SignupResult {
  const SignupResult({required this.state});

  final String state;

  bool get pending => state == 'pending';
}

/// One invite, as listed to administrators. The token itself is only
/// ever visible on [InviteCreated].
class Invite {
  const Invite({
    required this.id,
    this.note,
    this.roles = const [],
    this.libraryAccess,
    this.permissions,
    this.uploadEnabled = false,
    required this.maxUses,
    this.usedCount = 0,
    this.revoked = false,
    this.expiresAt,
    required this.createdAt,
    this.createdBy,
  });

  final String id;
  final String? note;
  final List<String> roles;
  final LibraryAccess? libraryAccess;
  final Permissions? permissions;
  final bool uploadEnabled;
  final int maxUses;
  final int usedCount;
  final bool revoked;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final String? createdBy;

  bool get expired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now().toUtc());
}

/// A freshly created invite; [token] is visible exactly once.
class InviteCreated extends Invite {
  const InviteCreated({
    required super.id,
    super.note,
    super.roles,
    super.libraryAccess,
    super.permissions,
    super.uploadEnabled,
    required super.maxUses,
    super.usedCount,
    super.revoked,
    super.expiresAt,
    required super.createdAt,
    super.createdBy,
    required this.token,
  });

  final String token;
}

/// Server-wide switches administrators can flip at runtime.
class AdminSettings {
  const AdminSettings({
    required this.signupEnabled,
    required this.readOnly,
    required this.sonicAnalysis,
    required this.backupKeepCount,
    required this.backupKeepBytes,
    required this.trashRetentionDays,
    required this.taskRetentionDays,
    required this.radioExternalArt,
  });

  final bool signupEnabled;

  /// Server-wide read-only mode: every mutation of library content is
  /// refused while set.
  final bool readOnly;

  /// Whether the server analyzes its own library for sonic similarity
  /// in the background (the embedded analyzer).
  final bool sonicAnalysis;

  /// Backup retention: how many archives to keep (0 keeps all).
  final int backupKeepCount;

  /// Backup retention: total archive bytes to keep (0 keeps all).
  final int backupKeepBytes;

  /// Trash retention: purge trashed files older than this many days on a
  /// periodic sweep (0 disables retention).
  final int trashRetentionDays;

  /// Task retention: clear finished tool tasks older than this many days
  /// on the scheduled prune. Unlike [trashRetentionDays], 0 is a choice
  /// ("keep them") rather than the default, which is 30.
  final int taskRetentionDays;

  /// Whether radio may look a station's announced title up against
  /// MusicBrainz and the Cover Art Archive when nothing in this library
  /// matches it. Off by default, and the only setting here that decides
  /// whether the server talks to a third party at all.
  final bool radioExternalArt;

  AdminSettings copyWith({
    bool? signupEnabled,
    bool? readOnly,
    bool? sonicAnalysis,
    int? backupKeepCount,
    int? backupKeepBytes,
    int? trashRetentionDays,
    int? taskRetentionDays,
    bool? radioExternalArt,
  }) => AdminSettings(
    signupEnabled: signupEnabled ?? this.signupEnabled,
    readOnly: readOnly ?? this.readOnly,
    sonicAnalysis: sonicAnalysis ?? this.sonicAnalysis,
    backupKeepCount: backupKeepCount ?? this.backupKeepCount,
    backupKeepBytes: backupKeepBytes ?? this.backupKeepBytes,
    trashRetentionDays: trashRetentionDays ?? this.trashRetentionDays,
    taskRetentionDays: taskRetentionDays ?? this.taskRetentionDays,
    radioExternalArt: radioExternalArt ?? this.radioExternalArt,
  );
}

/// Server-wide transcoding concurrency and bitrate ceilings.
class TranscodingLimits {
  const TranscodingLimits({
    required this.maxConcurrent,
    required this.maxConcurrentPerUser,
    required this.defaultMaxBitrateKbps,
  });

  final int maxConcurrent;
  final int maxConcurrentPerUser;

  /// Default bitrate ceiling for accounts without a per-user override;
  /// 0 means unlimited.
  final int defaultMaxBitrateKbps;
}

/// What the transcoder is doing right now, read beside the limits that
/// bound it.
class TranscodingActivity {
  const TranscodingActivity({
    required this.activeSessions,
    this.activeTimelines,
  });

  /// Engine-backed sessions in flight: what the concurrent caps count.
  final int activeSessions;

  /// How much of [activeSessions] is listeners playing a queue as one
  /// gapless rendering; null from a server that does not separate them.
  final int? activeTimelines;
}

/// The server-level Last.fm API credential state (administrators).
class ScrobblingAdminConfig {
  const ScrobblingAdminConfig({
    required this.lastfmConfigured,
    required this.lastfmSource,
    this.lastfmApiKey,
    required this.lastfmSecretSet,
  });

  /// Whether a usable Last.fm API credential pair is in effect (users
  /// can link accounts and the connect button enables).
  final bool lastfmConfigured;

  /// Where the effective pair came from: `settings`, `environment`, or
  /// `none`. Open vocabulary.
  final String lastfmSource;

  /// The effective API key, for display in the admin form. Present only
  /// when configured; the shared secret is never read back.
  final String? lastfmApiKey;

  /// Whether a shared secret is stored.
  final bool lastfmSecretSet;
}

/// One recurring maintenance schedule (`scan`, `backup`, or `prune`).
class Schedule {
  const Schedule({
    required this.kind,
    required this.cron,
    required this.enabled,
    this.lastRunAt,
    this.lastStatus,
    this.lastError,
    this.nextRunAt,
  });

  final String kind;
  final String cron;
  final bool enabled;
  final DateTime? lastRunAt;

  /// `ok` or `failed`, once the schedule has run.
  final String? lastStatus;
  final String? lastError;
  final DateTime? nextRunAt;
}

/// One backup archive.
class Backup {
  const Backup({
    required this.id,
    required this.state,
    required this.trigger,
    required this.fileName,
    this.sizeBytes,
    this.error,
    required this.createdAt,
    this.finishedAt,
  });

  final String id;

  /// `running`, `done`, or `failed`. Open vocabulary.
  final String state;

  /// `manual` or `scheduled`. Open vocabulary.
  final String trigger;
  final String fileName;
  final int? sizeBytes;
  final String? error;
  final DateTime createdAt;
  final DateTime? finishedAt;
}

/// Sealed (credential-encrypted) state a restore would lose.
class SealedCasualty {
  const SealedCasualty({required this.kind, required this.name});

  final String kind;
  final String name;
}

/// A staged restore, applied at the next server restart.
class RestorePlan {
  const RestorePlan({
    required this.backupId,
    required this.stagedAt,
    required this.keyfilePresent,
    required this.keyfileMatches,
    this.sealedCasualties = const [],
    this.warnings = const [],
  });

  final String backupId;
  final DateTime stagedAt;

  /// Whether the archive carries the sealed-secrets keyfile at all.
  final bool keyfilePresent;

  /// Whether that keyfile matches this server's; when false, sealed
  /// secrets in the backup become [sealedCasualties].
  final bool keyfileMatches;
  final List<SealedCasualty> sealedCasualties;
  final List<String> warnings;
}

/// One background job (scan, enrichment, and friends).
class Job {
  const Job({
    required this.pid,
    required this.kind,
    required this.state,
    this.progress,
    this.message,
    this.error,
  });

  final String pid;
  final String kind;
  final String state;

  /// 0 to 1 when the job can estimate progress.
  final double? progress;
  final String? message;
  final String? error;
}

/// One audit-log event, newest first in listings.
class AuditEvent {
  const AuditEvent({
    required this.id,
    this.actorId,
    this.actorName,
    required this.action,
    this.targetKind,
    this.targetPid,
    this.targetName,
    this.detail = const {},
    required this.createdAt,
  });

  final String id;

  /// Null for system-initiated actions.
  final String? actorId;
  final String? actorName;

  /// Dotted action name (`user.create`, `backup.restore-staged`, ...).
  final String action;
  final String? targetKind;
  final String? targetPid;
  final String? targetName;

  /// Action-specific structured payload.
  final Map<String, Object?> detail;
  final DateTime createdAt;
}

/// One keyset-paginated page of audit events.
class AuditEventPage {
  const AuditEventPage({required this.events, this.nextCursor});

  final List<AuditEvent> events;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// One file parked in the server-side trash.
class TrashEntry {
  const TrashEntry({
    required this.id,
    this.itemPid,
    required this.name,
    required this.reason,
    required this.sizeBytes,
    required this.trashedAt,
    this.restoredAt,
  });

  final String id;
  final String? itemPid;

  /// The original library-relative path.
  final String name;

  /// Why the file was trashed (`delete`, `upgrade`, ...). Open vocabulary.
  final String reason;
  final int sizeBytes;
  final DateTime trashedAt;

  /// Set once the entry was restored back into the library.
  final DateTime? restoredAt;
}

/// The server-side trash listing.
class TrashList {
  const TrashList({required this.entries});

  final List<TrashEntry> entries;
}

/// Outcome of emptying the trash.
class TrashEmptyResult {
  const TrashEmptyResult({
    required this.purged,
    required this.errored,
    required this.reclaimedBytes,
  });

  final int purged;
  final int errored;
  final int reclaimedBytes;
}

/// One fully-addressed request a client can hand to the platform on
/// its way out.
///
/// Everything is resolved: the absolute URL, the method, the encoded
/// body, and the headers that authenticate it. Nothing about sending it
/// belongs to this package - a browser tab uses `fetch(keepalive: true)`
/// so the request outlives the document - so this is the shape that
/// crosses the line, not a call.
class ExitRequest {
  const ExitRequest({
    required this.path,
    required this.method,
    required this.body,
    required this.headers,
  });

  final String path;
  final String method;

  /// The already-encoded JSON body.
  final String body;

  /// Everything but `Content-Type`, which the sender adds.
  final Map<String, String> headers;
}

/// One uploaded account data export, staged for the import that reads
/// it. [pid] is what `createMigration` names as its `exportId`.
class MigrationExport {
  const MigrationExport({
    required this.pid,
    required this.source,
    required this.files,
    required this.sizeBytes,
    required this.expiresAt,
  });

  final String pid;

  /// Which service's export this was recognised as.
  final String source;

  /// The files inside the archive the import will read.
  final List<String> files;

  final int sizeBytes;

  /// When the staged file is swept, after which it has to be uploaded
  /// again.
  final DateTime expiresAt;
}

/// What the generated-thumbnail cache holds, beside what the source
/// images behind it cost.
///
/// Every row is derived: a re-encode of a stored source at one rung of
/// the size ladder. [bytes] is read against [artSourceBytes] - a cache
/// smaller than the originals it was derived from is doing its job.
class ThumbnailCacheReport {
  const ThumbnailCacheReport({
    required this.rows,
    required this.bytes,
    required this.sources,
    required this.artSources,
    required this.artSourceBytes,
    required this.rungs,
    this.oldestAt,
    this.newestAt,
  });

  final int rows;
  final int bytes;

  /// Source images with at least one derivative, out of [artSources].
  final int sources;
  final int artSources;
  final int artSourceBytes;

  /// Null together when the cache is empty: an empty cache has no
  /// oldest entry rather than one at the epoch.
  final DateTime? oldestAt;
  final DateTime? newestAt;

  /// Per-rung breakdown, largest box first.
  final List<ThumbnailRung> rungs;
}

/// One ladder rung's share of the thumbnail cache.
class ThumbnailRung {
  const ThumbnailRung({
    required this.size,
    required this.rows,
    required this.bytes,
  });

  /// The rung in pixels. A requested box rounds up to one of these,
  /// which is what bounds how many derivatives one cover accumulates.
  final int size;
  final int rows;
  final int bytes;
}

/// What a thumbnail-cache prune dropped.
class ThumbnailPruneResult {
  const ThumbnailPruneResult({required this.removed, required this.freedBytes});

  final int removed;

  /// Freed inside the catalog file rather than returned to the
  /// filesystem.
  final int freedBytes;
}

/// What one server-side migration import should carry over.
class MigrationOptions {
  const MigrationOptions({
    this.stars = true,
    this.ratings = true,
    this.history = true,
    this.progress = true,
  });

  final bool stars;
  final bool ratings;
  final bool history;
  final bool progress;
}

/// One entry in a delete plan: what deleting a pid removes.
class DeletePlanEntry {
  const DeletePlanEntry({
    required this.pid,
    this.name,
    required this.files,
    required this.bytes,
  });

  final String pid;
  final String? name;
  final int files;
  final int bytes;
}

/// Outcome (or dry-run plan) of a library item deletion.
class DeleteItemsResult {
  const DeleteItemsResult({
    required this.applied,
    required this.mode,
    this.entries = const [],
  });

  /// False for a dry run: [entries] is the plan, nothing was touched.
  final bool applied;

  /// `trash` or `permanent`.
  final String mode;
  final List<DeletePlanEntry> entries;

  int get totalFiles => entries.fold(0, (sum, e) => sum + e.files);
  int get totalBytes => entries.fold(0, (sum, e) => sum + e.bytes);
}

/// Which engine answered a discovery request: [sonic] used stored audio
/// embeddings, [metadata] used genre and artist heuristics (the
/// zero-setup fallback).
enum MixBasis {
  sonic('sonic'),
  metadata('metadata');

  const MixBasis(this.wireName);

  /// Value as it appears on the wire.
  final String wireName;
}

/// Tracks similar to a seed, most similar first.
class SimilarTracks {
  const SimilarTracks({required this.basis, this.items = const []});

  final MixBasis basis;
  final List<ItemSummary> items;
}

/// A computed instant mix. Not persisted; order is play order.
class InstantMix {
  const InstantMix({
    required this.basis,
    this.items = const [],
    this.excluded = 0,
  });

  final MixBasis basis;
  final List<ItemSummary> items;

  /// Distinct candidates dropped because `excludePids` named them. What
  /// tells an empty mix whose candidates are all queued apart from a
  /// seed with none at all; zero from servers predating the field.
  final int excluded;
}

/// A sonic path between two tracks, starting track first, destination
/// last when [complete].
class SonicPath {
  const SonicPath({required this.complete, this.items = const []});

  /// Whether the path reaches the destination. False when the neighbor
  /// graph connects the endpoints only partially; the returned prefix
  /// still drifts toward the target.
  final bool complete;

  final List<ItemSummary> items;
}

/// One chart bucket of listening time.
class ListeningBucket {
  const ListeningBucket({
    required this.start,
    required this.ms,
    required this.sessions,
  });

  /// First calendar day of the bucket in the caller's timezone, as a
  /// UTC-midnight instant.
  final DateTime start;

  /// Milliseconds listened in the bucket.
  final int ms;

  /// Listen sessions in the bucket.
  final int sessions;
}

/// Listening total for one media type.
class MediaTypeListening {
  const MediaTypeListening({
    required this.mediaType,
    required this.ms,
    required this.sessions,
  });

  final StatsMediaType mediaType;
  final int ms;
  final int sessions;
}

/// Aggregated listening time for one user.
class ListeningStats {
  const ListeningStats({
    required this.range,
    required this.bucket,
    required this.timezone,
    required this.totalMs,
    required this.sessions,
    required this.timeSavedMs,
    this.buckets = const [],
    this.byMediaType = const [],
  });

  /// The range that was aggregated: 7d, 30d, 90d, 365d, or all.
  final String range;

  /// The bucket size used: day, week, or month.
  final String bucket;

  /// IANA timezone the calendar bucketing used.
  final String timezone;

  final int totalMs;
  final int sessions;

  /// Milliseconds saved by silence trimming and speed-up in the range.
  final int timeSavedMs;

  /// Chart buckets, oldest first. Empty buckets are omitted.
  final List<ListeningBucket> buckets;

  /// Listening split by media type, most-listened first.
  final List<MediaTypeListening> byMediaType;
}

/// One day's listening on the heatmap.
class HeatmapDay {
  const HeatmapDay({
    required this.date,
    required this.ms,
    required this.sessions,
  });

  /// The calendar day in the caller's timezone, as a UTC-midnight
  /// instant.
  final DateTime date;

  final int ms;
  final int sessions;
}

/// Per-day listening for one calendar year, plus streaks.
class ListeningHeatmap {
  const ListeningHeatmap({
    required this.year,
    required this.timezone,
    this.days = const [],
    required this.currentStreakDays,
    required this.longestStreakDays,
  });

  final int year;
  final String timezone;

  /// Days with listening, chronological.
  final List<HeatmapDay> days;

  /// Consecutive listening days ending today or yesterday; 0 when the
  /// streak is broken.
  final int currentStreakDays;

  /// The longest run of consecutive listening days that touches the
  /// requested year.
  final int longestStreakDays;
}

/// One top-list entry.
class TopEntry {
  const TopEntry({
    required this.name,
    this.pid,
    this.artUrl,
    required this.plays,
    required this.ms,
  });

  /// Display name (artist, album, genre, or show).
  final String name;

  /// The entry's pid when the entry is a catalog entity; null for
  /// genres and for names that no longer resolve.
  final String? pid;

  /// Artwork URL, already resolved against the client base URL, when
  /// the entry has one.
  final String? artUrl;

  /// Listen sessions attributed to the entry in the range.
  final int plays;

  /// Milliseconds listened in the range.
  final int ms;
}

/// One ranked top list.
class TopList {
  const TopList({
    required this.kind,
    required this.range,
    this.entries = const [],
  });

  /// Which top list this is: artists, albums, genres, or shows.
  final String kind;

  /// The range that was aggregated: 7d, 30d, 90d, 365d, or all.
  final String range;

  /// Ranked entries, most listening time first.
  final List<TopEntry> entries;
}

/// One recorded listen session in the log.
class ListenLogEntry {
  const ListenLogEntry({
    required this.pid,
    this.title,
    this.artist,
    required this.mediaType,
    required this.startedAt,
    required this.msPlayed,
    this.skippedMs,
    required this.finished,
    required this.client,
    required this.source,
  });

  final String pid;

  /// The item's display title at read time; null when the item has
  /// left the catalog entirely.
  final String? title;

  /// The item's display artist, author, or show.
  final String? artist;

  final StatsMediaType mediaType;
  final DateTime startedAt;

  /// Milliseconds actually heard.
  final int msPlayed;

  /// Milliseconds saved by silence trimming and speed-up, when the
  /// client reported them.
  final int? skippedMs;

  final bool finished;

  /// The reporting client label.
  final String client;

  /// `live` playback or a backdated `import`.
  final String source;
}

/// One page of the caller's listen session log, newest first.
class ListenLogPage {
  const ListenLogPage({required this.sessions, this.nextCursor});

  final List<ListenLogEntry> sessions;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// One month's listening.
class MonthListening {
  const MonthListening({
    required this.month,
    required this.ms,
    required this.sessions,
  });

  /// Calendar month, 1 is January.
  final int month;

  final int ms;
  final int sessions;
}

/// One user's listening recap for one calendar year.
class YearInReview {
  const YearInReview({
    required this.year,
    required this.timezone,
    required this.totalMs,
    required this.sessions,
    required this.distinctItems,
    required this.newInLibrary,
    required this.timeSavedMs,
    required this.longestStreakDays,
    this.byMonth = const [],
    this.byMediaType = const [],
    this.topArtists = const [],
    this.topTracks = const [],
    this.topGenres = const [],
    this.topShows = const [],
  });

  final int year;

  /// IANA timezone the recap was computed in.
  final String timezone;

  final int totalMs;
  final int sessions;

  /// Distinct tracks, episodes, and books played that year.
  final int distinctItems;

  /// Items that joined the library that year.
  final int newInLibrary;

  /// Milliseconds saved by silence trimming and speed-up that year.
  final int timeSavedMs;

  /// The year's longest run of consecutive listening days.
  final int longestStreakDays;

  /// Month-by-month listening, January first, all twelve months
  /// present with zeros included.
  final List<MonthListening> byMonth;

  /// Listening split by media type, most-listened first.
  final List<MediaTypeListening> byMediaType;

  final List<TopEntry> topArtists;
  final List<TopEntry> topTracks;
  final List<TopEntry> topGenres;
  final List<TopEntry> topShows;
}

/// The whole server's listening recap for one calendar year, aggregated
/// across users who have not opted out of shared stats.
class ServerYearInReview {
  const ServerYearInReview({
    required this.year,
    required this.participants,
    required this.totalMs,
    required this.sessions,
    this.topArtists = const [],
    this.topTracks = const [],
    this.topGenres = const [],
  });

  final int year;

  /// Users whose listening is included (those who have not opted out
  /// and listened that year).
  final int participants;

  final int totalMs;
  final int sessions;

  final List<TopEntry> topArtists;
  final List<TopEntry> topTracks;
  final List<TopEntry> topGenres;
}

/// One public share link.
class Share {
  const Share({
    required this.pid,
    required this.url,
    required this.targetPid,
    required this.targetKind,
    required this.targetTitle,
    required this.allowDownload,
    this.positionMs,
    required this.createdAt,
    this.expiresAt,
    required this.plays,
    this.owner,
  });

  /// Share PID.
  final String pid;

  /// Capability URL of the landing page, already resolved against the
  /// client base URL. Anyone holding the full URL can open it; treat
  /// it as the secret it is.
  final String url;

  /// The shared track, playlist, book, or episode.
  final String targetPid;

  /// What kind of thing the share opens: track, playlist, book, or
  /// episode.
  final String targetKind;

  /// The target's display title at read time.
  final String targetTitle;

  /// Whether the landing page offers the original file.
  final bool allowDownload;

  /// Start position for copy-link-at-timestamp shares (episodes);
  /// null otherwise.
  final int? positionMs;

  final DateTime createdAt;

  /// When the link stops resolving; null for links without expiry.
  final DateTime? expiresAt;

  /// Anonymous plays through the link so far.
  final int plays;

  /// Who minted the link: display name, or username where none is set.
  /// Only the administrative all-shares listing fills it; on a caller's
  /// own listing every row would name the caller, so it is null there.
  final String? owner;
}

/// One page of share links, newest first.
class SharePage {
  const SharePage({required this.shares, this.nextCursor});

  final List<Share> shares;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// One unmatched playlist import entry.
class PlaylistImportMiss {
  const PlaylistImportMiss({
    this.artist,
    required this.title,
    this.album,
    this.durationMs,
  });

  final String? artist;
  final String title;
  final String? album;

  /// The entry's duration, when the export carried one.
  final int? durationMs;
}

/// How many entries each resolve-ladder rung matched, most confident
/// rung first. A high [descriptive] share means fuzzy matches worth
/// spot-checking.
class ResolveRungCounts {
  const ResolveRungCounts({
    required this.essence,
    required this.strongId,
    required this.fingerprint,
    required this.descriptive,
  });

  /// Identical audio bytes.
  final int essence;

  /// Exact external identifier (recording MBID, ASIN, ISBN).
  final int strongId;

  /// Same recording, different encoding.
  final int fingerprint;

  /// Fuzzy artist, title, album, and duration match.
  final int descriptive;
}

/// The playlist import report.
class PlaylistImportResult {
  const PlaylistImportResult({
    this.playlistPid,
    required this.name,
    required this.requested,
    required this.resolved,
    this.missing = const [],
    required this.rungs,
  });

  /// The created playlist; null when nothing resolved (no playlist is
  /// created).
  final String? playlistPid;

  /// The playlist name used.
  final String name;

  /// Entries found in the export.
  final int requested;

  /// Entries matched to library items.
  final int resolved;

  /// Entries with no library match, in export order: the
  /// missing-tracks report.
  final List<PlaylistImportMiss> missing;

  final ResolveRungCounts rungs;
}

/// A catalog-independent identity descriptor for one playable item,
/// carrying the progressively fuzzier anchors the resolve ladder
/// walks. Produced by the portable export; consumed by the portable
/// import source.
class PortableRef {
  const PortableRef({
    required this.kind,
    this.essence,
    this.fingerprint,
    this.fingerprintAlgo,
    this.mbid,
    this.asin,
    this.isbn,
    this.isrc,
    this.artist,
    required this.title,
    this.album,
    this.durationMs,
  });

  /// What the ref describes: track, book, or episode.
  final String kind;

  /// Exact-rip audio-essence hash.
  final String? essence;

  /// Packed acoustic fingerprint, base64.
  final String? fingerprint;

  /// Fingerprint algorithm: 1 pure-Go, 100 Chromaprint.
  final int? fingerprintAlgo;

  /// Recording MBID (track) or release MBID (book).
  final String? mbid;

  final String? asin;
  final String? isbn;
  final String? isrc;

  /// Track artist, or book author.
  final String? artist;

  final String title;

  /// Track album, or book series.
  final String? album;

  final int? durationMs;
}

/// A playlist exported as portable refs, in playlist order.
class PortablePlaylist {
  const PortablePlaylist({required this.name, this.refs = const []});

  final String name;
  final List<PortableRef> refs;
}

/// One part of a rule or an NSP document with no faithful counterpart
/// on the other side.
///
/// [reason] is the converter's own sentence about what the person built,
/// so a screen renders it rather than mapping it to a phrase of its own.
/// [field] and [op] are written in the vocabulary of the side being
/// read, which is what the report's direction says.
class NspGap {
  const NspGap({
    required this.kind,
    required this.path,
    required this.reason,
    this.field,
    this.op,
    this.value,
  });

  /// `field`, `operator`, `value`, `shape`, `sort`, `limit`, `entity`,
  /// or `malformed`. Open by construction: a kind this build has no
  /// wording for still carries a [reason], which is what a screen shows.
  final String kind;

  /// An RFC 6901 JSON Pointer to the offending part.
  final String path;

  final String reason;
  final String? field;
  final String? op;

  /// The offending value on a `value` gap, whatever JSON type it was.
  final Object? value;
}

/// What one NSP conversion could not carry.
///
/// [gaps] refuse the strict conversion and are what a partial one drops;
/// [notes] refuse nothing. A lossless conversion reports neither, which
/// is what lets a caller skip asking the person anything.
class NspReport {
  const NspReport({
    required this.direction,
    this.gaps = const [],
    this.notes = const [],
  });

  /// `export` or `import`.
  final String direction;

  final List<NspGap> gaps;
  final List<NspGap> notes;

  /// Everything worth showing, in one list: the losses that refuse and
  /// the losses that do not. A person deciding whether to accept the
  /// loss is not helped by the distinction, only by the list.
  List<NspGap> get all => <NspGap>[...gaps, ...notes];

  bool get isLossless => gaps.isEmpty && notes.isEmpty;
}

/// Coverage of the sonic-similarity surface.
class SimilarityStatus {
  const SimilarityStatus({
    required this.enabled,
    this.model,
    this.dims,
    required this.embeddedTracks,
    required this.totalTracks,
    required this.coveragePct,
    required this.queueDepth,
    this.lastIngestAt,
  });

  /// Whether a worker token is configured (a worker may connect).
  final bool enabled;

  /// The embedding model the stored vectors carry; null before the
  /// first ingest.
  final String? model;

  /// Stored vector dimensionality; null before the first ingest.
  final int? dims;

  /// Tracks with a stored embedding.
  final int embeddedTracks;

  /// Tracks eligible for analysis.
  final int totalTracks;

  /// [embeddedTracks] over [totalTracks], 0 to 100. Clients show
  /// sonic affordances when coverage is meaningful.
  final double coveragePct;

  /// Tracks awaiting analysis.
  final int queueDepth;

  /// When a worker last posted embeddings; null before the first
  /// ingest.
  final DateTime? lastIngestAt;
}
