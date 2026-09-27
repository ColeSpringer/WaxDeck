import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

const _help = 'Paste the address the file came from';

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWaxTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: WaxButton(
              label: 'Open',
              onPressed: () => showWaxSheet<void>(
                context: context,
                builder: (_) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[WaxProse(_help), SizedBox(height: 160)],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    "a mouse drag down a sheet's text selects it and leaves the sheet",
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
    (tester) async {
      // The sheet's drag took a mouse's first pixel down, and a release
      // past half height closed it with the edit in it.
      await _open(tester);
      final line = tester.getRect(find.text(_help));
      final top = tester.getTopLeft(find.byType(BottomSheet)).dy;
      final gesture = await tester.startGesture(
        line.centerLeft + const Offset(2, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      // Straight down, in the small steps a real mouse reports.
      for (var step = 0; step < 60; step++) {
        await gesture.moveBy(const Offset(0, 1.5));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text(_help), findsOneWidget);
      expect(tester.getTopLeft(find.byType(BottomSheet)).dy, top);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(copied, isNotEmpty);
    },
  );

  testWidgets(
    'its handle still pulls it closed with a mouse',
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
    (tester) async {
      await _open(tester);
      final handle = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_DragHandle',
      );
      final gesture = await tester.startGesture(
        tester.getCenter(handle),
        kind: PointerDeviceKind.mouse,
      );
      for (var step = 0; step < 20; step++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text(_help), findsNothing);
    },
  );

  testWidgets('a finger pulls it closed from anywhere', (tester) async {
    await _open(tester);
    await tester.fling(find.text(_help), const Offset(0, 400), 1500);
    await tester.pumpAndSettle();
    expect(find.text(_help), findsNothing);
    expect(defaultTargetPlatform, TargetPlatform.android);
  });
}
