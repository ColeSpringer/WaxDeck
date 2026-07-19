import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/podcasts/podcasts_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: const MaterialApp(home: PodcastsScreen()),
);

void main() {
  testWidgets('lists the caller subscriptions', (tester) async {
    final repo = FakeRepository()
      ..addSubscription(testShow('pc-A', title: 'Alpha Show'))
      ..addSubscription(
        testShow('pc-B', title: 'Bravo Show', author: 'Rosie Cotton'),
      );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('podcast-pc-A')), findsOneWidget);
    expect(find.byKey(const ValueKey('podcast-pc-B')), findsOneWidget);
    expect(find.text('Alpha Show'), findsOneWidget);
    expect(find.text('Rosie Cotton'), findsOneWidget);
  });

  testWidgets('empty state renders without rows', (tester) async {
    await tester.pumpWidget(_host(FakeRepository()));
    await tester.pumpAndSettle();
    expect(find.text('No subscriptions yet'), findsOneWidget);
  });

  testWidgets('the subscribe dialog flow adds a row', (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('podcast-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('podcast-url-field')),
      'https://pony.example/feed.xml',
    );
    await tester.tap(find.byKey(const Key('podcast-subscribe-confirm')));
    await tester.pumpAndSettle();

    expect(repo.subscribeCalls, hasLength(1));
    expect(repo.subscribeCalls.single.url, 'https://pony.example/feed.xml');
    expect(repo.subscribeCalls.single.sourceType, 'rss');
    // The dialog closed and the new subscription is on screen.
    expect(find.byKey(const Key('podcast-url-field')), findsNothing);
    expect(find.text('Subscribed Show 1'), findsOneWidget);
  });

  testWidgets('a failed subscribe surfaces the server message', (tester) async {
    final repo = FakeRepository()
      ..subscribeError = const WaxDeckApiException(
        code: 'feed-unreachable',
        message: 'feed unreachable: connection refused',
        statusCode: 502,
      );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('podcast-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('podcast-url-field')),
      'https://dead.example/feed.xml',
    );
    await tester.tap(find.byKey(const Key('podcast-subscribe-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('feed unreachable: connection refused'), findsOneWidget);
    // The dialog stays open for another attempt.
    expect(find.byKey(const Key('podcast-url-field')), findsOneWidget);
  });
}
