import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// The shelf under a pointer: mouse drag the row wires up for itself,
/// paging chevrons that appear only while there is somewhere to go, and
/// a viewport that reflows when the window is resized.

const _cardWidth = 120.0;
const _pitch = _cardWidth + WaxShellMetrics.gridGap;

List<MediaTileData> _tiles(int count) => <MediaTileData>[
  for (var i = 0; i < count; i++)
    MediaTileData(title: 'Card $i', subtitle: 'Nightjar'),
];

Future<void> _pump(
  WidgetTester tester, {
  double width = 500,
  int cards = 12,
  bool reducedMotion = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWaxTheme(),
      home: MediaQuery(
        // A real window size, not a bare MediaQueryData: WaxSizeClass
        // reads it, and a defaulted Size.zero would report compact
        // whatever the SizedBox below says.
        data: MediaQueryData(
          size: Size(width, 600),
          disableAnimations: reducedMotion,
        ),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: ShelfRow(
                title: 'Recently added',
                cardWidth: _cardWidth,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                items: _tiles(cards),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // The chevron availability lands a frame after the metrics do.
  await tester.pump();
}

Finder get _shelf => find.byType(ListView);

double _offset(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

/// Rests a mouse pointer on the shelf and keeps the gesture alive so
/// the hover holds for the rest of the test.
Future<TestGesture> _hover(WidgetTester tester) async {
  final gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    pointer: 7,
  );
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await gesture.moveTo(tester.getCenter(_shelf));
  await tester.pumpAndSettle();
  return gesture;
}

/// The chevron pointing [forward], found by its glyph.
Finder _chevron({required bool forward}) => find.byWidgetPredicate(
  (widget) =>
      widget is WaxIcon &&
      widget.glyph == (forward ? WaxIcons.forward : WaxIcons.backward),
);

void main() {
  testWidgets('a widened window reveals more cards on its own', (tester) async {
    // The reported bug's other half: growing the window was said not to
    // show more items. The row is a plain viewport, so it must.
    await _pump(tester, width: 400);
    final narrow = find.textContaining('Card ').evaluate().length;
    await _pump(tester, width: 780);
    final wide = find.textContaining('Card ').evaluate().length;
    expect(wide, greaterThan(narrow));
  });

  testWidgets('a mouse can drag the shelf', (tester) async {
    await _pump(tester);
    expect(_offset(tester), 0);
    await tester.drag(
      _shelf,
      const Offset(-2 * _pitch, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(_offset(tester), greaterThan(0));
  });

  testWidgets('chevrons appear under a pointer, each only where it can go', (
    tester,
  ) async {
    await _pump(tester);
    // Nothing before the pointer arrives: touch never sees them.
    expect(_chevron(forward: true), findsNothing);

    await _hover(tester);
    // At the start there is nowhere back to go.
    expect(_chevron(forward: true), findsOneWidget);
    expect(_chevron(forward: false), findsNothing);

    await tester.tap(_chevron(forward: true));
    await tester.pumpAndSettle();
    expect(_chevron(forward: false), findsOneWidget);

    // A page is a viewport's worth of whole cards, landed on the same
    // grid a flick's SnapScrollPhysics settles on (k * pitch + inset):
    // 500px of viewport holds three whole 132px pitches.
    expect(_offset(tester), 3 * _pitch + 16);
  });

  testWidgets('paging back reaches the true start, not the grid', (
    tester,
  ) async {
    // The snap grid's first landing sits one inset past zero; a page
    // back that stopped there would leave the leading gutter scrolled
    // away and the back chevron still armed for sixteen pixels.
    await _pump(tester);
    await _hover(tester);
    await tester.tap(_chevron(forward: true));
    await tester.pumpAndSettle();
    expect(_offset(tester), greaterThan(0));

    await tester.tap(_chevron(forward: false));
    await tester.pumpAndSettle();
    expect(_offset(tester), 0);
    expect(_chevron(forward: false), findsNothing);
  });

  testWidgets('the last page retires the forward chevron', (tester) async {
    await _pump(tester, cards: 5);
    await _hover(tester);
    await tester.tap(_chevron(forward: true));
    await tester.pumpAndSettle();

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.pixels, position.maxScrollExtent);
    expect(_chevron(forward: true), findsNothing);
    expect(_chevron(forward: false), findsOneWidget);
  });

  testWidgets('a resize that strands overflow arms the forward chevron', (
    tester,
  ) async {
    // Wide enough for everything: no chevron has anywhere to go.
    await _pump(tester, cards: 4, width: 700);
    final gesture = await _hover(tester);
    expect(_chevron(forward: true), findsNothing);

    // Shrunk: the overflow the resize strands is exactly what the
    // chevron exists to reach. The pointer follows the shelf, which
    // moved out from under its old position.
    await _pump(tester, cards: 4, width: 300);
    await gesture.moveTo(tester.getCenter(_shelf));
    await tester.pumpAndSettle();
    expect(_chevron(forward: true), findsOneWidget);
  });

  testWidgets('reduced motion pages in one jump', (tester) async {
    await _pump(tester, reducedMotion: true);
    await _hover(tester);
    await tester.tap(_chevron(forward: true));
    // One frame, no settle: the move must already be complete.
    await tester.pump();
    expect(_offset(tester), 3 * _pitch + 16);
  });
}
