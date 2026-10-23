import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// Expects the caret [control] draws to point where its action goes: up
/// for one that moves something to the top, down for one that moves it to
/// the bottom or brings more in below.
void expectPointing(WidgetTester tester, Finder control, {required bool up}) {
  final icons = find.descendant(of: control, matching: find.byType(WaxIcon));
  expect(icons, findsAtLeastNWidgets(1), reason: 'the control draws a caret');
  final drawn = tester.widget<WaxIcon>(icons.first).glyph;
  final want = up ? WaxIcons.caretUp : WaxIcons.caretDown;
  expect(
    drawn.codePoint,
    want.codePoint,
    reason: up ? 'its action goes up' : 'its action goes down',
  );
}
