import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/admin/admin_shares_screen.dart';
import 'package:waxdeck/src/admin/audit_screen.dart';
import 'package:waxdeck/src/admin/backups_screen.dart';
import 'package:waxdeck/src/admin/dashboard_screen.dart';
import 'package:waxdeck/src/admin/enrichment_screen.dart';
import 'package:waxdeck/src/admin/genres_screen.dart';
import 'package:waxdeck/src/admin/libraries_screen.dart';
import 'package:waxdeck/src/admin/migrate_screen.dart';
import 'package:waxdeck/src/admin/notifications_screen.dart';
import 'package:waxdeck/src/admin/schedules_screen.dart';
import 'package:waxdeck/src/admin/server_settings_screen.dart';
import 'package:waxdeck/src/admin/trash_screen.dart';
import 'package:waxdeck/src/admin/user_edit_screen.dart';
import 'package:waxdeck/src/admin/users_screen.dart';
import 'package:waxdeck/src/auth/connect_server_screen.dart';
import 'package:waxdeck/src/auth/login_screen.dart';
import 'package:waxdeck/src/auth/setup_screen.dart';
import 'package:waxdeck/src/auth/signup_screen.dart';
import 'package:waxdeck/src/books/book_bucket_screen.dart';
import 'package:waxdeck/src/books/book_dimension.dart';
import 'package:waxdeck/src/books/book_screen.dart';
import 'package:waxdeck/src/books/books_screen.dart';
import 'package:waxdeck/src/books/series_index_screen.dart';
import 'package:waxdeck/src/books/series_screen.dart';
import 'package:waxdeck/src/connect/remote_screen.dart';
import 'package:waxdeck/src/connect/remote_session.dart';
import 'package:waxdeck/src/diagnostics/defect_log_screen.dart';
import 'package:waxdeck/src/discovery/track_list_screen.dart';
import 'package:waxdeck/src/downloads/downloads_screen.dart';
import 'package:waxdeck/src/health/diagnostics_screen.dart';
import 'package:waxdeck/src/health/health_screen.dart';
import 'package:waxdeck/src/home/home_screen.dart';
import 'package:waxdeck/src/metadata/entity_editor_screen.dart';
import 'package:waxdeck/src/metadata/metadata_screen.dart';
import 'package:waxdeck/src/metadata/release_workbench.dart';
import 'package:waxdeck/src/music/album_screen.dart';
import 'package:waxdeck/src/music/artist_screen.dart';
import 'package:waxdeck/src/music/index_screen.dart';
import 'package:waxdeck/src/music/listing_screen.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/music/music_hub_screen.dart';
import 'package:waxdeck/src/notifications/notifications_screen.dart';
import 'package:waxdeck/src/organize/organize_screen.dart';
import 'package:waxdeck/src/player/car_mode_screen.dart';
import 'package:waxdeck/src/player/player_screen.dart';
import 'package:waxdeck/src/player/visualizer_screen.dart';
import 'package:waxdeck/src/playlists/playlist_screen.dart';
import 'package:waxdeck/src/playlists/playlists_screen.dart';
import 'package:waxdeck/src/playlists/rule_editor_screen.dart';
import 'package:waxdeck/src/podcasts/episode_screen.dart';
import 'package:waxdeck/src/podcasts/podcasts_screen.dart';
import 'package:waxdeck/src/podcasts/show_screen.dart';
import 'package:waxdeck/src/queue/queue_screen.dart';
import 'package:waxdeck/src/radio/radio_saved_screen.dart';
import 'package:waxdeck/src/radio/radio_screen.dart';
import 'package:waxdeck/src/review/review_screen.dart';
import 'package:waxdeck/src/search/search_screen.dart';
import 'package:waxdeck/src/settings/about_screen.dart';
import 'package:waxdeck/src/settings/settings_registry.dart';
import 'package:waxdeck/src/settings/settings_screen.dart';
import 'package:waxdeck/src/settings/settings_section_screen.dart';
import 'package:waxdeck/src/sharing/shares_screen.dart';
import 'package:waxdeck/src/shell/adaptive_shell.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck/src/stats/listen_log_screen.dart';
import 'package:waxdeck/src/stats/stats_screen.dart';
import 'package:waxdeck/src/stats/year_in_review_screen.dart';
import 'package:waxdeck/src/tools/tasks_screen.dart';
import 'package:waxdeck/src/uploads/uploads_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';
import 'wax_finders.dart';

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
  WaxRoute.bookSeriesIndex: BookSeriesIndexScreen,
  WaxRoute.bookSeries('sr-1'): BookSeriesScreen,
  // The books indexes are the music index over the books' scope; a
  // bucket is one page of covers whatever its handle is.
  for (final dimension in BookDimension.values)
    WaxRoute.bookIndex(dimension): MusicIndexScreen,
  WaxRoute.bookBucket(BookDimension.authors, 'ar-1'): BookBucketScreen,
  WaxRoute.bookBucket(BookDimension.genres, 'plain-key'): BookBucketScreen,
  WaxRoute.bookBucket(BookDimension.authors, musicUnknownSegment):
      BookBucketScreen,
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
  // workbench rather than the item editor, and an artist or release
  // group opens its entity editor.
  WaxRoute.metadata('al-1'): ReleaseWorkbench,
  WaxRoute.metadata('ar-1'): EntityEditorScreen,
  WaxRoute.metadata('rg-1'): EntityEditorScreen,
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
  // The same section with a dry run under way, which the path rule's fix
  // opens. A query, so the one route answers both.
  WaxRoute.organizePreviewOwn: OrganizeScreen,
  WaxRoute.adminEnrichment: EnrichmentScreen,
  WaxRoute.users: UsersScreen,
  // The same screen on its signup requests, where a signup notification
  // lands, and on its invites. A query, so the one route answers all three.
  WaxRoute.userRequests: UsersScreen,
  WaxRoute.userInvites: UsersScreen,
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
  // The index under the hub, and one series under the index: a stranger
  // opening either link gets the surface above it underneath.
  WaxRoute.bookSeriesIndex,
  WaxRoute.bookSeries('sr-1'),
  for (final dimension in BookDimension.values) WaxRoute.bookIndex(dimension),
  WaxRoute.bookBucket(BookDimension.authors, 'ar-1'),
  WaxRoute.bookBucket(BookDimension.genres, 'plain-key'),
  WaxRoute.bookBucket(BookDimension.authors, musicUnknownSegment),
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

/// The view the users screen on screen shows, by its segment's name.
String _usersView(WidgetTester tester) => tester
    .widget<WaxSegmented>(
      find.descendant(
        of: find.byType(UsersScreen),
        matching: find.byType(WaxSegmented),
      ),
    )
    .selected;

Future<GoRouter> _pumpApp(WidgetTester tester) async {
  final container = appContainer(
    repo: FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _user),
    ),
  );
  await pumpWholeApp(tester, container: container);
  return container.read(routerProvider);
}

/// Whether the page [screen] is on has a place for the shell's messages:
/// [screen] holds a `ShellMessageArea`, or sits in one on its own page.
///
/// What `page_messages_audit.dart` cannot see, a page with no material
/// Scaffold (none at all, or another design-system scaffold), is caught
/// here, for every screen the table opens.
bool _drawsMessages(Finder screen) {
  final area = find.byType(ShellMessageArea, skipOffstage: false);
  if (find
      .descendant(of: screen, matching: area, skipOffstage: false)
      .evaluate()
      .isNotEmpty) {
    return true;
  }
  var found = false;
  screen.evaluate().single.visitAncestorElements((ancestor) {
    found = ancestor.widget is ShellMessageArea;
    // A page ends at the overlay of the navigator it is on.
    return !found && ancestor.widget is! Overlay;
  });
  return found;
}

/// An offer worded as no page words anything.
const _guardMessage = 'A message under guard';
const _guardAction = 'Act on it';

/// Every semantics node a screen reader hears [label] from.
List<SemanticsNode> _heard(WidgetTester tester, String label) {
  final found = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    if (node.getSemanticsData().label == label) found.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return found;
}

/// Raises a waiting offer over the page on screen, [where], and checks a
/// screen reader reaches it there, then answers it so the next page starts
/// with none: one copy drawn and one node where it is drawn, not hidden; a
/// touch across the bar explores the bar, so nothing is drawn over it; the
/// same nodes as a reader starts and stops reading (Android's bridge turns
/// accessible navigation on with the first node a reader asks for); and
/// its action a button inside it that a reader's tap runs.
Future<void> _expectMessageReached(
  WidgetTester tester,
  ProviderContainer container,
  String where,
) async {
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  var acted = 0;
  container
      .read(shellMessengerProvider)
      .show(
        _guardMessage,
        actionLabel: _guardAction,
        onAction: () => acted++,
        persist: true,
      );
  await tester.pumpAndSettle();

  expect(find.text(_guardMessage), findsOneWidget, reason: '$where: drawn');
  final bar = tester.getRect(
    find
        .ancestor(of: find.text(_guardMessage), matching: find.byType(Material))
        .first,
  );
  // The semantics tree is in the window's pixels.
  final ratio = tester.view.devicePixelRatio;
  (SemanticsNode, SemanticsNode) nodes(String when) {
    final message = _heard(tester, _guardMessage);
    final action = _heard(tester, _guardAction);
    expect(message, hasLength(1), reason: '$where$when: the message heard');
    expect(action, hasLength(1), reason: '$where$when: its action heard');
    final node = message.single;
    expect(
      node.getSemanticsData().flagsCollection.isHidden,
      isFalse,
      reason: '$where$when: the message hidden',
    );
    expect(
      semanticsRectOnScreen(node),
      rectMoreOrLessEquals(
        Rect.fromLTRB(
          bar.left * ratio,
          bar.top * ratio,
          bar.right * ratio,
          bar.bottom * ratio,
        ),
        epsilon: 0.01,
      ),
      reason: '$where$when: the message heard where it is drawn',
    );
    expect(
      action.single.parent,
      same(node),
      reason: '$where$when: the action inside the message',
    );
    expect(
      action.single.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
      reason: '$where$when: the action pressable',
    );
    return (node, action.single);
  }

  final (node, action) = nodes('');
  for (final point in <Offset>[
    bar.centerLeft.translate(4, 0),
    bar.center,
    bar.centerRight.translate(-4, 0),
    bar.topRight.translate(-4, 4),
    bar.bottomRight.translate(-4, -4),
  ]) {
    final explored = touchExploredAt(tester, point * ratio);
    expect(
      explored == node || explored?.parent == node,
      isTrue,
      reason: '$where: a touch at $point explores $explored',
    );
  }

  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(accessibleNavigation: true);
  await tester.pump();
  expect(nodes(', a reader arriving'), (node, action), reason: where);
  tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
  await tester.pump();
  expect(nodes(', a reader leaving'), (node, action), reason: where);

  tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
    action.id,
    SemanticsAction.tap,
  );
  await tester.pumpAndSettle();
  expect(acted, 1, reason: '$where: its action, tapped by a reader');
  expect(find.text(_guardMessage), findsNothing, reason: '$where: answered');
}

/// The screens outside a session, each by where it opens (null: where a
/// server with no accounts lands) and whether that is such a server.
final _publicScreens = <(String?, Type, bool)>[
  (WaxRoute.login, LoginScreen, false),
  (WaxRoute.signup, SignupScreen, false),
  (WaxRoute.serverConnect, ConnectServerScreen, false),
  (null, SetupScreen, true),
];

/// A session on another device, for the remote screen to control.
final _remoteSession = PlaybackSessionInfo(
  id: 'ps-remote',
  endpointId: 'pe-speaker',
  endpointName: 'Kitchen speaker',
  mine: true,
  authority: 'remote',
  playing: true,
  index: 0,
  positionMs: 1000,
  positionAt: DateTime.utc(2026, 7, 1),
  rate: 1,
  volume: 0.8,
  queueVersion: 1,
  entries: const [
    PlaybackSessionEntry(pid: 'tr-x', title: 'Alpha', durationMs: 30000),
  ],
);

/// The routes only ever pushed, each pushed over where the app pushes it
/// with what the app pushes there, and the screen it opens.
final _pushedScreens = <(String, String, Object?, Type)>[
  (WaxRoute.queue, WaxRoute.home, null, QueueScreen),
  // Arriving with no session to control is sent home; one is adopted.
  (WaxRoute.remote, WaxRoute.home, null, RemoteControlScreen),
  (
    WaxRoute.tracks,
    WaxRoute.home,
    TrackListArgs(
      title: 'Night drive',
      basis: MixBasis.sonic,
      items: [testItem('tr-1')],
      idPrefix: 'mix',
    ),
    TrackListScreen,
  ),
  (
    WaxRoute.playlistRules,
    WaxRoute.playlists,
    const RuleDraftArgs(name: 'Late', shared: false),
    RuleEditorScreen,
  ),
  (
    WaxRoute.playlistEdit('pl-1'),
    WaxRoute.playlist('pl-1'),
    Playlist(
      pid: 'pl-1',
      name: 'Late',
      kind: 'smart',
      visibility: 'private',
      ownerName: 'admin',
      isOwner: true,
      createdAt: DateTime.utc(2026, 7, 1),
      updatedAt: DateTime.utc(2026, 7, 1),
    ),
    RuleEditorScreen,
  ),
  (
    WaxRoute.userEdit,
    WaxRoute.users,
    UserEditArgs(
      user: UserAccount(
        id: 'us-3',
        username: 'merry',
        roles: const ['user'],
        createdAt: DateTime.utc(2026, 7, 1),
        libraryAccess: const LibraryAccess(mode: 'all'),
      ),
    ),
    UserEditScreen,
  ),
];

/// Every location a guard of a place for messages opens.
final _guarded = <String>{
  ..._locations.keys,
  for (final (location, _, _) in _publicScreens) location ?? WaxRoute.setup,
  for (final (location, _, _, _) in _pushedScreens) location,
};

/// Every route of [routes] that builds a page, down the tree.
Iterable<GoRoute> _builtRoutes(List<RouteBase> routes) sync* {
  for (final route in routes) {
    if (route is GoRoute && (route.builder ?? route.pageBuilder) != null) {
      yield route;
    }
    yield* _builtRoutes(route.routes);
  }
}

/// Whether [matches] hold a push anywhere down the tree.
bool _holdsPush(List<RouteMatchBase> matches) => matches.any(
  (match) =>
      match is ImperativeRouteMatch ||
      match is ShellRouteMatch && _holdsPush(match.matches),
);

/// The shell route the table hangs its branches from.
StatefulShellRoute _statefulShell(List<RouteBase> routes) =>
    _findStatefulShell(routes) ??
    (throw StateError('the route table has no StatefulShellRoute'));

StatefulShellRoute? _findStatefulShell(List<RouteBase> routes) {
  for (final route in routes) {
    if (route is StatefulShellRoute) return route;
    if (_findStatefulShell(route.routes) case final inner?) return inner;
  }
  return null;
}

/// The navigator every shell match on the way to a location owns, which
/// is how a location says which branch holds it.
Set<GlobalKey<NavigatorState>> _navigatorKeysOf(List<RouteMatchBase> matches) =>
    <GlobalKey<NavigatorState>>{
      for (final match in matches)
        if (match is ShellRouteMatch) ...<GlobalKey<NavigatorState>>{
          match.navigatorKey,
          ..._navigatorKeysOf(match.matches),
        },
    };

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
      expect(
        _drawsMessages(find.byType(entry.value)),
        isTrue,
        reason: '${entry.key}: ${entry.value} has no place for messages',
      );
    }
  });

  testWidgets('every location draws a message a screen reader reaches, an '
      'index beside its letter rail too', (tester) async {
    final repository = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _user),
    );
    // Buckets for every index, so an index in A-to-Z order shows its rail.
    for (final dimension in MusicDimension.values) {
      repository.facets[dimension.wireName] = [
        for (final name in ['Abba', 'Mogwai', 'Zebra'])
          FacetBucket(
            key: 'k$name',
            label: name,
            count: 3,
            entityPid: switch (dimension.entityPrefix) {
              final prefix? => '$prefix$name',
              null => null,
            },
          ),
      ];
    }
    final container = appContainer(repo: repository);
    await pumpWholeApp(tester, container: container);
    final router = container.read(routerProvider);

    final railed = <String>{};
    for (final location in _locations.keys) {
      router.go(location);
      await tester.pumpAndSettle();
      if (find.byType(FastScrollRail).evaluate().isNotEmpty) {
        railed.add(location);
      }
      await _expectMessageReached(tester, container, location);
    }
    expect(
      railed,
      containsAll(<String>[
        WaxRoute.musicIndex(MusicDimension.artists),
        WaxRoute.musicIndex(MusicDimension.albums),
        WaxRoute.bookIndex(BookDimension.authors),
      ]),
    );
  });

  testWidgets('every pushed route, with its payload, and the not-found page '
      'open a screen with a place for messages a screen reader reaches', (
    tester,
  ) async {
    final container = appContainer(
      repo: FakeRepository(
        sessionState: const SessionState(authenticated: true, user: _user),
      ),
    );
    await pumpWholeApp(tester, container: container);
    final router = container.read(routerProvider);
    container.read(remoteSessionProvider.notifier).adopt(_remoteSession);

    for (final (location, under, extra, screen) in _pushedScreens) {
      router.go(under);
      await tester.pumpAndSettle();
      unawaited(router.push<void>(location, extra: extra));
      await tester.pumpAndSettle();

      expect(find.byType(screen), findsOneWidget, reason: location);
      expect(
        _drawsMessages(find.byType(screen)),
        isTrue,
        reason: '$location: $screen has no place for messages',
      );
      await _expectMessageReached(tester, container, location);
    }

    router.go('/nowhere/at-all');
    await tester.pumpAndSettle();
    final notFound = find.ancestor(
      of: find.text('Not found'),
      matching: find.byType(WaxScaffold),
    );
    expect(notFound, findsOneWidget);
    expect(
      _drawsMessages(notFound),
      isTrue,
      reason: 'the not-found page has no place for messages',
    );
    await _expectMessageReached(tester, container, 'the not-found page');
  });

  testWidgets('the message guard opens every route the table declares', (
    tester,
  ) async {
    final router = await _pumpApp(tester);
    final table = router.configuration;
    final opened = <RouteBase>{
      for (final location in _guarded)
        table.findMatch(Uri.parse(location)).last.route,
    };

    expect(
      [
        for (final route in _builtRoutes(table.routes))
          if (!opened.contains(route)) route.path,
      ],
      isEmpty,
      reason: 'routes no message guard opens',
    );
  });

  testWidgets('every location outside a session opens a screen with a place '
      'for messages a screen reader reaches', (tester) async {
    for (final (location, screen, bootstrap) in _publicScreens) {
      final container = appContainer(
        repo: FakeRepository(bootstrapNeeded: bootstrap),
      );
      await pumpWholeApp(tester, container: container);
      if (location != null) container.read(routerProvider).go(location);
      await tester.pumpAndSettle();

      expect(find.byType(screen), findsOneWidget, reason: '$screen');
      expect(
        _drawsMessages(find.byType(screen)),
        isTrue,
        reason: '$screen has no place for messages',
      );
      await _expectMessageReached(tester, container, '$screen');
    }
  });

  testWidgets('the users location opens on the view it names', (tester) async {
    final router = await _pumpApp(tester);

    router.go(WaxRoute.userRequests);
    await tester.pumpAndSettle();
    expect(_usersView(tester), WaxRoute.usersRequestsView);
    router.go(WaxRoute.userInvites);
    await tester.pumpAndSettle();
    expect(_usersView(tester), WaxRoute.usersInvitesView);

    // One page under every query, so the view follows the location.
    router.go(WaxRoute.users);
    await tester.pumpAndSettle();
    expect(_usersView(tester), 'users');
    router.go(WaxRoute.userRequests);
    await tester.pumpAndSettle();
    expect(_usersView(tester), WaxRoute.usersRequestsView);
  });

  testWidgets('a users view chosen by tap is the location, and a reload of '
      'it opens that view', (tester) async {
    final router = await _pumpApp(tester);
    router.go(WaxRoute.users);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(WaxSegmented),
        matching: find.text('Invites'),
      ),
    );
    await tester.pumpAndSettle();
    final location = router.routerDelegate.currentConfiguration.uri.toString();
    expect(location, WaxRoute.userInvites);
    expect(_usersView(tester), WaxRoute.usersInvitesView);

    // A reload: a fresh app, opened at the location the tap wrote.
    await tester.pumpWidget(const SizedBox());
    tester.platformDispatcher.defaultRouteNameTestValue = location;
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
    await _pumpApp(tester);
    expect(_usersView(tester), WaxRoute.usersInvitesView);
  });

  testWidgets('a listing reads the scope its location states', (tester) async {
    // A /music listing is music, whatever its handle; a link whose medium
    // is unknown says so in the location.
    final router = await _pumpApp(tester);
    for (final (location, domain) in <(String, BrowseDomain)>[
      (WaxRoute.artistTracks('ar-1'), BrowseDomain.music),
      // The artist's own list is music, as the artist page above it is.
      (
        '${WaxRoute.artistTracks('ar-1')}'
            '?${WaxRoute.scopeParam}=${WaxRoute.wholeLibraryScope}',
        BrowseDomain.music,
      ),
      (WaxRoute.artistTracks(musicUnknownSegment), BrowseDomain.music),
      (
        WaxRoute.musicBucket(MusicDimension.artists, 'plain-key'),
        BrowseDomain.music,
      ),
      (
        WaxRoute.musicBucket(MusicDimension.genres, 'key-1'),
        BrowseDomain.music,
      ),
      (
        WaxRoute.musicBucket(
          MusicDimension.genres,
          'key-1',
          wholeLibrary: true,
        ),
        BrowseDomain.wholeLibrary,
      ),
      (
        WaxRoute.musicBucket(MusicDimension.releaseGroups, 'rg-1'),
        BrowseDomain.music,
      ),
      (
        WaxRoute.musicBucket(
          MusicDimension.releaseGroups,
          'rg-1',
          wholeLibrary: true,
        ),
        BrowseDomain.wholeLibrary,
      ),
    ]) {
      router.go(location);
      await tester.pumpAndSettle();
      final listing = tester.widget<MusicListingScreen>(
        find.byType(MusicListingScreen),
      );
      expect(listing.domain, domain, reason: location);
      expect(listing.segment, isNot(contains('?')), reason: location);
    }
  });

  testWidgets('the books locations read the books domain', (tester) async {
    // A music index under the books path would count tracks.
    final router = await _pumpApp(tester);
    for (final dimension in BookDimension.values) {
      final location = WaxRoute.bookIndex(dimension);
      router.go(location);
      await tester.pumpAndSettle();
      final index = tester.widget<MusicIndexScreen>(
        find.byType(MusicIndexScreen),
      );
      expect(index.domain, BrowseDomain.books, reason: location);
      expect(index.dimension, dimension.dimension, reason: location);

      final bucket = WaxRoute.bookBucket(dimension, 'plain-key');
      router.go(bucket);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BookBucketScreen>(find.byType(BookBucketScreen))
            .dimension,
        dimension,
        reason: bucket,
      );
    }
  });

  testWidgets('an artist card opens the page its media has', (tester) async {
    // A person with only books has no music page: their card opens the
    // Books author bucket; anyone with music, or a card that names no
    // media, the music artist page.
    final router = await _pumpApp(tester);
    EntityCard card(List<MediaType>? media) => EntityCard(
      pid: 'ar-1',
      kind: EntityCardKind.artist,
      title: 'Ann Writer',
      mediaTypes: media,
    );
    for (final (media, location, screen) in <(List<MediaType>?, String, Type)>[
      (
        <MediaType>[MediaType.audiobook],
        WaxRoute.bookBucket(BookDimension.authors, 'ar-1'),
        BookBucketScreen,
      ),
      (
        <MediaType>[MediaType.music],
        WaxRoute.musicBucket(MusicDimension.artists, 'ar-1'),
        ArtistScreen,
      ),
      (
        <MediaType>[MediaType.audiobook, MediaType.music],
        WaxRoute.musicBucket(MusicDimension.artists, 'ar-1'),
        ArtistScreen,
      ),
      (
        <MediaType>[],
        WaxRoute.musicBucket(MusicDimension.artists, 'ar-1'),
        ArtistScreen,
      ),
      (
        null,
        WaxRoute.musicBucket(MusicDimension.artists, 'ar-1'),
        ArtistScreen,
      ),
    ]) {
      final at = artistLocation(card(media));
      expect(at, location, reason: '$media');
      router.go(at);
      await tester.pumpAndSettle();
      expect(find.byType(screen), findsOneWidget, reason: '$media');
    }
  });

  testWidgets('a door\'s declared parent is the table\'s, not its path\'s', (
    tester,
  ) async {
    final router = await _pumpApp(tester);
    final parents = <String, String?>{
      WaxRoute.book('bk-1'): WaxRoute.books,
      WaxRoute.bookBucket(BookDimension.authors, 'ar-1'): WaxRoute.bookIndex(
        BookDimension.authors,
      ),
      WaxRoute.musicBucket(MusicDimension.albums, 'al-1'): WaxRoute.musicIndex(
        MusicDimension.albums,
      ),
      WaxRoute.musicBucket(MusicDimension.artists, 'ar-1'): WaxRoute.musicIndex(
        MusicDimension.artists,
      ),
      // Two segments below its show: cutting the last one off would name
      // `/podcasts/pc-1/episodes`, which is no page.
      WaxRoute.showEpisode('pc-1', 'ep-1'): WaxRoute.show('pc-1'),
      WaxRoute.episode('ep-1'): null,
      WaxRoute.metadata('tr-1'): null,
      '/nowhere/at-all': null,
    };
    for (final MapEntry(key: location, value: parent) in parents.entries) {
      expect(router.declaredParentOf(location), parent, reason: location);
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
    // A playlist pid is nothing this location edits: before the entity
    // editors it used to fall into the item editor and fail its read,
    // which read as a broken editor rather than a wrong link.
    final router = await _pumpApp(tester);
    router.go(WaxRoute.metadata('pl-1'));
    await tester.pumpAndSettle();

    expect(find.byType(MetadataScreen), findsNothing);
    expect(find.byType(ReleaseWorkbench), findsNothing);
    expect(find.byType(EntityEditorScreen), findsNothing);
    expect(find.text('Not found'), findsOneWidget);
    expect(find.widgetWithText(WaxButton, 'Go home'), findsOneWidget);
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

  testWidgets('a payload route restored without one leaves for what is '
      'under it', (tester) async {
    // As a reload or a browser entry rebuilds a push: the push is there,
    // its payload is not, and a restore runs no redirect of a push's.
    final router = await _pumpApp(tester);
    final table = router.configuration;
    for (final (under, pushed) in <(String, String)>[
      (WaxRoute.users, WaxRoute.userEdit),
      (WaxRoute.home, WaxRoute.tracks),
      (WaxRoute.playlists, WaxRoute.playlistRules),
      (WaxRoute.playlist('pl-1'), WaxRoute.playlistEdit('pl-1')),
    ]) {
      router.go(under);
      await tester.pumpAndSettle();
      expect(
        _holdsPush(router.routerDelegate.currentConfiguration.matches),
        isFalse,
      );
      router.restore(
        table
            .findMatch(Uri.parse(under))
            .push(
              ImperativeRouteMatch(
                pageKey: ValueKey<String>('restored $pushed'),
                matches: table.findMatch(Uri.parse(pushed)),
                completer: Completer<Object?>(),
              ),
            ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: pushed);
      final config = router.routerDelegate.currentConfiguration;
      expect(config.uri.toString(), under, reason: pushed);
      expect(_holdsPush(config.matches), isFalse, reason: '$pushed left');
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

  testWidgets('every secondary destination is declared in the shared branch', (
    tester,
  ) async {
    // A destination of its own is gone to, and `go` files a location in
    // the branch that declares it. Declared in a domain's branch, one
    // would be what that domain's tab restores; declared in the shared
    // one, nothing a domain tab restores can be it.
    final router = await _pumpApp(tester);
    final stateful = _statefulShell(router.configuration.routes);
    final shared = stateful.branches.last.navigatorKey;
    for (final (index, target) in waxShellBranches.indexed) {
      expect(
        _navigatorKeysOf(
          router.configuration.findMatch(Uri.parse(target.location)).matches,
        ),
        contains(stateful.branches[index].navigatorKey),
        reason: '${target.name} is its own branch',
      );
    }
    final secondary = WaxNavTarget.values.where(
      (target) => target.section == WaxNavSection.secondary,
    );
    expect(secondary, isNotEmpty);
    for (final target in secondary) {
      expect(
        _navigatorKeysOf(
          router.configuration.findMatch(Uri.parse(target.location)).matches,
        ),
        contains(shared),
        reason: '${target.name} at ${target.location}',
      );
    }
    for (final location in <String>[
      WaxRoute.uploads,
      WaxRoute.reviewEntry('re-1'),
    ]) {
      expect(
        _navigatorKeysOf(
          router.configuration.findMatch(Uri.parse(location)).matches,
        ),
        contains(shared),
        reason: location,
      );
    }
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
