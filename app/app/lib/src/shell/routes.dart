import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../music/music_controllers.dart';

/// Every canonical location in the app, in one place.
///
/// Screens never type a path literal: they call these constants and
/// builders, so renaming a route is a single edit and the compiler finds
/// the callers. Paths follow the route map in the UI plan; the web build
/// keeps Flutter's default hash strategy for now, so these read as
/// `/#/podcasts/pc-...` in the address bar until the path-URL flip.
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

  static const playlists = '/playlists';

  /// Rule editor in create mode. Declared ahead of [playlist] so the
  /// literal wins over the `:pid` pattern.
  static const playlistRules = '$playlists/rules';
  static String playlist(String pid) => '$playlists/$pid';
  static String playlistEdit(String pid) => '$playlists/$pid/edit';

  static const podcasts = '/podcasts';
  static String show(String pid) => '$podcasts/$pid';
  static String episode(String pid) => '/episodes/$pid';

  static String book(String pid) => '/books/$pid';

  static const radio = '/radio';

  static const stats = '/stats';
  static const listenLog = '$stats/log';
  static const yearInReview = '$stats/year';

  /// A computed list of tracks (an instant mix, a similar-tracks answer).
  static const tracks = '/tracks';

  /// The full player: a view of whatever is playing, so it needs no
  /// payload and a reload lands back on it. Modal over whatever is
  /// underneath.
  static const nowPlaying = '/now-playing';

  /// Controlling a Connect session on another endpoint.
  static const remote = '/remote';

  static const settings = '/settings';
  static const shares = '/shares';
  static const uploads = '/uploads';

  /// Background tool tasks. Not under [admin]: whoever starts a task is
  /// offered this list by the snackbar that starts it, and uploading
  /// and acquiring are not administrator-only.
  static const tasks = '/tasks';

  /// Preserved deep link into the metadata editor.
  static const metadataPrefix = '/metadata/';
  static String metadata(String pid) => '$metadataPrefix$pid';

  /// Preserved deep link to the editing prototype. Deliberately outside
  /// the signed-in shell: it is a self-contained rendering harness with
  /// no session of its own, and the e2e suite opens it cold.
  static const editingPrototype = '/prototype/editing';

  /// Curation and administration. No role redirect lives on these paths:
  /// the menus that lead here already hide what an account cannot use,
  /// and the server refuses the calls regardless. A role-aware console
  /// shell is the admin phase's job.
  static const admin = '/admin';
  static const review = '$admin/review';
  static String reviewEntry(String entryId) => '$review/$entryId';
  static const health = '$admin/health';
  static String healthRule(String rule) => '$health/$rule';
  static const diagnostics = '$admin/diagnostics';
  static const organize = '$admin/organize';
  static const users = '$admin/users';
  static const userEdit = '$users/edit';
  static const audit = '$admin/audit';
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
  });

  final String title;
  final MixBasis basis;
  final List<ItemSummary> items;
  final String idPrefix;
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
