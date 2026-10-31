import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';
import 'package:waxdeck_ui_catalog/pages/components_page.dart';
import 'package:waxdeck_ui_catalog/sample_library.dart';

/// The page every component is reviewed on, drawn whole at a phone's
/// width and a desktop's, at the default text size and at 2.0: a demo
/// that overflows or throws is a component nobody can judge here.
void main() {
  late SampleArt art;

  setUpAll(() async {
    art = await SampleArt.generate(SampleArt.seeds, size: 64);
  });

  for (final (device, width) in const <(String, double)>[
    ('phone', 390),
    ('desktop', 1400),
  ]) {
    for (final scale in const <double>[1, 2]) {
      testWidgets('the components page draws whole on a $device at ${scale}x', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildWaxTheme(),
            localizationsDelegates: waxLocalizationsDelegates,
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: Scaffold(body: ComponentsPage(art: art)),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // Built lazily, so walked a screen at a time to its end: every
        // demo is laid out on the way, and any overflow or exception it
        // raises fails the test.
        final page = tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(ComponentsPage),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position;
        var steps = 0;
        while (page.pixels < page.maxScrollExtent) {
          page.jumpTo(math.min(page.pixels + 800, page.maxScrollExtent));
          await tester.pump(const Duration(milliseconds: 100));
          expect(++steps, lessThan(400), reason: 'the page ends');
        }
        expect(steps, greaterThan(0), reason: 'the page scrolled');

        // Torn down inside the test, so no ticker or timer a demo started
        // outlives it.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
      });
    }
  }
}
