import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// The Wax control of type [T] that owns the semantics identifier [id].
///
/// The one way a test finds a control by its handle: a predicate on the
/// widget's `semanticsId` finds the same thing, and two idioms for one
/// question is how a suite drifts.
Finder waxControl<T extends Widget>(String id) =>
    find.ancestor(of: find.bySemanticsIdentifier(id), matching: find.byType(T));

/// Gives [control], a Wax control, keyboard focus and presses Enter on it,
/// answering the focus node it was pressed with.
Future<FocusNode> pressWithKeyboard(WidgetTester tester, Finder control) async {
  final ring = find.descendant(
    of: control,
    matching: find.byType(WaxFocusRing),
  );
  final node = Focus.of(tester.element(ring.first));
  node.requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
  return node;
}

/// Presses the Load more [button] from the keyboard while its page is
/// held, and checks what a press leaves: the same button, busy and still
/// focused, over the one-row ghost of the page.
Future<void> expectLoadMoreHolds(WidgetTester tester, Finder button) async {
  final pressed = await pressWithKeyboard(tester, button);
  await tester.pump(const Duration(milliseconds: 400));
  expect(tester.widget<WaxButton>(button).busy, isTrue);
  expect(pressed.hasFocus, isTrue);
  expect(find.byType(SkeletonShapes), findsOneWidget);
  expect(
    tester.getTopLeft(find.byType(SkeletonShapes)).dy,
    greaterThanOrEqualTo(tester.getBottomLeft(button).dy),
  );
}

/// The info tip that holds [message].
Finder infoTipHolding(String message) =>
    _infoTip((held) => held == message, 'holding "$message"');

/// The info tip whose message contains [part], for a test about one
/// clause of it.
Finder infoTipContaining(String part) =>
    _infoTip((held) => held.contains(part), 'containing "$part"');

Finder _infoTip(bool Function(String message) test, String description) =>
    find.byWidgetPredicate(
      (widget) => widget is WaxInfoTip && test(widget.message),
      description: 'WaxInfoTip $description',
    );

/// The empty state titled [title].
Finder emptyStateTitled(String title) => find.byWidgetPredicate(
  (widget) => widget is EmptyState && widget.title == title,
  description: 'EmptyState titled "$title"',
);

/// Whether [tip], a WaxInfoTip, is a node of its own in the semantics
/// tree: the node its glyph lands in is named by the tip alone and takes
/// the tap. Under an ancestor that merges or excludes semantics the glyph
/// lands in that ancestor's node instead, and on web a tap goes to that
/// node, so the tip never opens.
bool hasOwnSemanticsNode(WidgetTester tester, Finder tip) {
  final widget = tester.widget<WaxInfoTip>(tip);
  final node = tester.getSemantics(
    find.descendant(of: tip, matching: find.byType(Icon)),
  );
  return node.label == widget.message &&
      node.getSemanticsData().hasAction(SemanticsAction.tap);
}
