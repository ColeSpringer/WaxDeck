import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

void main() {
  testWidgets('a sheet with more rows than room scrolls to the last', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWaxTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showWaxOptionSheet(
                context,
                builder: (_) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (var i = 0; i < 12; i++)
                      WaxOptionRow(title: 'Row $i', onTap: () {}),
                  ],
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(find.text('Row 11'), 100);
    expect(find.text('Row 11').hitTestable(), findsOneWidget);
  });

  testWidgets('a sheet that scrolls its own rows keeps its header', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWaxTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showWaxOptionSheet(
                context,
                scrolls: false,
                builder: (_) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text('Header'),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: <Widget>[
                            for (var i = 0; i < 12; i++)
                              WaxOptionRow(title: 'Row $i', onTap: () {}),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final header = tester.getTopLeft(find.text('Header'));

    await tester.drag(find.text('Row 3'), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Header')), header);
  });

  testWidgets('a sheet answers with the row it was closed on', (tester) async {
    String? chosen;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWaxTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                chosen = await showWaxOptionSheet<String>(
                  context,
                  builder: (sheetContext) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (final name in const <String>['play', 'shuffle'])
                        WaxOptionRow(
                          title: name,
                          onTap: () => Navigator.of(sheetContext).pop(name),
                        ),
                    ],
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('shuffle'));
    await tester.pumpAndSettle();
    expect(chosen, 'shuffle');
  });
}
