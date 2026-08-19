import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// A seam a caller drives: it holds no width of its own, so every test
/// here plays the caller, clamping and handing back what it was told.
Future<void> _pump(
  WidgetTester tester, {
  required ValueNotifier<double> position,
  double min = 100,
  double max = 600,
  VoidCallback? onReset,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWaxTheme(),
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: ValueListenableBuilder<double>(
            valueListenable: position,
            builder: (context, at, _) => Row(
              children: <Widget>[
                SizedBox(
                  width: at,
                  child: const ColoredBox(color: Colors.grey),
                ),
                WaxSplitter(
                  position: at,
                  min: min,
                  max: max,
                  onReset: onReset,
                  onChanged: (value) => position.value = value,
                ),
                const Expanded(child: SizedBox.shrink()),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('splitter', () {
    testWidgets('follows the pointer one for one', (tester) async {
      final position = ValueNotifier<double>(300);
      addTearDown(position.dispose);
      await _pump(tester, position: position);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(WaxSplitter)),
      );
      // The first move buys past the arena's drag slop, which the
      // recogniser withholds; what follows is reported in full.
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      final grabbed = position.value;
      await gesture.moveBy(const Offset(45, 0));
      await tester.pump();
      expect(position.value, grabbed + 45);
      await gesture.up();
    });

    testWidgets('never reports past its bounds, and comes back from one', (
      tester,
    ) async {
      final position = ValueNotifier<double>(560);
      addTearDown(position.dispose);
      await _pump(tester, position: position);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(WaxSplitter)),
      );
      await gesture.moveBy(const Offset(300, 0));
      await tester.pump();
      expect(position.value, 600);

      // And a drag that ran past the end comes back the moment the
      // pointer does: the travel is measured from where the pointer
      // went rather than from where the seam had to stop, so the seam
      // does not sit dead until the overshoot has been undone twice.
      await gesture.moveBy(const Offset(-400, 0));
      await tester.pump();
      expect(position.value, lessThan(600));
      await gesture.up();
    });

    testWidgets('moves on the arrow keys, which is the whole of its keyboard', (
      tester,
    ) async {
      final position = ValueNotifier<double>(300);
      addTearDown(position.dispose);
      await _pump(tester, position: position);

      // Focus lands on it by traversal: a control only a pointer can
      // reach is a control half the people using this cannot.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(position.value, 300 + WaxSpace.s32);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(position.value, 300);
    });

    testWidgets('grows towards its own pane in either script', (tester) async {
      final position = ValueNotifier<double>(300);
      addTearDown(position.dispose);
      await _pump(tester, position: position, direction: TextDirection.rtl);

      // The pane before the seam is the leading one, which sits on the
      // right here: the pointer moving left is what widens it, and the
      // arrow key that widens is the one pointing away from the pane.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(WaxSplitter)),
      );
      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump();
      final grabbed = position.value;
      await gesture.moveBy(const Offset(-45, 0));
      await tester.pump();
      expect(position.value, grabbed + 45);
      await gesture.up();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final before = position.value;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(position.value, before + WaxSpace.s32);
    });

    testWidgets('reports a settled width once per gesture, not per frame', (
      tester,
    ) async {
      final position = ValueNotifier<double>(300);
      addTearDown(position.dispose);
      final settled = <double>[];
      var live = 0;
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWaxTheme(),
          home: Scaffold(
            body: ValueListenableBuilder<double>(
              valueListenable: position,
              builder: (context, at, _) => Row(
                children: <Widget>[
                  SizedBox(width: at),
                  WaxSplitter(
                    position: at,
                    min: 100,
                    max: 600,
                    onChanged: (value) {
                      live++;
                      position.value = value;
                    },
                    onSettled: settled.add,
                  ),
                  const Expanded(child: SizedBox.shrink()),
                ],
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(WaxSplitter)),
      );
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(6, 0));
        await tester.pump();
      }
      // The panes have to follow the pointer, so the live stream is
      // per frame; what a caller writes down is not.
      expect(live, greaterThan(1));
      expect(settled, isEmpty, reason: 'nothing has been settled on yet');

      await gesture.up();
      await tester.pumpAndSettle();
      expect(settled, hasLength(1));
      expect(settled.single, position.value);

      // A keyboard step has no release to wait for, so it settles itself.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(settled, hasLength(2));
      expect(settled.last, position.value);
    });

    testWidgets('hands the width back on a double tap', (tester) async {
      final position = ValueNotifier<double>(340);
      addTearDown(position.dispose);
      var reset = 0;
      await _pump(tester, position: position, onReset: () => reset++);

      await tester.tap(find.byType(WaxSplitter));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(WaxSplitter));
      await tester.pumpAndSettle();
      expect(reset, 1);
    });

    testWidgets('announces how far along its travel it sits', (tester) async {
      final handle = tester.ensureSemantics();
      final position = ValueNotifier<double>(250);
      addTearDown(position.dispose);
      await _pump(tester, position: position, min: 200, max: 400);

      // A quarter of the way from 200 to 400, said as a proportion:
      // a pixel width would tell a screen reader nothing about how much
      // is left on either side.
      //
      // Focusable, and saying so on this node: the arrow keys are half
      // of what this control is, and on the web a node that does not
      // publish itself as focusable gets no tab stop - so the keyboard
      // test below would pass on in-framework traversal while the
      // browser offered nothing.
      expect(
        tester.getSemantics(find.byType(WaxSplitter)),
        matchesSemantics(
          isSlider: true,
          hasEnabledState: false,
          isFocusable: true,
          hasFocusAction: true,
          label: 'Resize panes',
          value: '25%',
          increasedValue: '41%',
          decreasedValue: '9%',
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );
      handle.dispose();
    });
  });
}
