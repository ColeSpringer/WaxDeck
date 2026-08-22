import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

Widget _host(Widget child) => MaterialApp(
  theme: buildWaxTheme(variant: WaxThemeVariant.dark),
  home: Scaffold(body: child),
);

/// What the switch holds and what it concluded, together.
///
/// The second half is the point of the file and used to go unread: the
/// depth is mutated synchronously by enter and leave, so a suite that
/// only counts it stays green with the drain gutted and the browser menu
/// never actually suppressed. Off the web the platform call is skipped
/// but the bookkeeping still runs, so this is observable everywhere.
void _expectMenu(int depth, {required bool suppressed}) {
  expect(debugBrowserMenuState.$1, depth, reason: 'regions holding');
  expect(debugBrowserMenuState.$2, suppressed, reason: 'menu suppressed');
}

/// A pointer parked outside every region, so a test moves it in rather
/// than starting inside one.
Future<TestGesture> _pointer(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  return gesture;
}

void main() {
  setUp(debugResetBrowserMenu);
  tearDown(debugResetBrowserMenu);

  group('the browser menu comes back off a surface that answers', () {
    testWidgets('is held only while the pointer is over an answering one', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Column(
            children: <Widget>[
              const SizedBox(height: 100, key: Key('outside')),
              WaxSecondaryTapRegion(
                child: Container(
                  height: 100,
                  color: const Color(0xFF000000),
                  key: const Key('inside'),
                ),
              ),
            ],
          ),
        ),
      );
      final gesture = await _pointer(tester);

      await gesture.moveTo(tester.getCenter(find.byKey(const Key('inside'))));
      await tester.pump();
      _expectMenu(1, suppressed: true);

      await gesture.moveTo(tester.getCenter(find.byKey(const Key('outside'))));
      await tester.pump();
      _expectMenu(0, suppressed: false);
    });

    testWidgets('a region with nothing to raise never takes it', (
      tester,
    ) async {
      // Which is what makes the suppression follow the surfaces that
      // answer rather than the whole page: a row without a menu is
      // exactly the text and artwork somebody wants to copy.
      await tester.pumpWidget(
        _host(
          WaxSecondaryTapRegion(
            enabled: false,
            child: Container(
              height: 100,
              color: const Color(0xFF000000),
              key: const Key('inside'),
            ),
          ),
        ),
      );
      final gesture = await _pointer(tester);

      await gesture.moveTo(tester.getCenter(find.byKey(const Key('inside'))));
      await tester.pump();
      _expectMenu(0, suppressed: false);
    });

    testWidgets('nested regions hand it back once, not twice', (tester) async {
      // A card inside a shelf that also answers: leaving the inner one
      // must not switch the menu back on while the pointer is still in
      // the outer.
      await tester.pumpWidget(
        _host(
          WaxSecondaryTapRegion(
            child: Container(
              height: 200,
              color: const Color(0xFF000000),
              alignment: Alignment.topCenter,
              child: WaxSecondaryTapRegion(
                child: Container(
                  height: 60,
                  width: 200,
                  color: const Color(0xFF111111),
                  key: const Key('inner'),
                ),
              ),
            ),
          ),
        ),
      );
      final gesture = await _pointer(tester);

      await gesture.moveTo(tester.getCenter(find.byKey(const Key('inner'))));
      await tester.pump();
      _expectMenu(2, suppressed: true);

      // Still inside the outer region - it is 200 tall and the inner is
      // the top 60 of it - so the menu stays held.
      await gesture.moveTo(const Offset(200, 150));
      await tester.pump();
      _expectMenu(1, suppressed: true);
    });

    testWidgets('a row scrolled out from under the pointer lets go', (
      tester,
    ) async {
      // No exit event ever arrives for a region that is unmounted while
      // the pointer is inside it, so the count has to be released on
      // dispose or the page keeps the menu switched off for good.
      Widget build({required bool showing}) => _host(
        showing
            ? WaxSecondaryTapRegion(
                child: Container(
                  height: 100,
                  color: const Color(0xFF000000),
                  key: const Key('inside'),
                ),
              )
            : const SizedBox.expand(),
      );

      await tester.pumpWidget(build(showing: true));
      final gesture = await _pointer(tester);
      await gesture.moveTo(tester.getCenter(find.byKey(const Key('inside'))));
      await tester.pump();
      _expectMenu(1, suppressed: true);

      await tester.pumpWidget(build(showing: false));
      await tester.pump();
      _expectMenu(0, suppressed: false);
    });

    testWidgets('a row that loses its menu under the pointer lets go too', (
      tester,
    ) async {
      Widget build({required bool enabled}) => _host(
        WaxSecondaryTapRegion(
          enabled: enabled,
          child: Container(
            height: 100,
            color: const Color(0xFF000000),
            key: const Key('inside'),
          ),
        ),
      );

      await tester.pumpWidget(build(enabled: true));
      final gesture = await _pointer(tester);
      await gesture.moveTo(tester.getCenter(find.byKey(const Key('inside'))));
      await tester.pump();
      _expectMenu(1, suppressed: true);

      await tester.pumpWidget(build(enabled: false));
      await tester.pump();
      _expectMenu(0, suppressed: false);
    });
  });

  group('a menu of our own holds it across the route', () {
    testWidgets('the modal barrier taking the pointer does not hand it back', (
      tester,
    ) async {
      // The regression this pairing exists to stop. A route raises a
      // modal barrier, the barrier is an opaque MouseRegion covering
      // the screen, so the surface underneath is told the pointer left
      // the instant the menu opens - and the menu that appears would be
      // standing over a browser menu switched back on, ready to stack a
      // second one on top of the first.
      await tester.pumpWidget(
        _host(
          WaxSecondaryTapRegion(
            child: Builder(
              builder: (context) => WaxMenuButton<String>(
                items: const <WaxMenuItem<String>>[
                  WaxMenuItem<String>(value: 'a', label: 'An option'),
                ],
                onSelected: (_) {},
                semanticsId: 'menu-trigger',
              ),
            ),
          ),
        ),
      );
      final gesture = await _pointer(tester);
      await gesture.moveTo(
        tester.getCenter(find.byType(WaxMenuButton<String>)),
      );
      await tester.pump();
      _expectMenu(1, suppressed: true);

      await tester.tap(find.byType(WaxMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('An option'), findsOneWidget);
      // The pointer has been taken by the barrier, so the region has let
      // go - and the menu is still held, by the route rather than by the
      // pointer.
      expect(
        debugBrowserMenuState.$2,
        isTrue,
        reason: 'held while our own menu is on screen',
      );

      // Closing hands it back to the pointer, which is over the trigger
      // again now that the barrier is gone - so the hold passes from the
      // route to the region without the menu ever coming back on.
      await tester.tap(find.text('An option'));
      await tester.pumpAndSettle();
      _expectMenu(1, suppressed: true);

      // The far corner: the region wraps the button alone, and the
      // button sits at the body's top-left, so the origin is inside it.
      await gesture.moveTo(const Offset(799, 599));
      await tester.pump();
      _expectMenu(0, suppressed: false);
    });

    testWidgets('the hold is released even when the body throws', (
      tester,
    ) async {
      await expectLater(
        waxWithoutBrowserMenu<void>(() async => throw StateError('nope')),
        throwsStateError,
      );
      await tester.pump();
      _expectMenu(0, suppressed: false);
    });
  });
}
