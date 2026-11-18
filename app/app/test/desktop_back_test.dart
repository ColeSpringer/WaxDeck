import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/desktop/desktop_ports.dart';
import 'package:waxdeck/src/desktop/mini_window.dart';
import 'package:waxdeck/src/home/home_screen.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_es.dart';
import 'package:waxdeck/src/player/player_screen.dart';
import 'package:waxdeck/src/podcasts/show_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/command_palette.dart';
import 'package:waxdeck/src/shell/commands.dart';
import 'package:waxdeck/src/shell/desktop_back.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shortcut_sheet.dart';
import 'package:waxdeck/src/tools/tasks_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

const _showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const _episodePid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';

const _admin = WaxDeckUser(
  id: 'us-1',
  username: 'admin',
  roles: ['admin'],
  uploadEnabled: true,
);

/// A window that can always be made small, and is, when asked.
class _SmallWindow implements MiniWindowPort {
  @override
  Future<MiniWindowCapabilities> probe() async => const MiniWindowCapabilities(
    available: true,
    frameless: true,
    alwaysOnTop: true,
  );

  @override
  Future<void> enter(MiniWindowCapabilities capabilities) async {}

  @override
  Future<void> leave() async {}

  @override
  Future<void> show() async {}

  @override
  Future<void> startDragging() async {}

  @override
  Future<void> quit() async {}

  @override
  Future<void> bindClose(Future<void> Function() handler) async {}

  @override
  Future<void> unbindClose() async {}
}

/// The whole app, signed in, standing on [desktop]'s machine or not.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  bool desktop = true,
}) async {
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo =
      FakeRepository(
          sessionState: const SessionState(authenticated: true, user: _admin),
        )
        ..addSubscription(testShow(_showPid))
        ..episodesByShow[_showPid] = <EpisodeSummary>[testEpisode(_episodePid)];
  final container = appContainer(
    repo: repo,
    extra: [
      desktopBackProvider.overrideWithValue(desktop),
      miniWindowPortProvider.overrideWithValue(_SmallWindow()),
    ],
  );
  await pumpWholeApp(tester, container: container, disableAnimations: true);
  return container;
}

GoRouter _router(ProviderContainer container) => container.read(routerProvider);

String _location(ProviderContainer container) =>
    _router(container).routerDelegate.currentConfiguration.uri.toString();

/// Home, then Tasks, then the show: two presses of back reach Home.
Future<ProviderContainer> _pumpOnTheShow(
  WidgetTester tester, {
  bool desktop = true,
}) async {
  final container = await _pump(tester, desktop: desktop);
  final router = _router(container);
  router.go(WaxRoute.tasks);
  await tester.pumpAndSettle();
  router.go(WaxRoute.show(_showPid));
  await tester.pumpAndSettle();
  expect(find.byType(ShowScreen), findsOneWidget);
  return container;
}

Future<void> _altLeft(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await tester.pumpAndSettle();
}

Future<void> _cmdBracket(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
}

/// The mouse's fourth button pressed at [at], dragged a little while held,
/// and let go.
Future<void> _backButton(WidgetTester tester, Offset at) async {
  final gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kBackMouseButton,
  );
  await gesture.down(at);
  await gesture.moveBy(const Offset(6, 0));
  await gesture.moveBy(const Offset(6, 0));
  await gesture.up();
  await tester.pumpAndSettle();
}

Offset _contentCentre(WidgetTester tester) =>
    tester.getCenter(find.byType(ShowScreen));

/// [DesktopBack] alone over a router of two pages, the second pushed,
/// with [wrap] between them.
Future<GoRouter> _pumpBare(
  WidgetTester tester,
  Widget Function(Widget child) wrap,
) async {
  final router = GoRouter(
    initialLocation: '/a',
    routes: <RouteBase>[
      GoRoute(
        path: '/a',
        builder: (context, state) => const SizedBox.expand(),
        routes: <RouteBase>[
          GoRoute(
            path: 'b',
            builder: (context, state) => const SizedBox.expand(),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  final container = appContainer(
    extra: [
      desktopBackProvider.overrideWithValue(true),
      routerProvider.overrideWithValue(router),
      miniWindowPortProvider.overrideWithValue(_SmallWindow()),
    ],
  );
  await mountHost(
    tester,
    WidgetsApp.router(
      routerConfig: router,
      color: const Color(0xFF000000),
      builder: (context, child) => DesktopBack(child: wrap(child!)),
    ),
    container: container,
  );
  unawaited(router.push<void>('/a/b'));
  await tester.pumpAndSettle();
  expect(router.state.uri.path, '/a/b');
  return router;
}

/// Something open over the page that is not a page: what Android's back
/// closes before it moves anything.
typedef _Opener = Future<void> Function(WidgetTester tester);

Future<void> _openDialog(WidgetTester tester) async {
  unawaited(
    showDialog<void>(
      context: tester.element(find.byType(ShowScreen)),
      builder: (context) => const AlertDialog(content: Text('Unsubscribe?')),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Unsubscribe?'), findsOneWidget);
}

Future<void> _openSheet(WidgetTester tester) async {
  unawaited(
    showWaxSheet<void>(
      context: tester.element(find.byType(ShowScreen)),
      builder: (context) => const SizedBox(
        height: 120,
        child: Center(child: Text('Unsubscribe?')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Unsubscribe?'), findsOneWidget);
}

Future<void> _openMenu(WidgetTester tester) async {
  unawaited(
    showMenu<void>(
      context: tester.element(find.byType(ShowScreen)),
      position: const RelativeRect.fromLTRB(300, 300, 300, 300),
      items: const <PopupMenuEntry<void>>[
        PopupMenuItem<void>(child: Text('Unsubscribe?')),
      ],
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Unsubscribe?'), findsOneWidget);
}

final _openers = <String, _Opener>{
  'a dialog': _openDialog,
  'a sheet': _openSheet,
  'a menu': _openMenu,
};

/// Whether the platform was asked to close the app, which is what leaving
/// looks like from inside a test.
bool Function() _watchLeaving(WidgetTester tester) {
  var left = false;
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'SystemNavigator.pop') left = true;
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return () => left;
}

void main() {
  group('on a native desktop', () {
    testWidgets('Alt+Left runs back once', (tester) async {
      final container = await _pumpOnTheShow(tester);

      await _altLeft(tester);
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(_location(container), WaxRoute.tasks);

      await _altLeft(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(_location(container), WaxRoute.home);
    });

    testWidgets('Cmd+[ runs back once', (tester) async {
      final container = await _pumpOnTheShow(tester);

      await _cmdBracket(tester);

      expect(find.byType(TasksScreen), findsOneWidget);
      expect(_location(container), WaxRoute.tasks);
    });

    testWidgets('a held key steps once', (tester) async {
      final container = await _pumpOnTheShow(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      expect(_location(container), WaxRoute.tasks);
    });

    testWidgets('mouse button 4 runs back once per press', (tester) async {
      final container = await _pumpOnTheShow(tester);

      await _backButton(tester, _contentCentre(tester));
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(_location(container), WaxRoute.tasks);

      await _backButton(tester, tester.getCenter(find.byType(TasksScreen)));
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('the other buttons and chords leave the page alone', (
      tester,
    ) async {
      final container = await _pumpOnTheShow(tester);

      for (final buttons in <int>[
        kPrimaryButton,
        kSecondaryButton,
        kMiddleMouseButton,
        kForwardMouseButton,
      ]) {
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: buttons,
        );
        await gesture.down(const Offset(900, 20));
        await gesture.up();
        await tester.pumpAndSettle();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
      await tester.pumpAndSettle();

      expect(_location(container), WaxRoute.show(_showPid));
    });

    for (final MapEntry(key: name, value: open) in _openers.entries) {
      testWidgets('Alt+Left closes $name and leaves the page where it is', (
        tester,
      ) async {
        final container = await _pumpOnTheShow(tester);
        await open(tester);

        await _altLeft(tester);
        expect(find.text('Unsubscribe?'), findsNothing);
        expect(find.byType(ShowScreen), findsOneWidget);
        expect(_location(container), WaxRoute.show(_showPid));

        await _altLeft(tester);
        expect(find.byType(TasksScreen), findsOneWidget);
      });

      testWidgets('mouse button 4 closes $name and leaves the page where it '
          'is', (tester) async {
        final container = await _pumpOnTheShow(tester);
        await open(tester);

        await _backButton(tester, tester.getCenter(find.text('Unsubscribe?')));
        expect(find.text('Unsubscribe?'), findsNothing);
        expect(find.byType(ShowScreen), findsOneWidget);
        expect(_location(container), WaxRoute.show(_showPid));
      });
    }

    testWidgets('mouse button 4 over the scrim closes the dialog once', (
      tester,
    ) async {
      final container = await _pumpOnTheShow(tester);
      await _openDialog(tester);

      await _backButton(tester, const Offset(40, 860));

      expect(find.text('Unsubscribe?'), findsNothing);
      expect(find.byType(ShowScreen), findsOneWidget);
      expect(_location(container), WaxRoute.show(_showPid));
    });

    testWidgets('with the player up, both collapse it and nothing else', (
      tester,
    ) async {
      final container = await _pumpOnTheShow(tester);
      final router = _router(container);

      unawaited(router.push<void>(WaxRoute.nowPlaying));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsOneWidget);
      await _altLeft(tester);
      expect(find.byType(PlayerScreen), findsNothing);
      expect(find.byType(ShowScreen), findsOneWidget);
      expect(_location(container), WaxRoute.show(_showPid));

      unawaited(router.push<void>(WaxRoute.nowPlaying));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsOneWidget);
      await _backButton(tester, tester.getCenter(find.byType(PlayerScreen)));
      expect(find.byType(PlayerScreen), findsNothing);
      expect(find.byType(ShowScreen), findsOneWidget);
      expect(_location(container), WaxRoute.show(_showPid));
    });

    testWidgets('at home with nowhere to go back to, both do nothing and the '
        'app stays open', (tester) async {
      final container = await _pump(tester);
      final left = _watchLeaving(tester);
      expect(find.byType(HomeScreen), findsOneWidget);

      await _altLeft(tester);
      await _cmdBracket(tester);
      await _backButton(tester, tester.getCenter(find.byType(HomeScreen)));

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(_location(container), WaxRoute.home);
      expect(left(), isFalse);
    });

    testWidgets('on a sign-in screen with nothing under it, both leave where '
        'the visitor was headed', (tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.defaultRouteNameTestValue = WaxRoute.tasks;
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
      final container = await pumpWholeApp(
        tester,
        container: appContainer(
          extra: [desktopBackProvider.overrideWithValue(true)],
        ),
        disableAnimations: true,
      );
      final login = _location(container);
      expect(Uri.parse(login).queryParameters[WaxRoute.fromParam], isNotNull);

      await _backButton(tester, const Offset(900, 20));
      expect(_location(container), login);

      // On the sign-in button: the form's fields keep Alt+Left for their
      // caret.
      Focus.of(
        tester.element(
          find
              .descendant(
                of: find.bySemanticsIdentifier(SemanticsIds.loginSubmit),
                matching: find.byType(Text),
              )
              .first,
        ),
      ).requestFocus();
      await tester.pump();
      await _altLeft(tester);
      expect(_location(container), login);
    });

    testWidgets('with the mini window up, Alt+Left moves nothing behind it', (
      tester,
    ) async {
      // The shell is kept mounted offstage, focus and all.
      final container = await _pumpOnTheShow(tester);
      await container.read(miniWindowProvider.notifier).enter();
      await tester.pumpAndSettle();
      expect(find.byType(ShowScreen), findsNothing);

      await _altLeft(tester);
      await _cmdBracket(tester);

      expect(_location(container), WaxRoute.show(_showPid));
      await container.read(miniWindowProvider.notifier).leave();
      await tester.pumpAndSettle();
      expect(find.byType(ShowScreen), findsOneWidget);
      await _altLeft(tester);
      expect(_location(container), WaxRoute.tasks, reason: 'bound again');
    });

    testWidgets('a text field keeps Alt+Left', (tester) async {
      final container = await _pumpOnTheShow(tester);
      await tester.tap(find.byType(EditableText).first);
      await tester.pumpAndSettle();

      await _altLeft(tester);

      expect(_location(container), WaxRoute.show(_showPid));
    });

    testWidgets('a second command flagged above the router is bound too, '
        'over a dialog as well', (tester) async {
      final container = await _pumpOnTheShow(tester);
      var ran = 0;
      container.read(commandRegistryProvider.notifier).register(Object(), [
        WaxCommand(
          id: 'probe',
          section: WaxCommandSection.app,
          activators: const <ShortcutActivator>[
            SingleActivator(LogicalKeyboardKey.keyJ, alt: true),
          ],
          aboveRouter: true,
          run: (context, ref) => ran++,
        ),
      ]);
      await tester.pumpAndSettle();
      Future<void> altJ() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pumpAndSettle();
      }

      await altJ();
      expect(ran, 1);
      await _openDialog(tester);
      await altJ();
      expect(ran, 2);
      expect(find.text('Unsubscribe?'), findsOneWidget, reason: 'not back');
      expect(_location(container), WaxRoute.show(_showPid));
    });

    testWidgets('mouse button 4 is heard over a child that takes no '
        'pointer', (tester) async {
      final router = await _pumpBare(
        tester,
        (child) => IgnorePointer(child: child),
      );

      await _backButton(tester, const Offset(500, 450));

      expect(router.state.uri.path, '/a');
    });

    testWidgets('mouse button 4 is heard over a child that takes every '
        'pointer', (tester) async {
      final router = await _pumpBare(
        tester,
        (child) => AbsorbPointer(child: child),
      );

      await _backButton(tester, const Offset(500, 450));

      expect(router.state.uri.path, '/a');
    });

    testWidgets('the palette runs back too', (tester) async {
      final container = await _pumpOnTheShow(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.bySemanticsIdentifier(SemanticsIds.commandPaletteField),
        'go back',
      );
      await tester.pump(PaletteQueryController.debounce);
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(
          SemanticsIds.commandPaletteEntry('cmd-back'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TasksScreen), findsOneWidget);
      expect(_location(container), WaxRoute.tasks);
    });

    testWidgets('the command is named, keyed and taught', (tester) async {
      final container = await _pump(tester);
      final commands = container.read(commandRegistryProvider);
      final back = commands.singleWhere((command) => command.id == 'back');

      expect(commandLabel(AppLocalizationsEn(), back), 'Go back');
      expect(commandLabel(AppLocalizationsEs(), back), 'Volver atrás');
      expect(back.keys, 'Alt ←');
      final taught = <String, String>{
        for (final group in shortcutGroups(AppLocalizationsEn(), commands))
          for (final row in group.rows) row.label: row.keys,
      };
      expect(taught['Go back'], 'Alt ←');
    });

    test('the keys are spelled the way each machine writes them', () {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      for (final (platform, spelled) in <(TargetPlatform, String)>[
        (TargetPlatform.linux, 'Alt ←'),
        (TargetPlatform.windows, 'Alt ←'),
        (TargetPlatform.macOS, '⌘ ['),
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(waxBackCommand.keys, spelled, reason: '$platform');
      }
    });
  });

  group('where the browser or the system owns back', () {
    testWidgets('neither the keys nor the button is bound', (tester) async {
      final container = await _pumpOnTheShow(tester, desktop: false);
      await _openDialog(tester);

      await _altLeft(tester);
      await _cmdBracket(tester);
      await _backButton(tester, tester.getCenter(find.text('Unsubscribe?')));

      expect(find.text('Unsubscribe?'), findsOneWidget);
      expect(_location(container), WaxRoute.show(_showPid));
      Navigator.of(tester.element(find.text('Unsubscribe?'))).pop();
      await tester.pumpAndSettle();

      await _altLeft(tester);
      await _cmdBracket(tester);
      await _backButton(tester, _contentCentre(tester));
      expect(find.byType(ShowScreen), findsOneWidget);
      expect(_location(container), WaxRoute.show(_showPid));
    });

    testWidgets('a command flagged above the router is bound all the same', (
      tester,
    ) async {
      final container = await _pumpOnTheShow(tester, desktop: false);
      var ran = 0;
      container.read(commandRegistryProvider.notifier).register(Object(), [
        WaxCommand(
          id: 'probe',
          section: WaxCommandSection.app,
          activators: const <ShortcutActivator>[
            SingleActivator(LogicalKeyboardKey.keyJ, alt: true),
          ],
          aboveRouter: true,
          run: (context, ref) => ran++,
        ),
      ]);
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      expect(ran, 1);
    });

    testWidgets('the command is neither offered nor taught', (tester) async {
      final container = await _pump(tester, desktop: false);
      final commands = container.read(commandRegistryProvider);

      expect(commands.where((command) => command.id == 'back'), isEmpty);
      final taught = <String>{
        for (final group in shortcutGroups(AppLocalizationsEn(), commands))
          for (final row in group.rows) row.label,
      };
      expect(taught, isNot(contains('Go back')));
    });

    test('the machines that carry the keys and the button', () {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        final container = ProviderContainer();
        addTearDown(container.dispose);
        expect(container.read(desktopBackProvider), switch (platform) {
          TargetPlatform.linux ||
          TargetPlatform.windows ||
          TargetPlatform.macOS => true,
          TargetPlatform.android ||
          TargetPlatform.iOS ||
          TargetPlatform.fuchsia => false,
        }, reason: '$platform');
      }
    });
  });
}
