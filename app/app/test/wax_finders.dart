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
