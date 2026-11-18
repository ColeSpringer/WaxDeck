import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/login_screen.dart';
import 'package:waxdeck/src/books/books_screen.dart';
import 'package:waxdeck/src/connect/remote_session.dart';
import 'package:waxdeck/src/home/home_screen.dart';
import 'package:waxdeck/src/music/album_screen.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/music/music_hub_screen.dart';
import 'package:waxdeck/src/notifications/notifications_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/adaptive_shell.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/system_back_signal.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

const _showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const _albumPid = 'al-01JZX5N8QW3F4V9T2B7KDALBUM1';

const _admin = WaxDeckUser(
  id: 'us-1',
  username: 'admin',
  roles: ['admin'],
  uploadEnabled: true,
);

String get _album => WaxRoute.musicBucket(MusicDimension.albums, _albumPid);

/// Another endpoint's paused session, this client driving it.
final _pausedRemote = PlaybackSessionInfo(
  id: 'ps-remote',
  endpointId: 'pe-speaker',
  endpointName: 'Kitchen speaker',
  mine: true,
  authority: 'remote',
  playing: false,
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

/// What the app has told Android about system back, in order, and whether
/// a press asked the platform to leave.
class _Told {
  final handles = <bool>[];
  var left = false;

  bool? get last => handles.lastOrNull;
}

Future<void> _lifecycle(WidgetTester tester, AppLifecycleState state) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.lifecycle.name,
    SystemChannels.lifecycle.codec.encodeMessage(state.toString()),
    (_) {},
  );
  await tester.pumpAndSettle();
}

/// The whole app on a phone, with every call it makes on the platform
/// channel recorded. [resumed] as Android starts it: the framework tells
/// the platform nothing before then.
Future<(ProviderContainer, _Told)> _pumpPhone(
  WidgetTester tester, {
  bool resumed = true,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final told = _Told();
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    switch (call.method) {
      case 'SystemNavigator.setFrameworkHandlesBack':
        told.handles.add(call.arguments as bool);
      case 'SystemNavigator.pop':
        told.left = true;
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  if (resumed) await _lifecycle(tester, AppLifecycleState.resumed);
  final repo =
      FakeRepository(
          sessionState: const SessionState(authenticated: true, user: _admin),
        )
        ..addSubscription(testShow(_showPid))
        ..albums[_albumPid] = const AlbumDetail(
          pid: _albumPid,
          title: 'Gullwing',
        );
  final container = await pumpWholeApp(
    tester,
    container: appContainer(repo: repo),
    disableAnimations: true,
  );
  return (container, told);
}

/// A system back press, through the channel the platform uses.
Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
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

GoRouter _router(ProviderContainer container) => container.read(routerProvider);

Future<void> _go(
  WidgetTester tester,
  ProviderContainer container,
  String location,
) async {
  _router(container).go(location);
  await tester.pumpAndSettle();
}

/// Opens a dialog the way `showDialog` does by default: on the navigator
/// above the shell.
Future<void> _openDialog(WidgetTester tester, Type over) async {
  unawaited(
    showDialog<void>(
      context: tester.element(find.byType(over)),
      builder: (context) => const AlertDialog(content: Text('Delete files?')),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Delete files?'), findsOneWidget);
}

void main() {
  testWidgets('a cold start at home leaves back to Android', (tester) async {
    final (_, told) = await _pumpPhone(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(told.last, isFalse);
  });

  testWidgets('a tab and a drill-in under it claim back, and a dialog '
      'closing over the drill-in keeps the claim', (tester) async {
    final (container, told) = await _pumpPhone(tester);

    await _tapNav(tester, WaxNavTarget.music);
    expect(find.byType(MusicHubScreen), findsOneWidget);
    expect(told.last, isTrue, reason: 'the hub steps to Home');

    await _go(tester, container, _album);
    expect(find.byType(AlbumScreen), findsOneWidget);
    expect(told.last, isTrue, reason: 'the album steps back');

    await _openDialog(tester, AlbumScreen);
    expect(told.last, isTrue, reason: 'the dialog closes');

    await _systemBack(tester);
    expect(find.text('Delete files?'), findsNothing);
    expect(find.byType(AlbumScreen), findsOneWidget);
    expect(told.last, isTrue, reason: 'the album still steps back');
  });

  testWidgets('a go from home claims back, and back at home gives it up', (
    tester,
  ) async {
    final (container, told) = await _pumpPhone(tester);

    await _go(tester, container, WaxRoute.notifications);
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(told.last, isTrue, reason: 'back returns home');

    await _systemBack(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(told.last, isFalse);
  });

  testWidgets('three tab taps claim back until the ladder reaches home', (
    tester,
  ) async {
    final (_, told) = await _pumpPhone(tester);

    await _tapNav(tester, WaxNavTarget.music);
    await _tapNav(tester, WaxNavTarget.podcasts);
    await _tapNav(tester, WaxNavTarget.books);
    expect(find.byType(BooksScreen), findsOneWidget);
    expect(told.last, isTrue, reason: 'the ladder steps home once');

    await _systemBack(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(told.last, isFalse);
  });

  testWidgets('home after a sign-out and back in has nothing to step to', (
    tester,
  ) async {
    final (container, told) = await _pumpPhone(tester);
    await _go(tester, container, WaxRoute.notifications);
    await _go(tester, container, WaxRoute.home);
    expect(told.last, isTrue, reason: 'back returns to notifications');

    await container.read(authControllerProvider.notifier).logout();
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await container
        .read(authControllerProvider.notifier)
        .login(username: 'admin', password: 'secret');
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(told.last, isFalse);
  });

  testWidgets('another account arriving at home has nothing to step to', (
    tester,
  ) async {
    final (container, told) = await _pumpPhone(tester);
    await _go(tester, container, WaxRoute.notifications);
    await _go(tester, container, WaxRoute.home);
    expect(told.last, isTrue);

    final repo = container.read(repositoryProvider) as FakeRepository;
    repo.sessionState = const SessionState(
      authenticated: true,
      user: WaxDeckUser(id: 'us-9', username: 'kit', roles: ['user']),
    );
    // Not awaited: the swap waits for the last account's screens to go.
    unawaited(container.read(authControllerProvider.notifier).refreshSession());
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(told.last, isFalse);
  });

  testWidgets('the history cleared with nothing navigating gives back up at '
      'home', (tester) async {
    // What an account change does to the history, apart from the shell
    // it also replaces.
    final (container, told) = await _pumpPhone(tester);
    await _go(tester, container, WaxRoute.notifications);
    await _go(tester, container, WaxRoute.home);
    expect(told.last, isTrue);

    container.read(waxHistoryProvider)!.clear();
    await tester.pumpAndSettle();

    expect(told.last, isFalse);
  });

  testWidgets('a step back the router answers with the screen already up '
      'tells Android at once', (tester) async {
    // The remote's location sends home once nothing is being controlled,
    // so the step back to it lands where the visitor already is.
    final (container, told) = await _pumpPhone(tester);
    container.read(remoteSessionProvider.notifier).adopt(_pausedRemote);
    await _go(tester, container, WaxRoute.remote);
    expect(_router(container).state.uri.path, WaxRoute.remote);
    await _go(tester, container, WaxRoute.home);
    container.read(remoteSessionProvider.notifier).release();
    await tester.pumpAndSettle();
    expect(told.last, isTrue, reason: 'back steps to the remote');

    await _systemBack(tester);

    expect(told.left, isFalse);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(told.last, isFalse);
  });

  testWidgets('what was decided before the app ran is told once it does', (
    tester,
  ) async {
    final (_, told) = await _pumpPhone(tester, resumed: false);
    await _tapNav(tester, WaxNavTarget.music);
    expect(told.handles, isEmpty, reason: 'nothing is sent before it runs');

    await _lifecycle(tester, AppLifecycleState.resumed);
    expect(told.handles, <bool>[true]);
  });

  testWidgets('after every step Android hears whether the next press is the '
      "app's", (tester) async {
    final (container, told) = await _pumpPhone(tester);
    final signal = container.read(systemBackSignalProvider)!;
    final seen = <SystemBackAnswer>{};
    void check(String step) {
      final answer = signal.answer!;
      seen.add(answer);
      expect(
        told.last,
        answer != SystemBackAnswer.leave,
        reason: '$step: $answer',
      );
    }

    // A press Android was told is not the app's leaves it; any other
    // stays in it.
    Future<void> press(String step) async {
      final claimed = told.last!;
      await _systemBack(tester);
      expect(told.left, !claimed, reason: '$step: claimed $claimed');
      if (!told.left) check(step);
    }

    check('cold home');
    await _go(tester, container, WaxRoute.notifications);
    check('notifications');
    await _go(tester, container, WaxRoute.home);
    check('home, gone to');
    container.read(waxHistoryProvider)!.forget(WaxRoute.notifications);
    await tester.pumpAndSettle();
    expect(signal.answer, SystemBackAnswer.leave);
    check('notifications forgotten');

    await _openDialog(tester, HomeScreen);
    check('a dialog at home');
    await press('the dialog closed');
    expect(signal.answer, SystemBackAnswer.leave);

    await _tapNav(tester, WaxNavTarget.music);
    check('the music tab');
    await _go(tester, container, _album);
    check('the album');
    unawaited(
      showModalBottomSheet<void>(
        context: tester.element(find.byType(AlbumScreen)),
        builder: (context) => const Text('Track options'),
      ),
    );
    await tester.pumpAndSettle();
    check('a sheet over the album');
    await press('the sheet closed');
    expect(find.byType(AlbumScreen), findsOneWidget);
    await _openDialog(tester, AlbumScreen);
    check('a dialog over the album');
    await press('the dialog closed');
    expect(find.byType(AlbumScreen), findsOneWidget);

    await _tapNav(tester, WaxNavTarget.home);
    check('the home tab, music still drilled in');
    await _tapNav(tester, WaxNavTarget.music);
    check('the music tab, back on the album');
    await press('the album popped');
    await _go(tester, container, WaxRoute.notifications);
    check('notifications again');

    told.handles.clear();
    await _lifecycle(tester, AppLifecycleState.paused);
    await _lifecycle(tester, AppLifecycleState.resumed);
    expect(told.handles, isNotEmpty, reason: 'told again on resuming');
    check('resumed');

    while (!told.left) {
      await press('climbing out');
    }
    expect(seen, SystemBackAnswer.values.toSet());
  });
}
