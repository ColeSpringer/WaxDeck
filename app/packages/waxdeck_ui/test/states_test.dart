import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// A page-sized host, which is the shape these panes are drawn at: both
/// wrap a `Center` that fills whatever it is given.
Widget _host(Widget child) => MaterialApp(
  theme: buildWaxTheme(variant: WaxThemeVariant.dark),
  home: Scaffold(body: child),
);

/// The semantics node one identifier names.
SemanticsNode _node(WidgetTester tester, String id) {
  SemanticsNode? found;
  void walk(SemanticsNode node) {
    if (node.identifier == id) found = node;
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(tester.binding.rootElement!.renderObject!.debugSemantics!);
  expect(found, isNotNull, reason: 'no semantics node named $id');
  return found!;
}

void main() {
  // A container that merges its descendants takes their actions with
  // them, and both of these panes fill the viewport: on web a tappable
  // node draws flt-tappable with pointer-events over its whole rect, so
  // a click anywhere on an empty page fired the invitation's button.
  group('a full-page state pane', () {
    testWidgets('does not become one page-sized tap target', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        _host(
          EmptyState(
            title: 'Nothing here yet',
            message: 'Add something to see it.',
            actionLabel: 'Add',
            onAction: () => pressed++,
            semanticsId: 'empty',
            actionSemanticsId: 'empty-action',
          ),
        ),
      );
      final handle = tester.ensureSemantics();
      await tester.pump();

      final pane = _node(tester, 'empty');
      expect(
        pane.getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
        reason: 'the pane must not answer the button\'s tap',
      );
      // The button keeps a node of its own, so the action is still
      // reachable where it is drawn.
      expect(
        _node(
          tester,
          'empty-action',
        ).getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );

      // The boundary costs the container its merged text, so the label
      // has to be carried across with it or the pane announces nothing.
      expect(pane.label, contains('Nothing here yet'));
      expect(pane.label, contains('Add something to see it.'));
      // And the lines keep nodes of their own, so a reader can navigate
      // to them and a spec can find them by text.
      expect(find.text('Nothing here yet'), findsOne);
      expect(find.text('Add something to see it.'), findsOne);

      // A click on the far corner, nowhere near the button.
      await tester.tapAt(const Offset(8, 8));
      await tester.pump();
      expect(pressed, 0);

      handle.dispose();
    });

    testWidgets('announces the error rather than an empty live region', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          ErrorState(
            title: 'Could not load',
            message: 'The server did not answer.',
            onRetry: () {},
            semanticsId: 'error',
            retrySemanticsId: 'error-retry',
          ),
        ),
      );
      final handle = tester.ensureSemantics();
      await tester.pump();

      final pane = _node(tester, 'error');
      // The pair WaxBanner sets together: a live region that stopped
      // merging its descendants would announce an empty string on every
      // error, which no layout test would catch.
      expect(pane.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      expect(pane.label, contains('Could not load'));
      expect(pane.label, contains('The server did not answer.'));
      expect(find.text('The server did not answer.'), findsOne);
      expect(pane.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      expect(
        _node(
          tester,
          'error-retry',
        ).getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );

      handle.dispose();
    });
  });

  group('a filter chip row', () {
    testWidgets('keeps one node per chip, and none for the row', (
      tester,
    ) async {
      final picked = <String>[];
      await tester.pumpWidget(
        _host(
          Align(
            alignment: Alignment.topCenter,
            child: FilterChipRow(
              chips: const <WaxFilterChip>[
                WaxFilterChip(
                  name: 'all',
                  label: 'All',
                  semanticsId: 'chip-all',
                ),
                WaxFilterChip(
                  name: 'music',
                  label: 'Music',
                  semanticsId: 'chip-music',
                ),
              ],
              selected: 'all',
              onSelect: picked.add,
              semanticsId: 'chips',
            ),
          ),
        ),
      );
      final handle = tester.ensureSemantics();
      await tester.pump();

      // Merged, the row answered to whichever chip merged last: a press
      // on the row selected a chip nobody aimed at, and the search
      // screen's own e2e passed because of it.
      expect(
        _node(
          tester,
          'chips',
        ).getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
      );
      for (final id in <String>['chip-all', 'chip-music']) {
        expect(
          _node(tester, id).getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
          reason: '$id must stay individually reachable',
        );
      }

      handle.dispose();
    });
  });
}
