import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/library/library_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: const MaterialApp(home: LibraryScreen()),
);

void main() {
  testWidgets('renders item cards from the repository', (tester) async {
    final repo = FakeRepository(
      items: [
        testItem('tr-01JZX5N8QW3F4V9T2B7KDEXAMPL1', title: 'First Track'),
        testItem(
          'pc-01JZX5N8QW3F4V9T2B7KDEXAMPL2',
          mediaType: MediaType.podcast,
          title: 'Second Show',
          artist: 'Some Host',
        ),
      ],
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('item-tr-01JZX5N8QW3F4V9T2B7KDEXAMPL1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('item-pc-01JZX5N8QW3F4V9T2B7KDEXAMPL2')),
      findsOneWidget,
    );
    expect(find.text('First Track'), findsOneWidget);
    expect(find.text('Second Show'), findsOneWidget);
    expect(find.text('Some Host'), findsOneWidget);
  });

  testWidgets('shows the continue-listening banner when the server has one', (
    tester,
  ) async {
    final resume = testItem(
      'bk-01JZX5N8QW3F4V9T2B7KDEXAMPL3',
      mediaType: MediaType.audiobook,
      title: 'There And Back Again',
      artist: null,
    );
    final repo = FakeRepository(items: [resume], recentlyPlayed: resume);
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('resume-banner')), findsOneWidget);
    expect(find.text('Continue listening'), findsOneWidget);
  });

  testWidgets('no banner without a recently played item', (tester) async {
    final repo = FakeRepository(items: [testItem('tr-1')]);
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('resume-banner')), findsNothing);
  });

  testWidgets('empty library shows the empty state', (tester) async {
    await tester.pumpWidget(_host(FakeRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Nothing here yet'), findsOneWidget);
  });
}
