import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../music/music_controllers.dart';
import '../settings/settings_registry.dart';

/// Every canonical location in the app, in one place.
///
/// Screens never type a path literal: they call these constants and
/// builders, so renaming a route is a single edit and the compiler finds
/// the callers. Paths follow the route map in the UI plan, and the web
/// build puts them in the path rather than the fragment
/// (`useWaxUrlStrategy`), so a location reads as
/// `/podcasts/pc-...` in the address bar and is the same string a
/// stranger can open.
abstract final class WaxRoute {
  /// The signed-in landing surface (the library grid today).
  static const home = '/';

  static const login = '/login';
  static const setup = '/setup';
  static const signup = '/signup';

  /// Locations that only make sense while signed out. The auth redirect
  /// bounces a signed-in session away from all of them.
  static const authLocations = {login, setup, signup};

  /// Query parameter carrying the location a signed-out visitor asked
  /// for, so the deep link survives the trip through the login form.
  static const fromParam = 'from';

  /// One search over everything the caller can see. The query is in the
  /// URL, so a result set is a link.
  static const search = '/search';
  static const searchParam = 'q';

  static String searchFor(String query) => Uri(
    path: search,
    queryParameters: query.isEmpty ? null : {searchParam: query},
  ).toString();

  /// The music domain: a hub, an index per dimension, and a listing per
  /// bucket. Every one of them is a place a stranger can open.
  static const music = '/music';
  static const musicTracks = '$music/tracks';

  static String musicIndex(MusicDimension dimension) =>
      '$music/${dimension.segment}';

  /// One bucket's listing. [segment] is the handle
  /// [musicBucketSegment] mints: an `ar-`/`al-` pid where the bucket is
  /// an entity, the bucket key otherwise, and [musicUnknownSegment] for
  /// the bucket a dimension is absent from.
  /// Encoded, though the four shipped dimensions never need it: their
  /// handles are prefixed ULIDs, digits, and the unknown sentinel. The
  /// endpoint enumerates `kind` and `tag.<KEY>` too, whose keys are free
  /// text, and a helper that is safe only for its current callers is a
  /// trap for the next one.
  static String musicBucket(MusicDimension dimension, String segment) =>
      '${musicIndex(dimension)}/${Uri.encodeComponent(segment)}';

  /// Everything one artist plays on, as a list rather than as a screen
  /// about them. Its own location beneath the artist, because the
  /// artist's own is their screen: a stranger opening this gets the
  /// list, which is what the "Show all" above it promises.
  static String artistTracks(String pid) =>
      '${musicBucket(MusicDimension.artists, pid)}/tracks';

  static const playlists = '/playlists';

  /// Rule editor in create mode. Declared ahead of [playlist] so the
  /// literal wins over the `:pid` pattern.
  static const playlistRules = '$playlists/rules';
  static String playlist(String pid) => '$playlists/$pid';
  static String playlistEdit(String pid) => '$playlists/$pid/edit';

  static const podcasts = '/podcasts';
  static String show(String pid) => '$podcasts/$pid';

  /// One episode, beneath the show it belongs to.
  ///
  /// The show is in the path because an episode's ancestry is real: a
  /// stranger opening this gets the episode with its show underneath, so
  /// back lands on the show from a shared link exactly as it does from a
  /// tap, and the address bar follows the hop. The flat location this
  /// replaced could only be pushed, because `go` would have built the
  /// hub beneath it and leaving an episode landed on a list of shows.
  static String showEpisode(String showPid, String pid) =>
      '${show(showPid)}/episodes/$pid';

  /// The same episode for a caller with no show in hand.
  ///
  /// Search hits carry a pid, a kind, and display text and nothing else,
  /// so this is the location they can build; it also keeps the links the
  /// flat route minted before the show moved into the path working. A
  /// screen opened here has no ancestry, so it is pushed and leaves to
  /// the hub. [showEpisode] is what every caller that knows the show
  /// uses.
  static const episodePrefix = '/episodes/';
  static String episode(String pid) => '$episodePrefix$pid';

  /// The audiobook domain: a hub, and one book beneath it. The book's
  /// declared parent is the hub, so it is gone to from there and pushed
  /// from anywhere else (a search hit, a home shelf).
  static const books = '/books';
  static String book(String pid) => '$books/$pid';

  static const radio = '/radio';

  /// Songs kept off the air. A location a stranger can open and get
  /// their own list, like `/queue`, so it is gone to rather than pushed,
  /// and its declared parent is the hub it is reached from.
  static const radioSaved = '$radio/saved';

  /// What this device holds offline. Native only: the web build has no
  /// download manager, so the destination is not offered there.
  static const downloads = '/downloads';

  static const stats = '/stats';
  static const listenLog = '$stats/log';
  static const yearInReview = '$stats/year';

  /// A computed list of tracks (an instant mix, a similar-tracks answer).
  static const tracks = '/tracks';

  /// The full player: a view of whatever is playing, so it needs no
  /// payload and a reload lands back on it. Modal over whatever is
  /// underneath.
  static const nowPlaying = '/now-playing';

  /// The queue, full screen. A view of live state like the player, and
  /// modal for the same reason: below sidebar width there is no panel to
  /// put it in, and back closes it onto what was underneath.
  static const queue = '/queue';

  /// The track drawn large, and the player at arm's length. Views of
  /// what is playing like [nowPlaying], and declared for the same
  /// reason: each is a whole surface with a way out, reachable from a
  /// menu today and from the command palette next, and neither is a
  /// place a stranger's link can put somebody.
  static const visualizer = '/visualizer';
  static const carMode = '/car';

  /// Controlling a Connect session on another endpoint.
  static const remote = '/remote';

  /// Settings, and one location per section. A section is a place a
  /// stranger can open, so "it is under Playback" is a link rather than
  /// a set of directions.
  static const settings = '/settings';

  static String settingsSection(SettingsSection section) =>
      '$settings/${section.segment}';

  /// What this build is and what it is talking to. A location like any
  /// other section: a stranger opening it gets the page, which is the
  /// question 8.3 asks. Declared ahead of the `:section` pattern in the
  /// table so the literal wins over it.
  static const settingsAbout = '$settings/about';

  /// What the app caught and nobody saw. Beneath About because that is
  /// where a bug report is assembled, and a location rather than a push
  /// for the same reason About is one: somebody being asked for it can
  /// be sent straight here.
  static const settingsDefects = '$settingsAbout/defects';

  /// The caller's public links, beneath settings.
  ///
  /// Its ancestry is real: it is opened from the Account section's own
  /// row and nowhere else, so a stranger arriving here gets the page with
  /// settings underneath and back lands where the tap came from. It was
  /// declared beside settings before that, which is why it could only be
  /// pushed. Declared ahead of the `:section` pattern so the literal wins
  /// over it, the same way [settingsAbout] is.
  static const shares = '$settings/shares';

  /// The upload sessions list. No longer a nav destination: adding audio
  /// is the + control on the screen somebody is already on, and this is
  /// the oversight surface behind it - reached from a notification about
  /// an upload and from a review entry's own origin line. Still a
  /// location a stranger can open, which is what keeps both links
  /// working.
  static const uploads = '/uploads';

  /// Background tool tasks. Not under [admin]: whoever starts a task is
  /// offered this list by the snackbar that starts it, and uploading
  /// and acquiring are not administrator-only.
  static const tasks = '/tasks';

  /// What happened, and how this account is told about it. The bell is
  /// the quick peek at the first half; this is the surface that holds
  /// both, so "turn that off" is somewhere to go rather than a setting
  /// to hunt for.
  static const notifications = '/notifications';

  /// The queue of imports waiting on a decision. Its own location rather
  /// than a console section: an uploader sees their own entries here,
  /// which is not administration, and the screen an administrator opens
  /// daily should not be a level deeper than the ones they open monthly.
  static const review = '/review';
  static String reviewEntry(String entryId) => '$review/$entryId';

  /// Where the queue was declared while it was a console section. Kept
  /// because every console location is shareable and the web build puts
  /// it in the URL, so links minted then are somebody's bookmarks; the
  /// router answers both with a redirect onto [review]. Nothing builds
  /// one - it is here rather than in the table for the same reason
  /// [episodePrefix] is: a location this app used to mint is still a
  /// location, and they live in one place.
  static const legacyReview = '/admin/review';

  /// Preserved deep link into the metadata editor.
  static const metadataPrefix = '/metadata/';
  static String metadata(String pid) => '$metadataPrefix$pid';

  /// Preserved deep link to the editing prototype. Deliberately outside
  /// the signed-in shell: it is a self-contained rendering harness with
  /// no session of its own, and the e2e suite opens it cold.
  static const editingPrototype = '/prototype/editing';

  /// Administration: the admin console, and one location per section.
  /// Still no role redirect on these paths - a redirect would answer a
  /// pasted link by silently landing somebody somewhere else, which
  /// reads as a broken link rather than as a refusal. The console frame
  /// refuses in its own build instead, with an `EmptyState` that says so
  /// and a way back, so the location keeps its meaning for the account
  /// that shares it and stops offering panels that all 403 to the one
  /// that follows it.
  ///
  /// Every one of these is a place a stranger can open, which is what
  /// makes "it is under Backups" a link rather than a set of directions;
  /// the console frame wraps them all, so a section opened cold arrives
  /// with its own navigation around it.
  static const admin = '/admin';
  static const libraries = '$admin/libraries';
  static const genres = '$admin/genres';
  static const health = '$admin/health';
  static String healthRule(String rule) => '$health/$rule';
  static const diagnostics = '$admin/diagnostics';
  static const organize = '$admin/organize';
  static const users = '$admin/users';
  static const userEdit = '$users/edit';
  static const audit = '$admin/audit';

  /// Every account's share links, distinct from [shares], which is the
  /// caller's own: one is oversight, the other is a listener auditing
  /// what they published.
  static const adminShares = '$admin/shares';

  /// The server's own switches. Distinct from [settings], which is the
  /// listener's: one is what this instance does, the other is what this
  /// account prefers, and only administrators see the first.
  static const adminSettings = '$admin/settings';

  /// The server's notification destinations, distinct from the
  /// listener's own on the Integrations screen: one is where this
  /// instance reports operations events, the other is where an account
  /// asks to be told about its own.
  static const adminNotifications = '$admin/notifications';
  static const schedules = '$admin/schedules';
  static const backups = '$admin/backups';
  static const trash = '$admin/trash';
  static const migrate = '$admin/migrate';
}

/// A computed track list, held in memory because the server does not
/// mint an id for it: a mix is an answer, not an entity.
class TrackListArgs {
  const TrackListArgs({
    required this.title,
    required this.basis,
    required this.items,
    required this.idPrefix,
    this.sourceLabel = '',
  });

  final String title;
  final MixBasis basis;
  final List<ItemSummary> items;
  final String idPrefix;

  /// What the queue records this list as: its own name, not [title],
  /// since a stored label outlives the language it was built in. Empty
  /// where the answer is not the thing it was computed from.
  final String sourceLabel;
}

/// The account an admin opened, plus whether this is an approval of a
/// pending signup rather than an edit of a stored account.
class UserEditArgs {
  const UserEditArgs({required this.user, this.approve = false});

  final UserAccount user;
  final bool approve;
}

/// The name and visibility a smart playlist is about to be created with;
/// the rule editor owns creation because a smart playlist cannot exist
/// without a rule.
class RuleDraftArgs {
  const RuleDraftArgs({required this.name, required this.shared});

  final String name;
  final bool shared;
}

/// Opening a pushed destination without stacking a second copy of it.
extension WaxPushOnce on GoRouter {
  /// Pushes [location] unless it is already the top of the stack.
  ///
  /// The deck bar's expand is one `onTap`, and a double click fires it
  /// twice: without this the second click pushes a second player over
  /// the first, and backing out once looks like nothing happened. An
  /// `onDoubleTap` recognizer is not the fix - it would introduce the
  /// disambiguation delay and swallow the first tap, trading a
  /// hit-testing bug for a latency one. Two taps firing the action twice
  /// is correct behaviour once the action is idempotent.
  ///
  /// The check reads the match stack rather than the reported URL,
  /// because go_router deliberately keeps imperative pushes out of that
  /// URL and `optionURLReflectsImperativeAPIs` is not the way
  /// back. The stack does carry them.
  void pushOnce(String location) {
    final matches = routerDelegate.currentConfiguration.matches;
    if (matches.isNotEmpty && matches.last.matchedLocation == location) {
      return;
    }
    unawaited(push<void>(location));
  }
}

/// The same on a context, for call sites that do not outlive it.
extension WaxPushOnceContext on BuildContext {
  void pushOnce(String location) => GoRouter.of(this).pushOnce(location);
}

/// Leaving a screen that can be arrived at directly.
extension WaxLeave on GoRouter {
  /// Pops when something is underneath, and goes to [fallback] when
  /// nothing is.
  ///
  /// A screen that finishes by removing itself (a deleted playlist, a
  /// completed signup) can be the only page on the stack when a visitor
  /// opened its link directly. Popping then throws, and leaving them
  /// staring at what they just deleted is not an answer either.
  ///
  /// [result] reaches a caller awaiting the push only through the pop
  /// branch, which is the only branch that can have one: a push always
  /// leaves a page underneath, so a pending push future implies this
  /// pops. The fallback branch runs exactly when nobody pushed.
  void leave({String fallback = WaxRoute.home, Object? result}) {
    if (canPop()) {
      pop(result);
      return;
    }
    go(fallback);
  }
}

/// The same on a context, for call sites that do not outlive it.
extension WaxLeaveContext on BuildContext {
  void leave({String fallback = WaxRoute.home, Object? result}) =>
      GoRouter.of(this).leave(fallback: fallback, result: result);
}
