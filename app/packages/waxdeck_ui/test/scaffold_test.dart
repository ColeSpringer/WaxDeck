import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// How much chrome sits above the first row of content, which is what
/// the report was about. Read off the content rather than off the bar:
/// a `SliverAppBar` is a sliver and has no box to measure.
Future<double> _chromeAboveContent(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWaxTheme(),
      home: const WaxScaffold(
        title: 'Music',
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: SizedBox(key: Key('content'), height: 2000),
          ),
        ],
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.getTopLeft(find.byKey(const Key('content'))).dy;
}

void main() {
  group('the large title band', () {
    testWidgets('is shallower on a phone than on a desktop window', (
      tester,
    ) async {
      // The reported forehead: a fixed 112 plus the status-bar inset a
      // primary bar adds to itself put a fifth of a phone window above
      // the first row of content.
      final compact = await _chromeAboveContent(tester, const Size(390, 844));
      final wide = await _chromeAboveContent(tester, const Size(1280, 900));
      expect(compact, lessThan(wide));
      expect(
        compact,
        WaxScaffold.shallowTitleHeight,
        reason: 'the drawn band is the height barHeight promises',
      );
      expect(wide, WaxScaffold.deepTitleHeight);
    });

    testWidgets('a phone on its side gets the shallow band too', (
      tester,
    ) async {
      // The size class is a width, and a landscape phone is 844 of them.
      // Taking the deep band and the 1.5x title there spends a fifth of
      // the shallowest window the app is ever drawn in on chrome - a
      // worse forehead than the portrait one this all started with.
      final landscape = await _chromeAboveContent(tester, const Size(844, 390));
      expect(landscape, WaxScaffold.shallowTitleHeight);
    });

    testWidgets('the title fits the band it is given', (tester) async {
      // A shallow band has no travel for Material's 1.5x expanded title
      // to fall through, so compact holds one size. If it did not, the
      // title would overflow the band it is drawn in.
      await _chromeAboveContent(tester, const Size(390, 844));
      expect(tester.takeException(), isNull);
      final title = tester.getRect(find.text('Music'));
      expect(title.height, lessThanOrEqualTo(WaxScaffold.shallowTitleHeight));
    });

    testWidgets('barHeight answers for the window it is asked in', (
      tester,
    ) async {
      late double large;
      late double small;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWaxTheme(),
          home: Builder(
            builder: (context) {
              large = WaxScaffold.barHeight(context);
              small = WaxScaffold.barHeight(context, largeTitle: false);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // The rail that reads this lays itself out under the bar; a stale
      // constant here puts its first letter behind the title.
      expect(large, WaxScaffold.shallowTitleHeight);
      expect(small, kToolbarHeight);
    });
  });
}
