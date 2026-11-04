import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/shell/paged_scroll.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// A list of [rows] rows, 50 tall, that counts what it asks for and
/// says more is behind it while [more]. [loaded] is the screen's loaded
/// list: the same object across rebuilds is a page that failed, a new one
/// is a page that landed or a reload.
class _Paged extends StatefulWidget {
  _Paged({
    int? rows,
    List<int>? loaded,
    required this.asks,
    this.more = true,
    this.ahead,
  }) : loaded = loaded ?? List<int>.filled(rows!, 0);

  final List<int> loaded;
  final List<int> asks;
  final bool more;
  final double? ahead;

  int get rows => loaded.length;

  @override
  State<_Paged> createState() => _PagedState();
}

class _PagedState extends State<_Paged> with PagedScroll {
  @override
  double get pageAhead => widget.ahead ?? super.pageAhead;

  @override
  void loadMore() => widget.asks.add(widget.rows);

  @override
  Widget build(BuildContext context) {
    fillViewportWhile(widget.more, at: widget.loaded);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ListView.builder(
        controller: pagedScroll,
        itemCount: widget.rows,
        itemExtent: 50,
        itemBuilder: (_, i) => Text('row $i'),
      ),
    );
  }
}

void main() {
  testWidgets('a short list with more behind it asks once laid out', (
    tester,
  ) async {
    final asks = <int>[];
    await tester.pumpWidget(_Paged(rows: 3, asks: asks));
    await tester.pump();

    expect(asks, <int>[3]);
  });

  testWidgets('a next page that fails is asked for once per loaded list', (
    tester,
  ) async {
    final asks = <int>[];
    // A failing read leaves the loaded list as it was, and the screen
    // rebuilds frame after frame over it.
    final held = <int>[1, 2, 3];
    for (var frame = 0; frame < 5; frame++) {
      await tester.pumpWidget(_Paged(loaded: held, asks: asks));
      await tester.pump();
    }
    expect(asks, <int>[3]);

    // A page that lands is a new list, and the fill may ask again.
    await tester.pumpWidget(_Paged(loaded: <int>[1, 2, 3, 4], asks: asks));
    await tester.pump();
    expect(asks, <int>[3, 4]);
  });

  testWidgets('a reload to the same length on a window too tall to scroll '
      'fills again', (tester) async {
    final asks = <int>[];
    await tester.pumpWidget(_Paged(loaded: <int>[1, 2, 3], asks: asks));
    await tester.pump();
    expect(asks, <int>[3]);

    // Another listing (a filter changed, a refresh) that happens to load
    // as many rows: its own list, so its own fill.
    await tester.pumpWidget(_Paged(loaded: <int>[7, 8, 9], asks: asks));
    await tester.pump();
    expect(asks, <int>[3, 3]);
  });

  testWidgets('a short list with nothing behind it asks for nothing', (
    tester,
  ) async {
    final asks = <int>[];
    await tester.pumpWidget(_Paged(rows: 3, asks: asks, more: false));
    await tester.pump();

    expect(asks, isEmpty);
  });

  testWidgets('a long list asks only once a scroll nears its end', (
    tester,
  ) async {
    final asks = <int>[];
    // 200 rows of 50 in a 600 tall window: 9400 to scroll.
    await tester.pumpWidget(_Paged(rows: 200, asks: asks));
    await tester.pump();
    expect(asks, isEmpty);

    final scroll = tester.state<_PagedState>(find.byType(_Paged)).pagedScroll;
    scroll.jumpTo(8000);
    await tester.pump();
    expect(asks, isEmpty, reason: '1400 from the end');

    scroll.jumpTo(9000);
    await tester.pump();
    expect(asks, isNotEmpty, reason: 'within 400 of the end');
  });

  testWidgets('a screen asks as far ahead as it says', (tester) async {
    final asks = <int>[];
    await tester.pumpWidget(_Paged(rows: 200, asks: asks, ahead: 600));
    await tester.pump();

    tester.state<_PagedState>(find.byType(_Paged)).pagedScroll.jumpTo(8900);
    await tester.pump();
    expect(asks, isNotEmpty, reason: 'within 600 of the end');
  });

  testWidgets('nothing is asked once the screen is gone', (tester) async {
    final asks = <int>[];
    await tester.pumpWidget(_Paged(rows: 200, asks: asks));
    final scroll = tester.state<_PagedState>(find.byType(_Paged)).pagedScroll;
    await tester.pumpWidget(const SizedBox());

    // Disposed with the screen, so no scroll can reach the listener.
    expect(() => scroll.addListener(() {}), throwsFlutterError);
    expect(asks, isEmpty);
  });
}
