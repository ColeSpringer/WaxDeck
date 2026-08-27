import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// The shelf under a pointer: mouse drag the row wires up for itself,
/// paging chevrons with real hit targets that appear only while there is
/// somewhere to go, an edge fade over the side with more cards, and a
/// viewport that reflows when the window is resized.

const _cardWidth = 120.0;
const _pitch = _cardWidth + WaxShellMetrics.gridGap;

/// What the shelf's cards were asked to do, in order.
final _taps = <String>[];
final _plays = <String>[];
final _menus = <String>[];

List<MediaTileData> _tiles(int count) => <MediaTileData>[
  for (var i = 0; i < count; i++)
    MediaTileData(title: 'Card $i', subtitle: 'Nightjar'),
];

Future<void> _pump(
  WidgetTester tester, {
  double width = 500,
  int cards = 12,
  bool reducedMotion = false,
  TextDirection textDirection = TextDirection.ltr,
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
        child: Directionality(
          textDirection: textDirection,
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
                  onTapItem: (tile) => _taps.add(tile.title),
                  onPlayItem: (tile) => _plays.add(tile.title),
                  onMoreItem: (tile) => _menus.add(tile.title),
                  backSemanticsId: 'shelf-test-back',
                  forwardSemanticsId: 'shelf-test-forward',
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // The chevron availability lands a frame after the metrics do, and
  // the widgets reading it rebuild the frame after that.
  await tester.pump();
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
  setUp(() {
    _taps.clear();
    _plays.clear();
    _menus.clear();
  });

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

  testWidgets('a near-miss on the chevron pages instead of hitting the card', (
    tester,
  ) async {
    await _pump(tester);
    await _hover(tester);
    // 18px diagonally off the circle's centre: outside the 32px circle,
    // inside the 44px box. Losing this tap to the card beneath is the
    // misplay the box exists to prevent.
    final centre = tester.getCenter(_chevron(forward: true));
    await tester.tapAt(centre + const Offset(18, 18));
    await tester.pumpAndSettle();
    expect(_offset(tester), 3 * _pitch + 16);
    // The card beneath is also in the hit path now that the halo is
    // translucent; the chevron wins the tap, the card must not.
    expect(_taps, isEmpty);
  });

  testWidgets('a drag that starts on the chevron halo still scrolls', (
    tester,
  ) async {
    // The halo forgives a near-miss tap; it must not confiscate the
    // gestures the row owns. Only the drawn circle absorbs them, the
    // way any button over a scrollable does.
    await _pump(tester);
    await _hover(tester);
    final start =
        tester.getCenter(_chevron(forward: true)) + const Offset(0, 20);
    await tester.dragFrom(start, const Offset(-2 * _pitch, 0));
    await tester.pumpAndSettle();
    expect(_offset(tester), greaterThan(0));
    expect(_taps, isEmpty);
  });

  testWidgets('a secondary tap in the halo reaches the card menu', (
    tester,
  ) async {
    await _pump(tester);
    await _hover(tester);
    final centre = tester.getCenter(_chevron(forward: true));
    await tester.tapAt(
      centre + const Offset(18, 18),
      kind: PointerDeviceKind.mouse,
      pointer: 9,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(_menus, hasLength(1));
    expect(_offset(tester), 0);
  });

  testWidgets('a retiring chevron neither answers nor announces', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, cards: 5);
    await _hover(tester);
    await tester.tap(_chevron(forward: true));
    // Walk frames to mid-fade: widget mounted, semantics withdrawn.
    // Without the gate no such frame exists, so the loop times out red.
    var midFade = false;
    for (var i = 0; i < 60 && !midFade; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      midFade =
          _chevron(forward: true).evaluate().isNotEmpty &&
          find.semantics.byLabel('Scroll forward').evaluate().isEmpty;
    }
    expect(midFade, isTrue, reason: 'the fade never opened a gated frame');

    // A tap where the chevron still faintly draws belongs to the card
    // beneath it.
    await tester.tapAt(tester.getCenter(_chevron(forward: true)));
    await tester.pumpAndSettle();
    expect(_taps, hasLength(1));
    handle.dispose();
  });

  testWidgets('a tap outside the 44px box still reaches the card', (
    tester,
  ) async {
    await _pump(tester);
    await _hover(tester);
    // 30px below the centre: past the box's 22px half-extent, on the
    // artwork of the card the chevron floats over.
    final centre = tester.getCenter(_chevron(forward: true));
    await tester.tapAt(centre + const Offset(0, 30));
    await tester.pumpAndSettle();
    expect(_offset(tester), 0);
    expect(_taps, hasLength(1));
  });

  testWidgets('desktop shows chevrons at rest, and only while they can go', (
    tester,
  ) async {
    double dim() => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: _chevron(forward: true),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;

    await _pump(tester, cards: 5);
    // A desktop platform with no pointer hardware - a touch-only
    // machine the web reports as linux - keeps the hover contract.
    expect(_chevron(forward: true), findsNothing);

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      pointer: 7,
    );
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();

    // A mouse exists, nowhere near the shelf: the overflow shows,
    // dimmed but well above invisible.
    expect(_chevron(forward: true), findsOneWidget);
    expect(_chevron(forward: false), findsNothing);
    expect(dim(), lessThan(1));
    expect(dim(), greaterThanOrEqualTo(0.7));

    await gesture.moveTo(tester.getCenter(_shelf));
    await tester.pumpAndSettle();
    expect(dim(), 1);

    await tester.tap(_chevron(forward: true));
    await tester.pumpAndSettle();
    expect(_chevron(forward: true), findsNothing);
    expect(_chevron(forward: false), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('RTL points the carets the way the row actually moves', (
    tester,
  ) async {
    await _pump(tester, textDirection: TextDirection.rtl);
    await _hover(tester);
    // Only forward has anywhere to go at the start, and in RTL forward
    // is the left edge, so the one armed chevron draws the left caret.
    Finder caret(WaxGlyph glyph) =>
        find.byWidgetPredicate((w) => w is WaxIcon && w.glyph == glyph);
    expect(caret(WaxIcons.backward), findsOneWidget);
    expect(caret(WaxIcons.forward), findsNothing);
    expect(tester.getCenter(caret(WaxIcons.backward)).dx, lessThan(250));

    await tester.tap(caret(WaxIcons.backward));
    await tester.pumpAndSettle();
    expect(_offset(tester), greaterThan(0));
  });

  testWidgets('touch keeps the chevrons hover-armed only', (tester) async {
    // Overflow exists, but with no pointer the chevrons stay out of the
    // way of a finger that scrolls the row directly.
    await _pump(tester);
    expect(_chevron(forward: true), findsNothing);
    expect(_chevron(forward: false), findsNothing);
  });

  testWidgets('the edge fade sits only over the side with more cards', (
    tester,
  ) async {
    EdgeFade fade() => tester.widget<EdgeFade>(find.byType(EdgeFade));

    await _pump(tester, cards: 5);
    expect(fade().start, 0);
    expect(fade().end, greaterThan(0));

    await _hover(tester);
    await tester.tap(_chevron(forward: true));
    await tester.pumpAndSettle();
    expect(fade().start, greaterThan(0));
    expect(fade().end, 0);
  });

  testWidgets('no overflow, no fade', (tester) async {
    await _pump(tester, cards: 2, width: 700);
    final fade = tester.widget<EdgeFade>(find.byType(EdgeFade));
    expect(fade.start, 0);
    expect(fade.end, 0);
  });

  testWidgets('a chevron is a labelled semantics button', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    await _hover(tester);
    expect(
      tester.getSemantics(_chevron(forward: true)),
      matchesSemantics(
        isButton: true,
        label: 'Scroll forward',
        identifier: 'shelf-test-forward',
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });
}
