import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// The cap has to bite under a sliver's tight cross-axis width, which is
/// the case a bare `ConstrainedBox` silently fails - and the reason this
/// component exists. Both sliver shapes the app puts a reading column in
/// are exercised, plus the plain box case, so a refactor that reaches
/// back for a `ConstrainedBox` fails here rather than on a wide window
/// nobody tests on.
void main() {
  const wide = Size(1400, 800);
  final marker = UniqueKey();

  // Fills whatever width it is offered, so its measured size *is* the
  // cap the column handed down - which is the thing under test.
  Widget probe() => SizedBox(key: marker, width: double.infinity, height: 40);

  double markerWidth(WidgetTester tester) =>
      tester.getSize(find.byKey(marker)).width;

  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.binding.setSurfaceSize(wide);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: home)));
  }

  testWidgets('caps inside SliverToBoxAdapter', (tester) async {
    await pump(
      tester,
      CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(child: ReadingColumn(child: probe())),
        ],
      ),
    );
    expect(markerWidth(tester), WaxSpace.readingWidth);
  });

  testWidgets('caps inside SliverList', (tester) async {
    await pump(
      tester,
      CustomScrollView(
        slivers: <Widget>[
          SliverList.list(children: <Widget>[ReadingColumn(child: probe())]),
        ],
      ),
    );
    expect(markerWidth(tester), WaxSpace.readingWidth);
  });

  testWidgets('caps inside a ListView', (tester) async {
    await pump(
      tester,
      ListView(children: <Widget>[ReadingColumn(child: probe())]),
    );
    expect(markerWidth(tester), WaxSpace.readingWidth);
  });

  testWidgets('a narrow window is left alone rather than stretched', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: ReadingColumn(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[probe()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(markerWidth(tester), 400);
  });

  testWidgets('sits against the leading edge, not the middle', (tester) async {
    await pump(
      tester,
      CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(child: ReadingColumn(child: probe())),
        ],
      ),
    );
    expect(tester.getTopLeft(find.byKey(marker)).dx, 0);
  });

  testWidgets('a flexed child still works under a bounded height', (
    tester,
  ) async {
    // Raised in review as a hazard of the `Align`. It is not one:
    // `loosen()` drops the minimum and keeps the maximum, so a bounded
    // height stays bounded and the flex resolves. The unbounded case
    // throws either way - a bare `ConstrainedBox` under the same sliver
    // throws the same `RenderFlex` assertion - so nothing about the cap
    // changed it.
    await pump(
      tester,
      CustomScrollView(
        slivers: <Widget>[
          SliverFillRemaining(
            hasScrollBody: false,
            child: ReadingColumn(
              child: Column(children: <Widget>[const Spacer(), probe()]),
            ),
          ),
        ],
      ),
    );
    expect(markerWidth(tester), WaxSpace.readingWidth);
  });

  testWidgets('a content-sized child measures its content, not the window', (
    tester,
  ) async {
    // The real consequence of the loose width, and the one worth
    // knowing: this is a shrink-wrap where a `ConstrainedBox` under the
    // same sliver reported the full window. Rows from this package fill
    // on their own; a column of bare text does not.
    final column = GlobalKey();
    await pump(
      tester,
      CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: ReadingColumn(
              child: Column(
                key: column,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const <Widget>[Text('short')],
              ),
            ),
          ),
        ],
      ),
    );
    expect(tester.getSize(find.byKey(column)).width, lessThan(200));
  });

  testWidgets('follows the reading direction rather than the left edge', (
    tester,
  ) async {
    // The alignment is directional, and the doc comment says so, so it
    // is held here: a "tidy-up" to `Alignment.topLeft` would pin the
    // column to the wrong side under RTL and nothing else would notice.
    await pump(
      tester,
      // `Directionality` rather than a locale: this package has no
      // localizations dependency and the app has no translations, so
      // the direction is what there is to assert on.
      Directionality(
        textDirection: TextDirection.rtl,
        child: CustomScrollView(
          slivers: <Widget>[
            SliverToBoxAdapter(child: ReadingColumn(child: probe())),
          ],
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(marker)).dx,
      wide.width - WaxSpace.readingWidth,
      reason: 'the column sits against the trailing edge under RTL',
    );
  });

  testWidgets('maxWidth overrides the reading width', (tester) async {
    await pump(
      tester,
      CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: ReadingColumn(maxWidth: 420, child: probe()),
          ),
        ],
      ),
    );
    expect(markerWidth(tester), 420);
  });
}
