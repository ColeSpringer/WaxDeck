import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/main.dart';

void main() {
  testWidgets('shell renders brand and probes health', (tester) async {
    await tester.pumpWidget(const WaxDeckApp());

    expect(find.text('WaxDeck'), findsOneWidget);
    expect(find.text('Music, podcasts, and audiobooks'), findsOneWidget);

    // No server in widget tests: the health probe must fail gracefully into
    // the unreachable state, never throw into the framework.
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('Server unreachable'), findsOneWidget);
  });
}
