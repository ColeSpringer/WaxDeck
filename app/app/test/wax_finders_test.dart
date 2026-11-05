import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'localized_host.dart';
import 'wax_finders.dart';

/// The finders other tests lean on answer from what they claim to read.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) =>
      tester.pumpWidget(localizedHost(Scaffold(body: Center(child: child))));

  const tip = WaxInfoTip(message: 'Held, not printed');

  group('hasOwnSemanticsNode', () {
    testWidgets('a tip on its own is its own node', (tester) async {
      await pump(tester, tip);
      expect(hasOwnSemanticsNode(tester, infoTipHolding(tip.message)), isTrue);
    });

    testWidgets('a tip a merging ancestor takes is not', (tester) async {
      await pump(
        tester,
        const MergeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[Text('A row'), tip],
          ),
        ),
      );
      expect(hasOwnSemanticsNode(tester, infoTipHolding(tip.message)), isFalse);
    });

    testWidgets('a tip an excluding ancestor hides is not', (tester) async {
      await pump(
        tester,
        Semantics(label: 'A row', excludeSemantics: true, child: tip),
      );
      expect(hasOwnSemanticsNode(tester, infoTipHolding(tip.message)), isFalse);
    });

    testWidgets('a wrapper that excludes nothing leaves it its own', (
      tester,
    ) async {
      // The tree is what is read, not the widget's type.
      await pump(tester, const ExcludeSemantics(excluding: false, child: tip));
      expect(hasOwnSemanticsNode(tester, infoTipHolding(tip.message)), isTrue);
    });
  });

  testWidgets('a tip is found by its whole message or by a part', (
    tester,
  ) async {
    await pump(tester, tip);
    expect(infoTipHolding('Held, not printed'), findsOneWidget);
    expect(infoTipHolding('Held'), findsNothing);
    expect(infoTipContaining('not printed'), findsOneWidget);
  });

  testWidgets('an empty state is found by its title', (tester) async {
    await pump(tester, const EmptyState(title: 'Nothing here'));
    expect(emptyStateTitled('Nothing here'), findsOneWidget);
    expect(
      tester.widget<EmptyState>(emptyStateTitled('Nothing here')).message,
      isNull,
    );
  });
}
