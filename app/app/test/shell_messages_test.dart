import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/admin/dashboard_screen.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/connect_server_screen.dart';
import 'package:waxdeck/src/auth/login_screen.dart';
import 'package:waxdeck/src/auth/setup_screen.dart';
import 'package:waxdeck/src/auth/signup_screen.dart';
import 'package:waxdeck/src/home/home_screen.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/music/music_hub_screen.dart';
import 'package:waxdeck/src/player/car_mode_screen.dart';
import 'package:waxdeck/src/player/deck_bar_host.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/player/player_screen.dart';
import 'package:waxdeck/src/player/visualizer_screen.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_screen.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/shell/adaptive_shell.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';
import 'localized_host.dart';
import 'wax_finders.dart';

/// Where a shell message ends up on screen.
///
/// The channel itself is asserted a dozen times across the suite by
/// reading the notifier, which is the half that has always worked. What
/// nothing covered is the other half: the shell is what renders these,
/// and the surfaces that raise the ones with an action - an instant mix,
/// a queue edit - raise them from over the player, which is a route of
/// its own above the shell. Whether the button survives that trip is the
/// question, and it is answered here rather than only in the e2e suite.
///
/// Mounted as the whole app, deliberately: `routed_host.dart` builds its
/// own `MaterialApp.router` with no shell in it, so the listener that
/// draws these would not be there at all.

const _user = WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']);

const _track = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';

/// The window's insets as the engine reports them: [view] the view
/// padding, a keyboard [keyboard] high, and the padding what the keyboard
/// leaves of the view padding, side by side.
void _engineInsets(
  WidgetTester tester,
  FakeViewPadding view, {
  double keyboard = 0,
}) {
  tester.view
    ..viewPadding = view
    ..viewInsets = FakeViewPadding(bottom: keyboard)
    ..padding = FakeViewPadding(
      left: view.left,
      top: view.top,
      right: view.right,
      bottom: math.max(0, view.bottom - keyboard),
    );
}

ProviderContainer _signedInContainer() => appContainer(
  repo: FakeRepository(
    sessionState: const SessionState(authenticated: true, user: _user),
    items: [testItem('tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE')],
  ),
);

void main() {
  testWidgets('a message with an action is reachable from over the player', (
    tester,
  ) async {
    final container = _signedInContainer();
    await pumpWholeApp(tester, container: container);

    // The player over the shell, which is where the mix sheet raises its
    // message from.
    container.read(routerProvider).push(WaxRoute.nowPlaying);
    await tester.pumpAndSettle();

    var opened = false;
    container
        .read(shellMessengerProvider)
        .show(
          'Added 2 tracks to the queue',
          actionLabel: 'Open',
          onAction: () => opened = true,
          actionSemanticsId: SemanticsIds.queueOpen,
        );
    await tester.pumpAndSettle();

    final action = find.bySemanticsIdentifier(SemanticsIds.queueOpen);
    expect(
      action,
      findsOneWidget,
      reason: 'the only affordance a mix leaves is drawn where it can be used',
    );
    expect(find.text('Added 2 tracks to the queue'), findsOneWidget);

    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });

  testWidgets('a message is drawn on an ordinary screen as well', (
    tester,
  ) async {
    // The other position, so the one above is a comparison rather than
    // an isolated fact: no route pushed, the shell's own branch showing.
    final container = _signedInContainer();
    await pumpWholeApp(tester, container: container);

    container.read(shellMessengerProvider).show('Scan started');
    await tester.pumpAndSettle();

    expect(find.text('Scan started'), findsOneWidget);
  });

  testWidgets('a message rests where it always has with no bar to clear', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = _signedInContainer();
    await pumpWholeApp(tester, container: container);

    container.read(shellMessengerProvider).show('Scan started');
    await tester.pumpAndSettle();

    final bar = tester.getRect(
      find
          .ancestor(
            of: find.text('Scan started'),
            matching: find.byType(Material),
          )
          .first,
    );
    // Measured before any bar could lift it.
    expect(1000 - bar.bottom, 10);
  });

  group('with no bar to clear a message rests where a floating snack bar '
      'rests', () {
    /// The whole app in a window of [size] with the view padding [insets]
    /// and a keyboard [keyboard] high, and something playing, so the deck
    /// bar is up.
    Future<ProviderContainer> pumpPlaying(
      WidgetTester tester,
      Size size, {
      FakeViewPadding insets = FakeViewPadding.zero,
      double keyboard = 0,
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      _engineInsets(tester, insets, keyboard: keyboard);
      addTearDown(tester.view.reset);
      final container = _signedInContainer();
      await pumpWholeApp(tester, container: container, disableAnimations: true);
      container.read(nowPlayingProvider.notifier).play(
        [testItem('tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE', title: 'Kelp Line')],
        source: const QueueSource(
          kind: QueueSourceKind.single,
          label: 'Kelp Line',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DeckBarHost), findsOneWidget);
      return container;
    }

    Future<Rect> show(WidgetTester tester, ProviderContainer container) async {
      container.read(shellMessengerProvider).show('Scan started');
      await tester.pumpAndSettle();
      return tester.getRect(
        find
            .ancestor(
              of: find.text('Scan started'),
              matching: find.byType(Material),
            )
            .first,
      );
    }

    /// The pane the screens are drawn in, beside and above the chrome.
    Rect pane(WidgetTester tester) =>
        tester.getRect(find.byType(StatefulNavigationShell));

    Future<void> stop(WidgetTester tester, ProviderContainer container) async {
      container.read(queueControllerProvider.notifier).clear();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('on the pane beside the sidebar, above the dock', (
      tester,
    ) async {
      final container = await pumpPlaying(tester, const Size(1600, 1000));
      final bar = await show(tester, container);

      final sidebar = tester.getRect(find.byType(WaxSidebar));
      final dock = tester.getRect(find.byType(DeckBarHost));
      expect(pane(tester).left, sidebar.right);
      expect(pane(tester).bottom, dock.top);
      expect(bar.bottom, dock.top - 10);
      expect(bar.left, pane(tester).left + 15);
      expect(bar.right, pane(tester).right - 15);
      await stop(tester, container);
    });

    testWidgets('moves up with the pane as the dock comes under it', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1600, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = _signedInContainer();
      await pumpWholeApp(tester, container: container, disableAnimations: true);
      final before = await show(tester, container);
      expect(before.bottom, 1000 - 10);

      container.read(nowPlayingProvider.notifier).play(
        [testItem('tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE', title: 'Kelp Line')],
        source: const QueueSource(
          kind: QueueSourceKind.single,
          label: 'Kelp Line',
        ),
      );
      await tester.pumpAndSettle();

      final dock = tester.getRect(find.byType(DeckBarHost));
      final bar = tester.getRect(
        find
            .ancestor(
              of: find.text('Scan started'),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(bar.bottom, dock.top - 10);
      await stop(tester, container);
    });

    testWidgets("on the console's page beside its section list", (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1600, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = _signedInContainer();
      await pumpWholeApp(tester, container: container);
      container.read(routerProvider).go(WaxRoute.admin);
      await tester.pumpAndSettle();
      final page = tester.getRect(find.byType(AdminDashboardScreen));
      expect(page.left, greaterThan(pane(tester).left + 200));

      final bar = await show(tester, container);
      expect(bar.left, page.left + 15);
      expect(bar.right, page.right - 15);
      expect(bar.bottom, page.bottom - 10);
    });

    testWidgets('on the pane beside the rail, above the dock', (tester) async {
      final container = await pumpPlaying(tester, const Size(700, 900));
      final bar = await show(tester, container);

      final rail = tester.getRect(find.byType(WaxNavRail));
      final dock = tester.getRect(find.byType(DeckBarHost));
      expect(pane(tester).left, rail.right);
      expect(bar.bottom, dock.top - 10);
      expect(bar.left, rail.right + 15);
      expect(bar.right, 700 - 15);
      await stop(tester, container);
    });

    testWidgets('on a phone, above the mini player over the tab bar', (
      tester,
    ) async {
      final container = await pumpPlaying(tester, const Size(390, 844));
      final bar = await show(tester, container);

      final player = tester.getRect(find.byType(DeckBarHost));
      final tabs = tester.getRect(find.byType(WaxNavBar));
      expect(player.bottom, tabs.top);
      expect(bar.bottom, player.top - 10);
      expect(bar.left, 15);
      expect(bar.right, 390 - 15);
      await stop(tester, container);
    });

    testWidgets("on a phone with a bottom inset, on the pane's foot: the "
        'tabs have taken it', (tester) async {
      const inset = FakeViewPadding(bottom: 34);
      final container = await pumpPlaying(
        tester,
        const Size(390, 844),
        insets: inset,
      );
      final bar = await show(tester, container);

      expect(tester.getRect(find.byType(WaxNavBar)).bottom, 844);
      expect(bar.bottom, pane(tester).bottom - 10);
      await stop(tester, container);
    });

    testWidgets("beside the sidebar with a bottom inset, on the pane's foot: "
        'the dock has taken it', (tester) async {
      const inset = FakeViewPadding(bottom: 30);
      final container = await pumpPlaying(
        tester,
        const Size(1600, 1000),
        insets: inset,
      );
      final bar = await show(tester, container);

      final dock = tester.getRect(find.byType(DeckBarHost));
      expect(dock.bottom, 1000);
      expect(pane(tester).bottom, dock.top);
      expect(bar.bottom, dock.top - 10);
      await stop(tester, container);
    });

    testWidgets('beside the rail with a bottom inset and nothing playing, the '
        "inset above the pane's foot", (tester) async {
      tester.view
        ..physicalSize = const Size(700, 900)
        ..devicePixelRatio = 1;
      _engineInsets(tester, const FakeViewPadding(bottom: 30));
      addTearDown(tester.view.reset);
      final container = _signedInContainer();
      await pumpWholeApp(tester, container: container, disableAnimations: true);
      final bar = await show(tester, container);

      expect(find.byType(DeckBarHost), findsNothing);
      expect(pane(tester).bottom, 900);
      expect(bar.bottom, 900 - 30 - 10);
    });

    testWidgets("beside the sidebar with the keyboard up, on the keyboard's "
        'top', (tester) async {
      final container = await pumpPlaying(
        tester,
        const Size(1600, 1000),
        insets: const FakeViewPadding(bottom: 30),
        keyboard: 300,
      );
      final bar = await show(tester, container);

      expect(bar.bottom, 1000 - 300 - 10);
      await stop(tester, container);
    });

    testWidgets("on a phone with nothing playing and the keyboard up, on the "
        "keyboard's top", (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      _engineInsets(tester, const FakeViewPadding(bottom: 34), keyboard: 300);
      addTearDown(tester.view.reset);
      final container = _signedInContainer();
      await pumpWholeApp(tester, container: container, disableAnimations: true);
      final bar = await show(tester, container);

      expect(find.byType(DeckBarHost), findsNothing);
      expect(bar.bottom, 844 - 300 - 10);
    });

    testWidgets("on a phone with the keyboard up, on the keyboard's top: the "
        'dock and the tabs under it are not counted again', (tester) async {
      final container = await pumpPlaying(
        tester,
        const Size(390, 844),
        insets: const FakeViewPadding(bottom: 34),
        keyboard: 300,
      );
      final bar = await show(tester, container);

      expect(bar.bottom, 844 - 300 - 10);
      expect(bar.left, 15);
      await stop(tester, container);
    });

    for (final entry in <String, (Size, double)>{
      'on a phone': (const Size(390, 844), 34),
      'beside the sidebar': (const Size(1600, 1000), 30),
    }.entries) {
      final (size, inset) = entry.value;

      testWidgets("${entry.key}, with a keyboard shorter than what is below "
          "the pane, on the pane's foot: the inset under it is not counted "
          'again', (tester) async {
        final container = await pumpPlaying(
          tester,
          size,
          insets: FakeViewPadding(bottom: inset),
        );
        await show(tester, container);
        final foot = pane(tester).bottom;
        final tabs = find.byType(WaxNavBar);
        // Short of the gesture bar, then over it but short of the tabs
        // (or of the dock beside the sidebar), then between the tabs and
        // the dock on them.
        final keyboards = <double>[
          inset / 2,
          if (tester.any(tabs)) ...<double>[
            tester.getRect(tabs).height - 10,
            tester.getRect(tabs).height + 10,
          ] else
            size.height - foot - 10,
        ];
        for (final keyboard in keyboards) {
          _engineInsets(
            tester,
            FakeViewPadding(bottom: inset),
            keyboard: keyboard,
          );
          await tester.pumpAndSettle();
          expect(pane(tester).bottom, foot, reason: 'keyboard $keyboard');
          expect(
            tester
                .getRect(
                  find
                      .ancestor(
                        of: find.text('Scan started'),
                        matching: find.byType(Material),
                      )
                      .first,
                )
                .bottom,
            foot - 10,
            reason: 'keyboard $keyboard',
          );
        }
        await stop(tester, container);
      });
    }

    for (final entry in <String, Size>{
      'beside the rail': const Size(700, 900),
      'beside the sidebar': const Size(1600, 1000),
    }.entries) {
      final size = entry.value;

      testWidgets("${entry.key} with nothing playing, a keyboard rising "
          "through the gesture bar never takes a message below the page's "
          'foot', (tester) async {
        const inset = FakeViewPadding(bottom: 30);
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        _engineInsets(tester, inset);
        addTearDown(tester.view.reset);
        final container = _signedInContainer();
        await pumpWholeApp(
          tester,
          container: container,
          disableAnimations: true,
        );
        await show(tester, container);
        expect(find.byType(DeckBarHost), findsNothing);

        for (final keyboard in const <double>[0, 10, 20, 29, 30, 40]) {
          _engineInsets(tester, inset, keyboard: keyboard);
          await tester.pumpAndSettle();
          final foot = tester
              .getRect(
                find
                    .descendant(
                      of: find.byType(StatefulNavigationShell),
                      matching: find.byType(CustomScrollView),
                    )
                    .first,
              )
              .bottom;
          final message = tester.getRect(
            find
                .ancestor(
                  of: find.text('Scan started'),
                  matching: find.byType(Material),
                )
                .first,
          );
          expect(message.bottom, foot - 10, reason: 'keyboard $keyboard');
        }
      });
    }

    testWidgets('inside the side insets of a pane that has them', (
      tester,
    ) async {
      const notch = FakeViewPadding(left: 44, right: 44);
      final container = await pumpPlaying(
        tester,
        const Size(1300, 600),
        insets: notch,
      );
      final bar = await show(tester, container);

      // The sidebar stands against the start edge and has taken that
      // inset; the end one is the pane's.
      expect(bar.left, pane(tester).left + 15);
      expect(bar.right, pane(tester).right - 44 - 15);
      expect(bar.bottom, pane(tester).bottom - 10);
      await stop(tester, container);
    });

    testWidgets("over the player, at the window's foot inside its inset", (
      tester,
    ) async {
      const inset = FakeViewPadding(bottom: 34);
      final container = await pumpPlaying(
        tester,
        const Size(390, 844),
        insets: inset,
      );
      container.read(routerProvider).push<void>(WaxRoute.nowPlaying);
      await tester.pumpAndSettle();
      final bar = await show(tester, container);

      expect(bar.bottom, 844 - 34 - 10);
      expect(bar.left, 15);
      expect(bar.right, 390 - 15);
      await stop(tester, container);
    });
  });

  /// A host over a page that counts the presses that reach it, in an
  /// 800 by 600 window, and the messenger it draws. The page is drawn on
  /// as the app's are: a Scaffold in an area of its own, as the player's.
  Future<ShellMessenger> pumpPage(
    WidgetTester tester, {
    required VoidCallback onPress,
    Widget? bottom,
  }) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: localizedHost(
          ShellMessageHost(
            child: ShellMessageArea(
              child: Scaffold(
                body: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onPress,
                      ),
                    ),
                    if (bottom != null)
                      Align(alignment: Alignment.bottomCenter, child: bottom),
                  ],
                ),
              ),
            ),
          ),
          theme: buildWaxTheme(),
        ),
      ),
    );
    return ProviderScope.containerOf(
      tester.element(find.byType(ShellMessageHost)),
    ).read(shellMessengerProvider);
  }

  Rect barOf(WidgetTester tester, String text) => tester.getRect(
    find.ancestor(of: find.text(text), matching: find.byType(Material)).first,
  );

  testWidgets("with no bar to clear a message is drawn in the theme's "
      'colours, takes a press only on itself, and is up for its usual time', (
    tester,
  ) async {
    var under = 0;
    final messenger = await pumpPage(tester, onPress: () => under++);

    messenger.show('Scan started');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final material = tester.widget<Material>(
      find
          .ancestor(
            of: find.text('Scan started'),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, WaxColors.dark.surface3);
    expect(
      material.shape,
      const RoundedRectangleBorder(borderRadius: WaxRadius.card),
    );
    expect(material.elevation, 6);
    final bar = barOf(tester, 'Scan started');
    expect(600 - bar.bottom, 10);
    // Beside it and under it is the page's.
    await tester.tapAt(Offset(bar.center.dx, bar.bottom + 5));
    await tester.tapAt(Offset(bar.left - 5, bar.center.dy));
    await tester.pump();
    expect(under, 2);
    await tester.tapAt(bar.center);
    await tester.pump();
    expect(under, 2);

    await tester.pump(const Duration(milliseconds: 3600));
    expect(find.text('Scan started'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('Scan started'), findsNothing);
  });

  testWidgets("rests above its page's floating button as Material's bar did, "
      'a message declining the lift included', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: localizedHost(
          ShellMessageHost(
            child: WaxScaffold(
              title: 'Invites',
              body: const SizedBox(height: 200),
              floating: WaxFab(
                glyph: WaxIcons.addPerson,
                label: 'Invite',
                onPressed: () {},
              ),
            ),
          ),
          theme: buildWaxTheme(),
        ),
      ),
    );
    final messenger = ProviderScope.containerOf(
      tester.element(find.byType(ShellMessageHost)),
    ).read(shellMessengerProvider);
    final fab = tester.getRect(find.byType(WaxFab));
    expect(fab.bottom, lessThan(600));

    for (final clearsBar in <bool>[true, false]) {
      messenger.show('Invite sent', clearsBar: clearsBar);
      await tester.pumpAndSettle();
      // Material rested a floating snack bar's inset on the button's top.
      expect(
        barOf(tester, 'Invite sent').bottom,
        fab.top - WaxMessageBar.inset.bottom,
        reason: 'clearsBar: $clearsBar',
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    }
  });

  for (final clearsBar in <bool>[true, false]) {
    testWidgets('moves above a floating button on the first frame that has '
        'it, and back on the first that lacks it, as Material did, with '
        'clearsBar $clearsBar', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final shown = ValueNotifier(true);
      addTearDown(shown.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: localizedHost(
            ShellMessageHost(
              child: ValueListenableBuilder<bool>(
                valueListenable: shown,
                builder: (context, on, _) => WaxScaffold(
                  title: 'Invites',
                  body: const SizedBox(height: 200),
                  floating: on
                      ? WaxFab(
                          glyph: WaxIcons.addPerson,
                          label: 'Invite',
                          onPressed: () {},
                        )
                      : null,
                ),
              ),
            ),
            theme: buildWaxTheme(),
          ),
        ),
      );
      final fabTop = tester.getRect(find.byType(WaxFab)).top;
      shown.value = false;
      await tester.pumpAndSettle();
      var undone = 0;
      ProviderScope.containerOf(tester.element(find.byType(ShellMessageHost)))
          .read(shellMessengerProvider)
          .show(
            'Invite sent',
            actionLabel: 'Undo',
            onAction: () => undone++,
            persist: true,
            clearsBar: clearsBar,
          );
      await tester.pumpAndSettle();
      final rest = barOf(tester, 'Invite sent').bottom;
      final above = fabTop - WaxMessageBar.inset.bottom;
      expect(above, lessThan(rest));

      shown.value = true;
      for (var i = 1; i <= 12; i++) {
        await tester.pump(const Duration(milliseconds: 25));
        expect(
          barOf(tester, 'Invite sent').bottom,
          above,
          reason: 'comes, ${i * 25} ms',
        );
      }
      await tester.pumpAndSettle();

      shown.value = false;
      for (var i = 1; i <= 16; i++) {
        await tester.pump(const Duration(milliseconds: 25));
        final going = find.byType(WaxFab).evaluate().isNotEmpty;
        expect(
          barOf(tester, 'Invite sent').bottom,
          going ? above : rest,
          reason: 'goes, ${i * 25} ms, button ${going ? 'leaving' : 'gone'}',
        );
      }
      expect(find.byType(WaxFab), findsNothing);
      expect(tester.takeException(), isNull);

      // Pressed where it is drawn, above the button.
      shown.value = true;
      await tester.pumpAndSettle();
      expect(barOf(tester, 'Invite sent').bottom, above);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(undone, 1);
    });
  }

  testWidgets('a message is one node a screen reader hears as it comes, its '
      "bar's own, with its action inside and a way to dismiss it", (
    tester,
  ) async {
    final messenger = await pumpPage(tester, onPress: () {});

    messenger.show(
      'Added 2 tracks to the queue',
      actionLabel: 'Open',
      onAction: () {},
      actionSemanticsId: SemanticsIds.queueOpen,
    );
    await tester.pumpAndSettle();

    final node = tester.getSemantics(find.text('Added 2 tracks to the queue'));
    expect(
      semanticsRectOnScreen(node),
      barOf(tester, 'Added 2 tracks to the queue'),
    );
    final data = node.getSemanticsData();
    expect(data.label, 'Added 2 tracks to the queue');
    expect(data.flagsCollection.isLiveRegion, isTrue);
    expect(data.hasAction(SemanticsAction.dismiss), isTrue);
    final action = tester.getSemantics(
      find.bySemanticsIdentifier(SemanticsIds.queueOpen),
    );
    expect(action.parent, same(node));
    expect(action.getSemanticsData().flagsCollection.isButton, isTrue);

    messenger.show('Scan started');
    await tester.pump();
    tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.dismiss,
    );
    await tester.pumpAndSettle();
    expect(find.text('Added 2 tracks to the queue'), findsNothing);
    expect(find.text('Scan started'), findsOneWidget);
  });

  testWidgets('a message lifted clear of a bar leaves its buttons to touch '
      'exploration', (tester) async {
    final messenger = await pumpPage(
      tester,
      onPress: () {},
      bottom: ShellMessageClearance(
        child: SizedBox(
          width: 400,
          height: 80,
          child: Center(
            child: WaxButton(
              label: 'Approve',
              semanticsId: SemanticsIds.reviewApprove,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );

    messenger.show('Scan started');
    await tester.pumpAndSettle();

    final bar = barOf(tester, 'Scan started');
    final approve = find.bySemanticsIdentifier(SemanticsIds.reviewApprove);
    expect(bar.bottom, lessThanOrEqualTo(tester.getRect(approve).top));
    expect(
      semanticsRectOnScreen(tester.getSemantics(find.text('Scan started'))),
      bar,
    );
    // Over the button, and in the gap the lift opened over its bar.
    for (final point in <Offset>[
      tester.getCenter(approve),
      Offset(tester.getCenter(approve).dx, 600 - 80 - 2),
    ]) {
      expect(
        touchExploredAt(tester, point)?.id,
        isNot(tester.getSemantics(find.text('Scan started')).id),
      );
    }
    expect(
      touchExploredAt(tester, tester.getCenter(approve))?.id,
      tester.getSemantics(approve).id,
    );
  });

  testWidgets('swiped down, a message goes and the next comes', (tester) async {
    final messenger = await pumpPage(tester, onPress: () {});

    messenger.show('Scan started');
    await tester.pumpAndSettle();
    messenger.show('Link copied');
    await tester.pump();
    await tester.drag(find.text('Scan started'), const Offset(0, 300));
    await tester.pumpAndSettle();

    expect(find.text('Scan started'), findsNothing);
    expect(find.text('Link copied'), findsOneWidget);
  });

  testWidgets('an offer made to wait closes from its close control', (
    tester,
  ) async {
    final messenger = await pumpPage(tester, onPress: () {});
    var undone = false;

    messenger.show(
      'Marked finished',
      actionLabel: 'Undo',
      onAction: () => undone = true,
      persist: true,
    );
    await tester.pumpAndSettle();
    // By the name a screen reader reads, which a tooltip may carry.
    SemanticsNode? close;
    void visit(SemanticsNode node) {
      final data = node.getSemanticsData();
      if (data.label == 'Close' || data.tooltip == 'Close') close ??= node;
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    visit(
      tester
          .binding
          .renderViews
          .first
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!,
    );
    await tester.tapAt(semanticsRectOnScreen(close!).center);
    await tester.pumpAndSettle();

    expect(find.text('Marked finished'), findsNothing);
    expect(undone, isFalse);
  });

  testWidgets("a message over car mode's playing face is drawn in the car's "
      'colours', (tester) async {
    final container = _signedInContainer();
    await pumpWholeApp(tester, container: container, disableAnimations: true);
    container.read(nowPlayingProvider.notifier).play(
      [testItem('tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE', title: 'Kelp Line')],
      source: const QueueSource(
        kind: QueueSourceKind.single,
        label: 'Kelp Line',
      ),
    );
    await tester.pumpAndSettle();
    container.read(routerProvider).push<void>(WaxRoute.carMode);
    await tester.pumpAndSettle();
    expect(find.byType(CarModeScaffold), findsOneWidget);

    container.read(shellMessengerProvider).show('Could not restore');
    await tester.pumpAndSettle();

    final bar = tester.widget<Material>(
      find
          .ancestor(
            of: find.text('Could not restore'),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(bar.color, WaxColors.oled.surface3);
    container.read(queueControllerProvider.notifier).clear();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets("a message over car mode is drawn in the car's colours", (
    tester,
  ) async {
    final container = _signedInContainer();
    await pumpWholeApp(tester, container: container);
    container.read(routerProvider).go(WaxRoute.carMode);
    await tester.pumpAndSettle();

    container.read(shellMessengerProvider).show('Could not restore');
    await tester.pumpAndSettle();

    final bar = tester.widget<Material>(
      find
          .ancestor(
            of: find.text('Could not restore'),
            matching: find.byType(Material),
          )
          .first,
    );
    // The bar's own ground, in the car's theme and not the app's.
    expect(bar.color, WaxColors.oled.surface3);
    expect(bar.color, isNot(buildWaxTheme().extension<WaxColors>()!.surface3));
  });

  group('a message beside a bar along the bottom', () {
    const height = 600.0;
    const bar = 80.0;

    /// A shell with one bar to clear, there while [shown] holds, on a page
    /// drawn on as the app's are, and the gap under the message once it is
    /// up.
    Future<ShellMessenger> pumpBar(
      WidgetTester tester, {
      ValueNotifier<bool>? shown,
    }) async {
      tester.view.physicalSize = const Size(800, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const clearance = ShellMessageClearance(
        child: SizedBox(width: 400, height: bar),
      );
      await tester.pumpWidget(
        ProviderScope(
          child: localizedHost(
            ShellMessageHost(
              child: ShellMessageArea(
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: shown == null
                        ? clearance
                        : ValueListenableBuilder<bool>(
                            valueListenable: shown,
                            builder: (context, on, _) =>
                                on ? clearance : const SizedBox.shrink(),
                          ),
                  ),
                ),
              ),
            ),
            theme: buildWaxTheme(),
          ),
        ),
      );
      return ProviderScope.containerOf(
        tester.element(find.byType(ShellMessageHost)),
      ).read(shellMessengerProvider);
    }

    double gapUnder(WidgetTester tester, String text) =>
        height -
        tester
            .getRect(
              find
                  .ancestor(
                    of: find.text(text),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .bottom;

    testWidgets('is drawn above it', (tester) async {
      final messenger = await pumpBar(tester);

      messenger.show('Scan started');
      await tester.pumpAndSettle();

      expect(gapUnder(tester, 'Scan started'), greaterThanOrEqualTo(bar));
    });

    testWidgets('rests where it always has when it declines the lift', (
      tester,
    ) async {
      final messenger = await pumpBar(tester);

      messenger.show('Scan started', clearsBar: false);
      await tester.pumpAndSettle();

      expect(gapUnder(tester, 'Scan started'), 10);
    });

    testWidgets('follows it up as it comes and down as it goes', (
      tester,
    ) async {
      final shown = ValueNotifier(false);
      addTearDown(shown.dispose);
      final messenger = await pumpBar(tester, shown: shown);

      messenger.show('Scan started');
      await tester.pumpAndSettle();
      expect(gapUnder(tester, 'Scan started'), 10);

      shown.value = true;
      await tester.pumpAndSettle();
      expect(gapUnder(tester, 'Scan started'), greaterThanOrEqualTo(bar));

      shown.value = false;
      await tester.pumpAndSettle();
      expect(gapUnder(tester, 'Scan started'), 10);
    });

    testWidgets('moves nothing for a bar gone a frame and back', (
      tester,
    ) async {
      final shown = ValueNotifier(true);
      addTearDown(shown.dispose);
      final messenger = await pumpBar(tester, shown: shown);
      messenger.show('Scan started');
      await tester.pumpAndSettle();
      final placed = gapUnder(tester, 'Scan started');
      expect(placed, greaterThanOrEqualTo(bar));

      final drawn = <double>[];
      shown.value = false;
      await tester.pump();
      drawn.add(gapUnder(tester, 'Scan started'));
      shown.value = true;
      for (var i = 0; i < 5; i++) {
        await tester.pump();
        drawn.add(gapUnder(tester, 'Scan started'));
      }

      expect(drawn, everyElement(placed));
    });

    testWidgets('declining the lift, stays put as it comes and goes', (
      tester,
    ) async {
      final shown = ValueNotifier(false);
      addTearDown(shown.dispose);
      final messenger = await pumpBar(tester, shown: shown);

      messenger.show('Scan started', clearsBar: false);
      await tester.pumpAndSettle();
      shown.value = true;
      await tester.pumpAndSettle();

      expect(gapUnder(tester, 'Scan started'), 10);
    });
  });

  testWidgets('a message is drawn over a lone overlay', (tester) async {
    // A typed overlay location builds no shell beneath it.
    final container = _signedInContainer();
    await pumpWholeApp(tester, container: container);
    container.read(routerProvider).go(WaxRoute.queue);
    await tester.pumpAndSettle();
    expect(find.byType(AdaptiveShell), findsNothing);

    container.read(shellMessengerProvider).show('Could not restore');
    await tester.pumpAndSettle();

    expect(find.text('Could not restore'), findsOneWidget);
  });

  testWidgets('a bar up as the player opens over two visited tabs', (
    tester,
  ) async {
    // Each visited tab's top screen draws its own copy of the bar, under
    // the player as it opens; one is in sight once it is up.
    final container = _signedInContainer();
    await pumpWholeApp(tester, container: container);
    final router = container.read(routerProvider)..go(WaxRoute.health);
    await tester.pumpAndSettle();
    container.read(shellMessengerProvider).show('Scan started');
    await tester.pumpAndSettle();

    router.push<void>(WaxRoute.nowPlaying);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Scan started'), findsOneWidget);
  });

  testWidgets('an offer opens its shell screen from over the player', (
    tester,
  ) async {
    // The offer outlives the screen that raised it, so the player can be
    // over the shell by the time it is pressed, and a plain push from
    // under an overlay builds a second shell.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _user),
    );
    repo
      ..healthSummary = const HealthSummary(
        score: 90,
        totalItems: 4,
        evaluatedItems: 4,
        rules: [
          HealthRuleCount(
            rule: 'missing-art',
            label: 'Missing artwork',
            failing: 1,
            fixable: true,
          ),
        ],
      )
      ..fixHealthStart = const HealthFixStart(queued: 1, taskId: 'tk-fix');
    final container = appContainer(repo: repo);
    await pumpWholeApp(tester, container: container);
    final router = container.read(routerProvider)..go(WaxRoute.health);
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.healthFix('missing-art')),
    );
    await tester.pumpAndSettle();

    router.push<void>(WaxRoute.nowPlaying);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.openTasks));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.tasksScreen),
      findsOneWidget,
    );
    expect(find.byType(AdaptiveShell), findsOneWidget);
  });

  testWidgets('of pages one inside another, only the outermost draws a '
      'message', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: localizedHost(
          const ShellMessageHost(
            child: ShellMessageArea(
              child: ShellMessageArea(child: SizedBox.expand()),
            ),
          ),
          theme: buildWaxTheme(),
        ),
      ),
    );
    ProviderScope.containerOf(tester.element(find.byType(ShellMessageHost)))
        .read(shellMessengerProvider)
        .show('Scan started');
    await tester.pumpAndSettle();

    expect(find.byType(WaxMessageBar), findsOneWidget);
    final outer = find.byType(ShellMessageArea).first;
    expect(
      tester
          .element(find.byType(WaxMessageBar))
          .findAncestorWidgetOfExactType<ShellMessageArea>(),
      same(tester.widget(outer)),
    );
  });

  group('a message drawn in its page', () {
    /// The whole app on a phone, home showing, and a waiting offer up;
    /// how often its action ran.
    Future<ValueGetter<int>> offerOnHome(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = _signedInContainer();
      await pumpWholeApp(tester, container: container);
      var undone = 0;
      container
          .read(shellMessengerProvider)
          .show(
            'Marked finished',
            actionLabel: 'Undo',
            onAction: () => undone++,
            persist: true,
          );
      await tester.pumpAndSettle();
      return () => undone;
    }

    BuildContext home(WidgetTester tester) =>
        tester.element(find.byType(HomeScreen));

    testWidgets('is covered by a sheet opened over the page, which takes the '
        'press where the bar lies', (tester) async {
      final undone = await offerOnHome(tester);
      final bar = barOf(tester, 'Marked finished');
      var kept = 0;
      unawaited(
        showWaxSheet<void>(
          context: home(tester),
          builder: (context) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 120),
              WaxButton(label: 'Keep', expand: true, onPressed: () => kept++),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final under = bar.intersect(
        tester.getRect(find.widgetWithText(WaxButton, 'Keep')),
      );
      expect(under.height, greaterThan(0));
      await tester.tapAt(under.center);
      await tester.pumpAndSettle();
      expect(kept, 1);
      expect(undone(), 0);
    });

    testWidgets('is covered by a menu opened over the page, which takes the '
        'press where the bar lies', (tester) async {
      final undone = await offerOnHome(tester);
      final bar = barOf(tester, 'Marked finished');
      int? chosen;
      unawaited(
        showWaxMenu<int>(home(tester), const <WaxMenuItem<int>>[
          WaxMenuItem(value: 1, label: 'Pin'),
        ]).then((value) => chosen = value),
      );
      await tester.pumpAndSettle();

      final pin = tester.getCenter(find.text('Pin'));
      expect(bar.contains(pin), isTrue);
      await tester.tapAt(pin);
      await tester.pumpAndSettle();
      expect(chosen, 1);
      expect(undone(), 0);
    });

    /// The whole app on a phone, home showing.
    Future<ProviderContainer> onHome(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = _signedInContainer();
      await pumpWholeApp(tester, container: container);
      return container;
    }

    for (final (cover, open, close)
        in <(String, void Function(BuildContext), void Function(BuildContext))>[
          (
            'a sheet',
            (context) => unawaited(
              showWaxSheet<void>(
                context: context,
                builder: (context) => const SizedBox(height: 200),
              ),
            ),
            (context) => Navigator.of(context).pop(),
          ),
          (
            'a dialog',
            (context) => unawaited(
              showDialog<void>(
                context: context,
                builder: (context) => const Center(child: Text('Busy')),
              ),
            ),
            (context) => Navigator.of(context, rootNavigator: true).pop(),
          ),
        ]) {
      testWidgets('an offer raised under $cover waits out the cover, and is '
          'there to take once it closes', (tester) async {
        final container = await onHome(tester);
        open(home(tester));
        await tester.pumpAndSettle();
        var opened = 0;
        container
            .read(shellMessengerProvider)
            .show(
              'Similar tracks ready',
              actionLabel: 'Open',
              onAction: () => opened++,
            );
        // In, under the cover, and then well past its time.
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();

        close(home(tester));
        await tester.pumpAndSettle();
        expect(find.text('Similar tracks ready'), findsOneWidget);
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(opened, 1);
      });
    }

    testWidgets('a message up as a sheet opens keeps the time it had left '
        'for when the sheet closes', (tester) async {
      final container = await onHome(tester);
      container.read(shellMessengerProvider).show('Scan started');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));

      unawaited(
        showWaxSheet<void>(
          context: home(tester),
          builder: (context) => const SizedBox(height: 200),
        ),
      );
      await tester.pumpAndSettle();
      // Under its own time, which a message with no action waits at most.
      await tester.pump(const Duration(seconds: 2));
      Navigator.of(home(tester)).pop();
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Scan started'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();
      expect(find.text('Scan started'), findsNothing);
    });

    testWidgets('a message with no action covered past its own time is '
        'dropped as the cover closes, and one with an action still waits', (
      tester,
    ) async {
      final container = await onHome(tester);
      final messenger = container.read(shellMessengerProvider)
        ..show('Scan started');
      await tester.pumpAndSettle();
      unawaited(
        showWaxSheet<void>(
          context: home(tester),
          builder: (context) => const SizedBox(height: 200),
        ),
      );
      await tester.pumpAndSettle();
      var opened = 0;
      messenger
        ..show('Saved')
        ..show(
          'Similar tracks ready',
          actionLabel: 'Open',
          onAction: () => opened++,
        );
      await tester.pump(const Duration(seconds: 6));

      Navigator.of(home(tester)).pop();
      for (var i = 1; i <= 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        // Gone before the sheet is, so never read once it has.
        if (i >= 2) {
          for (final stale in <String>['Scan started', 'Saved']) {
            expect(
              find.text(stale, skipOffstage: false),
              findsNothing,
              reason: '$stale, ${i * 50} ms after the close',
            );
          }
        }
      }
      expect(find.text('Similar tracks ready'), findsOneWidget);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });

    testWidgets('an offer made to wait yields on time with its timers slowed, '
        'as in a tab in the background', (tester) async {
      final container = await onHome(tester);
      // A browser runs a background tab's timers about once a second.
      const second = Duration(seconds: 1);
      runZoned(
        () => container.read(shellMessengerProvider)
          ..show(
            'Marked finished',
            actionLabel: 'Undo',
            onAction: () {},
            persist: true,
          )
          ..show('Saved'),
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, f) => parent.createTimer(
            zone,
            duration < second ? second : duration,
            f,
          ),
          createPeriodicTimer: (self, parent, zone, period, f) => parent
              .createPeriodicTimer(zone, period < second ? second : period, f),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(second);
      }
      await tester.pumpAndSettle();

      expect(find.text('Marked finished'), findsNothing);
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets("is drawn on a page a dialog opens over the session's "
        'pages, and has its time there', (tester) async {
      final container = await onHome(tester);
      unawaited(
        showDialog<void>(
          context: home(tester),
          builder: (context) => const WaxScaffold(
            title: 'Pick a station',
            body: SizedBox(height: 200),
          ),
        ),
      );
      await tester.pumpAndSettle();
      container.read(shellMessengerProvider).show('Scan started');
      await tester.pumpAndSettle();

      final onDialog = find.descendant(
        of: find.ancestor(
          of: find.text('Pick a station'),
          matching: find.byType(WaxScaffold),
        ),
        matching: find.byType(WaxMessageBar),
      );
      expect(onDialog, findsOneWidget);
      expect(
        find.descendant(of: onDialog, matching: find.text('Scan started')),
        findsOneWidget,
      );
      // In front, so its time runs.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Scan started', skipOffstage: false), findsNothing);
    });

    testWidgets('is covered by a dialog, which takes the press where the bar '
        'lies', (tester) async {
      final undone = await offerOnHome(tester);
      final bar = barOf(tester, 'Marked finished');
      var kept = 0;
      unawaited(
        showDialog<void>(
          context: home(tester),
          builder: (context) => Stack(
            children: <Widget>[
              Positioned.fromRect(
                rect: bar,
                child: WaxButton(label: 'Keep', onPressed: () => kept++),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tapAt(
        tester.getCenter(find.widgetWithText(WaxButton, 'Keep')),
      );
      await tester.pumpAndSettle();
      expect(kept, 1);
      expect(undone(), 0);
    });

    testWidgets('is drawn inside each kind of page, car mode playing '
        'included', (tester) async {
      final container = _signedInContainer();
      await pumpWholeApp(tester, container: container, disableAnimations: true);
      container.read(nowPlayingProvider.notifier).play(
        [testItem('tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE', title: 'Kelp Line')],
        source: const QueueSource(
          kind: QueueSourceKind.single,
          label: 'Kelp Line',
        ),
      );
      await tester.pumpAndSettle();
      container
          .read(shellMessengerProvider)
          .show(
            'Marked finished',
            actionLabel: 'Undo',
            onAction: () {},
            persist: true,
          );
      await tester.pumpAndSettle();
      final router = container.read(routerProvider);
      void drawnIn(Type page) => expect(
        find.descendant(
          of: find.byType(page),
          matching: find.byType(WaxMessageBar),
        ),
        findsOneWidget,
        reason: '$page',
      );

      drawnIn(HomeScreen);
      router.go(WaxRoute.admin);
      await tester.pumpAndSettle();
      drawnIn(AdminDashboardScreen);
      for (final (location, page) in <(String, Type)>[
        (WaxRoute.nowPlaying, PlayerScreen),
        (WaxRoute.queue, QueueScreen),
        (WaxRoute.visualizer, VisualizerScreen),
        (WaxRoute.carMode, CarModeScreen),
      ]) {
        router.push<void>(location);
        await tester.pumpAndSettle();
        drawnIn(page);
        router.pop();
        await tester.pumpAndSettle();
      }
      expect(find.byType(WaxMessageBar), findsOneWidget);
      container.read(queueControllerProvider.notifier).clear();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('is one node to a screen reader however many pages under '
        'others hold it', (tester) async {
      final container = _signedInContainer();
      await pumpWholeApp(tester, container: container);
      final router = container.read(routerProvider)..go(WaxRoute.music);
      await tester.pumpAndSettle();
      router.go(WaxRoute.health);
      await tester.pumpAndSettle();
      container.read(shellMessengerProvider).show('Scan started');
      await tester.pumpAndSettle();
      router.push<void>(WaxRoute.nowPlaying);
      await tester.pumpAndSettle();

      var heard = 0;
      void visit(SemanticsNode node) {
        if (node.getSemanticsData().label == 'Scan started') heard++;
        node.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      visit(
        tester
            .binding
            .renderViews
            .first
            .owner!
            .semanticsOwner!
            .rootSemanticsNode!,
      );
      expect(heard, 1);
    });

    // Tab on an empty home from nothing focused, as the floating snack
    // bar was reached: the first press lands on the page's first
    // focusable, and the bar comes inside the page, before the chrome
    // under it.
    for (final (size, presses) in <(Size, int)>[
      (const Size(390, 844), 4),
      (const Size(1600, 1000), 3),
    ]) {
      testWidgets("puts a waiting offer's action $presses presses of Tab in "
          'at ${size.width.toInt()} wide', (tester) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final container = appContainer(
          repo: FakeRepository(
            sessionState: const SessionState(authenticated: true, user: _user),
          ),
        );
        await pumpWholeApp(tester, container: container);
        container
            .read(shellMessengerProvider)
            .show(
              'Marked finished',
              actionLabel: 'Undo',
              onAction: () {},
              persist: true,
            );
        await tester.pumpAndSettle();

        bool onAction() {
          final focused = FocusManager.instance.primaryFocus?.context;
          if (focused == null) return false;
          WaxButton? button;
          if (focused.widget case final WaxButton own) button = own;
          focused.visitAncestorElements((element) {
            if (element.widget case final WaxButton above) button ??= above;
            return button == null;
          });
          return button?.label == 'Undo';
        }

        bool inPage() {
          final focused = FocusManager.instance.primaryFocus?.context;
          final page = find.byType(HomeScreen).evaluate().single;
          var inside = false;
          focused?.visitAncestorElements((element) {
            inside = element == page;
            return !inside;
          });
          return inside;
        }

        Future<void> tab() async {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }

        await tab();
        expect(inPage(), isTrue);
        var pressed = 1;
        while (!onAction() && pressed < 40) {
          await tab();
          pressed++;
        }
        expect(pressed, presses);
      });
    }
  });

  group('a message on an index beside its letter rail', () {
    /// The whole app at [size] on the albums index, its rail shown, and a
    /// waiting offer up; how often its action ran.
    Future<ValueGetter<int>> offerOnIndex(
      WidgetTester tester,
      Size size,
    ) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = FakeRepository(
        sessionState: const SessionState(authenticated: true, user: _user),
      );
      repository.facets['album'] = [
        for (final name in ['Abba', 'Gullwing', 'Mogwai', 'Zebra'])
          FacetBucket(
            key: 'k$name',
            label: name,
            count: 3,
            entityPid: 'al-$name',
          ),
      ];
      final container = appContainer(repo: repository);
      await pumpWholeApp(tester, container: container);
      container
          .read(routerProvider)
          .go(WaxRoute.musicIndex(MusicDimension.albums));
      await tester.pumpAndSettle();
      expect(find.byType(FastScrollRail), findsOneWidget);
      var undone = 0;
      container
          .read(shellMessengerProvider)
          .show(
            'Marked finished',
            actionLabel: 'Undo',
            onAction: () => undone++,
            persist: true,
          );
      await tester.pumpAndSettle();
      return () => undone;
    }

    /// Every node a screen reader hears [label] from.
    List<SemanticsNode> labelled(WidgetTester tester, String label) {
      final found = <SemanticsNode>[];
      void visit(SemanticsNode node) {
        if (node.getSemanticsData().label == label) found.add(node);
        node.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      visit(
        tester
            .binding
            .renderViews
            .first
            .owner!
            .semanticsOwner!
            .rootSemanticsNode!,
      );
      return found;
    }

    for (final size in const <Size>[Size(390, 844), Size(1600, 1000)]) {
      testWidgets('is one node with its action, kept as a screen reader '
          'starts and stops reading, at ${size.width.round()} wide', (
        tester,
      ) async {
        final undone = await offerOnIndex(tester, size);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );

        (SemanticsNode, SemanticsNode) nodes() {
          final bar = labelled(tester, 'Marked finished');
          final action = labelled(tester, 'Undo');
          expect(bar, hasLength(1));
          expect(action, hasLength(1));
          expect(bar.single.getSemanticsData().flagsCollection.isHidden, false);
          expect(action.single.parent, same(bar.single));
          expect(
            semanticsRectOnScreen(bar.single),
            barOf(tester, 'Marked finished'),
          );
          return (bar.single, action.single);
        }

        final (bar, action) = nodes();
        // Android's bridge turns accessible navigation on with the first
        // node a reader asks for, and off as accessibility goes.
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(accessibleNavigation: true);
        await tester.pump();
        expect(nodes(), (bar, action), reason: 'a reader arriving');
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
        await tester.pump();
        expect(nodes(), (bar, action), reason: 'a reader leaving');

        tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
          action.id,
          SemanticsAction.tap,
        );
        await tester.pumpAndSettle();
        expect(undone(), 1);
      });

      testWidgets('is laid out clear of the rail, which draws nothing over '
          'it, at ${size.width.round()} wide', (tester) async {
        await offerOnIndex(tester, size);

        final bar = barOf(tester, 'Marked finished');
        final rail = tester.getRect(find.byType(FastScrollRail));
        expect(bar.overlaps(rail), isFalse, reason: 'bar $bar, rail $rail');
        final node = labelled(tester, 'Marked finished').single;
        for (final point in <Offset>[
          bar.centerLeft.translate(4, 0),
          bar.center,
          bar.centerRight.translate(-4, 0),
          bar.topRight.translate(-4, 4),
          bar.bottomRight.translate(-4, -4),
        ]) {
          final explored = touchExploredAt(tester, point);
          expect(
            explored == node || explored?.parent == node,
            isTrue,
            reason: 'explored at $point: $explored',
          );
        }
      });
    }
  });

  group('a message held through a page transition', () {
    const text = 'Marked finished';

    /// Every copy of the bar drawn on this frame, at the opacity it is
    /// drawn at, one out of sight or faded out altogether left out, and
    /// whether it is a page's own rather than one in flight between pages.
    List<({double opacity, bool onPage, Element element})> copies(
      WidgetTester tester,
    ) => [
      for (final element
          in find.byType(WaxMessageBar, skipOffstage: false).evaluate())
        if (_opacityOnStage(element) case final opacity? when opacity > 0)
          (
            element: element,
            opacity: opacity,
            onPage: find
                .ancestor(
                  of: find.byElementPredicate(
                    (candidate) => candidate == element,
                    skipOffstage: false,
                  ),
                  matching: find.byType(ShellMessageArea, skipOffstage: false),
                )
                .evaluate()
                .isNotEmpty,
          ),
    ];

    /// The opacity each copy of the bar is drawn at on this frame, one out
    /// of sight or faded out altogether left out.
    List<double> drawn(WidgetTester tester) => [
      for (final (:opacity, onPage: _, element: _) in copies(tester)) opacity,
    ];

    /// How many semantics nodes a screen reader hears [text] from, or the
    /// page whose identifier is [page].
    int heard(WidgetTester tester, {String? page}) {
      var heard = 0;
      void visit(SemanticsNode node) {
        final data = node.getSemanticsData();
        if (page == null ? data.label == text : data.identifier == page) {
          heard++;
        }
        node.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      visit(
        tester
            .binding
            .renderViews
            .first
            .owner!
            .semanticsOwner!
            .rootSemanticsNode!,
      );
      return heard;
    }

    /// The whole app at [size], at [at] if given, and a waiting offer up.
    Future<GoRouter> offerUp(
      WidgetTester tester,
      Size size, {
      String? at,
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = _signedInContainer();
      await pumpWholeApp(tester, container: container);
      final router = container.read(routerProvider);
      if (at != null) {
        router.go(at);
        await tester.pumpAndSettle();
      }
      container
          .read(shellMessengerProvider)
          .show(text, actionLabel: 'Undo', onAction: () {}, persist: true);
      await tester.pumpAndSettle();
      return router;
    }

    /// Runs [move] and reads every frame of what follows: the frames on
    /// which anything but one copy, drawn whole, is in sight, or the
    /// message is not one node to a screen reader.
    ///
    /// A push's first frame lays the incoming page out unseen, for its
    /// heroes to be measured, under its route's barrier, which hides
    /// [leaving], the page it covers, from a screen reader: the message
    /// may go unheard on that frame only, and only with that whole page,
    /// as Material's snack bar did.
    ///
    /// [count] frames 50 ms apart, then settled unless [settle] is false,
    /// for a move another cuts short.
    ///
    /// [landing], the page a move comes back to under an overlay closing
    /// over it, as that page's own content is: its copy, and no other, is
    /// drawn at the page's opacity as the page fades in, and heard only
    /// once the overlay's barrier lets the page be heard at all.
    Future<List<String>> through(
      WidgetTester tester,
      String name,
      VoidCallback move, {
      String? leaving,
      String? landing,
      int count = 20,
      bool settle = true,
    }) async {
      final wrong = <String>[];
      move();
      for (var i = 1; i <= count; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final drawn = copies(tester);
        final nodes = heard(tester);
        final landed =
            landing != null &&
            drawn.length == 1 &&
            drawn.single.onPage &&
            _within(drawn.single.element, landing);
        final unseen =
            nodes == 0 &&
            (i == 1 && leaving != null && heard(tester, page: leaving) == 0 ||
                landed && heard(tester, page: landing) == 0);
        final whole =
            drawn.length == 1 && (drawn.single.opacity == 1 || landed);
        if (!whole || nodes != 1 && !unseen) {
          final at = [
            for (final copy in drawn)
              '${copy.opacity.toStringAsFixed(2)}'
                  '${copy.onPage ? '' : ' flying'}',
          ];
          wrong.add('$name ${i * 50} ms: drawn at $at, heard $nodes');
        }
      }
      if (settle) await tester.pumpAndSettle();
      return wrong;
    }

    for (final size in <Size>[const Size(390, 844), const Size(1600, 1000)]) {
      final wide = size.width.toInt();

      // A door from over the player pops the player and moves inside the
      // shell in one frame, two flights to one page; going back before
      // they land reverses the inner one only.
      for (final (name, at, page, door, back)
          in <
            (
              String,
              String,
              String,
              void Function(GoRouter),
              void Function(GoRouter),
            )
          >[
            (
              'a screen pushed in the shell over the review surface',
              WaxRoute.review,
              SemanticsIds.adminReview,
              (router) => unawaited(
                router.pushInShell<void>(WaxRoute.metadata(_track)),
              ),
              (router) => router.pop(),
            ),
            (
              'a screen pushed in the shell over the admin console',
              WaxRoute.admin,
              SemanticsIds.adminDashboard,
              (router) => unawaited(
                router.pushInShell<void>(WaxRoute.metadata(_track)),
              ),
              (router) => router.pop(),
            ),
            (
              'a deeper location in a built branch',
              WaxRoute.settings,
              SemanticsIds.settingsScreen,
              (router) => router.go(WaxRoute.settingsAbout),
              (router) => router.go(WaxRoute.settings),
            ),
          ]) {
        for (final cut in <int>[100, 300]) {
          testWidgets('one copy and one node as $name from over the player '
              'is gone back from $cut ms in, at $wide wide', (tester) async {
            final router = await offerUp(tester, size, at: at);
            router.push<void>(WaxRoute.nowPlaying);
            await tester.pumpAndSettle();

            final wrong = [
              ...await through(
                tester,
                'door',
                () => door(router),
                count: cut ~/ 50,
                settle: false,
              ),
              ...await through(
                tester,
                'back',
                () => back(router),
                // Only a Back this early outruns the flight to the screen
                // it pops, leaving the bar to the page under the player.
                landing: cut == 100 ? page : null,
              ),
            ];

            expect(wrong, isEmpty, reason: wrong.join('\n'));
            expect(tester.takeException(), isNull);
            expect(drawn(tester), [1.0]);
          });
        }
      }

      testWidgets('one copy and one node as the player opens while a drill-in '
          'is still flying, at $wide wide', (tester) async {
        final router = await offerUp(tester, size, at: WaxRoute.settings);

        final wrong = [
          ...await through(
            tester,
            'in',
            () => router.go(WaxRoute.settingsDefects),
            count: 2,
            settle: false,
            leaving: SemanticsIds.settingsScreen,
          ),
          ...await through(
            tester,
            'player',
            () => router.push<void>(WaxRoute.nowPlaying),
            leaving: SemanticsIds.defectsScreen,
          ),
        ];

        expect(wrong, isEmpty, reason: wrong.join('\n'));
        expect(tester.takeException(), isNull);
        expect(drawn(tester), [1.0]);
      });

      testWidgets('one copy and one node as another tab is gone to while a '
          'door is in the air, at $wide wide', (tester) async {
        final router = await offerUp(tester, size, at: WaxRoute.admin);
        router.push<void>(WaxRoute.nowPlaying);
        await tester.pumpAndSettle();

        final wrong = [
          ...await through(
            tester,
            'door',
            () =>
                unawaited(router.pushInShell<void>(WaxRoute.metadata(_track))),
            count: 4,
            settle: false,
          ),
          ...await through(tester, 'home', () => router.go(WaxRoute.home)),
        ];

        expect(wrong, isEmpty, reason: wrong.join('\n'));
        expect(tester.takeException(), isNull);
        expect(drawn(tester), [1.0]);
        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('one copy and one node while the player opens over home '
          'and closes, at $wide wide', (tester) async {
        final router = await offerUp(tester, size);

        final wrong = [
          ...await through(
            tester,
            'push',
            () => router.push<void>(WaxRoute.nowPlaying),
            leaving: SemanticsIds.homeScreen,
          ),
          ...await through(tester, 'pop', router.pop),
        ];

        expect(wrong, isEmpty, reason: wrong.join('\n'));
        expect(tester.takeException(), isNull);
        expect(drawn(tester), [1.0]);
      });

      testWidgets('one copy and one node through a drill-in inside a branch '
          'and back, at $wide wide', (tester) async {
        final router = await offerUp(tester, size, at: WaxRoute.settings);

        final wrong = [
          ...await through(
            tester,
            'in',
            () => router.go(WaxRoute.settingsAbout),
            leaving: SemanticsIds.settingsScreen,
          ),
          ...await through(tester, 'out', () => router.go(WaxRoute.settings)),
        ];

        expect(wrong, isEmpty, reason: wrong.join('\n'));
        expect(tester.takeException(), isNull);
        expect(drawn(tester), [1.0]);
      });

      testWidgets('its copy in sight on a tab the player closed over while '
          'another tab showed, at $wide wide', (tester) async {
        final router = await offerUp(tester, size);
        router.push<void>(WaxRoute.nowPlaying);
        await tester.pumpAndSettle();

        router.go(WaxRoute.music);
        await tester.pumpAndSettle();
        expect(drawn(tester), [1.0]);
        router.go(WaxRoute.home);
        // From the frame that shows the tab.
        for (var i = 1; i <= 3; i++) {
          await tester.pump();
          expect(drawn(tester), [1.0], reason: 'frame $i');
          expect(heard(tester), 1, reason: 'frame $i');
        }
        await tester.pumpAndSettle();

        expect(drawn(tester), [1.0]);
        expect(heard(tester), 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets('its copy drawn once a tab the player closed over, shown '
          'again under a dialog, comes to the front, at $wide wide', (
        tester,
      ) async {
        final router = await offerUp(tester, size);
        router.push<void>(WaxRoute.nowPlaying);
        await tester.pumpAndSettle();
        router.go(WaxRoute.music);
        await tester.pumpAndSettle();
        unawaited(
          showDialog<void>(
            context: tester.element(find.byType(MusicHubScreen)),
            builder: (context) => const Center(child: Text('Busy')),
          ),
        );
        await tester.pumpAndSettle();
        router.go(WaxRoute.home);
        await tester.pumpAndSettle();

        Navigator.of(
          tester.element(find.byType(HomeScreen)),
          rootNavigator: true,
        ).pop();
        // From the frame that brings the tab to the front.
        for (var i = 1; i <= 3; i++) {
          await tester.pump();
          expect(drawn(tester), [1.0], reason: 'frame $i');
        }
        await tester.pumpAndSettle();

        expect(drawn(tester), [1.0]);
        expect(heard(tester), 1);
        expect(find.text('Undo'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      for (final (name, at, page) in <(String, String, String)>[
        ('the admin console', WaxRoute.admin, SemanticsIds.adminDashboard),
        ('the review surface', WaxRoute.review, SemanticsIds.adminReview),
      ]) {
        testWidgets('one copy and one node through a screen pushed over '
            '$name, the player over it, and back, at $wide wide', (
          tester,
        ) async {
          final router = await offerUp(tester, size, at: at);

          final wrong = [
            ...await through(
              tester,
              'over',
              () => router.push<void>(WaxRoute.metadata(_track)),
              leaving: page,
            ),
            ...await through(
              tester,
              'player',
              () => router.push<void>(WaxRoute.nowPlaying),
              leaving: SemanticsIds.metadataEditor,
            ),
            ...await through(tester, 'player off', router.pop),
            ...await through(tester, 'back', router.pop),
          ];

          expect(wrong, isEmpty, reason: wrong.join('\n'));
          expect(tester.takeException(), isNull);
          expect(drawn(tester), [1.0]);
        });

        testWidgets('one copy and one node as a screen is pushed in the '
            'shell over $name from over the player, at $wide wide', (
          tester,
        ) async {
          final router = await offerUp(tester, size, at: at);
          router.push<void>(WaxRoute.nowPlaying);
          await tester.pumpAndSettle();

          final wrong = [
            ...await through(
              tester,
              'door',
              () => unawaited(
                router.pushInShell<void>(WaxRoute.metadata(_track)),
              ),
            ),
            ...await through(tester, 'back', router.pop),
          ];

          expect(wrong, isEmpty, reason: wrong.join('\n'));
          expect(tester.takeException(), isNull);
          expect(drawn(tester), [1.0]);
        });
      }

      testWidgets('one copy and one node as a deeper location in a built '
          'branch is gone to from over the player, at $wide wide', (
        tester,
      ) async {
        final router = await offerUp(tester, size, at: WaxRoute.settings);
        router.push<void>(WaxRoute.nowPlaying);
        await tester.pumpAndSettle();

        final wrong = [
          ...await through(
            tester,
            'go',
            () => router.go(WaxRoute.settingsAbout),
          ),
          ...await through(tester, 'out', () => router.go(WaxRoute.settings)),
        ];

        expect(wrong, isEmpty, reason: wrong.join('\n'));
        expect(tester.takeException(), isNull);
        expect(drawn(tester), [1.0]);
      });
    }

    for (final (pop, push) in <(int, int)>[
      (500, 150),
      (150, 500),
      (300, 300),
    ]) {
      testWidgets('one copy through a pop over a page and a push inside it '
          'in one frame, a pop of $pop ms and a push of $push ms', (
        tester,
      ) async {
        // As a door from over the player, with either move ending first,
        // in the app's shape: the page that holds the inner navigator is
        // no place for messages, the pages on either navigator are.
        final outer = GlobalKey<NavigatorState>();
        final inner = GlobalKey<NavigatorState>();
        final heroes = [
          for (var i = 0; i < 2; i++)
            MaterialApp.createMaterialHeroController(),
        ];
        for (final controller in heroes) {
          addTearDown(controller.dispose);
        }
        Route<void> page(Widget content, int ms) => PageRouteBuilder<void>(
          transitionDuration: Duration(milliseconds: ms),
          reverseTransitionDuration: Duration(milliseconds: ms),
          pageBuilder: (context, animation, secondary) => content,
        );
        const screen = ShellMessageArea(child: SizedBox.expand());
        await tester.pumpWidget(
          ProviderScope(
            child: localizedHost(
              ShellMessageHost(
                child: HeroControllerScope(
                  controller: heroes[0],
                  child: Navigator(
                    key: outer,
                    onGenerateRoute: (_) => page(
                      ShellMessageNest(
                        child: HeroControllerScope(
                          controller: heroes[1],
                          child: Navigator(
                            key: inner,
                            onGenerateRoute: (_) => page(screen, 100),
                          ),
                        ),
                      ),
                      100,
                    ),
                  ),
                ),
              ),
              theme: buildWaxTheme(),
            ),
          ),
        );
        ProviderScope.containerOf(tester.element(find.byType(ShellMessageHost)))
            .read(shellMessengerProvider)
            .show(text, actionLabel: 'Undo', onAction: () {}, persist: true);
        await tester.pumpAndSettle();
        unawaited(outer.currentState!.push(page(screen, pop)));
        await tester.pumpAndSettle();
        expect(drawn(tester), [1.0]);
        // A copy on each navigator's page, each a hero of its own.
        expect(
          find.byType(WaxMessageBar, skipOffstage: false),
          findsNWidgets(2),
        );

        outer.currentState!.pop();
        unawaited(inner.currentState!.push(page(screen, push)));
        final wrong = <String>[];
        for (var i = 1; i <= 14; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          final copies = drawn(tester);
          if (copies.length != 1 || copies.single != 1) {
            wrong.add('${i * 50} ms: drawn at $copies');
          }
        }
        await tester.pumpAndSettle();

        expect(wrong, isEmpty, reason: wrong.join('\n'));
        expect(tester.takeException(), isNull);
        expect(drawn(tester), [1.0]);
      });
    }
  });

  group('a message outside the session', () {
    /// Whether [page] draws a copy of the bar, in sight or not.
    bool drawsOn(Type page) => find
        .descendant(
          of: find.byType(page, skipOffstage: false),
          matching: find.byType(WaxMessageBar, skipOffstage: false),
          skipOffstage: false,
        )
        .evaluate()
        .isNotEmpty;

    /// The messenger [page] raises through, as a public page does.
    ShellMessenger raisedOn(WidgetTester tester, Type page) =>
        ShellMessenger.of(tester.element(find.byType(page)));

    testWidgets('is drawn on each sign-in screen, in a page of its own', (
      tester,
    ) async {
      final container = appContainer(repo: FakeRepository());
      await pumpWholeApp(tester, container: container);
      final router = container.read(routerProvider);

      for (final (location, page) in <(String, Type)>[
        (WaxRoute.login, LoginScreen),
        (WaxRoute.signup, SignupScreen),
        (WaxRoute.serverConnect, ConnectServerScreen),
      ]) {
        router.go(location);
        await tester.pumpAndSettle();
        raisedOn(tester, page).show('Could not reach the server');
        await tester.pumpAndSettle();
        expect(drawsOn(page), isTrue, reason: '$page');
        expect(find.text('Could not reach the server'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.byType(WaxMessageBar), findsNothing);
      }
    });

    testWidgets('is drawn on the setup screen', (tester) async {
      final container = appContainer(
        repo: FakeRepository(bootstrapNeeded: true),
      );
      await pumpWholeApp(tester, container: container);
      expect(find.byType(SetupScreen), findsOneWidget);

      raisedOn(tester, SetupScreen).show('Could not reach the server');
      await tester.pumpAndSettle();

      expect(drawsOn(SetupScreen), isTrue);
    });

    testWidgets('up as the session ends goes with it, never drawn on the '
        'sign-in screen', (tester) async {
      final container = _signedInContainer();
      await pumpWholeApp(tester, container: container);
      container
          .read(shellMessengerProvider)
          .show(
            'Marked finished',
            actionLabel: 'Undo',
            onAction: () {},
            persist: true,
          );
      await tester.pumpAndSettle();

      await container.read(authControllerProvider.notifier).signOutLocally();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(drawsOn(LoginScreen), isFalse, reason: '${i * 50 + 50} ms');
      }
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Marked finished', skipOffstage: false), findsNothing);
      // The sign-in screen's own messages are drawn there.
      raisedOn(tester, LoginScreen).show('Signed out');
      await tester.pumpAndSettle();
      expect(drawsOn(LoginScreen), isTrue);
      expect(find.text('Marked finished', skipOffstage: false), findsNothing);
    });

    testWidgets('up on the sign-in screen as a session begins goes with that '
        'screen, never drawn in the session or after it', (tester) async {
      final container = appContainer(repo: FakeRepository());
      await pumpWholeApp(tester, container: container);
      raisedOn(tester, LoginScreen).show(
        'Could not reach the server',
        actionLabel: 'Retry',
        onAction: () {},
        persist: true,
      );
      await tester.pumpAndSettle();
      expect(drawsOn(LoginScreen), isTrue);

      await container
          .read(authControllerProvider.notifier)
          .login(username: 'admin', password: 'hunter22');
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Could not reach the server'), findsNothing);

      await container.read(authControllerProvider.notifier).signOutLocally();
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        find.text('Could not reach the server', skipOffstage: false),
        findsNothing,
      );
    });

    for (final (name, overlay) in <(String, String)>[
      ('the player', WaxRoute.nowPlaying),
      ('the queue', WaxRoute.queue),
    ]) {
      for (final size in <Size>[const Size(390, 844), const Size(1600, 1000)]) {
        testWidgets('up over $name as the session ends, leaves with it and '
            'starts no flight across its edge, at ${size.width.toInt()} '
            'wide', (tester) async {
          tester.view
            ..physicalSize = size
            ..devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final container = _signedInContainer();
          await pumpWholeApp(tester, container: container);
          container
              .read(shellMessengerProvider)
              .show(
                'Marked finished',
                actionLabel: 'Undo',
                onAction: () {},
                persist: true,
              );
          await tester.pumpAndSettle();
          container.read(routerProvider).push<void>(overlay);
          await tester.pumpAndSettle();

          await container
              .read(authControllerProvider.notifier)
              .signOutLocally();
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.byType(LoginScreen), findsOneWidget);
          expect(
            find.text('Marked finished', skipOffstage: false),
            findsNothing,
          );
        });
      }
    }

    testWidgets("a session's message answered after it ended is drawn "
        'nowhere, the sign-in screen included', (tester) async {
      final repo = _HeldRematch();
      final container = appContainer(repo: repo);
      await pumpWholeApp(tester, container: container);
      container.read(routerProvider).go(WaxRoute.metadata(_track));
      await tester.pumpAndSettle();
      final rematch = find.bySemanticsIdentifier(SemanticsIds.metadataRematch);
      await tester.ensureVisible(rematch);
      await tester.pumpAndSettle();
      await tester.tap(rematch);
      await tester.pump();

      await container.read(authControllerProvider.notifier).signOutLocally();
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      repo.answer.complete();
      await tester.pumpAndSettle();

      expect(repo.rematchCalls, [_track]);
      expect(
        find.text('Queued for identification', skipOffstage: false),
        findsNothing,
      );
      expect(drawsOn(LoginScreen), isFalse);
    });

    testWidgets('raised in a dialog or a sheet a sign-in screen opens, is '
        'drawn on that screen', (tester) async {
      final container = appContainer(repo: FakeRepository());
      await pumpWholeApp(tester, container: container);
      BuildContext login() => tester.element(find.byType(LoginScreen));

      late BuildContext inDialog;
      unawaited(
        showDialog<void>(
          context: login(),
          builder: (context) {
            inDialog = context;
            return const Center(child: Text('Pick a server'));
          },
        ),
      );
      await tester.pumpAndSettle();
      ShellMessenger.of(inDialog).show('Could not reach the server');
      await tester.pumpAndSettle();
      // On the page, under the dialog that raised it, and there once it
      // closes.
      expect(drawsOn(LoginScreen), isTrue);
      Navigator.of(inDialog).pop();
      await tester.pumpAndSettle();
      expect(find.text('Could not reach the server'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      late BuildContext inSheet;
      unawaited(
        showWaxSheet<void>(
          context: login(),
          builder: (context) {
            inSheet = context;
            return const SizedBox(height: 200);
          },
        ),
      );
      await tester.pumpAndSettle();
      ShellMessenger.of(inSheet).show('Server saved');
      await tester.pumpAndSettle();
      Navigator.of(inSheet).pop();
      await tester.pumpAndSettle();
      expect(find.text('Server saved'), findsOneWidget);
      expect(drawsOn(LoginScreen), isTrue);
    });

    for (final (how, change)
        in <
          (
            String,
            Future<void> Function(
              WidgetTester,
              ProviderContainer,
              FakeRepository,
            ),
          )
        >[
          (
            'the session is replaced by another account',
            (tester, container, repo) async {
              repo.sessionState = const SessionState(
                authenticated: true,
                user: WaxDeckUser(id: 'us-2', username: 'ben', roles: ['user']),
              );
              // It waits on the frames that take the last session down.
              unawaited(
                container
                    .read(authControllerProvider.notifier)
                    .refreshSession(),
              );
            },
          ),
          (
            'it signs out and another account signs in',
            (tester, container, repo) async {
              await container
                  .read(authControllerProvider.notifier)
                  .signOutLocally();
              await tester.pumpAndSettle();
              expect(find.byType(LoginScreen), findsOneWidget);
              repo.sessionState = const SessionState(
                authenticated: true,
                user: WaxDeckUser(id: 'us-2', username: 'ben', roles: ['user']),
              );
              await container
                  .read(authControllerProvider.notifier)
                  .login(username: 'ben', password: 'hunter22');
            },
          ),
        ]) {
      testWidgets("one account's message answered after $how is drawn "
          "nowhere in the next account's session", (tester) async {
        final repo = _HeldRematch();
        final container = appContainer(repo: repo);
        await pumpWholeApp(tester, container: container);
        container.read(routerProvider).go(WaxRoute.metadata(_track));
        await tester.pumpAndSettle();
        final rematch = find.bySemanticsIdentifier(
          SemanticsIds.metadataRematch,
        );
        await tester.ensureVisible(rematch);
        await tester.pumpAndSettle();
        await tester.tap(rematch);
        await tester.pump();

        await change(tester, container, repo);
        await tester.pumpAndSettle();
        final next = container.read(signedInAccountProvider);
        expect(next, isNotNull);
        expect(next, isNot(_user.id));
        repo.answer.complete();
        await tester.pumpAndSettle();

        expect(repo.rematchCalls, [_track]);
        expect(
          find.text('Queued for identification', skipOffstage: false),
          findsNothing,
        );
        // The next account's own words are drawn.
        container.read(shellMessengerProvider).show('Scan started');
        await tester.pumpAndSettle();
        expect(find.text('Scan started'), findsOneWidget);
      });
    }

    testWidgets('raised on the sign-in screen with its answer after the '
        'session began, is drawn nowhere in it', (tester) async {
      final container = appContainer(repo: FakeRepository());
      await pumpWholeApp(tester, container: container);
      final hoisted = raisedOn(tester, LoginScreen);

      await container
          .read(authControllerProvider.notifier)
          .login(username: 'admin', password: 'hunter22');
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      hoisted.show('Could not reach the server');
      await tester.pumpAndSettle();

      expect(
        find.text('Could not reach the server', skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets('is drawn on the boot splash while the session is read', (
      tester,
    ) async {
      final repo = FakeRepository(
        sessionState: const SessionState(authenticated: true, user: _user),
      );
      final gate = repo.getSessionGate = Completer<void>();
      final container = appContainer(repo: repo);
      await pumpWholeApp(tester, container: container);
      expect(find.byType(WaxWordmark), findsOneWidget);

      ShellMessenger.of(tester.element(find.byType(WaxWordmark)))
          .show('Could not reach the server');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Could not reach the server'), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(
        find.text('Could not reach the server', skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets("up as another account's session arrives goes with the "
        'last one, never drawn for the next', (tester) async {
      final repo = FakeRepository(
        sessionState: const SessionState(authenticated: true, user: _user),
        items: [testItem(_track)],
      );
      final container = appContainer(repo: repo);
      await pumpWholeApp(tester, container: container);
      container
          .read(shellMessengerProvider)
          .show(
            'Marked finished',
            actionLabel: 'Undo',
            onAction: () {},
            persist: true,
          );
      await tester.pumpAndSettle();

      repo.sessionState = const SessionState(
        authenticated: true,
        user: WaxDeckUser(id: 'us-2', username: 'ben', roles: ['user']),
      );
      unawaited(
        container.read(authControllerProvider.notifier).refreshSession(),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(drawsOn(LoginScreen), isFalse, reason: '${i * 50 + 50} ms');
      }
      await tester.pumpAndSettle();

      expect(container.read(signedInAccountProvider), 'us-2');
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Marked finished', skipOffstage: false), findsNothing);
    });

    testWidgets("one account's late withdrawal takes back nothing in the "
        "next account's session", (tester) async {
      final repo = FakeRepository(
        sessionState: const SessionState(authenticated: true, user: _user),
        items: [testItem(_track)],
      );
      final container = appContainer(repo: repo);
      await pumpWholeApp(tester, container: container);
      final ended = container.read(shellMessengerProvider);

      repo.sessionState = const SessionState(
        authenticated: true,
        user: WaxDeckUser(id: 'us-2', username: 'ben', roles: ['user']),
      );
      unawaited(
        container.read(authControllerProvider.notifier).refreshSession(),
      );
      await tester.pumpAndSettle();
      expect(container.read(signedInAccountProvider), 'us-2');
      container
          .read(shellMessengerProvider)
          .show(
            'Decided 1 entry',
            actionLabel: 'Undo',
            onAction: () {},
            channel: ShellChannel.review,
            subject: 'rv-1',
            persist: true,
          );
      await tester.pumpAndSettle();
      expect(find.text('Decided 1 entry'), findsOneWidget);

      ended.withdraw(ShellChannel.review, 'rv-1');
      await tester.pumpAndSettle();

      expect(find.text('Decided 1 entry'), findsOneWidget);
      // The session's own still takes it back.
      container
          .read(shellMessengerProvider)
          .withdraw(ShellChannel.review, 'rv-1');
      await tester.pumpAndSettle();
      expect(find.text('Decided 1 entry'), findsNothing);
    });
  });

  group('a run of messages', () {
    Future<ShellMessenger> pumpMessenger(WidgetTester tester) async {
      final container = _signedInContainer();
      await pumpWholeApp(tester, container: container);
      return container.read(shellMessengerProvider);
    }

    Future<void> outlast(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    }

    testWidgets('replaces its own bar on screen', (tester) async {
      final messenger = await pumpMessenger(tester);

      messenger.show('Unpinned Blue Train', channel: ShellChannel.pins);
      await tester.pumpAndSettle();
      messenger.show('Unpinned Kind of Blue', channel: ShellChannel.pins);
      await tester.pumpAndSettle();

      expect(find.text('Unpinned Blue Train'), findsNothing);
      expect(find.text('Unpinned Kind of Blue'), findsOneWidget);
    });

    testWidgets('waits behind another bar as its newest word', (tester) async {
      final messenger = await pumpMessenger(tester);

      messenger.show('Could not save');
      await tester.pumpAndSettle();
      messenger.show('Unpinned Blue Train', channel: ShellChannel.pins);
      await tester.pump();
      messenger.show('Unpinned Kind of Blue', channel: ShellChannel.pins);
      await tester.pumpAndSettle();

      expect(find.text('Could not save'), findsOneWidget);
      await outlast(tester);
      expect(find.text('Could not save'), findsNothing);
      expect(find.text('Unpinned Kind of Blue'), findsOneWidget);
      await outlast(tester);
      expect(find.text('Unpinned Blue Train'), findsNothing);
    });

    testWidgets('an offer made to wait stays until it is answered', (
      tester,
    ) async {
      final messenger = await pumpMessenger(tester);

      messenger.show(
        'Marked finished',
        actionLabel: 'Undo',
        onAction: () {},
        persist: true,
      );
      await tester.pumpAndSettle();
      await outlast(tester);
      expect(find.text('Marked finished'), findsOneWidget);

      // The next message takes its place rather than waiting behind it.
      messenger.show('Scan started');
      await tester.pumpAndSettle();
      expect(find.text('Marked finished'), findsNothing);
      expect(find.text('Scan started'), findsOneWidget);
    });

    testWidgets('under accessible navigation every offer stays', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final messenger = await pumpMessenger(tester);

      messenger.show(
        'Added 2 tracks to the queue',
        actionLabel: 'Open',
        onAction: () {},
      );
      await tester.pumpAndSettle();
      await outlast(tester);
      expect(find.text('Added 2 tracks to the queue'), findsOneWidget);
    });

    testWidgets('an offer made to wait yields only after its time', (
      tester,
    ) async {
      final messenger = await pumpMessenger(tester);

      messenger.show(
        'Identifying 2 files',
        actionLabel: 'Open review',
        onAction: () {},
        persist: true,
      );
      await tester.pump();
      messenger.show('Skipped 1 Audible file');
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Identifying 2 files'), findsOneWidget);

      await outlast(tester);
      expect(find.text('Identifying 2 files'), findsNothing);
      expect(find.text('Skipped 1 Audible file'), findsOneWidget);
    });

    testWidgets('an answered offer lets the next message on', (tester) async {
      final messenger = await pumpMessenger(tester);
      var undone = false;

      messenger.show(
        'Restored Kind of Blue',
        actionLabel: 'Undo',
        onAction: () => undone = true,
      );
      await tester.pump();
      messenger.show('Scan started');
      await tester.pumpAndSettle();
      expect(find.text('Scan started'), findsNothing);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(undone, isTrue);
      expect(find.text('Scan started'), findsOneWidget);
    });

    testWidgets('an offer that waited its turn yields to the next', (
      tester,
    ) async {
      final messenger = await pumpMessenger(tester);

      messenger.show('Saved');
      await tester.pump();
      messenger.show(
        'Marked finished',
        actionLabel: 'Undo',
        onAction: () {},
        persist: true,
      );
      await tester.pump();
      messenger.show('Could not sync');
      await tester.pumpAndSettle();

      await outlast(tester);
      expect(find.text('Marked finished'), findsOneWidget);
      await outlast(tester);
      expect(find.text('Marked finished'), findsNothing);
      expect(find.text('Could not sync'), findsOneWidget);
    });

    testWidgets('an offer answers one press', (tester) async {
      final messenger = await pumpMessenger(tester);
      var undone = 0;

      messenger.show(
        'Restored Kind of Blue',
        actionLabel: 'Undo',
        onAction: () => undone++,
        persist: true,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(undone, 1);
    });

    testWidgets('a waiting offer leaves with the session', (tester) async {
      final container = _signedInContainer();
      await pumpWholeApp(tester, container: container);

      container
          .read(shellMessengerProvider)
          .show(
            'Marked finished',
            actionLabel: 'Undo',
            onAction: () {},
            persist: true,
          );
      await tester.pumpAndSettle();
      expect(find.text('Marked finished'), findsOneWidget);

      await container.read(authControllerProvider.notifier).signOutLocally();
      await tester.pumpAndSettle();
      expect(find.byType(AdaptiveShell), findsNothing);
      expect(find.text('Marked finished'), findsNothing);
    });

    testWidgets('a message is drawn on a page with no Scaffold, and holds up '
        'nothing', (tester) async {
      // As over car mode's playing face, whose page is an area with no
      // Scaffold under it.
      await tester.pumpWidget(
        ProviderScope(
          child: localizedHost(
            const ShellMessageHost(
              child: ShellMessageArea(child: SizedBox.expand()),
            ),
            theme: buildWaxTheme(),
          ),
        ),
      );
      final messenger = ProviderScope.containerOf(
        tester.element(find.byType(ShellMessageHost)),
      ).read(shellMessengerProvider);

      messenger.show('Skipped 1 unplayable track');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Skipped 1 unplayable track'), findsOneWidget);

      messenger.show('Scan started');
      await outlast(tester);
      expect(find.text('Skipped 1 unplayable track'), findsNothing);
      expect(find.text('Scan started'), findsOneWidget);
    });

    testWidgets('with no page under the host a message is drawn nowhere, and '
        'still has its time', (tester) async {
      final page = ValueNotifier(false);
      addTearDown(page.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: localizedHost(
            ShellMessageHost(
              child: ValueListenableBuilder<bool>(
                valueListenable: page,
                builder: (context, on, _) => on
                    ? const ShellMessageArea(child: SizedBox.expand())
                    : const SizedBox.expand(),
              ),
            ),
            theme: buildWaxTheme(),
          ),
        ),
      );
      final messenger = ProviderScope.containerOf(
        tester.element(find.byType(ShellMessageHost)),
      ).read(shellMessengerProvider);

      messenger.show('Skipped 1 unplayable track');
      await tester.pump();
      messenger.show('Scan started');
      await tester.pumpAndSettle();
      expect(find.byType(WaxMessageBar), findsNothing);

      await outlast(tester);
      page.value = true;
      await tester.pumpAndSettle();
      expect(find.text('Skipped 1 unplayable track'), findsNothing);
      expect(find.text('Scan started'), findsOneWidget);
    });

    testWidgets('an interruption takes the bar at once, and what it '
        'interrupted comes back after it', (tester) async {
      final messenger = await pumpMessenger(tester);
      const warning = 'a.flac: the tags could not be written';

      messenger.show(warning);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      messenger.show(
        'Decided 1 entry',
        actionLabel: 'Undo',
        onAction: () {},
        channel: ShellChannel.review,
        interrupts: true,
      );
      await tester.pumpAndSettle();
      expect(find.text('Decided 1 entry'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(find.text(warning), findsNothing);

      await outlast(tester);
      expect(find.text('Decided 1 entry'), findsNothing);
      expect(find.text(warning), findsOneWidget);
      // Its whole time again: it was drawn afresh.
      await tester.pump(const Duration(seconds: 3));
      expect(find.text(warning), findsOneWidget);
      await outlast(tester);
      expect(find.text(warning), findsNothing);
    });

    testWidgets('interruptions in a row lose nothing', (tester) async {
      final messenger = await pumpMessenger(tester);
      final drawn = <String>[];
      void note() {
        for (final text in ['Saved', 'Could not sync', 'Undone', 'Pinned']) {
          if (find.text(text).evaluate().isNotEmpty &&
              (drawn.isEmpty || drawn.last != text)) {
            drawn.add(text);
          }
        }
      }

      messenger.show('Saved');
      await tester.pumpAndSettle();
      note();
      messenger.show('Undone', channel: ShellChannel.review, interrupts: true);
      await tester.pumpAndSettle();
      note();
      // One waiting behind them, and a second interruption over the first.
      messenger.show('Could not sync');
      await tester.pump();
      messenger.show('Pinned', channel: ShellChannel.pins, interrupts: true);
      await tester.pumpAndSettle();
      note();
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        note();
      }

      expect(drawn, [
        'Saved',
        'Undone',
        'Pinned',
        'Undone',
        'Saved',
        'Could not sync',
      ]);
    });

    testWidgets('an interruption does not bring back a bar that had its '
        'time', (tester) async {
      final messenger = await pumpMessenger(tester);

      messenger.show(
        'Marked finished',
        actionLabel: 'Undo',
        onAction: () {},
        persist: true,
      );
      await tester.pumpAndSettle();
      await outlast(tester);
      expect(find.text('Marked finished'), findsOneWidget);

      messenger.show('Decided 1 entry', interrupts: true);
      await tester.pumpAndSettle();
      expect(find.text('Decided 1 entry'), findsOneWidget);
      await outlast(tester);
      await outlast(tester);
      expect(find.text('Marked finished'), findsNothing);
    });

    testWidgets('a message taken back goes as an answered one, from the bar '
        'or the queue, and no other with it', (tester) async {
      final messenger = await pumpMessenger(tester);
      var undone = 0;

      messenger.show(
        'Decided 1 entry',
        actionLabel: 'Undo',
        onAction: () => undone++,
        channel: ShellChannel.review,
        subject: 'rv-1',
        persist: true,
      );
      await tester.pumpAndSettle();
      messenger.withdraw(ShellChannel.review, 'rv-2');
      await tester.pumpAndSettle();
      expect(find.text('Decided 1 entry'), findsOneWidget);
      messenger
        ..show('Pinned Blue Train', channel: ShellChannel.pins, subject: 'al-1')
        ..withdraw(ShellChannel.review, 'rv-1');
      await tester.pumpAndSettle();
      expect(find.text('Decided 1 entry'), findsNothing);
      expect(find.text('Pinned Blue Train'), findsOneWidget);
      expect(undone, 0);

      messenger
        ..show('Scan started')
        ..show(
          'Unpinned Kind of Blue',
          channel: ShellChannel.pins,
          subject: 'al-2',
        )
        ..withdraw(ShellChannel.pins, 'al-2');
      final drawn = <String>{};
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        for (final text in ['Scan started', 'Unpinned Kind of Blue']) {
          if (find.text(text).evaluate().isNotEmpty) drawn.add(text);
        }
      }
      expect(drawn, {'Scan started'});
    });

    testWidgets('a message taken back takes no press while it leaves', (
      tester,
    ) async {
      final messenger = await pumpMessenger(tester);
      var undone = 0;
      messenger.show(
        'Decided 1 entry',
        actionLabel: 'Undo',
        onAction: () => undone++,
        channel: ShellChannel.review,
        subject: 'rv-1',
        persist: true,
      );
      await tester.pumpAndSettle();

      messenger.withdraw(ShellChannel.review, 'rv-1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Undo'), findsOneWidget, reason: 'still leaving');
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(undone, 0);
      expect(find.text('Decided 1 entry'), findsNothing);
    });

    testWidgets('leaves other messages to take their turns', (tester) async {
      final messenger = await pumpMessenger(tester);

      messenger.show('Scan started');
      await tester.pump();
      messenger.show('Link copied');
      await tester.pumpAndSettle();

      expect(find.text('Scan started'), findsOneWidget);
      await outlast(tester);
      expect(find.text('Link copied'), findsOneWidget);
    });
  });

  group("a message's clock", () {
    test('in the app is the monotonic one, not the wall clock', () {
      expect(messageStopwatch().runtimeType, Stopwatch);
    });

    testWidgets("in a test is the test's fake time", (tester) async {
      final watch = messageStopwatch()..start();
      await tester.pump(const Duration(seconds: 3));
      expect(watch.elapsed, const Duration(seconds: 3));
    });
  });

  group("a flight's animation", () {
    final route = AnimationController(vsync: const TestVSync());
    final overlay = AnimationController(vsync: const TestVSync());
    tearDownAll(() {
      route.dispose();
      overlay.dispose();
    });

    /// What the shuttle reads under a stand-in for the hero overlay: an
    /// [AnimatedBuilder] over [animation] whose child is the shuttle
    /// itself, or holds it below a box where [boxed].
    Future<Animation<double>> flownUnder(
      WidgetTester tester,
      Listenable animation, {
      bool boxed = false,
    }) async {
      late Animation<double> read;
      final shuttle = Builder(
        builder: (context) {
          read = flightAnimation(context, context.widget, route);
          return const SizedBox();
        },
      );
      await tester.pumpWidget(
        AnimatedBuilder(
          animation: animation,
          child: boxed ? SizedBox(child: shuttle) : shuttle,
          builder: (context, child) => child!,
        ),
      );
      return read;
    }

    testWidgets("is the hero overlay's, whose child the shuttle is", (
      tester,
    ) async {
      expect(await flownUnder(tester, overlay), same(overlay));
    });

    testWidgets("is the route's under a builder over something else", (
      tester,
    ) async {
      final restoration = ValueNotifier<String?>(null);
      addTearDown(restoration.dispose);
      expect(await flownUnder(tester, restoration), same(route));
      expect(tester.takeException(), isNull);
    });

    testWidgets("is the route's under a builder whose child is not the "
        'shuttle', (tester) async {
      expect(await flownUnder(tester, overlay, boxed: true), same(route));
    });
  });
}

/// Whether [element] is drawn inside the page whose identifier is [page].
bool _within(Element element, String page) {
  var inside = false;
  element.visitAncestorElements((ancestor) {
    if (ancestor.widget case Semantics(:final properties)
        when properties.identifier == page) {
      inside = true;
    }
    return !inside;
  });
  return inside;
}

/// The opacity [element] is drawn at, the fades above it multiplied; null
/// for one out of sight: under an Offstage, a page covered in its
/// navigator or a hidden tab, each of which turns its tickers off.
double? _opacityOnStage(Element element) {
  var opacity = 1.0;
  var offstage = false;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is FadeTransition) opacity *= widget.opacity.value;
    if (widget is Opacity) opacity *= widget.opacity;
    if (widget is TickerMode && !widget.enabled) offstage = true;
    if (ancestor.renderObject case final RenderOffstage box when box.offstage) {
      offstage = true;
    }
    return true;
  });
  return offstage ? null : opacity;
}

/// A signed-in repository whose rematch answers when [answer] completes.
class _HeldRematch extends FakeRepository {
  _HeldRematch()
    : super(
        sessionState: const SessionState(authenticated: true, user: _user),
        items: [testItem(_track)],
      );

  final answer = Completer<void>();

  @override
  Future<String> rematchItem(String pid) async {
    await answer.future;
    return super.rematchItem(pid);
  }
}
