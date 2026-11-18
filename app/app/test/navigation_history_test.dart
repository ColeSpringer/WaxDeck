import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/admin/backups_screen.dart';
import 'package:waxdeck/src/admin/user_edit_screen.dart';
import 'package:waxdeck/src/admin/users_screen.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/login_screen.dart';
import 'package:waxdeck/src/auth/signup_screen.dart';
import 'package:waxdeck/src/books/book_screen.dart';
import 'package:waxdeck/src/books/books_screen.dart';
import 'package:waxdeck/src/home/home_screen.dart';
import 'package:waxdeck/src/library/item_delete.dart';
import 'package:waxdeck/src/metadata/metadata_screen.dart';
import 'package:waxdeck/src/music/album_screen.dart';
import 'package:waxdeck/src/music/artist_screen.dart';
import 'package:waxdeck/src/music/index_screen.dart';
import 'package:waxdeck/src/music/listing_screen.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/notifications/notifications_controller.dart';
import 'package:waxdeck/src/notifications/notifications_screen.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/player/player_screen.dart';
import 'package:waxdeck/src/playlists/playlist_screen.dart';
import 'package:waxdeck/src/playlists/playlists_controller.dart';
import 'package:waxdeck/src/playlists/playlists_screen.dart';
import 'package:waxdeck/src/podcasts/episode_screen.dart';
import 'package:waxdeck/src/podcasts/podcasts_screen.dart';
import 'package:waxdeck/src/podcasts/show_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/radio/radio_saved_screen.dart';
import 'package:waxdeck/src/review/review_entry_screen.dart';
import 'package:waxdeck/src/review/review_screen.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/search/search_screen.dart';
import 'package:waxdeck/src/settings/settings_registry.dart';
import 'package:waxdeck/src/settings/settings_screen.dart';
import 'package:waxdeck/src/settings/settings_section_screen.dart';
import 'package:waxdeck/src/shell/adaptive_shell.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/tools/tasks_screen.dart';
import 'package:waxdeck/src/uploads/uploads_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';
import 'router_stack.dart';
import 'secondary_click.dart';

const _showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const _episodePid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';
const _albumPid = 'al-01JZX5N8QW3F4V9T2B7KDALBUM1';
const _playlistPid = 'pl-01JZX5N8QW3F4V9T2B7KDPLIST1';
const _bookPid = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';

const _admin = WaxDeckUser(
  id: 'us-1',
  username: 'admin',
  roles: ['admin'],
  uploadEnabled: true,
);

/// Signed in, with each review decision held until [release] completes.
class _HeldDecisions extends FakeRepository {
  _HeldDecisions()
    : super(
        sessionState: const SessionState(authenticated: true, user: _admin),
      );

  final release = Completer<void>();

  @override
  Future<ReviewDecideResult> decideReviewEntry(
    String entryId, {
    required String action,
    String? candidateMbid,
  }) async {
    final decided = await super.decideReviewEntry(
      entryId,
      action: action,
      candidateMbid: candidateMbid,
    );
    await release.future;
    return decided;
  }
}

/// The whole app at desktop width, where the arrow is the only back
/// there is. [at] opens it cold on a link instead of at home; [over] is
/// the repository it runs over, signed in.
Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  String? at,
  Size size = const Size(1000, 900),
  List<ItemSummary> items = const <ItemSummary>[],
  FakeRepository? over,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (at != null) {
    tester.platformDispatcher.defaultRouteNameTestValue = at;
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
  }
  final repo =
      (over ??
            FakeRepository(
              sessionState: const SessionState(
                authenticated: true,
                user: _admin,
              ),
            ))
        ..addSubscription(testShow(_showPid))
        ..episodesByShow[_showPid] = <EpisodeSummary>[testEpisode(_episodePid)]
        ..albums[_albumPid] = const AlbumDetail(
          pid: _albumPid,
          title: 'Gullwing',
        )
        ..libraryItems.addAll(items);
  final container = appContainer(repo: repo);
  return pumpWholeApp(tester, container: container, disableAnimations: true);
}

/// What a screen's leading arrow does: a tap on the one on top. A hub
/// draws no arrow, so [hub] runs `context.back()` itself, which is what an
/// arrow there would do (the system back climbs out of a tab-tap visit
/// instead).
Future<void> _back(WidgetTester tester, {bool hub = false}) async {
  if (hub) {
    tester.element(find.byType(WaxScaffold).last).back();
  } else {
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.navBack));
  }
  await tester.pumpAndSettle();
}

FakeRepository _repo(ProviderContainer container) =>
    container.read(repositoryProvider) as FakeRepository;

GoRouter _router(ProviderContainer container) => container.read(routerProvider);

String _location(ProviderContainer container) =>
    _router(container).routerDelegate.currentConfiguration.uri.toString();

/// Every location on the stack, pushes included.
List<String> _stack(ProviderContainer container) {
  List<String> walk(List<RouteMatchBase> matches) => <String>[
    for (final match in matches)
      if (match is ShellRouteMatch)
        ...walk(match.matches)
      else
        match.matchedLocation,
  ];
  return walk(_router(container).routerDelegate.currentConfiguration.matches);
}

Future<void> _go(
  WidgetTester tester,
  ProviderContainer container,
  String location,
) async {
  _router(container).go(location);
  await tester.pumpAndSettle();
}

String get _album => WaxRoute.musicBucket(MusicDimension.albums, _albumPid);

/// The push on top of the stack, however deep the shells nest it.
ImperativeRouteMatch _topPush(ProviderContainer container) {
  RouteMatchBase walker = _router(
    container,
  ).routerDelegate.currentConfiguration.matches.last;
  while (walker is ShellRouteMatch) {
    walker = walker.matches.last;
  }
  return walker as ImperativeRouteMatch;
}

/// A choice made on the navigation chrome.
Future<void> _tapNav(WidgetTester tester, WaxNavTarget target) async {
  await tester.tap(
    find
        .byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.identifier ==
                  SemanticsIds.navDestination(target.name),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

/// Opens the row a session-local notification of [kind] draws.
Future<void> _openHintRow(
  WidgetTester tester,
  ProviderContainer container,
  NotificationKind kind,
) async {
  container
      .read(localNotificationsProvider.notifier)
      .record(kind, at: DateTime.now());
  await tester.pumpAndSettle();
  await tester.tap(
    find.bySemanticsIdentifier(SemanticsIds.notificationRowPlain(kind.token)),
  );
  await tester.pumpAndSettle();
}

/// Opens review entry [id] in the pane from its row in the queue.
Future<void> _openReviewRow(WidgetTester tester, String id) async {
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewRow(id)));
  await tester.pumpAndSettle();
  expect(
    tester.widget<ReviewEntryView>(find.byType(ReviewEntryView)).entryId,
    id,
  );
}

/// Picks Delete from the menu that is open and confirms it.
Future<void> _confirmPlaylistDelete(WidgetTester tester) async {
  // The row's label: the middle of the row can fall between glyph and
  // label, where nothing in it takes the hit.
  await tester.tap(
    find
        .descendant(
          of: find.bySemanticsIdentifier(SemanticsIds.playlistDelete),
          matching: find.byType(Text),
        )
        .first,
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.bySemanticsIdentifier(SemanticsIds.playlistDeleteConfirm),
  );
  await tester.pumpAndSettle();
}

/// Deletes the playlist on screen from its own overflow.
Future<void> _deletePlaylist(WidgetTester tester) async {
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistOverflow));
  await tester.pumpAndSettle();
  await _confirmPlaylistDelete(tester);
}

UserAccount _account(String id, String username) => UserAccount(
  id: id,
  username: username,
  roles: const ['user'],
  createdAt: DateTime.utc(2026, 7, 1),
  libraryAccess: const LibraryAccess(mode: 'all'),
);

void main() {
  testWidgets('the arrow returns from a notification row to the list', (
    tester,
  ) async {
    final container = await _pumpApp(tester);
    await _go(tester, container, WaxRoute.notifications);
    container
        .read(localNotificationsProvider.notifier)
        .record(NotificationKind.task, at: DateTime.now());
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsIdentifier(
        SemanticsIds.notificationRowPlain(NotificationKind.task.token),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TasksScreen), findsOneWidget);

    await _back(tester);
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(_location(container), WaxRoute.notifications);
  });

  testWidgets('a row into another domain returns, and back again goes on '
      'to what came before', (tester) async {
    final container = await _pumpApp(tester);
    await _go(tester, container, WaxRoute.tasks);
    await _go(tester, container, WaxRoute.notifications);
    container
        .read(localNotificationsProvider.notifier)
        .record(
          NotificationKind.feedDisabled,
          at: DateTime.now(),
          pid: _showPid,
        );
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsIdentifier(
        SemanticsIds.notificationRow(
          NotificationKind.feedDisabled.token,
          _showPid,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ShowScreen), findsOneWidget);

    await _back(tester);
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(_location(container), WaxRoute.notifications);

    await _back(tester);
    expect(find.byType(TasksScreen), findsOneWidget);
    expect(_location(container), WaxRoute.tasks);
  });

  testWidgets('back from a destination of its own restores the drill-in it '
      'was opened over', (tester) async {
    final container = await _pumpApp(tester);
    await _go(tester, container, _album);
    expect(find.byType(AlbumScreen), findsOneWidget);
    final before = _stack(container);

    await _go(tester, container, WaxRoute.tasks);
    await _back(tester);

    expect(find.byType(AlbumScreen), findsOneWidget);
    expect(_location(container), _album);
    expect(_stack(container), before);
  });

  group('the destinations that had no arrow', () {
    testWidgets('Tasks goes back to where the visitor came from', (
      tester,
    ) async {
      // Not Home, which is what an up arrow would reach too.
      final container = await _pumpApp(tester);
      await _go(tester, container, WaxRoute.notifications);
      await _go(tester, container, WaxRoute.tasks);

      await _back(tester);
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(_location(container), WaxRoute.notifications);
    });

    testWidgets('Tasks opened cold goes up, to home', (tester) async {
      final container = await _pumpApp(tester, at: WaxRoute.tasks);
      expect(find.byType(TasksScreen), findsOneWidget);

      await _back(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(_location(container), WaxRoute.home);
    });

    testWidgets('Notifications goes back to where the visitor came from', (
      tester,
    ) async {
      final container = await _pumpApp(tester);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.notifications);

      await _back(tester);
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(_location(container), WaxRoute.tasks);
    });

    testWidgets('Notifications opened cold goes up, to home', (tester) async {
      final container = await _pumpApp(tester, at: WaxRoute.notifications);
      expect(find.byType(NotificationsScreen), findsOneWidget);

      await _back(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(_location(container), WaxRoute.home);
    });

    testWidgets('Review goes back to the notification that opened it', (
      tester,
    ) async {
      final container = await _pumpApp(tester);
      await _go(tester, container, WaxRoute.notifications);
      await _openHintRow(tester, container, NotificationKind.review);
      expect(find.byType(ReviewScreen), findsOneWidget);

      await _back(tester);
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(_location(container), WaxRoute.notifications);
    });

    testWidgets('a console section at sidebar width goes back to where the '
        'visitor came from', (tester) async {
      final container = await _pumpApp(tester);
      await _go(tester, container, WaxRoute.notifications);
      await _go(tester, container, WaxRoute.backups);
      expect(find.byType(BackupsScreen), findsOneWidget);

      await _back(tester);
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(_location(container), WaxRoute.notifications);
    });

    testWidgets('a console section opened cold goes up to the dashboard', (
      tester,
    ) async {
      final container = await _pumpApp(tester, at: WaxRoute.backups);
      expect(find.byType(BackupsScreen), findsOneWidget);

      await _back(tester);
      expect(_location(container), WaxRoute.admin);
    });
  });

  testWidgets('uploads reached by a go returns to where it was opened from', (
    tester,
  ) async {
    final container = await _pumpApp(tester);
    await _go(tester, container, WaxRoute.notifications);
    await _openHintRow(tester, container, NotificationKind.upload);
    expect(find.byType(UploadsScreen), findsOneWidget);

    await _back(tester);
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(_location(container), WaxRoute.notifications);
  });

  testWidgets('a decision on an entry page of its own is not somewhere back '
      'returns to', (tester) async {
    final container = await _pumpApp(tester, size: const Size(700, 1200));
    _repo(container).reviewEntries = [
      testReviewEntry('rv-1', title: 'First Album'),
      testReviewEntry('rv-2', title: 'Second Album'),
    ];
    await _go(tester, container, WaxRoute.notifications);
    await _go(tester, container, WaxRoute.review);
    await _go(tester, container, WaxRoute.reviewEntry('rv-1'));
    expect(find.byType(ReviewEntryScreen), findsOneWidget);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewScreen), findsOneWidget);
    expect(_location(container), WaxRoute.review);

    await _back(tester);
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(find.byType(ReviewEntryScreen), findsNothing);
    expect(_location(container), WaxRoute.notifications);
  });

  testWidgets('a decision on an entry page left before it landed is not '
      'returned to', (tester) async {
    final repo = _HeldDecisions();
    final container = await _pumpApp(
      tester,
      size: const Size(700, 1200),
      over: repo,
    );
    repo.reviewEntries = [
      testReviewEntry('rv-1', title: 'First Album'),
      testReviewEntry('rv-2', title: 'Second Album'),
    ];
    await _go(tester, container, WaxRoute.review);
    await _go(tester, container, WaxRoute.reviewEntry('rv-1'));
    await _go(tester, container, WaxRoute.tasks);
    await _go(tester, container, WaxRoute.reviewEntry('rv-1'));

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs));
    await tester.pump();
    await _back(tester);
    expect(find.byType(TasksScreen), findsOneWidget);
    repo.release.complete();
    await tester.pumpAndSettle();
    expect(repo.decideReviewCalls.single.entryId, 'rv-1');

    await _back(tester);
    expect(find.byType(ReviewEntryScreen), findsNothing);
    expect(_location(container), WaxRoute.review);
  });

  testWidgets('a decision on an entry page a notification opened returns to '
      'the queue, and back to the notifications', (tester) async {
    final container = await _pumpApp(tester, size: const Size(700, 1200));
    _repo(container).reviewEntries = [
      testReviewEntry('rv-1', title: 'First Album'),
      testReviewEntry('rv-2', title: 'Second Album'),
    ];
    await _go(tester, container, WaxRoute.notifications);
    container
        .read(localNotificationsProvider.notifier)
        .record(
          NotificationKind.importCompleted,
          at: DateTime.now(),
          pid: 'rv-1',
        );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(
        SemanticsIds.notificationRow(
          NotificationKind.importCompleted.token,
          'rv-1',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ReviewEntryScreen), findsOneWidget);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewScreen), findsOneWidget);
    expect(_location(container), WaxRoute.review);

    await _back(tester);
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(find.byType(ReviewEntryScreen), findsNothing);
    expect(_location(container), WaxRoute.notifications);
  });

  group('the review pane moved on by a decision', () {
    /// Two panes: an album, then the queue holding [ids], then the first
    /// opened in the pane from its row.
    Future<ProviderContainer> openFromAlbum(
      WidgetTester tester, {
      List<String> ids = const <String>['rv-1', 'rv-2'],
    }) async {
      final container = await _pumpApp(tester, size: const Size(1400, 1000));
      _repo(container).reviewEntries = [
        for (final id in ids) testReviewEntry(id),
      ];
      await _go(tester, container, _album);
      await _go(tester, container, WaxRoute.review);
      await _openReviewRow(tester, ids.first);
      return container;
    }

    String paneEntry(WidgetTester tester) =>
        tester.widget<ReviewEntryView>(find.byType(ReviewEntryView)).entryId;

    testWidgets('to the next entry is the same visit, and back never returns '
        'to the one decided', (tester) async {
      final container = await openFromAlbum(tester);

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs));
      await tester.pumpAndSettle();
      expect(_location(container), WaxRoute.reviewEntry('rv-2'));
      expect(paneEntry(tester), 'rv-2');

      await _back(tester);
      expect(_location(container), WaxRoute.review);
      expect(find.bySemanticsIdentifier(SemanticsIds.reviewPane), findsNothing);
      await _back(tester);
      expect(find.byType(AlbumScreen), findsOneWidget);
    });

    testWidgets('onto the list from the last entry leaves back going to what '
        'preceded the queue', (tester) async {
      final container = await openFromAlbum(tester, ids: const ['rv-1']);

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs));
      await tester.pumpAndSettle();
      expect(_location(container), WaxRoute.review);
      expect(find.bySemanticsIdentifier(SemanticsIds.reviewPane), findsNothing);

      await _back(tester);
      expect(find.byType(AlbumScreen), findsOneWidget);
    });

    /// Back from the pane until the album, and where each press landed.
    Future<List<String>> backToAlbum(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      final seen = <String>[];
      for (
        var i = 0;
        i < 5 && find.byType(AlbumScreen).evaluate().isEmpty;
        i++
      ) {
        await _back(tester);
        seen.add(_location(container));
      }
      expect(find.byType(AlbumScreen), findsOneWidget);
      return seen;
    }

    testWidgets('a bulk decision that did not take the open entry is not '
        'returned to', (tester) async {
      final container = await openFromAlbum(
        tester,
        ids: const ['rv-1', 'rv-2', 'rv-3'],
      );
      await _openReviewRow(tester, 'rv-2');
      await tester.longPress(
        find.bySemanticsIdentifier(SemanticsIds.reviewRow('rv-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.reviewRow('rv-3')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip));
      await tester.pumpAndSettle();
      expect(paneEntry(tester), 'rv-2');

      expect(
        await backToAlbum(tester, container),
        isNot(contains(WaxRoute.reviewEntry('rv-1'))),
      );
    });

    testWidgets('a key decision on a row the pane does not show is not '
        'returned to', (tester) async {
      final container = await openFromAlbum(tester);
      await _openReviewRow(tester, 'rv-2');
      // The cursor came to the open row; k moves it to the one above.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();
      expect(_repo(container).decideReviewCalls.single.entryId, 'rv-1');
      expect(paneEntry(tester), 'rv-2');

      expect(
        await backToAlbum(tester, container),
        isNot(contains(WaxRoute.reviewEntry('rv-1'))),
      );
    });

    testWidgets('off an entry visited before is not returned to by any back', (
      tester,
    ) async {
      final container = await openFromAlbum(
        tester,
        ids: const ['rv-1', 'rv-2', 'rv-3'],
      );
      await _openReviewRow(tester, 'rv-2');
      await _openReviewRow(tester, 'rv-1');

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs));
      await tester.pumpAndSettle();
      expect(paneEntry(tester), 'rv-2');

      final seen = <String>[];
      for (
        var i = 0;
        i < 5 && find.byType(AlbumScreen).evaluate().isEmpty;
        i++
      ) {
        await _back(tester);
        seen.add(_location(container));
      }
      expect(seen, isNot(contains(WaxRoute.reviewEntry('rv-1'))));
      expect(find.byType(AlbumScreen), findsOneWidget);
    });
  });

  group('a child gone to with a query', () {
    // What settings search does: the section opens with the setting asked
    // for in its query, and a pop carries that query onto the parent.
    Future<ProviderContainer> openSetting(WidgetTester tester) async {
      final container = await _pumpApp(tester);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.settings);
      await _go(
        tester,
        container,
        WaxRoute.settingsSection(
          SettingsSection.playback,
          setting: 'crossfade',
        ),
      );
      expect(find.byType(SettingsSectionScreen), findsOneWidget);
      return container;
    }

    testWidgets('the arrow returns to its parent, and back goes on', (
      tester,
    ) async {
      final container = await openSetting(tester);

      await _back(tester);
      expect(find.byType(SettingsScreen), findsOneWidget);

      await _back(tester, hub: true);
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(_location(container), WaxRoute.tasks);
    });

    testWidgets('a pop steps back to the parent visit, not in place', (
      tester,
    ) async {
      final container = await openSetting(tester);

      // What `leave` and the system back's router rung do.
      _router(container).pop();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      await _back(tester, hub: true);
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(_location(container), WaxRoute.tasks);
    });
  });

  testWidgets('a search refined over a hit it opened is a visit of its own', (
    tester,
  ) async {
    final container = await _pumpApp(tester);
    final jazz = WaxRoute.searchFor('jazz');
    await _go(tester, container, jazz);
    unawaited(_router(container).push<void>(_album));
    await tester.pumpAndSettle();
    expect(find.byType(AlbumScreen), findsOneWidget);
    // What the header field does on a submit over the hit.
    await _go(tester, container, WaxRoute.searchFor('blues'));

    await _back(tester);
    expect(find.byType(AlbumScreen), findsOneWidget);
    expect(_location(container), jazz);

    await _back(tester);
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.byType(AlbumScreen), findsNothing);
    expect(_location(container), jazz);
  });

  testWidgets('a search refined in place is one visit, which back leaves', (
    tester,
  ) async {
    final container = await _pumpApp(tester);
    await _go(tester, container, WaxRoute.tasks);
    await _go(tester, container, WaxRoute.searchFor('j'));
    for (final query in <String>['ja', 'jazz']) {
      tester.element(find.byType(SearchScreen)).swap(WaxRoute.searchFor(query));
      await tester.pumpAndSettle();
    }
    expect(_location(container), WaxRoute.searchFor('jazz'));

    await _back(tester);
    expect(find.byType(TasksScreen), findsOneWidget);
    expect(_location(container), WaxRoute.tasks);
  });

  testWidgets('an up go inside the stack is not somewhere back returns to', (
    tester,
  ) async {
    final container = await _pumpApp(
      tester,
      items: <ItemSummary>[testItem('tr-001', title: 'Track 1')],
    );
    await _go(tester, container, WaxRoute.musicTracks);
    unawaited(_router(container).push<void>(WaxRoute.metadata('tr-001')));
    await tester.pumpAndSettle();
    await _go(tester, container, WaxRoute.musicTracks);
    expect(find.byType(MetadataScreen), findsNothing);

    await _back(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(_location(container), WaxRoute.home);
  });

  testWidgets('a refresh under a push is not somewhere back returns to', (
    tester,
  ) async {
    // A refresh decodes the list on screen again, every push with a fresh
    // completer and the page key it had.
    final container = await _pumpApp(
      tester,
      items: <ItemSummary>[testItem('tr-001', title: 'Track 1')],
    );
    await _go(tester, container, WaxRoute.musicTracks);
    unawaited(_router(container).push<void>(WaxRoute.metadata('tr-001')));
    await tester.pumpAndSettle();
    _router(container).refresh();
    await tester.pumpAndSettle();
    expect(find.byType(MetadataScreen), findsOneWidget);

    await _back(tester);
    expect(find.byType(MetadataScreen), findsNothing);
    expect(find.byType(MusicListingScreen), findsOneWidget);
  });

  testWidgets('back from a page somebody awaits hands them null', (
    tester,
  ) async {
    final container = await _pumpApp(tester);
    await _go(tester, container, WaxRoute.podcasts);

    var answered = false;
    Object? answer = 'unanswered';
    unawaited(
      _router(container).push<String>(WaxRoute.episode(_episodePid)).then((
        value,
      ) {
        answered = true;
        answer = value;
      }),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EpisodeScreen), findsOneWidget);

    await _back(tester);

    expect(tester.takeException(), isNull);
    expect(answered, isTrue, reason: 'the push has to be popped, not dropped');
    expect(answer, isNull);
    expect(find.byType(PodcastsScreen), findsOneWidget);
  });

  group('a visit of a push somebody awaits', () {
    /// Podcasts with an episode pushed over it, awaited, and what its
    /// opener heard so far.
    Future<(ProviderContainer, List<Object?>)> pushed(
      WidgetTester tester,
    ) async {
      final container = await _pumpApp(tester);
      await _go(tester, container, WaxRoute.podcasts);
      final heard = <Object?>[];
      unawaited(
        _router(
          container,
        ).push<String>(WaxRoute.episode(_episodePid)).then(heard.add),
      );
      await tester.pumpAndSettle();
      expect(container.read(waxHistoryProvider)!.heldAwaiters, hasLength(1));
      return (container, heard);
    }

    testWidgets('holds no completer once its page is popped', (tester) async {
      final (container, heard) = await pushed(tester);

      _router(container).pop<String>('played');
      await tester.pumpAndSettle();

      expect(heard, <Object?>['played']);
      expect(container.read(waxHistoryProvider)!.heldAwaiters, isEmpty);
    });

    testWidgets('holds no completer once a go in its branch takes the page '
        'off', (tester) async {
      final (container, heard) = await pushed(tester);

      await _go(tester, container, WaxRoute.show(_showPid));

      expect(find.byType(EpisodeScreen, skipOffstage: false), findsNothing);
      expect(container.read(waxHistoryProvider)!.heldAwaiters, isEmpty);
    });

    testWidgets('keeps its completer while the page waits in another branch, '
        'and the opener hears through it', (tester) async {
      final (container, heard) = await pushed(tester);
      await _go(tester, container, WaxRoute.radio);
      expect(container.read(waxHistoryProvider)!.heldAwaiters, hasLength(1));

      await _back(tester, hub: true);
      expect(find.byType(EpisodeScreen), findsOneWidget);
      _router(container).pop<String>('played');
      await tester.pumpAndSettle();

      expect(heard, <Object?>['played']);
      expect(container.read(waxHistoryProvider)!.heldAwaiters, isEmpty);
    });
  });

  testWidgets('back from a push over a location it does not record pops it '
      'and its opener hears null', (tester) async {
    // Signed out, so the app is on the login form, which is not recorded.
    final container = await pumpWholeApp(
      tester,
      container: appContainer(),
      disableAnimations: true,
    );
    expect(find.byType(LoginScreen), findsOneWidget);

    var answered = false;
    Object? answer = 'unanswered';
    unawaited(
      _router(container).push<String>(WaxRoute.signup).then((value) {
        answered = true;
        answer = value;
      }),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SignupScreen), findsOneWidget);

    await _back(tester);

    expect(answered, isTrue, reason: 'the push has to be popped, not dropped');
    expect(answer, isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(_location(container), WaxRoute.login);
  });

  testWidgets('back from signup over a login carrying where it was asked for '
      'keeps that', (tester) async {
    // Signed out on a deep link: the redirect carries it into the form.
    tester.platformDispatcher.defaultRouteNameTestValue = WaxRoute.musicTracks;
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
    final container = await pumpWholeApp(
      tester,
      container: appContainer(),
      disableAnimations: true,
    );
    final login = _location(container);
    expect(Uri.parse(login).queryParameters[WaxRoute.fromParam], isNotNull);

    // The way the login screen opens it.
    var answered = false;
    Object? answer = 'unanswered';
    unawaited(
      _router(container).push<String>(WaxRoute.signup).then((value) {
        answered = true;
        answer = value;
      }),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SignupScreen), findsOneWidget);

    await _back(tester);

    expect(answered, isTrue, reason: 'the push has to be popped, not dropped');
    expect(answer, isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(_location(container), login);
  });

  testWidgets('a cold link pops through the pages its location declares', (
    tester,
  ) async {
    final container = await _pumpApp(tester, at: WaxRoute.artistTracks('ar-1'));
    expect(find.byType(MusicListingScreen), findsOneWidget);

    await _back(tester);
    expect(find.byType(ArtistScreen), findsOneWidget);
    expect(
      _location(container),
      WaxRoute.musicBucket(MusicDimension.artists, 'ar-1'),
    );

    await _back(tester);
    expect(find.byType(MusicIndexScreen), findsOneWidget);
    expect(_location(container), WaxRoute.musicIndex(MusicDimension.artists));
  });

  group('an editor its opener awaits', () {
    Future<ProviderContainer> openEditor(WidgetTester tester) async {
      final container = await _pumpApp(tester);
      _repo(container).usersById['us-3'] = _account('us-3', 'merry');
      await _go(tester, container, WaxRoute.users);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.userRow('us-3')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(UserEditScreen), findsOneWidget);
      return container;
    }

    // Saving pops the editor with true, and the list re-reads on that; an
    // account added meanwhile shows only if it did.
    Future<void> save(WidgetTester tester, ProviderContainer container) async {
      _repo(container).usersById['us-4'] = _account('us-4', 'pippin');
      final save = find.bySemanticsIdentifier(SemanticsIds.userSave);
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
    }

    testWidgets('hears it saved after a trip to another domain and back', (
      tester,
    ) async {
      final container = await openEditor(tester);
      await _go(tester, container, WaxRoute.radio);

      await _back(tester, hub: true);
      expect(find.byType(UserEditScreen), findsOneWidget);
      await save(tester, container);

      expect(tester.takeException(), isNull);
      expect(find.byType(UsersScreen), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.userRow('us-4')),
        findsOneWidget,
      );
    });

    testWidgets('left by a go inside its domain is reopened for nobody', (
      tester,
    ) async {
      // The opener's page went with the go, so answering it would run its
      // code on a disposed page.
      final container = await openEditor(tester);
      await _go(tester, container, WaxRoute.tasks);

      await _back(tester);
      expect(find.byType(UserEditScreen), findsOneWidget);
      await save(tester, container);

      expect(tester.takeException(), isNull);
      expect(find.byType(UsersScreen), findsOneWidget);
    });

    testWidgets('already answered is not answered again', (tester) async {
      final container = await openEditor(tester);
      final opened = _topPush(container);
      await _go(tester, container, WaxRoute.radio);
      // Answered with its page still mounted, which go_router does only in
      // the turn of a pop: reused, the next pop would answer it twice.
      opened.complete(false);
      await tester.pump();

      await _back(tester, hub: true);
      expect(find.byType(UserEditScreen), findsOneWidget);
      await save(tester, container);

      expect(tester.takeException(), isNull);
      expect(find.byType(UsersScreen), findsOneWidget);
    });
  });

  testWidgets('a cold link has nowhere it came from, so back goes up', (
    tester,
  ) async {
    final container = await _pumpApp(
      tester,
      at: WaxRoute.showEpisode(_showPid, _episodePid),
    );
    expect(find.byType(EpisodeScreen), findsOneWidget);

    // Each with the fallback its screen declares; the hub has no arrow.
    await _back(tester);
    expect(find.byType(ShowScreen), findsOneWidget);
    expect(_location(container), WaxRoute.show(_showPid));

    await _back(tester);
    expect(find.byType(PodcastsScreen), findsOneWidget);
    expect(_location(container), WaxRoute.podcasts);

    await _back(tester, hub: true);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(_location(container), WaxRoute.home);
    expect(container.read(waxHistoryProvider)!.canGoBack, isFalse);
  });

  group('a deleted playlist', () {
    testWidgets('deleted from its own screen is skipped on the way back', (
      tester,
    ) async {
      final container = await _pumpApp(tester);
      final playlist = await _repo(
        container,
      ).createPlaylist(name: 'Road Trip', kind: 'static', itemPids: const []);
      final at = WaxRoute.playlist(playlist.pid);
      await _go(tester, container, WaxRoute.notifications);
      await _go(tester, container, at);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, at);

      await _deletePlaylist(tester);
      expect(find.byType(PlaylistsScreen), findsOneWidget);

      await _back(tester, hub: true);
      expect(find.byType(TasksScreen), findsOneWidget);

      await _back(tester);
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(find.byType(PlaylistScreen), findsNothing);
      expect(_location(container), WaxRoute.notifications);
    });

    testWidgets('deleted from its hub card is skipped on the way back and '
        'read afresh', (tester) async {
      final container = await _pumpApp(tester);
      final playlist = await _repo(
        container,
      ).createPlaylist(name: 'Road Trip', kind: 'static', itemPids: const []);
      final at = WaxRoute.playlist(playlist.pid);
      await _go(tester, container, WaxRoute.notifications);
      await _go(tester, container, at);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.playlists);

      await rightClick(
        tester,
        find.bySemanticsIdentifier(SemanticsIds.playlist(playlist.pid)),
      );
      await _confirmPlaylistDelete(tester);
      expect(find.byType(PlaylistsScreen), findsOneWidget);

      // The hub draws no arrow.
      await _back(tester, hub: true);
      expect(find.byType(TasksScreen), findsOneWidget);
      await _back(tester);
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(find.byType(PlaylistScreen), findsNothing);

      // What the screen read of it before is gone with it: a visit asks
      // the server, which says the playlist is not there.
      await _go(tester, container, at);
      expect(find.text('Could not load this playlist'), findsOneWidget);
    });

    testWidgets('forgotten while on screen leaves back below it', (
      tester,
    ) async {
      final container = await _pumpApp(tester);
      final at = WaxRoute.playlist(_playlistPid);
      await _go(tester, container, WaxRoute.notifications);
      await _go(tester, container, at);
      await _go(tester, container, WaxRoute.tasks);
      await _back(tester);
      expect(find.byType(PlaylistScreen), findsOneWidget);

      tester.element(find.byType(PlaylistScreen)).forget(at);
      await _back(tester);

      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(_location(container), WaxRoute.notifications);
    });

    testWidgets('forgotten as the only visit leaves nowhere recorded', (
      tester,
    ) async {
      final at = WaxRoute.playlist(_playlistPid);
      final container = await _pumpApp(tester, at: at);
      expect(find.byType(PlaylistScreen), findsOneWidget);

      tester.element(find.byType(PlaylistScreen)).forget(at);
      expect(container.read(waxHistoryProvider)!.canGoBack, isFalse);

      await _back(tester);
      expect(find.byType(PlaylistsScreen), findsOneWidget);
      await _go(tester, container, WaxRoute.tasks);
      await _back(tester);
      expect(find.byType(PlaylistsScreen), findsOneWidget);
      expect(_location(container), WaxRoute.playlists);
    });

    testWidgets('deleted elsewhere is returned to and says it is gone', (
      tester,
    ) async {
      final container = await _pumpApp(tester);
      final repo = _repo(container);
      final playlist = await repo.createPlaylist(
        name: 'Road Trip',
        kind: 'static',
        itemPids: const [],
      );
      await _go(tester, container, WaxRoute.playlist(playlist.pid));
      await _go(tester, container, WaxRoute.tasks);
      // Gone on the server, and the change feed drops what was read of it.
      await repo.deletePlaylist(playlist.pid);
      container.invalidate(playlistDetailProvider);

      await _back(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(PlaylistScreen), findsOneWidget);
      expect(_location(container), WaxRoute.playlist(playlist.pid));
      expect(find.text('Could not load this playlist'), findsOneWidget);
    });
  });

  group('an item deleted from its own screen', () {
    // Deletes the entity on screen from its overflow menu and confirms.
    Future<void> deleteFrom(WidgetTester tester, String overflow) async {
      await tester.tap(find.bySemanticsIdentifier(overflow));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.itemMenuDelete));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.itemDeleteConfirm),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('an album is skipped on the way back', (tester) async {
      final container = await _pumpApp(tester);
      _repo(container).facetItems['album ${_albumPid.substring(3)}'] = [
        testItem('tr-1', title: 'One'),
        testItem('tr-2', title: 'Two'),
      ];
      await _go(tester, container, WaxRoute.notifications);
      await _go(tester, container, _album);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, _album);

      await deleteFrom(tester, SemanticsIds.entityOverflow);
      expect(find.byType(AlbumScreen), findsNothing);

      await _back(tester);
      expect(find.byType(TasksScreen), findsOneWidget);
      await _back(tester);
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(find.byType(AlbumScreen), findsNothing);
    });

    testWidgets('an album takes its workbench with it, wherever it was '
        'pushed', (tester) async {
      final container = await _pumpApp(tester);
      _repo(container).facetItems['album ${_albumPid.substring(3)}'] = [
        testItem('tr-1', title: 'One'),
        testItem('tr-2', title: 'Two'),
      ];
      await _go(tester, container, WaxRoute.notifications);
      await _go(tester, container, WaxRoute.tasks);
      // The release workbench over another root, not over the album.
      unawaited(_router(container).push<void>(WaxRoute.metadata(_albumPid)));
      await tester.pumpAndSettle();
      expect(_stack(container), contains(WaxRoute.metadata(_albumPid)));
      await _go(tester, container, _album);

      await deleteFrom(tester, SemanticsIds.entityOverflow);
      expect(find.byType(AlbumScreen), findsNothing);

      await _back(tester);
      expect(_stack(container), isNot(contains(WaxRoute.metadata(_albumPid))));
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(_location(container), WaxRoute.tasks);
    });

    testWidgets('a book is skipped on the way back', (tester) async {
      final container = await _pumpApp(tester);
      _repo(container)
        ..books[_bookPid] = testBook(_bookPid, partCount: 2)
        ..libraryItems.add(testItem(_bookPid));
      await _go(tester, container, WaxRoute.notifications);
      await _go(tester, container, WaxRoute.book(_bookPid));
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.book(_bookPid));

      await deleteFrom(tester, SemanticsIds.bookOverflow);
      expect(find.byType(BookScreen), findsNothing);
      expect(find.byType(BooksScreen), findsOneWidget);

      await _back(tester, hub: true);
      expect(find.byType(TasksScreen), findsOneWidget);
      await _back(tester);
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(find.byType(BookScreen), findsNothing);
    });
  });

  group('a deleted episode', () {
    testWidgets('is skipped wherever it was visited', (tester) async {
      final container = await _pumpApp(tester);
      await _go(tester, container, WaxRoute.show(_showPid));
      // Opened from the show's row: the episode beneath its show.
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.episodeInfo(_episodePid)),
      );
      await tester.pumpAndSettle();
      expect(_location(container), WaxRoute.showEpisode(_showPid, _episodePid));
      await _go(tester, container, WaxRoute.tasks);
      // And again by another route: a search hit's, with no show in hand.
      unawaited(_router(container).push<void>(WaxRoute.episode(_episodePid)));
      await tester.pumpAndSettle();
      expect(find.byType(EpisodeScreen), findsOneWidget);

      // The way the player's menu asks for it.
      unawaited(
        confirmDeleteItem(
          tester.element(find.byType(EpisodeScreen)),
          pid: _episodePid,
          onDeleted: _router(container).leave,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.itemDeleteConfirm),
      );
      await tester.pumpAndSettle();
      expect(_repo(container).deleteItemsCalls.last.dryRun, isFalse);
      expect(find.byType(TasksScreen), findsOneWidget);

      await _back(tester);
      expect(find.byType(EpisodeScreen), findsNothing);
      expect(_location(container), WaxRoute.show(_showPid));

      await _back(tester);
      expect(find.byType(EpisodeScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(_location(container), WaxRoute.home);
    });
  });

  group('a location forgotten by its tail', () {
    testWidgets('keeps a visit whose id only starts with the one forgotten', (
      tester,
    ) async {
      final container = await _pumpApp(tester);
      final longer = WaxRoute.showEpisode(_showPid, 'tr-11');
      await _go(tester, container, longer);
      await _go(tester, container, WaxRoute.tasks);

      container
          .read(waxHistoryProvider)!
          .forget(WaxRoute.episode('tr-1'), anywhere: true);

      await _back(tester);
      expect(_location(container), longer);
    });

    testWidgets('drops a location the tail sits inside of, followed by a '
        'slash', (tester) async {
      final container = await _pumpApp(tester);
      final deeper = WaxRoute.artistTracks('ar-1');
      final other = WaxRoute.artistTracks('ar-11');
      await _go(tester, container, deeper);
      await _go(tester, container, other);
      await _go(tester, container, WaxRoute.tasks);

      container
          .read(waxHistoryProvider)!
          .forget('/${MusicDimension.artists.segment}/ar-1', anywhere: true);

      await _back(tester);
      expect(_location(container), other);
      await _back(tester);
      expect(_location(container), WaxRoute.home);
    });
  });

  group('a deleted account', () {
    Future<void> openAccount(
      WidgetTester tester,
      ProviderContainer container,
      String id,
    ) async {
      await _go(tester, container, WaxRoute.users);
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.userRow(id)));
      await tester.pumpAndSettle();
      expect(find.byType(UserEditScreen), findsOneWidget);
    }

    Future<void> deleteAccount(WidgetTester tester) async {
      final delete = find.bySemanticsIdentifier(SemanticsIds.userDelete);
      await tester.ensureVisible(delete);
      await tester.pumpAndSettle();
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('user-confirm')));
      await tester.pumpAndSettle();
      expect(find.byType(UserEditScreen), findsNothing);
    }

    testWidgets('has its editor skipped on the way back', (tester) async {
      final container = await _pumpApp(tester);
      _repo(container).usersById['us-3'] = _account('us-3', 'merry');
      await openAccount(tester, container, 'us-3');
      await _go(tester, container, WaxRoute.radio);
      await openAccount(tester, container, 'us-3');

      await deleteAccount(tester);
      expect(_repo(container).deletedUserIds, ['us-3']);

      await _back(tester);
      expect(find.byType(UserEditScreen), findsNothing);
      expect(_location(container), WaxRoute.radio);

      await _back(tester, hub: true);
      expect(find.byType(UserEditScreen), findsNothing);
    });

    testWidgets("leaves another account's editor to back", (tester) async {
      final container = await _pumpApp(tester);
      _repo(container)
        ..usersById['us-3'] = _account('us-3', 'merry')
        ..usersById['us-4'] = _account('us-4', 'pippin');
      await openAccount(tester, container, 'us-4');
      await _go(tester, container, WaxRoute.radio);
      await openAccount(tester, container, 'us-3');

      await deleteAccount(tester);
      await _back(tester);
      expect(_location(container), WaxRoute.radio);

      await _back(tester, hub: true);
      expect(find.byType(UserEditScreen), findsOneWidget);
    });
  });

  testWidgets('back to a console section after the role is gone lands on '
      'the refusal', (tester) async {
    final container = await _pumpApp(tester);
    await _go(tester, container, WaxRoute.backups);
    await _go(tester, container, WaxRoute.tasks);

    _repo(container).sessionState = const SessionState(
      authenticated: true,
      user: WaxDeckUser(
        id: 'us-1',
        username: 'admin',
        roles: ['user'],
        uploadEnabled: true,
      ),
    );
    await container.read(authControllerProvider.notifier).refreshSession();
    await tester.pumpAndSettle();

    await _back(tester);

    expect(tester.takeException(), isNull);
    expect(_location(container), WaxRoute.backups);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.adminForbidden),
      findsOneWidget,
    );
  });

  testWidgets('the history keeps the last fifty visits', (tester) async {
    final container = await _pumpApp(tester);
    for (var hop = 0; hop < 60; hop++) {
      await _go(tester, container, WaxRoute.searchFor('hop $hop'));
    }

    final history = container.read(waxHistoryProvider)!;
    var steps = 0;
    while (history.canGoBack && steps < 100) {
      await _back(tester);
      steps++;
    }

    // Home and sixty hops are sixty-one visits; the fifty kept start at
    // the tenth hop.
    expect(steps, 49);
    expect(_location(container), WaxRoute.searchFor('hop 10'));
  });

  testWidgets('collapsing the player is not somewhere back returns to', (
    tester,
  ) async {
    final container = await _pumpApp(tester);
    container.read(nowPlayingProvider.notifier).play(
      [testItem('tr-A', title: 'Salt Harbour')],
      source: const QueueSource(
        kind: QueueSourceKind.single,
        label: 'Salt Harbour',
      ),
    );
    await tester.pumpAndSettle();
    await _go(tester, container, WaxRoute.tasks);
    await _go(tester, container, _album);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.deckExpand));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerScreen), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerBack));
    await tester.pumpAndSettle();
    expect(find.byType(AlbumScreen), findsOneWidget);

    await _back(tester);

    expect(find.byType(TasksScreen), findsOneWidget);
    expect(find.byType(PlayerScreen), findsNothing);
    expect(_location(container), WaxRoute.tasks);

    container.read(queueControllerProvider.notifier).clear();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a listing an editor was pushed over keeps its place across a '
      'trip away and back', (tester) async {
    final container = await _pumpApp(
      tester,
      items: <ItemSummary>[
        for (var n = 0; n < 60; n++)
          testItem('tr-${n.toString().padLeft(3, '0')}', title: 'Track $n'),
      ],
    );
    await _go(tester, container, WaxRoute.musicTracks);
    final listing = find.descendant(
      of: find.byType(MusicListingScreen),
      matching: find.byType(Scrollable),
    );
    await tester.drag(listing.first, const Offset(0, -1200));
    await tester.pumpAndSettle();
    double offset() =>
        tester.state<ScrollableState>(listing.first).position.pixels;
    final scrolled = offset();
    expect(scrolled, greaterThan(0));

    unawaited(_router(container).push<void>(WaxRoute.metadata('tr-001')));
    await tester.pumpAndSettle();
    final editor = tester.element(find.byType(MetadataScreen));
    await _go(tester, container, WaxRoute.tasks);

    await _back(tester);
    // The page it had, not one built again: the restored push carries the
    // key the branch's navigator still holds it under.
    expect(tester.element(find.byType(MetadataScreen)), same(editor));
    expect(_location(container), WaxRoute.musicTracks);

    _router(container).pop();
    await tester.pumpAndSettle();
    expect(find.byType(MusicListingScreen), findsOneWidget);
    expect(offset(), scrolled);
  });

  testWidgets('another account arriving forgets where the last one went', (
    tester,
  ) async {
    final container = await _pumpApp(tester);
    await _go(tester, container, WaxRoute.tasks);
    await _go(tester, container, WaxRoute.notifications);
    expect(container.read(waxHistoryProvider)!.canGoBack, isTrue);

    // A tab that signed another account in over this browser's session.
    _repo(container).sessionState = const SessionState(
      authenticated: true,
      user: WaxDeckUser(id: 'us-9', username: 'kit', roles: ['user']),
    );
    // Not awaited: the swap waits for the last account's screens to go,
    // which takes frames.
    unawaited(container.read(authControllerProvider.notifier).refreshSession());
    await tester.pumpAndSettle();

    expect(_location(container), WaxRoute.notifications);
    expect(container.read(waxHistoryProvider)!.canGoBack, isFalse);
  });

  testWidgets('back walks through tab taps', (tester) async {
    // Hubs draw no arrow, so each step runs what an arrow there would do.
    final container = await _pumpApp(tester);
    await _tapNav(tester, WaxNavTarget.radio);
    await _tapNav(tester, WaxNavTarget.music);
    await _tapNav(tester, WaxNavTarget.podcasts);

    await _back(tester, hub: true);
    expect(_location(container), WaxRoute.music);
    await _back(tester, hub: true);
    expect(_location(container), WaxRoute.radio);
    await _back(tester, hub: true);
    expect(_location(container), WaxRoute.home);
  });

  // A screen's own host, whose router is not the app's.
  group('without a history', () {
    String location(WidgetTester tester) =>
        routerOf(tester).routerDelegate.currentConfiguration.uri.toString();

    testWidgets('back pops what is underneath', (tester) async {
      final container = await pumpApp(
        tester,
        const RadioSavedScreen(),
        pushed: true,
      );

      await _back(tester);

      expect(find.byType(RadioSavedScreen), findsNothing);
      expect(location(tester), isNot(WaxRoute.radio));
      expect(routerOf(tester).canPop(), isFalse);
      expect(container.exists(routerProvider), isFalse);
    });

    testWidgets('back with nothing underneath goes to its fallback', (
      tester,
    ) async {
      final container = await pumpApp(tester, const RadioSavedScreen());

      await _back(tester);

      expect(location(tester), WaxRoute.radio);
      expect(container.exists(routerProvider), isFalse);
    });

    testWidgets('the provider answers once a router is built after it was '
        'read', (tester) async {
      final container = appContainer();
      expect(container.read(waxHistoryProvider), isNull);

      container.read(routerProvider);
      // The session the router's redirect reads settles in the background.
      await tester.pumpAndSettle();

      expect(container.read(waxHistoryProvider), isNotNull);
    });

    testWidgets('the provider answers null and builds no router', (
      tester,
    ) async {
      final container = await pumpApp(tester, const TasksScreen());

      expect(container.read(waxHistoryProvider), isNull);
      expect(container.exists(routerProvider), isFalse);
    });
  });
}
