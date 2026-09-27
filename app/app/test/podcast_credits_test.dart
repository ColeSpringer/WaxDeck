import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/podcasts/credits.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'localized_host.dart';

void main() {
  testWidgets('an avatar takes the first letter of a name, not its '
      'punctuation', (tester) async {
    await tester.pumpWidget(
      localizedHost(
        Scaffold(
          body: PodcastCredits(
            persons: const <FeedPerson>[
              FeedPerson(name: '(Guest) Jane Doe'),
              FeedPerson(name: '"Weird Al" Yankovic'),
              FeedPerson(name: '_host'),
            ],
            onOpenLink: (_) {},
          ),
        ),
        theme: buildWaxTheme(),
      ),
    );

    String initialOf(int row) => tester
        .widget<Text>(
          find.descendant(
            of: find.byType(CircleAvatar).at(row),
            matching: find.byType(Text),
          ),
        )
        .data!;
    expect(
      <String>[initialOf(0), initialOf(1), initialOf(2)],
      <String>['G', 'W', 'H'],
    );
  });
}
