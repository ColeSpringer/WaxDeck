import 'dart:ui' show CheckedState, Tristate;

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

/// Where [node] is on screen, in logical pixels: its rect through every
/// transform above it but the window's own.
Rect semanticsRectOnScreen(SemanticsNode node) {
  var rect = node.rect;
  for (var at = node; at.parent != null; at = at.parent!) {
    final transform = at.transform;
    if (transform != null) rect = MatrixUtils.transformRect(transform, rect);
  }
  return rect;
}

/// The node a screen reader exploring by touch lands on at [position], as
/// Android's accessibility bridge picks it: the topmost node holding the
/// point, children before their parent, that takes the focus.
SemanticsNode? touchExploredAt(WidgetTester tester, Offset position) {
  SemanticsNode? landOn(SemanticsNode node, Offset point) {
    final transform = node.transform;
    final local = transform == null
        ? point
        : MatrixUtils.transformPoint(Matrix4.inverted(transform), point);
    if (!node.rect.contains(local)) return null;
    final found = _topmostFirst(node)
        .where((child) => !child.getSemanticsData().flagsCollection.isHidden)
        .map((child) => landOn(child, local))
        .firstWhere((hit) => hit != null, orElse: () => null);
    return found ?? (_takesFocus(node.getSemanticsData()) ? node : null);
  }

  final root = tester
      .binding
      .renderViews
      .first
      .owner!
      .semanticsOwner!
      .rootSemanticsNode!;
  return _topmostFirst(root)
      .map((child) => landOn(child, position))
      .firstWhere((hit) => hit != null, orElse: () => null);
}

/// [node]'s children in the order a touch asks them: the last painted
/// first.
List<SemanticsNode> _topmostFirst(SemanticsNode node) {
  final children = <SemanticsNode>[];
  node.visitChildren((child) {
    children.add(child);
    return true;
  });
  return children.reversed.toList();
}

/// Whether the bridge would put the accessibility focus on a node with
/// [data]: something to read or to do besides scrolling, or a state.
bool _takesFocus(SemanticsData data) {
  final flags = data.flagsCollection;
  if (flags.scopesRoute || flags.isAccessibilityFocusBlocked) return false;
  const scrolls = <SemanticsAction>{
    SemanticsAction.scrollLeft,
    SemanticsAction.scrollRight,
    SemanticsAction.scrollUp,
    SemanticsAction.scrollDown,
  };
  return SemanticsAction.values.any(
        (action) => !scrolls.contains(action) && data.hasAction(action),
      ) ||
      flags.isChecked != CheckedState.none ||
      flags.isSelected == Tristate.isTrue ||
      flags.isTextField ||
      flags.isFocused != Tristate.none ||
      flags.isEnabled != Tristate.none ||
      flags.isInMutuallyExclusiveGroup ||
      flags.isToggled != Tristate.none ||
      flags.isSlider ||
      data.label.isNotEmpty ||
      data.value.isNotEmpty ||
      data.hint.isNotEmpty;
}
