import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: buildWaxTheme(),
    home: Scaffold(body: Center(child: child)),
  ),
);

/// The line itself: the one box drawn in the hairline colour.
Rect _line(WidgetTester tester) => tester.getRect(
  find.descendant(
    of: find.byType(WaxHairline),
    matching: find.byWidgetPredicate(
      (w) =>
          w is ColoredBox &&
          w.color ==
              WaxColors.of(tester.element(find.byType(WaxHairline))).hairline,
    ),
  ),
);

void main() {
  testWidgets('a hairline is one pixel across the room it is given', (
    tester,
  ) async {
    await _pump(tester, const SizedBox(width: 200, child: WaxHairline()));
    expect(tester.getSize(find.byType(WaxHairline)), const Size(200, 1));
    expect(_line(tester).size, const Size(200, 1));
  });

  testWidgets('a band centres its line in the room across it', (tester) async {
    await _pump(
      tester,
      const SizedBox(width: 200, child: WaxHairline(extent: WaxSpace.s16)),
    );
    final band = tester.getRect(find.byType(WaxHairline));
    expect(band.size, const Size(200, WaxSpace.s16));
    final line = _line(tester);
    expect(line.size, const Size(200, 1));
    expect(line.center.dy, moreOrLessEquals(band.center.dy));
  });

  // What the ratchet's fix tells a sweep: the band a divider took is the
  // hairline's extent, and the theme's bare divider is the line alone.
  testWidgets('a hairline stands in for a divider band for band', (
    tester,
  ) async {
    Future<Size> size(Widget line, {bool across = true}) async {
      await _pump(
        tester,
        across
            ? SizedBox(width: 200, child: line)
            : SizedBox(height: 120, child: line),
      );
      return tester.getSize(find.byWidget(line));
    }

    expect(await size(const Divider()), await size(const WaxHairline()));
    expect(
      await size(const Divider(height: WaxSpace.s16)),
      await size(const WaxHairline(extent: WaxSpace.s16)),
    );
    expect(
      await size(const VerticalDivider(), across: false),
      await size(const WaxHairline.vertical(), across: false),
    );
    expect(
      await size(const VerticalDivider(width: WaxSpace.s12), across: false),
      await size(
        const WaxHairline.vertical(extent: WaxSpace.s12),
        across: false,
      ),
    );
  });

  testWidgets('a vertical hairline runs the height between two panes', (
    tester,
  ) async {
    await _pump(
      tester,
      const SizedBox(
        height: 120,
        child: Row(
          children: <Widget>[
            SizedBox(width: 40),
            WaxHairline.vertical(),
            SizedBox(width: 40),
          ],
        ),
      ),
    );
    expect(tester.getSize(find.byType(WaxHairline)), const Size(1, 120));
    expect(_line(tester).size, const Size(1, 120));
  });

  testWidgets('with no width to fill it takes none rather than throwing', (
    tester,
  ) async {
    await _pump(
      tester,
      const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[WaxHairline()],
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(WaxHairline)).width, 0);
  });
}
