import 'dart:async';

import 'package:flutter/rendering.dart' show RenderPhysicalShape;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// [bar] laid along the foot of an 800 by 600 page that counts the presses
/// reaching it in [presses].
Future<void> _pump(
  WidgetTester tester,
  Widget bar, {
  ThemeData? theme,
  List<Offset>? presses,
}) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? buildWaxTheme(),
      localizationsDelegates: waxLocalizationsDelegates,
      home: Scaffold(
        body: Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => presses?.add(details.globalPosition),
              ),
            ),
            Positioned(left: 0, right: 0, bottom: 0, child: bar),
          ],
        ),
      ),
    ),
  );
}

/// The bar itself, inside its inset.
Finder get _bar => find
    .descendant(of: find.byType(WaxMessageBar), matching: find.byType(Material))
    .first;

/// Where [node] is on screen.
Rect _onScreen(SemanticsNode node) {
  var rect = node.rect;
  for (var at = node; at.parent != null; at = at.parent!) {
    final transform = at.transform;
    if (transform != null) rect = MatrixUtils.transformRect(transform, rect);
  }
  return rect;
}

void main() {
  testWidgets('floats its inset inside the box it is laid in', (tester) async {
    await _pump(tester, const WaxMessageBar(message: 'Scan started'));

    final bar = tester.getRect(_bar);
    expect(bar.left, WaxMessageBar.inset.left);
    expect(bar.right, 800 - WaxMessageBar.inset.right);
    expect(bar.bottom, 600 - WaxMessageBar.inset.bottom);
    expect(
      tester.getRect(find.byType(WaxMessageBar)).top,
      bar.top - WaxMessageBar.inset.top,
    );
  });

  for (final variant in WaxThemeVariant.values) {
    testWidgets("is drawn in the ${variant.name} theme's tokens", (
      tester,
    ) async {
      await _pump(
        tester,
        WaxMessageBar(
          message: 'Restored Kind of Blue',
          actionLabel: 'Undo',
          onAction: () {},
        ),
        theme: buildWaxTheme(variant: variant),
      );

      final colors = variant.colors;
      final bar = tester.widget<Material>(_bar);
      expect(bar.color, colors.surface3);
      expect(bar.elevation, 6);
      expect(
        bar.shape,
        const RoundedRectangleBorder(borderRadius: WaxRadius.card),
      );
      final text = DefaultTextStyle.of(
        tester.element(find.text('Restored Kind of Blue')),
      ).style;
      expect(text.color, colors.textPrimary);
      expect(text.fontSize, WaxType.body.fontSize);
      expect(
        tester.widget<WaxButton>(find.byType(WaxButton)).kind,
        WaxButtonKind.text,
      );
    });
  }

  testWidgets('lands a theme switch in one frame', semanticsEnabled: false, (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final mode = ValueNotifier(ThemeMode.light);
    addTearDown(mode.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<ThemeMode>(
        valueListenable: mode,
        builder: (context, value, _) => MaterialApp(
          theme: buildWaxTheme(variant: WaxThemeVariant.light),
          darkTheme: buildWaxTheme(),
          themeMode: value,
          themeAnimationStyle: AnimationStyle.noAnimation,
          home: const Material(
            type: MaterialType.transparency,
            animationDuration: Duration.zero,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: WaxMessageBar(message: 'Scan started'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    mode.value = ThemeMode.dark;
    await tester.pump();

    final ground = tester.renderObject<RenderPhysicalShape>(
      find.descendant(of: _bar, matching: find.byType(PhysicalShape)).first,
    );
    expect(ground.color, WaxColors.dark.surface3);
    expect(
      DefaultTextStyle.of(tester.element(find.text('Scan started')))
          .style
          .color,
      WaxColors.dark.textPrimary,
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets("takes car mode's colours under it", (tester) async {
    await _pump(
      tester,
      const CarModeTheme(child: WaxMessageBar(message: 'Could not restore')),
    );

    expect(tester.widget<Material>(_bar).color, WaxColors.oled.surface3);
  });

  testWidgets("is one node, its bar's own: a live region a dismiss takes "
      'away, with its action a button inside it', (tester) async {
    var dismissed = 0;
    await _pump(
      tester,
      WaxMessageBar(
        message: 'Added 2 tracks to the queue',
        actionLabel: 'Open',
        onAction: () {},
        actionSemanticsId: 'queue-open',
        onDismiss: () => dismissed++,
      ),
    );

    final node = tester.getSemantics(find.text('Added 2 tracks to the queue'));
    expect(_onScreen(node), tester.getRect(_bar));
    final data = node.getSemanticsData();
    expect(data.label, 'Added 2 tracks to the queue');
    expect(data.flagsCollection.isLiveRegion, isTrue);
    expect(data.hasAction(SemanticsAction.dismiss), isTrue);
    final action = tester.getSemantics(
      find.bySemanticsIdentifier('queue-open'),
    );
    expect(action.parent, same(node));
    expect(action.label, 'Open');
    expect(action.getSemanticsData().flagsCollection.isButton, isTrue);

    tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.dismiss,
    );
    expect(dismissed, 1);
  });

  // Merged into the bar's node, a control's name and tap would be the bar's,
  // and a click anywhere on it would press the control. The two shapes in
  // which one control would merge on its own: no other tap beside it.
  for (final (shape, bar, names) in <(String, WaxMessageBar, List<String>)>[
    (
      'its close control beside an identified action',
      WaxMessageBar(
        message: 'Marked finished',
        actionLabel: 'Undo',
        onAction: () {},
        actionSemanticsId: 'undo',
        onClose: () {},
      ),
      <String>['Undo', 'Close'],
    ),
    (
      'an action with no identifier',
      WaxMessageBar(
        message: 'Marked finished',
        actionLabel: 'Undo',
        onAction: () {},
      ),
      <String>['Undo'],
    ),
  ]) {
    testWidgets('keeps $shape a node of its own inside its node', (
      tester,
    ) async {
      await _pump(tester, bar);

      final node = tester.getSemantics(find.text('Marked finished'));
      final data = node.getSemanticsData();
      expect(data.label, 'Marked finished');
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(data.flagsCollection.isButton, isFalse);
      final controls = <String>[];
      node.visitChildren((child) {
        final control = child.getSemanticsData();
        expect(control.flagsCollection.isButton, isTrue);
        expect(control.hasAction(SemanticsAction.tap), isTrue);
        controls.add(control.label);
        return true;
      });
      expect(controls, names);
    });
  }

  testWidgets('takes a press only on itself', (tester) async {
    final presses = <Offset>[];
    var acted = 0;
    await _pump(
      tester,
      WaxMessageBar(
        message: 'Restored Kind of Blue',
        actionLabel: 'Undo',
        onAction: () => acted++,
      ),
      presses: presses,
    );
    final bar = tester.getRect(_bar);

    final beside = <Offset>[
      Offset(bar.center.dx, bar.bottom + 5),
      Offset(bar.center.dx, bar.top - 2),
      Offset(bar.left - 5, bar.center.dy),
      Offset(bar.right + 5, bar.center.dy),
    ];
    for (final point in beside) {
      await tester.tapAt(point);
    }
    await tester.tapAt(Offset(bar.left + 20, bar.center.dy));
    await tester.tap(find.text('Undo'));

    expect(presses, beside);
    expect(acted, 1);
  });

  testWidgets('swiped down, is dismissed', (tester) async {
    var dismissed = 0;
    await _pump(
      tester,
      WaxMessageBar(message: 'Scan started', onDismiss: () => dismissed++),
    );

    await tester.drag(find.text('Scan started'), const Offset(0, 300));
    await tester.pumpAndSettle();

    expect(dismissed, 1);
  });

  testWidgets('stays put with nothing to dismiss it', (tester) async {
    await _pump(tester, const WaxMessageBar(message: 'Scan started'));

    await tester.drag(find.text('Scan started'), const Offset(0, 300));
    await tester.pumpAndSettle();

    expect(tester.getRect(_bar).bottom, 600 - WaxMessageBar.inset.bottom);
    final node = tester.getSemantics(find.text('Scan started'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.dismiss), isFalse);
  });

  testWidgets('closes from its close control, named for a screen reader', (
    tester,
  ) async {
    var closed = 0;
    var acted = 0;
    await _pump(
      tester,
      WaxMessageBar(
        message: 'Marked finished',
        actionLabel: 'Undo',
        onAction: () => acted++,
        onClose: () => closed++,
      ),
    );

    final close = find.bySemanticsLabel('Close');
    expect(close, findsOneWidget);
    await tester.tap(close);

    expect(closed, 1);
    expect(acted, 0);
  });

  testWidgets('rises into view as it fades in, and leaves by fading where it '
      'stands', (tester) async {
    final motion = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 250),
    );
    addTearDown(motion.dispose);
    await _pump(
      tester,
      WaxMessageBar(message: 'Scan started', animation: motion),
    );
    double shown() => tester.getSize(find.byType(WaxMessageBar)).height;
    double opacity() => tester
        .widget<FadeTransition>(
          find.descendant(
            of: find.byType(WaxMessageBar),
            matching: find.byType(FadeTransition),
          ),
        )
        .opacity
        .value;

    expect(shown(), 0);
    expect(find.bySemanticsLabel('Scan started'), findsNothing);

    motion.value = 0.5;
    await tester.pump();
    final full = tester.getSize(_bar).height + WaxMessageBar.inset.vertical;
    expect(shown(), closeTo(full * Curves.easeInOutQuart.transform(0.5), 1));
    expect(opacity(), greaterThan(0));
    expect(opacity(), lessThan(1));
    // Rising from its foot: the bar's bottom is already where it rests.
    expect(tester.getRect(_bar).bottom, 600 - WaxMessageBar.inset.bottom);

    motion.value = 1;
    await tester.pump();
    expect(shown(), full);
    expect(opacity(), 1);
    expect(find.bySemanticsLabel('Scan started'), findsOneWidget);

    unawaited(motion.reverse());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 125));
    expect(shown(), full);
    expect(opacity(), lessThan(1));
    await tester.pumpAndSettle();
    expect(opacity(), 0);
  });

  // A platform turns accessible navigation on as a reader starts reading
  // (Android's bridge on its first node request), so a node rebuilt then
  // is gone from under a reader that listed it a moment before.
  testWidgets('keeps its nodes as a screen reader comes and goes', (
    tester,
  ) async {
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final motion = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 250),
      value: 1,
    );
    addTearDown(motion.dispose);
    await _pump(
      tester,
      WaxMessageBar(
        message: 'Marked finished',
        actionLabel: 'Undo',
        onAction: () {},
        actionSemanticsId: 'undo',
        onClose: () {},
        animation: motion,
      ),
    );
    List<int> ids() => <int>[
      tester.getSemantics(find.text('Marked finished')).id,
      tester.getSemantics(find.bySemanticsIdentifier('undo')).id,
    ];
    final before = ids();

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    await tester.pump();
    expect(ids(), before, reason: 'a reader arriving');

    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    await tester.pump();
    expect(ids(), before, reason: 'a reader leaving');
  });

  testWidgets('read aloud, is there all at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final motion = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 250),
    );
    addTearDown(motion.dispose);
    await _pump(
      tester,
      WaxMessageBar(message: 'Scan started', animation: motion),
    );

    expect(
      tester.getSize(find.byType(WaxMessageBar)).height,
      tester.getSize(_bar).height + WaxMessageBar.inset.vertical,
    );
    expect(find.bySemanticsLabel('Scan started'), findsOneWidget);
  });
}
