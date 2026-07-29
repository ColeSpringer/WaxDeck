import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../admin/audit_screen.dart';
import '../admin/backups_screen.dart';
import '../admin/migrate_screen.dart';
import '../admin/trash_screen.dart';
import '../admin/user_edit_screen.dart';
import '../admin/users_screen.dart';
import '../auth/auth_controller.dart';
import '../auth/login_screen.dart';
import '../auth/setup_screen.dart';
import '../auth/signup_screen.dart';
import '../books/book_screen.dart';
import '../connect/remote_screen.dart';
import '../discovery/track_list_screen.dart';
import '../health/diagnostics_screen.dart';
import '../health/health_screen.dart';
import '../library/library_screen.dart';
import '../metadata/metadata_screen.dart';
import '../music/album_screen.dart';
import '../music/artist_screen.dart';
import '../music/index_screen.dart';
import '../music/listing_screen.dart';
import '../music/music_controllers.dart';
import '../music/music_hub_screen.dart';
import '../organize/organize_screen.dart';
import '../player/autoplay_gate.dart';
import '../player/now_playing_controller.dart';
import '../player/player_screen.dart';
import '../playlists/playlist_screen.dart';
import '../playlists/playlists_screen.dart';
import '../playlists/rule_editor_screen.dart';
import '../podcasts/episode_screen.dart';
import '../podcasts/podcasts_screen.dart';
import '../podcasts/show_screen.dart';
import '../prototype/editing_prototype_screen.dart';
import '../queue/queue_persistence.dart';
import '../queue/queue_refiller.dart';
import '../queue/queue_screen.dart';
import '../radio/radio_screen.dart';
import '../review/review_entry_screen.dart';
import '../review/review_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';
import '../sharing/shares_screen.dart';
import '../stats/listen_log_screen.dart';
import '../stats/stats_screen.dart';
import '../stats/year_in_review_screen.dart';
import '../sync/sync_binder.dart';
import '../tools/tasks_screen.dart';
import '../uploads/share_intake_gate.dart';
import '../uploads/uploads_screen.dart';
import 'adaptive_shell.dart';
import 'routes.dart';

/// The app's router, built once per provider container.
///
/// A [GoRouter] holds navigation state, so this provider must never
/// rebuild: it reads its inputs instead of watching them, and the auth
/// redirect re-runs through [_SessionRefresh] rather than through a new
/// router.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _SessionRefresh(ref);
  final router = GoRouter(
    initialLocation: WaxRoute.home,
    refreshListenable: refresh,
    redirect: (context, state) => _redirect(ref, state),
    errorBuilder: (context, state) => const _NotFoundScreen(),
    routes: [
      ...publicRoutes,
      // Built here rather than in a shared list: a ShellRoute given no
      // key mints its own navigator GlobalKey, and a list held in a
      // top-level final would hand that one key to every router in the
      // process.
      ShellRoute(
        navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'signed-in'),
        builder: (context, state, child) => _SignedInScope(child: child),
        routes: shellRoutes(),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

/// Re-runs the router's redirect when the answers it depends on change.
///
/// Signing in and out moves a visitor between two different sets of
/// reachable locations; the first-run probe decides which of `/setup`
/// and `/login` a signed-out one lands on, and it is resolved fresh
/// after a sign-out, so the redirect has to be told when it settles.
/// Listening costs one cheap `bootstrapStatus` call on a signed-in
/// launch that would otherwise not make it.
class _SessionRefresh extends ChangeNotifier {
  _SessionRefresh(Ref ref) {
    _subscriptions = [
      ref.listen(authControllerProvider, (_, _) => notifyListeners()),
      ref.listen(bootstrapRequiredProvider, (_, _) => notifyListeners()),
    ];
  }

  // Closed before the notifier is, so a late answer cannot notify a
  // disposed listener at all rather than being caught doing it.
  late final List<ProviderSubscription<Object?>> _subscriptions;

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.close();
    }
    super.dispose();
  }
}

/// Whether [location] is somewhere this app can send a visitor. A `from`
/// parameter arrives in the URL, so it is treated as input: only in-app
/// absolute paths pass, never a scheme, and never a second leading
/// slash or backslash.
///
/// Three things get a location past a naive check. Browsers read
/// `/\host` the way they read `//host` for http(s), so the backslash
/// form is the usual way around a `//`-only test; and they strip tab,
/// newline, and carriage return from a URL wherever those appear, so
/// `/<tab>/host` becomes `//host` on arrival. A real WaxDeck location
/// contains none of them, so all three are refused rather than
/// normalized. Nothing today would follow such a value off-origin (the
/// hash strategy keeps it in the fragment, and `pushState` refuses a
/// cross-origin URL), but it is user input on its way into a location,
/// and the path-URL flip is coming.
bool _isInAppLocation(String location) =>
    location.startsWith('/') &&
    !location.startsWith('//') &&
    !location.startsWith(r'/\') &&
    !location.contains(RegExp(r'[\t\n\r]'));

/// The session gate, as a redirect.
///
/// Signed out lands on setup (no accounts yet) or login, remembering
/// where the visitor was headed; signing in returns them there. Signed
/// in, the auth screens are unreachable.
String? _redirect(Ref ref, GoRouterState state) {
  final location = state.matchedLocation;
  // The prototype harness carries no session and is opened cold.
  if (location == WaxRoute.editingPrototype) return null;

  final signedIn =
      ref.read(authControllerProvider).value?.authenticated ?? false;
  if (signedIn) {
    if (!WaxRoute.authLocations.contains(location)) return null;
    final from = state.uri.queryParameters[WaxRoute.fromParam];
    return from != null && _isInAppLocation(from) ? from : WaxRoute.home;
  }

  // A server with no accounts has exactly one thing to offer. An
  // unresolved probe reads as "has accounts" and lands on login;
  // _SessionRefresh brings the redirect back when it answers.
  final needsSetup = ref.read(bootstrapRequiredProvider).value ?? false;
  if (needsSetup) return location == WaxRoute.setup ? null : WaxRoute.setup;

  if (location == WaxRoute.login || location == WaxRoute.signup) return null;
  final target = Uri(
    path: WaxRoute.login,
    queryParameters: location == WaxRoute.home
        ? null
        : {WaxRoute.fromParam: state.uri.toString()},
  );
  return target.toString();
}

/// Sends a route that needs an in-memory payload back to a real screen
/// when it has none: a reload or a restored history entry drops [extra],
/// and rendering half a screen is worse than landing one level up.
///
/// This is a redirect, so it replaces the location on a `go` or a
/// restore, which is where a payload actually goes missing. A `push`
/// with no payload would instead stack the fallback on top of what is
/// already there; nothing does that, because every one of these routes
/// is pushed from a call site holding the payload, and the redirect is
/// what makes arriving any other way land somewhere real.
GoRouterRedirect _requires<T>(String fallback) =>
    (context, state) => state.extra is T ? null : fallback;

// The screens that read a payload out of the route. Named rather than
// inlined so the table below reads as a table: each of these is three or
// four lines of unpacking that would otherwise sit in the middle of the
// branch it belongs to.

/// One dimension's index, and beneath it whatever one of its buckets
/// opens onto.
///
/// Built rather than typed out four times: the four dimensions differ in
/// their wire name and their label and in nothing the router cares about,
/// and a table with four near-identical branches is where the fifth one
/// gets subtly wrong.
///
/// The two entity dimensions open onto the entity itself rather than
/// onto its filtered listing. Same location either way — the contract
/// makes a bucket's key its entity pid behind a type prefix, so one
/// address names the artist and filters the list — but an artist is a
/// screen about an artist, not a list of their tracks, and the list
/// still has a location one level down.
GoRoute _musicIndexRoute(MusicDimension dimension) => GoRoute(
  path: dimension.segment,
  builder: (context, state) => MusicIndexScreen(dimension: dimension),
  routes: <RouteBase>[
    GoRoute(
      path: ':key',
      builder: (context, state) => _bucketScreen(dimension, state),
      routes: <RouteBase>[
        if (dimension == MusicDimension.artists)
          GoRoute(
            path: 'tracks',
            builder: (context, state) => MusicListingScreen(
              dimension: dimension,
              segment: state.pathParameters['key']!,
              label: state.extra is String ? state.extra! as String : null,
            ),
          ),
      ],
    ),
  ],
);

/// What one bucket of [dimension] opens onto. `extra` carries the label
/// the caller had: a hint, never a dependency, since a reload and a
/// shared link both drop it and every one of these screens names itself
/// from what it loads.
Widget _bucketScreen(MusicDimension dimension, GoRouterState state) {
  final segment = state.pathParameters['key']!;
  final label = state.extra is String ? state.extra! as String : null;
  // An entity screen wants an entity pid, and the handle in the location
  // is only one when the bucket carried an `entityPid`: a bucket without
  // one travels as its bare key, and the bucket a dimension is absent
  // from travels as a sentinel. The prefix is the test, and it is the
  // same one `musicFacetKey` keys on to turn a handle back into a facet
  // key — so the two cannot disagree about what the segment is.
  final prefix = dimension.entityPrefix;
  if (prefix != null && segment.startsWith(prefix)) {
    switch (dimension) {
      case MusicDimension.artists:
        return ArtistScreen(pid: segment, label: label);
      case MusicDimension.albums:
        return AlbumScreen(pid: segment, label: label);
      case MusicDimension.genres:
      case MusicDimension.years:
        break;
    }
  }
  return MusicListingScreen(
    dimension: dimension,
    segment: segment,
    label: label,
  );
}

Widget _trackList(BuildContext context, GoRouterState state) {
  final args = state.extra! as TrackListArgs;
  return TrackListScreen(
    title: args.title,
    basis: args.basis,
    items: args.items,
    idPrefix: args.idPrefix,
  );
}

Widget _ruleDraft(BuildContext context, GoRouterState state) {
  final args = state.extra! as RuleDraftArgs;
  return RuleEditorScreen(createName: args.name, createShared: args.shared);
}

Widget _userEdit(BuildContext context, GoRouterState state) {
  final args = state.extra! as UserEditArgs;
  return UserEditScreen(user: args.user, approve: args.approve);
}

/// Locations that do not need a session: the auth surfaces themselves,
/// and the prototype harness.
final publicRoutes = <RouteBase>[
  GoRoute(
    path: WaxRoute.login,
    builder: (context, state) => const LoginScreen(),
  ),
  GoRoute(
    path: WaxRoute.setup,
    builder: (context, state) => const SetupScreen(),
  ),
  GoRoute(
    path: WaxRoute.signup,
    builder: (context, state) => const SignupScreen(),
  ),
  GoRoute(
    path: WaxRoute.editingPrototype,
    builder: (context, state) => const EditingPrototypeScreen(),
  ),
];

/// Everything behind the session, listed apart from the shell route that
/// wraps it so widget tests can mount one screen over the same table.
///
/// A function rather than a list: every branch mints a navigator key and
/// the shell route holds state of its own, so a value held in a top-level
/// final would hand one router's navigation state to the next.
///
/// The shape is what makes the address bar follow a destination. Each
/// domain gets a branch, so its stack survives a trip to another one, and
/// everything that is not a domain shares the last branch: a settings
/// visit must not become what the Home tab restores. Locations that only
/// make sense on top of what is already there — the player, a computed
/// track list, a remote session — are declared outside the shell, on the
/// signed-in navigator, so they cover the chrome and back closes them.
///
/// One consequence worth knowing, narrowed by a later phase: a book lives
/// in the home branch, because that is where books are reached from until
/// there is a books hub, so opening one from Browse lights Home.
List<RouteBase> shellRoutes() => <RouteBase>[
  StatefulShellRoute.indexedStack(
    builder: (context, state, navigationShell) =>
        AdaptiveShell(shell: navigationShell, location: state.uri.path),
    branches: <StatefulShellBranch>[
      // Home. Books hang off it: the library grid is where they are
      // reached from until the audiobooks hub exists.
      StatefulShellBranch(
        routes: <RouteBase>[
          GoRoute(
            path: WaxRoute.home,
            builder: (context, state) => const LibraryScreen(),
            routes: <RouteBase>[
              GoRoute(
                path: 'books/:pid',
                builder: (context, state) =>
                    BookScreen(pid: state.pathParameters['pid']!),
              ),
            ],
          ),
        ],
      ),
      // Music: the hub, an index per dimension, and a listing per bucket.
      // Every segment is a literal, so nothing here is ambiguous with
      // `/music/tracks` and no route has to be declared before another to
      // win a match.
      StatefulShellBranch(
        routes: <RouteBase>[
          GoRoute(
            path: WaxRoute.music,
            builder: (context, state) => const MusicHubScreen(),
            routes: <RouteBase>[
              GoRoute(
                path: 'tracks',
                builder: (context, state) => const MusicListingScreen(),
              ),
              for (final dimension in MusicDimension.values)
                _musicIndexRoute(dimension),
            ],
          ),
        ],
      ),
      StatefulShellBranch(
        routes: <RouteBase>[
          GoRoute(
            path: WaxRoute.podcasts,
            builder: (context, state) => const PodcastsScreen(),
            routes: <RouteBase>[
              GoRoute(
                path: ':pid',
                builder: (context, state) =>
                    ShowScreen(pid: state.pathParameters['pid']!),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'episodes/:episodePid',
                    builder: (context, state) => EpisodeScreen(
                      pid: state.pathParameters['episodePid']!,
                      showPid: state.pathParameters['pid']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // The same episode with no show around it, for a caller that
          // has only a pid: a search hit, and a link minted before the
          // show moved into the path. It resolves to the screen and
          // leaves to the hub, which is the honest answer when nothing
          // names an ancestor.
          GoRoute(
            path: '${WaxRoute.episodePrefix}:pid',
            builder: (context, state) =>
                EpisodeScreen(pid: state.pathParameters['pid']!),
          ),
        ],
      ),
      StatefulShellBranch(
        routes: <RouteBase>[
          GoRoute(
            path: WaxRoute.radio,
            builder: (context, state) => const RadioScreen(),
          ),
        ],
      ),
      // Everything that is not a domain. Nothing calls `goBranch` on this
      // one — its destinations are reached by location — so it needs no
      // root of its own.
      StatefulShellBranch(
        routes: <RouteBase>[
          // Search is here rather than in a domain because it is over all
          // of them: leaving it must not rewrite the stack of whichever
          // one the visitor came from.
          GoRoute(
            path: WaxRoute.search,
            builder: (context, state) => SearchScreen(
              initialQuery:
                  state.uri.queryParameters[WaxRoute.searchParam] ?? '',
            ),
          ),
          GoRoute(
            path: WaxRoute.playlists,
            builder: (context, state) => const PlaylistsScreen(),
            routes: <RouteBase>[
              // Declared ahead of ':pid' so the literal wins the match.
              GoRoute(
                path: 'rules',
                redirect: _requires<RuleDraftArgs>(WaxRoute.playlists),
                builder: _ruleDraft,
              ),
              GoRoute(
                path: ':pid',
                builder: (context, state) =>
                    PlaylistScreen(pid: state.pathParameters['pid']!),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'edit',
                    redirect: (context, state) => state.extra is Playlist
                        ? null
                        : WaxRoute.playlist(state.pathParameters['pid']!),
                    builder: (context, state) =>
                        RuleEditorScreen(editing: state.extra! as Playlist),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: WaxRoute.stats,
            builder: (context, state) => const StatsScreen(),
            routes: <RouteBase>[
              GoRoute(
                path: 'log',
                builder: (context, state) => const ListenLogScreen(),
              ),
              GoRoute(
                path: 'year',
                builder: (context, state) => const YearInReviewScreen(),
              ),
            ],
          ),
          GoRoute(
            path: WaxRoute.settings,
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: WaxRoute.shares,
            builder: (context, state) => const SharesScreen(),
          ),
          GoRoute(
            path: WaxRoute.uploads,
            builder: (context, state) => const UploadsScreen(),
          ),
          GoRoute(
            path: WaxRoute.tasks,
            builder: (context, state) => const TasksScreen(),
          ),
          GoRoute(
            path: '/metadata/:pid',
            builder: (context, state) =>
                MetadataScreen(pid: state.pathParameters['pid']!),
          ),
          GoRoute(
            path: WaxRoute.review,
            builder: (context, state) => const ReviewScreen(),
            routes: <RouteBase>[
              GoRoute(
                path: ':entryId',
                builder: (context, state) => ReviewEntryScreen(
                  entryId: state.pathParameters['entryId']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: WaxRoute.health,
            builder: (context, state) => const HealthScreen(),
            routes: <RouteBase>[
              GoRoute(
                path: ':rule',
                builder: (context, state) =>
                    HealthIssuesScreen(rule: state.pathParameters['rule']!),
              ),
            ],
          ),
          GoRoute(
            path: WaxRoute.diagnostics,
            builder: (context, state) => const DiagnosticsScreen(),
          ),
          GoRoute(
            path: WaxRoute.organize,
            builder: (context, state) => const OrganizeScreen(),
          ),
          GoRoute(
            path: WaxRoute.users,
            builder: (context, state) => const UsersScreen(),
            routes: <RouteBase>[
              GoRoute(
                path: 'edit',
                redirect: _requires<UserEditArgs>(WaxRoute.users),
                builder: _userEdit,
              ),
            ],
          ),
          GoRoute(
            path: WaxRoute.audit,
            builder: (context, state) => const AuditScreen(),
          ),
          GoRoute(
            path: WaxRoute.backups,
            builder: (context, state) => const BackupsScreen(),
          ),
          GoRoute(
            path: WaxRoute.trash,
            builder: (context, state) => const TrashScreen(),
          ),
          GoRoute(
            path: WaxRoute.migrate,
            builder: (context, state) => const MigrateScreen(),
          ),
        ],
      ),
    ],
  ),
  // Overlays. Pushed onto the signed-in navigator, so they sit over the
  // chrome and over whichever branch is showing; each carries a payload
  // or is a view of what is playing, so none of them belongs in the
  // address bar and every one resolves to something real when typed.
  GoRoute(
    path: WaxRoute.nowPlaying,
    builder: (context, state) => const PlayerScreen(),
  ),
  GoRoute(
    path: WaxRoute.queue,
    builder: (context, state) => const QueueScreen(),
  ),
  GoRoute(
    path: WaxRoute.tracks,
    redirect: _requires<TrackListArgs>(WaxRoute.home),
    builder: _trackList,
  ),
  GoRoute(
    path: WaxRoute.remote,
    redirect: _requires<PlaybackSessionInfo>(WaxRoute.home),
    builder: (context, state) =>
        RemoteControlScreen(initial: state.extra! as PlaybackSessionInfo),
  ),
];

/// Wraps every signed-in screen, so the machinery that belongs to a
/// session lives exactly as long as the session does.
///
/// The sync engine (or the web invalidation listener) starts when this
/// mounts and stops when the auth redirect replaces it with the login
/// screen; share-sheet payloads and queue persistence land here for the
/// same reason.
class _SignedInScope extends ConsumerWidget {
  const _SignedInScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(syncBinderProvider);
    ref.watch(queuePersistenceProvider);
    ref.watch(queueRefillProvider);
    // The notifier, not its state: playback has to be listening to the
    // queue for the whole session, but what it is playing changes
    // constantly and nothing under here should rebuild for that. The
    // autoplay gate is here for the other half of that reason: it has to
    // be listening before the refusal it exists to catch, and the deck
    // bar it feeds is mounted only once there is something to show.
    ref.watch(nowPlayingProvider.notifier);
    ref.watch(autoplayBlockedProvider.notifier);
    return ShareIntakeGate(child: child);
  }
}

/// A location the app has no screen for: a stale bookmark, a typo in
/// the fragment, a link from a newer build.
class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('That page does not exist.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.go(WaxRoute.home),
              child: const Text('Go home'),
            ),
          ],
        ),
      ),
    );
  }
}
