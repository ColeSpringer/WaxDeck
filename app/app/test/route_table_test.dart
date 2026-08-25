import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/admin/admin_shares_screen.dart';
import 'package:waxdeck/src/admin/audit_screen.dart';
import 'package:waxdeck/src/admin/dashboard_screen.dart';
import 'package:waxdeck/src/admin/genres_screen.dart';
import 'package:waxdeck/src/admin/libraries_screen.dart';
import 'package:waxdeck/src/admin/schedules_screen.dart';
import 'package:waxdeck/src/admin/server_settings_screen.dart';
import 'package:waxdeck/src/admin/backups_screen.dart';
import 'package:waxdeck/src/admin/migrate_screen.dart';
import 'package:waxdeck/src/admin/notifications_screen.dart';
import 'package:waxdeck/src/admin/trash_screen.dart';
import 'package:waxdeck/src/admin/users_screen.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/books/book_screen.dart';
import 'package:waxdeck/src/books/books_screen.dart';
import 'package:waxdeck/src/downloads/downloads_screen.dart';
import 'package:waxdeck/src/health/diagnostics_screen.dart';
import 'package:waxdeck/src/health/health_screen.dart';
import 'package:waxdeck/src/home/home_screen.dart';
import 'package:waxdeck/src/music/album_screen.dart';
import 'package:waxdeck/src/music/artist_screen.dart';
import 'package:waxdeck/src/music/index_screen.dart';
import 'package:waxdeck/src/music/listing_screen.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/music/music_hub_screen.dart';
import 'package:waxdeck/src/metadata/metadata_screen.dart';
import 'package:waxdeck/src/metadata/release_workbench.dart';
import 'package:waxdeck/src/notifications/notifications_screen.dart';
import 'package:waxdeck/src/organize/organize_screen.dart';
import 'package:waxdeck/src/player/car_mode_screen.dart';
import 'package:waxdeck/src/player/player_screen.dart';
import 'package:waxdeck/src/player/visualizer_screen.dart';
import 'package:waxdeck/src/playlists/playlist_screen.dart';
import 'package:waxdeck/src/playlists/playlists_screen.dart';
import 'package:waxdeck/src/podcasts/episode_screen.dart';
import 'package:waxdeck/src/podcasts/podcasts_screen.dart';
import 'package:waxdeck/src/podcasts/show_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/radio/radio_saved_screen.dart';
import 'package:waxdeck/src/radio/radio_screen.dart';
import 'package:waxdeck/src/review/review_screen.dart';
import 'package:waxdeck/src/search/search_screen.dart';
import 'package:waxdeck/src/diagnostics/defect_log_screen.dart';
import 'package:waxdeck/src/settings/about_screen.dart';
import 'package:waxdeck/src/settings/settings_registry.dart';
import 'package:waxdeck/src/settings/settings_screen.dart';
import 'package:waxdeck/src/settings/settings_section_screen.dart';
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

/// A bucket handle of the shape [dimension] mints for a bucket that has
/// an entity behind it: the entity's pid for the two that are entities,
/// a bare key for the two that are not.
String _entityHandle(MusicDimension dimension) =>
    dimension.entityPrefix == null ? 'key-1' : '${dimension.entityPrefix}1';

/// Every location a caller can build, and the screen it must land on.
///
/// The table declares its paths as relative segments and `WaxRoute`
/// builds them as absolute strings; this is what keeps the two from
/// drifting apart, and what catches a route that stops resolving at all
/// (go_router answers an unmatched location with the error screen, not
/// an exception).
final _locations = <String, Type>{
  WaxRoute.home: HomeScreen,
  WaxRoute.search: SearchScreen,
  WaxRoute.searchFor('nightjar'): SearchScreen,
  WaxRoute.music: MusicHubScreen,
  WaxRoute.musicTracks: MusicListingScreen,
  for (final dimension in MusicDimension.values) ...<String, Type>{
    WaxRoute.musicIndex(dimension): MusicIndexScreen,
    // A bucket of an entity dimension opens the entity itself; the two
    // that are not entities open the filtered listing. The handle is
    // what says which: it is a prefixed pid only when the bucket carried
    // an entity.
    WaxRoute.musicBucket(
      dimension,
      _entityHandle(dimension),
    ): switch (dimension) {
      MusicDimension.artists => ArtistScreen,
      MusicDimension.albums => AlbumScreen,
      // A release group is an entity and travels as its pid, but has no
      // screen of its own, so it opens the listing like the two that are
      // not entities.
      MusicDimension.releaseGroups ||
      MusicDimension.genres ||
      MusicDimension.years => MusicListingScreen,
    },
    // A bucket with no entity behind it travels as its bare key, even on
    // a dimension whose buckets usually are entities, and an entity
    // screen handed one of those would ask the artwork and star
    // endpoints for something that is not a pid.
    WaxRoute.musicBucket(dimension, 'plain-key'): MusicListingScreen,
    // The bucket a dimension is absent from: its key is empty, and an
    // empty path segment is not a location, so it travels as a sentinel.
    // There is no entity behind it either way, so it is always a listing.
    WaxRoute.musicBucket(dimension, musicUnknownSegment): MusicListingScreen,
  },
  WaxRoute.artistTracks('ar-1'): MusicListingScreen,
  WaxRoute.playlists: PlaylistsScreen,
  WaxRoute.playlist('pl-1'): PlaylistScreen,
  WaxRoute.podcasts: PodcastsScreen,
  WaxRoute.show('pc-1'): ShowScreen,
  // The canonical episode location, with its show in the path, and the
  // show-less one a search hit opens and an older link still carries.
  WaxRoute.showEpisode('pc-1', 'ep-1'): EpisodeScreen,
  WaxRoute.episode('ep-1'): EpisodeScreen,
  WaxRoute.books: BooksScreen,
  WaxRoute.book('bk-1'): BookScreen,
  WaxRoute.radio: RadioScreen,
  WaxRoute.radioSaved: RadioSavedScreen,
  WaxRoute.downloads: DownloadsScreen,
  // Views of whatever is playing, so none carries a payload and a
  // reload lands back on it.
  WaxRoute.nowPlaying: PlayerScreen,
  WaxRoute.visualizer: VisualizerScreen,
  WaxRoute.carMode: CarModeScreen,
  WaxRoute.stats: StatsScreen,
  WaxRoute.listenLog: ListenLogScreen,
  WaxRoute.yearInReview: YearInReviewScreen,
  WaxRoute.settings: SettingsScreen,
  // One location per section, so "it is under Playback" is a link.
  for (final section in SettingsSection.values)
    WaxRoute.settingsSection(section): SettingsSectionScreen,
  // The same location naming a setting inside it, which is what a
  // settings search result opens. A query parameter rather than a path
  // segment, so the `:section` route answers both.
  WaxRoute.settingsSection(SettingsSection.playback, setting: 'replay-gain'):
      SettingsSectionScreen,
  // And one no section draws. Not a redirect and not a refusal: the id
  // names nothing, so the section opens and says nothing about it.
  WaxRoute.settingsSection(
    SettingsSection.playback,
    setting: 'no-such-setting',
  ): SettingsSectionScreen,
  // A literal beside the `:section` pattern, which would otherwise match
  // it and the redirect would bounce it back to the settings home.
  WaxRoute.settingsAbout: AboutScreen,
  WaxRoute.settingsDefects: DefectLogScreen,
  WaxRoute.shares: SharesScreen,
  WaxRoute.uploads: UploadsScreen,
  WaxRoute.tasks: TasksScreen,
  WaxRoute.notifications: NotificationsScreen,
  // Its own destination rather than a console section, so it is declared
  // out here with the rest of what is not a domain.
  WaxRoute.review: ReviewSurface,
  // The same surface: the entry is a pane beside the queue where there
  // is room for one and the page itself where there is not.
  WaxRoute.reviewEntry('re-1'): ReviewSurface,
  WaxRoute.metadata('tr-1'): MetadataScreen,
  // The same location, branched by the pid: an album opens the release
  // workbench rather than the item editor.
  WaxRoute.metadata('al-1'): ReleaseWorkbench,
  // The admin console. Every section is a location a stranger can open,
  // which is what makes "it is under Backups" a link rather than a set
  // of directions; the console frame wraps them all.
  WaxRoute.admin: AdminDashboardScreen,
  WaxRoute.libraries: LibrariesScreen,
  WaxRoute.genres: GenreTreeScreen,
  WaxRoute.health: HealthScreen,
  WaxRoute.healthRule('missing-artwork'): HealthIssuesScreen,
  WaxRoute.diagnostics: DiagnosticsScreen,
  WaxRoute.organize: OrganizeScreen,
  WaxRoute.users: UsersScreen,
  WaxRoute.adminShares: AdminSharesScreen,
  WaxRoute.adminSettings: ServerSettingsScreen,
  WaxRoute.adminNotifications: AdminNotificationsScreen,
  WaxRoute.schedules: SchedulesScreen,
  WaxRoute.audit: AuditScreen,
  WaxRoute.backups: BackupsScreen,
  WaxRoute.trash: TrashScreen,
  WaxRoute.migrate: MigrateScreen,
};

/// Locations this app used to mint and no longer does, and where each
/// one lands now. Every console location is shareable and the web build
/// puts it in the URL, so a path that moves owes its old links an answer.
final _movedRoutes = <String, String>{
  WaxRoute.legacyReview: WaxRoute.review,
  '${WaxRoute.legacyReview}/re-1': WaxRoute.reviewEntry('re-1'),
};

/// The routes that carry an in-memory payload, and where each sends a
/// visitor who arrives without one (a reload, a restored history entry,
/// a guessed URL). `extra` never survives that trip, so every one of
/// them has to land somewhere real.
final _payloadRoutes = <String, String>{
  WaxRoute.tracks: WaxRoute.home,
  WaxRoute.remote: WaxRoute.home,
  WaxRoute.playlistRules: WaxRoute.playlists,
  WaxRoute.playlistEdit('pl-1'): WaxRoute.playlist('pl-1'),
  WaxRoute.userEdit: WaxRoute.users,
};

/// Locations the table declares beneath another one, and so the only
/// ones that answer a back affordance.
///
/// The rest are a branch's own top-level routes: a destination is not a
/// stack, and a shell that offered "back" from one would be lying.
final _stackedInShell = <String>{
  WaxRoute.musicTracks,
  for (final dimension in MusicDimension.values) ...<String>{
    WaxRoute.musicIndex(dimension),
    WaxRoute.musicBucket(dimension, _entityHandle(dimension)),
    WaxRoute.musicBucket(dimension, 'plain-key'),
    WaxRoute.musicBucket(dimension, musicUnknownSegment),
  },
  WaxRoute.artistTracks('ar-1'),
  WaxRoute.book('bk-1'),
  WaxRoute.show('pc-1'),
  // Declared beneath its show, which is the point of putting the show in
  // the path: a stranger opening the link gets the show underneath.
  WaxRoute.showEpisode('pc-1', 'ep-1'),
  WaxRoute.playlist('pl-1'),
  WaxRoute.listenLog,
  WaxRoute.yearInReview,
  for (final section in SettingsSection.values)
    WaxRoute.settingsSection(section),
  // A named setting is the same location with a query on it, so it
  // stacks under the settings home exactly as the bare section does.
  WaxRoute.settingsSection(SettingsSection.playback, setting: 'replay-gain'),
  WaxRoute.settingsSection(
    SettingsSection.playback,
    setting: 'no-such-setting',
  ),
  WaxRoute.settingsAbout,
  // Two deep: About under settings, and the log under About, so back
  // walks the way it was opened.
  WaxRoute.settingsDefects,
  // Beneath settings now, so `go` builds settings under it and back
  // lands on the row that opened it - which is what let the Account
  // section stop pushing.
  WaxRoute.shares,
  // Declared beneath the hub, so a stranger opening the link gets the
  // dial underneath and back lands on the row that opened it.
  WaxRoute.radioSaved,
  WaxRoute.healthRule('missing-artwork'),
};

Future<GoRouter> _pumpApp(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [
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
  testWidgets('every declared location resolves to its screen', (tester) async {
    final router = await _pumpApp(tester);
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
        _stackedInShell.contains(entry.key),
        reason: '${entry.key} back affordance',
      );
    }
  });

  testWidgets('a location that moved still answers where it was', (
    tester,
  ) async {
    final router = await _pumpApp(tester);
    for (final entry in _movedRoutes.entries) {
      router.go(entry.key);
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        entry.value,
        reason: '${entry.key} should redirect',
      );
      expect(find.byType(ReviewSurface), findsOneWidget);
    }
  });

  testWidgets('a pid the editor location cannot edit lands on not-found', (
    tester,
  ) async {
    // An artist or release-group pid used to fall into the item editor
    // and fail its read, which read as a broken editor rather than a
    // wrong link.
    final router = await _pumpApp(tester);
    for (final pid in <String>['ar-1', 'rg-1', 'pl-1']) {
      router.go(WaxRoute.metadata(pid));
      await tester.pumpAndSettle();

      expect(find.byType(MetadataScreen), findsNothing, reason: pid);
      expect(find.byType(ReleaseWorkbench), findsNothing, reason: pid);
      expect(find.text('Not found'), findsOneWidget, reason: pid);
    }
  });

  testWidgets('a payload route opened without one lands one level up', (
    tester,
  ) async {
    final router = await _pumpApp(tester);
    for (final entry in _payloadRoutes.entries) {
      router.go(entry.key);
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        entry.value,
        reason: '${entry.key} without extra',
      );
    }
  });

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
