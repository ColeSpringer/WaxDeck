import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// Two targets side by side, which is the row of icon buttons the
/// reported bug is about.
Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWaxTheme(),
      home: const Scaffold(
        body: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              WaxTooltip(
                message: 'Shuffle',
                child: SizedBox(width: 48, height: 48, child: Text('A')),
              ),
              WaxTooltip(
                message: 'Repeat',
                child: SizedBox(width: 48, height: 48, child: Text('B')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The theme's wait, which is what every instance is meant to serve.
const _wait = Duration(milliseconds: 400);

void main() {
  testWidgets('a label waits its delay before it appears', (tester) async {
    await _pump(tester);
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);

    await pointer.moveTo(tester.getCenter(find.text('A')));
    await tester.pump();
    expect(find.text('Shuffle'), findsNothing);

    await tester.pump(_wait);
    await tester.pump();
    expect(find.text('Shuffle'), findsOneWidget);
  });

  testWidgets('the next target waits its own delay, not none at all', (
    tester,
  ) async {
    // Material shares one open set across every tooltip in the tree, so
    // a second target opens instantly for as long as the first is still
    // fading. Crossing a row of icon buttons then trails a label from
    // every button on the way.
    await _pump(tester);
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);

    await pointer.moveTo(tester.getCenter(find.text('A')));
    await tester.pump(_wait);
    await tester.pump();
    expect(find.text('Shuffle'), findsOneWidget);

    await pointer.moveTo(tester.getCenter(find.text('B')));
    await tester.pump();
    expect(find.text('Shuffle'), findsNothing, reason: 'leaving dismisses it');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Repeat'), findsNothing, reason: 'half the wait is not');

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('Repeat'), findsOneWidget);
  });

  testWidgets('leaving the target takes the label with it', (tester) async {
    await _pump(tester);
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);

    await pointer.moveTo(tester.getCenter(find.text('A')));
    await tester.pump(_wait);
    await tester.pump();
    expect(find.text('Shuffle'), findsOneWidget);

    await pointer.moveTo(Offset.zero);
    await tester.pump();
    expect(find.text('Shuffle'), findsNothing);
  });

  testWidgets('a press dismisses it, and does not open one behind it', (
    tester,
  ) async {
    await _pump(tester);
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);

    await pointer.moveTo(tester.getCenter(find.text('A')));
    await tester.pump(_wait);
    await tester.pump();
    expect(find.text('Shuffle'), findsOneWidget);

    await tester.tap(find.text('A'));
    await tester.pump();
    expect(find.text('Shuffle'), findsNothing);
  });

  testWidgets('a long press is how a touch device asks for one', (
    tester,
  ) async {
    await _pump(tester);

    await tester.longPress(find.text('A'));
    await tester.pump();
    expect(find.text('Shuffle'), findsOneWidget);

    // And it goes on its own, since a finger has nowhere to hover away
    // to.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump();
    expect(find.text('Shuffle'), findsNothing);
  });

  testWidgets('a target that owns the long press keeps it', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWaxTheme(),
        home: Scaffold(
          body: Center(
            child: WaxTooltip(
              message: 'Kind of Blue',
              touchTrigger: false,
              excludeFromSemantics: true,
              child: GestureDetector(
                onLongPress: () => pressed++,
                child: const SizedBox(width: 48, height: 48, child: Text('A')),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.longPress(find.text('A'));
    await tester.pump();
    expect(pressed, 1);
    expect(find.text('Kind of Blue'), findsNothing);
  });

  testWidgets('only the innermost of a nest opens', (tester) async {
    // Tooltips nest: a card names itself on hover and the play
    // affordance drawn over its artwork names itself too. Both regions
    // contain the pointer, so two labels used to open a few pixels
    // apart - Material shows only the inner one.
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWaxTheme(),
        home: Scaffold(
          body: Center(
            child: WaxTooltip(
              message: 'The whole card',
              child: SizedBox(
                width: 120,
                height: 120,
                child: Center(
                  child: WaxTooltip(
                    message: 'Play',
                    child: SizedBox(width: 40, height: 40, child: Text('P')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);

    await pointer.moveTo(tester.getCenter(find.text('P')));
    await tester.pump(_wait);
    await tester.pump();

    expect(find.text('Play'), findsOneWidget);
    expect(find.text('The whole card'), findsNothing);
  });

  testWidgets('the label is placed against the overlay it is drawn in', (
    tester,
  ) async {
    // An app's overlays do not begin at the window origin: a screen
    // inside the shell sits in a branch navigator whose overlay starts
    // after the nav rail. Measured against the window, every tooltip on
    // such a screen drew a rail's width to the right of its control.
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWaxTheme(),
        home: Scaffold(
          body: Row(
            children: <Widget>[
              const SizedBox(width: 200, child: ColoredBox(color: Colors.grey)),
              Expanded(
                child: Overlay(
                  initialEntries: <OverlayEntry>[
                    OverlayEntry(
                      builder: (context) => const Center(
                        child: WaxTooltip(
                          message: 'Shuffle',
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Text('A'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);

    await pointer.moveTo(tester.getCenter(find.text('A')));
    await tester.pump(_wait);
    await tester.pump();

    expect(
      tester.getCenter(find.text('Shuffle')).dx,
      moreOrLessEquals(tester.getCenter(find.text('A')).dx, epsilon: 1),
      reason: 'the label sits over its control, not an overlay origin away',
    );
  });

  testWidgets('a screen reader is given the description Material gave it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    expect(
      tester.getSemantics(find.text('A')).getSemanticsData().tooltip,
      'Shuffle',
    );
    handle.dispose();
  });
}
