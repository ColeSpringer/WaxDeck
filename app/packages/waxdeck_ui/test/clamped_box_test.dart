import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

void main() {
  const box = Key('clamped');

  /// Pumps [height] pixels of content under a 100 pixel budget, and
  /// answers every overflow report the box made.
  Future<List<bool>> pump(
    WidgetTester tester, {
    required double height,
    bool clamped = true,
  }) async {
    final reports = <bool>[];
    await tester.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 200,
          child: ClampedBox(
            key: box,
            budget: 100,
            clamped: clamped,
            onOverflow: reports.add,
            child: SizedBox(height: height),
          ),
        ),
      ),
    );
    await tester.pump();
    return reports;
  }

  testWidgets('takes only the budget and says there is more', (tester) async {
    final reports = await pump(tester, height: 300);
    expect(tester.getSize(find.byKey(box)).height, 100);
    expect(reports, <bool>[true]);
  });

  testWidgets('content inside the budget is drawn whole and not offered', (
    tester,
  ) async {
    final reports = await pump(tester, height: 80);
    expect(tester.getSize(find.byKey(box)).height, 80);
    expect(reports, <bool>[false]);
  });

  testWidgets('half a pixel over is not more to show', (tester) async {
    final reports = await pump(tester, height: 100.4);
    expect(tester.getSize(find.byKey(box)).height, 100.4);
    expect(reports, <bool>[false]);
    // The estimates agree with the layout inside that margin too.
    final render = tester.renderObject<RenderBox>(find.byKey(box));
    expect(
      render.getDryLayout(const BoxConstraints(maxWidth: 200)).height,
      100.4,
    );
    expect(render.getMaxIntrinsicHeight(200), 100.4);
  });

  testWidgets('unfolded, it takes all of it and still knows it overflows', (
    tester,
  ) async {
    final reports = await pump(tester, height: 300, clamped: false);
    expect(tester.getSize(find.byKey(box)).height, 300);
    expect(reports, <bool>[true]);
  });

  testWidgets('dry layout and intrinsics answer the clamped size', (
    tester,
  ) async {
    await pump(tester, height: 300);
    final render = tester.renderObject<RenderBox>(find.byKey(box));
    expect(
      render.getDryLayout(const BoxConstraints(maxWidth: 200)).height,
      100,
    );
    expect(render.getMaxIntrinsicHeight(200), 100);
    expect(render.getMinIntrinsicHeight(200), 100);
  });
}
