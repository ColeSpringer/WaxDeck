import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

class _Row {
  const _Row(this.id, this.name, this.path, this.count);

  final String id;
  final String name;
  final String path;
  final int count;
}

const _rows = <_Row>[
  _Row('lb-1', 'music', '/srv/media/music', 4210),
  _Row('lb-2', 'audiobooks', '/srv/media/books', 38),
];

List<WaxColumn<_Row>> _columns() => <WaxColumn<_Row>>[
  WaxColumn<_Row>(
    label: 'Name',
    priority: WaxColumnPriority.primary,
    text: (r) => r.name,
    cell: (context, r) => Text(r.name),
  ),
  WaxColumn<_Row>(
    label: 'Items',
    numeric: true,
    width: 80,
    text: (r) => '${r.count}',
    cell: (context, r) => Text('${r.count}'),
  ),
  WaxColumn<_Row>(
    label: 'Path',
    priority: WaxColumnPriority.detail,
    text: (r) => r.path,
    cell: (context, r) => Text(r.path),
  ),
];

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 1000,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWaxTheme(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  testWidgets('draws a header and every row where there is room', (
    tester,
  ) async {
    await _pump(
      tester,
      WaxTable<_Row>(columns: _columns(), rows: _rows, rowId: (r) => r.id),
    );

    // The header labels, once each, over both rows.
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Items'), findsOneWidget);
    expect(find.text('music'), findsOneWidget);
    expect(find.text('audiobooks'), findsOneWidget);
    // The detail column is a column here rather than a sheet.
    expect(find.text('/srv/media/music'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('becomes cards below sidebar width, detail columns dropped', (
    tester,
  ) async {
    await _pump(
      tester,
      WaxTable<_Row>(
        columns: _columns(),
        rows: _rows,
        rowId: (r) => r.id,
        rowDetailSemanticsId: (id) => 'library-detail-$id',
      ),
      width: 420,
    );

    // No header row: a phone gets cards, and the labels ride each card's
    // own fields instead.
    expect(find.text('Name'), findsNothing);
    expect(find.text('music'), findsOneWidget);
    // The secondary column keeps its label beside its value.
    expect(find.text('Items'), findsNWidgets(2));
    // The detail column is not on the card - it is behind the card's
    // own control, so a phone can still reach it.
    expect(find.text('/srv/media/music'), findsNothing);
    expect(find.bySemanticsIdentifier('library-detail-lb-1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a card opens the whole record, detail columns included', (
    tester,
  ) async {
    await _pump(
      tester,
      WaxTable<_Row>(
        columns: _columns(),
        rows: _rows,
        rowId: (r) => r.id,
        rowDetailSemanticsId: (id) => 'library-detail-$id',
      ),
      width: 420,
    );

    await tester.tap(
      find.bySemanticsIdentifier('library-detail-lb-1'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    // Every column with a text form, not only the detail one: somebody
    // who opened this wants the row.
    expect(find.text('/srv/media/music'), findsOneWidget);
    expect(find.text('Path'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    // The secondary column is on the card as well as in the sheet, and
    // that is the point: the sheet is the whole record, not the
    // leftovers.
    expect(find.text('4210'), findsNWidgets(2));
  });

  testWidgets('a row with a tap handler is a button carrying its handle', (
    tester,
  ) async {
    _Row? opened;
    await _pump(
      tester,
      WaxTable<_Row>(
        columns: _columns(),
        rows: _rows,
        rowId: (r) => r.id,
        rowSemanticsId: (id) => 'library-row-$id',
        onRowTap: (row) => opened = row,
      ),
    );

    final handle = find.bySemanticsIdentifier('library-row-lb-2');
    expect(handle, findsOneWidget);
    await tester.tap(handle, warnIfMissed: false);
    await tester.pump();
    expect(opened?.id, 'lb-2');
  });

  testWidgets('an empty table draws its empty state, not a bare header', (
    tester,
  ) async {
    await _pump(
      tester,
      WaxTable<_Row>(
        columns: _columns(),
        rows: const <_Row>[],
        rowId: (r) => r.id,
        empty: const EmptyState(
          glyph: WaxIcons.albums,
          title: 'No libraries yet',
          message: 'Add a root and WaxDeck scans it.',
        ),
      ),
    );

    expect(find.text('No libraries yet'), findsOneWidget);
    expect(find.text('Name'), findsNothing);
  });

  testWidgets('a stat tile that goes nowhere is not a button', (tester) async {
    await _pump(
      tester,
      const Row(
        children: <Widget>[
          Expanded(
            child: StatTile(
              label: 'Pending review',
              value: '12',
              caption: 'albums waiting',
              semanticsId: 'tile-review',
            ),
          ),
        ],
      ),
    );

    // A tile with nowhere to go names its value and does not announce as
    // a button: there is nothing to press.
    expect(
      tester.getSemantics(find.bySemanticsIdentifier('tile-review')),
      matchesSemantics(label: 'Pending review, 12'),
    );
  });

  testWidgets('typed confirmation stays disabled until the word matches', (
    tester,
  ) async {
    bool? answer;
    await _pump(
      tester,
      Builder(
        builder: (context) => WaxButton(
          label: 'Empty trash',
          onPressed: () async {
            answer = await showTypedConfirm(
              context,
              title: 'Empty the trash?',
              message: 'Every file in it is deleted for good.',
              confirmWord: 'EMPTY',
              confirmLabel: 'Empty trash',
              fieldSemanticsId: 'confirm-field',
              confirmSemanticsId: 'confirm-go',
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Empty trash'));
    await tester.pumpAndSettle();

    // Pressing confirm before typing does nothing: the dialog is still
    // up and no answer has come back.
    await tester.tap(
      find.bySemanticsIdentifier('confirm-go'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(answer, isNull);
    expect(find.text('Empty the trash?'), findsOneWidget);

    await tester.enterText(
      find.bySemanticsIdentifier('confirm-field'),
      'EMPTY',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier('confirm-go'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(answer, isTrue);
  });

  testWidgets('a near miss is not the word', (tester) async {
    bool? answer;
    await _pump(
      tester,
      Builder(
        builder: (context) => WaxButton(
          label: 'Empty trash',
          onPressed: () async {
            answer = await showTypedConfirm(
              context,
              title: 'Empty the trash?',
              message: 'Every file in it is deleted for good.',
              confirmWord: 'EMPTY',
              confirmLabel: 'Empty trash',
              fieldSemanticsId: 'confirm-field',
              confirmSemanticsId: 'confirm-go',
              cancelSemanticsId: 'confirm-cancel',
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Empty trash'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier('confirm-field'),
      'empty',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier('confirm-go'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(answer, isNull);

    await tester.tap(
      find.bySemanticsIdentifier('confirm-cancel'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(answer, isFalse);
  });
}
