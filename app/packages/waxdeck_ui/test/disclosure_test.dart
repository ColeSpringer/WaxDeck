import 'dart:ui' show Tristate;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool reducedMotion = false,
}) => tester.pumpWidget(
  MaterialApp(
    theme: buildWaxTheme(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 360, child: child),
        ),
      ),
    ),
  ),
);

WaxDisclosure _edition({
  bool initiallyExpanded = false,
  ValueChanged<bool>? onExpansionChanged,
}) => WaxDisclosure(
  title: 'Edition',
  semanticsId: 'edition',
  initiallyExpanded: initiallyExpanded,
  onExpansionChanged: onExpansionChanged,
  children: const <Widget>[
    MonoDetailRow(label: 'Publisher', value: 'Harbour Press'),
    MonoDetailRow(label: 'Narrator', value: 'Ora Lune'),
  ],
);

SemanticsData _header(WidgetTester tester) => tester
    .getSemantics(find.bySemanticsIdentifier('edition'))
    .getSemanticsData();

void main() {
  testWidgets('a press opens it and says so, and another closes it', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final changes = <bool>[];
    await _pump(tester, _edition(onExpansionChanged: changes.add));
    expect(find.text('Harbour Press'), findsNothing);
    var header = _header(tester);
    expect(header.label, 'Edition');
    expect(header.flagsCollection.isButton, isTrue);
    expect(header.flagsCollection.isExpanded, Tristate.isFalse);

    await tester.tap(find.text('Edition'));
    await tester.pumpAndSettle();
    expect(find.text('Harbour Press'), findsOneWidget);
    header = _header(tester);
    expect(header.flagsCollection.isExpanded, Tristate.isTrue);

    await tester.tap(find.text('Edition'));
    await tester.pumpAndSettle();
    expect(find.text('Harbour Press'), findsNothing);
    expect(_header(tester).flagsCollection.isExpanded, Tristate.isFalse);
    expect(changes, <bool>[true, false]);
    semantics.dispose();
  });

  testWidgets('Enter and Space toggle it from the keyboard', (tester) async {
    await _pump(tester, _edition());
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Harbour Press'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Harbour Press'), findsNothing);
  });

  testWidgets('a closed section is out of the tree: nothing to tab to or '
      'read', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      WaxDisclosure(
        title: 'Transcript',
        children: <Widget>[WaxButton(label: 'Copy', onPressed: () {})],
      ),
    );
    expect(find.byType(WaxButton), findsNothing);
    expect(find.bySemanticsLabel('Copy'), findsNothing);
    semantics.dispose();
  });

  testWidgets('it opens already open when asked to', (tester) async {
    await _pump(tester, _edition(initiallyExpanded: true));
    expect(find.text('Harbour Press'), findsOneWidget);
  });

  testWidgets('with motion it grows into its room', (tester) async {
    await _pump(tester, _edition(initiallyExpanded: true));
    final open = tester.getSize(find.byType(WaxDisclosure)).height;
    // A fresh one: the open one would keep its state through a pump.
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, _edition());
    final closed = tester.getSize(find.byType(WaxDisclosure)).height;

    await tester.tap(find.text('Edition'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final midway = tester.getSize(find.byType(WaxDisclosure)).height;
    expect(midway, greaterThan(closed));
    expect(midway, lessThan(open));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(WaxDisclosure)).height, open);
  });

  testWidgets('under reduced motion nothing moves: it fades in at its '
      'full size', (tester) async {
    await _pump(tester, _edition(initiallyExpanded: true), reducedMotion: true);
    final open = tester.getSize(find.byType(WaxDisclosure)).height;
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, _edition(), reducedMotion: true);
    expect(find.text('Harbour Press'), findsNothing);

    await tester.tap(find.text('Edition'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(tester.getSize(find.byType(WaxDisclosure)).height, open);
    final fade = tester.widget<Opacity>(
      find.ancestor(
        of: find.text('Harbour Press'),
        matching: find.byType(Opacity),
      ),
    );
    expect(fade.opacity, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });
}
