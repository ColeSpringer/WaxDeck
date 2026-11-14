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

/// The bordered or filled boxes a [WaxButton] draws, matching [test].
List<RenderDecoratedBox> _decorated(
  WidgetTester tester,
  bool Function(BoxDecoration) test,
) => tester
    .renderObjectList<RenderDecoratedBox>(
      find.descendant(
        of: find.byType(WaxButton),
        matching: find.byType(DecoratedBox),
      ),
    )
    .where((r) => r.decoration is BoxDecoration)
    .where((r) => test(r.decoration as BoxDecoration))
    .toList();

/// The rect a progress pill's done share is clipped to, and the width it
/// is a share of.
(Rect, double) _shareClip(WidgetTester tester) {
  final clip = tester.renderObject<RenderClipRect>(
    find.descendant(
      of: find.byType(WaxButton),
      matching: find.byType(ClipRect),
    ),
  );
  return (clip.clipper!.getClip(clip.size), clip.size.width);
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

    testWidgets('a $name tappable spends the press it does not take', (
      tester,
    ) async {
      var behind = 0;
      await _pump(
        tester,
        GestureDetector(
          onTap: () => behind++,
          child: WaxTappable(
            label: 'Artwork',
            onPressed: busy ? () {} : null,
            busy: busy,
            child: const SizedBox.square(dimension: 48),
          ),
        ),
      );
      await tester.tap(find.byType(WaxTappable));
      await tester.pump();
      expect(behind, 0, reason: 'a greyed control is not a way through');
    });
  }

  testWidgets('an inert tappable lets the press through', (tester) async {
    var behind = 0;
    await _pump(
      tester,
      GestureDetector(
        onTap: () => behind++,
        child: const WaxTappable(
          label: 'Downloaded',
          onPressed: null,
          inert: true,
          child: SizedBox.square(dimension: 48),
        ),
      ),
    );
    await tester.tap(find.byType(WaxTappable));
    await tester.pump();
    expect(behind, 1);
  });

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
        await tester.tap(find.byType(WaxButton));
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
        await tester.tap(find.byWidget(control));
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
      await tester.tap(find.byType(WaxIconButton));
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
        await tester.tap(find.byType(WaxButton));
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

    testWidgets('a ring can be drawn thinner than its size suggests', (
      tester,
    ) async {
      Future<RenderObject> arcsOf(double? thickness) async {
        await _pump(tester, WaxSpinner(size: 40, thickness: thickness));
        return tester.renderObject(
          find.descendant(
            of: find.byType(WaxSpinner),
            matching: find.byType(CustomPaint),
          ),
        );
      }

      // An eighth of the box unless told otherwise, so the ring grows with
      // the glyph it stands in for.
      expect(
        await arcsOf(null),
        paints
          ..arc(rect: const Rect.fromLTWH(2.5, 2.5, 35, 35), strokeWidth: 5)
          ..arc(rect: const Rect.fromLTWH(2.5, 2.5, 35, 35), strokeWidth: 5),
      );
      // A hairline still keeps its outer edge on the box.
      expect(
        await arcsOf(2),
        paints
          ..arc(rect: const Rect.fromLTWH(1, 1, 38, 38), strokeWidth: 2)
          ..arc(rect: const Rect.fromLTWH(1, 1, 38, 38), strokeWidth: 2),
      );
    });
  });

  group('states', () {
    testWidgets('a status pill is not a button and keeps the pill height', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var pressed = 0;
      await _pump(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            WaxButton(
              label: 'Queued for download',
              icon: WaxIcons.downloads,
              status: true,
              semanticsId: 'queued',
              onPressed: () => pressed++,
            ),
            WaxButton(
              label: 'Download',
              kind: WaxButtonKind.tonal,
              semanticsId: 'download',
              onPressed: () {},
            ),
          ],
        ),
      );

      final status = find.byWidgetPredicate(
        (w) => w is WaxButton && w.semanticsId == 'queued',
      );
      final tonal = find.byWidgetPredicate(
        (w) => w is WaxButton && w.semanticsId == 'download',
      );
      expect(tester.getSize(tonal).height, WaxSpace.touchTarget);
      expect(tester.getSize(status).height, tester.getSize(tonal).height);

      final node = tester
          .getSemantics(find.bySemanticsIdentifier('queued'))
          .getSemanticsData();
      expect(node.label, 'Queued for download');
      expect(node.flagsCollection.isButton, isFalse);
      expect(node.hasAction(SemanticsAction.tap), isFalse);
      expect(node.flagsCollection.isFocused, Tristate.none);

      await tester.tap(status);
      await tester.pump();
      expect(pressed, 0, reason: 'a status takes no press');
      semantics.dispose();
    });

    for (final pressable in <bool>[false, true]) {
      testWidgets('a progress pill reports its value and takes no press'
          '${pressable ? ' even with a callback' : ''}', (tester) async {
        final semantics = tester.ensureSemantics();
        var pressed = 0;
        await _pump(
          tester,
          WaxButton(
            label: 'Downloading',
            kind: WaxButtonKind.tonal,
            progress: 0.42,
            semanticsId: 'fetch',
            onPressed: pressable ? () => pressed++ : null,
          ),
        );

        final node = tester
            .getSemantics(find.bySemanticsIdentifier('fetch'))
            .getSemanticsData();
        expect(node.label, 'Downloading');
        expect(node.value, '42%');
        expect(node.flagsCollection.isEnabled, Tristate.isFalse);
        expect(node.hasAction(SemanticsAction.tap), isFalse);

        final colors = WaxColors.of(tester.element(find.byType(WaxButton)));
        final inks = tester
            .widgetList<Text>(find.text('Downloading'))
            .map((t) => t.style?.color);
        expect(inks, isNot(contains(colors.textDisabled)));

        await tester.tap(find.byType(WaxButton));
        await tester.pump();
        expect(pressed, 0);
        semantics.dispose();
      });
    }

    for (final given in <double>[
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      testWidgets('progress $given has no share to draw, so it is the busy '
          'pill', (tester) async {
        final semantics = tester.ensureSemantics();
        await _pump(
          tester,
          WaxButton(
            label: 'Downloading',
            kind: WaxButtonKind.tonal,
            progress: given,
            semanticsId: 'fetch',
            onPressed: () {},
          ),
        );

        expect(find.byType(WaxSpinner), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(WaxButton),
            matching: find.byType(ClipRect),
          ),
          findsNothing,
          reason: 'no share is drawn',
        );
        final node = tester
            .getSemantics(find.bySemanticsIdentifier('fetch'))
            .getSemanticsData();
        expect(node.label, 'Downloading');
        expect(node.value, 'Working');
        expect(node.flagsCollection.isEnabled, Tristate.isFalse);
        expect(node.hasAction(SemanticsAction.tap), isFalse);
        semantics.dispose();
      });
    }

    testWidgets('a disabled pill with a detail is a tab stop that shows it, '
        'takes no press and says it is disabled', (tester) async {
      final semantics = tester.ensureSemantics();
      const why = 'Connect to Wi-Fi to download';
      var pressed = 0;
      await _pump(
        tester,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            WaxButton(label: 'Play', onPressed: () => pressed++),
            const WaxButton(
              label: 'Download',
              detail: why,
              semanticsId: 'download',
              onPressed: null,
            ),
            WaxButton(label: 'Share', onPressed: () => pressed++),
          ],
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<WaxButton>()
            ?.label,
        'Download',
      );
      expect(find.text(why), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(pressed, 0);

      final node = tester
          .getSemantics(find.bySemanticsIdentifier('download'))
          .getSemanticsData();
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isEnabled, Tristate.isFalse);
      expect(node.flagsCollection.isFocused, Tristate.isTrue);
      expect(node.hasAction(SemanticsAction.tap), isFalse);
      semantics.dispose();
    });

    testWidgets('a disabled pill is no focus stop to a reader', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        const WaxButton(label: 'Save', semanticsId: 'save', onPressed: null),
      );
      final node = tester
          .getSemantics(find.bySemanticsIdentifier('save'))
          .getSemanticsData();
      expect(node.flagsCollection.isEnabled, Tristate.isFalse);
      expect(node.flagsCollection.isFocused, Tristate.none);
      semantics.dispose();
    });

    testWidgets('every pill kind stands one height at 2.0 text scale', (
      tester,
    ) async {
      final kinds = WaxButtonKind.values
          .where((k) => k != WaxButtonKind.inline)
          .toList();
      await _pump(
        tester,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final kind in kinds)
                  WaxButton(label: 'Save', kind: kind, onPressed: () {}),
              ],
            ),
          ),
        ),
      );
      final heights = tester
          .widgetList<WaxButton>(find.byType(WaxButton))
          .map((b) => tester.getSize(find.byWidget(b)).height)
          .toSet();
      expect(heights, hasLength(1));
      expect(heights.single, greaterThan(WaxSpace.touchTarget));
    });

    testWidgets('a link capped at one line ends in an ellipsis, keeps its '
        'target and speaks the whole label', (tester) async {
      final semantics = tester.ensureSemantics();
      const name = 'The Exceedingly Long Name of a Show About Many Things';
      await _pump(
        tester,
        SizedBox(
          width: 160,
          child: WaxButton(
            label: name,
            spokenLabel: 'Go to $name',
            kind: WaxButtonKind.inline,
            maxLines: 1,
            semanticsId: 'show',
            onPressed: () {},
          ),
        ),
      );

      final text = tester.widget<Text>(
        find.descendant(of: find.byType(WaxButton), matching: find.text(name)),
      );
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      final line = tester.getSize(find.text(name)).height;
      expect(line, lessThan(WaxSpace.touchTarget));
      expect(
        tester.getSize(find.byType(WaxButton)).height,
        WaxSpace.touchTarget,
      );
      expect(
        tester
            .getSemantics(find.bySemanticsIdentifier('show'))
            .getSemanticsData()
            .label,
        'Go to $name',
      );
      semantics.dispose();
    });

    test('only a link takes a line cap', () {
      expect(
        () => WaxButton(label: 'x', onPressed: null, maxLines: 1),
        throwsAssertionError,
      );
    });

    test('busy, progress and status are one state at a time', () {
      expect(
        () => WaxButton(label: 'x', onPressed: null, busy: true, status: true),
        throwsAssertionError,
      );
      expect(
        () => WaxButton(label: 'x', onPressed: null, busy: true, progress: 0),
        throwsAssertionError,
      );
      expect(
        () =>
            WaxButton(label: 'x', onPressed: null, progress: 0.5, status: true),
        throwsAssertionError,
      );
    });

    for (final (host, wrap) in <(String, Widget Function(Widget))>[
      ('a fixed width', (pill) => SizedBox(width: 300, child: pill)),
      (
        'an expanded row slot',
        (pill) => SizedBox(
          width: 300,
          child: Row(children: <Widget>[Expanded(child: pill)]),
        ),
      ),
    ]) {
      testWidgets('a progress pill in $host draws one label and one outline', (
        tester,
      ) async {
        await _pump(
          tester,
          wrap(
            const WaxButton(
              label: 'Fetching',
              kind: WaxButtonKind.tonal,
              progress: 0.42,
              onPressed: null,
            ),
          ),
        );
        final labels = find.text('Fetching');
        expect(labels, findsNWidgets(2));
        expect(tester.getRect(labels.at(1)), tester.getRect(labels.at(0)));
        final outlines = _decorated(
          tester,
          (d) => d.border != null,
        ).map((r) => r.localToGlobal(Offset.zero) & r.size).toSet();
        expect(outlines, <Rect>{tester.getRect(find.byType(WaxButton))});
      });
    }

    for (final direction in TextDirection.values) {
      testWidgets('a progress fill starts at the ${direction.name} reading '
          'edge', (tester) async {
        await _pump(
          tester,
          Directionality(
            textDirection: direction,
            child: const WaxButton(
              label: 'Fetching',
              kind: WaxButtonKind.tonal,
              progress: 0.25,
              onPressed: null,
            ),
          ),
        );
        final (clip, width) = _shareClip(tester);
        expect(clip.width, closeTo(width * 0.25, 0.01));
        if (direction == TextDirection.ltr) {
          expect(clip.left, 0);
        } else {
          expect(clip.right, width);
        }
      });
    }

    for (final (given, spoken, share) in <(double, String, double)>[
      (0, '0%', 0),
      (1, '100%', 1),
      (1.5, '100%', 1),
      (-0.2, '0%', 0),
    ]) {
      testWidgets('progress $given is drawn and spoken as $spoken', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await _pump(
          tester,
          WaxButton(
            label: 'Fetching',
            progress: given,
            semanticsId: 'fetch',
            onPressed: null,
          ),
        );
        final node = tester
            .getSemantics(find.bySemanticsIdentifier('fetch'))
            .getSemanticsData();
        expect(node.value, spoken);
        final (clip, width) = _shareClip(tester);
        expect(clip.width, closeTo(width * share, 0.01));
        semantics.dispose();
      });
    }

    for (final kind in <WaxButtonKind>[
      WaxButtonKind.filled,
      WaxButtonKind.tonal,
      WaxButtonKind.destructive,
    ]) {
      testWidgets('a ${kind.name} progress pill keeps a readable pair on '
          'each side of the fill', (tester) async {
        await _pump(
          tester,
          WaxButton(
            label: 'Fetching',
            kind: kind,
            progress: 0.5,
            onPressed: null,
          ),
        );
        final colors = WaxColors.of(tester.element(find.byType(WaxButton)));
        final (track, trackInk, fill, onFill) = switch (kind) {
          WaxButtonKind.filled => (
            colors.accentContainer,
            colors.onAccentContainer,
            colors.accent,
            colors.onAccent,
          ),
          WaxButtonKind.destructive => (
            Colors.transparent,
            colors.error,
            colors.error,
            colors.onError,
          ),
          _ => (
            colors.surface2,
            colors.textPrimary,
            colors.accent,
            colors.onAccent,
          ),
        };
        final material = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(WaxButton),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(material.color, track);
        expect(_decorated(tester, (d) => d.color == fill), hasLength(1));
        expect(
          tester
              .widgetList<Text>(find.text('Fetching'))
              .map((t) => t.style?.color),
          <Color?>[trackInk, onFill],
        );
      });
    }

    for (final kind in WaxButtonKind.values) {
      testWidgets('a ${kind.name} status pill is tonal in secondary ink', (
        tester,
      ) async {
        await _pump(
          tester,
          WaxButton(
            label: 'Queued for download',
            icon: WaxIcons.downloads,
            kind: kind,
            status: true,
            onPressed: () {},
          ),
        );
        final colors = WaxColors.of(tester.element(find.byType(WaxButton)));
        final box = _decorated(tester, (d) => d.color != null).single;
        final decoration = box.decoration as BoxDecoration;
        expect(decoration.color, colors.surface2);
        expect(decoration.border, Border.all(color: colors.hairline));
        expect(
          tester.widget<Text>(find.text('Queued for download')).style?.color,
          colors.textSecondary,
        );
        expect(
          tester.widget<WaxIcon>(find.byType(WaxIcon)).color,
          colors.textSecondary,
        );
      });
    }

    for (final (host, wrap) in <(String, Widget Function(Widget))>[
      ('a centred page', (pill) => pill),
      (
        'a fixed-height row',
        (pill) => SizedBox(
          height: 120,
          child: Row(children: <Widget>[Expanded(child: pill)]),
        ),
      ),
    ]) {
      for (final (name, pill) in <(String, WaxButton)>[
        ('ready', WaxButton(label: 'Download', onPressed: () {})),
        (
          'expanded',
          WaxButton(label: 'Download', expand: true, onPressed: () {}),
        ),
        (
          'progress',
          const WaxButton(label: 'Fetching', progress: 0.4, onPressed: null),
        ),
        (
          'status',
          const WaxButton(label: 'Queued', status: true, onPressed: null),
        ),
      ]) {
        testWidgets('a $name pill in $host keeps its own height', (
          tester,
        ) async {
          await _pump(tester, SizedBox(width: 300, child: wrap(pill)));
          expect(
            tester.getSize(find.byType(WaxButton)).height,
            WaxSpace.touchTarget,
          );
        });
      }
    }

    for (final (name, pill) in <(String, WaxButton)>[
      for (final kind in WaxButtonKind.values)
        (kind.name, WaxButton(label: 'Save', kind: kind, onPressed: () {})),
      (
        'glyph',
        WaxButton(label: 'Save', icon: WaxIcons.downloads, onPressed: () {}),
      ),
      ('busy', WaxButton(label: 'Save', busy: true, onPressed: () {})),
      (
        'progress',
        const WaxButton(label: 'Saving', progress: 0.4, onPressed: null),
      ),
      (
        'status',
        const WaxButton(label: 'Saved', status: true, onPressed: null),
      ),
    ]) {
      testWidgets('a one-line $name pill fits an app bar at 2.0 text scale', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildWaxTheme(),
            localizationsDelegates: waxLocalizationsDelegates,
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: WaxScaffold(
                  title: 'Rules',
                  largeTitle: false,
                  actions: <Widget>[pill],
                  body: const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final toolbar = tester.getRect(find.byType(NavigationToolbar));
        expect(toolbar.height, kToolbarHeight);
        final box = tester.getRect(find.byType(WaxButton));
        expect(box.top, greaterThanOrEqualTo(toolbar.top));
        expect(box.bottom, lessThanOrEqualTo(toolbar.bottom));
        // Laid out whole: the bar's height squeezes no line short.
        final lines = tester.renderObjectList<RenderParagraph>(
          find.descendant(
            of: find.byType(WaxButton),
            matching: find.byType(RichText),
          ),
        );
        expect(lines, isNotEmpty);
        for (final line in lines) {
          expect(
            line.size.height,
            greaterThanOrEqualTo(
              line.getMaxIntrinsicHeight(line.size.width) - 0.01,
            ),
          );
        }
      });
    }

    testWidgets('a long label wraps at 2.0 text scale instead of clipping', (
      tester,
    ) async {
      const long = 'Download every episode of this show';
      await _pump(
        tester,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            // A column, as a page holds it: the pill's height is its own.
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: 220,
                  child: WaxButton(
                    label: long,
                    kind: WaxButtonKind.tonal,
                    icon: WaxIcons.downloads,
                    onPressed: () {},
                  ),
                ),
                // One line at the same scale, to measure a line by.
                WaxButton(
                  label: 'Download',
                  kind: WaxButtonKind.tonal,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final line = tester.getSize(find.text('Download')).height;
      final label = tester.getRect(find.text(long));
      expect(
        label.height,
        greaterThanOrEqualTo(2 * line - 0.01),
        reason: 'the label lays out on more than one line',
      );
      final paragraph = tester.renderObject<RenderParagraph>(find.text(long));
      expect(
        paragraph.size.height,
        greaterThanOrEqualTo(
          paragraph.getMaxIntrinsicHeight(paragraph.size.width) - 0.01,
        ),
        reason: 'and none of it is cut',
      );
      final pill = tester.getRect(
        find.ancestor(of: find.text(long), matching: find.byType(WaxButton)),
      );
      expect(label.top - pill.top, greaterThanOrEqualTo(WaxSpace.s8));
      expect(pill.bottom - label.bottom, greaterThanOrEqualTo(WaxSpace.s8));
    });

    testWidgets('an inactive icon button with no press is drawn disabled', (
      tester,
    ) async {
      await _pump(
        tester,
        const WaxIconButton(
          glyph: WaxIcons.downloads,
          label: 'Download',
          onPressed: null,
        ),
      );
      final colors = WaxColors.of(tester.element(find.byType(WaxIconButton)));
      expect(
        tester.widget<WaxIcon>(find.byType(WaxIcon)).color,
        colors.textDisabled,
      );
    });

    testWidgets('a disabled icon button is drawn disabled whatever active '
        'and its colour say', (tester) async {
      for (final color in <Color?>[null, const Color(0xFF3366CC)]) {
        await _pump(
          tester,
          WaxIconButton(
            glyph: WaxIcons.lock,
            label: 'Unlock',
            active: true,
            color: color,
            onPressed: null,
          ),
        );
        final colors = WaxColors.of(tester.element(find.byType(WaxIconButton)));
        expect(
          tester.widget<WaxIcon>(find.byType(WaxIcon)).color,
          colors.textDisabled,
          reason: '$color',
        );
      }
    });

    testWidgets('a status icon button stays lit, takes no press and is no '
        'button', (tester) async {
      final semantics = tester.ensureSemantics();
      var pressed = 0;
      await _pump(
        tester,
        WaxIconButton(
          glyph: WaxIcons.success,
          label: 'Downloaded',
          active: true,
          status: true,
          semanticsId: 'done',
          onPressed: () => pressed++,
        ),
      );
      final colors = WaxColors.of(tester.element(find.byType(WaxIconButton)));
      expect(tester.widget<WaxIcon>(find.byType(WaxIcon)).color, colors.accent);

      final data = tester
          .getSemantics(find.bySemanticsIdentifier('done'))
          .getSemanticsData();
      expect(data.label, 'Downloaded');
      expect(data.flagsCollection.isButton, isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);

      await tester.tap(find.byType(WaxIconButton));
      await tester.pump();
      expect(pressed, 0);
      semantics.dispose();
    });

    testWidgets('a status icon button keeps its own colour, and reads in '
        'secondary ink when not active', (tester) async {
      const own = Color(0xFF3366CC);
      await _pump(
        tester,
        const WaxIconButton(
          glyph: WaxIcons.success,
          label: 'Downloaded',
          active: true,
          status: true,
          color: own,
          onPressed: null,
        ),
      );
      expect(tester.widget<WaxIcon>(find.byType(WaxIcon)).color, own);

      await _pump(
        tester,
        const WaxIconButton(
          glyph: WaxIcons.downloads,
          label: 'Not here',
          status: true,
          onPressed: null,
        ),
      );
      final colors = WaxColors.of(tester.element(find.byType(WaxIconButton)));
      expect(
        tester.widget<WaxIcon>(find.byType(WaxIcon)).color,
        colors.textSecondary,
      );
    });
  });

  group('an ink tappable', () {
    testWidgets('a disabled row takes no long press', (tester) async {
      var long = 0;
      await _pump(
        tester,
        WaxInkTappable(
          label: 'Row',
          onPressed: null,
          onLongPress: () => long++,
          child: const SizedBox(width: 200, height: 44, child: Text('Row')),
        ),
      );
      await tester.longPress(find.byType(WaxInkTappable));
      expect(long, 0);
    });

    testWidgets('a long press reaches its own callback', (tester) async {
      var long = 0;
      await _pump(
        tester,
        WaxInkTappable(
          label: 'Row',
          onPressed: () {},
          onLongPress: () => long++,
          child: const SizedBox(width: 200, height: 44, child: Text('Row')),
        ),
      );
      await tester.longPress(find.byType(WaxInkTappable));
      expect(long, 1);
    });

    testWidgets('a pointer, a key and a reader press the one callback', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var pressed = 0;
      void press() => pressed++;
      await _pump(
        tester,
        WaxInkTappable(
          label: 'Kitchen speaker',
          semanticsId: 'row',
          onPressed: press,
          child: const SizedBox(width: 200, height: 44, child: Text('Kitchen')),
        ),
      );
      final ink = tester.widget<InkWell>(find.byType(InkWell));
      final node = tester.widget<WaxTappable>(find.byType(WaxTappable));
      expect(ink.onTap, same(node.onPressed), reason: 'one callback');

      await tester.tap(find.byType(WaxInkTappable));
      await tester.pump();
      expect(pressed, 1, reason: 'a pointer');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(pressed, 2, reason: 'a key');

      tester.semantics.tap(
        find.semantics.byPredicate((node) => node.identifier == 'row'),
      );
      await tester.pump();
      expect(pressed, 3, reason: 'a reader');

      final data = tester
          .getSemantics(find.bySemanticsIdentifier('row'))
          .getSemanticsData();
      expect(data.label, 'Kitchen speaker');
      expect(data.flagsCollection.isButton, isTrue);
      semantics.dispose();
    });

    testWidgets('with no callback it takes no press and says so', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        const WaxInkTappable(
          label: 'Kitchen speaker',
          semanticsId: 'row',
          onPressed: null,
          child: SizedBox(width: 200, height: 44),
        ),
      );
      expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
      final data = tester
          .getSemantics(find.bySemanticsIdentifier('row'))
          .getSemanticsData();
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      semantics.dispose();
    });

    testWidgets('the ground, the ink and the ring share one corner', (
      tester,
    ) async {
      await _pump(
        tester,
        WaxInkTappable(
          label: 'Backups',
          color: Colors.teal,
          borderRadius: WaxRadius.card,
          onPressed: () {},
          child: const SizedBox(width: 200, height: 44),
        ),
      );
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(WaxInkTappable),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, Colors.teal);
      expect(material.borderRadius, WaxRadius.card);
      expect(
        tester.widget<InkWell>(find.byType(InkWell)).borderRadius,
        WaxRadius.card,
      );
      expect(
        tester.widget<WaxTappable>(find.byType(WaxTappable)).borderRadius,
        WaxRadius.card,
      );
    });
  });

  group('a tappable\'s tooltip coming and going', () {
    testWidgets('keys its focus detector to nothing, with a tooltip or '
        'without', (tester) async {
      for (final tooltip in <String?>[null, 'Waits for Wi-Fi']) {
        await _pump(
          tester,
          WaxTappable(
            label: 'Download',
            tooltip: tooltip,
            onPressed: () {},
            child: const SizedBox(width: 80, height: 44),
          ),
        );
        final detector = tester.widget<FocusableActionDetector>(
          find.descendant(
            of: find.byType(WaxTappable),
            matching: find.byType(FocusableActionDetector),
          ),
        );
        expect(detector.key, isNull, reason: '$tooltip');
      }
    });

    testWidgets('keeps the focus detector\'s element', (tester) async {
      final tip = ValueNotifier<String?>(null);
      addTearDown(tip.dispose);
      await _pump(
        tester,
        ValueListenableBuilder<String?>(
          valueListenable: tip,
          builder: (_, words, _) => WaxTappable(
            label: 'Download',
            tooltip: words,
            onPressed: () {},
            child: const SizedBox(width: 80, height: 44),
          ),
        ),
      );
      Element detector() => tester.element(
        find.descendant(
          of: find.byType(WaxTappable),
          matching: find.byType(FocusableActionDetector),
        ),
      );
      final first = detector();
      for (final words in <String?>['Waits for Wi-Fi', null]) {
        tip.value = words;
        await tester.pump();
        expect(identical(detector(), first), isTrue, reason: '$words');
      }
    });
  });

  group('a tooltip and a long press', () {
    testWidgets('a tappable\'s tooltip leaves a long press to what holds it', (
      tester,
    ) async {
      var held = 0;
      await _pump(
        tester,
        GestureDetector(
          onLongPress: () => held++,
          child: WaxTappable(
            label: 'Kitchen speaker',
            tooltip: 'Waits for Wi-Fi',
            onPressed: () {},
            child: const SizedBox(width: 200, height: 44),
          ),
        ),
      );
      await tester.longPress(find.byType(WaxTappable));
      await tester.pump();
      expect(held, 1);
      expect(find.text('Waits for Wi-Fi'), findsNothing);
    });

    testWidgets('a pill shows its detail on a long press', (tester) async {
      await _pump(
        tester,
        WaxButton(label: 'Retry', detail: 'No space left', onPressed: () {}),
      );
      await tester.longPress(find.byType(WaxButton));
      await tester.pump();
      expect(find.text('No space left'), findsOne);
    });
  });

  group('a key press told apart', () {
    testWidgets('a key runs onKeyPress, a pointer and a reader onPressed', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final heard = <String>[];
      void press() => heard.add('press');
      await _pump(
        tester,
        WaxTappable(
          label: 'About',
          semanticsId: 'about',
          onPressed: press,
          onKeyPress: () => heard.add('key'),
          child: InkWell(
            onTap: press,
            child: const SizedBox(width: 200, height: 44),
          ),
        ),
      );

      await tester.tap(find.byType(WaxTappable));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      tester.semantics.tap(
        find.semantics.byPredicate((node) => node.identifier == 'about'),
      );
      await tester.pump();
      expect(heard, <String>['press', 'key', 'key', 'press']);
      semantics.dispose();
    });

    testWidgets('a disabled control runs neither', (tester) async {
      var keys = 0;
      await _pump(
        tester,
        WaxTappable(
          label: 'About',
          onPressed: null,
          onKeyPress: () => keys++,
          tooltip: 'Not yet',
          child: const SizedBox(width: 200, height: 44),
        ),
      );
      // The tooltip keeps it a stop, so the key has a control to press.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(keys, 0);
    });
  });

  group('an icon button with a detail', () {
    testWidgets('shows the label then the detail, and reads the detail as '
        'its hint', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        WaxIconButton(
          glyph: WaxIcons.warning,
          label: 'Retry download',
          detail: 'No longer on the server',
          semanticsId: 'retry',
          onPressed: () {},
        ),
      );
      final node = tester
          .getSemantics(find.bySemanticsIdentifier('retry'))
          .getSemanticsData();
      expect(node.label, 'Retry download');
      expect(node.hint, 'No longer on the server');

      await tester.longPress(find.byType(WaxIconButton));
      await tester.pump();
      expect(find.text('Retry download\nNo longer on the server'), findsOne);
      semantics.dispose();
    });

    testWidgets('without one, shows only the label and has no hint', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        WaxIconButton(
          glyph: WaxIcons.downloads,
          label: 'Download',
          semanticsId: 'download',
          onPressed: () {},
        ),
      );
      final node = tester
          .getSemantics(find.bySemanticsIdentifier('download'))
          .getSemanticsData();
      expect(node.label, 'Download');
      expect(node.hint, isEmpty);

      await tester.longPress(find.byType(WaxIconButton));
      await tester.pump();
      expect(find.text('Download'), findsOne);
      semantics.dispose();
    });
  });
}
