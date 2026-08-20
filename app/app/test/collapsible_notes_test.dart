import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/podcasts/show_notes.dart';
import 'package:waxdeck/src/podcasts/show_screen.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'localized_host.dart';

Widget _host(String html, {double collapsedTo = 120}) => ProviderScope(
  child: localizedHost(
    Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: CollapsibleNotes(html: html, collapsedTo: collapsedTo),
        ),
      ),
    ),
  ),
);

/// Long enough to run past any budget these tests set.
const _long =
    '<p>The Prancing Pony sessions, part one. Barliman on the low end, '
    'Bree brass through the bridge, and a long tail of studio talk that '
    'nobody trimmed.</p><p>Recorded over three nights in a room with the '
    'windows open, which you can hear in the second half.</p><p>Notes, '
    'corrections and the setlist follow.</p>';

void main() {
  testWidgets('notes that fit get no control at all', (tester) async {
    await tester.pumpWidget(_host('<p>One line of notes.</p>'));
    await tester.pumpAndSettle();

    expect(find.text('One line of notes.', findRichText: true), findsOneWidget);
    // The control used to be unconditional, so short notes carried one
    // that unfolded nothing.
    expect(find.text('Show more'), findsNothing);
    expect(find.text('Show less'), findsNothing);
  });

  testWidgets('notes past the budget offer the rest and fold back', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_long, collapsedTo: 60));
    await tester.pumpAndSettle();

    expect(find.text('Show more'), findsOneWidget);
    final clamped = tester.getSize(find.byType(CollapsibleNotes)).height;

    await tester.tap(find.text('Show more'));
    await tester.pumpAndSettle();

    expect(find.text('Show less'), findsOneWidget);
    expect(
      tester.getSize(find.byType(CollapsibleNotes)).height,
      greaterThan(clamped),
    );

    await tester.tap(find.text('Show less'));
    await tester.pumpAndSettle();
    expect(find.text('Show more'), findsOneWidget);
  });

  testWidgets('the control lines up with the notes it opens', (tester) async {
    await tester.pumpWidget(_host(_long, collapsedTo: 60));
    await tester.pumpAndSettle();

    // The whole point of the inline kind: a pill's 20 px of padding used
    // to push this a fifth of an inch right of the paragraph above it.
    expect(
      tester.getTopLeft(find.text('Show more')).dx,
      moreOrLessEquals(
        tester.getTopLeft(find.byType(ShowNotesView)).dx,
        epsilon: 0.5,
      ),
    );
  });
}
