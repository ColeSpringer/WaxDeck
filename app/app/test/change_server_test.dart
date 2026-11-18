import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Override lives here rather than in the root library.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/connect_server_screen.dart';
import 'package:waxdeck/src/auth/server_address.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

/// "Change server" on the sign-in and setup screens opens the connect
/// screen over the one it was opened from, so back returns there.
void main() {
  const loginFrom = '${WaxRoute.login}?${WaxRoute.fromParam}=%2Fsettings';

  Finder id(String id) => find.bySemanticsIdentifier(id);

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    bool bootstrapNeeded = false,
    bool animations = false,
    List<Override> extra = const <Override>[],
  }) => pumpWholeApp(
    tester,
    container: appContainer(
      repo: FakeRepository(bootstrapNeeded: bootstrapNeeded),
      extra: [
        desktopBackProvider.overrideWithValue(true),
        serverProbeProvider.overrideWithValue(
          (_) async =>
              const ServerHealth(status: 'ok', version: 'test', apiVersion: 1),
        ),
        ...extra,
      ],
    ),
    disableAnimations: !animations,
  );

  String location(ProviderContainer container) => container
      .read(routerProvider)
      .routerDelegate
      .currentConfiguration
      .uri
      .toString();

  /// System back, through the channel the platform sends it on.
  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  /// Whether a press of system back reached the platform: nothing in the
  /// app answered it, which is what leaving the app looks like from here.
  Future<bool> systemBackLeavesTheApp(WidgetTester tester) async {
    var left = false;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') left = true;
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await systemBack(tester);
    return left;
  }

  /// The mouse's back button pressed on the page.
  Future<void> mouseBack(WidgetTester tester) async {
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kBackMouseButton,
    );
    await gesture.down(const Offset(400, 20));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> altLeft(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
  }

  /// Whether the connect screen's address field holds the focus.
  bool addressFieldFocused(WidgetTester tester) => tester
      .widget<EditableText>(
        find.descendant(
          of: id(SemanticsIds.connectServerAddress),
          matching: find.byType(EditableText),
        ),
      )
      .focusNode
      .hasPrimaryFocus;

  Future<void> openChangeServer(WidgetTester tester) async {
    await tester.tap(id(SemanticsIds.connectServerOpen));
    await tester.pumpAndSettle();
    expect(id(SemanticsIds.connectServerAddress), findsOneWidget);
  }

  /// Presses the Change server button twice, the second press landing
  /// while the first is still sliding the connect screen in.
  Future<void> pressChangeServerTwice(WidgetTester tester) async {
    final open = tester.widget<WaxButton>(
      find.ancestor(
        of: id(SemanticsIds.connectServerOpen),
        matching: find.byType(WaxButton),
      ),
    );
    open.onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    open.onPressed!();
    await tester.pumpAndSettle();
  }

  group('from sign-in', () {
    Future<ProviderContainer> pumpLogin(
      WidgetTester tester, {
      bool animations = false,
    }) async {
      final container = await pump(tester, animations: animations);
      container.read(routerProvider).go(loginFrom);
      await tester.pumpAndSettle();
      await tester.enterText(id(SemanticsIds.loginUsername), 'frodo');
      await openChangeServer(tester);
      return container;
    }

    testWidgets('system back returns to it, with its from and its typing', (
      tester,
    ) async {
      final container = await pumpLogin(tester);

      expect(await systemBackLeavesTheApp(tester), isFalse);

      expect(id(SemanticsIds.loginSubmit), findsOneWidget);
      expect(id(SemanticsIds.connectServerAddress), findsNothing);
      expect(location(container), loginFrom);
      expect(find.widgetWithText(WaxTextField, 'frodo'), findsOneWidget);
    });

    testWidgets('the app back, as the mouse button sends it, does the same', (
      tester,
    ) async {
      final container = await pumpLogin(tester);

      await mouseBack(tester);

      expect(id(SemanticsIds.loginSubmit), findsOneWidget);
      expect(location(container), loginFrom);
      expect(find.widgetWithText(WaxTextField, 'frodo'), findsOneWidget);
    });

    testWidgets('the screen draws a back arrow that returns to it', (
      tester,
    ) async {
      final container = await pumpLogin(tester);

      expect(id(SemanticsIds.navBack), findsOneWidget);
      await tester.tap(id(SemanticsIds.navBack));
      await tester.pumpAndSettle();

      expect(id(SemanticsIds.loginSubmit), findsOneWidget);
      expect(id(SemanticsIds.connectServerAddress), findsNothing);
      expect(location(container), loginFrom);
      expect(find.widgetWithText(WaxTextField, 'frodo'), findsOneWidget);
    });

    testWidgets('Alt+Left is the address field\'s until focus leaves it', (
      tester,
    ) async {
      final container = await pumpLogin(tester);
      expect(addressFieldFocused(tester), isTrue);

      await altLeft(tester);
      expect(id(SemanticsIds.connectServerAddress), findsOneWidget);

      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pump();
      expect(addressFieldFocused(tester), isFalse);
      await altLeft(tester);

      expect(id(SemanticsIds.loginSubmit), findsOneWidget);
      expect(location(container), loginFrom);
      expect(find.widgetWithText(WaxTextField, 'frodo'), findsOneWidget);
    });

    testWidgets('a double tap on the button opens one connect screen', (
      tester,
    ) async {
      final container = await pump(tester);
      container.read(routerProvider).go(loginFrom);
      await tester.pumpAndSettle();

      await pressChangeServerTwice(tester);

      expect(
        find.byType(ConnectServerScreen, skipOffstage: false),
        findsOneWidget,
      );
      await systemBack(tester);
      expect(id(SemanticsIds.loginSubmit), findsOneWidget);
      expect(location(container), loginFrom);
    });

    testWidgets('connecting to the same address ends on a fresh form too', (
      tester,
    ) async {
      final container = await pumpLogin(tester);
      final address = container.read(serverAddressProvider);

      // The field is prefilled with it: a bare Connect.
      await tester.tap(id(SemanticsIds.connectServerSubmit));
      await tester.pumpAndSettle();

      expect(container.read(serverAddressProvider), address);
      expect(location(container), WaxRoute.login);
      expect(id(SemanticsIds.loginSubmit), findsOneWidget);
      expect(find.widgetWithText(WaxTextField, 'frodo'), findsNothing);
      expect(container.read(routerProvider).canPop(), isFalse);
    });

    testWidgets('the page leaving after a connect keeps its bar and arrow', (
      tester,
    ) async {
      final container = await pumpLogin(tester, animations: true);

      await tester.tap(id(SemanticsIds.connectServerSubmit));
      for (var i = 0; i < 60 && container.read(routerProvider).canPop(); i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(container.read(routerProvider).canPop(), isFalse);

      // Part-way through the exit: the page is still sliding away.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ConnectServerScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ConnectServerScreen),
          matching: find.byType(WaxScaffold),
        ),
        findsOneWidget,
      );
      expect(id(SemanticsIds.navBack), findsOneWidget);

      await tester.pumpAndSettle();
      expect(
        find.byType(ConnectServerScreen, skipOffstage: false),
        findsNothing,
      );
      expect(id(SemanticsIds.loginSubmit), findsOneWidget);
    });

    testWidgets('connecting ends on a fresh sign-in, as it always has', (
      tester,
    ) async {
      final container = await pumpLogin(tester);

      await tester.enterText(
        id(SemanticsIds.connectServerAddress),
        'http://other.test',
      );
      await tester.tap(id(SemanticsIds.connectServerSubmit));
      await tester.pumpAndSettle();

      expect(container.read(serverAddressProvider), 'http://other.test');
      expect(location(container), WaxRoute.login);
      expect(id(SemanticsIds.loginSubmit), findsOneWidget);
      expect(find.widgetWithText(WaxTextField, 'frodo'), findsNothing);
      expect(container.read(routerProvider).canPop(), isFalse);
      expect(await systemBackLeavesTheApp(tester), isTrue);
    });
  });

  group('from setup', () {
    Future<ProviderContainer> pumpSetup(WidgetTester tester) async {
      final container = await pump(tester, bootstrapNeeded: true);
      expect(location(container), WaxRoute.setup);
      await tester.enterText(id(SemanticsIds.setupUsername), 'bilbo');
      await openChangeServer(tester);
      return container;
    }

    testWidgets('system back returns to it, with its typing', (tester) async {
      final container = await pumpSetup(tester);

      expect(await systemBackLeavesTheApp(tester), isFalse);

      expect(id(SemanticsIds.setupSubmit), findsOneWidget);
      expect(id(SemanticsIds.connectServerAddress), findsNothing);
      expect(location(container), WaxRoute.setup);
      expect(find.widgetWithText(WaxTextField, 'bilbo'), findsOneWidget);
    });

    testWidgets('the mouse back button returns to it', (tester) async {
      final container = await pumpSetup(tester);

      await mouseBack(tester);

      expect(id(SemanticsIds.setupSubmit), findsOneWidget);
      expect(id(SemanticsIds.connectServerAddress), findsNothing);
      expect(location(container), WaxRoute.setup);
      expect(find.widgetWithText(WaxTextField, 'bilbo'), findsOneWidget);
    });

    testWidgets('the screen draws a back arrow that returns to it', (
      tester,
    ) async {
      final container = await pumpSetup(tester);

      expect(id(SemanticsIds.navBack), findsOneWidget);
      await tester.tap(id(SemanticsIds.navBack));
      await tester.pumpAndSettle();

      expect(id(SemanticsIds.setupSubmit), findsOneWidget);
      expect(id(SemanticsIds.connectServerAddress), findsNothing);
      expect(location(container), WaxRoute.setup);
      expect(find.widgetWithText(WaxTextField, 'bilbo'), findsOneWidget);
    });

    testWidgets('a double tap on the button opens one connect screen', (
      tester,
    ) async {
      final container = await pump(tester, bootstrapNeeded: true);
      expect(location(container), WaxRoute.setup);

      await pressChangeServerTwice(tester);

      expect(
        find.byType(ConnectServerScreen, skipOffstage: false),
        findsOneWidget,
      );
      await systemBack(tester);
      expect(id(SemanticsIds.setupSubmit), findsOneWidget);
      expect(location(container), WaxRoute.setup);
    });

    testWidgets('connecting to the same address ends on a fresh form too', (
      tester,
    ) async {
      final container = await pumpSetup(tester);
      final address = container.read(serverAddressProvider);

      // The field is prefilled with it: a bare Connect.
      await tester.tap(id(SemanticsIds.connectServerSubmit));
      await tester.pumpAndSettle();

      expect(container.read(serverAddressProvider), address);
      expect(location(container), WaxRoute.setup);
      expect(id(SemanticsIds.setupSubmit), findsOneWidget);
      expect(find.widgetWithText(WaxTextField, 'bilbo'), findsNothing);
      expect(container.read(routerProvider).canPop(), isFalse);
    });

    testWidgets('connecting another server to set up ends on a fresh form', (
      tester,
    ) async {
      final container = await pumpSetup(tester);

      await tester.enterText(
        id(SemanticsIds.connectServerAddress),
        'http://other.test',
      );
      await tester.tap(id(SemanticsIds.connectServerSubmit));
      await tester.pumpAndSettle();

      expect(location(container), WaxRoute.setup);
      expect(id(SemanticsIds.setupSubmit), findsOneWidget);
      expect(find.widgetWithText(WaxTextField, 'bilbo'), findsNothing);
      expect(container.read(routerProvider).canPop(), isFalse);
    });

    testWidgets('connecting a server with accounts ends on sign-in', (
      tester,
    ) async {
      final container = await pumpSetup(tester);
      // The server the visitor meant has its accounts.
      final repo = container.read(repositoryProvider) as FakeRepository;
      repo.bootstrapNeeded = false;
      container.invalidate(bootstrapStatusProvider);

      await tester.enterText(
        id(SemanticsIds.connectServerAddress),
        'http://other.test',
      );
      await tester.tap(id(SemanticsIds.connectServerSubmit));
      await tester.pumpAndSettle();

      expect(location(container), WaxRoute.login);
      expect(id(SemanticsIds.loginSubmit), findsOneWidget);
      expect(container.read(routerProvider).canPop(), isFalse);
    });
  });

  testWidgets('a cold start on the connect screen has nothing under it', (
    tester,
  ) async {
    final container = await pump(
      tester,
      extra: [bootServerAddressProvider.overrideWithValue(null)],
    );

    expect(id(SemanticsIds.connectServerAddress), findsOneWidget);
    expect(id(SemanticsIds.navBack), findsNothing);
    expect(container.read(routerProvider).canPop(), isFalse);
    expect(await systemBackLeavesTheApp(tester), isTrue);
  });

  testWidgets('a cold start grows no arrow under its forget dialog', (
    tester,
  ) async {
    final container = await pump(tester);
    // Opened by its own location, with an address stored to forget.
    container.read(routerProvider).go(WaxRoute.serverConnect);
    await tester.pumpAndSettle();
    expect(container.read(routerProvider).canPop(), isFalse);
    expect(id(SemanticsIds.connectServerForget), findsOneWidget);

    await tester.tap(id(SemanticsIds.connectServerForget));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    // The screen builds again while the dialog is up.
    unawaited(
      container.read(serverAddressProvider.notifier).adopt('http://other.test'),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(id(SemanticsIds.navBack), findsNothing);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(id(SemanticsIds.navBack), findsNothing);
    expect(id(SemanticsIds.connectServerAddress), findsOneWidget);
  });
}
