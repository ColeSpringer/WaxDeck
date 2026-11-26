import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/admin/user_edit_screen.dart';
import 'package:waxdeck/src/admin/users_screen.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/login_screen.dart';
import 'package:waxdeck/src/auth/signup_screen.dart';
import 'package:waxdeck/src/books/book_bucket_screen.dart';
import 'package:waxdeck/src/books/book_dimension.dart';
import 'package:waxdeck/src/books/book_screen.dart';
import 'package:waxdeck/src/books/books_screen.dart';
import 'package:waxdeck/src/books/series_screen.dart';
import 'package:waxdeck/src/connect/remote_session.dart';
import 'package:waxdeck/src/discovery/discovery_actions.dart';
import 'package:waxdeck/src/discovery/track_list_screen.dart';
import 'package:waxdeck/src/home/home_screen.dart';
import 'package:waxdeck/src/home/home_shelves.dart';
import 'package:waxdeck/src/home/mix_shelf.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/library/item_delete.dart';
import 'package:waxdeck/src/library/item_kind.dart';
import 'package:waxdeck/src/metadata/entity_editor_screen.dart';
import 'package:waxdeck/src/metadata/metadata_screen.dart';
import 'package:waxdeck/src/metadata/rename_section.dart';
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
import 'package:waxdeck/src/playlists/playlists_screen.dart';
import 'package:waxdeck/src/playlists/rule_editor_screen.dart';
import 'package:waxdeck/src/podcasts/episode_screen.dart';
import 'package:waxdeck/src/podcasts/podcasts_screen.dart';
import 'package:waxdeck/src/podcasts/show_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_screen.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck/src/radio/radio_screen.dart';
import 'package:waxdeck/src/review/review_entry_screen.dart';
import 'package:waxdeck/src/review/review_screen.dart';
import 'package:waxdeck/src/search/search_screen.dart';
import 'package:waxdeck/src/shell/adaptive_shell.dart';
import 'package:waxdeck/src/shell/navigation_history.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/tools/tasks_screen.dart';
import 'package:waxdeck/src/uploads/uploads_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fake_browser.dart';
import 'fakes.dart';

// Back on web, where the browser keeps the list too: the arrow is the
// browser's own back, and a browser back or forward is told apart from a
// tab tap by the browser saying so.

const _showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const _episodePid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';
const _albumPid = 'al-01JZX5N8QW3F4V9T2B7KDALBUM1';
const _otherAlbumPid = 'al-01JZX5N8QW3F4V9T2B7KDALBUM2';
const _bookPid = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';
const _otherBookPid = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK02';
const _stationPid = 'rs-01JZX5N8QW3F4V9T2B7KDSTATN1';

final _station = RadioStation(
  pid: _stationPid,
  name: 'Coastal FM',
  streamUrl: 'https://stream.example/coastal',
  createdAt: DateTime.utc(2026, 7, 1),
);

const _admin = WaxDeckUser(
  id: 'us-1',
  username: 'admin',
  roles: ['admin'],
  uploadEnabled: true,
);

/// The whole app at desktop width in a browser tab, or at [size], signed
/// in unless [signedIn] is false; [at] opens it cold on a link. [native]
/// keeps the browser's list but not its buttons: the history is the app's
/// own, as on a phone or a desktop. [behind] says whether the tab holds a
/// page before the app. With [reloading], that tab reloads the app on the
/// entry it is on, and the app starts over there; with [returning], it
/// loads again by a return to it instead. [animated] leaves the
/// transitions on, for a test that looks at each frame of one.
Future<(ProviderContainer, FakeBrowser)> _pumpTab(
  WidgetTester tester, {
  String? at,
  bool signedIn = true,
  Size size = const Size(1000, 900),
  bool native = false,
  bool behind = true,
  bool animated = false,
  FakeBrowser? reloading,
  bool returning = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  reloading?.reload(returning: returning);
  final link = reloading?.location ?? at;
  if (link != null) {
    tester.platformDispatcher.defaultRouteNameTestValue = link;
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
  }
  final repo =
      (signedIn
            ? FakeRepository(
                sessionState: const SessionState(
                  authenticated: true,
                  user: _admin,
                ),
              )
            : FakeRepository())
        ..addSubscription(testShow(_showPid))
        ..episodesByShow[_showPid] = <EpisodeSummary>[testEpisode(_episodePid)]
        ..albums[_albumPid] = const AlbumDetail(
          pid: _albumPid,
          title: 'Gullwing',
        );
  final browser = reloading ?? FakeBrowser(before: behind ? 1 : 0);
  final container = appContainer(
    repo: repo,
    extra: [if (!native) browserHistoryProvider.overrideWithValue(browser)],
  );
  await pumpWholeApp(
    tester,
    container: container,
    disableAnimations: !animated,
  );
  return (container, browser);
}

GoRouter _router(ProviderContainer container) => container.read(routerProvider);

FakeRepository _repo(ProviderContainer container) =>
    container.read(repositoryProvider) as FakeRepository;

String _location(ProviderContainer container) =>
    _router(container).routerDelegate.currentConfiguration.uri.toString();

Future<void> _go(
  WidgetTester tester,
  ProviderContainer container,
  String location,
) async {
  _router(container).go(location);
  await tester.pumpAndSettle();
}

/// A tap on the arrow on top; a hub draws none, so [hub] runs back the
/// way the system back does there.
Future<void> _back(WidgetTester tester, {bool hub = false}) async {
  if (hub) {
    tester.element(find.byType(WaxScaffold).last).back();
  } else {
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.navBack));
  }
  await tester.pumpAndSettle();
}

/// Every location the router arrives at from here on: one it never
/// arrived at was never built.
List<String> _arrivals(ProviderContainer container) {
  final delegate = _router(container).routerDelegate;
  final seen = <String>[];
  void heard() => seen.add(delegate.currentConfiguration.uri.toString());
  delegate.addListener(heard);
  addTearDown(() => delegate.removeListener(heard));
  return seen;
}

/// Every push the router arrives with from here on, which a location
/// does not show.
List<String> _pushArrivals(ProviderContainer container) {
  final delegate = _router(container).routerDelegate;
  final seen = <String>[];
  void walk(List<RouteMatchBase> matches) {
    for (final match in matches) {
      switch (match) {
        case ShellRouteMatch():
          walk(match.matches);
        case ImperativeRouteMatch():
          seen.add(match.matches.uri.toString());
        case _:
      }
    }
  }

  void heard() => walk(delegate.currentConfiguration.matches);
  delegate.addListener(heard);
  addTearDown(() => delegate.removeListener(heard));
  return seen;
}

/// The locations pushed over the router's location, bottom first, as a
/// browser entry keeps them.
List<String> _pushes(ProviderContainer container) {
  final pushes = <String>[];
  void walk(List<RouteMatchBase> matches) {
    for (final match in matches) {
      switch (match) {
        case ShellRouteMatch():
          walk(match.matches);
        case ImperativeRouteMatch():
          pushes.add(match.matches.uri.toString());
        case _:
      }
    }
  }

  walk(_router(container).routerDelegate.currentConfiguration.matches);
  return pushes;
}

Future<void> _browserBack(WidgetTester tester, FakeBrowser browser) async {
  browser.goBack();
  await tester.pumpAndSettle();
}

Future<void> _browserForward(WidgetTester tester, FakeBrowser browser) async {
  browser.goForward();
  await tester.pumpAndSettle();
}

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

/// Deletes the item on screen through its [overflow] menu.
Future<void> _deleteFrom(WidgetTester tester, String overflow) async {
  await tester.tap(find.bySemanticsIdentifier(overflow));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.itemMenuDelete));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.itemDeleteConfirm));
  await tester.pumpAndSettle();
}

/// Deletes the playlist on screen through its overflow menu.
Future<void> _deletePlaylist(WidgetTester tester) async {
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistOverflow));
  await tester.pumpAndSettle();
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

/// The shell's bar saying [text], and its action pressed.
Future<void> _takeOffer(WidgetTester tester, String text) async {
  expect(find.text(text), findsOneWidget, reason: 'offered');
  await tester.tap(
    find.descendant(
      of: find.byType(WaxMessageBar),
      matching: find.text(AppLocalizationsEn().commonOpen),
    ),
  );
  await tester.pumpAndSettle();
}

/// A move of the app's, made on the screen [tester] shows.
typedef _Move = void Function(WidgetTester tester, GoRouter router);

UserAccount _account(String id, String username) => UserAccount(
  id: id,
  username: username,
  roles: const ['user'],
  createdAt: DateTime.utc(2026, 7, 1),
  libraryAccess: const LibraryAccess(mode: 'all'),
);

/// Files [row] in the fake inbox and reads it, as the notifications screen
/// does on arrival.
Future<void> _fileInInbox(
  WidgetTester tester,
  ProviderContainer container,
  ServerNotification row,
) async {
  (container.read(repositoryProvider) as FakeRepository).inbox =
      <ServerNotification>[row];
  container.invalidate(notificationsProvider);
  await tester.pumpAndSettle();
}

ServerNotification _notice(String event, {String? id, String? target}) =>
    ServerNotification(
      id: id ?? 'nf-$event',
      event: event,
      title: 'Server title',
      body: 'Server body',
      targetPid: target,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

void main() {
  testWidgets('the arrow is the browser back, and forward returns to the '
      'visit it left', (tester) async {
    final (container, browser) = await _pumpTab(tester);
    await _go(tester, container, WaxRoute.notifications);
    await _fileInInbox(
      tester,
      container,
      _notice('job-finished', id: 'nf-job'),
    );
    await tester.tap(
      find.bySemanticsIdentifier(
        SemanticsIds.notificationRow('job-finished', 'nf-job'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TasksScreen), findsOneWidget);
    final entries = browser.entries.length;

    await _back(tester);
    expect(browser.backs, 1);
    expect(browser.entries, hasLength(entries), reason: 'no entry minted');
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(_location(container), WaxRoute.notifications);

    await _browserForward(tester, browser);
    expect(find.byType(TasksScreen), findsOneWidget);
    expect(_location(container), WaxRoute.tasks);

    await _back(tester);
    expect(browser.backs, 2);
    expect(find.byType(NotificationsScreen), findsOneWidget);

    await _back(tester);
    expect(browser.backs, 3);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(browser.entries, hasLength(entries));
  });

  testWidgets('a second press before the first has landed asks for no '
      'second step', (tester) async {
    // At the tab's first entry of the app, a second step would leave it.
    final (container, browser) = await _pumpTab(tester);
    await _go(tester, container, WaxRoute.tasks);
    final tasks = tester.element(find.byType(TasksScreen));

    tasks.back();
    tasks.back();
    expect(browser.backs, 1);
    await tester.pumpAndSettle();

    expect(browser.backs, 1);
    expect(browser.index, 0);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(_location(container), WaxRoute.home);
  });

  testWidgets('a second press after the first has landed on the first '
      'entry of the app goes up, not out', (tester) async {
    // The second press is on the page the first landed on, with nothing
    // of the app behind its entry.
    final album = WaxRoute.musicBucket(MusicDimension.albums, _albumPid);
    final (container, browser) = await _pumpTab(tester, at: album);
    await _go(tester, container, WaxRoute.tasks);

    await _back(tester);
    expect(browser.backs, 1);
    expect(find.byType(AlbumScreen), findsOneWidget);
    expect(browser.index, 0);

    await _back(tester);

    expect(browser.backs, 1, reason: 'the router way');
    expect(browser.left, isFalse);
    expect(find.byType(AlbumScreen), findsNothing);
    expect(_location(container), WaxRoute.musicIndex(MusicDimension.albums));
  });

  testWidgets('a second press that finds no entry of the app behind goes '
      'up, not out', (tester) async {
    // The first lands on an episode pushed over its hub; the second would
    // step the browser off it, where nothing of the app lies behind.
    final (container, browser) = await _pumpTab(tester);
    await _go(tester, container, WaxRoute.podcasts);
    unawaited(_router(container).push<void>(WaxRoute.episode(_episodePid)));
    await tester.pumpAndSettle();
    await _go(tester, container, WaxRoute.radio);

    await _back(tester, hub: true);
    expect(browser.backs, 1);
    expect(find.byType(EpisodeScreen), findsOneWidget);
    browser.stepsBack = false;

    await _back(tester);

    expect(browser.backs, 1, reason: 'the router way');
    expect(browser.left, isFalse);
    expect(find.byType(EpisodeScreen), findsNothing);
    expect(find.byType(PodcastsScreen), findsOneWidget);
  });

  testWidgets('a pop asked with no entry of the app behind is the router '
      'pop, with its result', (tester) async {
    final (container, browser) = await _pumpTab(tester);
    await _go(tester, container, WaxRoute.podcasts);
    final router = _router(container);
    final heard = <Object?>[];
    unawaited(
      router.push<String>(WaxRoute.episode(_episodePid)).then(heard.add),
    );
    await tester.pumpAndSettle();
    browser.stepsBack = false;

    var landed = false;
    unawaited(router.leave(result: 'played').then((_) => landed = true));
    await tester.pumpAndSettle();

    expect(browser.backs, 0);
    expect(browser.left, isFalse);
    expect(landed, isTrue);
    expect(heard, <Object?>['played']);
    expect(find.byType(EpisodeScreen), findsNothing);
    expect(find.byType(PodcastsScreen), findsOneWidget);
  });

  for (final native in <bool>[false, true]) {
    testWidgets('the arrow on a location the app has no screen for returns '
        'to the visit before it ${native ? 'natively' : 'in a browser tab'}', (
      tester,
    ) async {
      // The router reports nothing for it, so the browser has no entry
      // of it to step back from.
      final (container, browser) = await _pumpTab(tester, native: native);
      await _go(tester, container, WaxRoute.notifications);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, '/no-such-place');
      expect(
        _router(container).routerDelegate.currentConfiguration.isError,
        isTrue,
      );

      await _back(tester);

      expect(browser.backs, 0);
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(_location(container), WaxRoute.tasks);
    });
  }

  testWidgets('a visit forgotten behind a step under way leaves it landing '
      'where it was going', (tester) async {
    final (container, browser) = await _pumpTab(tester);
    await _go(tester, container, WaxRoute.tasks);
    await _go(tester, container, WaxRoute.notifications);

    tester.element(find.byType(NotificationsScreen)).back();
    container.read(waxHistoryProvider)!.forget(WaxRoute.home);
    await tester.pumpAndSettle();

    expect(browser.backs, 1);
    expect(find.byType(TasksScreen), findsOneWidget);
    expect(_location(container), WaxRoute.tasks);
  });

  group('the browser back with something open over the page', () {
    /// Notifications, then Tasks with [open] up over it.
    Future<(ProviderContainer, FakeBrowser)> openOverTasks(
      WidgetTester tester,
      void Function(BuildContext context) open,
    ) async {
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.notifications);
      await _go(tester, container, WaxRoute.tasks);
      open(tester.element(find.byType(TasksScreen)));
      await tester.pumpAndSettle();
      expect(find.text('Sure?'), findsOneWidget);
      return (container, browser);
    }

    final openers = <String, void Function(BuildContext)>{
      'a dialog': (context) => unawaited(
        showDialog<void>(
          context: context,
          builder: (context) => const AlertDialog(content: Text('Sure?')),
        ),
      ),
      'a sheet': (context) => unawaited(
        showWaxSheet<void>(
          context: context,
          builder: (context) =>
              const SizedBox(height: 120, child: Center(child: Text('Sure?'))),
        ),
      ),
    };

    for (final MapEntry(key: name, value: open) in openers.entries) {
      testWidgets('closes $name and leaves the page and the entries where '
          'they were', (tester) async {
        final (container, browser) = await openOverTasks(tester, open);
        final entries = [for (final entry in browser.entries) entry.location];
        final index = browser.index;

        await _browserBack(tester, browser);

        expect(find.text('Sure?'), findsNothing);
        expect(find.byType(TasksScreen), findsOneWidget);
        expect(_location(container), WaxRoute.tasks);
        expect([for (final entry in browser.entries) entry.location], entries);
        expect(browser.index, index);

        await _browserBack(tester, browser);
        expect(find.byType(NotificationsScreen), findsOneWidget);
        expect(_location(container), WaxRoute.notifications);
        await _back(tester);
        expect(find.byType(HomeScreen), findsOneWidget);
      });
    }

    // The step forward again lands after a frame, as a browser's may, and
    // what the handler does as the dialog closes reports in that frame.
    final handlers = <String, void Function(BuildContext, GoRouter)>{
      'a go': (context, router) => router.go(WaxRoute.radio),
      'a push': (context, router) =>
          unawaited(router.push<void>(WaxRoute.episode(_episodePid))),
      'a swap': (context, router) => context.swap(WaxRoute.uploads),
    };
    for (final MapEntry(key: name, value: navigate) in handlers.entries) {
      testWidgets('closes a dialog whose close handler does $name, and the '
          'location, the address and the screen agree', (tester) async {
        final (container, browser) = await _pumpTab(tester);
        await _go(tester, container, WaxRoute.notifications);
        await _go(tester, container, WaxRoute.tasks);
        final tasks = tester.element(find.byType(TasksScreen));
        unawaited(
          showDialog<void>(
            context: tasks,
            builder: (context) => const AlertDialog(content: Text('Sure?')),
          ).then((_) => navigate(tasks, _router(container))),
        );
        await tester.pumpAndSettle();
        browser.framed = true;

        await _browserBack(tester, browser);

        expect(find.text('Sure?'), findsNothing);
        expect(browser.location, _location(container), reason: 'the address');
        expect(browser.pushes, _pushes(container));
        switch (name) {
          case 'a go':
            expect(find.byType(RadioScreen), findsOneWidget);
          case 'a push':
            expect(find.byType(EpisodeScreen), findsOneWidget);
          case _:
            expect(find.byType(UploadsScreen), findsOneWidget);
        }
        await _browserBack(tester, browser);
        expect(
          find.byType(name == 'a swap' ? NotificationsScreen : TasksScreen),
          findsOneWidget,
          reason: 'the entry of the page the dialog was over kept',
        );
        expect(browser.location, _location(container));
      });

      // Closed by the app while the browser is still on its way forward
      // again, one entry behind the one the engine writes to.
      testWidgets('closes a dialog whose close handler does $name while the '
          'step forward again is on its way, and the entry behind stays the '
          "visitor's previous screen", (tester) async {
        final (container, browser) = await _pumpTab(tester);
        await _go(tester, container, WaxRoute.notifications);
        await _go(tester, container, WaxRoute.tasks);
        final tasks = tester.element(find.byType(TasksScreen));
        unawaited(
          showDialog<void>(
            context: tasks,
            builder: (context) => const AlertDialog(content: Text('Sure?')),
          ).then((_) => navigate(tasks, _router(container))),
        );
        await tester.pumpAndSettle();
        browser.latency = const Duration(milliseconds: 100);

        browser.goBack();
        await tester.pump(const Duration(milliseconds: 1));
        Navigator.of(tester.element(find.text('Sure?'))).pop();
        await tester.pump();
        await tester.pumpAndSettle();

        final swapped = name == 'a swap';
        expect(find.text('Sure?'), findsNothing);
        expect(browser.location, _location(container), reason: 'the address');
        expect(browser.pushes, _pushes(container));
        expect(
          browser.entries[browser.index - 1].location,
          swapped ? WaxRoute.notifications : WaxRoute.tasks,
          reason: 'the entry behind',
        );
        final entries = browser.entries.length;
        await _browserBack(tester, browser);
        expect(
          find.byType(swapped ? NotificationsScreen : TasksScreen),
          findsOneWidget,
          reason: 'in one press',
        );
        expect(browser.location, _location(container));
        expect(browser.entries, hasLength(entries), reason: 'no entry minted');
      });
    }

    testWidgets('closes a dialog while the app swaps the page, and the '
        'location, the address and the screen agree', (tester) async {
      // Reported before the step forward again lands.
      final (container, browser) = await openOverTasks(
        tester,
        openers['a dialog']!,
      );
      browser.latency = const Duration(milliseconds: 100);
      final tasks = tester.element(find.byType(TasksScreen));

      browser.goBack();
      await tester.pump(const Duration(milliseconds: 1));
      tasks.swap(WaxRoute.uploads);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Sure?'), findsNothing);
      expect(find.byType(UploadsScreen), findsOneWidget);
      expect(_location(container), WaxRoute.uploads);
      expect(browser.location, WaxRoute.uploads, reason: 'the address');
      expect(container.read(waxHistoryProvider)!.stepping, isFalse);
      expect(
        browser.entries[browser.index - 1].location,
        WaxRoute.notifications,
        reason: "the visitor's previous screen, behind",
      );
      await _browserBack(tester, browser);
      expect(find.byType(NotificationsScreen), findsOneWidget);
    });

    testWidgets('closes a dialog while the app goes elsewhere, and the entry '
        'of the page it was over stays behind the one gone to', (tester) async {
      // Reported before the step forward again lands.
      final (container, browser) = await openOverTasks(
        tester,
        openers['a dialog']!,
      );
      browser.latency = const Duration(milliseconds: 100);

      browser.goBack();
      await tester.pump(const Duration(milliseconds: 1));
      _router(container).go(WaxRoute.radio);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Sure?'), findsNothing);
      expect(find.byType(RadioScreen), findsOneWidget);
      expect(browser.location, WaxRoute.radio, reason: 'the address');
      expect(container.read(waxHistoryProvider)!.stepping, isFalse);
      await _browserBack(tester, browser);
      expect(find.byType(TasksScreen), findsOneWidget);
      await _browserBack(tester, browser);
      expect(find.byType(NotificationsScreen), findsOneWidget);
    });

    testWidgets('closes a dialog while the app goes elsewhere, and the step '
        "forward again comes too late: the visitor's back stands and the "
        'go past it', (tester) async {
      // Given up before it lands, which leaves nothing to go forward to.
      final (container, browser) = await openOverTasks(
        tester,
        openers['a dialog']!,
      );
      browser.latency = WaxHistory.unansweredStep * 1.5;

      browser.goBack();
      await tester.pump(const Duration(milliseconds: 1));
      _router(container).go(WaxRoute.radio);
      await tester.pump();
      await tester.pump(WaxHistory.unansweredStep);
      await tester.pumpAndSettle();

      expect(find.text('Sure?'), findsNothing);
      expect(find.byType(RadioScreen), findsOneWidget);
      expect(browser.location, _location(container), reason: 'the address');
      expect(container.read(waxHistoryProvider)!.stepping, isFalse);
      await tester.pump(WaxHistory.unansweredStep);
      expect(
        find.byType(RadioScreen),
        findsOneWidget,
        reason: 'it went nowhere',
      );
      await _browserBack(tester, browser);
      expect(find.byType(NotificationsScreen), findsOneWidget);
    });

    testWidgets('jumped two entries by the back menu, goes forward again as '
        'far in one step', (tester) async {
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.notifications);
      await _go(tester, container, WaxRoute.uploads);
      await _go(tester, container, WaxRoute.tasks);
      openers['a dialog']!(tester.element(find.byType(TasksScreen)));
      await tester.pumpAndSettle();
      final entries = [for (final entry in browser.entries) entry.location];
      final index = browser.index;

      browser.jump(-2);
      await tester.pumpAndSettle();

      expect(browser.forwards, 1, reason: 'the two entries in one step');
      expect(container.read(waxHistoryProvider)!.stepping, isFalse);
      expect(find.text('Sure?'), findsNothing);
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(_location(container), WaxRoute.tasks);
      expect([for (final entry in browser.entries) entry.location], entries);
      expect(browser.index, index);
    });

    testWidgets('is not what a browser forward closes', (tester) async {
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.notifications);
      await _go(tester, container, WaxRoute.tasks);
      await _browserBack(tester, browser);
      openers['a dialog']!(tester.element(find.byType(NotificationsScreen)));
      await tester.pumpAndSettle();

      await _browserForward(tester, browser);

      expect(_location(container), WaxRoute.tasks);
      expect(browser.forwards, 0);
    });
  });

  group('what the app writes while a step it asked of the browser is on '
      'its way', () {
    // Until the step lands the browser is away from the entry the engine
    // writes to. What the app's own move writes meanwhile goes there once
    // the browser is back on it: the move stands, and the entry behind the
    // page it shows is the visitor's previous screen, one browser back
    // away. The browser answers each step 100 ms after it is asked.
    const latency = Duration(milliseconds: 100);

    /// Makes [move] while a step is on its way, then checks that [shows]
    /// is up, the address shows the router's location, the entry behind is
    /// [behind] with [behindPushes], and one browser back shows [back]
    /// (null: leaves the app).
    Future<void> moveDuring(
      WidgetTester tester,
      ProviderContainer container,
      FakeBrowser browser, {
      required VoidCallback move,
      required Type shows,
      required String behind,
      List<String> behindPushes = const <String>[],
      required Type? back,
    }) async {
      final history = container.read(waxHistoryProvider)!;
      expect(history.stepping, isTrue, reason: 'the step is on its way');
      move();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(history.stepping, isFalse);
      expect(find.byType(shows), findsOneWidget);
      expect(browser.location, _location(container), reason: 'the address');
      expect(browser.pushes, _pushes(container));
      expect(
        Uri.parse(browser.entries[browser.index - 1].location).path,
        behind,
        reason: 'the entry behind',
      );
      expect(browser.pushesAt(browser.index - 1), behindPushes);
      final entries = browser.entries.length;
      // The visitor's back, and whatever it passes, at once.
      browser.latency = null;
      await _browserBack(tester, browser);
      if (back == null) {
        expect(browser.left, isTrue, reason: 'out of the app in one press');
        await tester.pump(WaxHistory.unansweredStep);
        return;
      }
      expect(find.byType(back), findsOneWidget, reason: 'in one press');
      expect(browser.location, _location(container));
      expect(browser.entries, hasLength(entries), reason: 'no entry minted');
    }

    /// The app's own moves, signed in, and the screen each shows: a go and
    /// a swap to Uploads, and an episode pushed.
    final moves =
        <String, (void Function(WidgetTester, ProviderContainer), Type)>{
          'a go': (
            (tester, container) => _router(container).go(WaxRoute.uploads),
            UploadsScreen,
          ),
          'a push': (
            (tester, container) => unawaited(
              _router(container).push<void>(WaxRoute.episode(_episodePid)),
            ),
            EpisodeScreen,
          ),
          'a swap': (
            (tester, container) => tester
                .element(find.byType(WaxScaffold).last)
                .swap(WaxRoute.uploads),
            UploadsScreen,
          ),
        };

    for (final MapEntry(key: name, value: (move, shows)) in moves.entries) {
      final swap = name == 'a swap';

      testWidgets('$name while the arrow steps back stands, over the screen '
          'it was made on', (tester) async {
        final (container, browser) = await _pumpTab(tester);
        await _go(tester, container, WaxRoute.notifications);
        await _go(tester, container, WaxRoute.tasks);
        browser.latency = latency;
        tester.element(find.byType(TasksScreen)).back();
        await tester.pump(const Duration(milliseconds: 1));

        await moveDuring(
          tester,
          container,
          browser,
          move: () => move(tester, container),
          shows: shows,
          behind: swap ? WaxRoute.notifications : WaxRoute.tasks,
          back: swap ? NotificationsScreen : TasksScreen,
        );
      });

      /// Home, Tasks, Notifications forgotten, then Radio.
      Future<(ProviderContainer, FakeBrowser)> pastForgotten(
        WidgetTester tester,
      ) async {
        final (container, browser) = await _pumpTab(tester);
        await _go(tester, container, WaxRoute.tasks);
        await _go(tester, container, WaxRoute.notifications);
        await _go(tester, container, WaxRoute.radio);
        container.read(waxHistoryProvider)!.forget(WaxRoute.notifications);
        browser.latency = latency;
        return (container, browser);
      }

      testWidgets('$name while browser back passes a forgotten entry stands, '
          'over the screen it was made on', (tester) async {
        final (container, browser) = await pastForgotten(tester);
        browser.goBack();
        await tester.pump(const Duration(milliseconds: 1));

        await moveDuring(
          tester,
          container,
          browser,
          move: () => move(tester, container),
          shows: shows,
          behind: swap ? WaxRoute.notifications : WaxRoute.radio,
          back: swap ? TasksScreen : RadioScreen,
        );
      });

      testWidgets('$name while the arrow steps past a forgotten entry '
          'stands, over the screen it was made on', (tester) async {
        final (container, browser) = await pastForgotten(tester);
        tester.element(find.byType(WaxScaffold).last).back();
        await tester.pump(latency + const Duration(milliseconds: 50));
        expect(browser.backs, 2, reason: 'on its way past the forgotten one');

        await moveDuring(
          tester,
          container,
          browser,
          move: () => move(tester, container),
          shows: shows,
          behind: swap ? WaxRoute.notifications : WaxRoute.radio,
          back: swap ? TasksScreen : RadioScreen,
        );
      });

      testWidgets('$name while browser back passes a copy of the screen '
          'stands, over the screen it was made on', (tester) async {
        // Tasks twice is two entries of one visit; the swap leaves the
        // older one behind.
        final (container, browser) = await _pumpTab(tester);
        await _go(tester, container, WaxRoute.notifications);
        await _go(tester, container, WaxRoute.tasks);
        await _go(tester, container, WaxRoute.tasks);
        browser.latency = latency;
        browser.goBack();
        await tester.pump(const Duration(milliseconds: 1));

        await moveDuring(
          tester,
          container,
          browser,
          move: () => move(tester, container),
          shows: shows,
          behind: WaxRoute.tasks,
          back: TasksScreen,
        );
      });
    }

    testWidgets('a go while the arrow steps past an entry the router '
        'built stands over that entry, and the visits name it too', (
      tester,
    ) async {
      // A bare replace rewrites Notifications' visit while go_router
      // reports it as an entry past Notifications' own: an entry the list
      // does not hold and does not pass, which the router builds when the
      // arrow lands on it, then steps past. The go made then is over that
      // entry, so the list holds it behind the go as well.
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.notifications);
      unawaited(_router(container).replace<void>(WaxRoute.radio));
      await tester.pumpAndSettle();
      expect(
        browser.entries[browser.index - 1].location,
        WaxRoute.notifications,
      );
      final history = container.read(waxHistoryProvider)!;
      browser.latency = latency;
      tester.element(find.byType(RadioScreen)).back();
      await tester.pump(latency + const Duration(milliseconds: 50));
      expect(browser.backs, 2, reason: 'on its way past the one built');

      _router(container).go(WaxRoute.uploads);
      await tester.pump();
      await tester.pumpAndSettle();
      browser.latency = null;

      expect(history.stepping, isFalse);
      expect(find.byType(UploadsScreen), findsOneWidget);
      expect(browser.location, WaxRoute.uploads);
      expect(
        browser.entries[browser.index - 1].location,
        WaxRoute.notifications,
        reason: 'the entry behind',
      );
      await _browserBack(tester, browser);
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(
        history.isBehind(WaxRoute.tasks),
        isTrue,
        reason: 'the list did not start over there',
      );
      await _back(tester);
      expect(find.byType(TasksScreen), findsOneWidget);
    });

    /// Home, Tasks, Notifications forgotten, Uploads, then Radio, with the
    /// entries' locations.
    Future<(ProviderContainer, FakeBrowser, List<String>)> fiveEntries(
      WidgetTester tester,
    ) async {
      final (container, browser) = await _pumpTab(tester);
      for (final location in <String>[
        WaxRoute.tasks,
        WaxRoute.notifications,
        WaxRoute.uploads,
        WaxRoute.radio,
      ]) {
        await _go(tester, container, location);
      }
      container.read(waxHistoryProvider)!.forget(WaxRoute.notifications);
      return (
        container,
        browser,
        [for (final entry in browser.entries) entry.location],
      );
    }

    /// Lets each step asked of the browser land: a pass, then a return.
    Future<void> landEach(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.pump(latency + const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    testWidgets('a go while browser back, jumped two entries onto a forgotten '
        'one, passes it stands over the screen it was made on', (tester) async {
      // The back menu lands two entries behind in one move and the pass
      // steps one more: the return goes the three entries crossed.
      final (container, browser, entries) = await fiveEntries(tester);
      final history = container.read(waxHistoryProvider)!;
      browser.latency = latency;
      browser.jump(-2);
      await tester.pump(const Duration(milliseconds: 1));
      expect(history.stepping, isTrue, reason: 'passing the forgotten one');

      _router(container).go(WaxRoute.playlists);
      await tester.pump();
      await landEach(tester);
      browser.latency = null;

      expect(history.stepping, isFalse);
      expect(find.byType(PlaylistsScreen), findsOneWidget);
      expect(_location(container), WaxRoute.playlists);
      expect(browser.location, WaxRoute.playlists, reason: 'the address');
      expect(
        [for (final entry in browser.entries) entry.location],
        <String>[...entries, WaxRoute.playlists],
        reason: 'past the entry of the screen it was made on',
      );
      await _browserBack(tester, browser);
      expect(find.byType(RadioScreen), findsOneWidget, reason: 'in one press');
      expect(browser.entries, hasLength(entries.length + 1));
    });

    testWidgets('a go while browser forward, jumped two entries onto a '
        'forgotten one, passes it stands over the screen it was made on', (
      tester,
    ) async {
      final (container, browser, _) = await fiveEntries(tester);
      final history = container.read(waxHistoryProvider)!;
      // Back to Home, past the forgotten entry.
      for (var i = 0; i < 3; i++) {
        await _browserBack(tester, browser);
      }
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(browser.index, 0);
      browser.latency = latency;
      browser.jump(2);
      await tester.pump(const Duration(milliseconds: 1));
      expect(history.stepping, isTrue, reason: 'passing the forgotten one');

      _router(container).go(WaxRoute.playlists);
      await tester.pump();
      await landEach(tester);
      browser.latency = null;

      expect(history.stepping, isFalse);
      expect(find.byType(PlaylistsScreen), findsOneWidget);
      expect(_location(container), WaxRoute.playlists);
      expect(
        [for (final entry in browser.entries) entry.location],
        <String>[WaxRoute.home, WaxRoute.playlists],
        reason: 'past the entry of the screen it was made on',
      );
      await _browserBack(tester, browser);
      expect(find.byType(HomeScreen), findsOneWidget, reason: 'in one press');
    });

    // A pop the app's own move overtakes ends as it does natively, where
    // the pop lands first: the page it closed is gone, from under the move
    // or from its branch, its opener hears the pop's result, no entry shows
    // that page, and the move stands over the page beneath. An episode
    // pushed over Podcasts.
    final overPop =
        <String, (void Function(WidgetTester, ProviderContainer), Type)>{
          'a push': (
            (tester, container) => unawaited(
              _router(container).push<void>(WaxRoute.show(_showPid)),
            ),
            ShowScreen,
          ),
          'a go to another branch': (
            (tester, container) => _router(container).go(WaxRoute.uploads),
            UploadsScreen,
          ),
          'a go within the branch': (
            (tester, container) =>
                _router(container).go(WaxRoute.show(_showPid)),
            ShowScreen,
          ),
          'a swap': (
            (tester, container) => tester
                .element(find.byType(WaxScaffold).last)
                .swap(WaxRoute.uploads),
            UploadsScreen,
          ),
        };
    for (final MapEntry(key: name, value: (move, shows)) in overPop.entries) {
      // Natively the pop lands at once, so a swap asked after it would put
      // something in the place of the page beneath instead.
      // The pop may land before a frame has drawn the move, and reported
      // it: [null] is that, in a browser.
      for (final made in <bool?>[false, if (name != 'a swap') true, null]) {
        final native = made ?? false;
        final drawn = made != null;
        final how = switch (made) {
          true => 'natively',
          false => 'through the browser',
          null => 'through the browser, before a frame draws the move',
        };
        testWidgets('$name while a pop takes a push off stands over the page '
            'beneath, and the pop is made $how', (tester) async {
          final (container, browser) = await _pumpTab(tester, native: native);
          final episode = WaxRoute.episode(_episodePid);
          await _go(tester, container, WaxRoute.podcasts);
          final router = _router(container);
          final heard = <Object?>[];
          unawaited(router.push<String>(episode).then(heard.add));
          await tester.pumpAndSettle();
          browser.latency = latency;
          var left = false;
          unawaited(router.leave(result: 'played').then((_) => left = true));
          await tester.pump(const Duration(milliseconds: 1));
          final history = container.read(waxHistoryProvider)!;
          if (!native) {
            expect(history.stepping, isTrue, reason: 'the pop is on its way');
          }

          move(tester, container);
          await tester.pump(drawn ? null : latency);
          await tester.pumpAndSettle();

          expect(history.stepping, isFalse);
          expect(find.byType(shows), findsOneWidget);
          expect(left, isTrue, reason: 'the pop is done with');
          expect(heard, <Object?>['played'], reason: 'its opener answered');
          expect(
            find.byType(EpisodeScreen, skipOffstage: false),
            name == 'a go to another branch' ? findsAny : findsNothing,
            reason: 'gone from under the move',
          );
          expect(_pushes(container), isNot(contains(episode)));
          if (!native) {
            expect(browser.location, _location(container));
            expect(browser.pushes, _pushes(container));
            for (var i = 0; i < browser.entries.length; i++) {
              expect(
                browser.pushesAt(i),
                isNot(contains(episode)),
                reason: 'no entry shows the page closed',
              );
            }
            expect(
              Uri.parse(browser.entries[browser.index - 1].location).path,
              WaxRoute.podcasts,
              reason: 'the entry behind',
            );
          }
          browser.latency = null;
          if (name == 'a go to another branch') {
            // Its branch does not bring it back either.
            await _tapNav(tester, WaxNavTarget.podcasts);
            expect(find.byType(EpisodeScreen), findsNothing);
            expect(find.byType(PodcastsScreen), findsOneWidget);
            return;
          }
          final entries = browser.entries.length;
          if (native) {
            await _back(tester);
          } else {
            await _browserBack(tester, browser);
            expect(browser.entries, hasLength(entries), reason: 'none minted');
          }
          expect(find.byType(PodcastsScreen), findsOneWidget, reason: 'in one');
          expect(find.byType(EpisodeScreen), findsNothing);
        });
      }
    }

    // The pop lands, and before the frame after it the app moves again (a
    // server answer's follow, say): that move is one more, an entry of its
    // own past the one the first stands on, and nothing waits on it.
    for (final drawn in <bool>[false, true]) {
      final how = drawn ? 'drawn' : 'not yet drawn';
      testWidgets('a go in the frame a pop lands that a push, $how, overtook '
          'is an entry of its own past the push', (tester) async {
        final (container, browser) = await _pumpTab(tester);
        final episode = WaxRoute.episode(_episodePid);
        final show = WaxRoute.show(_showPid);
        await _go(tester, container, WaxRoute.podcasts);
        final router = _router(container);
        final heard = <Object?>[];
        unawaited(router.push<String>(episode).then(heard.add));
        await tester.pumpAndSettle();
        browser.latency = latency;
        unawaited(router.leave(result: 'played'));
        await tester.pump(const Duration(milliseconds: 1));
        unawaited(router.push<void>(show));
        if (drawn) await tester.pump();
        // Once the pop has landed, before the frame that follows.
        Timer(
          latency - const Duration(microseconds: 500),
          () => router.go(WaxRoute.radio),
        );
        await tester.pump(latency);
        await tester.pumpAndSettle();
        browser.latency = null;

        final history = container.read(waxHistoryProvider)!;
        expect(history.stepping, isFalse);
        expect(find.byType(RadioScreen), findsOneWidget);
        expect(heard, <Object?>['played'], reason: "the pop's opener");
        expect(
          [for (final entry in browser.entries) entry.location],
          <String>[
            WaxRoute.home,
            WaxRoute.podcasts,
            WaxRoute.podcasts,
            WaxRoute.radio,
          ],
          reason: 'the push keeps its entry, behind the go',
        );
        expect(browser.pushesAt(1), isEmpty);
        expect(browser.pushesAt(2), <String>[show]);
        expect(browser.index, 3);

        await _browserBack(tester, browser);
        expect(browser.forwards, 0, reason: 'not sent forward again');
        expect(find.byType(ShowScreen), findsOneWidget, reason: 'in one');
        expect(_pushes(container), <String>[show]);
        await _browserBack(tester, browser);
        expect(find.byType(PodcastsScreen), findsOneWidget);
        expect(find.byType(EpisodeScreen), findsNothing);
        expect(browser.entries, hasLength(4), reason: 'none minted');
      });
    }

    testWidgets('a go in the frame a pop lands that a go to another branch '
        'overtook is an entry of its own past that one', (tester) async {
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.podcasts);
      final router = _router(container);
      unawaited(router.push<String>(WaxRoute.episode(_episodePid)));
      await tester.pumpAndSettle();
      browser.latency = latency;
      unawaited(router.leave(result: 'played'));
      await tester.pump(const Duration(milliseconds: 1));
      router.go(WaxRoute.uploads);
      await tester.pump();
      Timer(
        latency - const Duration(microseconds: 500),
        () => router.go(WaxRoute.radio),
      );
      await tester.pump(latency);
      await tester.pumpAndSettle();
      browser.latency = null;

      expect(container.read(waxHistoryProvider)!.stepping, isFalse);
      expect(find.byType(RadioScreen), findsOneWidget);
      expect(
        [for (final entry in browser.entries) entry.location],
        <String>[
          WaxRoute.home,
          WaxRoute.podcasts,
          WaxRoute.uploads,
          WaxRoute.radio,
        ],
      );
      expect(browser.pushesAt(1), isEmpty, reason: 'the page closed is gone');

      await _browserBack(tester, browser);
      expect(browser.forwards, 0, reason: 'not sent forward again');
      expect(find.byType(UploadsScreen), findsOneWidget, reason: 'in one');
    });

    // Two moves overtake the pop, the second with no frame of its own
    // before it lands: each is written as its own frame would have.
    for (final swap in <bool>[false, true]) {
      testWidgets('a go, then ${swap ? 'a swap' : 'a go'} no frame has '
          'drawn, while a pop takes a push off are '
          '${swap ? 'one entry' : 'two entries'} past the page beneath', (
        tester,
      ) async {
        final (container, browser) = await _pumpTab(tester);
        await _go(tester, container, WaxRoute.podcasts);
        final router = _router(container);
        unawaited(router.push<String>(WaxRoute.episode(_episodePid)));
        await tester.pumpAndSettle();
        browser.latency = latency;
        unawaited(router.leave(result: 'played'));
        await tester.pump(const Duration(milliseconds: 1));
        router.go(WaxRoute.uploads);
        await tester.pump();
        if (swap) {
          tester.element(find.byType(UploadsScreen)).swap(WaxRoute.radio);
        } else {
          router.go(WaxRoute.radio);
        }
        await tester.pump(latency);
        await tester.pumpAndSettle();
        browser.latency = null;

        expect(container.read(waxHistoryProvider)!.stepping, isFalse);
        expect(find.byType(RadioScreen), findsOneWidget);
        expect(
          [for (final entry in browser.entries) entry.location],
          <String>[
            WaxRoute.home,
            WaxRoute.podcasts,
            if (!swap) WaxRoute.uploads,
            WaxRoute.radio,
          ],
        );
        expect(browser.pushesAt(1), isEmpty, reason: 'the page closed is gone');
        await _browserBack(tester, browser);
        expect(
          find.byType(swap ? PodcastsScreen : UploadsScreen),
          findsOneWidget,
          reason: 'in one press',
        );
      });
    }

    testWidgets('a page taken out in the frame a push went over it leaves '
        'the push an entry of its own', (tester) async {
      // Written in place, the take-out is told apart from the push no
      // frame has reported yet: that one is an entry past the page's.
      final (container, browser) = await _pumpTab(tester);
      final episode = WaxRoute.episode(_episodePid);
      final show = WaxRoute.show(_showPid);
      await _go(tester, container, WaxRoute.podcasts);
      final router = _router(container);
      final heard = <Object?>[];
      unawaited(router.push<String>(episode).then(heard.add));
      await tester.pumpAndSettle();

      unawaited(router.push<void>(show));
      container
          .read(waxHistoryProvider)!
          .takeOutFromUnder((location, _) => location == episode);
      await tester.pumpAndSettle();

      expect(find.byType(ShowScreen), findsOneWidget);
      expect(find.byType(EpisodeScreen, skipOffstage: false), findsNothing);
      expect(heard, <Object?>[null], reason: 'its opener answered');
      expect(_pushes(container), <String>[show]);
      expect(browser.index, 3);
      expect(browser.pushesAt(1), isEmpty);
      expect(browser.pushesAt(2), <String>[episode], reason: 'its own entry');
      expect(browser.pushesAt(3), <String>[show]);
    });

    // Signed out, the moves are the sign-up screen's.
    final signedOut = <String, void Function(GoRouter router, BuildContext)>{
      'a go': (router, _) => router.go(WaxRoute.signup),
      'a push': (router, _) => unawaited(router.push<void>(WaxRoute.signup)),
      'a swap': (_, context) => context.swap(WaxRoute.signup),
    };
    for (final MapEntry(key: name, value: move) in signedOut.entries) {
      testWidgets('$name while browser back passes the entries a session '
          'left stands, over the sign-in screen', (tester) async {
        // A swap takes the sign-in entry's place, so the one behind is
        // the session's, and back leaves the app past them all.
        final (container, browser) = await _pumpTab(tester);
        await _go(tester, container, WaxRoute.tasks);
        await _go(tester, container, WaxRoute.notifications);
        await _go(tester, container, WaxRoute.radio);
        await container.read(authControllerProvider.notifier).logout();
        await tester.pumpAndSettle();
        expect(find.byType(LoginScreen), findsOneWidget);
        browser.latency = latency;
        browser.goBack();
        await tester.pump(const Duration(milliseconds: 1));

        final swap = name == 'a swap';
        await moveDuring(
          tester,
          container,
          browser,
          move: () => move(
            _router(container),
            tester.element(find.byType(LoginScreen)),
          ),
          shows: SignupScreen,
          behind: swap ? WaxRoute.radio : WaxRoute.login,
          back: swap ? null : LoginScreen,
        );
      });
    }
  });

  testWidgets('a search refined in place is one entry, which browser back '
      'leaves', (tester) async {
    final (container, browser) = await _pumpTab(tester);
    await _go(tester, container, WaxRoute.tasks);
    await _go(tester, container, WaxRoute.searchFor('j'));
    for (final query in <String>['ja', 'jazz']) {
      tester.element(find.byType(SearchScreen)).swap(WaxRoute.searchFor(query));
      await tester.pumpAndSettle();
    }
    expect(browser.location, WaxRoute.searchFor('jazz'));
    expect(
      browser.entries.where(
        (entry) => entry.location.startsWith(WaxRoute.search),
      ),
      hasLength(1),
    );

    await _browserBack(tester, browser);
    expect(find.byType(TasksScreen), findsOneWidget);
    expect(_location(container), WaxRoute.tasks);
  });

  testWidgets('the review pane moved on by a decision is one entry', (
    tester,
  ) async {
    final (container, browser) = await _pumpTab(
      tester,
      size: const Size(1400, 1000),
    );
    _repo(container).reviewEntries = [
      testReviewEntry('rv-1'),
      testReviewEntry('rv-2'),
    ];
    await _go(tester, container, WaxRoute.review);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.reviewRow('rv-1')),
    );
    await tester.pumpAndSettle();
    expect(browser.location, WaxRoute.reviewEntry('rv-1'));
    final entries = browser.entries.length;

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs));
    await tester.pumpAndSettle();
    expect(browser.location, WaxRoute.reviewEntry('rv-2'));
    expect(browser.entries, hasLength(entries), reason: 'no entry minted');

    await _back(tester);
    expect(browser.backs, 1);
    expect(_location(container), WaxRoute.review);
  });

  group('a review entry decided on a page of its own', () {
    /// One pane, the queue holding two entries, gone to from [from].
    Future<(ProviderContainer, FakeBrowser)> queueFrom(
      WidgetTester tester,
      String from,
    ) async {
      final (container, browser) = await _pumpTab(
        tester,
        size: const Size(700, 1200),
      );
      _repo(container).reviewEntries = [
        testReviewEntry('rv-1'),
        testReviewEntry('rv-2'),
      ];
      await _go(tester, container, from);
      return (container, browser);
    }

    Future<void> decide(WidgetTester tester) async {
      expect(find.byType(ReviewEntryScreen), findsOneWidget);
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs));
      await tester.pumpAndSettle();
    }

    Future<(ProviderContainer, FakeBrowser)> decidedFromQueue(
      WidgetTester tester,
    ) async {
      final (container, browser) = await queueFrom(tester, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.review);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.reviewRow('rv-1')),
      );
      await tester.pumpAndSettle();
      await decide(tester);
      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(_location(container), WaxRoute.review);
      return (container, browser);
    }

    testWidgets('opened from the queue returns to it, and browser back goes '
        'to what came before the queue', (tester) async {
      final (container, browser) = await decidedFromQueue(tester);
      expect(
        browser.entries.where((entry) => entry.location == WaxRoute.review),
        hasLength(1),
        reason: 'the queue once',
      );

      await _browserBack(tester, browser);

      expect(find.byType(TasksScreen), findsOneWidget);
      expect(find.byType(ReviewEntryScreen), findsNothing);
      expect(_location(container), WaxRoute.tasks);
    });

    testWidgets('opened from the queue returns to it, and the arrow goes to '
        'what came before the queue', (tester) async {
      final (container, browser) = await decidedFromQueue(tester);
      final backs = browser.backs;

      await _back(tester);

      expect(browser.backs, backs + 1, reason: 'one step');
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(_location(container), WaxRoute.tasks);
    });

    testWidgets('opened from a notification row returns to the queue, and '
        'browser back goes to the notifications', (tester) async {
      final (container, browser) = await queueFrom(
        tester,
        WaxRoute.notifications,
      );
      await _fileInInbox(
        tester,
        container,
        _notice('import-completed', id: 'nf-import', target: 'rv-1'),
      );
      await tester.tap(
        find.bySemanticsIdentifier(
          SemanticsIds.notificationRow('import-completed', 'nf-import'),
        ),
      );
      await tester.pumpAndSettle();
      await decide(tester);
      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(_location(container), WaxRoute.review);

      await _browserBack(tester, browser);

      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(_location(container), WaxRoute.notifications);
    });
  });

  testWidgets('the review pane closed onto the queue by the last decision '
      'leaves browser back going to what came before the queue', (
    tester,
  ) async {
    final (container, browser) = await _pumpTab(
      tester,
      size: const Size(1400, 1000),
    );
    _repo(container).reviewEntries = [testReviewEntry('rv-1')];
    await _go(tester, container, WaxRoute.tasks);
    await _go(tester, container, WaxRoute.review);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.reviewRow('rv-1')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs));
    await tester.pumpAndSettle();
    expect(_location(container), WaxRoute.review);
    expect(find.bySemanticsIdentifier(SemanticsIds.reviewPane), findsNothing);

    await _browserBack(tester, browser);
    expect(find.byType(TasksScreen), findsOneWidget);
    expect(_location(container), WaxRoute.tasks);
  });

  testWidgets('a tab tap is a visit of its own, not a browser back', (
    tester,
  ) async {
    // A tab tap restores the branch, as a browser move does; only the
    // browser saying so tells them apart.
    final (container, browser) = await _pumpTab(tester);
    final album = WaxRoute.musicBucket(MusicDimension.albums, _albumPid);
    await _go(tester, container, album);
    await _tapNav(tester, WaxNavTarget.podcasts);
    await _tapNav(tester, WaxNavTarget.music);
    expect(find.byType(AlbumScreen), findsOneWidget);
    expect(
      container.read(waxHistoryProvider)!.atTabTap,
      isTrue,
      reason: 'the tap is the visit on screen',
    );

    await _back(tester);
    expect(browser.backs, 1);
    expect(find.byType(PodcastsScreen), findsOneWidget);
    expect(_location(container), WaxRoute.podcasts);
  });

  testWidgets('a browser back off a push answers whoever awaits it', (
    tester,
  ) async {
    final (container, browser) = await _pumpTab(tester, signedIn: false);
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

    await _browserBack(tester, browser);

    expect(answered, isTrue);
    expect(answer, isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('a back asked while a pop lands does not step past it', (
    tester,
  ) async {
    // Nowhere recorded on an auth screen, so the arrow would be a browser
    // pop of its own, which must not take the pending one's place.
    final (container, browser) = await _pumpTab(tester, signedIn: false);
    final heard = <Object?>[];
    final router = _router(container);
    unawaited(router.push<String>(WaxRoute.signup).then(heard.add));
    await tester.pumpAndSettle();
    var landed = false;
    unawaited(router.leave(result: 'merry').then((_) => landed = true));
    tester.element(find.byType(SignupScreen)).back(fallback: WaxRoute.login);
    await tester.pumpAndSettle();

    expect(landed, isTrue);
    expect(heard, <Object?>['merry']);
    expect(browser.backs, 1);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  group('a step asked while another lands', () {
    /// Home, then Podcasts with an episode pushed over it, and what its
    /// opener heard so far.
    Future<(ProviderContainer, FakeBrowser, List<Object?>)> overTheHub(
      WidgetTester tester,
    ) async {
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.podcasts);
      final heard = <Object?>[];
      unawaited(
        _router(
          container,
        ).push<String>(WaxRoute.episode(_episodePid)).then(heard.add),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EpisodeScreen), findsOneWidget);
      return (container, browser, heard);
    }

    testWidgets('a leave while the arrow steps off its page is that step, '
        'and its result reaches the opener', (tester) async {
      final (container, browser, heard) = await overTheHub(tester);
      final entries = browser.entries.length;

      tester.element(find.byType(EpisodeScreen)).back();
      var left = false;
      unawaited(
        _router(container).leave(result: 'played').then((_) => left = true),
      );
      await tester.pumpAndSettle();

      expect(browser.backs, 1);
      expect(find.byType(EpisodeScreen), findsNothing);
      expect(find.byType(PodcastsScreen), findsOneWidget);
      expect(heard, <Object?>['played']);
      expect(left, isTrue);
      expect(browser.entries, hasLength(entries), reason: 'no entry minted');
    });

    testWidgets('an arrow while a pop takes its page off is that pop, and '
        'the pop keeps its result', (tester) async {
      final (container, browser, heard) = await overTheHub(tester);
      var left = false;
      unawaited(
        _router(container).leave(result: 'played').then((_) => left = true),
      );
      tester.element(find.byType(EpisodeScreen)).back();
      await tester.pumpAndSettle();

      expect(browser.backs, 1);
      expect(find.byType(PodcastsScreen), findsOneWidget);
      expect(heard, <Object?>['played']);
      expect(left, isTrue);
    });

    testWidgets('a leave while a browser back passes an entry takes its turn '
        'after it', (tester) async {
      // Asked of the page the visitor's own back is leaving: that back
      // has left it.
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.notifications);
      await _go(tester, container, WaxRoute.radio);
      container.read(waxHistoryProvider)!.forget(WaxRoute.notifications);
      final entries = [for (final entry in browser.entries) entry.location];
      final built = _arrivals(container);
      browser.latency = const Duration(milliseconds: 100);

      browser.goBack();
      await tester.pump(const Duration(milliseconds: 1));
      expect(container.read(waxHistoryProvider)!.stepping, isTrue);
      var left = false;
      unawaited(_router(container).leave().then((_) => left = true));
      await tester.pumpAndSettle();

      expect(find.byType(TasksScreen), findsOneWidget);
      expect(_location(container), WaxRoute.tasks);
      expect(built, <String>[WaxRoute.tasks], reason: 'nothing else built');
      expect(browser.backs, 1);
      expect(left, isTrue);
      expect([for (final entry in browser.entries) entry.location], entries);
    });

    testWidgets('an arrow while a browser back passes an entry takes its turn '
        'after it', (tester) async {
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.notifications);
      await _go(tester, container, WaxRoute.radio);
      container.read(waxHistoryProvider)!.forget(WaxRoute.notifications);
      browser.latency = const Duration(milliseconds: 100);

      browser.goBack();
      await tester.pump(const Duration(milliseconds: 1));
      expect(container.read(waxHistoryProvider)!.stepping, isTrue);
      tester.element(find.byType(WaxScaffold).last).back();
      await tester.pumpAndSettle();

      expect(find.byType(TasksScreen), findsOneWidget);
      expect(_location(container), WaxRoute.tasks);
      expect(browser.backs, 1);
    });

    /// Tasks, one album, then another, which go_router keys as the same
    /// page: its route's pattern.
    Future<(ProviderContainer, FakeBrowser)> twoAlbums(
      WidgetTester tester,
    ) async {
      final (container, browser) = await _pumpTab(tester);
      _repo(container).albums[_otherAlbumPid] = const AlbumDetail(
        pid: _otherAlbumPid,
        title: 'Rumours of the Lighthouse',
      );
      await _go(tester, container, WaxRoute.tasks);
      await _go(
        tester,
        container,
        WaxRoute.musicBucket(MusicDimension.albums, _albumPid),
      );
      await _go(
        tester,
        container,
        WaxRoute.musicBucket(MusicDimension.albums, _otherAlbumPid),
      );
      return (container, browser);
    }

    testWidgets('an arrow while the arrow steps from one album to another is '
        'that step', (tester) async {
      final (container, browser) = await twoAlbums(tester);

      final album = tester.element(find.byType(AlbumScreen));
      album.back();
      album.back();
      await tester.pumpAndSettle();

      expect(browser.backs, 1);
      expect(find.byType(AlbumScreen), findsOneWidget);
      expect(
        _location(container),
        WaxRoute.musicBucket(MusicDimension.albums, _albumPid),
      );
    });

    testWidgets('a leave on one album while the arrow steps to another is '
        'that step, and is not made again from there', (tester) async {
      final (container, browser) = await twoAlbums(tester);

      tester.element(find.byType(AlbumScreen)).back();
      var left = false;
      unawaited(
        _router(container).leave(result: 'played').then((_) => left = true),
      );
      await tester.pumpAndSettle();

      expect(browser.backs, 1);
      expect(left, isTrue);
      expect(find.byType(AlbumScreen), findsOneWidget);
      expect(
        _location(container),
        WaxRoute.musicBucket(MusicDimension.albums, _albumPid),
      );
    });
  });

  group('a step asked before a frame has drawn the move before it', () {
    // Until that frame the navigators hold the pages the move left, and
    // the browser is on the entry it left: the step takes its turn after
    // it, and ends as one asked a frame later does.
    List<String> locations(FakeBrowser browser) => [
      for (final entry in browser.entries) entry.location,
    ];
    final episode = WaxRoute.episode(_episodePid);
    final show = WaxRoute.show(_showPid);

    for (final native in <bool>[false, true]) {
      final where = native ? 'natively' : 'in a browser tab';

      testWidgets('the arrow in the frame of a go returns to the screen the '
          'go was made on $where', (tester) async {
        final (container, browser) = await _pumpTab(tester, native: native);
        await _go(tester, container, WaxRoute.tasks);
        await _go(tester, container, WaxRoute.notifications);
        final built = _arrivals(container);

        _router(container).go(WaxRoute.uploads);
        tester.element(find.byType(NotificationsScreen)).back();
        await tester.pumpAndSettle();

        expect(find.byType(NotificationsScreen), findsOneWidget);
        expect(_location(container), WaxRoute.notifications);
        expect(built, <String>[
          WaxRoute.uploads,
          WaxRoute.notifications,
        ], reason: 'nothing else built');
        if (!native) {
          expect(browser.backs, 1);
          expect(locations(browser), <String>[
            WaxRoute.home,
            WaxRoute.tasks,
            WaxRoute.notifications,
            WaxRoute.uploads,
          ], reason: 'no entry written over');
          expect(browser.index, 2);
          await _browserForward(tester, browser);
          expect(find.byType(UploadsScreen), findsOneWidget);
          await _browserBack(tester, browser);
        }
        await _back(tester);
        expect(find.byType(TasksScreen), findsOneWidget);
      });

      testWidgets('the arrow in the frame of a push takes the push off, and '
          'its opener hears $where', (tester) async {
        final (container, browser) = await _pumpTab(tester, native: native);
        await _go(tester, container, WaxRoute.tasks);
        await _go(tester, container, WaxRoute.podcasts);
        final built = _arrivals(container);
        final heard = <Object?>[];

        unawaited(_router(container).push<String>(episode).then(heard.add));
        tester.element(find.byType(PodcastsScreen)).back();
        await tester.pumpAndSettle();

        expect(find.byType(PodcastsScreen), findsOneWidget);
        expect(find.byType(EpisodeScreen), findsNothing);
        expect(heard, <Object?>[null]);
        expect(built, <String>[WaxRoute.podcasts, WaxRoute.podcasts]);
        if (!native) {
          expect(browser.backs, 1);
          expect(locations(browser), <String>[
            WaxRoute.home,
            WaxRoute.tasks,
            WaxRoute.podcasts,
            WaxRoute.podcasts,
          ], reason: 'no entry written over');
          expect(browser.pushesAt(2), isEmpty);
          expect(browser.pushesAt(3), <String>[episode]);
          expect(browser.index, 2);
        }
        await _back(tester, hub: true);
        expect(find.byType(TasksScreen), findsOneWidget);
      });

      testWidgets('a leave in the frame of a push pops the push with its '
          'result $where', (tester) async {
        final (container, browser) = await _pumpTab(tester, native: native);
        await _go(tester, container, WaxRoute.tasks);
        await _go(tester, container, WaxRoute.podcasts);
        final router = _router(container);
        final heard = <Object?>[];

        unawaited(router.push<String>(episode).then(heard.add));
        var left = false;
        unawaited(router.leave(result: 'played').then((_) => left = true));
        await tester.pumpAndSettle();

        expect(find.byType(PodcastsScreen), findsOneWidget);
        expect(_location(container), WaxRoute.podcasts);
        expect(_pushes(container), isEmpty);
        expect(heard, <Object?>['played']);
        expect(left, isTrue);
        if (!native) {
          expect(browser.backs, 1);
          expect(locations(browser), <String>[
            WaxRoute.home,
            WaxRoute.tasks,
            WaxRoute.podcasts,
            WaxRoute.podcasts,
          ]);
          expect(browser.pushesAt(3), <String>[episode]);
          expect(browser.index, 2);
        }
      });

      testWidgets('a leave in the frame of a push over a page that can pop '
          'takes the push, not that page $where', (tester) async {
        final (container, browser) = await _pumpTab(tester, native: native);
        await _go(tester, container, WaxRoute.podcasts);
        final router = _router(container);
        final under = <Object?>[];
        final over = <Object?>[];
        unawaited(router.push<String>(episode).then(under.add));
        await tester.pumpAndSettle();

        unawaited(router.push<String>(show).then(over.add));
        var left = false;
        unawaited(router.leave(result: 'played').then((_) => left = true));
        await tester.pumpAndSettle();

        expect(find.byType(EpisodeScreen), findsOneWidget);
        expect(find.byType(ShowScreen), findsNothing);
        expect(_pushes(container), <String>[episode]);
        expect(over, <Object?>['played']);
        expect(under, isEmpty, reason: 'the page under it was not popped');
        expect(left, isTrue);
        if (!native) {
          expect(browser.backs, 1);
          expect(browser.index, 2);
          expect(browser.pushesAt(2), <String>[episode]);
          expect(browser.pushesAt(3), <String>[episode, show]);
        }
      });

      testWidgets('a leave in the frame of a go to a page with one under it '
          'pops to that one $where', (tester) async {
        final album = WaxRoute.musicBucket(MusicDimension.albums, _albumPid);
        final albums = WaxRoute.musicIndex(MusicDimension.albums);
        final (container, browser) = await _pumpTab(tester, native: native);
        await _go(tester, container, WaxRoute.tasks);
        final router = _router(container);

        router.go(album);
        var left = false;
        unawaited(router.leave().then((_) => left = true));
        await tester.pumpAndSettle();

        expect(find.byType(AlbumScreen), findsNothing);
        expect(_location(container), albums);
        expect(left, isTrue);
        if (!native) {
          expect(locations(browser), <String>[
            WaxRoute.home,
            WaxRoute.tasks,
            album,
            albums,
          ], reason: 'as a frame later');
        }
      });

      testWidgets('two goes in one frame leave the first a visit of its own, '
          'and the arrow steps back through it $where', (tester) async {
        final (container, browser) = await _pumpTab(tester, native: native);
        await _go(tester, container, WaxRoute.tasks);
        final router = _router(container);

        router
          ..go(WaxRoute.uploads)
          ..go(WaxRoute.playlists);
        await tester.pumpAndSettle();

        expect(find.byType(PlaylistsScreen), findsOneWidget);
        if (!native) {
          expect(locations(browser), <String>[
            WaxRoute.home,
            WaxRoute.tasks,
            WaxRoute.uploads,
            WaxRoute.playlists,
          ], reason: 'each move its entry');
          expect(browser.index, 3);
        }
        final backs = browser.backs;
        await _back(tester, hub: true);
        expect(find.byType(UploadsScreen), findsOneWidget);
        await _back(tester, hub: true);
        expect(find.byType(TasksScreen), findsOneWidget);
        if (!native) {
          expect(browser.backs, backs + 2, reason: 'through the browser');
          expect(locations(browser), <String>[
            WaxRoute.home,
            WaxRoute.tasks,
            WaxRoute.uploads,
            WaxRoute.playlists,
          ], reason: 'no entry minted');
        }
      });
    }

    // The visitor's own back, which the browser made from the entry the
    // move was made on: it stands, the move goes unwritten, and the list
    // is where that entry's visit is.
    for (final push in <bool>[false, true]) {
      for (final pass in <bool>[false, true]) {
        testWidgets("the browser's back in the frame of "
            '${push ? 'a push' : 'a go'} '
            '${pass ? 'passes a forgotten entry' : 'lands'} as from the '
            'screen the move was made on, and the list keeps its place', (
          tester,
        ) async {
          final (container, browser) = await _pumpTab(tester);
          await _go(tester, container, WaxRoute.tasks);
          await _go(tester, container, WaxRoute.notifications);
          await _go(tester, container, WaxRoute.podcasts);
          final history = container.read(waxHistoryProvider)!;
          if (pass) history.forget(WaxRoute.notifications);
          final entries = locations(browser);
          final router = _router(container);
          final heard = <Object?>[];

          if (push) {
            unawaited(router.push<String>(episode).then(heard.add));
          } else {
            router.go(WaxRoute.uploads);
          }
          browser.goBack();
          await tester.pump(Duration.zero);
          await tester.pumpAndSettle();

          expect(history.stepping, isFalse);
          expect(
            find.byType(pass ? TasksScreen : NotificationsScreen),
            findsOneWidget,
          );
          expect(browser.location, _location(container));
          expect(locations(browser), entries, reason: 'the move is unwritten');
          for (var i = 0; i < browser.entries.length; i++) {
            expect(browser.pushesAt(i), isEmpty);
          }
          expect(heard, push ? <Object?>[null] : isEmpty);
          expect(history.canGoBack, isTrue, reason: 'the list kept its place');
          final backs = browser.backs;
          await _back(tester);
          expect(browser.backs, backs + 1, reason: 'through the browser');
          expect(find.byType(pass ? HomeScreen : TasksScreen), findsOneWidget);
          expect(locations(browser), entries, reason: 'no entry minted');
        });
      }
    }

    testWidgets("the browser's back in the frame of a go, onto the app's "
        'oldest entry, forgotten: what stands in is written over it, the go '
        'goes unwritten and the entry ahead stays', (tester) async {
      final (container, browser) = await _pumpTab(
        tester,
        at: WaxRoute.notifications,
      );
      await _go(tester, container, WaxRoute.tasks);
      final history = container.read(waxHistoryProvider)!
        ..forget(WaxRoute.notifications);
      final built = _arrivals(container);

      _router(container).go(WaxRoute.uploads);
      browser.goBack();
      await tester.pump(Duration.zero);
      await tester.pumpAndSettle();

      expect(history.stepping, isFalse);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(browser.index, 0);
      expect(locations(browser), <String>[
        WaxRoute.home,
        WaxRoute.tasks,
      ], reason: 'the go is unwritten');
      expect(built, isNot(contains(WaxRoute.notifications)));
      expect(history.canGoBack, isFalse, reason: 'the oldest');

      await _browserForward(tester, browser);
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(browser.index, 1);
      expect(history.isBehind(WaxRoute.home), isTrue);
      expect(locations(browser), <String>[WaxRoute.home, WaxRoute.tasks]);
    });

    // A go made with visits ahead takes their place in the list, as any
    // new visit does. Where the browser's own move comes before the engine
    // is told of it, the browser still holds their entries, so the list
    // holds them again.
    testWidgets("the browser's back in the frame of a go made with visits "
        'ahead leaves them in the list: forward lands on each, and the '
        'arrow walks them back', (tester) async {
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.notifications);
      await _go(tester, container, WaxRoute.podcasts);
      await _browserBack(tester, browser);
      await _browserBack(tester, browser);
      final history = container.read(waxHistoryProvider)!;
      final entries = locations(browser);
      expect(browser.index, 1);

      _router(container).go(WaxRoute.uploads);
      browser.goBack();
      await tester.pump(Duration.zero);
      await tester.pumpAndSettle();

      expect(history.stepping, isFalse);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(browser.index, 0);
      expect(locations(browser), entries, reason: 'the go is unwritten');
      for (final (i, screen) in <Type>[
        TasksScreen,
        NotificationsScreen,
        PodcastsScreen,
      ].indexed) {
        await _browserForward(tester, browser);
        expect(find.byType(screen), findsOneWidget);
        expect(browser.index, i + 1);
        expect(locations(browser), entries);
        expect(history.canGoBack, isTrue, reason: 'the list kept its place');
      }
      final backs = browser.backs;
      for (final (i, screen) in <Type>[
        NotificationsScreen,
        TasksScreen,
        HomeScreen,
      ].indexed) {
        await _back(tester, hub: true);
        expect(find.byType(screen), findsOneWidget);
        expect(browser.index, 2 - i);
      }
      expect(browser.backs, backs + 3, reason: 'through the browser');
      expect(locations(browser), entries, reason: 'no entry minted');
      expect(history.canGoBack, isFalse, reason: 'the oldest');
    });

    testWidgets("the browser's back in the frame of a go made with a visit "
        'ahead passes a forgotten entry and leaves that visit in the list', (
      tester,
    ) async {
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.notifications);
      await _go(tester, container, WaxRoute.podcasts);
      await _go(tester, container, WaxRoute.radio);
      await _browserBack(tester, browser);
      final history = container.read(waxHistoryProvider)!
        ..forget(WaxRoute.notifications);
      final entries = locations(browser);
      final built = _arrivals(container);
      expect(browser.index, 3);

      _router(container).go(WaxRoute.uploads);
      browser.goBack();
      await tester.pump(Duration.zero);
      await tester.pumpAndSettle();

      expect(history.stepping, isFalse);
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(browser.index, 1);
      expect(locations(browser), entries, reason: 'the go is unwritten');
      expect(history.canGoBack, isTrue);
      // Forward passes the forgotten entry too, and lands on each ahead.
      for (final (screen, index) in <(Type, int)>[
        (PodcastsScreen, 3),
        (RadioScreen, 4),
      ]) {
        await _browserForward(tester, browser);
        expect(find.byType(screen), findsOneWidget);
        expect(browser.index, index);
        expect(locations(browser), entries);
        expect(history.canGoBack, isTrue, reason: 'the list kept its place');
      }
      for (final (screen, index) in <(Type, int)>[
        (PodcastsScreen, 3),
        (TasksScreen, 1),
        (HomeScreen, 0),
      ]) {
        await _back(tester, hub: true);
        expect(find.byType(screen), findsOneWidget);
        expect(browser.index, index);
      }
      expect(locations(browser), entries, reason: 'no entry minted');
      expect(built, isNot(contains(WaxRoute.notifications)));
    });

    testWidgets("the browser's back in the frame of a go made with a visit "
        "ahead, onto the app's oldest entry, forgotten: what stands in is "
        'written over it, and forward lands on each entry ahead', (
      tester,
    ) async {
      final (container, browser) = await _pumpTab(
        tester,
        at: WaxRoute.notifications,
      );
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.podcasts);
      await _browserBack(tester, browser);
      final history = container.read(waxHistoryProvider)!
        ..forget(WaxRoute.notifications);
      final built = _arrivals(container);
      final entries = <String>[
        WaxRoute.home,
        WaxRoute.tasks,
        WaxRoute.podcasts,
      ];
      expect(browser.index, 1);

      _router(container).go(WaxRoute.uploads);
      browser.goBack();
      await tester.pump(Duration.zero);
      await tester.pumpAndSettle();

      expect(history.stepping, isFalse);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(browser.index, 0);
      expect(
        locations(browser),
        entries,
        reason: 'the go is unwritten, and no entry ahead is lost',
      );
      expect(history.canGoBack, isFalse, reason: 'the oldest');
      expect(built, isNot(contains(WaxRoute.notifications)));

      await _browserForward(tester, browser);
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(browser.index, 1);
      expect(history.isBehind(WaxRoute.home), isTrue);
      await _browserForward(tester, browser);
      expect(find.byType(PodcastsScreen), findsOneWidget);
      expect(browser.index, 2);
      expect(history.isBehind(WaxRoute.tasks), isTrue);
      expect(locations(browser), entries, reason: 'no entry minted');
    });

    // The visitor's forward has nothing to show: the browser is sent back
    // to the entry the go was made on, and the go stands.
    for (final passing in <bool>[false, true]) {
      testWidgets("the browser's forward in the frame of a go, "
          '${passing ? 'past a forgotten entry ' : ''}onto the newest entry, '
          'forgotten${passing ? ' too' : ''}: the browser comes back, the go '
          'is written past the entry it was made on, and its visit stays in '
          'the list', (tester) async {
        final (container, browser) = await _pumpTab(tester);
        await _go(tester, container, WaxRoute.tasks);
        await _go(tester, container, WaxRoute.notifications);
        if (passing) await _go(tester, container, WaxRoute.podcasts);
        await _browserBack(tester, browser);
        if (passing) await _browserBack(tester, browser);
        final history = container.read(waxHistoryProvider)!
          ..forget(WaxRoute.notifications)
          ..forget(WaxRoute.podcasts);
        final built = _arrivals(container);
        final entries = <String>[
          WaxRoute.home,
          WaxRoute.tasks,
          WaxRoute.uploads,
        ];
        expect(browser.index, 1);

        _router(container).go(WaxRoute.uploads);
        browser.goForward();
        await tester.pump(Duration.zero);
        await tester.pumpAndSettle();

        expect(history.stepping, isFalse);
        expect(find.byType(UploadsScreen), findsOneWidget);
        expect(browser.location, WaxRoute.uploads, reason: 'the address');
        expect(browser.index, 2);
        expect(locations(browser), entries, reason: 'the go stands');
        expect(history.isBehind(WaxRoute.tasks), isTrue);

        // Its entry is written, so a later browser move leaves its visit be.
        await _browserBack(tester, browser);
        expect(find.byType(TasksScreen), findsOneWidget);
        expect(browser.index, 1);
        await _browserForward(tester, browser);
        expect(find.byType(UploadsScreen), findsOneWidget);
        expect(browser.index, 2);
        expect(
          history.isBehind(WaxRoute.tasks),
          isTrue,
          reason: "the go's visit is still the list's",
        );
        final backs = browser.backs;
        await _back(tester);
        expect(browser.backs, backs + 1, reason: 'through the browser');
        expect(find.byType(TasksScreen), findsOneWidget);
        expect(locations(browser), entries, reason: 'no entry minted');
        expect(built, isNot(contains(WaxRoute.notifications)));
        expect(built, isNot(contains(WaxRoute.podcasts)));
      });
    }

    // A move that adds no visit is told again the same way: a swap over
    // the entry it was made on, an up go past it. With a frame drawn while
    // the browser is away, the router's own report of it is held with the
    // rest, and goes with it.
    final artistsIndex = WaxRoute.musicIndex(MusicDimension.artists);
    for (final (what, from, to, move) in <(String, String, String, _Move)>[
      (
        'a swap',
        WaxRoute.tasks,
        WaxRoute.uploads,
        (tester, router) =>
            tester.element(find.byType(TasksScreen)).swap(WaxRoute.uploads),
      ),
      (
        'an up go',
        artistsIndex,
        WaxRoute.music,
        (tester, router) => router.go(WaxRoute.music),
      ),
    ]) {
      final swap = what == 'a swap';
      for (final (passing, framed) in <(bool, bool)>[
        (false, false),
        (false, true),
        (true, false),
        (true, true),
      ]) {
        testWidgets("the browser's forward in the frame of $what, "
            '${passing ? 'past a forgotten entry ' : ''}onto the newest '
            'entry, forgotten${passing ? ' too' : ''}'
            "${framed ? ', each step a frame apart' : ''}: the browser comes "
            "back, and the move is written ${swap ? 'over' : 'past'} the "
            'entry it was made on', (tester) async {
          const latency = Duration(milliseconds: 100);
          final (container, browser) = await _pumpTab(tester);
          await _go(tester, container, from);
          await _go(tester, container, WaxRoute.notifications);
          if (passing) await _go(tester, container, WaxRoute.podcasts);
          await _browserBack(tester, browser);
          if (passing) await _browserBack(tester, browser);
          final history = container.read(waxHistoryProvider)!
            ..forget(WaxRoute.notifications)
            ..forget(WaxRoute.podcasts);
          final built = _arrivals(container);
          expect(browser.index, 1);

          if (framed) browser.latency = latency;
          move(tester, _router(container));
          browser.goForward();
          await tester.pump(Duration.zero);
          if (framed) {
            expect(history.stepping, isTrue, reason: 'the browser is away');
            for (var i = 0; i < 3; i++) {
              await tester.pump(latency + const Duration(milliseconds: 10));
            }
          }
          await tester.pumpAndSettle();
          browser.latency = null;

          expect(history.stepping, isFalse);
          expect(_location(container), to);
          expect(browser.location, to, reason: 'the address');
          // A swap drops no entry ahead; a go drops them, as any push.
          expect(browser.index, swap ? 1 : 2);
          expect(locations(browser), <String>[
            WaxRoute.home,
            if (!swap) from,
            to,
            if (swap) WaxRoute.notifications,
            if (swap && passing) WaxRoute.podcasts,
          ]);

          await _browserBack(tester, browser);
          expect(_location(container), swap ? WaxRoute.home : from);
          expect(browser.index, swap ? 0 : 1);
          await _browserForward(tester, browser);
          expect(_location(container), to);
          expect(browser.location, to, reason: 'the address');
          expect(built, isNot(contains(WaxRoute.notifications)));
          expect(built, isNot(contains(WaxRoute.podcasts)));
        });
      }
    }

    // By design, pinned as it is: the step that sends the browser back
    // cannot be called off, so the visitor's own back heard before it lands
    // drops the go being told again, and the step lands from where that
    // back went.
    testWidgets('a back of the visitor while the browser is being sent back '
        'to the entry a go was made on undoes the go: home shows on the way, '
        'and the tab ends on that entry as it was', (tester) async {
      const latency = Duration(milliseconds: 100);
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.notifications);
      await _go(tester, container, WaxRoute.podcasts);
      await _browserBack(tester, browser);
      await _browserBack(tester, browser);
      final history = container.read(waxHistoryProvider)!
        ..forget(WaxRoute.notifications)
        ..forget(WaxRoute.podcasts);
      final entries = locations(browser);
      final built = _arrivals(container);

      _router(container).go(WaxRoute.uploads);
      browser
        ..latency = latency
        ..goForward();
      await tester.pump(Duration.zero);
      // The pass has reached the newest, and the browser is sent back.
      await tester.pump(latency + const Duration(milliseconds: 10));
      expect(browser.index, 3);
      expect(history.stepping, isTrue);
      browser.goBack();
      for (var i = 0; i < 4; i++) {
        await tester.pump(latency);
      }
      await tester.pumpAndSettle();
      browser.latency = null;

      expect(history.stepping, isFalse);
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(browser.index, 1);
      expect(browser.location, WaxRoute.tasks, reason: 'the address');
      expect(locations(browser), entries, reason: 'the go is unwritten');
      expect(built, <String>[
        WaxRoute.uploads,
        WaxRoute.home,
        WaxRoute.tasks,
      ], reason: 'home on the way');
      expect(history.isBehind(WaxRoute.home), isTrue);
    });

    testWidgets("the browser's back in the frame of a push leaves the push "
        'out of what a tap on its tab brings back', (tester) async {
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.podcasts);
      final heard = <Object?>[];

      unawaited(_router(container).push<String>(episode).then(heard.add));
      browser.goBack();
      await tester.pump(Duration.zero);
      await tester.pumpAndSettle();
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(heard, <Object?>[null]);

      await _tapNav(tester, WaxNavTarget.podcasts);
      expect(find.byType(PodcastsScreen), findsOneWidget);
      expect(find.byType(EpisodeScreen, skipOffstage: false), findsNothing);
    });

    testWidgets("the browser's back in the frame of a go to the screen on "
        'screen keeps that screen in the list, and the arrow then steps back '
        'through the browser', (tester) async {
      // A move that changes nothing is neither drawn nor written: the back
      // leaves the visit on screen, whose entry it is.
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.notifications);
      final history = container.read(waxHistoryProvider)!;
      final entries = locations(browser);

      _router(container).go(WaxRoute.notifications);
      browser.goBack();
      await tester.pump(Duration.zero);
      await tester.pumpAndSettle();
      expect(find.byType(TasksScreen), findsOneWidget);

      await _browserForward(tester, browser);
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(history.canGoBack, isTrue, reason: 'the list kept its place');
      expect(history.isBehind(WaxRoute.tasks), isTrue);
      final backs = browser.backs;
      await _back(tester);
      expect(browser.backs, backs + 1, reason: 'through the browser');
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(locations(browser), entries, reason: 'no entry minted');
    });

    testWidgets("a go, then another while the browser's back it came before "
        'passes an entry, are both written, and the arrow steps back through '
        'them', (tester) async {
      const latency = Duration(milliseconds: 100);
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.notifications);
      await _go(tester, container, WaxRoute.podcasts);
      final history = container.read(waxHistoryProvider)!
        ..forget(WaxRoute.notifications);
      final entries = locations(browser);
      final router = _router(container);
      browser.latency = latency;

      router.go(WaxRoute.uploads);
      browser.goBack();
      // Once the back has landed, before a frame has drawn the first.
      var passing = false;
      Timer.run(() {
        passing = history.stepping;
        router.go(WaxRoute.playlists);
      });
      await tester.pump(Duration.zero);
      expect(passing, isTrue, reason: 'passing the forgotten one');
      for (var i = 0; i < 4; i++) {
        await tester.pump(latency + const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      browser.latency = null;

      expect(history.stepping, isFalse);
      expect(find.byType(PlaylistsScreen), findsOneWidget);
      expect(locations(browser), <String>[
        ...entries,
        WaxRoute.uploads,
        WaxRoute.playlists,
      ]);
      final built = _arrivals(container);
      await _back(tester, hub: true);
      expect(find.byType(UploadsScreen), findsOneWidget);
      expect(built, <String>[WaxRoute.uploads], reason: 'nothing else built');
      expect(browser.index, entries.length);
    });

    testWidgets('an arrow asked as the frame that draws a go ends steps back '
        "from the go's entry", (tester) async {
      // The router has told the engine of the go by then, and the engine
      // writes its entry a moment later.
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.notifications);
      final history = container.read(waxHistoryProvider)!;
      final built = _arrivals(container);

      _router(container).go(WaxRoute.uploads);
      tester.binding.addPostFrameCallback((_) => history.back());
      await tester.pumpAndSettle();

      expect(history.stepping, isFalse);
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(built, <String>[
        WaxRoute.uploads,
        WaxRoute.notifications,
      ], reason: 'nothing else built');
      expect(browser.backs, 1);
      expect(locations(browser), <String>[
        WaxRoute.home,
        WaxRoute.tasks,
        WaxRoute.notifications,
        WaxRoute.uploads,
      ], reason: 'no entry written over');
      expect(browser.index, 2);
    });

    testWidgets('an arrow asked on a go that overtook the arrow before it '
        "steps back from the go's entry", (tester) async {
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.notifications);
      final notifications = tester.element(find.byType(NotificationsScreen));
      browser.latency = const Duration(milliseconds: 100);
      notifications.back();
      // The way back to the entry the go is written past lands at once,
      // before a frame has drawn the go.
      browser.latency = null;
      final built = _arrivals(container);

      _router(container).go(WaxRoute.uploads);
      notifications.back();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(container.read(waxHistoryProvider)!.stepping, isFalse);
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(built, <String>[
        WaxRoute.uploads,
        WaxRoute.notifications,
      ], reason: 'nothing else built');
      expect(locations(browser), <String>[
        WaxRoute.home,
        WaxRoute.tasks,
        WaxRoute.notifications,
        WaxRoute.uploads,
      ], reason: 'no entry written over');
      expect(browser.index, 2);
    });
  });

  group('a push somebody awaits', () {
    /// The podcasts hub with an episode pushed over it, and what its
    /// opener heard so far.
    Future<(ProviderContainer, FakeBrowser, List<Object?>)> open(
      WidgetTester tester,
    ) async {
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.podcasts);
      final heard = <Object?>[];
      unawaited(
        _router(
          container,
        ).push<String>(WaxRoute.episode(_episodePid)).then(heard.add),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EpisodeScreen), findsOneWidget);
      return (container, browser, heard);
    }

    testWidgets('is heard through the entry a browser back rebuilt it from', (
      tester,
    ) async {
      final (container, browser, heard) = await open(tester);
      await _go(tester, container, WaxRoute.radio);

      await _browserBack(tester, browser);
      expect(find.byType(EpisodeScreen), findsOneWidget);
      expect(heard, isEmpty);
      _router(container).pop<String>('played');
      await tester.pumpAndSettle();

      expect(heard, <Object?>['played']);
    });

    testWidgets('left offstage by a browser move is not answered for it', (
      tester,
    ) async {
      // Forward to the other domain leaves the episode in its branch, so
      // its opener waits on.
      final (container, browser, heard) = await open(tester);
      await _go(tester, container, WaxRoute.radio);
      await _browserBack(tester, browser);
      await _browserForward(tester, browser);
      expect(find.byType(RadioScreen), findsOneWidget);
      expect(heard, isEmpty);

      await _back(tester, hub: true);
      expect(browser.backs, 1);
      expect(find.byType(EpisodeScreen), findsOneWidget);
      _router(container).pop<String>('played');
      await tester.pumpAndSettle();

      expect(heard, <Object?>['played']);
    });

    testWidgets('taken off the screen by a browser back hears null', (
      tester,
    ) async {
      final (_, browser, heard) = await open(tester);

      await _browserBack(tester, browser);

      expect(find.byType(PodcastsScreen), findsOneWidget);
      expect(heard, <Object?>[null]);
    });
  });

  group('a push left by its own pop', () {
    /// The podcasts hub gone to from Home with an episode pushed over it,
    /// and what its opener heard so far.
    Future<(ProviderContainer, FakeBrowser, List<Object?>)> open(
      WidgetTester tester,
    ) async {
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.podcasts);
      final heard = <Object?>[];
      unawaited(
        _router(
          container,
        ).push<String>(WaxRoute.episode(_episodePid)).then(heard.add),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EpisodeScreen), findsOneWidget);
      return (container, browser, heard);
    }

    testWidgets('through the helper is a browser back, and the arrow then '
        'goes where the visitor was before', (tester) async {
      final (container, browser, heard) = await open(tester);
      final entries = browser.entries.length;

      _router(container).leave(result: 'played');
      await tester.pumpAndSettle();
      expect(find.byType(PodcastsScreen), findsOneWidget);
      expect(browser.backs, 1, reason: 'the pop is the browser back');
      expect(browser.entries, hasLength(entries), reason: 'no entry minted');
      expect(heard, <Object?>['played']);

      await _back(tester, hub: true);
      expect(browser.backs, 2, reason: 'one press');
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(EpisodeScreen), findsNothing);
    });

    testWidgets('by a bare router pop is stepped past by the arrow', (
      tester,
    ) async {
      // The pop is a new entry, so the one behind is the page closed.
      final (container, browser, heard) = await open(tester);
      _router(container).pop<String>('played');
      await tester.pumpAndSettle();
      expect(heard, <Object?>['played']);

      await _back(tester, hub: true);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(EpisodeScreen), findsNothing);
      expect(_location(container), WaxRoute.home);
    });

    testWidgets('is opened again by browser forward and left again by '
        'browser back', (tester) async {
      final (container, browser, _) = await open(tester);
      _router(container).leave();
      await tester.pumpAndSettle();

      await _browserForward(tester, browser);
      expect(find.byType(EpisodeScreen), findsOneWidget);

      await _browserBack(tester, browser);
      expect(find.byType(PodcastsScreen), findsOneWidget);
      expect(find.byType(EpisodeScreen), findsNothing);
    });

    testWidgets('through the helper is done once the browser has landed', (
      tester,
    ) async {
      final (container, _, heard) = await open(tester);
      var landed = false;
      unawaited(
        _router(container).leave(result: 'played').then((_) => landed = true),
      );
      await tester.pump();
      expect(landed, isFalse, reason: 'the browser has not moved yet');
      expect(find.byType(EpisodeScreen), findsOneWidget);

      await tester.pumpAndSettle();
      expect(landed, isTrue);
      expect(find.byType(PodcastsScreen), findsOneWidget);
      expect(heard, <Object?>['played']);
    });

    testWidgets('answers its opener when the entry behind still holds it', (
      tester,
    ) async {
      // A bare router pop of a show pushed over it made an entry of its
      // own, so the first the browser lands on still shows the episode.
      final (container, browser, heard) = await open(tester);
      final router = _router(container);
      unawaited(router.push<String>(WaxRoute.show(_showPid)));
      await tester.pumpAndSettle();
      router.pop<String>('router');
      await tester.pumpAndSettle();
      expect(find.byType(EpisodeScreen), findsOneWidget);

      var landed = false;
      unawaited(router.leave(result: 'played').then((_) => landed = true));
      await tester.pumpAndSettle();

      expect(landed, isTrue);
      expect(heard, <Object?>['played']);
      expect(find.byType(PodcastsScreen), findsOneWidget);
      expect(find.byType(EpisodeScreen), findsNothing);
    });

    testWidgets('twice in one turn over a root takes the fallback the second '
        'time', (tester) async {
      // The first lands on the hub, a branch root nothing pops.
      final (container, browser, heard) = await open(tester);
      final router = _router(container);
      unawaited(router.leave(result: 'played'));
      unawaited(router.leave(fallback: WaxRoute.radio));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(heard, <Object?>['played']);
      expect(browser.backs, 1);
      expect(find.byType(RadioScreen), findsOneWidget);
      expect(_location(container), WaxRoute.radio);
    });

    testWidgets('twice in one turn lands in order, and both callers go on', (
      tester,
    ) async {
      final (container, browser, heard) = await open(tester);
      final router = _router(container);
      final show = <Object?>[];
      unawaited(router.push<String>(WaxRoute.show(_showPid)).then(show.add));
      await tester.pumpAndSettle();
      expect(find.byType(ShowScreen), findsOneWidget);
      final entries = browser.entries.length;

      final order = <String>[];
      unawaited(router.leave(result: 'first').then((_) => order.add('first')));
      unawaited(
        router.leave(result: 'second').then((_) => order.add('second')),
      );
      await tester.pumpAndSettle();

      expect(order, <String>['first', 'second']);
      expect(show, <Object?>['first']);
      expect(heard, <Object?>['second']);
      expect(find.byType(PodcastsScreen), findsOneWidget);
      expect(browser.backs, 2);
      expect(browser.entries, hasLength(entries), reason: 'no entry minted');
    });
  });

  group('a delete on a page a tab tap restored', () {
    // A tab tap restores the branch with its push, and the entry behind
    // that is the other tab's, not the page the push was made over.
    const seriesPid = 'sr-01JZX5N8QW3F4V9T2B7KDSERIE1';
    const artistPid = 'ar-01JZX5N8QW3F4V9T2B7KDARTST1';

    /// [tab] with [pushed] over [root], Radio tapped, then [tab] again,
    /// which brings the push back.
    Future<ProviderContainer> restored(
      WidgetTester tester, {
      required bool native,
      required WaxNavTarget tab,
      required String root,
      required String pushed,
      Object? extra,
    }) async {
      final (container, _) = await _pumpTab(tester, native: native);
      _repo(container)
        ..books[_bookPid] = testBook(_bookPid, partCount: 2)
        ..libraryItems.add(testItem(_bookPid))
        ..facetItems['album ${_albumPid.substring(3)}'] = [
          testItem('tr-1', title: 'One'),
        ];
      await _tapNav(tester, tab);
      if (_location(container) != root) await _go(tester, container, root);
      unawaited(_router(container).push<void>(pushed, extra: extra));
      await tester.pumpAndSettle();
      await _tapNav(tester, WaxNavTarget.radio);
      await _tapNav(tester, tab);
      expect(_router(container).canPop(), isTrue, reason: 'the push is back');
      return container;
    }

    for (final native in <bool>[false, true]) {
      final how = native ? 'natively' : 'in a browser tab';

      testWidgets('closed, then the arrow from the hub goes to the other tab '
          '$how', (tester) async {
        // The entry the tab tap made still holds the episode, a copy of the
        // visit it was first pushed in, which the arrow's step passes.
        final container = await restored(
          tester,
          native: native,
          tab: WaxNavTarget.podcasts,
          root: WaxRoute.podcasts,
          pushed: WaxRoute.episode(_episodePid),
        );
        unawaited(_router(container).leave(fallback: WaxRoute.podcasts));
        await tester.pumpAndSettle();
        expect(find.byType(PodcastsScreen), findsOneWidget);

        await _back(tester, hub: true);

        expect(find.byType(EpisodeScreen), findsNothing);
        expect(find.byType(RadioScreen), findsOneWidget);
        expect(_location(container), WaxRoute.radio);
      });

      testWidgets('an episode pushed over its hub leaves for the hub $how', (
        tester,
      ) async {
        final container = await restored(
          tester,
          native: native,
          tab: WaxNavTarget.podcasts,
          root: WaxRoute.podcasts,
          pushed: WaxRoute.episode(_episodePid),
        );
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

        expect(_location(container), WaxRoute.podcasts);
        expect(find.byType(PodcastsScreen), findsOneWidget);
        expect(find.byType(EpisodeScreen), findsNothing);
        await _tapNav(tester, WaxNavTarget.podcasts);
        expect(find.byType(EpisodeScreen), findsNothing);
      });

      testWidgets('a book opened from its series leaves for the series $how', (
        tester,
      ) async {
        // Pushed, as the series row does.
        final container = await restored(
          tester,
          native: native,
          tab: WaxNavTarget.books,
          root: WaxRoute.bookSeries(seriesPid),
          pushed: WaxRoute.book(_bookPid),
        );
        expect(find.byType(BookScreen), findsOneWidget);

        await _deleteFrom(tester, SemanticsIds.bookOverflow);

        expect(_location(container), WaxRoute.bookSeries(seriesPid));
        expect(find.byType(BookSeriesScreen), findsOneWidget);
        expect(find.byType(BookScreen), findsNothing);
        await _tapNav(tester, WaxNavTarget.books);
        expect(find.byType(BookScreen), findsNothing);
      });

      testWidgets('an album opened from its artist leaves for the artist '
          '$how', (tester) async {
        // Pushed with its title, as the artist's shelf does.
        final artist = WaxRoute.musicBucket(MusicDimension.artists, artistPid);
        final container = await restored(
          tester,
          native: native,
          tab: WaxNavTarget.music,
          root: artist,
          pushed: WaxRoute.musicBucket(MusicDimension.albums, _albumPid),
          extra: 'Gullwing',
        );
        expect(find.byType(AlbumScreen), findsOneWidget);

        await _deleteFrom(tester, SemanticsIds.entityOverflow);

        expect(_location(container), artist);
        expect(find.byType(ArtistScreen), findsOneWidget);
        expect(find.byType(AlbumScreen), findsNothing);
        await _tapNav(tester, WaxNavTarget.music);
        expect(find.byType(AlbumScreen), findsNothing);
      });
    }
  });

  group('a delete from the full player', () {
    /// Opens [pages] in turn, with [playing] playing, and expands the
    /// player over the last of them. The overflow offers the verb to
    /// anything but a podcast, so an episode's pid rides on a music item.
    Future<ProviderContainer> expanded(
      WidgetTester tester, {
      required bool native,
      required List<String> pages,
      required String playing,
      String? pushed,
      String? at,
    }) async {
      final (container, _) = await _pumpTab(tester, native: native, at: at);
      _repo(container)
        ..books[_bookPid] = testBook(_bookPid, partCount: 2)
        ..libraryItems.add(testItem(_bookPid));
      container.read(nowPlayingProvider.notifier).play(
        [testItem(playing, title: 'Salt Harbour')],
        source: const QueueSource(
          kind: QueueSourceKind.single,
          label: 'Salt Harbour',
        ),
      );
      await tester.pumpAndSettle();
      for (final page in pages) {
        await _go(tester, container, page);
      }
      if (pushed != null) {
        unawaited(_router(container).push<void>(pushed));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.deckExpand));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsOneWidget);
      return container;
    }

    Future<void> deleteFromPlayer(WidgetTester tester) async {
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerMore));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.itemDelete));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.itemDeleteConfirm),
      );
      await tester.pumpAndSettle();
    }

    Future<void> release(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      container.read(queueControllerProvider.notifier).clear();
      await tester.pump(const Duration(seconds: 1));
    }

    for (final native in <bool>[false, true]) {
      final how = native ? 'natively' : 'in a browser tab';

      testWidgets('over the book it deletes leaves the screen under the '
          'book $how', (tester) async {
        final container = await expanded(
          tester,
          native: native,
          pages: [WaxRoute.tasks, WaxRoute.book(_bookPid)],
          playing: _bookPid,
        );

        await deleteFromPlayer(tester);

        expect(find.byType(PlayerScreen), findsNothing);
        expect(find.byType(BookScreen), findsNothing);
        expect(find.byType(TasksScreen), findsOneWidget);
        expect(_location(container), WaxRoute.tasks);
        await release(tester, container);
      });

      testWidgets('over the book it deletes, opened cold, leaves for the '
          'books hub $how', (tester) async {
        // Nothing else is recorded, so the visits forgotten leave the
        // browser's pop to land on the book; only the step after that
        // landing leaves it.
        final container = await expanded(
          tester,
          native: native,
          at: WaxRoute.book(_bookPid),
          pages: const <String>[],
          playing: _bookPid,
        );

        await deleteFromPlayer(tester);

        expect(find.byType(PlayerScreen), findsNothing);
        expect(find.byType(BookScreen), findsNothing);
        expect(find.byType(BooksScreen), findsOneWidget);
        expect(_location(container), WaxRoute.books);
        await release(tester, container);
      });

      testWidgets('over a book pushed over its series leaves the series $how', (
        tester,
      ) async {
        final series = WaxRoute.bookSeries('sr-01JZX5N8QW3F4V9T2B7KDSERIE1');
        final container = await expanded(
          tester,
          native: native,
          pages: [WaxRoute.tasks, series],
          pushed: WaxRoute.book(_bookPid),
          playing: _bookPid,
        );

        await deleteFromPlayer(tester);

        expect(find.byType(PlayerScreen), findsNothing);
        expect(find.byType(BookScreen), findsNothing);
        expect(find.byType(BookSeriesScreen), findsOneWidget);
        expect(_location(container), series);
        await release(tester, container);
      });

      testWidgets('over the episode it deletes leaves the show $how', (
        tester,
      ) async {
        final container = await expanded(
          tester,
          native: native,
          pages: [
            WaxRoute.show(_showPid),
            WaxRoute.showEpisode(_showPid, _episodePid),
          ],
          playing: _episodePid,
        );
        expect(
          find.byType(EpisodeScreen, skipOffstage: false),
          findsOneWidget,
          reason: 'the episode is under the player',
        );

        await deleteFromPlayer(tester);

        expect(find.byType(PlayerScreen), findsNothing);
        expect(find.byType(EpisodeScreen, skipOffstage: false), findsNothing);
        expect(find.byType(ShowScreen), findsOneWidget);
        expect(_location(container), WaxRoute.show(_showPid));
        await release(tester, container);
      });

      testWidgets('over some other page leaves that page, and the back from '
          'it passes the book $how', (tester) async {
        final container = await expanded(
          tester,
          native: native,
          pages: [
            WaxRoute.tasks,
            WaxRoute.book(_bookPid),
            WaxRoute.notifications,
          ],
          playing: _bookPid,
        );

        await deleteFromPlayer(tester);

        expect(find.byType(PlayerScreen), findsNothing);
        expect(find.byType(NotificationsScreen), findsOneWidget);
        expect(_location(container), WaxRoute.notifications);

        await _back(tester);

        expect(find.byType(BookScreen), findsNothing);
        expect(find.byType(TasksScreen), findsOneWidget);
        await release(tester, container);
      });
    }
  });

  group('a delete that lands with something opened over the page', () {
    // Opened while the server was still answering, so the flow meets it
    // only when it leaves.
    Future<void> openSheet(WidgetTester tester, Finder over) async {
      unawaited(
        showWaxSheet<void>(
          context: tester.element(over),
          builder: (context) =>
              const SizedBox(height: 120, child: Center(child: Text('Sure?'))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sure?'), findsOneWidget);
    }

    Future<void> openDialog(WidgetTester tester, Finder over) async {
      unawaited(
        showDialog<void>(
          context: tester.element(over),
          builder: (context) => const AlertDialog(content: Text('Really?')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Really?'), findsOneWidget);
    }

    /// Tasks, then the book, with the server holding the delete.
    Future<(ProviderContainer, Completer<void>)> onTheBook(
      WidgetTester tester, {
      required bool native,
    }) async {
      final (container, _) = await _pumpTab(tester, native: native);
      final gate = Completer<void>();
      _repo(container)
        ..books[_bookPid] = testBook(_bookPid, partCount: 2)
        ..libraryItems.add(testItem(_bookPid))
        ..deleteItemsGate = gate;
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.book(_bookPid));
      expect(find.byType(BookScreen), findsOneWidget);
      return (container, gate);
    }

    for (final native in <bool>[false, true]) {
      final how = native ? 'natively' : 'in a browser tab';

      // With nothing open the book leaves for the page it is declared
      // under, and back from there goes to Tasks.
      Future<void> leftAsWithNothingOpen(
        WidgetTester tester,
        ProviderContainer container,
      ) async {
        expect(find.byType(BookScreen), findsNothing);
        expect(find.byType(BooksScreen), findsOneWidget);
        expect(_location(container), WaxRoute.books);
        await _back(tester, hub: true);
        expect(find.byType(TasksScreen), findsOneWidget);
        expect(find.byType(BookScreen), findsNothing);
      }

      testWidgets('a sheet over the book is closed and the book left $how', (
        tester,
      ) async {
        final (container, gate) = await onTheBook(tester, native: native);
        await _deleteFrom(tester, SemanticsIds.bookOverflow);
        await openSheet(tester, find.byType(BookScreen));

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.text('Sure?'), findsNothing);
        await leftAsWithNothingOpen(tester, container);
      });

      testWidgets('a dialog over a sheet over the book are both closed and '
          'the book left $how', (tester) async {
        final (container, gate) = await onTheBook(tester, native: native);
        await _deleteFrom(tester, SemanticsIds.bookOverflow);
        await openSheet(tester, find.byType(BookScreen));
        await openDialog(tester, find.text('Sure?'));

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.text('Really?'), findsNothing);
        expect(find.text('Sure?'), findsNothing);
        await leftAsWithNothingOpen(tester, container);
      });

      testWidgets('a sheet over the full player over the book leaves the '
          'player and the book $how', (tester) async {
        final (container, gate) = await onTheBook(tester, native: native);
        container.read(nowPlayingProvider.notifier).play(
          [testItem(_bookPid, title: 'Salt Harbour')],
          source: const QueueSource(
            kind: QueueSourceKind.single,
            label: 'Salt Harbour',
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.deckExpand));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerMore));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.itemDelete));
        await tester.pumpAndSettle();
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.itemDeleteConfirm),
        );
        await tester.pumpAndSettle();
        await openSheet(tester, find.byType(PlayerScreen));

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.text('Sure?'), findsNothing);
        expect(find.byType(PlayerScreen), findsNothing);
        expect(find.byType(BookScreen), findsNothing);
        expect(find.byType(TasksScreen), findsOneWidget);
        expect(_location(container), WaxRoute.tasks);
        container.read(queueControllerProvider.notifier).clear();
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets('one book deleted closes nothing over another $how', (
        tester,
      ) async {
        // Both books are one page to go_router, which keys a page by its
        // route's pattern: the screen is the same one, showing the other
        // book, and the other is held in Home so it comes up at once.
        final (container, gate) = await onTheBook(tester, native: native);
        _repo(container)
          ..books[_otherBookPid] = testBook(_otherBookPid, title: 'Roverandom')
          ..libraryItems.add(testItem(_otherBookPid));
        await _tapNav(tester, WaxNavTarget.home);
        unawaited(_router(container).push<void>(WaxRoute.book(_otherBookPid)));
        await tester.pumpAndSettle();
        await _tapNav(tester, WaxNavTarget.radio);
        await _tapNav(tester, WaxNavTarget.books);
        expect(_location(container), WaxRoute.book(_bookPid));
        await _deleteFrom(tester, SemanticsIds.bookOverflow);
        await _go(tester, container, WaxRoute.book(_otherBookPid));
        await openSheet(tester, find.byType(BookScreen));

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.text('Sure?'), findsOneWidget);
        expect(find.byType(BookScreen), findsOneWidget);
        expect(_location(container), WaxRoute.book(_otherBookPid));
      });
    }
  });

  group('a delete that lands once the visitor has moved on', () {
    // The server holds the delete while the visitor goes elsewhere: their
    // screen stays, and the item's page waits in its tab, where a tap on
    // the tab must not bring it back.
    Future<(ProviderContainer, Completer<void>)> held(
      WidgetTester tester, {
      required bool native,
    }) async {
      final (container, _) = await _pumpTab(tester, native: native);
      final gate = Completer<void>();
      _repo(container)
        ..books[_bookPid] = testBook(_bookPid, partCount: 2)
        ..libraryItems.add(testItem(_bookPid))
        ..facetItems['album ${_albumPid.substring(3)}'] = [
          testItem('tr-1', title: 'One'),
        ]
        ..deleteItemsGate = gate;
      return (container, gate);
    }

    for (final native in <bool>[false, true]) {
      final how = native ? 'natively' : 'in a browser tab';

      testWidgets('of an album leaves the tab the visitor is on, and Music '
          'shows the albums index $how', (tester) async {
        final (container, gate) = await held(tester, native: native);
        final album = WaxRoute.musicBucket(MusicDimension.albums, _albumPid);
        await _go(tester, container, album);
        await _deleteFrom(tester, SemanticsIds.entityOverflow);
        await _tapNav(tester, WaxNavTarget.home);

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.byType(HomeScreen), findsOneWidget);
        expect(_location(container), WaxRoute.home);
        await _tapNav(tester, WaxNavTarget.music);
        expect(find.byType(AlbumScreen), findsNothing);
        expect(find.byType(MusicIndexScreen), findsOneWidget);
        expect(
          _location(container),
          WaxRoute.musicIndex(MusicDimension.albums),
        );
        await _back(tester);
        expect(find.byType(AlbumScreen), findsNothing);
      });

      testWidgets('of a book leaves the tab the visitor is on, and Books '
          'shows the hub $how', (tester) async {
        final (container, gate) = await held(tester, native: native);
        await _go(tester, container, WaxRoute.book(_bookPid));
        await _deleteFrom(tester, SemanticsIds.bookOverflow);
        await _tapNav(tester, WaxNavTarget.radio);

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.byType(RadioScreen), findsOneWidget);
        expect(_location(container), WaxRoute.radio);
        await _tapNav(tester, WaxNavTarget.books);
        expect(find.byType(BookScreen), findsNothing);
        expect(find.byType(BooksScreen), findsOneWidget);
        expect(_location(container), WaxRoute.books);
      });

      testWidgets('from the full player collapsed since leaves the tab the '
          'visitor is on, and Books shows the hub $how', (tester) async {
        final (container, gate) = await held(tester, native: native);
        container.read(nowPlayingProvider.notifier).play(
          [testItem(_bookPid, title: 'Salt Harbour')],
          source: const QueueSource(
            kind: QueueSourceKind.single,
            label: 'Salt Harbour',
          ),
        );
        await tester.pumpAndSettle();
        await _go(tester, container, WaxRoute.tasks);
        await _go(tester, container, WaxRoute.book(_bookPid));
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.deckExpand));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerMore));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.itemDelete));
        await tester.pumpAndSettle();
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.itemDeleteConfirm),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerBack));
        await tester.pumpAndSettle();
        expect(find.byType(BookScreen), findsOneWidget);
        await _tapNav(tester, WaxNavTarget.radio);

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.byType(PlayerScreen), findsNothing);
        expect(find.byType(RadioScreen), findsOneWidget);
        expect(_location(container), WaxRoute.radio);
        await _tapNav(tester, WaxNavTarget.books);
        expect(find.byType(BookScreen), findsNothing);
        expect(find.byType(BooksScreen), findsOneWidget);
        container.read(queueControllerProvider.notifier).clear();
        await tester.pump(const Duration(seconds: 1));
      });
    }
  });

  testWidgets('a book deleted once the visitor moved on is not brought back '
      'by a tab tap after a browser jump started the list over', (
    tester,
  ) async {
    // The jump lands on neither neighbour, so the list starts over; the
    // tab still comes back without the book.
    final (container, browser) = await _pumpTab(tester);
    final gate = Completer<void>();
    _repo(container)
      ..books[_bookPid] = testBook(_bookPid, partCount: 2)
      ..libraryItems.add(testItem(_bookPid))
      ..deleteItemsGate = gate;
    await _go(tester, container, WaxRoute.book(_bookPid));
    await _deleteFrom(tester, SemanticsIds.bookOverflow);
    await _tapNav(tester, WaxNavTarget.radio);
    gate.complete();
    await tester.pumpAndSettle();
    await _tapNav(tester, WaxNavTarget.home);
    await _tapNav(tester, WaxNavTarget.music);

    browser.jump(-2);
    await tester.pumpAndSettle();
    expect(find.byType(RadioScreen), findsOneWidget);
    expect(
      container.read(waxHistoryProvider)!.canGoBack,
      isFalse,
      reason: 'the list started over',
    );

    await _tapNav(tester, WaxNavTarget.books);
    expect(find.byType(BookScreen), findsNothing);
    expect(find.byType(BooksScreen), findsOneWidget);
    expect(_location(container), WaxRoute.books);
  });

  group('a delete that lands under the full player playing something else', () {
    for (final native in <bool>[false, true]) {
      final how = native ? 'natively' : 'in a browser tab';

      testWidgets('takes the album out from under it, and collapsing it shows '
          'the albums index $how', (tester) async {
        final (container, _) = await _pumpTab(tester, native: native);
        final gate = Completer<void>();
        _repo(container)
          ..facetItems['album ${_albumPid.substring(3)}'] = [
            testItem('tr-1', title: 'One'),
          ]
          ..deleteItemsGate = gate;
        final albums = WaxRoute.musicIndex(MusicDimension.albums);
        await _go(tester, container, WaxRoute.tasks);
        await _go(tester, container, albums);
        final album = WaxRoute.musicBucket(MusicDimension.albums, _albumPid);
        await _go(tester, container, album);
        await _deleteFrom(tester, SemanticsIds.entityOverflow);
        // Another album's track.
        container.read(nowPlayingProvider.notifier).play(
          [testItem('tr-B', title: 'Salt Harbour')],
          source: const QueueSource(
            kind: QueueSourceKind.single,
            label: 'Salt Harbour',
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.deckExpand));
        await tester.pumpAndSettle();
        expect(find.byType(PlayerScreen), findsOneWidget);

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.byType(PlayerScreen), findsOneWidget, reason: 'it stays');
        expect(_pushes(container), <String>[WaxRoute.nowPlaying]);
        expect(_location(container), albums, reason: 'taken out under it');

        final built = _arrivals(container);
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerBack));
        await tester.pumpAndSettle();

        expect(find.byType(PlayerScreen), findsNothing);
        expect(find.byType(AlbumScreen), findsNothing);
        expect(find.byType(MusicIndexScreen), findsOneWidget);
        expect(_location(container), albums);
        expect(built, isNot(contains(album)), reason: 'never built');
        await _back(tester);
        expect(find.byType(AlbumScreen), findsNothing);
        expect(find.byType(TasksScreen), findsOneWidget);
        container.read(queueControllerProvider.notifier).clear();
        await tester.pump(const Duration(seconds: 1));
      });
    }

    for (final native in <bool>[false, true]) {
      testWidgets('takes the album out unseen: no frame of the collapse '
          'shows it leaving ${native ? 'natively' : 'in a browser tab'}', (
        tester,
      ) async {
        final (container, _) = await _pumpTab(tester, native: native);
        final gate = Completer<void>();
        _repo(container)
          ..facetItems['album ${_albumPid.substring(3)}'] = [
            testItem('tr-1', title: 'One'),
          ]
          ..deleteItemsGate = gate;
        final albums = WaxRoute.musicIndex(MusicDimension.albums);
        await _go(tester, container, WaxRoute.tasks);
        await _go(tester, container, albums);
        final album = WaxRoute.musicBucket(MusicDimension.albums, _albumPid);
        await _go(tester, container, album);
        await _deleteFrom(tester, SemanticsIds.entityOverflow);
        container.read(nowPlayingProvider.notifier).play(
          [testItem('tr-B', title: 'Salt Harbour')],
          source: const QueueSource(
            kind: QueueSourceKind.single,
            label: 'Salt Harbour',
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.deckExpand));
        await tester.pumpAndSettle();
        gate.complete();
        await tester.pumpAndSettle();
        expect(
          find.byType(AlbumScreen, skipOffstage: false),
          findsNothing,
          reason: 'gone at once, not waiting under the player to leave',
        );

        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerBack));
        for (var frame = 0; frame < 40; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            find.byType(AlbumScreen, skipOffstage: false),
            findsNothing,
            reason: 'frame $frame of the collapse',
          );
        }
        await tester.pumpAndSettle();
        expect(find.byType(MusicIndexScreen), findsOneWidget);
        container.read(queueControllerProvider.notifier).clear();
        await tester.pump(const Duration(seconds: 1));
      });
    }

    testWidgets('a take-out asked while the arrow steps waits for it, and is '
        'made under where it landed', (tester) async {
      // A rewrite in place made while the step is on its way would overtake
      // the visitor's back, and the push it closes would stay.
      final (container, browser) = await _pumpTab(tester);
      final albums = WaxRoute.musicIndex(MusicDimension.albums);
      final album = WaxRoute.musicBucket(MusicDimension.albums, _albumPid);
      await _go(tester, container, albums);
      await _go(tester, container, album);
      final router = _router(container);
      unawaited(router.push<void>(WaxRoute.notifications));
      await tester.pumpAndSettle();
      unawaited(router.push<void>(WaxRoute.tasks));
      await tester.pumpAndSettle();
      browser.latency = const Duration(milliseconds: 100);
      final history = container.read(waxHistoryProvider)!;

      tester.element(find.byType(TasksScreen)).back();
      await tester.pump(const Duration(milliseconds: 1));
      expect(history.stepping, isTrue);
      history.takeOutFromUnder((location, _) => location == album);
      await tester.pump();
      await tester.pumpAndSettle();
      browser.latency = null;

      expect(history.stepping, isFalse);
      expect(find.byType(TasksScreen), findsNothing, reason: 'the back made');
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(_pushes(container), <String>[WaxRoute.notifications]);
      expect(_location(container), albums, reason: 'taken out under it');
      expect(browser.location, albums);
      expect(browser.pushes, <String>[WaxRoute.notifications]);
    });

    testWidgets('lands while the visitor collapses it through the browser: '
        'the collapse stands, and the album is left as natively', (
      tester,
    ) async {
      // The collapse is a pop the browser makes, 100 ms on its way when the
      // delete lands. Natively it has landed by then, the album is on top,
      // and the delete leaves it.
      final (container, browser) = await _pumpTab(tester);
      final gate = Completer<void>();
      _repo(container)
        ..facetItems['album ${_albumPid.substring(3)}'] = [
          testItem('tr-1', title: 'One'),
        ]
        ..deleteItemsGate = gate;
      final albums = WaxRoute.musicIndex(MusicDimension.albums);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, albums);
      final album = WaxRoute.musicBucket(MusicDimension.albums, _albumPid);
      await _go(tester, container, album);
      await _deleteFrom(tester, SemanticsIds.entityOverflow);
      container.read(nowPlayingProvider.notifier).play(
        [testItem('tr-B', title: 'Salt Harbour')],
        source: const QueueSource(
          kind: QueueSourceKind.single,
          label: 'Salt Harbour',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.deckExpand));
      await tester.pumpAndSettle();
      browser.latency = const Duration(milliseconds: 100);
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerBack));
      await tester.pump(const Duration(milliseconds: 1));
      expect(container.read(waxHistoryProvider)!.stepping, isTrue);

      gate.complete();
      await tester.pump();
      await tester.pumpAndSettle();
      browser.latency = null;

      expect(tester.takeException(), isNull);
      expect(find.byType(PlayerScreen), findsNothing, reason: 'collapsed');
      expect(find.byType(AlbumScreen), findsNothing);
      expect(find.byType(MusicIndexScreen), findsOneWidget);
      expect(_location(container), albums);
      expect(browser.location, albums);
      await _back(tester);
      expect(find.byType(AlbumScreen), findsNothing);
      expect(find.byType(TasksScreen), findsOneWidget);
      container.read(queueControllerProvider.notifier).clear();
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('a playlist or an account deleted once the visitor has moved on', () {
    // The server holds the delete while the visitor goes elsewhere: their
    // screen stays, and back does not show what went. Both live in the
    // branch no tab restores, so a tab tap goes to its root.

    /// Tasks, then a playlist, deleted from its overflow while the server
    /// holds the answer.
    Future<(ProviderContainer, Completer<void>)> playlistHeld(
      WidgetTester tester, {
      required bool native,
    }) async {
      final (container, _) = await _pumpTab(tester, native: native);
      final playlist = await _repo(
        container,
      ).createPlaylist(name: 'Road Trip', kind: 'static', itemPids: const []);
      final gate = Completer<void>();
      _repo(container).deletePlaylistGate = gate;
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.playlist(playlist.pid));
      await _deletePlaylist(tester);
      expect(find.byType(PlaylistScreen), findsOneWidget);
      return (container, gate);
    }

    /// Tasks, the accounts, then merry's account, deleted while the server
    /// holds the answer; pippin's account is listed too.
    Future<(ProviderContainer, Completer<void>)> accountHeld(
      WidgetTester tester, {
      required bool native,
    }) async {
      final (container, _) = await _pumpTab(
        tester,
        native: native,
        size: const Size(1200, 4000),
      );
      final gate = Completer<void>();
      _repo(container)
        ..usersById['us-3'] = _account('us-3', 'merry')
        ..usersById['us-4'] = _account('us-4', 'pippin')
        ..deleteUserGate = gate;
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.users);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.userRow('us-3')),
      );
      await tester.pumpAndSettle();
      final delete = find.bySemanticsIdentifier(SemanticsIds.userDelete);
      await tester.ensureVisible(delete);
      await tester.pumpAndSettle();
      // The account's page in the test's wide placeholder font.
      tester.takeException();
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('user-confirm')));
      await tester.pumpAndSettle();
      expect(find.byType(UserEditScreen), findsOneWidget);
      return (container, gate);
    }

    for (final native in <bool>[false, true]) {
      final how = native ? 'natively' : 'in a browser tab';

      testWidgets('a playlist leaves the tab the visitor is on $how', (
        tester,
      ) async {
        final (container, gate) = await playlistHeld(tester, native: native);
        await _tapNav(tester, WaxNavTarget.home);

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.byType(HomeScreen), findsOneWidget);
        expect(_location(container), WaxRoute.home);
        await _back(tester, hub: true);
        expect(find.byType(PlaylistScreen), findsNothing);
        expect(find.byType(TasksScreen), findsOneWidget);
      });

      testWidgets('a playlist leaves a page opened over it $how', (
        tester,
      ) async {
        final (container, gate) = await playlistHeld(tester, native: native);
        unawaited(_router(container).push<void>(WaxRoute.notifications));
        await tester.pumpAndSettle();

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.byType(NotificationsScreen), findsOneWidget);
        expect(_pushes(container), <String>[WaxRoute.notifications]);
        expect(
          _location(container),
          WaxRoute.playlists,
          reason: 'taken out from under it',
        );
        await _back(tester);
        expect(find.byType(PlaylistScreen), findsNothing);
        expect(find.byType(TasksScreen), findsOneWidget);
      });

      testWidgets('a playlist deleted while its rule editor was opened over '
          'it leaves both $how', (tester) async {
        // The editor is the playlist's own: the leave closes it, and the
        // page it lands on, the deleted playlist's, is stepped off too.
        final (container, gate) = await playlistHeld(tester, native: native);
        final playlist = _repo(container).playlistsByPid.values.single;
        unawaited(
          _router(
            container,
          ).push<Object?>(WaxRoute.playlistEdit(playlist.pid), extra: playlist),
        );
        await tester.pumpAndSettle();
        expect(find.byType(RuleEditorScreen), findsOneWidget);

        gate.complete();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(RuleEditorScreen), findsNothing);
        expect(find.byType(PlaylistScreen), findsNothing);
        expect(find.byType(TasksScreen), findsOneWidget);
        expect(_location(container), WaxRoute.tasks);
      });

      testWidgets('an account leaves the tab the visitor is on $how', (
        tester,
      ) async {
        final (container, gate) = await accountHeld(tester, native: native);
        await _tapNav(tester, WaxNavTarget.home);

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.byType(HomeScreen), findsOneWidget);
        expect(_location(container), WaxRoute.home);
        await _back(tester, hub: true);
        expect(tester.takeException(), isNull);
        expect(find.byType(UserEditScreen), findsNothing);
        expect(find.byType(UsersScreen), findsOneWidget);
        expect(find.text('merry'), findsNothing, reason: 'the list is told');
      });

      testWidgets('an account leaves a page opened over its editor $how', (
        tester,
      ) async {
        final (container, gate) = await accountHeld(tester, native: native);
        unawaited(_router(container).push<void>(WaxRoute.notifications));
        await tester.pumpAndSettle();

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.byType(NotificationsScreen), findsOneWidget);
        expect(_pushes(container), <String>[
          WaxRoute.notifications,
        ], reason: 'the editor taken out from under it');
        await _back(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(UserEditScreen), findsNothing);
      });

      testWidgets("an account leaves another account's editor $how", (
        tester,
      ) async {
        // The editor's location carries no account: it is the one shown
        // that tells the two apart.
        final (container, gate) = await accountHeld(tester, native: native);
        await _back(tester);
        expect(find.byType(UsersScreen), findsOneWidget);
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.userRow('us-4')),
        );
        await tester.pumpAndSettle();
        tester.takeException();

        gate.complete();
        await tester.pumpAndSettle();
        tester.takeException();

        expect(find.byType(UserEditScreen), findsOneWidget);
        expect(
          tester.widget<UserEditScreen>(find.byType(UserEditScreen)).user.id,
          'us-4',
        );
      });
    }
  });

  group('work that moves the screen once the server answers, after the '
      'visitor moved on', () {
    // Each holds its server call while the visitor goes to Radio: their
    // screen stays, and nothing is opened over it or taken off it.
    Future<void> movedOn(
      WidgetTester tester,
      ProviderContainer container,
      Completer<void> gate,
    ) async {
      await _tapNav(tester, WaxNavTarget.radio);
      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(RadioScreen), findsOneWidget);
      expect(_location(container), WaxRoute.radio);
      expect(_pushes(container), isEmpty);
    }

    for (final native in <bool>[false, true]) {
      final how = native ? 'natively' : 'in a browser tab';

      testWidgets('a smart playlist saved leaves the screen alone $how', (
        tester,
      ) async {
        final (container, _) = await _pumpTab(tester, native: native);
        final gate = Completer<void>();
        _repo(container).createPlaylistGate = gate;
        await _go(tester, container, WaxRoute.playlists);
        unawaited(
          _router(container).push<Object?>(
            WaxRoute.playlistRules,
            extra: const RuleDraftArgs(name: 'Best of', shared: false),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.ruleSave));
        await tester.pump();

        await movedOn(tester, container, gate);
        expect(
          _repo(container).playlistsByPid.values.where(
            (playlist) => playlist.name == 'Best of',
          ),
          hasLength(1),
        );
      });

      testWidgets('a smart playlist saved is done with: back does not '
          'return to its draft, and it is made once $how', (tester) async {
        final (container, _) = await _pumpTab(tester, native: native);
        final gate = Completer<void>();
        _repo(container).createPlaylistGate = gate;
        await _go(tester, container, WaxRoute.playlists);
        unawaited(
          _router(container).push<Object?>(
            WaxRoute.playlistRules,
            extra: const RuleDraftArgs(name: 'Best of', shared: false),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.ruleSave));
        await tester.pump();

        await movedOn(tester, container, gate);
        await _back(tester, hub: true);

        expect(tester.takeException(), isNull);
        expect(
          find.byType(RuleEditorScreen, skipOffstage: false),
          findsNothing,
          reason: 'neither on screen nor waiting in its branch',
        );
        expect(find.byType(PlaylistsScreen), findsOneWidget);
        expect(
          _repo(container).playlistsByPid.values.where(
            (playlist) => playlist.name == 'Best of',
          ),
          hasLength(1),
        );
      });

      testWidgets("a smart playlist's rule saved is done with: back does "
          'not return to its editor $how', (tester) async {
        final (container, _) = await _pumpTab(tester, native: native);
        final repo = _repo(container);
        final playlist = await repo.createPlaylist(
          name: 'Best of',
          kind: 'smart',
        );
        final gate = Completer<void>();
        repo.updatePlaylistGate = gate;
        await _go(tester, container, WaxRoute.playlist(playlist.pid));
        unawaited(
          _router(
            container,
          ).push<Object?>(WaxRoute.playlistEdit(playlist.pid), extra: playlist),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.ruleSave));
        await tester.pump();

        await movedOn(tester, container, gate);
        await _back(tester, hub: true);

        expect(tester.takeException(), isNull);
        expect(
          find.byType(RuleEditorScreen, skipOffstage: false),
          findsNothing,
        );
        expect(find.byType(PlaylistScreen), findsOneWidget);
      });

      testWidgets('a sync unbound after its sheet was closed leaves the '
          'playlist up $how', (tester) async {
        final (container, _) = await _pumpTab(tester, native: native);
        final repo = _repo(container);
        final playlist = await repo.createPlaylist(
          name: 'Road Trip',
          kind: 'static',
        );
        final gate = Completer<void>();
        repo
          ..playlistSources[playlist.pid] = PlaylistSource(
            source: 'youtube',
            url: 'https://tube.example/playlist?list=PLbound',
            title: 'Road Tapes',
            live: true,
            mode: 'mirror',
            intervalHours: 6,
            disabled: false,
            consecutiveFailures: 0,
            lastSyncedAt: DateTime.utc(2026, 8, 20),
          )
          ..unbindPlaylistSourceGate = gate;
        await _go(tester, container, WaxRoute.tasks);
        await _go(tester, container, WaxRoute.playlist(playlist.pid));
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.playlistOverflow),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.playlistSyncSettings),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.playlistSyncUnbind),
        );
        await tester.pump();
        final sheet = find.bySemanticsIdentifier(
          SemanticsIds.playlistSyncSheet,
        );
        Navigator.of(tester.element(sheet)).pop();
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);

        gate.complete();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(PlaylistScreen), findsOneWidget);
        expect(_location(container), WaxRoute.playlist(playlist.pid));
      });

      testWidgets('a book turned into music leaves the screen alone $how', (
        tester,
      ) async {
        // Its part lands on an album, which takes a read to find.
        const ulid = '01JZX5N8QW3F4V9T2B7KDKINDA1';
        const album = 'al-01JZX5N8QW3F4V9T2B7KDKINDAL';
        final (container, _) = await _pumpTab(tester, native: native);
        final repo = _repo(container)
          ..books['bk-$ulid'] = testBook('bk-$ulid')
          ..libraryItems.add(
            const ItemSummary(
              pid: 'tr-$ulid',
              mediaType: MediaType.music,
              title: 'First Lecture',
              albumPid: album,
              durationMs: 60000,
            ),
          );
        await _go(tester, container, WaxRoute.book('bk-$ulid'));
        unawaited(
          confirmSetKind(
            tester.element(find.byType(BookScreen)),
            pids: ['bk-$ulid'],
            to: 'music',
          ),
        );
        await tester.pumpAndSettle();
        final gate = Completer<void>();
        repo.getItemGate = gate;
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.kindConfirm));
        await tester.pump();
        await tester.pump(kindChangePoll);
        await tester.pumpAndSettle();

        await movedOn(tester, container, gate);
        expect(find.byType(AlbumScreen), findsNothing);
      });

      testWidgets('a mix built leaves the screen alone, and plays $how', (
        tester,
      ) async {
        final (container, _) = await _pumpTab(tester, native: native);
        final gate = Completer<void>();
        _repo(container)
          ..instantMixResult = InstantMix(
            basis: MixBasis.metadata,
            items: [testItem('tr-mix', title: 'Salt Harbour')],
          )
          ..instantMixGate = gate;
        final home = find.byType(HomeScreen);
        unawaited(
          playMixCard(
            tester.element(home),
            tester.element(home) as WidgetRef,
            const MixCard(name: 'Jazz', genre: 'Jazz'),
          ),
        );
        await tester.pump();

        await movedOn(tester, container, gate);
        expect(find.byType(TrackListScreen), findsNothing);
        expect(container.read(nowPlayingProvider).item?.pid, 'tr-mix');
        // What was asked to be seen is offered where the visitor went.
        await _takeOffer(tester, AppLocalizationsEn().homeMixReady('Jazz'));
        expect(find.byType(TrackListScreen), findsOneWidget);
        container.read(queueControllerProvider.notifier).clear();
        await tester.pump(const Duration(seconds: 1));
      });

      /// Home, the genre of a mix card asked for through the card's
      /// menu with the server holding the lookup, then the visitor gone
      /// to Radio and the lookup answered.
      Future<ProviderContainer> genreAskedThenLeft(WidgetTester tester) async {
        final (container, _) = await _pumpTab(tester, native: native);
        final gate = Completer<void>();
        _repo(container)
          ..facets['genre'] = const <FacetBucket>[
            FacetBucket(key: 'gn-jazz', label: 'Jazz', count: 3),
          ]
          ..facetGate = gate;
        final home = find.byType(HomeScreen);
        unawaited(
          showMixMenuSheet(
            tester.element(home),
            tester.element(home) as WidgetRef,
            const MixCard(name: 'Jazz', genre: 'Jazz'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(AppLocalizationsEn().homeMixGoToGenre));
        await tester.pumpAndSettle();

        await movedOn(tester, container, gate);
        expect(find.byType(MusicListingScreen), findsNothing);
        return container;
      }

      testWidgets("a mix card's genre found leaves the screen alone, and is "
          'offered there $how', (tester) async {
        final container = await genreAskedThenLeft(tester);

        await _takeOffer(
          tester,
          AppLocalizationsEn().homeMixBasisReady('Jazz'),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(MusicListingScreen), findsOneWidget);
        expect(_location(container), WaxRoute.radio, reason: 'a drill-in');
        expect(_pushes(container), hasLength(1));
      });

      testWidgets("a mix card's genre offered is opened in the shell from "
          'under the player $how', (tester) async {
        final container = await genreAskedThenLeft(tester);
        container.read(nowPlayingProvider.notifier).play(
          [testItem('tr-B', title: 'Salt Harbour')],
          source: const QueueSource(
            kind: QueueSourceKind.single,
            label: 'Salt Harbour',
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.deckExpand));
        await tester.pumpAndSettle();
        expect(find.byType(PlayerScreen), findsOneWidget);

        // The player's own scaffold draws the bar too, over it.
        final offer = find.text(AppLocalizationsEn().homeMixBasisReady('Jazz'));
        expect(offer.hitTestable(), findsOneWidget, reason: 'still offered');
        await tester.tap(
          find
              .descendant(
                of: find.byType(WaxMessageBar),
                matching: find.text(AppLocalizationsEn().commonOpen),
              )
              .hitTestable(),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(PlayerScreen), findsNothing);
        expect(find.byType(MusicListingScreen), findsOneWidget);
        expect(find.byType(WaxSidebar), findsOneWidget, reason: 'one shell');
        container.read(queueControllerProvider.notifier).clear();
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets('a mix built while a sheet the visitor opened is up leaves '
          'it open, plays, and offers its list $how', (tester) async {
        // Closing what the visitor opened is for a leave: a push waits
        // for them as an offer instead.
        final (container, _) = await _pumpTab(tester, native: native);
        final gate = Completer<void>();
        _repo(container)
          ..instantMixResult = InstantMix(
            basis: MixBasis.metadata,
            items: [testItem('tr-mix', title: 'Salt Harbour')],
          )
          ..instantMixGate = gate;
        final home = find.byType(HomeScreen);
        const card = MixCard(name: 'Jazz', genre: 'Jazz');
        unawaited(
          playMixCard(
            tester.element(home),
            tester.element(home) as WidgetRef,
            card,
          ),
        );
        await tester.pump();
        unawaited(
          showMixMenuSheet(
            tester.element(home),
            tester.element(home) as WidgetRef,
            card,
          ),
        );
        await tester.pumpAndSettle();
        final sheet = find.text(AppLocalizationsEn().homeMixPlay);
        expect(sheet, findsOneWidget);

        gate.complete();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(sheet, findsOneWidget, reason: 'the sheet stays open');
        expect(find.byType(TrackListScreen), findsNothing);
        expect(container.read(nowPlayingProvider).item?.pid, 'tr-mix');
        Navigator.of(tester.element(sheet)).pop();
        await tester.pumpAndSettle();
        await _takeOffer(tester, AppLocalizationsEn().homeMixReady('Jazz'));
        expect(find.byType(TrackListScreen), findsOneWidget);
        container.read(queueControllerProvider.notifier).clear();
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets('similar tracks found from the player collapsed since '
          'leave the screen alone $how', (tester) async {
        final (container, _) = await _pumpTab(tester, native: native);
        final gate = Completer<void>();
        _repo(container).similarTracksGate = gate;
        container.read(nowPlayingProvider.notifier).play(
          [testItem('tr-A', title: 'Salt Harbour')],
          source: const QueueSource(
            kind: QueueSourceKind.single,
            label: 'Salt Harbour',
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.deckExpand));
        await tester.pumpAndSettle();
        final player = find.byType(PlayerScreen);
        unawaited(
          openSimilarTracks(
            tester.element(player),
            tester.element(find.byType(HomeScreen, skipOffstage: false))
                as WidgetRef,
            testItem('tr-A', title: 'Salt Harbour'),
          ),
        );
        await tester.pump();
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerBack));
        await tester.pumpAndSettle();

        await movedOn(tester, container, gate);
        expect(find.byType(TrackListScreen), findsNothing);
        await _takeOffer(
          tester,
          AppLocalizationsEn().discoverySimilarReady('Salt Harbour'),
        );
        expect(find.byType(TrackListScreen), findsOneWidget);
        container.read(queueControllerProvider.notifier).clear();
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets('a saved song identified after its sheet was closed '
          'leaves the screen alone $how', (tester) async {
        final (container, _) = await _pumpTab(tester, native: native);
        final gate = Completer<void>();
        _repo(container)
          ..seedSavedSong(
            RadioSavedSong(
              pid: 'rw-1',
              nowPlaying: 'Salt Harbour - The Bree Trio',
              artist: 'Salt Harbour',
              title: 'The Bree Trio',
              stationPid: _stationPid,
              stationName: 'Coastal FM',
              heardAt: DateTime.utc(2026, 7, 1),
              hasArt: false,
            ),
          )
          ..reviewEntries = [testReviewEntry('rv-1', trackCount: 1)]
          ..reidentifyGate = gate;
        await _go(tester, container, WaxRoute.radioSaved);
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.radioSavedMore('rw-1')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.radioSavedIdentify),
        );
        await tester.pumpAndSettle();
        final entry = find.bySemanticsIdentifier(
          SemanticsIds.radioSavedIdentifyEntry('rv-1'),
        );
        await tester.tap(entry);
        await tester.pump();
        Navigator.of(tester.element(entry)).pop();
        await tester.pumpAndSettle();

        await movedOn(tester, container, gate);
        expect(find.byType(ReviewEntryScreen), findsNothing);
      });

      testWidgets('an account saved leaves the screen alone, and is not '
          'shown again $how', (tester) async {
        final (container, _) = await _pumpTab(
          tester,
          native: native,
          size: const Size(1200, 4000),
        );
        final gate = Completer<void>();
        _repo(container)
          ..usersById['us-3'] = _account('us-3', 'merry')
          ..updateUserGate = gate;
        await _go(tester, container, WaxRoute.tasks);
        await _go(tester, container, WaxRoute.users);
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.userRow('us-3')),
        );
        await tester.pumpAndSettle();
        tester.takeException();
        final save = find.bySemanticsIdentifier(SemanticsIds.userSave);
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pump();

        await movedOn(tester, container, gate);
        await _back(tester, hub: true);
        expect(tester.takeException(), isNull);
        expect(find.byType(UserEditScreen), findsNothing);
        expect(find.byType(UsersScreen), findsOneWidget);
      });

      testWidgets('a saved song identified as its sheet leaves, the visitor '
          'gone on, closes nothing else $how', (tester) async {
        // Mounted is not there: on its way out the sheet's own pop would
        // take what is on top of its navigator instead.
        final (container, _) = await _pumpTab(tester, native: native);
        final gate = Completer<void>();
        _repo(container)
          ..seedSavedSong(
            RadioSavedSong(
              pid: 'rw-1',
              nowPlaying: 'Salt Harbour - The Bree Trio',
              artist: 'Salt Harbour',
              title: 'The Bree Trio',
              stationPid: _stationPid,
              stationName: 'Coastal FM',
              heardAt: DateTime.utc(2026, 7, 1),
              hasArt: false,
            ),
          )
          ..reviewEntries = [testReviewEntry('rv-1', trackCount: 1)]
          ..reidentifyGate = gate;
        await _go(tester, container, WaxRoute.radioSaved);
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.radioSavedMore('rw-1')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.radioSavedIdentify),
        );
        await tester.pumpAndSettle();
        final entry = find.bySemanticsIdentifier(
          SemanticsIds.radioSavedIdentifyEntry('rv-1'),
        );
        await tester.tap(entry);
        await tester.pump();
        Navigator.of(tester.element(entry)).pop();
        await tester.pump();
        _router(container).go(WaxRoute.radio);
        await tester.pump();
        gate.complete();
        await tester.pump();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(RadioScreen), findsOneWidget);
        expect(_location(container), WaxRoute.radio);
        expect(find.byType(ReviewEntryScreen), findsNothing);
      });

      testWidgets('a session stopped from the remote screen closed since '
          'leaves the screen alone $how', (tester) async {
        final (container, _) = await _pumpTab(tester, native: native);
        final gate = Completer<void>();
        _repo(container).deletePlaybackSessionGate = gate;
        container
            .read(remoteSessionProvider.notifier)
            .adopt(
              PlaybackSessionInfo(
                id: 'ps-remote',
                endpointId: 'pe-speaker',
                endpointName: 'Kitchen speaker',
                mine: true,
                authority: 'remote',
                playing: true,
                index: 0,
                positionMs: 1000,
                positionAt: DateTime.now().toUtc(),
                rate: 1,
                volume: 0.8,
                queueVersion: 1,
                entries: const [
                  PlaybackSessionEntry(
                    pid: 'tr-x',
                    title: 'Alpha',
                    durationMs: 30000,
                  ),
                ],
              ),
            );
        await _go(tester, container, WaxRoute.tasks);
        unawaited(_router(container).push<void>(WaxRoute.remote));
        await tester.pumpAndSettle();
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.remoteStopThere),
        );
        await tester.pump();
        await _back(tester);
        expect(find.byType(TasksScreen), findsOneWidget);

        await movedOn(tester, container, gate);
      });
    }
  });

  group('a page done with in a branch the visitor left', () {
    // Forgotten there, it leaves its navigator unseen as the branch is
    // next shown: left to the navigator, it would be seen sliding off.
    // Transitions on, each frame of the way back looked at.
    Future<void> unseen(WidgetTester tester, Type page) async {
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          find.byType(page),
          findsNothing,
          reason: 'frame $frame of the way back',
        );
      }
      await tester.pumpAndSettle();
      expect(find.byType(page, skipOffstage: false), findsNothing);
    }

    for (final native in <bool>[false, true]) {
      final how = native ? 'natively' : 'in a browser tab';

      testWidgets('a smart playlist saved leaves unseen: no frame of the way '
          'back shows its editor $how', (tester) async {
        final (container, _) = await _pumpTab(
          tester,
          native: native,
          animated: true,
        );
        final gate = Completer<void>();
        _repo(container).createPlaylistGate = gate;
        await _go(tester, container, WaxRoute.playlists);
        final heard = <Object?>[];
        unawaited(
          _router(container)
              .push<Object?>(
                WaxRoute.playlistRules,
                extra: const RuleDraftArgs(name: 'Best of', shared: false),
              )
              .then(heard.add),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.ruleSave));
        await tester.pump();
        await _tapNav(tester, WaxNavTarget.radio);
        gate.complete();
        await tester.pumpAndSettle();

        expect(find.byType(RadioScreen), findsOneWidget);

        tester.element(find.byType(WaxScaffold).last).back();
        await unseen(tester, RuleEditorScreen);
        expect(tester.takeException(), isNull);
        expect(find.byType(PlaylistsScreen), findsOneWidget);
        expect(heard, <Object?>[
          null,
        ], reason: 'its opener is not left waiting');
      });

      testWidgets('an account saved leaves unseen: no frame of the way back '
          'shows its editor $how', (tester) async {
        final (container, _) = await _pumpTab(
          tester,
          native: native,
          animated: true,
          size: const Size(1200, 4000),
        );
        final gate = Completer<void>();
        _repo(container)
          ..usersById['us-3'] = _account('us-3', 'merry')
          ..updateUserGate = gate;
        await _go(tester, container, WaxRoute.tasks);
        await _go(tester, container, WaxRoute.users);
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.userRow('us-3')),
        );
        await tester.pumpAndSettle();
        tester.takeException();
        final save = find.bySemanticsIdentifier(SemanticsIds.userSave);
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pump();
        await _tapNav(tester, WaxNavTarget.radio);
        gate.complete();
        await tester.pumpAndSettle();

        expect(find.byType(RadioScreen), findsOneWidget);

        tester.element(find.byType(WaxScaffold).last).back();
        await unseen(tester, UserEditScreen);
        expect(tester.takeException(), isNull);
        expect(find.byType(UsersScreen), findsOneWidget);
      });

      testWidgets('an album deleted leaves unseen: no frame of the tap on '
          'Music shows it $how', (tester) async {
        final (container, _) = await _pumpTab(
          tester,
          native: native,
          animated: true,
        );
        final gate = Completer<void>();
        _repo(container)
          ..facetItems['album ${_albumPid.substring(3)}'] = [
            testItem('tr-1', title: 'One'),
          ]
          ..deleteItemsGate = gate;
        await _go(
          tester,
          container,
          WaxRoute.musicIndex(MusicDimension.albums),
        );
        await _go(
          tester,
          container,
          WaxRoute.musicBucket(MusicDimension.albums, _albumPid),
        );
        await _deleteFrom(tester, SemanticsIds.entityOverflow);
        await _tapNav(tester, WaxNavTarget.home);
        gate.complete();
        await tester.pumpAndSettle();

        expect(find.byType(HomeScreen), findsOneWidget);

        await tester.tap(
          find
              .byWidgetPredicate(
                (widget) =>
                    widget is Semantics &&
                    widget.properties.identifier ==
                        SemanticsIds.navDestination(WaxNavTarget.music.name),
              )
              .first,
        );
        await unseen(tester, AlbumScreen);
        expect(tester.takeException(), isNull);
        expect(find.byType(MusicIndexScreen), findsOneWidget);
      });

      /// The albums index, an album deleted with the server holding it
      /// while the visitor taps Home, then the delete landed.
      Future<ProviderContainer> albumDeletedFromHome(
        WidgetTester tester,
      ) async {
        final (container, _) = await _pumpTab(
          tester,
          native: native,
          animated: true,
        );
        final gate = Completer<void>();
        _repo(container)
          ..albums[_otherAlbumPid] = const AlbumDetail(
            pid: _otherAlbumPid,
            title: 'Tidewrack',
          )
          ..facetItems['album ${_albumPid.substring(3)}'] = [
            testItem('tr-1', title: 'One'),
          ]
          ..deleteItemsGate = gate;
        await _go(
          tester,
          container,
          WaxRoute.musicIndex(MusicDimension.albums),
        );
        await _go(
          tester,
          container,
          WaxRoute.musicBucket(MusicDimension.albums, _albumPid),
        );
        await _deleteFrom(tester, SemanticsIds.entityOverflow);
        await _tapNav(tester, WaxNavTarget.home);
        gate.complete();
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
        return container;
      }

      testWidgets('another album opened there afterwards leaves as any page '
          'does $how', (tester) async {
        // An album's page is keyed by its route: the one that waited to
        // leave unseen is not the one shown there now.
        final container = await albumDeletedFromHome(tester);
        final other = WaxRoute.musicBucket(
          MusicDimension.albums,
          _otherAlbumPid,
        );
        await _go(tester, container, other);
        expect(find.byType(AlbumScreen), findsOneWidget);
        expect(_location(container), other);

        _router(container).go(WaxRoute.musicIndex(MusicDimension.albums));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          find.byType(AlbumScreen),
          findsOneWidget,
          reason: 'on its way out, as any page left',
        );
        await tester.pumpAndSettle();
        expect(find.byType(AlbumScreen), findsNothing);
        expect(find.byType(MusicIndexScreen), findsOneWidget);
      });

      testWidgets('a move to the place itself afterwards shows a page there '
          '$how', (tester) async {
        // go_router holds the branch as it was left, so a move to the
        // same place shows the navigator it kept: a page taken out of
        // that at once would leave the place showing the one under it.
        final container = await albumDeletedFromHome(tester);
        final album = WaxRoute.musicBucket(MusicDimension.albums, _albumPid);
        await _go(tester, container, album);

        expect(_location(container), album);
        expect(find.byType(AlbumScreen), findsOneWidget);
        expect(find.byType(MusicIndexScreen), findsNothing);
      });
    }

    // The finished editor's own browser entry stays (it cannot say what
    // it was gone to with), so a browser back lands on it: the page comes
    // back without its payload and leaves by itself.
    for (final stepsBack in <bool>[true, false]) {
      testWidgets('a smart playlist saved, then a browser back onto its '
          "editor's entry, shows no frame of the editor, and the page left "
          'there leaves ${stepsBack ? 'through the browser' : 'by a pop'}', (
        tester,
      ) async {
        final (container, browser) = await _pumpTab(tester, animated: true);
        final gate = Completer<void>();
        _repo(container).createPlaylistGate = gate;
        await _go(tester, container, WaxRoute.playlists);
        unawaited(
          _router(container).push<Object?>(
            WaxRoute.playlistRules,
            extra: const RuleDraftArgs(name: 'Best of', shared: false),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.ruleSave));
        await tester.pump();
        await _tapNav(tester, WaxNavTarget.radio);
        gate.complete();
        await tester.pumpAndSettle();
        expect(find.byType(RadioScreen), findsOneWidget);

        // With no entry behind to step to, the page pops the router's way.
        if (!stepsBack) browser.stepsBack = false;
        browser.goBack();
        await unseen(tester, RuleEditorScreen);
        expect(tester.takeException(), isNull);
        expect(find.byType(PlaylistsScreen), findsOneWidget);
        expect(_pushes(container), isEmpty);
        expect(container.read(waxHistoryProvider)!.stepping, isFalse);
      });
    }

    testWidgets('a push closed by a pop a move to another branch overtook '
        'leaves unseen: no frame of the tap on its branch shows it', (
      tester,
    ) async {
      final (container, browser) = await _pumpTab(tester, animated: true);
      await _go(tester, container, WaxRoute.podcasts);
      final router = _router(container);
      unawaited(router.push<String>(WaxRoute.episode(_episodePid)));
      await tester.pumpAndSettle();
      browser.latency = const Duration(milliseconds: 100);
      unawaited(router.leave(result: 'played'));
      await tester.pump(const Duration(milliseconds: 1));
      router.go(WaxRoute.uploads);
      await tester.pump();
      await tester.pumpAndSettle();
      browser.latency = null;
      expect(find.byType(UploadsScreen), findsOneWidget);
      expect(container.read(waxHistoryProvider)!.stepping, isFalse);

      await tester.tap(
        find
            .byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.identifier ==
                      SemanticsIds.navDestination(WaxNavTarget.podcasts.name),
            )
            .first,
      );
      await unseen(tester, EpisodeScreen);
      expect(tester.takeException(), isNull);
      expect(find.byType(PodcastsScreen), findsOneWidget);
    });
  });

  testWidgets('similar tracks found while the collapse of the player that '
      'asked is on its way leave the page under it alone', (tester) async {
    // Natively the collapse has landed when the answer comes, and the
    // player that asked is gone: the follow is decided from there.
    final (container, browser) = await _pumpTab(tester);
    final gate = Completer<void>();
    _repo(container).similarTracksGate = gate;
    await _go(tester, container, WaxRoute.podcasts);
    unawaited(_router(container).push<void>(WaxRoute.episode(_episodePid)));
    await tester.pumpAndSettle();
    container.read(nowPlayingProvider.notifier).play(
      [testItem('tr-A', title: 'Salt Harbour')],
      source: const QueueSource(
        kind: QueueSourceKind.single,
        label: 'Salt Harbour',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.deckExpand));
    await tester.pumpAndSettle();
    unawaited(
      openSimilarTracks(
        tester.element(find.byType(PlayerScreen)),
        tester.element(find.byType(EpisodeScreen, skipOffstage: false))
            as WidgetRef,
        testItem('tr-A', title: 'Salt Harbour'),
      ),
    );
    await tester.pump();
    browser.latency = const Duration(milliseconds: 100);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerBack));
    await tester.pump(const Duration(milliseconds: 1));
    expect(container.read(waxHistoryProvider)!.stepping, isTrue);

    gate.complete();
    await tester.pump();
    await tester.pumpAndSettle();
    browser.latency = null;

    expect(tester.takeException(), isNull);
    expect(find.byType(PlayerScreen), findsNothing);
    expect(find.byType(EpisodeScreen), findsOneWidget, reason: 'not popped');
    expect(find.byType(TrackListScreen), findsNothing);
    expect(_pushes(container), <String>[WaxRoute.episode(_episodePid)]);
    expect(
      find.text(AppLocalizationsEn().discoverySimilarReady('Salt Harbour')),
      findsOneWidget,
      reason: 'offered',
    );
    container.read(queueControllerProvider.notifier).clear();
    await tester.pump(const Duration(seconds: 1));
  });

  group('a pop on the browser, then a move', () {
    /// Tasks, then an album with the full player expanded over it, a
    /// track or [station] playing.
    Future<(ProviderContainer, FakeBrowser)> playerOverAlbum(
      WidgetTester tester, {
      bool station = false,
    }) async {
      final (container, browser) = await _pumpTab(tester);
      if (station) {
        _repo(container).radioStationsByPid[_stationPid] = _station;
        await container.read(radioPlaybackProvider.notifier).play(_station);
      } else {
        container.read(nowPlayingProvider.notifier).play(
          [testItem('tr-A', title: 'Salt Harbour')],
          source: const QueueSource(
            kind: QueueSourceKind.single,
            label: 'Salt Harbour',
          ),
        );
      }
      await tester.pumpAndSettle();
      await _go(tester, container, WaxRoute.tasks);
      await _go(
        tester,
        container,
        WaxRoute.musicBucket(MusicDimension.albums, _albumPid),
      );
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.deckExpand));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsOneWidget);
      return (container, browser);
    }

    testWidgets('the radio face to all stations ends on the Radio hub', (
      tester,
    ) async {
      final (container, browser) = await playerOverAlbum(tester, station: true);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.radioMenu(_stationPid)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppLocalizationsEn().playerAllStations));
      await tester.pumpAndSettle();

      expect(find.byType(RadioScreen), findsOneWidget);
      expect(find.byType(PlayerScreen), findsNothing);
      expect(_location(container), WaxRoute.radio);
      expect(browser.location, WaxRoute.radio);
      expect(
        browser.entries.where((entry) => entry.location == WaxRoute.radio),
        hasLength(1),
      );

      await container.read(radioPlaybackProvider.notifier).stop();
      await tester.pumpAndSettle();
    });

    testWidgets('a push in the shell over two overlays leaves both, then '
        'pushes', (tester) async {
      final (container, browser) = await playerOverAlbum(tester);
      final router = _router(container);
      unawaited(router.push<void>(WaxRoute.queue));
      await tester.pumpAndSettle();
      expect(find.byType(QueueScreen), findsOneWidget);

      unawaited(router.pushInShell<void>(WaxRoute.notifications));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(find.byType(QueueScreen), findsNothing);
      expect(find.byType(PlayerScreen), findsNothing);
      expect(browser.backs, 2);

      await _back(tester);
      expect(find.byType(AlbumScreen), findsOneWidget);
      expect(find.byType(PlayerScreen), findsNothing);

      container.read(queueControllerProvider.notifier).clear();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the rule editor leaving on its save cannot save twice', (
      tester,
    ) async {
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.playlists);
      final heard = <Object?>[];
      unawaited(
        _router(container)
            .push<Object?>(
              WaxRoute.playlistRules,
              extra: const RuleDraftArgs(name: 'Best of', shared: false),
            )
            .then(heard.add),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RuleEditorScreen), findsOneWidget);

      final save = find.bySemanticsIdentifier(SemanticsIds.ruleSave);
      await tester.tap(save);
      await tester.pump();
      expect(browser.backs, 1, reason: 'the save is leaving');
      await tester.tap(save, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(
        _repo(
          container,
        ).playlistsByPid.values.where((playlist) => playlist.name == 'Best of'),
        hasLength(1),
      );
      expect(find.byType(RuleEditorScreen), findsNothing);
      expect(heard, hasLength(1));
    });
  });

  testWidgets('an editor saved answers the list that opened it, and the '
      'arrow then goes where the list was opened from', (tester) async {
    final (container, browser) = await _pumpTab(tester);
    _repo(container).usersById['us-3'] = _account('us-3', 'merry');
    await _go(tester, container, WaxRoute.tasks);
    await _go(tester, container, WaxRoute.users);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.userRow('us-3')));
    await tester.pumpAndSettle();
    expect(find.byType(UserEditScreen), findsOneWidget);
    _repo(container).usersById['us-4'] = _account('us-4', 'pippin');
    final save = find.bySemanticsIdentifier(SemanticsIds.userSave);
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.byType(UsersScreen), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.userRow('us-4')),
      findsOneWidget,
      reason: 'the list heard the save and read itself again',
    );

    await _back(tester);

    expect(tester.takeException(), isNull);
    expect(browser.backs, 2);
    expect(find.byType(TasksScreen), findsOneWidget);
    expect(find.byType(UserEditScreen), findsNothing);
  });

  testWidgets('the player collapsed is not opened again by the arrow', (
    tester,
  ) async {
    final (container, browser) = await _pumpTab(tester);
    container.read(nowPlayingProvider.notifier).play(
      [testItem('tr-A', title: 'Salt Harbour')],
      source: const QueueSource(
        kind: QueueSourceKind.single,
        label: 'Salt Harbour',
      ),
    );
    await tester.pumpAndSettle();
    await _go(tester, container, WaxRoute.tasks);
    await _go(
      tester,
      container,
      WaxRoute.musicBucket(MusicDimension.albums, _albumPid),
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.deckExpand));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerScreen), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerBack));
    await tester.pumpAndSettle();
    expect(find.byType(AlbumScreen), findsOneWidget);

    await _back(tester);

    expect(find.byType(TasksScreen), findsOneWidget);
    expect(find.byType(PlayerScreen), findsNothing);
    expect(browser.backs, 2);

    container.read(queueControllerProvider.notifier).clear();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a browser landing keeps the payload the visit was pushed '
      'with', (tester) async {
    // The entries keep no payload, so the visit has to remember it for
    // every later landing.
    final (container, browser) = await _pumpTab(tester);
    _repo(container).usersById['us-3'] = _account('us-3', 'merry');
    await _go(tester, container, WaxRoute.users);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.userRow('us-3')));
    await tester.pumpAndSettle();
    await _go(tester, container, WaxRoute.radio);
    await _browserBack(tester, browser);
    await _browserForward(tester, browser);
    expect(find.byType(RadioScreen), findsOneWidget);

    await _back(tester, hub: true);

    expect(tester.takeException(), isNull);
    expect(browser.backs, 1);
    expect(
      tester.widget<UserEditScreen>(find.byType(UserEditScreen)).user.id,
      'us-3',
    );
  });

  group('a visit pushed with a payload', () {
    /// Users with an account's editor pushed over it, then Radio gone to.
    Future<(ProviderContainer, FakeBrowser)> editorThenRadio(
      WidgetTester tester,
    ) async {
      final (container, browser) = await _pumpTab(tester);
      _repo(container).usersById['us-3'] = _account('us-3', 'merry');
      await _go(tester, container, WaxRoute.users);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.userRow('us-3')),
      );
      await tester.pumpAndSettle();
      await _go(tester, container, WaxRoute.radio);
      return (container, browser);
    }

    UserAccount edited(WidgetTester tester) =>
        tester.widget<UserEditScreen>(find.byType(UserEditScreen)).user;

    testWidgets('is shown with its payload by browser back', (tester) async {
      // The entry dropped it, the visit kept it.
      final (_, browser) = await editorThenRadio(tester);

      await _browserBack(tester, browser);

      expect(tester.takeException(), isNull);
      expect(edited(tester).id, 'us-3');
    });

    testWidgets('is returned to by the arrow on the browser list, and its '
        'opener hears the save', (tester) async {
      final (container, browser) = await editorThenRadio(tester);

      await _back(tester, hub: true);
      expect(tester.takeException(), isNull);
      expect(browser.backs, 1);
      expect(edited(tester).id, 'us-3');

      await _browserForward(tester, browser);
      expect(find.byType(RadioScreen), findsOneWidget, reason: 'one list');
      await _browserBack(tester, browser);
      expect(edited(tester).id, 'us-3');

      _repo(container).usersById['us-4'] = _account('us-4', 'pippin');
      final save = find.bySemanticsIdentifier(SemanticsIds.userSave);
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(UsersScreen), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.userRow('us-4')),
        findsOneWidget,
      );
    });

    testWidgets('passed as a stray by the arrow does not throw', (
      tester,
    ) async {
      final (container, browser) = await _pumpTab(tester);
      _repo(container).usersById['us-3'] = _account('us-3', 'merry');
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.users);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.userRow('us-3')),
      );
      await tester.pumpAndSettle();
      await _go(tester, container, WaxRoute.radio);
      container.read(waxHistoryProvider)!.forget(WaxRoute.users);
      browser.framed = true;

      await _back(tester, hub: true);

      expect(tester.takeException(), isNull);
      expect(browser.backs, 3, reason: 'the editor, the list, then Tasks');
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(
        container.read(waxHistoryProvider)!.canGoBack,
        isTrue,
        reason: 'landed on the visit it was after',
      );
    });
  });

  testWidgets('a browser forward between two visits of one place moves '
      'forward', (tester) async {
    // Tasks, Notifications, Tasks: the entry forward is the visit behind
    // too, and only the way the browser went tells them apart.
    final (container, browser) = await _pumpTab(tester, at: WaxRoute.tasks);
    await _go(tester, container, WaxRoute.notifications);
    await _go(tester, container, WaxRoute.tasks);
    await _browserBack(tester, browser);
    expect(find.byType(NotificationsScreen), findsOneWidget);

    await _browserForward(tester, browser);
    expect(find.byType(TasksScreen), findsOneWidget);
    expect(container.read(waxHistoryProvider)!.canGoBack, isTrue);

    await _back(tester);
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(_location(container), WaxRoute.notifications);
  });

  testWidgets('browser backs between visits of two places move back', (
    tester,
  ) async {
    // Each entry behind matches a visit ahead as well.
    final (container, browser) = await _pumpTab(tester, at: WaxRoute.tasks);
    for (final location in <String>[
      WaxRoute.notifications,
      WaxRoute.tasks,
      WaxRoute.notifications,
      WaxRoute.tasks,
    ]) {
      await _go(tester, container, location);
    }
    for (var i = 0; i < 4; i++) {
      await _browserBack(tester, browser);
    }
    expect(find.byType(TasksScreen), findsOneWidget);
    expect(
      container.read(waxHistoryProvider)!.canGoBack,
      isFalse,
      reason: 'back at the link it opened on',
    );
  });

  testWidgets('an entry the same as the one on screen does not stop the '
      'arrow', (tester) async {
    // A go to the location on screen changes nothing but is an entry.
    final (container, browser) = await _pumpTab(tester);
    await _go(tester, container, WaxRoute.notifications);
    await _go(tester, container, WaxRoute.tasks);
    await _go(tester, container, WaxRoute.tasks);
    expect(browser.entries.map((entry) => entry.location), <String>[
      WaxRoute.home,
      WaxRoute.notifications,
      WaxRoute.tasks,
      WaxRoute.tasks,
    ]);

    await _back(tester);
    expect(
      find.byType(NotificationsScreen),
      findsOneWidget,
      reason: 'one press',
    );
    expect(browser.backs, 2);

    // Nothing of that step is left for the next browser move to misread.
    await _browserForward(tester, browser);
    expect(find.byType(TasksScreen), findsOneWidget);
    expect(container.read(waxHistoryProvider)!.canGoBack, isTrue);
  });

  group('an entry the list forgot', () {
    Future<(ProviderContainer, FakeBrowser)> forgotten(
      WidgetTester tester,
      List<String> locations,
      String forget,
    ) async {
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.tasks);
      for (final location in locations) {
        await _go(tester, container, location);
      }
      await _go(tester, container, WaxRoute.radio);
      container.read(waxHistoryProvider)!.forget(forget);
      return (container, browser);
    }

    const sections = <String>[
      WaxRoute.users,
      WaxRoute.backups,
      WaxRoute.audit,
      WaxRoute.trash,
      WaxRoute.schedules,
      WaxRoute.libraries,
    ];

    testWidgets('is stepped past by the arrow, which never builds it', (
      tester,
    ) async {
      final (container, browser) = await forgotten(tester, <String>[
        WaxRoute.notifications,
      ], WaxRoute.notifications);
      final built = _arrivals(container);

      await _back(tester, hub: true);
      expect(browser.backs, 2);
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(_location(container), WaxRoute.tasks);
      expect(built, isNot(contains(WaxRoute.notifications)));
    });

    testWidgets('five times at most, then the arrow goes the router way', (
      tester,
    ) async {
      final (container, browser) = await forgotten(
        tester,
        sections,
        WaxRoute.admin,
      );

      await _back(tester, hub: true);
      expect(browser.backs, 6);
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(_location(container), WaxRoute.tasks);
      expect(browser.location, WaxRoute.tasks);

      await _back(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('five times at most, then the router way in place: the '
        'entries stay one list with the visits', (tester) async {
      final (container, browser) = await forgotten(
        tester,
        sections,
        WaxRoute.admin,
      );
      final entries = browser.entries.length;

      await _back(tester, hub: true);
      expect(browser.backs, 6);
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(browser.entries, hasLength(entries), reason: 'none minted');
      expect(browser.index, 2, reason: 'where the walk stopped');
      expect(browser.location, WaxRoute.tasks);

      // The entry behind is the visit's own, which shows nothing new.
      await _browserBack(tester, browser);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(browser.index, 0);
      await _browserForward(tester, browser);
      expect(find.byType(TasksScreen), findsOneWidget);
      await _back(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('is passed over by browser back, which never builds it', (
      tester,
    ) async {
      final (container, browser) = await forgotten(tester, <String>[
        WaxRoute.notifications,
      ], WaxRoute.notifications);
      final built = _arrivals(container);

      await _browserBack(tester, browser);

      expect(find.byType(TasksScreen), findsOneWidget);
      expect(_location(container), WaxRoute.tasks);
      expect(browser.location, WaxRoute.tasks);
      expect(built, isNot(contains(WaxRoute.notifications)));
      expect(container.read(waxHistoryProvider)!.canGoBack, isTrue);
      await _back(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('is passed over by browser forward, which never builds it', (
      tester,
    ) async {
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.notifications);
      await _go(tester, container, WaxRoute.radio);
      await _browserBack(tester, browser);
      await _browserBack(tester, browser);
      expect(find.byType(TasksScreen), findsOneWidget);
      container.read(waxHistoryProvider)!.forget(WaxRoute.notifications);
      final built = _arrivals(container);

      await _browserForward(tester, browser);

      expect(find.byType(RadioScreen), findsOneWidget);
      expect(browser.location, WaxRoute.radio);
      expect(built, isNot(contains(WaxRoute.notifications)));
      await _back(tester, hub: true);
      expect(find.byType(TasksScreen), findsOneWidget);
    });

    for (final count in <int>[5, 6]) {
      testWidgets('$count in a row are passed by browser back five at most', (
        tester,
      ) async {
        final (container, browser) = await forgotten(
          tester,
          sections.take(count).toList(),
          WaxRoute.admin,
        );
        final built = _arrivals(container);

        await _browserBack(tester, browser);

        expect(browser.backs, 5, reason: 'the app passed five');
        final shown = count == 5 ? WaxRoute.tasks : WaxRoute.users;
        expect(_location(container), shown);
        expect(browser.location, shown);
        expect(built, <String>[shown], reason: 'nothing built on the way');
      });
    }

    testWidgets("as the app's first entry, gives way to what stands in for "
        'it rather than being shown', (tester) async {
      // A pass never leaves the app, so the entry is written over: a top
      // location of the branch every other location shares has nothing
      // declared under it and that branch no root, so Home stands in.
      final (container, browser) = await _pumpTab(
        tester,
        at: WaxRoute.notifications,
      );
      await _go(tester, container, WaxRoute.tasks);
      container.read(waxHistoryProvider)!.forget(WaxRoute.notifications);
      final built = _arrivals(container);

      await _browserBack(tester, browser);

      expect(browser.backs, 0);
      expect(browser.left, isFalse);
      expect(built, isNot(contains(WaxRoute.notifications)));
      expect(find.byType(NotificationsScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(_location(container), WaxRoute.home);
      expect(browser.index, 0);
      expect(browser.location, WaxRoute.home, reason: 'written over it');
      // One list with the entries: Tasks is ahead, and back from it Home.
      await _browserForward(tester, browser);
      expect(find.byType(TasksScreen), findsOneWidget);
      await _back(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(browser.index, 0);
    });

    for (final returning in <bool>[false, true]) {
      final how = returning
          ? 'after a return to the app, which knows no newest'
          : 'after a reload';

      testWidgets('$how, one ahead that is not the newest does not keep '
          'browser forward from what lies past it', (tester) async {
        final (first, browser) = await _pumpTab(tester);
        _repo(first)
          ..books[_bookPid] = testBook(_bookPid, partCount: 2)
          ..libraryItems.add(testItem(_bookPid));
        await _go(tester, first, WaxRoute.books);
        await _go(tester, first, WaxRoute.book(_bookPid));
        await _go(tester, first, WaxRoute.tasks);
        final (container, _) = await _pumpTab(
          tester,
          reloading: browser,
          returning: returning,
        );
        expect(find.byType(TasksScreen), findsOneWidget);
        await _browserBack(tester, browser);
        await _browserBack(tester, browser);
        expect(find.byType(BooksScreen), findsOneWidget);
        final history = container.read(waxHistoryProvider)!
          ..forget(WaxRoute.book(_bookPid));
        final built = _arrivals(container);

        await _browserForward(tester, browser);
        if (returning) {
          // Not known to be the newest, so let through as the router has
          // it, and the next forward goes on.
          expect(browser.location, WaxRoute.book(_bookPid));
          await _browserForward(tester, browser);
        } else {
          expect(built, isNot(contains(WaxRoute.book(_bookPid))));
        }

        expect(tester.takeException(), isNull);
        expect(find.byType(TasksScreen), findsOneWidget);
        expect(browser.location, WaxRoute.tasks);
        expect(history.stepping, isFalse);
      });
    }

    testWidgets("as the app's first entry behind a full list, gives way to "
        'what stands in for it, and forward still reaches the newest visit', (
      tester,
    ) async {
      final (container, browser) = await _pumpTab(
        tester,
        at: WaxRoute.notifications,
      );
      browser.kept = 100;
      final searches = [for (var i = 0; i < 50; i++) WaxRoute.searchFor('q$i')];
      for (final search in searches) {
        await _go(tester, container, search);
      }
      final history = container.read(waxHistoryProvider)!
        ..forget(WaxRoute.notifications);
      for (var i = 1; i < searches.length; i++) {
        await _browserBack(tester, browser);
      }
      expect(_location(container), searches.first);

      await _browserBack(tester, browser);
      expect(find.byType(HomeScreen), findsOneWidget, reason: 'stands in');
      for (var i = 0; i < searches.length; i++) {
        await _browserForward(tester, browser);
      }

      expect(_location(container), searches.last);
      expect(history.canGoBack, isTrue);
      final backs = browser.backs;
      await _back(tester, hub: true);
      expect(browser.backs, backs + 1, reason: "the browser's own step");
      expect(_location(container), searches[searches.length - 2]);
    });

    testWidgets('as the newest entry, is turned back from by browser '
        'forward, which never builds it', (tester) async {
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.notifications);
      await _browserBack(tester, browser);
      final history = container.read(waxHistoryProvider)!
        ..forget(WaxRoute.notifications);
      final built = _arrivals(container);

      await _browserForward(tester, browser);

      expect(browser.forwards, 0, reason: 'nothing ahead to step to');
      expect(browser.backs, 1, reason: 'back to the entry on screen');
      expect(built, isEmpty);
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(browser.location, WaxRoute.tasks);
      expect(history.stepping, isFalse);
      await _back(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('is not passed over once visited again', (tester) async {
      final (container, browser) = await forgotten(tester, <String>[
        WaxRoute.notifications,
      ], WaxRoute.notifications);
      await _go(tester, container, WaxRoute.notifications);
      await _go(tester, container, WaxRoute.radio);

      await _browserBack(tester, browser);

      expect(browser.backs, 0);
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(_location(container), WaxRoute.notifications);
    });

    testWidgets('by an extra the browser cannot read is landed on', (
      tester,
    ) async {
      // The entry has no extra to tell one account's editor by, so it
      // is the list's to step past.
      final (container, browser) = await _pumpTab(tester);
      _repo(container).usersById['us-3'] = _account('us-3', 'merry');
      await _go(tester, container, WaxRoute.users);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.userRow('us-3')),
      );
      await tester.pumpAndSettle();
      await _go(tester, container, WaxRoute.radio);
      container
          .read(waxHistoryProvider)!
          .forget(
            WaxRoute.userEdit,
            where: (extra) => extra is UserEditArgs && extra.user.id == 'us-3',
          );
      browser.framed = true;

      await _back(tester, hub: true);

      expect(tester.takeException(), isNull);
      expect(browser.backs, 2, reason: 'the editor, then the list');
      expect(find.byType(UsersScreen), findsOneWidget);
      expect(find.byType(UserEditScreen), findsNothing);
    });

    testWidgets('a deleted playlist is passed over by browser back', (
      tester,
    ) async {
      final (container, browser) = await _pumpTab(tester);
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
      final built = _arrivals(container);

      await _browserBack(tester, browser);
      expect(find.byType(TasksScreen), findsOneWidget);
      await _browserBack(tester, browser);

      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(_location(container), WaxRoute.notifications);
      expect(built, isNot(contains(at)));
    });

    testWidgets('a playlist opened from its list and deleted is passed over '
        'with the list again by one browser back', (tester) async {
      // The leave is a router pop, an entry of the list after the
      // playlist's own.
      final (container, browser) = await _pumpTab(tester);
      final playlist = await _repo(
        container,
      ).createPlaylist(name: 'Road Trip', kind: 'static', itemPids: const []);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.playlists);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.playlist(playlist.pid)),
      );
      await tester.pumpAndSettle();
      await _deletePlaylist(tester);
      expect(find.byType(PlaylistsScreen), findsOneWidget);
      final built = _arrivals(container);

      await _browserBack(tester, browser);

      expect(find.byType(TasksScreen), findsOneWidget);
      expect(_location(container), WaxRoute.tasks);
      expect(browser.location, WaxRoute.tasks);
      expect(built, <String>[WaxRoute.tasks]);
    });

    testWidgets('a pass stops at the location on screen without the push '
        'over it', (tester) async {
      // Podcasts, an episode pushed over it, a playlist, then the tab
      // tap that brings the push back.
      final (container, browser) = await _pumpTab(tester);
      final playlist = await _repo(
        container,
      ).createPlaylist(name: 'Road Trip', kind: 'static', itemPids: const []);
      await _go(tester, container, WaxRoute.podcasts);
      unawaited(_router(container).push<void>(WaxRoute.episode(_episodePid)));
      await tester.pumpAndSettle();
      await _go(tester, container, WaxRoute.playlist(playlist.pid));
      await _tapNav(tester, WaxNavTarget.podcasts);
      expect(find.byType(EpisodeScreen), findsOneWidget);
      container
          .read(waxHistoryProvider)!
          .forget(WaxRoute.playlist(playlist.pid));
      final built = _arrivals(container);

      await _browserBack(tester, browser);

      expect(browser.backs, 2, reason: 'the playlist, then the episode again');
      expect(find.byType(EpisodeScreen), findsNothing);
      expect(find.byType(PodcastsScreen), findsOneWidget);
      expect(built, <String>[WaxRoute.podcasts]);
    });

    testWidgets('an album opened from its list and deleted is passed over '
        'with the list again by one browser back', (tester) async {
      final (container, browser) = await _pumpTab(tester);
      _repo(container).facetItems['album ${_albumPid.substring(3)}'] = [
        testItem('tr-1', title: 'One'),
      ];
      final albums = WaxRoute.musicIndex(MusicDimension.albums);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, albums);
      // As the index's bucket does.
      _router(container).go(
        WaxRoute.musicBucket(MusicDimension.albums, _albumPid),
        extra: 'Gullwing',
      );
      await tester.pumpAndSettle();
      await _deleteFrom(tester, SemanticsIds.entityOverflow);
      expect(_location(container), albums);
      final built = _arrivals(container);

      await _browserBack(tester, browser);

      expect(find.byType(TasksScreen), findsOneWidget);
      expect(_location(container), WaxRoute.tasks);
      expect(browser.location, WaxRoute.tasks);
      expect(built, <String>[WaxRoute.tasks]);
    });

    testWidgets('is passed over by browser back after sixty later forgets', (
      tester,
    ) async {
      final (container, browser) = await forgotten(tester, <String>[
        WaxRoute.notifications,
      ], WaxRoute.notifications);
      final history = container.read(waxHistoryProvider)!;
      for (var i = 0; i < 60; i++) {
        history.forget(WaxRoute.book('bk-$i'));
      }
      final built = _arrivals(container);

      await _browserBack(tester, browser);

      expect(find.byType(TasksScreen), findsOneWidget);
      expect(_location(container), WaxRoute.tasks);
      expect(built, isNot(contains(WaxRoute.notifications)));
    });

    testWidgets('an album of twenty tracks deleted from its own screen is '
        'passed over by browser back', (tester) async {
      final (container, browser) = await _pumpTab(tester);
      _repo(container).facetItems['album ${_albumPid.substring(3)}'] = [
        for (var i = 0; i < 20; i++) testItem('tr-$i', title: 'Track $i'),
      ];
      final album = WaxRoute.musicBucket(MusicDimension.albums, _albumPid);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, album);
      await _deleteFrom(tester, SemanticsIds.entityOverflow);
      expect(find.byType(AlbumScreen), findsNothing);
      final built = _arrivals(container);

      await _browserBack(tester, browser);

      expect(built, isNot(contains(album)));
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(_location(container), WaxRoute.tasks);
    });

    testWidgets('landed two entries away by the back menu starts the list '
        'over', (tester) async {
      final (container, browser) = await _pumpTab(tester);
      for (final location in <String>[
        WaxRoute.tasks,
        WaxRoute.notifications,
        WaxRoute.radio,
      ]) {
        await _go(tester, container, location);
      }

      browser.jump(-2);
      await tester.pumpAndSettle();

      expect(find.byType(TasksScreen), findsOneWidget);
      expect(container.read(waxHistoryProvider)!.canGoBack, isFalse);
    });
  });

  group('a push the list forgot', () {
    // A push's entry is at its base's location, so only the state the
    // entry keeps says what was pushed.

    /// Tasks, [base] with [pushed] over it, more pushes over that, then
    /// Radio, where the item [pid] is deleted from a menu.
    Future<(ProviderContainer, FakeBrowser)> deletedFromRadio(
      WidgetTester tester, {
      required String base,
      required List<String> pushed,
      required String pid,
    }) async {
      final (container, browser) = await _pumpTab(tester);
      _repo(container)
        ..books[_bookPid] = testBook(_bookPid, partCount: 2)
        ..libraryItems.add(testItem(_bookPid));
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, base);
      for (final location in pushed) {
        unawaited(_router(container).push<void>(location));
        await tester.pumpAndSettle();
      }
      await _go(tester, container, WaxRoute.radio);
      unawaited(
        confirmDeleteItem(tester.element(find.byType(RadioScreen)), pid: pid),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.itemDeleteConfirm),
      );
      await tester.pumpAndSettle();
      return (container, browser);
    }

    testWidgets('an episode pushed over its hub is passed over by browser '
        'back', (tester) async {
      final (container, browser) = await deletedFromRadio(
        tester,
        base: WaxRoute.podcasts,
        pushed: [WaxRoute.episode(_episodePid)],
        pid: _episodePid,
      );
      final pushes = _pushArrivals(container);

      await _browserBack(tester, browser);

      expect(browser.backs, 1);
      expect(pushes, isEmpty, reason: 'the episode never built');
      expect(find.byType(EpisodeScreen), findsNothing);
      expect(find.byType(PodcastsScreen), findsOneWidget);
      expect(_router(container).canPop(), isFalse);
    });

    testWidgets('a book pushed from a search hit is passed over by browser '
        'back', (tester) async {
      // Pushed, as the hit does.
      final (container, browser) = await deletedFromRadio(
        tester,
        base: WaxRoute.searchFor('dune'),
        pushed: [WaxRoute.book(_bookPid)],
        pid: _bookPid,
      );
      final pushes = _pushArrivals(container);

      await _browserBack(tester, browser);

      expect(browser.backs, 1);
      expect(pushes, isEmpty, reason: 'the book never built');
      expect(find.byType(BookScreen), findsNothing);
      expect(find.byType(SearchScreen), findsOneWidget);
      expect(_location(container), WaxRoute.searchFor('dune'));
    });

    testWidgets('leaves the base under it for the arrow to reach', (
      tester,
    ) async {
      final (container, browser) = await deletedFromRadio(
        tester,
        base: WaxRoute.podcasts,
        pushed: [WaxRoute.episode(_episodePid)],
        pid: _episodePid,
      );
      final pushes = _pushArrivals(container);

      await _back(tester, hub: true);
      expect(browser.backs, 2, reason: 'the episode passed on the way');
      expect(find.byType(PodcastsScreen), findsOneWidget);
      expect(_location(container), WaxRoute.podcasts);
      expect(pushes, isEmpty);
      expect(container.read(waxHistoryProvider)!.canGoBack, isTrue);

      await _back(tester, hub: true);
      expect(find.byType(TasksScreen), findsOneWidget);
    });

    testWidgets('under another push is let through', (tester) async {
      // The entry shows the show, which is not gone.
      final (container, browser) = await deletedFromRadio(
        tester,
        base: WaxRoute.podcasts,
        pushed: [WaxRoute.episode(_episodePid), WaxRoute.show(_showPid)],
        pid: _episodePid,
      );

      await _browserBack(tester, browser);

      expect(browser.backs, 0);
      expect(find.byType(ShowScreen), findsOneWidget);
    });
  });

  group('a delete under the full player of an episode gone to by its link', () {
    for (final native in <bool>[false, true]) {
      for (final animated in <bool>[false, true]) {
        final how =
            '${native ? 'natively' : 'in a browser tab'}'
            '${animated ? ', animated' : ''}';

        testWidgets('takes it out before the player collapses: no frame shows '
            'it $how', (tester) async {
          final (container, _) = await _pumpTab(
            tester,
            at: WaxRoute.episode(_episodePid),
            native: native,
            animated: animated,
          );
          final gate = Completer<void>();
          _repo(container)
            ..libraryItems.add(testItem(_episodePid, title: 'Ep'))
            ..deleteItemsGate = gate;
          expect(find.byType(EpisodeScreen), findsOneWidget);
          unawaited(
            confirmDeleteItem(
              tester.element(find.byType(EpisodeScreen)),
              pid: _episodePid,
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.bySemanticsIdentifier(SemanticsIds.itemDeleteConfirm),
          );
          await tester.pumpAndSettle();
          container.read(nowPlayingProvider.notifier).play(
            [testItem('tr-B', title: 'Salt Harbour')],
            source: const QueueSource(
              kind: QueueSourceKind.single,
              label: 'Salt Harbour',
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.bySemanticsIdentifier(SemanticsIds.deckExpand));
          await tester.pumpAndSettle();
          expect(find.byType(PlayerScreen), findsOneWidget);

          gate.complete();
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(_location(container), WaxRoute.podcasts, reason: 'under it');
          expect(
            find.byType(EpisodeScreen, skipOffstage: false),
            findsNothing,
            reason: 'gone at once, not waiting under the player to leave',
          );
          await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerBack));
          for (var frame = 0; frame < 40; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(
              find.byType(EpisodeScreen),
              findsNothing,
              reason: 'frame $frame of the collapse',
            );
          }
          await tester.pumpAndSettle();
          expect(find.byType(PodcastsScreen), findsOneWidget);
          container.read(queueControllerProvider.notifier).clear();
          await tester.pump(const Duration(seconds: 1));
        });
      }
    }
  });

  group('a delete under the full player of an item editor gone to by its '
      'link', () {
    const pid = 'tr-01JZX5N8QW3F4V9T2B7KDTRACK1';

    for (final native in <bool>[false, true]) {
      final how = native ? 'natively' : 'in a browser tab';

      testWidgets('leaves Home under the player, and collapsing it shows Home '
          '$how', (tester) async {
        final (container, _) = await _pumpTab(
          tester,
          at: WaxRoute.metadata(pid),
          native: native,
        );
        final gate = Completer<void>();
        _repo(container)
          ..libraryItems.add(testItem(pid, title: 'Long Division'))
          ..deleteItemsGate = gate;
        expect(find.byType(MetadataScreen), findsOneWidget);
        unawaited(
          confirmDeleteItem(
            tester.element(find.byType(MetadataScreen)),
            pid: pid,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.itemDeleteConfirm),
        );
        await tester.pumpAndSettle();
        // Another track.
        container.read(nowPlayingProvider.notifier).play(
          [testItem('tr-B', title: 'Salt Harbour')],
          source: const QueueSource(
            kind: QueueSourceKind.single,
            label: 'Salt Harbour',
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.deckExpand));
        await tester.pumpAndSettle();
        expect(find.byType(PlayerScreen), findsOneWidget);

        gate.complete();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(PlayerScreen), findsOneWidget, reason: 'it stays');
        expect(_pushes(container), <String>[WaxRoute.nowPlaying]);
        expect(_location(container), WaxRoute.home, reason: 'under it');
        final built = _arrivals(container);

        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerBack));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(PlayerScreen), findsNothing);
        expect(find.byType(MetadataScreen), findsNothing);
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(_location(container), WaxRoute.home);
        expect(built, isNot(contains(WaxRoute.metadata(pid))));
        container.read(queueControllerProvider.notifier).clear();
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets('with a page pushed over it in its branch, leaves Home '
          'under that page $how', (tester) async {
        final (container, _) = await _pumpTab(
          tester,
          at: WaxRoute.metadata(pid),
          native: native,
        );
        final gate = Completer<void>();
        _repo(container)
          ..libraryItems.add(testItem(pid, title: 'Long Division'))
          ..deleteItemsGate = gate;
        unawaited(
          confirmDeleteItem(
            tester.element(find.byType(MetadataScreen)),
            pid: pid,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.itemDeleteConfirm),
        );
        await tester.pumpAndSettle();
        unawaited(_router(container).push<void>(WaxRoute.notifications));
        await tester.pumpAndSettle();

        gate.complete();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.byType(NotificationsScreen, skipOffstage: false),
          findsOneWidget,
          reason: 'moved with its visit, not built twice',
        );
        expect(_pushes(container), <String>[WaxRoute.notifications]);
        expect(_location(container), WaxRoute.home, reason: 'under it');
        final built = _arrivals(container);

        await _back(tester);

        expect(tester.takeException(), isNull);
        expect(find.byType(NotificationsScreen), findsNothing);
        expect(find.byType(MetadataScreen), findsNothing);
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(built, isNot(contains(WaxRoute.metadata(pid))));
      });

      testWidgets('with a sheet open over a page pushed over it in its branch, '
          'closes the sheet and answers it before the page moves $how', (
        tester,
      ) async {
        final (container, _) = await _pumpTab(
          tester,
          at: WaxRoute.metadata(pid),
          native: native,
        );
        final gate = Completer<void>();
        _repo(container)
          ..libraryItems.add(testItem(pid, title: 'Long Division'))
          ..deleteItemsGate = gate;
        unawaited(
          confirmDeleteItem(
            tester.element(find.byType(MetadataScreen)),
            pid: pid,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.itemDeleteConfirm),
        );
        await tester.pumpAndSettle();
        unawaited(_router(container).push<void>(WaxRoute.notifications));
        await tester.pumpAndSettle();
        final answered = <Object?>[];
        unawaited(
          showWaxSheet<String>(
            context: tester.element(find.byType(NotificationsScreen)),
            builder: (_) => const Text('Sure?'),
          ).then(answered.add),
        );
        await tester.pumpAndSettle();
        expect(find.text('Sure?'), findsOneWidget);

        gate.complete();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(_location(container), WaxRoute.home);
        expect(find.byType(NotificationsScreen), findsOneWidget);
        expect(find.text('Sure?', skipOffstage: false), findsNothing);
        expect(answered, <Object?>[null], reason: 'closed, so answered');
        final history = container.read(waxHistoryProvider)!;
        expect(history.pagelessOnTop, isFalse);
      });

      testWidgets('with a page pushed over it in its branch, that page goes on '
          'with its visit: a move elsewhere does not close it $how', (
        tester,
      ) async {
        final (container, _) = await _pumpTab(
          tester,
          at: WaxRoute.metadata(pid),
          native: native,
        );
        final gate = Completer<void>();
        _repo(container)
          ..libraryItems.add(testItem(pid, title: 'Long Division'))
          ..deleteItemsGate = gate;
        unawaited(
          confirmDeleteItem(
            tester.element(find.byType(MetadataScreen)),
            pid: pid,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.itemDeleteConfirm),
        );
        await tester.pumpAndSettle();
        final heard = <Object?>[];
        unawaited(
          _router(
            container,
          ).push<Object?>(WaxRoute.notifications).then(heard.add),
        );
        await tester.pumpAndSettle();
        gate.complete();
        await tester.pumpAndSettle();
        expect(_location(container), WaxRoute.home);

        await _go(tester, container, WaxRoute.searchFor('dune'));

        expect(tester.takeException(), isNull);
        expect(heard, isEmpty, reason: 'its opener still waits on it');
        await _tapNav(tester, WaxNavTarget.home);
        expect(find.byType(NotificationsScreen), findsOneWidget);
        expect(heard, isEmpty);
      });
    }
  });

  group('a page done with, then the browser back and forward', () {
    testWidgets('an account deleted on its own editor never has the editor '
        'reached again', (tester) async {
      final (container, browser) = await _pumpTab(
        tester,
        size: const Size(1200, 4000),
      );
      _repo(container).usersById['us-3'] = _account('us-3', 'merry');
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.users);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.userRow('us-3')),
      );
      await tester.pumpAndSettle();
      final delete = find.bySemanticsIdentifier(SemanticsIds.userDelete);
      await tester.ensureVisible(delete);
      await tester.pumpAndSettle();
      // The account's page in the test's wide placeholder font.
      tester.takeException();
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('user-confirm')));
      await tester.pumpAndSettle();
      expect(find.byType(UsersScreen), findsOneWidget);
      final pushes = _pushArrivals(container);

      await _browserBack(tester, browser);
      expect(find.byType(TasksScreen), findsOneWidget);
      await _browserForward(tester, browser);
      await _browserForward(tester, browser);

      expect(tester.takeException(), isNull);
      expect(pushes, isNot(contains(WaxRoute.userEdit)));
      expect(find.byType(UserEditScreen), findsNothing);
      expect(find.byType(UsersScreen), findsOneWidget);
      expect(browser.pushes, isEmpty, reason: 'not on its entry either');
      expect(container.read(waxHistoryProvider)!.stepping, isFalse);
    });

    testWidgets('a book pushed from a search hit and deleted on its own '
        'screen is never reached again', (tester) async {
      final (container, browser) = await _pumpTab(tester);
      _repo(container)
        ..books[_bookPid] = testBook(_bookPid, partCount: 2)
        ..libraryItems.add(testItem(_bookPid));
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.searchFor('dune'));
      // Pushed, as the hit does.
      unawaited(_router(container).push<void>(WaxRoute.book(_bookPid)));
      await tester.pumpAndSettle();
      await _deleteFrom(tester, SemanticsIds.bookOverflow);
      expect(find.byType(BookScreen), findsNothing);
      final pushes = _pushArrivals(container);
      final shown = _location(container);

      await _browserBack(tester, browser);
      await _browserForward(tester, browser);
      expect(_location(container), shown);
      await _browserForward(tester, browser);

      expect(tester.takeException(), isNull);
      expect(pushes, isNot(contains(WaxRoute.book(_bookPid))));
      expect(find.byType(BookScreen), findsNothing);
      expect(_location(container), shown);
      expect(browser.pushes, isEmpty, reason: 'not on its entry either');
      expect(container.read(waxHistoryProvider)!.stepping, isFalse);
    });
  });

  group('a review entry decided while another is open', () {
    final decisions = <String, Future<void> Function(WidgetTester)>{
      'from the keyboard': (tester) async {
        // The cursor came to the open row; k moves it to the one above.
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.pumpAndSettle();
      },
      'in bulk': (tester) async {
        await tester.longPress(
          find.bySemanticsIdentifier(SemanticsIds.reviewRow('rv-1')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.reviewRow('rv-3')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip),
        );
        await tester.pumpAndSettle();
      },
    };

    for (final MapEntry(key: how, value: decide) in decisions.entries) {
      testWidgets('$how is passed over by browser back, which never builds '
          'it', (tester) async {
        // Two panes: Tasks, the queue, then two entries opened in turn
        // and the first decided with the second open.
        final (container, browser) = await _pumpTab(
          tester,
          size: const Size(1400, 1000),
        );
        _repo(container).reviewEntries = [
          for (final id in <String>['rv-1', 'rv-2', 'rv-3'])
            testReviewEntry(id),
        ];
        await _go(tester, container, WaxRoute.tasks);
        await _go(tester, container, WaxRoute.review);
        for (final id in <String>['rv-1', 'rv-2']) {
          await tester.tap(
            find.bySemanticsIdentifier(SemanticsIds.reviewRow(id)),
          );
          await tester.pumpAndSettle();
        }
        expect(browser.location, WaxRoute.reviewEntry('rv-2'));
        await decide(tester);
        final repo = _repo(container);
        expect(<String>[
          for (final call in repo.decideReviewCalls) call.entryId,
          for (final call in repo.decideBulkCalls) ...call.entryIds,
        ], contains('rv-1'));
        expect(_location(container), WaxRoute.reviewEntry('rv-2'));
        final built = _arrivals(container);

        await _browserBack(tester, browser);

        expect(_location(container), WaxRoute.review);
        expect(browser.location, WaxRoute.review);
        expect(
          find.bySemanticsIdentifier(SemanticsIds.reviewPane),
          findsNothing,
        );
        expect(built, isNot(contains(WaxRoute.reviewEntry('rv-1'))));
        await _browserBack(tester, browser);
        expect(find.byType(TasksScreen), findsOneWidget);
      });
    }

    testWidgets('the last two in bulk leave the queue by one browser back', (
      tester,
    ) async {
      // Nothing left pending, the pane swaps the open entry's for the
      // queue: the queue, the first entry's, the queue again.
      final (container, browser) = await _pumpTab(
        tester,
        size: const Size(1400, 1000),
      );
      _repo(container).reviewEntries = [
        for (final id in <String>['rv-1', 'rv-2']) testReviewEntry(id),
      ];
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.review);
      for (final id in <String>['rv-1', 'rv-2']) {
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.reviewRow(id)),
        );
        await tester.pumpAndSettle();
      }
      await tester.longPress(
        find.bySemanticsIdentifier(SemanticsIds.reviewRow('rv-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.reviewRow('rv-2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip));
      await tester.pumpAndSettle();
      expect(_location(container), WaxRoute.review);
      final built = _arrivals(container);

      await _browserBack(tester, browser);

      expect(find.byType(TasksScreen), findsOneWidget);
      expect(_location(container), WaxRoute.tasks);
      expect(browser.location, WaxRoute.tasks);
      expect(built, <String>[WaxRoute.tasks]);
    });
  });

  group('a step the browser never answers', () {
    // A tab past its bound drops its oldest entries and numbers on, so a
    // step back from the oldest it kept reads as one it can take, and
    // goes nowhere.
    Future<void> wait(WidgetTester tester) async {
      await tester.pump(WaxHistory.unansweredStep);
      await tester.pumpAndSettle();
    }

    List<String> locations(FakeBrowser browser) => [
      for (final entry in browser.entries) entry.location,
    ];

    testWidgets('of a pass is given up for the entry the browser is on', (
      tester,
    ) async {
      final (container, browser) = await _pumpTab(tester);
      browser.kept = 3;
      for (final location in <String>[
        WaxRoute.notifications,
        WaxRoute.tasks,
        WaxRoute.radio,
      ]) {
        await _go(tester, container, location);
      }
      expect(locations(browser), <String>[
        WaxRoute.notifications,
        WaxRoute.tasks,
        WaxRoute.radio,
      ]);
      final history = container.read(waxHistoryProvider)!
        ..forget(WaxRoute.notifications);
      await _browserBack(tester, browser);
      await _browserBack(tester, browser);
      expect(browser.backs, 1, reason: 'the pass, which goes nowhere');

      await wait(tester);

      expect(history.stepping, isFalse);
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(_location(container), WaxRoute.notifications);
      await _back(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('of a pop the app pushes over meanwhile closes the page, '
        'answers its opener, and leaves no entry of it', (tester) async {
      // The episode's entry is the oldest the tab kept, so the pop's step
      // goes nowhere; the show pushed meanwhile stands over Podcasts, as
      // natively, where the pop lands first.
      final (container, browser) = await _pumpTab(tester);
      final episode = WaxRoute.episode(_episodePid);
      await _go(tester, container, WaxRoute.podcasts);
      final router = _router(container);
      final heard = <Object?>[];
      browser.kept = 1;
      unawaited(router.push<String>(episode).then(heard.add));
      await tester.pumpAndSettle();
      browser.kept = 50;
      expect(browser.entries, hasLength(1));
      expect(browser.pushesAt(0), <String>[episode]);
      var left = false;
      unawaited(router.leave(result: 'played').then((_) => left = true));
      await tester.pump();
      unawaited(router.push<void>(WaxRoute.show(_showPid)));
      await tester.pump();
      await wait(tester);

      final history = container.read(waxHistoryProvider)!;
      expect(history.stepping, isFalse);
      expect(find.byType(ShowScreen), findsOneWidget);
      expect(left, isTrue);
      expect(heard, <Object?>['played']);
      expect(_pushes(container), <String>[WaxRoute.show(_showPid)]);
      expect(browser.location, _location(container), reason: 'the address');
      expect(browser.pushes, _pushes(container));
      for (var i = 0; i < browser.entries.length; i++) {
        expect(browser.pushesAt(i), isNot(contains(episode)));
      }
      await _back(tester);
      await wait(tester);
      expect(find.byType(PodcastsScreen), findsOneWidget);
      expect(find.byType(EpisodeScreen), findsNothing);
    });

    // The give-up and a move of the app's no frame has reported yet, in
    // one frame: the move is written where one already reported is.
    for (final over in <bool>[true, false]) {
      testWidgets('of a pop given up in the frame the app '
          '${over ? 'pushes over its page' : 'goes elsewhere'} leaves no '
          'entry of the page closed', (tester) async {
        final (container, browser) = await _pumpTab(tester);
        final episode = WaxRoute.episode(_episodePid);
        final show = WaxRoute.show(_showPid);
        await _go(tester, container, WaxRoute.podcasts);
        final router = _router(container);
        final heard = <Object?>[];
        browser.kept = 1;
        unawaited(router.push<String>(episode).then(heard.add));
        await tester.pumpAndSettle();
        browser.kept = 50;
        unawaited(router.leave(result: 'played'));
        await tester.pump();
        await tester.pump(
          WaxHistory.unansweredStep - const Duration(milliseconds: 2),
        );
        Timer(const Duration(milliseconds: 1), () {
          if (over) {
            unawaited(router.push<void>(show));
          } else {
            router.go(WaxRoute.uploads);
          }
        });
        await tester.pump(const Duration(milliseconds: 5));
        await wait(tester);

        expect(container.read(waxHistoryProvider)!.stepping, isFalse);
        expect(find.byType(over ? ShowScreen : UploadsScreen), findsOneWidget);
        expect(heard, <Object?>['played']);
        expect(locations(browser), <String>[
          over ? WaxRoute.podcasts : WaxRoute.uploads,
        ], reason: 'written over the entry of the page closed');
        expect(browser.pushesAt(0), over ? <String>[show] : isEmpty);
        expect(browser.location, _location(container), reason: 'the address');
      });
    }

    testWidgets('of a pop the app pushes over in the frame it was given up '
        'writes the push past the page beneath, and leaves no entry of the '
        'page closed', (tester) async {
      final (container, browser) = await _pumpTab(tester);
      final episode = WaxRoute.episode(_episodePid);
      final show = WaxRoute.show(_showPid);
      await _go(tester, container, WaxRoute.podcasts);
      final router = _router(container);
      final heard = <Object?>[];
      browser.kept = 1;
      unawaited(router.push<String>(episode).then(heard.add));
      await tester.pumpAndSettle();
      browser.kept = 50;
      unawaited(router.leave(result: 'played'));
      await tester.pump();
      // Once the pop is given up, before a frame.
      Timer(
        WaxHistory.unansweredStep + const Duration(microseconds: 500),
        () => unawaited(router.push<void>(show)),
      );
      await tester.pump(
        WaxHistory.unansweredStep + const Duration(milliseconds: 1),
      );
      await tester.pumpAndSettle();

      expect(container.read(waxHistoryProvider)!.stepping, isFalse);
      expect(find.byType(ShowScreen), findsOneWidget);
      expect(heard, <Object?>['played']);
      expect(locations(browser), <String>[
        WaxRoute.podcasts,
        WaxRoute.podcasts,
      ]);
      expect(browser.pushesAt(0), isEmpty);
      expect(browser.pushesAt(1), <String>[show]);
      await _browserBack(tester, browser);
      expect(find.byType(PodcastsScreen), findsOneWidget);
      expect(find.byType(EpisodeScreen), findsNothing);
    });

    for (final swap in <bool>[true, false]) {
      testWidgets('of a pass given up in the frame the app '
          '${swap ? 'swaps' : 'goes'} elsewhere writes that past the entry '
          'the browser is on', (tester) async {
        final (container, browser) = await _pumpTab(tester);
        browser.kept = 3;
        for (final location in <String>[
          WaxRoute.notifications,
          WaxRoute.tasks,
          WaxRoute.radio,
        ]) {
          await _go(tester, container, location);
        }
        final history = container.read(waxHistoryProvider)!
          ..forget(WaxRoute.notifications);
        await _browserBack(tester, browser);
        final tasks = tester.element(find.byType(TasksScreen));
        browser.goBack();
        await tester.pump(Duration.zero);
        expect(browser.backs, 1, reason: 'the pass, which goes nowhere');
        await tester.pump(
          WaxHistory.unansweredStep - const Duration(milliseconds: 2),
        );
        Timer(const Duration(milliseconds: 1), () {
          if (swap) {
            tasks.swap(WaxRoute.uploads);
          } else {
            _router(container).go(WaxRoute.uploads);
          }
        });
        await tester.pump(const Duration(milliseconds: 5));
        await wait(tester);

        expect(history.stepping, isFalse);
        expect(find.byType(UploadsScreen), findsOneWidget);
        expect(browser.location, _location(container), reason: 'the address');
        expect(locations(browser), <String>[
          WaxRoute.notifications,
          WaxRoute.uploads,
        ], reason: 'past the entry the browser is on');
        expect(browser.index, 1);
      });
    }

    for (final swap in <bool>[true, false]) {
      testWidgets('of a pass during which the app ${swap ? 'swaps' : 'goes'} '
          'elsewhere writes that past the entry the browser is on, and the '
          'address shows the page', (tester) async {
        final (container, browser) = await _pumpTab(tester);
        browser.kept = 3;
        for (final location in <String>[
          WaxRoute.notifications,
          WaxRoute.tasks,
          WaxRoute.radio,
        ]) {
          await _go(tester, container, location);
        }
        final history = container.read(waxHistoryProvider)!
          ..forget(WaxRoute.notifications);
        await _browserBack(tester, browser);
        await _browserBack(tester, browser);
        expect(browser.backs, 1, reason: 'the pass, which goes nowhere');
        expect(browser.location, WaxRoute.notifications);

        if (swap) {
          tester.element(find.byType(TasksScreen)).swap(WaxRoute.uploads);
        } else {
          _router(container).go(WaxRoute.uploads);
        }
        await tester.pump();
        await wait(tester);

        expect(history.stepping, isFalse);
        expect(find.byType(UploadsScreen), findsOneWidget);
        expect(browser.location, _location(container), reason: 'the address');
        expect(locations(browser), <String>[
          WaxRoute.notifications,
          WaxRoute.uploads,
        ], reason: 'past the entry the browser is on');
        expect(browser.index, 1);
      });
    }

    testWidgets('of the arrow on the oldest entry the tab kept, during which '
        'the app swaps the page, writes the swap in place', (tester) async {
      // The step goes nowhere, so the browser never left the entry the
      // engine writes to: a swap made meanwhile belongs on it, not past it.
      final (container, browser) = await _pumpTab(tester);
      browser.kept = 1;
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.searchFor('j'));
      browser.kept = 50;
      expect(browser.entries, hasLength(1));
      final history = container.read(waxHistoryProvider)!;

      tester.element(find.byType(SearchScreen)).back();
      await tester.pump();
      expect(history.stepping, isTrue, reason: 'a step that goes nowhere');
      tester
          .element(find.byType(SearchScreen))
          .swap(WaxRoute.searchFor('jazz'));
      await tester.pump();
      await wait(tester);

      expect(history.stepping, isFalse);
      expect(find.byType(SearchScreen), findsOneWidget);
      expect(browser.location, WaxRoute.searchFor('jazz'));
      expect(locations(browser), <String>[
        WaxRoute.searchFor('jazz'),
      ], reason: 'in place, no copy of the screen it replaced behind it');
    });

    testWidgets('a return after a give-up that wrote past an entry steps as '
        'far as the browser went', (tester) async {
      // The give-up writes the move past the entry the browser is on, two
      // behind the one the engine numbered it for: it is numbered from the
      // entry it lands past, so no number is skipped. The arrow then steps
      // back that one entry, and the app moves meanwhile: the return is
      // one step.
      final (container, browser) = await _pumpTab(tester);
      browser.kept = 3;
      for (final location in <String>[
        WaxRoute.notifications,
        WaxRoute.tasks,
        WaxRoute.radio,
      ]) {
        await _go(tester, container, location);
      }
      final history = container.read(waxHistoryProvider)!
        ..forget(WaxRoute.notifications);
      await _browserBack(tester, browser);
      await _browserBack(tester, browser);
      _router(container).go(WaxRoute.uploads);
      await tester.pump();
      await wait(tester);
      expect(locations(browser), <String>[
        WaxRoute.notifications,
        WaxRoute.uploads,
      ]);
      expect(
        browser.entries[1].serial - browser.entries[0].serial,
        1,
        reason: 'no gap in the numbers',
      );

      browser.latency = const Duration(milliseconds: 100);
      tester.element(find.byType(UploadsScreen)).back();
      await tester.pump(const Duration(milliseconds: 1));
      _router(container).go(WaxRoute.radio);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 150));
      await wait(tester);
      browser.latency = null;

      expect(history.stepping, isFalse);
      expect(find.byType(RadioScreen), findsOneWidget);
      expect(browser.location, WaxRoute.radio);
      expect(locations(browser), <String>[
        WaxRoute.notifications,
        WaxRoute.uploads,
        WaxRoute.radio,
      ], reason: 'the move past the entry the engine writes to');
      await _browserBack(tester, browser);
      expect(find.byType(UploadsScreen), findsOneWidget, reason: 'in one');
    });

    testWidgets('of the arrow is taken the router way to the visit it was '
        'after', (tester) async {
      final (container, browser) = await _pumpTab(tester);
      browser.kept = 2;
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.notifications);
      await _go(tester, container, WaxRoute.notifications);
      expect(locations(browser), <String>[
        WaxRoute.notifications,
        WaxRoute.notifications,
      ]);
      await _back(tester);
      expect(browser.backs, 2, reason: 'the copy, then nowhere');
      expect(find.byType(NotificationsScreen), findsOneWidget);

      await wait(tester);

      final history = container.read(waxHistoryProvider)!;
      expect(history.stepping, isFalse);
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(_location(container), WaxRoute.tasks);
      expect(history.canGoBack, isTrue);
      await _back(tester);
      await wait(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('of a pop is made the router way, with its result', (
      tester,
    ) async {
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.podcasts);
      browser.kept = 1;
      final router = _router(container);
      final heard = <Object?>[];
      unawaited(
        router.push<String>(WaxRoute.episode(_episodePid)).then(heard.add),
      );
      await tester.pumpAndSettle();
      expect(browser.entries, hasLength(1));
      var landed = false;
      unawaited(router.leave(result: 'played').then((_) => landed = true));
      await tester.pumpAndSettle();
      expect(browser.backs, 1);
      expect(landed, isFalse);

      await wait(tester);

      expect(landed, isTrue);
      expect(heard, <Object?>['played']);
      expect(find.byType(EpisodeScreen), findsNothing);
      expect(find.byType(PodcastsScreen), findsOneWidget);
      expect(container.read(waxHistoryProvider)!.stepping, isFalse);
      await _back(tester, hub: true);
      await wait(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('of the arrow is made in place, and the next back goes '
        'where the list says', (tester) async {
      final (container, browser) = await _pumpTab(tester);
      browser.kept = 2;
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.notifications);
      await _go(tester, container, WaxRoute.notifications);
      await _back(tester);
      expect(browser.backs, 2, reason: 'the copy, then nowhere');
      expect(browser.index, 0);

      await wait(tester);

      expect(find.byType(TasksScreen), findsOneWidget);
      expect(locations(browser), <String>[
        WaxRoute.tasks,
        WaxRoute.notifications,
      ], reason: 'the entry the browser is on, rewritten');
      expect(browser.index, 0);
      await _browserForward(tester, browser);
      expect(find.byType(NotificationsScreen), findsOneWidget);
      await _back(tester);
      expect(find.byType(TasksScreen), findsOneWidget);
      await _back(tester);
      await wait(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(locations(browser), hasLength(2));
    });

    testWidgets('of a pop is made in place, and the entries stay one list '
        'with the visits', (tester) async {
      final (container, browser) = await _pumpTab(tester);
      browser.kept = 2;
      await _go(tester, container, WaxRoute.podcasts);
      final router = _router(container);
      final heard = <Object?>[];
      unawaited(
        router.push<String>(WaxRoute.episode(_episodePid)).then(heard.add),
      );
      await tester.pumpAndSettle();
      await _go(tester, container, WaxRoute.radio);
      await _browserBack(tester, browser);
      expect(find.byType(EpisodeScreen), findsOneWidget);
      expect(browser.index, 0, reason: 'the oldest entry the tab kept');
      unawaited(router.leave(result: 'played'));
      await tester.pumpAndSettle();
      expect(browser.backs, 1, reason: 'which goes nowhere');

      await wait(tester);

      expect(heard, <Object?>['played']);
      expect(find.byType(PodcastsScreen), findsOneWidget);
      expect(locations(browser), <String>[WaxRoute.podcasts, WaxRoute.radio]);
      expect(browser.index, 0);
      await _browserForward(tester, browser);
      expect(find.byType(RadioScreen), findsOneWidget);
      await _back(tester, hub: true);
      expect(find.byType(PodcastsScreen), findsOneWidget);
      expect(find.byType(EpisodeScreen), findsNothing);
    });

    /// A dialog over [over], opened while a step is on its way.
    Future<void> openDialog(WidgetTester tester, Finder over) async {
      unawaited(
        showDialog<void>(
          context: tester.element(over),
          builder: (context) => const AlertDialog(content: Text('Sure?')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sure?'), findsOneWidget);
    }

    testWidgets('of a pop with a dialog opened during the wait closes it, '
        'then pops with its result', (tester) async {
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.podcasts);
      browser.kept = 1;
      final router = _router(container);
      final heard = <Object?>[];
      unawaited(
        router.push<String>(WaxRoute.episode(_episodePid)).then(heard.add),
      );
      await tester.pumpAndSettle();
      var landed = false;
      unawaited(router.leave(result: 'played').then((_) => landed = true));
      await tester.pumpAndSettle();
      await openDialog(tester, find.byType(EpisodeScreen));

      await wait(tester);

      expect(find.text('Sure?'), findsNothing);
      expect(find.byType(EpisodeScreen), findsNothing);
      expect(find.byType(PodcastsScreen), findsOneWidget);
      expect(heard, <Object?>['played']);
      expect(landed, isTrue);
      expect(container.read(waxHistoryProvider)!.stepping, isFalse);
    });

    testWidgets('of a pop with a dialog that will not close waits for it, '
        'then pops with its result', (tester) async {
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.podcasts);
      browser.kept = 1;
      final router = _router(container);
      final heard = <Object?>[];
      unawaited(
        router.push<String>(WaxRoute.episode(_episodePid)).then(heard.add),
      );
      await tester.pumpAndSettle();
      var landed = false;
      unawaited(router.leave(result: 'played').then((_) => landed = true));
      await tester.pumpAndSettle();
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(EpisodeScreen)),
          builder: (context) => const PopScope(
            canPop: false,
            child: AlertDialog(content: Text('Sure?')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await wait(tester);
      expect(find.text('Sure?'), findsOneWidget);
      expect(find.byType(EpisodeScreen), findsOneWidget);
      expect(landed, isFalse, reason: 'the page is still there');
      expect(heard, isEmpty);

      Navigator.of(tester.element(find.text('Sure?'))).pop();
      await wait(tester);

      expect(find.byType(EpisodeScreen), findsNothing);
      expect(find.byType(PodcastsScreen), findsOneWidget);
      expect(heard, <Object?>['played']);
      expect(landed, isTrue);
    });

    testWidgets('of the arrow with a dialog opened during the wait closes '
        'it, then steps to the visit it was after', (tester) async {
      final (container, browser) = await _pumpTab(tester);
      browser.kept = 2;
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.notifications);
      await _go(tester, container, WaxRoute.notifications);
      await _back(tester);
      expect(browser.backs, 2, reason: 'the copy, then nowhere');
      await openDialog(tester, find.byType(NotificationsScreen));

      await wait(tester);

      expect(find.text('Sure?'), findsNothing);
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(_location(container), WaxRoute.tasks);
      expect(container.read(waxHistoryProvider)!.stepping, isFalse);
    });

    testWidgets('of the arrow off a push with a dialog opened during the wait '
        'closes it, then pops the push', (tester) async {
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.podcasts);
      browser.kept = 1;
      final heard = <Object?>[];
      unawaited(
        _router(
          container,
        ).push<String>(WaxRoute.episode(_episodePid)).then(heard.add),
      );
      await tester.pumpAndSettle();
      await _back(tester);
      expect(browser.backs, 1, reason: 'nowhere');
      await openDialog(tester, find.byType(EpisodeScreen));

      await wait(tester);

      expect(find.text('Sure?'), findsNothing);
      expect(find.byType(EpisodeScreen), findsNothing);
      expect(find.byType(PodcastsScreen), findsOneWidget);
      expect(heard, <Object?>[null]);
      expect(container.read(waxHistoryProvider)!.stepping, isFalse);
    });

    testWidgets('of the arrow off a push pops it with the result of a leave '
        'asked during the wait', (tester) async {
      // The leave was that step, so its result goes to the push's opener.
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.podcasts);
      browser.kept = 1;
      final router = _router(container);
      final heard = <Object?>[];
      unawaited(
        router.push<String>(WaxRoute.episode(_episodePid)).then(heard.add),
      );
      await tester.pumpAndSettle();
      await _back(tester);
      expect(browser.backs, 1, reason: 'nowhere');
      var left = false;
      unawaited(router.leave(result: 'played').then((_) => left = true));
      await tester.pumpAndSettle();
      expect(heard, isEmpty);

      await wait(tester);

      expect(find.byType(EpisodeScreen), findsNothing);
      expect(find.byType(PodcastsScreen), findsOneWidget);
      expect(heard, <Object?>['played']);
      expect(left, isTrue);
      expect(browser.backs, 1, reason: 'the leave asked nothing more');
      expect(container.read(waxHistoryProvider)!.stepping, isFalse);
    });

    testWidgets('of the arrow restoring a visit past a push answers its '
        'opener', (tester) async {
      // The show the push was made over is forgotten during the wait, so
      // the step goes on to the hub, and the restore takes the push off.
      final (container, browser) = await _pumpTab(tester);
      await _go(tester, container, WaxRoute.podcasts);
      await _go(tester, container, WaxRoute.show(_showPid));
      browser.kept = 1;
      final heard = <Object?>[];
      unawaited(
        _router(
          container,
        ).push<String>(WaxRoute.episode(_episodePid)).then(heard.add),
      );
      await tester.pumpAndSettle();
      await _back(tester);
      expect(browser.backs, 1, reason: 'nowhere');
      container.read(waxHistoryProvider)!.forget(WaxRoute.show(_showPid));

      await wait(tester);

      expect(find.byType(EpisodeScreen), findsNothing);
      expect(find.byType(ShowScreen), findsNothing);
      expect(find.byType(PodcastsScreen), findsOneWidget);
      expect(_location(container), WaxRoute.podcasts);
      expect(heard, <Object?>[null]);
      expect(container.read(waxHistoryProvider)!.stepping, isFalse);
    });

    testWidgets('lands just before the wait and is handled once', (
      tester,
    ) async {
      // Two forgotten entries, each step of the pass landing a moment
      // before it would be given up.
      final (container, browser) = await _pumpTab(tester);
      for (final location in <String>[
        WaxRoute.tasks,
        WaxRoute.notifications,
        WaxRoute.users,
        WaxRoute.radio,
      ]) {
        await _go(tester, container, location);
      }
      container.read(waxHistoryProvider)!
        ..forget(WaxRoute.notifications)
        ..forget(WaxRoute.users);
      final entries = locations(browser);
      final built = _arrivals(container);
      final late = WaxHistory.unansweredStep - const Duration(milliseconds: 1);
      browser.latency = late;

      browser.goBack();
      await tester.pump();
      await tester.pump(late);
      await tester.pump(late);
      await wait(tester);

      expect(browser.backs, 2);
      expect(built, <String>[WaxRoute.tasks]);
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(locations(browser), entries, reason: 'no entry minted');
    });
  });

  group('after signing out', () {
    // Each entry the session left is answered by the sign-in screen, which
    // go_router would report as one more entry: Back never got past it.
    const screens = <String>[
      WaxRoute.tasks,
      WaxRoute.notifications,
      WaxRoute.radio,
      WaxRoute.podcasts,
      WaxRoute.stats,
      WaxRoute.settings,
    ];

    Future<void> visit(
      WidgetTester tester,
      ProviderContainer container,
      List<String> locations,
    ) async {
      for (final location in locations) {
        await _go(tester, container, location);
      }
    }

    Future<void> signOut(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      await container.read(authControllerProvider.notifier).logout();
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
    }

    Future<void> signIn(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      await container
          .read(authControllerProvider.notifier)
          .login(username: 'admin', password: 'pass');
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsNothing);
    }

    List<String> locations(FakeBrowser browser) => [
      for (final entry in browser.entries) entry.location,
    ];

    testWidgets('browser back leaves the app in one press, past every entry '
        'the session left', (tester) async {
      final (container, browser) = await _pumpTab(tester);
      await visit(tester, container, screens);
      await signOut(tester, container);
      final entries = locations(browser);
      final built = _arrivals(container);

      await _browserBack(tester, browser);

      expect(browser.left, isTrue);
      expect(built, isEmpty, reason: 'nothing the router heard of');
      expect(locations(browser), entries, reason: 'none minted');
      await tester.pump(WaxHistory.unansweredStep);
    });

    testWidgets('browser back leaves the app in one press past an entry of a '
        'record merged into another too', (tester) async {
      const gone = 'ar-01JZX5N8QW3F4V9T2B7KDGONE01';
      const kept = 'ar-01JZX5N8QW3F4V9T2B7KDKEPT01';
      final (container, browser) = await _pumpTab(tester);
      await visit(tester, container, <String>[
        WaxRoute.tasks,
        WaxRoute.musicBucket(MusicDimension.artists, gone),
        WaxRoute.radio,
      ]);
      container
          .read(waxHistoryProvider)!
          .forget(
            WaxRoute.musicBucket(MusicDimension.artists, gone),
            instead: WaxRoute.musicBucket(MusicDimension.artists, kept),
          );
      await signOut(tester, container);
      final entries = locations(browser);
      final built = _arrivals(container);

      await _browserBack(tester, browser);

      expect(browser.left, isTrue);
      expect(built, isEmpty, reason: 'nothing the router heard of');
      expect(locations(browser), entries, reason: 'none minted');
      await tester.pump(WaxHistory.unansweredStep);
    });

    testWidgets('browser back leaves the app past an earlier sign-in entry '
        'too', (tester) async {
      final (container, browser) = await _pumpTab(tester, signedIn: false);
      await signIn(tester, container);
      await visit(tester, container, screens.take(3).toList());
      await signOut(tester, container);
      expect(browser.entries.first.location, startsWith(WaxRoute.login));
      final entries = locations(browser);
      final built = _arrivals(container);

      await _browserBack(tester, browser);

      expect(browser.left, isTrue);
      expect(built, isEmpty);
      expect(locations(browser), entries);
      await tester.pump(WaxHistory.unansweredStep);
    });

    testWidgets('with nothing behind the app, browser back stays on the '
        'sign-in screen and adds no entry, and forward does the same', (
      tester,
    ) async {
      final (container, browser) = await _pumpTab(tester, behind: false);
      await visit(tester, container, screens.take(3).toList());
      await signOut(tester, container);
      final count = browser.entries.length;

      await _browserBack(tester, browser);

      expect(browser.left, isFalse);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(browser.entries, hasLength(count));
      expect(browser.index, 0, reason: 'the oldest entry of the app');
      expect(Uri.parse(browser.location).path, WaxRoute.login);
      expect(container.read(waxHistoryProvider)!.stepping, isFalse);

      await _browserForward(tester, browser);

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(browser.entries, hasLength(count));
      expect(browser.index, count - 1, reason: 'the newest');
      expect(Uri.parse(browser.location).path, WaxRoute.login);
      expect(container.read(waxHistoryProvider)!.stepping, isFalse);
    });

    testWidgets('signed in again, browser back returns into the screens of '
        'the session', (tester) async {
      final (container, browser) = await _pumpTab(tester);
      await visit(tester, container, screens.take(3).toList());
      await signOut(tester, container);
      await signIn(tester, container);
      expect(find.byType(RadioScreen), findsOneWidget);

      await _browserBack(tester, browser);

      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(_location(container), WaxRoute.notifications);
      await _browserBack(tester, browser);
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(browser.left, isFalse);
    });

    // A reload starts the app over on the sign-in entry: nothing it has
    // written since tells the app's entries from those of a page before
    // them, only what it counted when the tab first opened it.
    testWidgets('after a reload, with nothing before the app, browser back '
        'asks the browser for nothing and the address stays the sign-in '
        "screen's", (tester) async {
      final (signedIn, browser) = await _pumpTab(tester, behind: false);
      await signOut(tester, signedIn);
      final (container, _) = await _pumpTab(
        tester,
        signedIn: false,
        reloading: browser,
      );
      expect(find.byType(LoginScreen), findsOneWidget);
      final count = browser.entries.length;

      await _browserBack(tester, browser);

      expect(browser.backs, 0);
      expect(browser.left, isFalse);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(Uri.parse(browser.location).path, WaxRoute.login);
      await tester.pump(WaxHistory.unansweredStep);
      await tester.pumpAndSettle();
      expect(Uri.parse(browser.location).path, WaxRoute.login);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(browser.entries, hasLength(count), reason: 'none minted');
      expect(container.read(waxHistoryProvider)!.stepping, isFalse);
    });

    testWidgets('after a reload, with a page before the app, browser back '
        'leaves it', (tester) async {
      final (signedIn, browser) = await _pumpTab(tester);
      await signOut(tester, signedIn);
      await _pumpTab(tester, signedIn: false, reloading: browser);

      await _browserBack(tester, browser);

      expect(browser.left, isTrue);
      expect(browser.backs, 1);
      await tester.pump(WaxHistory.unansweredStep);
    });
  });

  testWidgets('with no entry of the app behind, the arrow goes the router '
      'way', (tester) async {
    final (container, browser) = await _pumpTab(tester);
    await _go(tester, container, WaxRoute.tasks);
    await _go(tester, container, WaxRoute.notifications);
    browser.stepsBack = false;

    await _back(tester);
    expect(browser.backs, 0);
    expect(find.byType(TasksScreen), findsOneWidget);
    expect(_location(container), WaxRoute.tasks);
  });

  testWidgets('with nowhere recorded, the arrow never steps the browser', (
    tester,
  ) async {
    final (container, browser) = await _pumpTab(
      tester,
      at: WaxRoute.showEpisode(_showPid, _episodePid),
    );

    await _back(tester);
    expect(browser.backs, 0);
    expect(find.byType(ShowScreen), findsOneWidget);
    expect(_location(container), WaxRoute.show(_showPid));
  });

  testWidgets('back to a console section after the role is gone lands on '
      'the refusal', (tester) async {
    final (container, browser) = await _pumpTab(tester);
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
    expect(browser.backs, 1);
    expect(_location(container), WaxRoute.backups);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.adminForbidden),
      findsOneWidget,
    );
  });

  group('a record merged into another', () {
    // Every page of the record is the survivor's from then on, wherever it
    // sits: the list and the tab's entries hold the same pages, one for
    // one, so back and forward walk them in order and mint or drop none.
    const gone = 'ar-01JZX5N8QW3F4V9T2B7KDGONE01';
    const kept = 'ar-01JZX5N8QW3F4V9T2B7KDKEPT01';
    final artists = WaxRoute.musicIndex(MusicDimension.artists);
    final gonePage = WaxRoute.musicBucket(MusicDimension.artists, gone);
    final page = WaxRoute.musicBucket(MusicDimension.artists, kept);
    final editor = WaxRoute.metadata(kept);
    final album = WaxRoute.musicBucket(MusicDimension.albums, _albumPid);
    final authors = WaxRoute.bookIndex(BookDimension.authors);
    final goneAuthor = WaxRoute.bookBucket(BookDimension.authors, gone);
    final author = WaxRoute.bookBucket(BookDimension.authors, kept);
    const home = (WaxRoute.home, <String>[]);

    /// The app with both artists in its library, in a browser tab unless
    /// [native]; [at] opens it cold on a link.
    Future<(ProviderContainer, FakeBrowser?)> tab(
      WidgetTester tester, {
      required bool native,
      String? at,
    }) async {
      final (container, browser) = await _pumpTab(
        tester,
        native: native,
        at: at,
      );
      _repo(container)
        ..facetItems['artist ${kept.substring(3)}'] = [testItem('tr-1')]
        ..facetItems['artist ${gone.substring(3)}'] = [testItem('tr-1')];
      return (container, native ? null : browser);
    }

    /// The artist's editor, as its page's overflow opens it.
    Future<void> edit(WidgetTester tester, ProviderContainer container) async {
      unawaited(_router(container).push<void>(WaxRoute.metadata(gone)));
      await tester.pumpAndSettle();
    }

    /// What the editor on top follows its answer with, read as it asks.
    EditFollow asked(WidgetTester tester) => EditFollow.of(
      tester.element(find.byType(EntityEditorScreen)),
      pid: gone,
    );

    /// The server's answer: the artist went into the other.
    Future<void> answer(
      WidgetTester tester,
      ProviderContainer container,
      EditFollow follow,
    ) async {
      _repo(container).facetItems.remove('artist ${gone.substring(3)}');
      unawaited(follow.merged(kept, said: (l10n) => l10n.commonOpen));
      await tester.pumpAndSettle();
    }

    /// The editor opened over what is on screen, and the merge it asks for.
    Future<void> merge(WidgetTester tester, ProviderContainer container) async {
      await edit(tester, container);
      await answer(tester, container, asked(tester));
    }

    const goneAlbum = 'al-01JZX5N8QW3F4V9T2B7KDGONEA1';
    const keptAlbum = 'al-01JZX5N8QW3F4V9T2B7KDKEPTA1';
    final goneRelease = WaxRoute.musicBucket(MusicDimension.albums, goneAlbum);
    final release = WaxRoute.musicBucket(MusicDimension.albums, keptAlbum);
    final albums = WaxRoute.musicIndex(MusicDimension.albums);

    /// Each artist's release of one title.
    void releases(ProviderContainer container) {
      final repo = _repo(container);
      for (final pid in [goneAlbum, keptAlbum]) {
        repo
          ..albums[pid] = AlbumDetail(pid: pid, title: 'Common Ground')
          ..facetItems['album ${pid.substring(3)}'] = [testItem('tr-1')];
      }
    }

    /// The merge, whose answer says the artist's release folded into the
    /// survivor's, as the server answers when both had one of a title.
    Future<void> mergeFolding(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      await edit(tester, container);
      final follow = asked(tester);
      _repo(container)
        ..facetItems.remove('artist ${gone.substring(3)}')
        ..facetItems.remove('album ${goneAlbum.substring(3)}')
        ..albums.remove(goneAlbum);
      unawaited(
        follow.merged(
          kept,
          said: (l10n) => l10n.commonOpen,
          folded: const [FoldedEntity(pid: goneAlbum, into: keptAlbum)],
        ),
      );
      await tester.pumpAndSettle();
    }

    final ofGoneRelease = find.byWidgetPredicate(
      (widget) => widget is AlbumScreen && widget.pid == goneAlbum,
      skipOffstage: false,
    );

    final ofGone = find.byWidgetPredicate(
      (widget) =>
          (widget is ArtistScreen && widget.pid == gone) ||
          (widget is EntityEditorScreen && widget.pid == gone) ||
          (widget is MusicListingScreen && widget.segment == gone),
      skipOffstage: false,
    );

    /// The author page of the artist merged away, on screen or off.
    final authorOfGone = find.byWidgetPredicate(
      (widget) => widget is BookBucketScreen && widget.segment == gone,
      skipOffstage: false,
    );

    /// The screen is [screen], a location and what is pushed over it, with
    /// no page of the artist merged away anywhere; in a browser the tab is
    /// on entry [index] of [entries], and that entry shows the same. Not
    /// [everywhere] while a branch the visitor left holds a page of it: a
    /// branch's pages are put in place as it is next shown.
    void shows(
      WidgetTester tester,
      ProviderContainer container,
      FakeBrowser? browser,
      (String, List<String>) screen, {
      required int index,
      required int entries,
      bool everywhere = true,
    }) {
      final (location, pushes) = screen;
      expect(tester.takeException(), isNull);
      expect(_location(container), location);
      expect(_pushes(container), pushes);
      if (everywhere) {
        expect(ofGone, findsNothing, reason: 'no page of the artist that went');
      }
      if (browser == null) return;
      expect(browser.index, index, reason: 'the entry the tab is on');
      expect(browser.entries, hasLength(entries), reason: 'none minted');
      expect(browser.location, location, reason: 'the address');
      expect(browser.pushes, pushes, reason: 'what the entry holds');
    }

    /// Walks back from the newest entry to the first, by the arrow where
    /// [arrow] and by the browser's own back otherwise, then in a browser
    /// forward to the newest again. [screens] is what each entry shows,
    /// oldest first. No page of the artist merged away is built on the way.
    Future<void> walk(
      WidgetTester tester,
      ProviderContainer container,
      FakeBrowser? browser,
      List<(String, List<String>)> screens, {
      bool arrow = true,
    }) async {
      final entries = screens.length;
      final built = _arrivals(container);
      final pushed = _pushArrivals(container);
      for (var i = entries - 2; i >= 0; i--) {
        if (arrow || browser == null) {
          await _back(tester, hub: true);
        } else {
          await _browserBack(tester, browser);
        }
        shows(
          tester,
          container,
          browser,
          screens[i],
          index: i,
          entries: entries,
        );
      }
      if (browser != null) {
        for (var i = 1; i < entries; i++) {
          await _browserForward(tester, browser);
          shows(
            tester,
            container,
            browser,
            screens[i],
            index: i,
            entries: entries,
          );
        }
      }
      expect(
        [...built, ...pushed].where((location) => location.contains(gone)),
        isEmpty,
        reason: 'the pages merged away are never built',
      );
    }

    /// Each way back is walked: the arrow natively, and in a browser tab
    /// the arrow and the browser's own back.
    const ways = <(String, {bool native, bool arrow})>[
      ('by the arrow natively', native: true, arrow: true),
      ('by the arrow in a browser tab', native: false, arrow: true),
      ("by the browser's back", native: false, arrow: false),
    ];

    for (final (how, :native, :arrow) in ways) {
      testWidgets('from its editor, opened from its page: back reaches the '
          "survivor's page, then the index, $how", (tester) async {
        final (container, browser) = await tab(tester, native: native);
        await _go(tester, container, artists);
        await _go(tester, container, gonePage);
        await merge(tester, container);
        final screens = [
          home,
          (artists, <String>[]),
          (page, <String>[]),
          (page, [editor]),
        ];
        shows(tester, container, browser, screens.last, index: 3, entries: 4);

        await walk(tester, container, browser, screens, arrow: arrow);
      });

      testWidgets('with a release open over its page and its page open again '
          "over that: every page is walked in order as the survivor's, $how", (
        tester,
      ) async {
        final (container, browser) = await tab(tester, native: native);
        await _go(tester, container, artists);
        await _go(tester, container, gonePage);
        unawaited(_router(container).push<void>(album));
        await tester.pumpAndSettle();
        // As a row's "Go to artist" does.
        unawaited(_router(container).push<void>(gonePage));
        await tester.pumpAndSettle();
        await merge(tester, container);
        final screens = [
          home,
          (artists, <String>[]),
          (page, <String>[]),
          (page, [album]),
          (page, [album, page]),
          (page, [album, page, editor]),
        ];
        shows(tester, container, browser, screens.last, index: 5, entries: 6);

        await walk(tester, container, browser, screens, arrow: arrow);
      });

      testWidgets('with its release open over its page, the release folded '
          "into the survivor's by the merge: every page is walked in order "
          "as the survivor's, the release too, $how", (tester) async {
        final (container, browser) = await tab(tester, native: native);
        releases(container);
        await _go(tester, container, artists);
        await _go(tester, container, gonePage);
        unawaited(_router(container).push<void>(goneRelease));
        await tester.pumpAndSettle();
        // As the release's "Go to artist" does.
        unawaited(_router(container).push<void>(gonePage));
        await tester.pumpAndSettle();
        await mergeFolding(tester, container);
        final built = _arrivals(container);
        final pushed = _pushArrivals(container);
        final screens = [
          home,
          (artists, <String>[]),
          (page, <String>[]),
          (page, [release]),
          (page, [release, page]),
          (page, [release, page, editor]),
        ];
        shows(tester, container, browser, screens.last, index: 5, entries: 6);
        expect(ofGoneRelease, findsNothing);

        await walk(tester, container, browser, screens, arrow: arrow);
        expect(ofGoneRelease, findsNothing);
        expect(
          [...built, ...pushed].where((at) => at.contains(goneAlbum)),
          isEmpty,
          reason: 'the release folded away is never built',
        );
      });

      testWidgets('with the release opened from the albums index and the '
          "artist from it, the release folded into the survivor's: back "
          "reaches the survivor's release, $how", (tester) async {
        final (container, browser) = await tab(tester, native: native);
        releases(container);
        await _go(tester, container, albums);
        await _go(tester, container, goneRelease);
        unawaited(_router(container).push<void>(gonePage));
        await tester.pumpAndSettle();
        await mergeFolding(tester, container);
        final built = _arrivals(container);
        final pushed = _pushArrivals(container);
        final screens = [
          home,
          (albums, <String>[]),
          (release, <String>[]),
          (release, [page]),
          (release, [page, editor]),
        ];
        shows(tester, container, browser, screens.last, index: 4, entries: 5);

        await walk(tester, container, browser, screens, arrow: arrow);
        expect(ofGoneRelease, findsNothing);
        expect(
          [...built, ...pushed].where((at) => at.contains(goneAlbum)),
          isEmpty,
          reason: 'the release folded away is never built',
        );
      });

      testWidgets('with its page opened from a search hit: back from the '
          "survivor's editor reaches the survivor's page, $how", (
        tester,
      ) async {
        final (container, browser) = await tab(tester, native: native);
        await _go(tester, container, WaxRoute.search);
        // As the hit does, with the name it had.
        unawaited(_router(container).push<void>(gonePage, extra: 'Old'));
        await tester.pumpAndSettle();
        await merge(tester, container);
        final screens = [
          home,
          (WaxRoute.search, <String>[]),
          (WaxRoute.search, [page]),
          (WaxRoute.search, [page, editor]),
        ];
        shows(tester, container, browser, screens.last, index: 3, entries: 4);

        await walk(tester, container, browser, screens, arrow: arrow);
        if (browser == null) return;
        await _browserBack(tester, browser);
        expect(
          tester.widget<ArtistScreen>(find.byType(ArtistScreen)).pid,
          kept,
        );
      });

      testWidgets('with its page opened from a health fold, which waits for '
          "it: back reaches the survivor's page, and the fold hears once that "
          'is left, $how', (tester) async {
        final (container, browser) = await tab(tester, native: native);
        await _go(tester, container, WaxRoute.health);
        // As the fold does.
        var heard = 0;
        unawaited(
          _router(
            container,
          ).push<void>(gonePage, extra: 'Old').then((_) => heard++),
        );
        await tester.pumpAndSettle();
        await merge(tester, container);
        final screens = [
          home,
          (WaxRoute.health, <String>[]),
          (WaxRoute.health, [page]),
          (WaxRoute.health, [page, editor]),
        ];
        shows(tester, container, browser, screens.last, index: 3, entries: 4);
        expect(heard, 0, reason: 'its page is still open, as the survivor');

        Future<void> back() => arrow || browser == null
            ? _back(tester, hub: true)
            : _browserBack(tester, browser);
        await back();
        shows(tester, container, browser, screens[2], index: 2, entries: 4);
        expect(heard, 0);
        await back();
        shows(tester, container, browser, screens[1], index: 1, entries: 4);
        expect(heard, 1, reason: 'left, and the fold reads its list again');
      });

      testWidgets('with its author page in a visit behind, and its own page '
          "opened from a search hit: back reaches the survivor's author page, "
          '$how', (tester) async {
        final (container, browser) = await tab(tester, native: native);
        await _go(tester, container, WaxRoute.books);
        await _go(tester, container, authors);
        await _go(tester, container, goneAuthor);
        await _go(tester, container, WaxRoute.search);
        // As the hit does, with the name it had.
        unawaited(_router(container).push<void>(gonePage, extra: 'Old'));
        await tester.pumpAndSettle();
        await merge(tester, container);
        final screens = [
          home,
          (WaxRoute.books, <String>[]),
          (authors, <String>[]),
          (author, <String>[]),
          (WaxRoute.search, <String>[]),
          (WaxRoute.search, [page]),
          (WaxRoute.search, [page, editor]),
        ];
        shows(tester, container, browser, screens.last, index: 6, entries: 7);

        await walk(tester, container, browser, screens, arrow: arrow);
        expect(authorOfGone, findsNothing);
        if (browser == null) return;
        for (var i = 0; i < 3; i++) {
          await _browserBack(tester, browser);
        }
        shows(tester, container, browser, screens[3], index: 3, entries: 7);
        expect(
          tester
              .widget<BookBucketScreen>(find.byType(BookBucketScreen))
              .segment,
          kept,
        );
      });
    }

    for (final native in [true, false]) {
      testWidgets('with its author page the last visit of a tab the visitor '
          "left: a tap on that tab shows the survivor's author "
          "page${native ? ', natively' : ''}", (tester) async {
        final (container, browser) = await tab(tester, native: native);
        await _go(tester, container, WaxRoute.books);
        await _go(tester, container, authors);
        await _go(tester, container, goneAuthor);
        await _go(tester, container, WaxRoute.search);
        unawaited(_router(container).push<void>(gonePage, extra: 'Old'));
        await tester.pumpAndSettle();
        await merge(tester, container);
        final built = _arrivals(container);

        await _tapNav(tester, WaxNavTarget.books);
        shows(tester, container, browser, (author, []), index: 7, entries: 8);
        expect(
          tester
              .widget<BookBucketScreen>(find.byType(BookBucketScreen))
              .segment,
          kept,
        );
        expect(authorOfGone, findsNothing);
        expect(built.where((location) => location.contains(gone)), isEmpty);
      });
    }

    testWidgets('once the asker went back before the answer: forward reaches '
        "the survivor's page and editor, entry for entry", (tester) async {
      final (container, browser) = await tab(tester, native: false);
      await _go(tester, container, artists);
      await _go(tester, container, gonePage);
      await edit(tester, container);
      final follow = asked(tester);
      await _browserBack(tester, browser!);
      await _browserBack(tester, browser);
      expect(_location(container), artists);

      await answer(tester, container, follow);
      final screens = [
        home,
        (artists, <String>[]),
        (page, <String>[]),
        (page, [editor]),
      ];
      shows(tester, container, browser, screens[1], index: 1, entries: 4);
      final built = _arrivals(container);
      final pushed = _pushArrivals(container);

      for (final i in [2, 3]) {
        await _browserForward(tester, browser);
        shows(tester, container, browser, screens[i], index: i, entries: 4);
      }
      expect(
        tester.widget<EntityEditorScreen>(find.byType(EntityEditorScreen)).pid,
        kept,
      );
      for (final i in [2, 1, 0, 1, 2, 3]) {
        if (browser.index > i) {
          await _browserBack(tester, browser);
        } else {
          await _browserForward(tester, browser);
        }
        shows(tester, container, browser, screens[i], index: i, entries: 4);
      }
      expect(
        [...built, ...pushed].where((location) => location.contains(gone)),
        isEmpty,
      );
    });

    for (final arrow in [true, false]) {
      testWidgets("with the survivor's page already under its own: the two "
          'are one page, shown once on the way back and once on the way '
          "forward, by ${arrow ? 'the arrow' : "the browser's back"}", (
        tester,
      ) async {
        final (container, browser) = await tab(tester, native: false);
        await _go(tester, container, artists);
        // As the index's row does, with its label.
        _router(container).go(page, extra: 'Kept');
        await tester.pumpAndSettle();
        // As a row's "Go to artist" does.
        unawaited(_router(container).push<void>(gonePage));
        await tester.pumpAndSettle();
        await merge(tester, container);
        // Entries: home, the index, the survivor's page, that with the
        // page merged away over it, and the survivor's editor.
        shows(
          tester,
          container,
          browser,
          (page, [editor]),
          index: 4,
          entries: 5,
        );
        Future<void> back() =>
            arrow ? _back(tester, hub: true) : _browserBack(tester, browser!);

        await back();
        shows(tester, container, browser, (page, []), index: 3, entries: 5);
        await back();
        shows(tester, container, browser, (artists, []), index: 1, entries: 5);
        await back();
        shows(tester, container, browser, home, index: 0, entries: 5);

        await _browserForward(tester, browser!);
        shows(tester, container, browser, (artists, []), index: 1, entries: 5);
        await _browserForward(tester, browser);
        shows(tester, container, browser, (page, []), index: 2, entries: 5);
        await _browserForward(tester, browser);
        shows(
          tester,
          container,
          browser,
          (page, [editor]),
          index: 4,
          entries: 5,
        );
      });
    }

    testWidgets('a second record merged into the same survivor: each keeps '
        "its place in the tab as the survivor's", (tester) async {
      const other = 'ar-01JZX5N8QW3F4V9T2B7KDGONE02';
      final otherPage = WaxRoute.musicBucket(MusicDimension.artists, other);
      final (container, browser) = await tab(tester, native: false);
      _repo(container).facetItems['artist ${other.substring(3)}'] = [
        testItem('tr-1'),
      ];
      await _go(tester, container, artists);
      await _go(tester, container, gonePage);
      await merge(tester, container);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, otherPage);
      unawaited(_router(container).push<void>(WaxRoute.metadata(other)));
      await tester.pumpAndSettle();
      final follow = EditFollow.of(
        tester.element(find.byType(EntityEditorScreen)),
        pid: other,
      );
      unawaited(follow.merged(kept, said: (l10n) => l10n.commonOpen));
      await tester.pumpAndSettle();
      final screens = [
        home,
        (artists, <String>[]),
        (page, <String>[]),
        (page, [editor]),
        (WaxRoute.tasks, <String>[]),
        (page, <String>[]),
        (page, [editor]),
      ];
      shows(tester, container, browser, screens.last, index: 6, entries: 7);

      await walk(tester, container, browser, screens, arrow: false);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is ArtistScreen && widget.pid == other,
          skipOffstage: false,
        ),
        findsNothing,
      );
    });

    testWidgets('a link to its tracks, with a scope: back reaches the '
        "survivor's location with the same query, written over that entry", (
      tester,
    ) async {
      const scope = '${WaxRoute.scopeParam}=${WaxRoute.wholeLibraryScope}';
      final (container, browser) = await tab(
        tester,
        native: false,
        at: '${WaxRoute.artistTracks(gone)}?$scope',
      );
      // By its link, as the player's "Edit metadata" opens an editor.
      await _go(tester, container, WaxRoute.metadata(gone));
      await answer(tester, container, asked(tester));
      final tracks = ('${WaxRoute.artistTracks(kept)}?$scope', <String>[]);
      // The music branch, off screen, holds its pages until it is shown.
      shows(
        tester,
        container,
        browser,
        (editor, []),
        index: 1,
        entries: 2,
        everywhere: false,
      );
      final built = _arrivals(container);

      await _back(tester);
      shows(tester, container, browser, tracks, index: 0, entries: 2);
      final listing = tester.widget<MusicListingScreen>(
        find.byType(MusicListingScreen),
      );
      expect(listing.segment, kept);
      // An artist's tracks list music whatever the scope in the link says.
      expect(listing.domain, BrowseDomain.music);
      expect(built.where((location) => location.contains(gone)), isEmpty);

      await _browserForward(tester, browser!);
      shows(tester, container, browser, (editor, []), index: 1, entries: 2);
      await _browserBack(tester, browser);
      shows(tester, container, browser, tracks, index: 0, entries: 2);
    });

    for (final native in [true, false]) {
      testWidgets('with its pages in the stack of a tab the visitor left: a '
          'tap on that tab and back to it show the same, the '
          "survivor's${native ? ', natively' : ''}", (tester) async {
        final (container, browser) = await tab(tester, native: native);
        await _go(tester, container, artists);
        await _go(tester, container, gonePage);
        await edit(tester, container);
        final follow = asked(tester);
        await _tapNav(tester, WaxNavTarget.podcasts);
        await answer(tester, container, follow);
        expect(find.byType(PodcastsScreen), findsOneWidget);

        await _tapNav(tester, WaxNavTarget.music);
        shows(
          tester,
          container,
          browser,
          (page, [editor]),
          index: 5,
          entries: 6,
        );
        expect(
          tester
              .widget<EntityEditorScreen>(find.byType(EntityEditorScreen))
              .pid,
          kept,
        );

        Future<void> back() => browser == null
            ? _back(tester, hub: true)
            : _browserBack(tester, browser);
        await back();
        expect(find.byType(PodcastsScreen), findsOneWidget);
        await back();
        shows(
          tester,
          container,
          browser,
          (page, [editor]),
          index: 3,
          entries: 6,
        );
        await back();
        shows(tester, container, browser, (page, []), index: 2, entries: 6);
        await back();
        shows(tester, container, browser, (artists, []), index: 1, entries: 6);
      });
    }

    for (final native in [true, false]) {
      testWidgets("with the survivor's page open over its own as the answer "
          'lands: that page stays up, and nothing lies on itself under '
          "it${native ? ', natively' : ''}", (tester) async {
        final (container, browser) = await tab(tester, native: native);
        await _go(tester, container, artists);
        await _go(tester, container, gonePage);
        await edit(tester, container);
        final follow = asked(tester);
        await _back(tester);
        // As a row's "Go to artist" does, for a track that credits both.
        unawaited(_router(container).push<void>(page));
        await tester.pumpAndSettle();
        final shown = tester.element(find.byType(ArtistScreen));

        await answer(tester, container, follow);
        // Its own page under the one on top gave way to the index.
        shows(
          tester,
          container,
          browser,
          (artists, [page]),
          index: 3,
          entries: 4,
        );
        expect(
          tester.element(find.byType(ArtistScreen)),
          same(shown),
          reason: 'the page on top stays as it is',
        );

        await _back(tester);
        shows(tester, container, browser, (page, []), index: 2, entries: 4);
        await _back(tester);
        shows(tester, container, browser, (artists, []), index: 1, entries: 4);
      });
    }

    testWidgets('with a copy of the survivor cut in the stack of a tab the '
        'visitor left: the tab comes back without it, and so does back', (
      tester,
    ) async {
      final (container, browser) = await tab(tester, native: false);
      await _go(tester, container, artists);
      _router(container).go(page, extra: 'Kept');
      await tester.pumpAndSettle();
      unawaited(_router(container).push<void>(gonePage));
      await tester.pumpAndSettle();
      await edit(tester, container);
      final follow = asked(tester);
      await _tapNav(tester, WaxNavTarget.podcasts);
      await answer(tester, container, follow);

      await _tapNav(tester, WaxNavTarget.music);
      shows(tester, container, browser, (page, [editor]), index: 6, entries: 7);

      await _browserBack(tester, browser!);
      expect(find.byType(PodcastsScreen), findsOneWidget);
      await _browserBack(tester, browser);
      shows(tester, container, browser, (page, [editor]), index: 4, entries: 7);
      await _browserBack(tester, browser);
      shows(tester, container, browser, (page, []), index: 3, entries: 7);
      await _browserBack(tester, browser);
      shows(tester, container, browser, (artists, []), index: 1, entries: 7);
    });

    testWidgets('a browser back and a forward again before a frame has drawn '
        'either end where they began, each entry its own page', (tester) async {
      final (container, browser) = await tab(tester, native: false);
      await _go(tester, container, artists);
      await _go(tester, container, gonePage);
      unawaited(_router(container).push<void>(album));
      await tester.pumpAndSettle();
      await edit(tester, container);
      final follow = asked(tester);
      await _browserBack(tester, browser!);
      await _browserBack(tester, browser);
      await _browserBack(tester, browser);
      await answer(tester, container, follow);
      final screens = [
        home,
        (artists, <String>[]),
        (page, <String>[]),
        (page, [album]),
        (page, [album, editor]),
      ];
      shows(tester, container, browser, screens[1], index: 1, entries: 5);

      browser
        ..goForward()
        ..goForward()
        ..goBack();
      await tester.pumpAndSettle();
      shows(tester, container, browser, screens[2], index: 2, entries: 5);
      browser
        ..goForward()
        ..goForward();
      await tester.pumpAndSettle();
      shows(tester, container, browser, screens[4], index: 4, entries: 5);
      await _back(tester);
      shows(tester, container, browser, screens[3], index: 3, entries: 5);
    });

    testWidgets('a jump of two entries onto an entry of it shows the '
        "survivor's page there, and the list starts over", (tester) async {
      final (container, browser) = await tab(tester, native: false);
      await _go(tester, container, artists);
      await _go(tester, container, gonePage);
      await edit(tester, container);
      final follow = asked(tester);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.radio);
      await answer(tester, container, follow);
      final built = _arrivals(container);

      browser!.jump(-2);
      await tester.pumpAndSettle();

      shows(tester, container, browser, (page, [editor]), index: 3, entries: 6);
      expect(built.where((location) => location.contains(gone)), isEmpty);
      await _browserBack(tester, browser);
      shows(tester, container, browser, (page, []), index: 2, entries: 6);
    });

    testWidgets('an entry the list forgot is still passed once a record '
        'became another', (tester) async {
      final (container, browser) = await tab(tester, native: false);
      await _go(tester, container, artists);
      await _go(tester, container, gonePage);
      await merge(tester, container);
      await _go(tester, container, WaxRoute.notifications);
      await _go(tester, container, WaxRoute.radio);
      container.read(waxHistoryProvider)!.forget(WaxRoute.notifications);
      final built = _arrivals(container);

      await _browserBack(tester, browser!);

      shows(tester, container, browser, (page, [editor]), index: 3, entries: 6);
      expect(built, isNot(contains(WaxRoute.notifications)));
    });

    testWidgets('a browser forward onto an entry of it lands on the visit '
        'ahead, not on the same page behind', (tester) async {
      final (container, browser) = await tab(tester, native: false);
      await _go(tester, container, gonePage);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, gonePage);
      await _browserBack(tester, browser!);
      expect(find.byType(TasksScreen), findsOneWidget);
      // As the merge's follow tells the history, the asker gone.
      container.read(waxHistoryProvider)!.forget(gonePage, instead: page);

      await _browserForward(tester, browser);
      shows(tester, container, browser, (page, []), index: 3, entries: 4);

      await _back(tester);
      shows(
        tester,
        container,
        browser,
        (WaxRoute.tasks, []),
        index: 2,
        entries: 4,
      );
      await _back(tester);
      shows(tester, container, browser, (page, []), index: 1, entries: 4);
    });

    testWidgets('a pop its own move overtakes lands on the entry of its page, '
        "which back then shows as the survivor's", (tester) async {
      final (container, browser) = await tab(tester, native: false);
      await _go(tester, container, artists);
      await _go(tester, container, gonePage);
      await merge(tester, container);
      final router = _router(container);
      browser!.latency = const Duration(milliseconds: 100);
      unawaited(router.leave());
      await tester.pump(const Duration(milliseconds: 1));
      final history = container.read(waxHistoryProvider)!;
      expect(history.stepping, isTrue, reason: 'the pop is on its way');

      router.go(WaxRoute.tasks);
      await tester.pump();
      await tester.pumpAndSettle();
      browser.latency = null;

      expect(history.stepping, isFalse);
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(browser.index, 3, reason: 'past the entry the pop landed on');
      expect(browser.entries, hasLength(4));
      await _browserBack(tester, browser);
      shows(tester, container, browser, (page, []), index: 2, entries: 4);
      await _browserBack(tester, browser);
      shows(tester, container, browser, (artists, []), index: 1, entries: 4);
    });

    testWidgets('the arrow back from the editor answers whoever waits for '
        'it, in a browser tab as natively', (tester) async {
      final (container, browser) = await tab(tester, native: false);
      await _go(tester, container, artists);
      await _go(tester, container, gonePage);
      await merge(tester, container);
      final awaited = container.read(waxHistoryProvider)!.heldAwaiters;
      expect(awaited, isNotEmpty);

      await _back(tester);
      shows(tester, container, browser, (page, []), index: 2, entries: 4);
      expect(
        awaited.every((completer) => completer.isCompleted),
        isTrue,
        reason: 'the editor it took off is answered',
      );
    });

    testWidgets('a second browser back before a frame has drawn the first '
        'leaves each entry its own page', (tester) async {
      final (container, browser) = await tab(tester, native: false);
      await _go(tester, container, artists);
      await _go(tester, container, gonePage);
      unawaited(_router(container).push<void>(album));
      await tester.pumpAndSettle();
      unawaited(_router(container).push<void>(gonePage));
      await tester.pumpAndSettle();
      await merge(tester, container);
      final screens = [
        home,
        (artists, <String>[]),
        (page, <String>[]),
        (page, [album]),
        (page, [album, page]),
        (page, [album, page, editor]),
      ];

      browser!
        ..goBack()
        ..goBack();
      await tester.pumpAndSettle();
      shows(tester, container, browser, screens[3], index: 3, entries: 6);
      expect(
        browser.pushesAt(4),
        hasLength(2),
        reason: 'the entry passed through kept its own two pages',
      );

      await _browserForward(tester, browser);
      shows(tester, container, browser, screens[4], index: 4, entries: 6);
      browser
        ..goBack()
        ..goBack();
      await tester.pumpAndSettle();
      shows(tester, container, browser, screens[2], index: 2, entries: 6);
      await _browserForward(tester, browser);
      shows(tester, container, browser, screens[3], index: 3, entries: 6);
      await _browserForward(tester, browser);
      shows(tester, container, browser, screens[4], index: 4, entries: 6);
      await _browserForward(tester, browser);
      shows(tester, container, browser, screens[5], index: 5, entries: 6);
    });

    /// Each entry of the tab, oldest first: its location and what is pushed
    /// over it.
    List<String> entriesOf(FakeBrowser browser) => [
      for (final (i, entry) in browser.entries.indexed)
        [entry.location, ...browser.pushesAt(i)].join(' + '),
    ];

    /// [shows], with every entry of the tab as [tab] says, oldest first.
    void showsTab(
      WidgetTester tester,
      ProviderContainer container,
      FakeBrowser browser,
      (String, List<String>) screen, {
      required int index,
      required List<String> tab,
      bool everywhere = true,
    }) {
      shows(
        tester,
        container,
        browser,
        screen,
        index: index,
        entries: tab.length,
        everywhere: everywhere,
      );
      expect(entriesOf(browser), tab, reason: 'every entry of the tab');
    }

    /// No arrival in [built] is at a page of one of [pids].
    void neverBuilt(List<String> built, List<String> pids) => expect(
      built.where((location) => pids.any(location.contains)),
      isEmpty,
      reason: 'never built',
    );

    testWidgets('the survivor deleted since: the browser passes its entries '
        "and the record's, as it passes any forgotten one", (tester) async {
      final (container, opened) = await tab(tester, native: false);
      final browser = opened!;
      await _go(tester, container, artists);
      await _go(tester, container, gonePage);
      await merge(tester, container);
      await _go(tester, container, WaxRoute.tasks);
      await _go(tester, container, WaxRoute.radio);
      // As a delete of the survivor forgets its pages.
      container.read(waxHistoryProvider)!
        ..forget(page)
        ..forget(editor);
      _repo(container).facetItems.remove('artist ${kept.substring(3)}');
      // None is written over: the two between are passed each way.
      final entries = [
        WaxRoute.home,
        artists,
        gonePage,
        '$page + $editor',
        WaxRoute.tasks,
        WaxRoute.radio,
      ];
      expect(entriesOf(browser), entries);
      final arrived = _arrivals(container);
      final pushed = _pushArrivals(container);
      const tasks = (WaxRoute.tasks, <String>[]);

      await _browserBack(tester, browser);
      showsTab(tester, container, browser, tasks, index: 4, tab: entries);
      await _browserBack(tester, browser);
      showsTab(
        tester,
        container,
        browser,
        (artists, []),
        index: 1,
        tab: entries,
      );
      expect(find.byType(ArtistScreen, skipOffstage: false), findsNothing);

      await _browserForward(tester, browser);
      showsTab(tester, container, browser, tasks, index: 4, tab: entries);
      neverBuilt([...arrived, ...pushed], [gone, kept]);
    });

    testWidgets('a release deleted since, open over its page: the browser '
        "passes that entry and lands on the page's own as the survivor's", (
      tester,
    ) async {
      final (container, opened) = await tab(tester, native: false);
      final browser = opened!;
      await _go(tester, container, artists);
      await _go(tester, container, gonePage);
      unawaited(_router(container).push<void>(album));
      await tester.pumpAndSettle();
      await _go(tester, container, WaxRoute.tasks);
      // As the merge's follow tells the history, the asker gone, and then
      // as the release's delete forgets its pages.
      _repo(container).facetItems.remove('artist ${gone.substring(3)}');
      container.read(waxHistoryProvider)!
        ..forget(gonePage, instead: page)
        ..forget(WaxRoute.metadata(gone), instead: editor)
        ..forget(album)
        ..forget(WaxRoute.metadata(_albumPid));
      final arrived = _arrivals(container);
      final pushed = _pushArrivals(container);
      // The one passed is as it was; the page's own is written as it is
      // landed on.
      final entries = [
        WaxRoute.home,
        artists,
        page,
        '$gonePage + $album',
        WaxRoute.tasks,
      ];
      const tasks = (WaxRoute.tasks, <String>[]);

      await _browserBack(tester, browser);
      showsTab(tester, container, browser, (page, []), index: 2, tab: entries);
      expect(find.byType(AlbumScreen, skipOffstage: false), findsNothing);
      await _browserBack(tester, browser);
      showsTab(
        tester,
        container,
        browser,
        (artists, []),
        index: 1,
        tab: entries,
      );

      await _browserForward(tester, browser);
      showsTab(tester, container, browser, (page, []), index: 2, tab: entries);
      await _browserForward(tester, browser);
      showsTab(tester, container, browser, tasks, index: 4, tab: entries);
      neverBuilt([...arrived, ...pushed], [gone, _albumPid]);
    });

    // Its own entry is its visit's, landed on. One whose top page was done
    // with since is forgotten, and at the app's oldest is stood in for.
    testWidgets("a browser back onto the app's oldest entry, its page with a "
        'release open over it that was deleted since: what the page became '
        'stands in, written over that entry, not the index it is declared '
        'beneath', (tester) async {
      final (container, opened) = await tab(tester, native: false);
      final browser = opened!;
      await _go(tester, container, artists);
      await _go(tester, container, gonePage);
      unawaited(_router(container).push<void>(album));
      await tester.pumpAndSettle();
      await _go(tester, container, WaxRoute.tasks);
      // As the merge's follow tells the history, the asker gone, and then
      // as the release's delete forgets its pages.
      _repo(container).facetItems.remove('artist ${gone.substring(3)}');
      container.read(waxHistoryProvider)!
        ..forget(gonePage, instead: page)
        ..forget(WaxRoute.metadata(gone), instead: editor)
        ..forget(album)
        ..forget(WaxRoute.metadata(_albumPid));
      final arrived = _arrivals(container);
      final pushed = _pushArrivals(container);
      // A tab that kept nothing behind the release's entry.
      browser.stepsBack = false;

      await _browserBack(tester, browser);
      showsTab(
        tester,
        container,
        browser,
        (page, []),
        index: 3,
        tab: [WaxRoute.home, artists, gonePage, page, WaxRoute.tasks],
      );
      expect(find.byType(AlbumScreen, skipOffstage: false), findsNothing);
      neverBuilt([...arrived, ...pushed], [gone, _albumPid]);
    });

    testWidgets('a pop its own move overtakes passes the entry of its page '
        'once the survivor was deleted, as a forgotten one', (tester) async {
      final (container, opened) = await tab(tester, native: false);
      final browser = opened!;
      await _go(tester, container, artists);
      await _go(tester, container, gonePage);
      await edit(tester, container);
      final follow = asked(tester);
      await _back(tester);
      unawaited(_router(container).push<void>(album));
      await tester.pumpAndSettle();
      await answer(tester, container, follow);
      showsTab(
        tester,
        container,
        browser,
        (page, [album]),
        index: 3,
        tab: [WaxRoute.home, artists, gonePage, '$page + $album'],
      );
      // As a delete of the survivor that lands with the release open over
      // its page.
      final history = container.read(waxHistoryProvider)!
        ..takeOutFromUnder((location, _) => Uri.parse(location).path == page)
        ..forget(page)
        ..forget(editor);
      await tester.pumpAndSettle();
      showsTab(
        tester,
        container,
        browser,
        (artists, [album]),
        index: 3,
        tab: [WaxRoute.home, artists, gonePage, '$artists + $album'],
      );

      final router = _router(container);
      browser.latency = const Duration(milliseconds: 100);
      unawaited(router.leave());
      await tester.pump(const Duration(milliseconds: 1));
      expect(history.stepping, isTrue, reason: 'the pop is on its way');
      router.go(WaxRoute.tasks);
      await tester.pump();
      await tester.pumpAndSettle();
      browser.latency = null;

      expect(history.stepping, isFalse);
      // The move is written past the index: the record's entry went with
      // the page the pop closed.
      final entries = [WaxRoute.home, artists, WaxRoute.tasks];
      showsTab(
        tester,
        container,
        browser,
        (WaxRoute.tasks, []),
        index: 2,
        tab: entries,
      );
      await _browserBack(tester, browser);
      showsTab(
        tester,
        container,
        browser,
        (artists, []),
        index: 1,
        tab: entries,
      );
    });

    for (final (how, :native, :arrow) in ways) {
      testWidgets('once the survivor went into another in turn: back reaches '
          "the last survivor's page on the record's entry, $how", (
        tester,
      ) async {
        const last = 'ar-01JZX5N8QW3F4V9T2B7KDKEPT02';
        final lastPage = WaxRoute.musicBucket(MusicDimension.artists, last);
        final lastEditor = WaxRoute.metadata(last);
        final (container, browser) = await tab(tester, native: native);
        _repo(container).facetItems['artist ${last.substring(3)}'] = [
          testItem('tr-1'),
        ];
        await _go(tester, container, artists);
        await _go(tester, container, gonePage);
        await merge(tester, container);
        // The survivor's editor, on top, asks in turn.
        final follow = EditFollow.of(
          tester.element(find.byType(EntityEditorScreen)),
          pid: kept,
        );
        _repo(container).facetItems.remove('artist ${kept.substring(3)}');
        unawaited(follow.merged(last, said: (l10n) => l10n.commonOpen));
        await tester.pumpAndSettle();
        final screens = [
          home,
          (artists, <String>[]),
          (lastPage, <String>[]),
          (lastPage, [lastEditor]),
        ];
        shows(tester, container, browser, screens.last, index: 3, entries: 4);
        if (browser != null) {
          expect(entriesOf(browser), [
            WaxRoute.home,
            artists,
            gonePage,
            '$lastPage + $lastEditor',
          ], reason: "the record's entry, not landed on since");
        }
        final arrived = _arrivals(container);
        final pushed = _pushArrivals(container);

        await walk(tester, container, browser, screens, arrow: arrow);
        neverBuilt([...arrived, ...pushed], [kept]);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                (widget is ArtistScreen && widget.pid == kept) ||
                (widget is EntityEditorScreen && widget.pid == kept),
            skipOffstage: false,
          ),
          findsNothing,
        );
        if (browser != null) {
          expect(entriesOf(browser), [
            WaxRoute.home,
            artists,
            lastPage,
            '$lastPage + $lastEditor',
          ], reason: "written as the last survivor's");
        }
      });
    }

    // The visitor's own back or forward, made from the entry the app's move
    // was made on before a frame drew it. Onto an entry of the record it
    // does what it does onto any other: one body, both entries.
    for (final merged in <bool>[true, false]) {
      final own = merged ? kept : gone;
      final ownPage = WaxRoute.musicBucket(MusicDimension.artists, own);
      final ownEditor = WaxRoute.metadata(own);
      final onto = merged
          ? 'an entry of the record'
          : 'an entry of an artist not merged, for comparison';

      for (final push in <bool>[false, true]) {
        testWidgets("the browser's back in the frame of "
            '${push ? 'a push' : 'a go'}, onto $onto: the move goes '
            'unwritten, no entry is lost and the list keeps its place', (
          tester,
        ) async {
          final (container, opened) = await tab(tester, native: false);
          final browser = opened!;
          await _go(tester, container, artists);
          await _go(tester, container, gonePage);
          if (merged) {
            await merge(tester, container);
          } else {
            await edit(tester, container);
          }
          final history = container.read(waxHistoryProvider)!;
          final router = _router(container);
          final heard = <Object?>[];
          final arrived = _arrivals(container);
          // The move is never written, and no entry minted or lost.
          final entries = [
            WaxRoute.home,
            artists,
            ownPage,
            '$ownPage + $ownEditor',
          ];
          void at((String, List<String>) screen, int index) => showsTab(
            tester,
            container,
            browser,
            screen,
            index: index,
            tab: entries,
            everywhere: merged,
          );

          if (push) {
            unawaited(router.push<String>(album).then(heard.add));
          } else {
            router.go(WaxRoute.uploads);
          }
          browser.goBack();
          await tester.pump(Duration.zero);
          await tester.pumpAndSettle();

          expect(history.stepping, isFalse);
          at((ownPage, []), 2);
          expect(heard, push ? <Object?>[null] : isEmpty);
          expect(history.canGoBack, isTrue, reason: 'the list kept its place');
          final backs = browser.backs;
          await _back(tester, hub: true);
          expect(browser.backs, backs + 1, reason: 'through the browser');
          at((artists, []), 1);

          await _browserForward(tester, browser);
          at((ownPage, []), 2);
          await _browserForward(tester, browser);
          at((ownPage, [ownEditor]), 3);
          if (merged) neverBuilt(arrived, [gone]);
        });
      }

      testWidgets("the browser's forward in the frame of a go, onto $onto: "
          'the go goes unwritten, no entry is lost and the list keeps the '
          'visits the go took the place of', (tester) async {
        final (container, opened) = await tab(tester, native: false);
        final browser = opened!;
        await _go(tester, container, artists);
        await _go(tester, container, gonePage);
        await edit(tester, container);
        final follow = asked(tester);
        await _browserBack(tester, browser);
        await _browserBack(tester, browser);
        if (merged) await answer(tester, container, follow);
        final history = container.read(waxHistoryProvider)!;
        final arrived = _arrivals(container);
        // Neither entry ahead has been landed on since.
        final ahead = '$gonePage + ${WaxRoute.metadata(gone)}';
        expect(entriesOf(browser), [WaxRoute.home, artists, gonePage, ahead]);
        void at(
          (String, List<String>) screen,
          int index, {
          required String newest,
        }) => showsTab(
          tester,
          container,
          browser,
          screen,
          index: index,
          tab: [WaxRoute.home, artists, ownPage, newest],
          everywhere: merged,
        );

        _router(container).go(WaxRoute.uploads);
        browser.goForward();
        await tester.pump(Duration.zero);
        await tester.pumpAndSettle();

        expect(history.stepping, isFalse);
        at((ownPage, []), 2, newest: ahead);
        expect(history.canGoBack, isTrue, reason: 'the list kept its place');

        final newest = '$ownPage + $ownEditor';
        await _browserForward(tester, browser);
        at((ownPage, [ownEditor]), 3, newest: newest);
        final backs = browser.backs;
        await _back(tester, hub: true);
        at((ownPage, []), 2, newest: newest);
        await _back(tester, hub: true);
        at((artists, []), 1, newest: newest);
        expect(browser.backs, backs + 2, reason: 'through the browser');
        if (merged) neverBuilt(arrived, [gone]);
      });
    }

    for (final together in <bool>[true, false]) {
      testWidgets('two browser backs '
          '${together ? 'before a frame has drawn the first' : 'a frame apart'}'
          ", the second onto the app's oldest entry, forgotten: the list "
          "keeps the survivor's page behind", (tester) async {
        final (container, opened) = await tab(
          tester,
          native: false,
          at: WaxRoute.notifications,
        );
        final browser = opened!;
        await _go(tester, container, gonePage);
        await _go(tester, container, WaxRoute.tasks);
        // As the merge's follow tells the history, the asker gone.
        _repo(container).facetItems.remove('artist ${gone.substring(3)}');
        final history = container.read(waxHistoryProvider)!
          ..forget(WaxRoute.notifications)
          ..forget(gonePage, instead: page);

        if (together) {
          browser
            ..goBack()
            ..goBack();
          await tester.pumpAndSettle();
        } else {
          await _browserBack(tester, browser);
          showsTab(
            tester,
            container,
            browser,
            (page, []),
            index: 1,
            tab: [WaxRoute.notifications, page, WaxRoute.tasks],
          );
          await _browserBack(tester, browser);
        }
        // What stands in is written over the oldest. Where the second back
        // came before the first landing's write, that write was dropped. A
        // branch off screen holds its pages until it is next shown.
        showsTab(
          tester,
          container,
          browser,
          home,
          index: 0,
          tab: [
            WaxRoute.home,
            if (together) gonePage else page,
            WaxRoute.tasks,
          ],
          everywhere: false,
        );
        expect(history.canGoBack, isFalse, reason: 'the oldest');

        final entries = [WaxRoute.home, page, WaxRoute.tasks];
        await _browserForward(tester, browser);
        showsTab(
          tester,
          container,
          browser,
          (page, []),
          index: 1,
          tab: entries,
        );
        expect(history.canGoBack, isTrue, reason: 'what stood in is behind');
        await _browserForward(tester, browser);
        showsTab(
          tester,
          container,
          browser,
          (WaxRoute.tasks, []),
          index: 2,
          tab: entries,
        );
        expect(history.isBehind(page), isTrue, reason: 'the list kept it');
      });
    }

    testWidgets('a browser forward onto an entry of it and another before a '
        'frame, onto the newest, forgotten: the browser comes back to its '
        "entry, written as the survivor's", (tester) async {
      final (container, opened) = await tab(tester, native: false);
      final browser = opened!;
      await _go(tester, container, artists);
      await _go(tester, container, gonePage);
      unawaited(_router(container).push<void>(album));
      await tester.pumpAndSettle();
      await _browserBack(tester, browser);
      await _browserBack(tester, browser);
      // As the merge's follow tells the history, the asker gone, and then
      // as the release's delete forgets its pages.
      _repo(container).facetItems.remove('artist ${gone.substring(3)}');
      final history = container.read(waxHistoryProvider)!
        ..forget(gonePage, instead: page)
        ..forget(WaxRoute.metadata(gone), instead: editor)
        ..forget(album)
        ..forget(WaxRoute.metadata(_albumPid));
      final arrived = _arrivals(container);
      final pushed = _pushArrivals(container);
      final entries = [WaxRoute.home, artists, page, '$gonePage + $album'];

      browser
        ..goForward()
        ..goForward();
      await tester.pumpAndSettle();

      expect(history.stepping, isFalse);
      showsTab(tester, container, browser, (page, []), index: 2, tab: entries);
      expect(history.isBehind(artists), isTrue, reason: 'the list kept it');
      await _browserBack(tester, browser);
      showsTab(
        tester,
        container,
        browser,
        (artists, []),
        index: 1,
        tab: entries,
      );
      await _browserForward(tester, browser);
      showsTab(tester, container, browser, (page, []), index: 2, tab: entries);
      neverBuilt([...arrived, ...pushed], [gone, _albumPid]);
    });

    // A second move that starts a pass (entries passed one after another,
    // each a move of its own) still counts from the entry the first landed
    // on, whose write went as the pass began.
    for (final together in <bool>[true, false]) {
      final how = together
          ? 'before a frame has drawn the first'
          : 'a frame apart';

      testWidgets('two browser backs $how, the second past a forgotten '
          "entry onto the app's oldest, forgotten too: the list keeps the "
          "survivor's page behind", (tester) async {
        final (container, opened) = await tab(
          tester,
          native: false,
          at: WaxRoute.notifications,
        );
        final browser = opened!;
        await _go(tester, container, WaxRoute.uploads);
        await _go(tester, container, gonePage);
        await _go(tester, container, WaxRoute.tasks);
        // As the merge's follow tells the history, the asker gone.
        _repo(container).facetItems.remove('artist ${gone.substring(3)}');
        final history = container.read(waxHistoryProvider)!
          ..forget(WaxRoute.notifications)
          ..forget(WaxRoute.uploads)
          ..forget(gonePage, instead: page);
        final arrived = _arrivals(container);

        if (together) {
          browser
            ..goBack()
            ..goBack();
          await tester.pumpAndSettle();
        } else {
          await _browserBack(tester, browser);
          showsTab(
            tester,
            container,
            browser,
            (page, []),
            index: 2,
            tab: [
              WaxRoute.notifications,
              WaxRoute.uploads,
              page,
              WaxRoute.tasks,
            ],
          );
          await _browserBack(tester, browser);
        }
        // What stands in is written over the oldest; the entry passed is
        // as it was. Where the second back came before the first landing's
        // write, that write was dropped. A branch off screen holds its
        // pages until it is next shown.
        showsTab(
          tester,
          container,
          browser,
          home,
          index: 0,
          tab: [
            WaxRoute.home,
            WaxRoute.uploads,
            if (together) gonePage else page,
            WaxRoute.tasks,
          ],
          everywhere: false,
        );
        expect(history.canGoBack, isFalse, reason: 'the oldest');

        final entries = [WaxRoute.home, WaxRoute.uploads, page, WaxRoute.tasks];
        await _browserForward(tester, browser);
        showsTab(
          tester,
          container,
          browser,
          (page, []),
          index: 2,
          tab: entries,
        );
        expect(history.canGoBack, isTrue, reason: 'what stood in is behind');
        await _browserForward(tester, browser);
        showsTab(
          tester,
          container,
          browser,
          (WaxRoute.tasks, []),
          index: 3,
          tab: entries,
        );
        expect(history.isBehind(page), isTrue, reason: 'the list kept it');
        neverBuilt(arrived, [gone, WaxRoute.uploads, WaxRoute.notifications]);
      });

      testWidgets('two browser forwards $how, the second onto a forgotten '
          'entry with the newest forgotten too: the browser comes back to '
          "the record's entry, written as the survivor's", (tester) async {
        final (container, opened) = await tab(tester, native: false);
        final browser = opened!;
        await _go(tester, container, artists);
        await _go(tester, container, gonePage);
        await _go(tester, container, WaxRoute.uploads);
        await _go(tester, container, WaxRoute.notifications);
        await _browserBack(tester, browser);
        await _browserBack(tester, browser);
        await _browserBack(tester, browser);
        // As the merge's follow tells the history, the asker gone.
        _repo(container).facetItems.remove('artist ${gone.substring(3)}');
        final history = container.read(waxHistoryProvider)!
          ..forget(WaxRoute.notifications)
          ..forget(WaxRoute.uploads)
          ..forget(gonePage, instead: page);
        final arrived = _arrivals(container);
        final entries = [
          WaxRoute.home,
          artists,
          page,
          WaxRoute.uploads,
          WaxRoute.notifications,
        ];
        void at((String, List<String>) screen, int index) => showsTab(
          tester,
          container,
          browser,
          screen,
          index: index,
          tab: entries,
        );

        if (together) {
          browser
            ..goForward()
            ..goForward();
          await tester.pumpAndSettle();
        } else {
          await _browserForward(tester, browser);
          at((page, []), 2);
          await _browserForward(tester, browser);
        }

        expect(history.stepping, isFalse);
        at((page, []), 2);
        expect(history.isBehind(artists), isTrue, reason: 'the list kept it');
        await _browserBack(tester, browser);
        at((artists, []), 1);
        await _browserForward(tester, browser);
        at((page, []), 2);
        neverBuilt(arrived, [gone, WaxRoute.uploads, WaxRoute.notifications]);
      });
    }

    testWidgets('a go of the app while the second of two browser forwards '
        "passes a forgotten entry: the go is written past the record's "
        'entry, which back then shows as the survivor', (tester) async {
      const latency = Duration(milliseconds: 100);
      final (container, opened) = await tab(tester, native: false);
      final browser = opened!;
      await _go(tester, container, artists);
      await _go(tester, container, gonePage);
      await _go(tester, container, WaxRoute.uploads);
      await _go(tester, container, WaxRoute.notifications);
      await _browserBack(tester, browser);
      await _browserBack(tester, browser);
      await _browserBack(tester, browser);
      // As the merge's follow tells the history, the asker gone.
      _repo(container).facetItems.remove('artist ${gone.substring(3)}');
      final history = container.read(waxHistoryProvider)!
        ..forget(WaxRoute.notifications)
        ..forget(WaxRoute.uploads)
        ..forget(gonePage, instead: page);
      final arrived = _arrivals(container);

      browser
        ..latency = latency
        ..goForward()
        ..goForward();
      // Once the second has begun its pass, before a frame.
      var passing = false;
      Timer.run(() {
        passing = history.stepping;
        _router(container).go(WaxRoute.radio);
      });
      await tester.pump(Duration.zero);
      for (var i = 0; i < 4; i++) {
        await tester.pump(latency + const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      browser.latency = null;

      expect(passing, isTrue, reason: 'passing the forgotten one');
      expect(history.stepping, isFalse);
      // The record's entry was never written (its landing's write went as
      // the pass began), and is where the go was made.
      showsTab(
        tester,
        container,
        browser,
        (WaxRoute.radio, []),
        index: 3,
        tab: [WaxRoute.home, artists, gonePage, WaxRoute.radio],
      );
      final entries = [WaxRoute.home, artists, page, WaxRoute.radio];
      await _browserBack(tester, browser);
      showsTab(tester, container, browser, (page, []), index: 2, tab: entries);
      await _browserBack(tester, browser);
      showsTab(
        tester,
        container,
        browser,
        (artists, []),
        index: 1,
        tab: entries,
      );
      neverBuilt(arrived, [gone, WaxRoute.uploads, WaxRoute.notifications]);
    });

    // By design, pinned as it is: the step that sends the browser back
    // cannot be called off, and a move of the visitor's own heard before it
    // lands is counted from the entry the first forward left.
    testWidgets('a back of the visitor while the browser is being sent back '
        "to the record's entry is counted from the entry before it: the "
        "index shows on the way, and the tab ends on the record's entry, "
        "written as the survivor's", (tester) async {
      const latency = Duration(milliseconds: 100);
      final (container, opened) = await tab(tester, native: false);
      final browser = opened!;
      await _go(tester, container, artists);
      await _go(tester, container, gonePage);
      await _go(tester, container, WaxRoute.uploads);
      await _go(tester, container, WaxRoute.notifications);
      await _browserBack(tester, browser);
      await _browserBack(tester, browser);
      await _browserBack(tester, browser);
      // As the merge's follow tells the history, the asker gone.
      _repo(container).facetItems.remove('artist ${gone.substring(3)}');
      final history = container.read(waxHistoryProvider)!
        ..forget(WaxRoute.notifications)
        ..forget(WaxRoute.uploads)
        ..forget(gonePage, instead: page);
      final arrived = _arrivals(container);

      browser
        ..latency = latency
        ..goForward()
        ..goForward();
      await tester.pump(Duration.zero);
      // The pass has reached the newest, and the browser is sent back.
      await tester.pump(latency + const Duration(milliseconds: 10));
      expect(browser.index, 4);
      expect(history.stepping, isTrue);
      browser.goBack();
      for (var i = 0; i < 4; i++) {
        await tester.pump(latency);
      }
      await tester.pumpAndSettle();
      browser.latency = null;

      expect(history.stepping, isFalse);
      showsTab(
        tester,
        container,
        browser,
        (page, []),
        index: 2,
        tab: [
          WaxRoute.home,
          artists,
          page,
          WaxRoute.uploads,
          WaxRoute.notifications,
        ],
      );
      expect(arrived, [page, artists, page], reason: 'the index on the way');
      expect(history.isBehind(artists), isTrue);
    });

    testWidgets('a dialog opened in the frame a browser back landed on an '
        'entry of it, then a second back: the dialog closes, and the tab '
        "is on that entry again, written as the survivor's", (tester) async {
      final (container, opened) = await tab(tester, native: false);
      final browser = opened!;
      await _go(tester, container, artists);
      await _go(tester, container, gonePage);
      await merge(tester, container);
      final history = container.read(waxHistoryProvider)!;
      final host = _router(container).routerDelegate.navigatorKey;
      // The step forward again lands once a frame has built the dialog, as
      // a browser's does.
      browser
        ..framed = true
        ..goBack();
      var held = false;
      Timer.run(() {
        held = history.stepping;
        unawaited(
          showDialog<void>(
            context: host.currentContext!,
            builder: (context) => const AlertDialog(content: Text('Sure?')),
          ),
        );
      });
      browser.goBack();
      await tester.pumpAndSettle();
      browser.framed = false;

      expect(held, isTrue, reason: 'the landing waits for its frame');
      expect(history.stepping, isFalse);
      expect(find.text('Sure?'), findsNothing);
      final entries = [WaxRoute.home, artists, page, '$page + $editor'];
      showsTab(tester, container, browser, (page, []), index: 2, tab: entries);
      await _browserBack(tester, browser);
      showsTab(
        tester,
        container,
        browser,
        (artists, []),
        index: 1,
        tab: entries,
      );
    });

    testWidgets('a go of the app in the frame a browser back landed on an '
        "entry of it: the survivor's page is written over that entry, and "
        'the go past it', (tester) async {
      final (container, opened) = await tab(tester, native: false);
      final browser = opened!;
      await _go(tester, container, artists);
      await _go(tester, container, gonePage);
      await merge(tester, container);
      final history = container.read(waxHistoryProvider)!;

      browser.goBack();
      // Once the back has landed, before the frame after it.
      var held = false;
      Timer.run(() {
        held = history.stepping;
        _router(container).go(WaxRoute.uploads);
      });
      await tester.pumpAndSettle();

      expect(held, isTrue, reason: 'the landing waits for its frame');
      expect(history.stepping, isFalse);
      final entries = [WaxRoute.home, artists, page, WaxRoute.uploads];
      showsTab(
        tester,
        container,
        browser,
        (WaxRoute.uploads, []),
        index: 3,
        tab: entries,
      );
      await _browserBack(tester, browser);
      showsTab(tester, container, browser, (page, []), index: 2, tab: entries);
      await _browserBack(tester, browser);
      showsTab(
        tester,
        container,
        browser,
        (artists, []),
        index: 1,
        tab: entries,
      );
    });

    for (final held in <bool>[true, false]) {
      testWidgets('signing out '
          '${held ? 'in the frame' : 'a frame after'} a browser back landed '
          "on an entry of it leaves the survivor's page on that entry, and "
          'one back leaves the app', (tester) async {
        final (container, opened) = await tab(tester, native: false);
        final browser = opened!;
        await _go(tester, container, artists);
        await _go(tester, container, gonePage);
        await merge(tester, container);
        final history = container.read(waxHistoryProvider)!;
        void signOut() =>
            unawaited(container.read(authControllerProvider.notifier).logout());

        browser.goBack();
        if (held) {
          Timer.run(signOut);
        } else {
          await tester.pumpAndSettle();
          signOut();
        }
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(history.stepping, isFalse);
        expect(browser.index, 3);
        expect(browser.location, _location(container));
        expect(Uri.parse(browser.location).path, WaxRoute.login);
        final entries = [WaxRoute.home, artists, page, browser.location];
        expect(entriesOf(browser), entries);

        browser.goBack();
        await tester.pumpAndSettle();
        expect(browser.left, isTrue, reason: 'no entry ate the press');
        expect(entriesOf(browser), entries);
        await tester.pump(WaxHistory.unansweredStep);
      });
    }

    testWidgets('the arrow pressed in the frame a browser back landed on an '
        'entry of it takes its turn after the write, and steps back from '
        'that entry', (tester) async {
      final (container, opened) = await tab(tester, native: false);
      final browser = opened!;
      await _go(tester, container, artists);
      await _go(tester, container, gonePage);
      await merge(tester, container);
      final history = container.read(waxHistoryProvider)!;

      browser.goBack();
      var held = false;
      Timer.run(() {
        held = history.stepping;
        history.back();
      });
      await tester.pumpAndSettle();

      expect(held, isTrue, reason: 'the landing waits for its frame');
      expect(history.stepping, isFalse);
      showsTab(
        tester,
        container,
        browser,
        (artists, []),
        index: 1,
        tab: [WaxRoute.home, artists, page, '$page + $editor'],
      );
    });

    testWidgets('a pop with a result that lands on an entry of it not landed '
        'on since: its opener hears, and the entry is written as the '
        "survivor's", (tester) async {
      final (container, opened) = await tab(tester, native: false);
      final browser = opened!;
      await _go(tester, container, artists);
      await _go(tester, container, gonePage);
      await edit(tester, container);
      final follow = asked(tester);
      await _back(tester);
      final heard = <Object?>[];
      unawaited(_router(container).push<String>(album).then(heard.add));
      await tester.pumpAndSettle();
      await answer(tester, container, follow);
      showsTab(
        tester,
        container,
        browser,
        (page, [album]),
        index: 3,
        tab: [WaxRoute.home, artists, gonePage, '$page + $album'],
      );
      final history = container.read(waxHistoryProvider)!;

      unawaited(history.pop('done'));
      await tester.pumpAndSettle();

      expect(heard, <Object?>['done']);
      expect(history.stepping, isFalse);
      final entries = [WaxRoute.home, artists, page, '$page + $album'];
      showsTab(tester, container, browser, (page, []), index: 2, tab: entries);
      await _browserBack(tester, browser);
      showsTab(
        tester,
        container,
        browser,
        (artists, []),
        index: 1,
        tab: entries,
      );
      await _browserForward(tester, browser);
      showsTab(tester, container, browser, (page, []), index: 2, tab: entries);
    });

    testWidgets('a history disposed in the frame its landing waits for has '
        'nothing under way, and writes nothing that is held after it', (
      tester,
    ) async {
      final (container, opened) = await tab(tester, native: false);
      final browser = opened!;
      await _go(tester, container, artists);
      await _go(tester, container, gonePage);
      await merge(tester, container);
      final history = container.read(waxHistoryProvider)!;
      final entries = entriesOf(browser);
      final binding = tester.binding;
      // Ahead of the landing's own callback in the frame after it, once
      // the app has gone: what holds the tab's writes next holds one.
      bool? stepping;
      binding.addPostFrameCallback((_) {
        stepping = history.stepping;
        browser.hold();
        unawaited(
          SystemNavigator.routeInformationUpdated(
            uri: Uri.parse(WaxRoute.tasks),
            state: const <String, Object?>{},
          ),
        );
      });

      browser.goBack();
      // Once the back has landed: the app goes in the frame after it.
      var held = false;
      Timer.run(() {
        held = history.stepping;
        binding
          ..attachRootWidget(binding.wrapWithDefaultView(const SizedBox()))
          ..scheduleFrame();
      });
      await tester.pump(Duration.zero);
      await tester.pump();

      expect(held, isTrue, reason: 'the landing waits for its frame');
      expect(stepping, isFalse, reason: 'gone with its history');
      expect(browser.index, 2);
      expect(entriesOf(browser), entries, reason: 'still held');
      browser.drop();
    });
  });
}
