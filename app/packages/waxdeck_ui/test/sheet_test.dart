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

  group("a sheet takes a side inset only where it reaches that side", () {
    final surface = find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Material),
        )
        .first;
    final content = find.byKey(const Key('content'));

    Future<void> openAt(
      WidgetTester tester,
      Size size,
      FakeViewPadding insets,
    ) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1
        ..padding = insets
        ..viewPadding = insets;
      addTearDown(tester.view.reset);
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
                    builder: (_) => const SafeArea(
                      top: false,
                      child: SizedBox(
                        key: Key('content'),
                        width: double.infinity,
                        height: 40,
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

    testWidgets('narrower than the window, a cutout it does not reach does '
        'not indent it', (tester) async {
      await openAt(
        tester,
        const Size(1000, 700),
        const FakeViewPadding(left: 44, right: 30),
      );
      final sheet = tester.getRect(surface);
      expect((sheet.left, sheet.right), (180.0, 820.0));
      final inner = tester.getRect(content);
      expect((inner.left, inner.right), (sheet.left, sheet.right));
    });

    testWidgets('as wide as the window, it takes the cutouts at both sides', (
      tester,
    ) async {
      await openAt(
        tester,
        const Size(600, 700),
        const FakeViewPadding(left: 44, right: 30),
      );
      final sheet = tester.getRect(surface);
      expect((sheet.left, sheet.right), (0.0, 600.0));
      final inner = tester.getRect(content);
      expect((inner.left, inner.right), (44.0, 570.0));
    });

    testWidgets('a cutout reaching past the gap beside it is taken for what '
        'of it reaches', (tester) async {
      await openAt(
        tester,
        const Size(700, 700),
        const FakeViewPadding(left: 44),
      );
      final sheet = tester.getRect(surface);
      expect((sheet.left, sheet.right), (30.0, 670.0));
      final inner = tester.getRect(content);
      expect((inner.left, inner.right), (44.0, 670.0));
    });

    testWidgets('a window narrowed under it lays it out again the same '
        'frame', (tester) async {
      await openAt(
        tester,
        const Size(1000, 700),
        const FakeViewPadding(left: 44),
      );
      tester.view.physicalSize = const Size(600, 700);
      await tester.pump();
      expect(tester.getRect(content).left, 44);
      tester.view.physicalSize = const Size(1000, 700);
      await tester.pump();
      expect(tester.getRect(content).left, tester.getRect(surface).left);
    });
  });
}
