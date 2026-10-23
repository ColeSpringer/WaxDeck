import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// Expects the caret [row] draws to be the one for a disclosure whose
/// content opens below it: pointing right while it is closed and down
/// while it is open, the pair the sidebar's groups draw. Up is the
/// player sheet's way of opening, which grows upward.
void expectDisclosure(WidgetTester tester, Finder row, {required bool open}) {
  final icons = find.descendant(of: row, matching: find.byType(WaxIcon));
  expect(icons, findsAtLeastNWidgets(1), reason: 'the row draws a caret');
  final drawn = tester.widget<WaxIcon>(icons.first).glyph;
  final want = open ? WaxIcons.collapse : WaxIcons.forward;
  expect(
    drawn.codePoint,
    want.codePoint,
    reason: open ? 'an open row points down' : 'a closed row points right',
  );
}
