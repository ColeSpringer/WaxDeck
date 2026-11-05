import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
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

/// A tooltip with words, under [of]: a tappable tile holds one with
/// nothing to say whether or not its room cuts anything.
Finder _tip(Finder of) => find.descendant(
  of: of,
  matching: find.byWidgetPredicate((w) => w is WaxTooltip && w.message != null),
);

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

  testWidgets('keeps a numeric column off the column after it', (tester) async {
    // Right-aligned against a left-aligned neighbour, the header read
    // "ItemsPath" and the count touched the next cell.
    await _pump(
      tester,
      WaxTable<_Row>(columns: _columns(), rows: _rows, rowId: (r) => r.id),
    );

    final header = tester.getRect(find.text('Path'));
    final cell = tester.getRect(find.text('/srv/media/music'));
    expect(
      header.left - tester.getRect(find.text('Items')).right,
      greaterThanOrEqualTo(WaxSpace.s16),
    );
    expect(
      cell.left - tester.getRect(find.text('4210')).right,
      greaterThanOrEqualTo(WaxSpace.s16),
    );
    expect(cell.left, header.left, reason: 'the header stays over its rows');
  });

  testWidgets('a width change lays its rows out again without rebuilding', (
    tester,
  ) async {
    // A sidebar collapsing or a panel docking resizes it every frame.
    var built = 0;
    final width = ValueNotifier<double>(900);
    addTearDown(width.dispose);
    final table = WaxTable<_Row>(
      columns: <WaxColumn<_Row>>[
        WaxColumn<_Row>(
          label: 'Name',
          priority: WaxColumnPriority.primary,
          text: (r) => r.name,
          cell: (context, r) {
            built++;
            return Text(r.name);
          },
        ),
      ],
      rows: _rows,
      rowId: (r) => r.id,
    );
    await _pump(
      tester,
      ValueListenableBuilder<double>(
        valueListenable: width,
        builder: (context, value, _) => SizedBox(width: value, child: table),
      ),
    );
    final first = built;
    expect(first, greaterThan(0));

    width.value = 800;
    await tester.pump();
    expect(built, first);
  });

  testWidgets('becomes cards where its columns cannot fit beside a sidebar', (
    tester,
  ) async {
    // The Libraries table's shape, in the pane an 840 px window leaves:
    // its fixed columns and their gaps alone overran it.
    WaxColumn<_Row> fixed(String label, double width) => WaxColumn<_Row>(
      label: label,
      width: width,
      text: (r) => label,
      cell: (context, r) => Text(label),
    );
    await _pump(
      tester,
      SizedBox(
        width: 552,
        child: WaxTable<_Row>(
          columns: <WaxColumn<_Row>>[
            ..._columns(),
            fixed('Holds', 96),
            fixed('Matching', 148),
            fixed('Read-only', 108),
          ],
          rows: _rows,
          rowId: (r) => r.id,
          trailing: (context, r) => const SizedBox(width: 40),
        ),
      ),
      width: 840,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Name'), findsNothing, reason: 'cards, not a header');
    expect(find.text('music'), findsOneWidget);
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

    await tester.tap(find.bySemanticsIdentifier('library-detail-lb-1'));
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
    await tester.tap(handle);
    await tester.pump();
    expect(opened?.id, 'lb-2');
  });

  for (final (layout, width) in <(String, double)>[
    ('table', 1000),
    ('cards', 420),
  ]) {
    testWidgets('a row that lands above another leaves it its nodes '
        '($layout)', (tester) async {
      // Flutter resends a node only when something besides its identifier
      // changed, so a control that read alike on every row and passed to
      // the next one by position would keep the old row's handle.
      final rows = ValueNotifier<List<_Row>>(_rows);
      addTearDown(rows.dispose);
      await _pump(
        tester,
        ValueListenableBuilder<List<_Row>>(
          valueListenable: rows,
          builder: (context, value, _) => WaxTable<_Row>(
            columns: _columns(),
            rows: value,
            rowId: (r) => r.id,
            rowSemanticsId: (id) => 'library-row-$id',
            trailing: (context, r) => WaxIconButton(
              glyph: WaxIcons.close,
              label: 'Remove',
              semanticsId: 'remove-${r.id}',
              onPressed: () {},
            ),
          ),
        ),
        width: width,
      );
      int node(String id) =>
          tester.getSemantics(find.bySemanticsIdentifier(id)).id;
      final ids = <String>[
        for (final row in _rows) ...[
          'library-row-${row.id}',
          'remove-${row.id}',
        ],
      ];
      final before = <String, int>{for (final id in ids) id: node(id)};

      rows.value = <_Row>[
        const _Row('lb-0', 'podcasts', '/srv/media/podcasts', 12),
        ..._rows,
      ];
      await tester.pump();

      for (final id in ids) {
        expect(node(id), before[id], reason: '$id keeps its node');
      }
    });
  }

  for (final (layout, width) in <(String, double)>[
    ('table', 1000),
    ('cards', 420),
  ]) {
    testWidgets('a tappable row reads out its name, not its id ($layout)', (
      tester,
    ) async {
      // A tappable row is one node that excludes its cells, so its label
      // is all a screen reader has to say.
      await _pump(
        tester,
        WaxTable<_Row>(
          columns: _columns(),
          rows: _rows,
          rowId: (r) => r.id,
          rowSemanticsId: (id) => 'library-row-$id',
          rowDetailSemanticsId: (id) => 'library-detail-$id',
          onRowTap: (_) {},
        ),
        width: width,
      );

      expect(
        tester.getSemantics(find.bySemanticsIdentifier('library-row-lb-2')),
        isSemantics(label: 'audiobooks', isButton: true),
      );
      if (layout == 'cards') {
        expect(
          tester.getSemantics(
            find.bySemanticsIdentifier('library-detail-lb-2'),
          ),
          isSemantics(label: 'Details for audiobooks', isButton: true),
        );
      }
    });
  }

  for (final (layout, width) in <(String, double)>[
    ('table', 1000),
    ('cards', 420),
  ]) {
    testWidgets('a row label says what its primary fields alone do not '
        '($layout)', (tester) async {
      await _pump(
        tester,
        WaxTable<_Row>(
          columns: _columns(),
          rows: _rows,
          rowId: (r) => r.id,
          rowSemanticsId: (id) => 'library-row-$id',
          rowDetailSemanticsId: (id) => 'library-detail-$id',
          rowLabel: (r) => '${r.name}, ${r.count} items',
          onRowTap: (_) {},
        ),
        width: width,
      );

      expect(
        tester.getSemantics(find.bySemanticsIdentifier('library-row-lb-2')),
        isSemantics(label: 'audiobooks, 38 items', isButton: true),
      );
      if (layout == 'cards') {
        expect(
          tester.getSemantics(
            find.bySemanticsIdentifier('library-detail-lb-2'),
          ),
          isSemantics(
            label: 'Details for audiobooks, 38 items',
            isButton: true,
          ),
        );
      }
    });
  }

  testWidgets('rows sharing an id still draw', (tester) async {
    // A file with two diagnostics is two rows under one path.
    await _pump(
      tester,
      WaxTable<_Row>(
        columns: _columns(),
        rows: const <_Row>[
          _Row('lb-1', 'music', '/srv/media/music', 4210),
          _Row('lb-1', 'music again', '/srv/media/music', 4210),
        ],
        rowId: (r) => r.id,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('music again'), findsOneWidget);
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

    // A tile with nowhere to go names its value and its caption and does
    // not announce as a button: there is nothing to press.
    expect(
      tester.getSemantics(find.bySemanticsIdentifier('tile-review')),
      matchesSemantics(label: 'Pending review, 12, albums waiting'),
    );
  });

  testWidgets('a stat tile without a caption reads its label and value', (
    tester,
  ) async {
    await _pump(
      tester,
      const Row(
        children: <Widget>[
          Expanded(
            child: StatTile(
              label: 'Pending review',
              value: '12',
              semanticsId: 'tile-plain',
            ),
          ),
        ],
      ),
    );

    expect(
      tester.getSemantics(find.bySemanticsIdentifier('tile-plain')),
      matchesSemantics(label: 'Pending review, 12'),
    );
  });

  testWidgets('a stat grid keeps every tile one height and reads captions', (
    tester,
  ) async {
    const wrapping =
        'A caption long enough that it would wrap onto a second line at '
        'this width if it were allowed to';
    await _pump(
      tester,
      WaxStatGrid(
        tiles: <StatTile>[
          const StatTile(
            label: 'Captioned',
            value: '1',
            caption: 'albums waiting',
            semanticsId: 'tile-a',
          ),
          const StatTile(label: 'Bare', value: '2', semanticsId: 'tile-b'),
          const StatTile(
            label: 'Wrapping',
            value: '3',
            caption: wrapping,
            semanticsId: 'tile-c',
          ),
        ],
      ),
    );

    final heights = <double>[
      for (final tile in tester.widgetList<StatTile>(find.byType(StatTile)))
        tester.getSize(find.byWidget(tile)).height,
    ];
    expect(heights[1], heights[0]);
    expect(heights[2], heights[0]);
    expect(
      tester.getSize(find.byType(StatTile).first).width,
      WaxStatGrid.defaultTileWidth,
    );
    expect(
      tester.getSemantics(find.bySemanticsIdentifier('tile-a')),
      matchesSemantics(label: 'Captioned, 1, albums waiting'),
    );
    expect(
      tester.getSemantics(find.bySemanticsIdentifier('tile-b')),
      matchesSemantics(label: 'Bare, 2'),
    );
    expect(
      tester.getSemantics(find.bySemanticsIdentifier('tile-c')),
      matchesSemantics(label: 'Wrapping, 3, $wrapping'),
    );
  });

  testWidgets('a grid that never captions pays no empty line', (tester) async {
    await _pump(
      tester,
      const WaxStatGrid(
        tiles: <StatTile>[
          StatTile(label: 'One', value: '1'),
          StatTile(label: 'Two', value: '2'),
        ],
      ),
    );
    final bare = tester.getSize(find.byType(StatTile).first).height;

    await _pump(
      tester,
      const WaxStatGrid(
        tiles: <StatTile>[
          StatTile(label: 'One', value: '1', caption: 'x'),
          StatTile(label: 'Two', value: '2'),
        ],
      ),
    );
    expect(
      tester.getSize(find.byType(StatTile).first).height,
      greaterThan(bare),
    );
  });

  testWidgets('a long value stays on one line', (tester) async {
    await _pump(
      tester,
      const WaxStatGrid(
        tiles: <StatTile>[
          StatTile(label: 'Short', value: '1'),
          StatTile(
            label: 'Long',
            value: 'A value far too long to fit in a stat tile width',
          ),
        ],
      ),
    );
    expect(
      tester.getSize(find.byType(StatTile).first).height,
      tester.getSize(find.byType(StatTile).last).height,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stat figure reads as one thing', (tester) async {
    await _pump(
      tester,
      const StatFigure(key: Key('fig'), value: '2h 6m', caption: 'listened'),
    );
    expect(find.byKey(const Key('fig')), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const Key('fig'))),
      matchesSemantics(label: '2h 6m\nlistened'),
    );
  });

  testWidgets('a stat figure sets its value in tabular figures', (
    tester,
  ) async {
    await _pump(tester, const StatFigure(value: '10', caption: 'sessions'));
    expect(
      tester.widget<Text>(find.text('10')).style?.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
  });

  testWidgets('a tappable stat tile reads its caption and is a button', (
    tester,
  ) async {
    await _pump(
      tester,
      Row(
        children: <Widget>[
          Expanded(
            child: StatTile(
              label: 'Pending review',
              value: '12',
              caption: 'albums waiting',
              semanticsId: 'tile-go',
              onTap: () {},
            ),
          ),
        ],
      ),
    );

    expect(
      tester.getSemantics(find.bySemanticsIdentifier('tile-go')),
      matchesSemantics(
        label: 'Pending review, 12, albums waiting',
        isButton: true,
        isEnabled: true,
        isFocusable: true,
        hasEnabledState: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
  });

  for (final tappable in <bool>[false, true]) {
    final form = tappable ? 'tappable' : 'inert';
    testWidgets(
      '${tappable ? 'a' : 'an'} $form tile tips only a caption it cuts',
      (tester) async {
        const long =
            'Elementos pendientes de revision por el equipo de catalogo';
        await _pump(
          tester,
          WaxStatGrid(
            tiles: <StatTile>[
              StatTile(
                label: 'Fits',
                value: '1',
                caption: 'albums waiting',
                onTap: tappable ? () {} : null,
              ),
              StatTile(
                label: 'Cut',
                value: '2',
                caption: long,
                onTap: tappable ? () {} : null,
              ),
            ],
          ),
        );

        // The cut is read off the first frame's layout.
        await tester.pump();

        final fits = find.byWidgetPredicate(
          (w) => w is StatTile && w.label == 'Fits',
        );
        final cut = find.byWidgetPredicate(
          (w) => w is StatTile && w.label == 'Cut',
        );
        expect(_tip(fits), findsNothing);
        final tip = _tip(cut);
        expect(tip, findsOneWidget);
        expect(tester.widget<WaxTooltip>(tip).message, long);
      },
    );
  }

  group('a stat tile\'s caption tip follows the room it is given', () {
    const short = 'albums waiting';
    const long = 'Elementos pendientes de revision por el equipo de catalogo';

    // The same tree pumped again, so the tile keeps its state: what is
    // under test is the transition, not the first layout.
    Future<void> pumpTile(
      WidgetTester tester, {
      required double width,
      String caption = short,
      double scale = 1,
      bool tappable = false,
    }) async {
      await _pump(
        tester,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: StatTile(
                  label: 'L',
                  value: '1',
                  caption: caption,
                  onTap: tappable ? () {} : null,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final tip = _tip(find.byType(StatTile));
    // The tile's padding and border around its caption.
    const padding = 2 * WaxSpace.s16 + 2;

    for (final tappable in <bool>[false, true]) {
      final form = tappable ? 'tappable' : 'inert';
      testWidgets(
        '${tappable ? 'a' : 'an'} $form tile gains the tip as it narrows '
        'and loses it as it widens',
        (tester) async {
          await pumpTile(tester, width: 400, tappable: tappable);
          expect(tip, findsNothing);

          for (var round = 0; round < 3; round++) {
            await pumpTile(tester, width: 100, tappable: tappable);
            expect(tip, findsOneWidget, reason: 'narrow, round $round');
            expect(tester.widget<WaxTooltip>(tip).message, short);
            expect(tester.binding.hasScheduledFrame, isFalse);

            await pumpTile(tester, width: 400, tappable: tappable);
            expect(tip, findsNothing, reason: 'wide, round $round');
            expect(tester.binding.hasScheduledFrame, isFalse);
          }
        },
      );
    }

    testWidgets('a caption that changes to one that cuts gains the tip, and '
        'back to one that fits loses it', (tester) async {
      await pumpTile(tester, width: 220);
      expect(tip, findsNothing);

      await pumpTile(tester, width: 220, caption: long);
      expect(tip, findsOneWidget);
      expect(tester.widget<WaxTooltip>(tip).message, long);

      await pumpTile(tester, width: 220);
      expect(tip, findsNothing);
    });

    testWidgets('a larger text scale cuts a caption that fit, and the '
        'smaller one lets it go', (tester) async {
      await pumpTile(tester, width: 1000);
      // Wide enough for the caption at this scale, with a little to spare.
      final width = tester.getSize(find.text(short)).width + padding + 4;

      await pumpTile(tester, width: width);
      expect(tip, findsNothing);

      await pumpTile(tester, width: width, scale: 1.3);
      expect(tip, findsOneWidget);

      await pumpTile(tester, width: width);
      expect(tip, findsNothing);
    });

    testWidgets('a caption that exactly fits is not tipped, and one pixel '
        'less is', (tester) async {
      await pumpTile(tester, width: 1000);
      final natural = tester.getSize(find.text(short)).width;
      final tile = natural + padding;

      await pumpTile(tester, width: tile);
      expect(tip, findsNothing);

      await pumpTile(tester, width: tile - 1);
      expect(tip, findsOneWidget);
    });
  });

  group('a stat tile\'s value tip', () {
    Future<void> pumpTile(WidgetTester tester, String value) async {
      await _pump(
        tester,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: WaxStatGrid.defaultTileWidth,
                child: StatTile(
                  label: 'Streaming',
                  value: value,
                  semanticsId: 'tile',
                ),
              ),
            ),
          ),
        ),
      );
      // The cut is read off the first frame's layout.
      await tester.pump();
    }

    final tip = _tip(find.byType(StatTile));

    testWidgets('a value cut at 1.3x is tipped, and the tile still reads it '
        'whole', (tester) async {
      await pumpTile(tester, 'Not configured');
      expect(tip, findsOneWidget);
      expect(tester.widget<WaxTooltip>(tip).message, 'Not configured');
      expect(
        tester.getSemantics(find.bySemanticsIdentifier('tile')),
        matchesSemantics(label: 'Streaming, Not configured'),
      );
    });

    testWidgets('a value that fits at 1.3x is not tipped', (tester) async {
      await pumpTile(tester, '812');
      expect(tip, findsNothing);
      expect(
        tester.getSemantics(find.bySemanticsIdentifier('tile')),
        matchesSemantics(label: 'Streaming, 812'),
      );
    });
  });

  group('a stat tile cut short from the keyboard', () {
    const value = 'Waiting for the first library scan to finish';
    const caption =
        'Elementos pendientes de revision por el equipo de catalogo';

    Future<void> pumpTile(WidgetTester tester, {required bool tappable}) async {
      await _pump(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: WaxStatGrid.defaultTileWidth,
                child: StatTile(
                  label: 'Streaming',
                  value: value,
                  caption: caption,
                  onTap: tappable ? () {} : null,
                ),
              ),
              WaxButton(label: 'After', onPressed: () {}),
            ],
          ),
        ),
      );
      // The cut is read off the first frame's layout.
      await tester.pump();
    }

    bool focusOnTile() =>
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<StatTile>() !=
        null;

    testWidgets('a tappable tile shows what its room cut on keyboard focus', (
      tester,
    ) async {
      await pumpTile(tester, tappable: true);
      expect(find.textContaining(value), findsOneWidget, reason: 'the tile');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      expect(focusOnTile(), isTrue);
      final shown = find.textContaining(value);
      expect(shown, findsNWidgets(2), reason: 'the tile and its tip');
      expect(find.textContaining(caption), findsNWidgets(2));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(find.textContaining(value), findsOneWidget);
    });

    testWidgets('a tappable tile shows what its room cut on a long press', (
      tester,
    ) async {
      await pumpTile(tester, tappable: true);
      await tester.longPress(find.byType(StatTile));
      await tester.pump();
      expect(find.textContaining(value), findsNWidgets(2));
    });

    testWidgets('a caption that goes and comes back short leaves no tip '
        'behind', (tester) async {
      final current = ValueNotifier<String?>(caption);
      addTearDown(current.dispose);
      await _pump(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: WaxStatGrid.defaultTileWidth,
                child: ValueListenableBuilder<String?>(
                  valueListenable: current,
                  builder: (context, now, _) => StatTile(
                    label: 'Pending',
                    value: '12',
                    caption: now,
                    onTap: () {},
                  ),
                ),
              ),
              WaxButton(label: 'After', onPressed: () {}),
            ],
          ),
        ),
      );
      await tester.pump();
      current.value = null;
      await tester.pump();
      await tester.pump();
      current.value = 'ok';
      await tester.pump();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      expect(focusOnTile(), isTrue);
      expect(find.text('ok'), findsOneWidget, reason: 'it fits: no tip');
    });

    testWidgets('an untappable tile is no tab stop, and keeps hover', (
      tester,
    ) async {
      await pumpTile(tester, tappable: false);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusOnTile(), isFalse);
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<WaxButton>()
            ?.label,
        'After',
      );
      expect(find.textContaining(caption), findsOneWidget);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text(caption)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.textContaining(caption), findsNWidgets(2));
    });
  });

  testWidgets('a mixed grid keeps every tile one height at any text scale', (
    tester,
  ) async {
    for (final scale in <double>[0.85, 1.0, 1.3, 2.0]) {
      await _pump(
        tester,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: const WaxStatGrid(
              tiles: <StatTile>[
                StatTile(label: 'Glyph', value: '1', glyph: WaxIcons.albums),
                StatTile(label: 'Plain', value: '2'),
                StatTile(
                  label: 'Both',
                  value: '3',
                  caption: 'albums waiting',
                  glyph: WaxIcons.albums,
                ),
                StatTile(label: 'Captioned', value: '4', caption: 'x'),
              ],
            ),
          ),
        ),
      );
      final heights = <double>{
        for (final tile in tester.widgetList<StatTile>(find.byType(StatTile)))
          tester.getSize(find.byWidget(tile)).height,
      };
      expect(heights, hasLength(1), reason: 'text scale $scale');
    }
  });

  testWidgets('a tile that asks to reserve its caption keeps doing so in a '
      'grid that never captions', (tester) async {
    await _pump(
      tester,
      const WaxStatGrid(
        tiles: <StatTile>[
          StatTile(label: 'Asks', value: '1', reserveCaption: true),
          StatTile(label: 'Plain', value: '2'),
        ],
      ),
    );
    final asks = tester.getSize(find.byType(StatTile).first).height;
    final plain = tester.getSize(find.byType(StatTile).last).height;
    expect(asks, greaterThan(plain));
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
    await tester.tap(find.bySemanticsIdentifier('confirm-go'));
    await tester.pumpAndSettle();
    expect(answer, isNull);
    expect(find.text('Empty the trash?'), findsOneWidget);

    await tester.enterText(
      find.bySemanticsIdentifier('confirm-field'),
      'EMPTY',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('confirm-go'));
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
    await tester.tap(find.bySemanticsIdentifier('confirm-go'));
    await tester.pumpAndSettle();
    expect(answer, isNull);

    await tester.tap(find.bySemanticsIdentifier('confirm-cancel'));
    await tester.pumpAndSettle();
    expect(answer, isFalse);
  });

  testWidgets('a confirmation without a message asks only for the word', (
    tester,
  ) async {
    bool? answer;
    await _pump(
      tester,
      Builder(
        builder: (context) => WaxButton(
          label: 'Clear',
          onPressed: () async {
            answer = await showTypedConfirm(
              context,
              title: 'Clear the slot?',
              confirmWord: 'CLEAR',
              confirmLabel: 'Clear slot',
              fieldSemanticsId: 'confirm-field',
              confirmSemanticsId: 'confirm-go',
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Clear the slot?'), findsOneWidget);
    expect(find.byType(WaxProse), findsNothing);

    await tester.enterText(
      find.bySemanticsIdentifier('confirm-field'),
      'CLEAR',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('confirm-go'));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
  });
}
