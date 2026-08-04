import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// The palette and the sheet are overlay surfaces: they draw their own
/// frame and are handed a window rather than filling one.
Future<void> pumpWax(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWaxTheme(variant: WaxThemeVariant.dark),
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

const _groups = <WaxPaletteGroup>[
  WaxPaletteGroup(
    title: 'Actions',
    entries: <WaxPaletteEntry>[
      WaxPaletteEntry(
        id: 'play',
        label: 'Play or pause',
        detail: 'Playback',
        shortcut: 'Space',
        semanticsId: 'entry-play',
      ),
      WaxPaletteEntry(
        id: 'queue',
        label: 'Show the queue',
        detail: 'Views',
        shortcut: 'Q',
        semanticsId: 'entry-queue',
      ),
    ],
  ),
  WaxPaletteGroup(
    title: 'Go to',
    entries: <WaxPaletteEntry>[
      WaxPaletteEntry(
        id: 'radio',
        label: 'Radio',
        detail: 'Go to',
        semanticsId: 'entry-radio',
      ),
    ],
  ),
];

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('enter runs the first row, and the arrows move which', (
    tester,
  ) async {
    final run = <String>[];
    await pumpWax(
      tester,
      WaxCommandPalette(
        groups: _groups,
        onQueryChanged: (_) {},
        onRun: run.add,
        semanticsId: 'palette',
        fieldSemanticsId: 'palette-field',
      ),
    );

    // Nothing touched: Enter runs the top row, which is what a palette
    // promises somebody who typed a name and stopped.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(run, <String>['play']);

    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    // Down twice from the first row lands on the third, which is in the
    // next group: the highlight walks the results, not the groups.
    expect(run, <String>['play', 'radio']);

    // And it wraps rather than stopping dead at the end.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(run, <String>['play', 'radio', 'play']);

    await _press(tester, LogicalKeyboardKey.arrowUp);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(run, <String>['play', 'radio', 'play', 'radio']);
  });

  testWidgets('a row can be clicked, and it says what key it answers to', (
    tester,
  ) async {
    final run = <String>[];
    await pumpWax(
      tester,
      WaxCommandPalette(
        groups: _groups,
        onQueryChanged: (_) {},
        onRun: run.add,
      ),
    );

    expect(find.text('Space'), findsOneWidget);
    expect(find.text('Q'), findsOneWidget);

    await tester.tap(find.text('Show the queue'));
    await tester.pumpAndSettle();
    expect(run, <String>['queue']);
  });

  testWidgets('typing is reported, and escape closes', (tester) async {
    final typed = <String>[];
    var closed = 0;
    await pumpWax(
      tester,
      WaxCommandPalette(
        groups: _groups,
        onQueryChanged: typed.add,
        onRun: (_) {},
        onClose: () => closed++,
        fieldSemanticsId: 'palette-field',
      ),
    );

    await tester.enterText(find.bySemanticsIdentifier('palette-field'), 'shuf');
    await tester.pumpAndSettle();
    expect(typed, <String>['shuf']);

    await _press(tester, LogicalKeyboardKey.escape);
    expect(closed, 1);
  });

  testWidgets('an empty answer says so rather than drawing nothing', (
    tester,
  ) async {
    await pumpWax(
      tester,
      WaxCommandPalette(
        groups: const <WaxPaletteGroup>[
          WaxPaletteGroup(title: 'Actions', entries: <WaxPaletteEntry>[]),
        ],
        onQueryChanged: (_) {},
        onRun: (_) {},
        emptyTitle: 'Nothing matches "zz"',
      ),
    );

    expect(find.text('Nothing matches "zz"'), findsOneWidget);
    // The heading over an empty group is dropped: a title with no rows
    // under it reads as a group that failed to load.
    expect(find.text('ACTIONS'), findsNothing);
  });

  testWidgets('the reference sheet pairs every label with its keys', (
    tester,
  ) async {
    var closed = 0;
    await pumpWax(
      tester,
      WaxShortcutSheet(
        groups: const <WaxShortcutGroup>[
          WaxShortcutGroup(
            title: 'Playback',
            rows: <WaxShortcutRow>[
              WaxShortcutRow(
                label: 'Play or pause',
                keys: 'Space',
                semanticsId: 'row-play',
              ),
              WaxShortcutRow(
                label: 'Next track',
                keys: 'Ctrl →',
                semanticsId: 'row-next',
              ),
            ],
          ),
          WaxShortcutGroup(title: 'Views', rows: <WaxShortcutRow>[]),
        ],
        onClose: () => closed++,
        semanticsId: 'sheet',
        closeSemanticsId: 'sheet-close',
      ),
    );

    expect(find.text('Keyboard shortcuts'), findsOneWidget);
    expect(find.text('Ctrl →'), findsOneWidget);
    // One node per line, carrying both halves: a reference read a row at
    // a time is the only way it is any use without sight of it.
    expect(
      tester.getSemantics(find.bySemanticsIdentifier('row-next')).label,
      'Next track, Ctrl →',
    );
    expect(find.text('VIEWS'), findsNothing);

    await tester.tap(find.bySemanticsIdentifier('sheet-close'));
    await tester.pumpAndSettle();
    expect(closed, 1);
  });
}
