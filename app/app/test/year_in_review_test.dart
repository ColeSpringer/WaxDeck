import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/stats/year_in_review_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: const MaterialApp(home: YearInReviewScreen()),
);

YearInReview _recap(int year) => YearInReview(
  year: year,
  timezone: 'UTC',
  totalMs: 2 * 3600000,
  sessions: 10,
  distinctItems: 5,
  newInLibrary: 3,
  timeSavedMs: 60000,
  longestStreakDays: 4,
  byMonth: [
    for (var month = 1; month <= 12; month++)
      MonthListening(month: month, ms: month * 60000, sessions: month),
  ],
  topArtists: const [TopEntry(name: 'The Bree Trio', plays: 12, ms: 7200000)],
  topTracks: const [
    TopEntry(name: 'Prancing Pony Blues', plays: 9, ms: 3600000),
  ],
);

void main() {
  testWidgets('renders the personal recap with totals and top lists', (
    tester,
  ) async {
    final repo = FakeRepository()..yearInReview = _recap(DateTime.now().year);
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('yir-total')),
        matching: find.text('2h 0m'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('yir-streak')),
        matching: find.text('4 days'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('yir-month-chart')), findsOneWidget);
    expect(find.text('The Bree Trio'), findsOneWidget);
    expect(find.text('Prancing Pony Blues'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the chevrons step the year and refetch', (tester) async {
    final thisYear = DateTime.now().year;
    final repo = FakeRepository()..yearInReview = _recap(thisYear);
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(repo.yearInReviewCalls.last, thisYear);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.yirPrevYear));
    await tester.pumpAndSettle();

    expect(find.text('${thisYear - 1}'), findsOneWidget);
    expect(repo.yearInReviewCalls.last, thisYear - 1);
  });

  testWidgets('the server toggle shows the server-wide recap', (tester) async {
    final thisYear = DateTime.now().year;
    final repo = FakeRepository()
      ..yearInReview = _recap(thisYear)
      ..serverYearInReview = ServerYearInReview(
        year: thisYear,
        participants: 4,
        totalMs: 3600000,
        sessions: 100,
        topArtists: const [
          TopEntry(name: 'Weathertop Quartet', plays: 40, ms: 3600000),
        ],
      );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.yirServer));
    await tester.pumpAndSettle();

    expect(repo.serverYearInReviewCalls.last, thisYear);
    expect(
      find.descendant(
        of: find.byKey(const Key('yir-participants')),
        matching: find.text('4'),
      ),
      findsOneWidget,
    );
    expect(find.text('listeners counted in'), findsOneWidget);
    expect(find.text('Weathertop Quartet'), findsOneWidget);
  });

  testWidgets('an all-zero year says nothing played', (tester) async {
    // No canned recap: the fake answers an all-zero year.
    final repo = FakeRepository();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('yir-nothing-played')), findsOneWidget);
    expect(find.text('Nothing played this year'), findsOneWidget);
  });
}
