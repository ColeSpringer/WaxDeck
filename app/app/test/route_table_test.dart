import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/admin/audit_screen.dart';
import 'package:waxdeck/src/admin/backups_screen.dart';
import 'package:waxdeck/src/admin/migrate_screen.dart';
import 'package:waxdeck/src/admin/trash_screen.dart';
import 'package:waxdeck/src/admin/users_screen.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/books/book_screen.dart';
import 'package:waxdeck/src/health/diagnostics_screen.dart';
import 'package:waxdeck/src/health/health_screen.dart';
import 'package:waxdeck/src/library/browse_screen.dart';
import 'package:waxdeck/src/library/library_screen.dart';
import 'package:waxdeck/src/metadata/metadata_screen.dart';
import 'package:waxdeck/src/organize/organize_screen.dart';
import 'package:waxdeck/src/player/player_screen.dart';
import 'package:waxdeck/src/playlists/playlist_screen.dart';
import 'package:waxdeck/src/playlists/playlists_screen.dart';
import 'package:waxdeck/src/podcasts/episode_screen.dart';
import 'package:waxdeck/src/podcasts/podcasts_screen.dart';
import 'package:waxdeck/src/podcasts/show_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/radio/radio_screen.dart';
import 'package:waxdeck/src/review/review_entry_screen.dart';
import 'package:waxdeck/src/review/review_screen.dart';
import 'package:waxdeck/src/settings/settings_screen.dart';
import 'package:waxdeck/src/sharing/shares_screen.dart';
import 'package:waxdeck/src/shell/adaptive_shell.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/stats/listen_log_screen.dart';
import 'package:waxdeck/src/stats/stats_screen.dart';
import 'package:waxdeck/src/stats/year_in_review_screen.dart';
import 'package:waxdeck/src/tools/tasks_screen.dart';
import 'package:waxdeck/src/uploads/uploads_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

const _user = WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']);

/// Every location a caller can build, and the screen it must land on.
///
/// The table declares its paths as relative segments and `WaxRoute`
/// builds them as absolute strings; this is what keeps the two from
/// drifting apart, and what catches a route that stops resolving at all
/// (go_router answers an unmatched location with the error screen, not
/// an exception).
final _locations = <String, Type>{
  WaxRoute.home: LibraryScreen,
  WaxRoute.browse: BrowseScreen,
  WaxRoute.playlists: PlaylistsScreen,
  WaxRoute.playlist('pl-1'): PlaylistScreen,
  WaxRoute.podcasts: PodcastsScreen,
  WaxRoute.show('pc-1'): ShowScreen,
  WaxRoute.episode('ep-1'): EpisodeScreen,
  WaxRoute.book('bk-1'): BookScreen,
  WaxRoute.radio: RadioScreen,
  // A view of whatever is playing, so it carries no payload and a
  // reload lands back on it.
  WaxRoute.nowPlaying: PlayerScreen,
  WaxRoute.stats: StatsScreen,
  WaxRoute.listenLog: ListenLogScreen,
  WaxRoute.yearInReview: YearInReviewScreen,
  WaxRoute.settings: SettingsScreen,
  WaxRoute.shares: SharesScreen,
  WaxRoute.uploads: UploadsScreen,
  WaxRoute.tasks: TasksScreen,
  WaxRoute.metadata('tr-1'): MetadataScreen,
  WaxRoute.review: ReviewScreen,
  WaxRoute.reviewEntry('re-1'): ReviewEntryScreen,
  WaxRoute.health: HealthScreen,
  WaxRoute.healthRule('missing-artwork'): HealthIssuesScreen,
  WaxRoute.diagnostics: DiagnosticsScreen,
  WaxRoute.organize: OrganizeScreen,
  WaxRoute.users: UsersScreen,
  WaxRoute.audit: AuditScreen,
  WaxRoute.backups: BackupsScreen,
  WaxRoute.trash: TrashScreen,
  WaxRoute.migrate: MigrateScreen,
};

/// The routes that carry an in-memory payload, and where each sends a
/// visitor who arrives without one (a reload, a restored history entry,
/// a guessed URL). `extra` never survives that trip, so every one of
/// them has to land somewhere real.
final _payloadRoutes = <String, String>{
  WaxRoute.tracks: WaxRoute.home,
  WaxRoute.remote: WaxRoute.home,
  WaxRoute.browseItems: WaxRoute.browse,
  WaxRoute.playlistRules: WaxRoute.playlists,
  WaxRoute.playlistEdit('pl-1'): WaxRoute.playlist('pl-1'),
  WaxRoute.userEdit: WaxRoute.users,
};

/// Locations the shell's table declares beneath another one, and so the
/// only ones that answer a back affordance there.
///
/// The rest are a branch's own top-level routes: a destination is not a
/// stack, and a shell that offered "back" from one would be lying. The old
/// navigation declares everything under home instead, so there every
/// location but home has something underneath.
final _stackedInShell = <String>{
  WaxRoute.book('bk-1'),
  WaxRoute.show('pc-1'),
  WaxRoute.playlist('pl-1'),
  WaxRoute.listenLog,
  WaxRoute.yearInReview,
  WaxRoute.reviewEntry('re-1'),
  WaxRoute.healthRule('missing-artwork'),
};

Future<GoRouter> _pumpApp(WidgetTester tester, {required bool newShell}) async {
  final container = ProviderContainer(
    overrides: [
      newShellProvider.overrideWithValue(newShell),
      repositoryProvider.overrideWithValue(
        FakeRepository(
          sessionState: const SessionState(authenticated: true, user: _user),
        ),
      ),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const WaxDeckApp()),
  );
  await tester.pumpAndSettle();
  return container.read(routerProvider);
}

void main() {
  // Both tables carry every location, which is what keeps them from
  // drifting apart while the flag exists. The old half goes with the flag.
  for (final newShell in <bool>[false, true]) {
    final table = newShell ? 'the shell' : 'the old navigation';

    testWidgets('every declared location resolves to its screen under $table', (
      tester,
    ) async {
      final router = await _pumpApp(tester, newShell: newShell);
      for (final entry in _locations.entries) {
        router.go(entry.key);
        await tester.pumpAndSettle();

        expect(
          find.byType(entry.value),
          findsOneWidget,
          reason: '${entry.key} should render ${entry.value}',
        );
        expect(
          router.canPop(),
          newShell
              ? _stackedInShell.contains(entry.key)
              : entry.key != WaxRoute.home,
          reason: '${entry.key} back affordance under $table',
        );
      }
    });

    testWidgets(
      'a payload route opened without one lands one level up under $table',
      (tester) async {
        final router = await _pumpApp(tester, newShell: newShell);
        for (final entry in _payloadRoutes.entries) {
          router.go(entry.key);
          await tester.pumpAndSettle();

          expect(
            router.routerDelegate.currentConfiguration.uri.toString(),
            entry.value,
            reason: '${entry.key} without extra',
          );
        }
      },
    );
  }

  test('the shell declares one branch per domain, in the chrome order', () {
    // `goBranch` takes a number, so the chrome's list and the router's
    // branches are one contract split in two.
    final branches = shellRoutes()
        .whereType<StatefulShellRoute>()
        .single
        .branches;
    expect(branches.length, waxShellBranches.length + 1);
    for (var i = 0; i < waxShellBranches.length; i++) {
      expect(
        branches[i].defaultRoute?.path,
        waxShellBranches[i].location,
        reason: 'branch $i',
      );
    }
    // The last branch is the shared one and names no destination, so
    // nothing calls `goBranch` on it: its own first route would answer.
    expect(
      waxShellBranches.length,
      branches.length - 1,
      reason: 'everything that is not a domain shares the last branch',
    );
  });

  test('every destination the chrome offers is a location under test', () {
    // A destination pointing somewhere no test resolves is how a dead
    // sidebar row ships.
    for (final target in WaxNavTarget.values) {
      expect(
        _locations.keys,
        contains(target.location),
        reason: '${target.name} points at ${target.location}',
      );
    }
  });
}
