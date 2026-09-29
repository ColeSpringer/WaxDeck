import 'dart:ui' show PointerDeviceKind, Tristate;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWaxTheme(),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  for (final icon in <bool>[true, false]) {
    testWidgets('Enter presses a focused ${icon ? 'icon ' : ''}button the '
        'way the web binds it', (tester) async {
      // The web maps Enter to ButtonActivateIntent, not ActivateIntent,
      // with nothing behind it to fall back to.
      var pressed = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWaxTheme(),
          shortcuts: <ShortcutActivator, Intent>{
            ...WidgetsApp.defaultShortcuts,
            const SingleActivator(LogicalKeyboardKey.enter):
                const ButtonActivateIntent(),
          },
          home: Scaffold(
            body: Center(
              child: icon
                  ? WaxIconButton(
                      glyph: WaxIcons.refresh,
                      label: 'Sweep',
                      onPressed: () => pressed++,
                    )
                  : WaxButton(label: 'Scan now', onPressed: () => pressed++),
            ),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(pressed, 1);
    });
  }

  testWidgets('a button reached from the keyboard draws the focus ring', (
    tester,
  ) async {
    await _pump(tester, WaxButton(label: 'Scan now', onPressed: () {}));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(WaxButton),
        matching: find.byWidgetPredicate((w) => w is WaxFocusRing && w.focused),
      ),
      findsOneWidget,
    );
  });

  for (final (name, busy) in <(String, bool)>[
    ('disabled', false),
    ('busy', true),
  ]) {
    testWidgets('a $name tappable shows no hand', (tester) async {
      await _pump(
        tester,
        WaxTappable(
          label: 'Artwork',
          onPressed: busy ? () {} : null,
          busy: busy,
          child: const SizedBox.square(dimension: 48),
        ),
      );
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        pointer: 1,
      );
      addTearDown(mouse.removePointer);
      await mouse.addPointer(
        location: tester.getCenter(find.byType(WaxTappable)),
      );
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.basic,
      );
    });
  }

  group('busy', () {
    for (final icon in <WaxGlyph?>[WaxIcons.refresh, null]) {
      testWidgets('a button ${icon == null ? 'without' : 'with'} a glyph '
          'takes no press, keeps its size and its name', (tester) async {
        final semantics = tester.ensureSemantics();
        var pressed = 0;
        Future<Rect> buttonAt({required bool busy}) async {
          await _pump(
            tester,
            WaxButton(
              label: 'Scan now',
              icon: icon,
              busy: busy,
              semanticsId: 'scan',
              onPressed: () => pressed++,
            ),
          );
          return tester.getRect(find.byType(WaxButton));
        }

        final idle = await buttonAt(busy: false);
        expect(find.byType(WaxSpinner), findsNothing);

        final busy = await buttonAt(busy: true);
        expect(busy, idle, reason: 'the button does not move under the hand');
        expect(find.byType(WaxSpinner), findsOneWidget);
        await tester.tap(find.byType(WaxButton), warnIfMissed: false);
        await tester.pump();
        expect(pressed, 0);

        final node = tester
            .getSemantics(find.bySemanticsIdentifier('scan'))
            .getSemanticsData();
        expect(node.label, 'Scan now');
        expect(node.value, 'Working', reason: 'says why it is dimmed');
        expect(node.flagsCollection.isEnabled, Tristate.isFalse);
        expect(node.hasAction(SemanticsAction.tap), isFalse);
        semantics.dispose();
      });
    }

    testWidgets('a press reaches neither the control\'s ink nor its parent', (
      tester,
    ) async {
      var pressed = 0;
      var parent = 0;
      Widget around(Widget child) => GestureDetector(
        onTap: () => parent++,
        child: Center(child: child),
      );
      for (final control in <Widget>[
        WaxIconButton(
          glyph: WaxIcons.heart,
          label: 'Save this song',
          busy: true,
          onPressed: () => pressed++,
        ),
        WaxButton(label: 'Scan now', busy: true, onPressed: () => pressed++),
        WaxTappable(
          label: 'Row',
          busy: true,
          onPressed: () => pressed++,
          child: InkWell(
            onTap: () => pressed++,
            child: const SizedBox(width: 120, height: 44),
          ),
        ),
      ]) {
        await _pump(tester, around(control));
        await tester.tap(find.byWidget(control), warnIfMissed: false);
        await tester.pump();
      }
      expect(pressed, 0);
      expect(parent, 0, reason: 'the heart sits in the bar\'s expand zone');
    });

    testWidgets('an icon button draws the ring where its glyph was', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var pressed = 0;
      await _pump(
        tester,
        WaxIconButton(
          glyph: WaxIcons.refresh,
          label: 'Sweep',
          busy: true,
          semanticsId: 'sweep',
          onPressed: () => pressed++,
        ),
      );

      expect(find.byType(WaxSpinner), findsOneWidget);
      expect(find.byType(WaxIcon), findsNothing);
      await tester.tap(find.byType(WaxIconButton), warnIfMissed: false);
      await tester.pump();
      expect(pressed, 0);
      final node = tester
          .getSemantics(find.bySemanticsIdentifier('sweep'))
          .getSemanticsData();
      expect(node.label, 'Sweep');
      expect(node.value, 'Working');
      expect(node.flagsCollection.isEnabled, Tristate.isFalse);
      semantics.dispose();
    });

    for (final icon in <bool>[false, true]) {
      testWidgets('a pressed ${icon ? 'icon ' : ''}button keeps the focus '
          'while it works', (tester) async {
        // A keyboard press that turns the control busy must not throw
        // the focus somewhere else on the page.
        Future<void> pump({required bool busy}) => _pump(
          tester,
          icon
              ? WaxIconButton(
                  glyph: WaxIcons.refresh,
                  label: 'Sweep',
                  busy: busy,
                  onPressed: () {},
                )
              : WaxButton(label: 'Scan now', busy: busy, onPressed: () {}),
        );
        bool focused() {
          final context = FocusManager.instance.primaryFocus?.context;
          return context != null &&
              find
                  .ancestor(
                    of: find.byElementPredicate((e) => e == context),
                    matching: find.byType(icon ? WaxIconButton : WaxButton),
                  )
                  .evaluate()
                  .isNotEmpty;
        }

        await pump(busy: false);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(focused(), isTrue, reason: 'reached from the keyboard');

        await pump(busy: true);
        await tester.pump();
        expect(focused(), isTrue);
      });
    }

    testWidgets('a busy button makes no click or buzz', (tester) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await _pump(
          tester,
          WaxButton(label: 'Scan now', busy: true, onPressed: () {}),
        );
        await tester.tap(find.byType(WaxButton), warnIfMissed: false);
        await tester.pump();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
      expect(calls, isNot(contains('SystemSound.play')));
    });

    testWidgets('the ring turns without painting its arcs again', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWaxTheme(),
          home: const Center(child: WaxSpinner()),
        ),
      );
      final arcs = tester.renderObject(
        find.descendant(
          of: find.byType(WaxSpinner),
          matching: find.byType(CustomPaint),
        ),
      );
      var painted = 0;
      debugOnProfilePaint = (object) {
        if (identical(object, arcs)) painted++;
      };
      try {
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      } finally {
        debugOnProfilePaint = null;
      }
      expect(painted, 0);
    });

    testWidgets('the ring holds still under reduced motion', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWaxTheme(),
          home: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Center(child: WaxSpinner()),
          ),
        ),
      );
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
