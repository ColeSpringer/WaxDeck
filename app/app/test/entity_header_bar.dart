import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// Asserts the entity header on screen builds its row as one
/// [WaxActionBar]: every pill is inside it, no raw button or chip sits in
/// the header beside it, and the bar holds only the pills its actions
/// build, so nothing handed in through `trailing` mixes in. The header's
/// own link line is an inline button and is not a pill.
void expectHeaderOnActionBar() {
  final header = find.byType(EntityHeader);
  expect(header, findsOneWidget);
  final bar = find.descendant(of: header, matching: find.byType(WaxActionBar));
  expect(bar, findsOneWidget, reason: 'the header row is a WaxActionBar');
  Finder pills(Finder within, Type type) => find.descendant(
    of: within,
    matching: find.byWidgetPredicate(
      (w) =>
          w.runtimeType == type &&
          !(w is WaxButton && w.kind == WaxButtonKind.inline),
    ),
  );
  for (final raw in <Type>[WaxButton, CodecChip, WaxPill]) {
    expect(
      pills(header, raw).evaluate().length,
      pills(bar, raw).evaluate().length,
      reason: '$raw outside the bar',
    );
  }
  for (final raw in <Type>[CodecChip, WaxPill]) {
    expect(
      find.descendant(of: bar, matching: find.byType(raw)),
      findsNothing,
      reason: '$raw in the bar',
    );
  }
  final actions = (bar.evaluate().single.widget as WaxActionBar).actions;
  expect(
    find.descendant(of: bar, matching: find.byType(WaxButton)),
    findsNWidgets(actions.length),
    reason: 'a WaxButton in the bar that no action builds',
  );
}

/// The control carrying semantics identifier [id] inside the header's
/// action bar.
Finder inActionBar(String id) => find.descendant(
  of: find.byType(WaxActionBar),
  matching: find.bySemanticsIdentifier(id),
);
