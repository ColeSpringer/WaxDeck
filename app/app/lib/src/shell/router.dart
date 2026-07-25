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
import '../library/browse_screen.dart';
import '../library/library_screen.dart';
import '../metadata/metadata_screen.dart';
import '../organize/organize_screen.dart';
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
import '../radio/radio_screen.dart';
import '../review/review_entry_screen.dart';
import '../review/review_screen.dart';
import '../settings/settings_screen.dart';
import '../sharing/shares_screen.dart';
import '../stats/listen_log_screen.dart';
import '../stats/stats_screen.dart';
import '../stats/year_in_review_screen.dart';
import '../sync/sync_providers.dart';
import '../tools/tasks_screen.dart';
import '../uploads/share_intake_gate.dart';
import '../uploads/uploads_screen.dart';
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
        routes: signedInRoutes,
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

/// Everything behind the session, listed apart from the shell that wraps
/// it so widget tests can mount one screen over the same table.
///
/// Every screen is a child of home rather than a sibling of it. That is
/// what makes an address work when it is the first thing a visitor
/// opens: `go` builds each declared ancestor beneath the target, so a
/// bookmarked book or the location handed back after a sign-in arrives
/// with the library underneath it, a back arrow, and a system back that
/// goes somewhere instead of out of the app. Pushing is unaffected,
/// since a push appends only the branch's leaf to the stack already
/// there.
final signedInRoutes = <RouteBase>[
  GoRoute(
    path: WaxRoute.home,
    builder: (context, state) => const LibraryScreen(),
    routes: [
      GoRoute(
        path: 'browse',
        builder: (context, state) => const BrowseScreen(),
        routes: [
          GoRoute(
            path: 'items',
            redirect: _requires<BrowseBucketArgs>(WaxRoute.browse),
            builder: (context, state) {
              final args = state.extra! as BrowseBucketArgs;
              return BrowseItemsScreen(
                dimension: args.dimension,
                bucket: args.bucket,
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: 'playlists',
        builder: (context, state) => const PlaylistsScreen(),
        routes: [
          // Declared ahead of ':pid' so the literal wins the match.
          GoRoute(
            path: 'rules',
            redirect: _requires<RuleDraftArgs>(WaxRoute.playlists),
            builder: (context, state) {
              final args = state.extra! as RuleDraftArgs;
              return RuleEditorScreen(
                createName: args.name,
                createShared: args.shared,
              );
            },
          ),
          GoRoute(
            path: ':pid',
            builder: (context, state) =>
                PlaylistScreen(pid: state.pathParameters['pid']!),
            routes: [
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
        path: 'podcasts',
        builder: (context, state) => const PodcastsScreen(),
        routes: [
          GoRoute(
            path: ':pid',
            builder: (context, state) =>
                ShowScreen(pid: state.pathParameters['pid']!),
          ),
        ],
      ),
      GoRoute(
        path: 'episodes/:pid',
        builder: (context, state) =>
            EpisodeScreen(pid: state.pathParameters['pid']!),
      ),
      GoRoute(
        path: 'books/:pid',
        builder: (context, state) =>
            BookScreen(pid: state.pathParameters['pid']!),
      ),
      GoRoute(path: 'radio', builder: (context, state) => const RadioScreen()),
      GoRoute(
        path: 'stats',
        builder: (context, state) => const StatsScreen(),
        routes: [
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
        path: 'tracks',
        redirect: _requires<TrackListArgs>(WaxRoute.home),
        builder: (context, state) {
          final args = state.extra! as TrackListArgs;
          return TrackListScreen(
            title: args.title,
            basis: args.basis,
            items: args.items,
            idPrefix: args.idPrefix,
          );
        },
      ),
      GoRoute(
        path: 'now-playing',
        builder: (context, state) => const PlayerScreen(),
      ),
      GoRoute(
        path: 'remote',
        redirect: _requires<PlaybackSessionInfo>(WaxRoute.home),
        builder: (context, state) =>
            RemoteControlScreen(initial: state.extra! as PlaybackSessionInfo),
      ),
      GoRoute(
        path: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: 'shares',
        builder: (context, state) => const SharesScreen(),
      ),
      GoRoute(
        path: 'uploads',
        builder: (context, state) => const UploadsScreen(),
      ),
      // Not under /admin: anyone who can start a task (an upload, an
      // acquisition) is offered this list from the snackbar that starts
      // it, administrator or not.
      GoRoute(path: 'tasks', builder: (context, state) => const TasksScreen()),
      GoRoute(
        path: 'metadata/:pid',
        builder: (context, state) =>
            MetadataScreen(pid: state.pathParameters['pid']!),
      ),
      GoRoute(
        path: 'admin/review',
        builder: (context, state) => const ReviewScreen(),
        routes: [
          GoRoute(
            path: ':entryId',
            builder: (context, state) =>
                ReviewEntryScreen(entryId: state.pathParameters['entryId']!),
          ),
        ],
      ),
      GoRoute(
        path: 'admin/health',
        builder: (context, state) => const HealthScreen(),
        routes: [
          GoRoute(
            path: ':rule',
            builder: (context, state) =>
                HealthIssuesScreen(rule: state.pathParameters['rule']!),
          ),
        ],
      ),
      GoRoute(
        path: 'admin/diagnostics',
        builder: (context, state) => const DiagnosticsScreen(),
      ),
      GoRoute(
        path: 'admin/organize',
        builder: (context, state) => const OrganizeScreen(),
      ),
      GoRoute(
        path: 'admin/users',
        builder: (context, state) => const UsersScreen(),
        routes: [
          GoRoute(
            path: 'edit',
            redirect: _requires<UserEditArgs>(WaxRoute.users),
            builder: (context, state) {
              final args = state.extra! as UserEditArgs;
              return UserEditScreen(user: args.user, approve: args.approve);
            },
          ),
        ],
      ),
      GoRoute(
        path: 'admin/audit',
        builder: (context, state) => const AuditScreen(),
      ),
      GoRoute(
        path: 'admin/backups',
        builder: (context, state) => const BackupsScreen(),
      ),
      GoRoute(
        path: 'admin/trash',
        builder: (context, state) => const TrashScreen(),
      ),
      GoRoute(
        path: 'admin/migrate',
        builder: (context, state) => const MigrateScreen(),
      ),
    ],
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
    // The notifier, not its state: playback has to be listening to the
    // queue for the whole session, but what it is playing changes
    // constantly and nothing under here should rebuild for that.
    ref.watch(nowPlayingProvider.notifier);
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
