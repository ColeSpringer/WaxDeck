import 'package:waxdeck_api/waxdeck_api.dart';

/// The address `FakeRepository` answers at, and the one a widget test's app
/// is pointed at.
const testServerAddress = 'http://server.test';

/// The repository's own address, token and preferences, the state its
/// constructor fills, and what more than one per-tag mixin reads; the rest
/// lives with its tag.
class FakeRepositoryState {
  FakeRepositoryState({
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

  String baseUrl = testServerAddress;

  /// Item surfaced by the recently-played browse list, if any.
  ItemSummary? recentlyPlayed;

  /// Whether the server still needs its first administrator.
  bool bootstrapNeeded;

  /// The device list served by `listSessions`.
  List<DeviceSession> deviceSessions;

  /// SSO providers served by `oidcProviders`.
  List<OidcProvider> ssoProviders;

  String? authToken;

  /// Saved resume positions by pid.
  final Map<String, int> playPositions = {};

  /// Pids whose saved play state reports the item finished.
  final Set<String> finishedPids = {};

  /// Play counts by pid, for a count past the one a finished pid reports.
  final Map<String, int> playCounts = {};

  /// Stored preferences, served and replaced by the prefs endpoints.
  Prefs prefs = const Prefs();

  /// When set, listing calls fail with it (a dead network in tests).
  WaxDeckApiException? listError;

  /// Episodes per show pid, newest first.
  final Map<String, List<EpisodeSummary>> episodesByShow = {};

  /// Audiobooks by pid.
  final Map<String, BookDetail> books = {};

  /// Items keyed by "dimension key", served when a listing drills a
  /// facet bucket. Missing keys answer an empty page.
  final Map<String, List<ItemSummary>> facetItems = {};

  /// Albums `getAlbum` answers, keyed by pid.
  final Map<String, AlbumDetail> albums = {};

  EpisodeSummary? findEpisode(String pid) {
    for (final episodes in episodesByShow.values) {
      for (final episode in episodes) {
        if (episode.pid == pid) return episode;
      }
    }
    return null;
  }

  /// When each position was last written, for the surfaces ordered by
  /// recency (a continue-listening shelf).
  final Map<String, DateTime> playStateUpdatedAt = {};

  /// When a play was last counted, which the facts sheet reads. Its own
  /// map because the server only stamps it on a counted play: an item
  /// marked played by hand carries a position and no stamp.
  final Map<String, DateTime> playStateLastPlayedAt = {};

  /// Scrobbler slots served by `listScrobblers`; connect and disconnect
  /// mutate them.
  List<Scrobbler> scrobblers = const [
    Scrobbler(service: 'lastfm', available: false, connected: false),
    Scrobbler(service: 'listenbrainz', available: true, connected: false),
  ];

  /// Review entries served by the queue endpoints.
  List<ReviewEntry> reviewEntries = [];

  final List<ArtRoleInfo> artRoles = [];

  /// Tool tasks by id, in creation order.
  final Map<String, ToolTask> toolTasksById = {};

  int toolTaskSeq = 0;

  /// Accounts by id, served and mutated by the admin user endpoints.
  final Map<String, UserAccount> usersById = {};
  int userSeq = 0;

  /// Server-wide switches served and replaced by the settings endpoints.
  AdminSettings adminSettings = const AdminSettings(
    signupEnabled: false,
    readOnly: false,
    sonicAnalysis: true,
    backupKeepCount: 5,
    backupKeepBytes: 0,
    trashRetentionDays: 0,
    taskRetentionDays: 30,
    radioExternalArt: true,
  );

  /// Background jobs served by `listJobs`.
  List<Job> jobs = [];
}
