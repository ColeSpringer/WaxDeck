import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// A right click on [finder], the pointer's door into a card's or a
/// row's menu, settled.
Future<void> rightClick(WidgetTester tester, Finder finder) async {
  await tester.tapAt(
    tester.getCenter(finder),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await tester.pumpAndSettle();
}

/// Rests a mouse on [card]'s artwork and presses the play affordance
/// that rises there, found by the name it carries.
Future<void> hoverPlay(
  WidgetTester tester,
  Finder card, {
  required String label,
}) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await gesture.moveTo(
    tester.getCenter(
      find.descendant(of: card, matching: find.byType(ArtworkImage)).first,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: card,
      matching: find.byWidgetPredicate(
        (widget) => widget is WaxIconButton && widget.label == label,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
