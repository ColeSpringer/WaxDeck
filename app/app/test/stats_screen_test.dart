import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/stats/stats_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: routedHost(const StatsScreen()),
);

FakeRepository _statsRepo() => FakeRepository()
  ..listeningStats = ListeningStats(
    range: '30d',
    bucket: 'day',
    timezone: 'UTC',
    totalMs: 2 * 3600000 + 34 * 60000,
    sessions: 42,
    timeSavedMs: 3600000 + 20 * 60000,
    buckets: [
      ListeningBucket(
        start: DateTime.utc(2026, 7, 1),
        ms: 3600000,
        sessions: 3,
      ),
      ListeningBucket(
        start: DateTime.utc(2026, 7, 2),
        ms: 1800000,
        sessions: 2,
      ),
    ],
  )
  ..heatmap = ListeningHeatmap(
    year: 2026,
    timezone: 'UTC',
    days: [
      HeatmapDay(date: DateTime.utc(2026, 1, 5), ms: 3600000, sessions: 2),
      HeatmapDay(date: DateTime.utc(2026, 7, 4), ms: 600000, sessions: 1),
    ],
    currentStreakDays: 3,
    longestStreakDays: 9,
  )
  ..topLists['artists'] = const TopList(
    kind: 'artists',
    range: '30d',
    entries: [
      TopEntry(name: 'The Bree Trio', plays: 12, ms: 7200000),
      TopEntry(name: 'Weathertop Quartet', plays: 5, ms: 1800000),
    ],
  )
  ..topLists['albums'] = const TopList(
    kind: 'albums',
    range: '30d',
    entries: [TopEntry(name: 'Songs of the Shire', plays: 8, ms: 3600000)],
  )
  ..topLists['stations'] = const TopList(
    kind: 'stations',
    range: '30d',
    entries: [
      TopEntry(
        name: 'Bree Radio',
        pid: 'rs-01JZX5N8QW3F4V9T2B7KDSTN001',
        artUrl: '/api/v1/radio/stations/rs-01JZX5N8QW3F4V9T2B7KDSTN001/logo',
        plays: 3,
        ms: 5400000,
      ),
    ],
  );

void main() {
  testWidgets('renders totals, chart, heatmap, and streaks', (tester) async {
    final repo = _statsRepo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('stats-total')),
        matching: find.text('2h 34m'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('stats-sessions')),
        matching: find.text('42'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('stats-saved')),
        matching: find.text('1h 20m'),
      ),
      findsOneWidget,
    );
    expect(find.text('time saved'), findsOneWidget);
    expect(find.byKey(const Key('stats-chart')), findsOneWidget);
    expect(find.byKey(const Key('stats-heatmap')), findsOneWidget);
    expect(
      find.text('Current streak: 3 days · Longest: 9 days'),
      findsOneWidget,
    );
    // The whole screen laid out without overflow exceptions.
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching the range refetches stats and the top list', (
    tester,
  ) async {
    final repo = _statsRepo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(repo.listeningStatsCalls.last, (range: '30d', bucket: 'day'));
    expect(repo.topListCalls.last.range, '30d');

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.statsRange('7d')));
    await tester.pumpAndSettle();

    expect(repo.listeningStatsCalls.last, (range: '7d', bucket: 'day'));
    expect(repo.topListCalls.last.range, '7d');
  });

  testWidgets('switching the bucket refetches with the new bucket', (
    tester,
  ) async {
    final repo = _statsRepo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    // The bucket is a picker rather than a segmented row: three values
    // on the trailing edge of a chart, not a filter over the page.
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.statsBucket));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Week').last);
    await tester.pumpAndSettle();

    expect(repo.listeningStatsCalls.last, (range: '30d', bucket: 'week'));
  });

  testWidgets('a range change keeps the old numbers until the new ones land', (
    tester,
  ) async {
    final repo = _statsRepo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    final gate = Completer<void>();
    repo.statsGate = gate;
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.statsRange('7d')));
    await tester.pump();

    // Riverpod hands the rebuild an AsyncLoading still carrying the last
    // value. Nothing may fall back to a skeleton over it - that is the
    // double reflow this screen was reported for.
    expect(repo.listeningStatsCalls.last, (range: '7d', bucket: 'day'));
    expect(find.byType(SkeletonShapes), findsNothing);
    expect(find.byKey(const Key('stats-chart')), findsOneWidget);
    expect(find.text('2h 34m'), findsOneWidget);

    repo.statsGate = null;
    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(SkeletonShapes), findsNothing);
    expect(find.byKey(const Key('stats-chart')), findsOneWidget);
  });

  testWidgets('a failed refresh displaces the numbers it could not renew', (
    tester,
  ) async {
    final repo = _statsRepo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();
    expect(find.text('2h 34m'), findsOneWidget);

    repo.statsError = WaxDeckApiException(
      statusCode: 503,
      code: 'unavailable',
      message: 'stats are down',
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.statsRange('7d')));
    await tester.pumpAndSettle();

    expect(find.text('2h 34m'), findsNothing);
    expect(find.byType(ErrorState), findsWidgets);
  });

  testWidgets('the split names every media type in the range', (tester) async {
    // The reported bug: a listener with podcast hours could not tell
    // from this screen whether any of them had been counted. The
    // figures are one number; the split is what names them.
    final repo = _statsRepo()
      ..listeningStats = ListeningStats(
        range: '30d',
        bucket: 'day',
        timezone: 'UTC',
        totalMs: 9000000,
        sessions: 12,
        timeSavedMs: 0,
        byMediaType: const [
          MediaTypeListening(
            mediaType: StatsMediaType.music,
            ms: 5400000,
            sessions: 8,
          ),
          MediaTypeListening(
            mediaType: StatsMediaType.podcast,
            ms: 3600000,
            sessions: 4,
          ),
        ],
      );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('stats-media-split')), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Podcasts'), findsOneWidget);
    expect(find.text('1h 30m'), findsOneWidget);
    expect(find.text('1h 0m'), findsOneWidget);

    // The bar is a canvas, so the whole split has to be one sentence.
    expect(
      tester.getSemantics(find.byKey(const Key('stats-media-split'))).label,
      'Listening by media type: Music 1h 30m, Podcasts 1h 0m.',
    );
  });

  testWidgets('one media type draws no split', (tester) async {
    // A bar that is all one colour says nothing the total did not.
    final repo = _statsRepo()
      ..listeningStats = ListeningStats(
        range: '30d',
        bucket: 'day',
        timezone: 'UTC',
        totalMs: 5400000,
        sessions: 8,
        timeSavedMs: 0,
        byMediaType: const [
          MediaTypeListening(
            mediaType: StatsMediaType.music,
            ms: 5400000,
            sessions: 8,
          ),
        ],
      );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('stats-media-split')), findsNothing);
  });

  testWidgets('top list tabs switch the kind', (tester) async {
    final repo = _statsRepo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.bySemanticsIdentifier(SemanticsIds.top('albums')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('The Bree Trio'), findsOneWidget);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.top('albums')));
    await tester.pumpAndSettle();

    expect(repo.topListCalls.last.kind, 'albums');
    expect(find.text('Songs of the Shire'), findsOneWidget);
    expect(find.text('The Bree Trio'), findsNothing);
  });

  testWidgets('top stations is a list of its own', (tester) async {
    // Radio time used to be invisible: nothing wrote a listen row for a
    // station, so no total counted it and no list could rank it.
    final repo = _statsRepo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.bySemanticsIdentifier(SemanticsIds.top('stations')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.top('stations')));
    await tester.pumpAndSettle();

    expect(repo.topListCalls.last.kind, 'stations');
    expect(find.text('Bree Radio'), findsOneWidget);
  });

  testWidgets('the listen log pages and filters by client', (tester) async {
    final repo = _statsRepo()
      ..listenLog = [
        ListenLogEntry(
          pid: 'tr-01JZX5N8QW3F4V9T2B7KDLOG001',
          title: 'Prancing Pony Blues',
          artist: 'The Bree Trio',
          mediaType: StatsMediaType.music,
          startedAt: DateTime.utc(2026, 7, 20, 12),
          msPlayed: 214000,
          finished: true,
          client: 'waxdeck-flutter-linux',
          source: 'live',
        ),
        ListenLogEntry(
          pid: 'tr-01JZX5N8QW3F4V9T2B7KDLOG002',
          title: 'Pipeweed Economics',
          artist: 'Barliman Butterbur',
          mediaType: StatsMediaType.podcast,
          startedAt: DateTime.utc(2026, 7, 19, 8),
          msPlayed: 1800000,
          finished: false,
          client: 'waxdeck-flutter-web',
          source: 'live',
        ),
      ];
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.bySemanticsIdentifier(SemanticsIds.openListenLog),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.openListenLog));
    await tester.pumpAndSettle();

    expect(find.text('Prancing Pony Blues'), findsOneWidget);
    expect(find.text('Pipeweed Economics'), findsOneWidget);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.listenLogClientFilter),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('waxdeck-flutter-web').last);
    await tester.pumpAndSettle();

    expect(repo.listenLogCalls.last.client, 'waxdeck-flutter-web');
    expect(find.text('Prancing Pony Blues'), findsNothing);
    expect(find.text('Pipeweed Economics'), findsOneWidget);
  });

  testWidgets('the log draws a station as radio', (tester) async {
    // A radio row carries no client - the server measured it rather
    // than a device reporting it - and its media type is one the item
    // enum has no value for, which is why the log maps through the
    // stats sibling.
    final repo = _statsRepo()
      ..listenLog = [
        ListenLogEntry(
          pid: 'rs-01JZX5N8QW3F4V9T2B7KDSTN001',
          title: 'Bree Radio',
          mediaType: StatsMediaType.radio,
          startedAt: DateTime.utc(2026, 7, 21, 9),
          msPlayed: 5400000,
          finished: false,
          client: '',
          source: 'radio',
        ),
      ];
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.bySemanticsIdentifier(SemanticsIds.openListenLog),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.openListenLog));
    await tester.pumpAndSettle();

    expect(find.text('Bree Radio'), findsOneWidget);

    // Its subtitle leads with the stamp rather than with a separator:
    // there is no artist and no client, and an empty client joined in
    // anyway would put a bare " · " in front of the date.
    expect(find.textContaining(RegExp(r'^\s*·')), findsNothing);

    // And it adds no nameless entry to the "reported by" filter: a row
    // the server measured has no client to filter on. Counted rather
    // than searched for by its text - what a stray option draws is an
    // empty string, and asserting `findsNothing` on that is asserting
    // nothing at all.
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.listenLogClientFilter),
    );
    await tester.pumpAndSettle();
    final options = find.byType(PopupMenuItem<String>);
    expect(options, findsOneWidget);
    expect(
      find.descendant(of: options, matching: find.text('All clients')),
      findsOneWidget,
    );
  });
}
