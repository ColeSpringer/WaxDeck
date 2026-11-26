import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/music/album_screen.dart';
import 'package:waxdeck/src/music/artist_screen.dart';
import 'package:waxdeck/src/music/listing_screen.dart';
import 'package:waxdeck/src/podcasts/episode_screen.dart';
import 'package:waxdeck/src/podcasts/show_screen.dart';
import 'package:waxdeck/src/books/book_screen.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/radio/radio_screen.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/stats/stats_charts.dart';
import 'package:waxdeck/src/stats/stats_screen.dart';
import 'package:waxdeck/src/sync/catalog_reads.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

const _music = StatsMediaType.music;

/// The stats screen over [repo], settled.
Future<void> _pump(WidgetTester tester, FakeRepository repo) async {
  await pumpApp(
    tester,
    const StatsScreen(),
    container: appContainer(repo: repo),
  );
}

/// The stats screen on a surface tall enough to build every section at
/// once, the medium chips and the top list's alike.
Future<void> _pumpTall(
  WidgetTester tester,
  FakeRepository repo, {
  ProviderContainer? container,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await pumpApp(
    tester,
    const StatsScreen(),
    container: container ?? appContainer(repo: repo),
  );
}

const _allKinds = <String>[
  'artists',
  'albums',
  'tracks',
  'genres',
  'shows',
  'episodes',
  'books',
  'authors',
  'stations',
];

/// The top-list chips on screen, in order.
List<String> _kindsShown() => <String>[
  for (final kind in _allKinds)
    if (find
        .bySemanticsIdentifier(SemanticsIds.top(kind))
        .evaluate()
        .isNotEmpty)
      kind,
];

/// The ranked row naming [name].
Finder _rowOf(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(MediaListRow));

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
      TopEntry(
        name: 'The Bree Trio',
        pid: 'ar-01JZXBREETRIO',
        artUrl: '/api/v1/items/ar-01JZXBREETRIO/art',
        plays: 12,
        ms: 7200000,
      ),
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
    await _pump(tester, repo);

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
    // The word each ranked row counts in.
    expect(
      find.descendant(
        of: find.byKey(const Key('stats-sessions')),
        matching: find.text('listens'),
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

  group('the chart spaces its bars in time', () {
    /// The bars the listening chart draws for [buckets] grouped by
    /// [bucket], and what it says of them.
    Future<(List<int>, String)> drawn(
      WidgetTester tester,
      String bucket,
      List<ListeningBucket> buckets,
    ) async {
      final repo = _statsRepo()
        ..listeningStats = ListeningStats(
          range: '365d',
          bucket: bucket,
          timezone: 'UTC',
          totalMs: 1,
          sessions: 1,
          timeSavedMs: 0,
          buckets: buckets,
        );
      await _pumpTall(tester, repo);
      final chart = tester.widget<ListeningBarChart>(
        find.byKey(const Key('stats-chart')),
      );
      return (chart.values, chart.summary);
    }

    testWidgets('days with no listening draw as empty bars', (tester) async {
      final (values, summary) = await drawn(tester, 'day', [
        ListeningBucket(start: DateTime.utc(2026, 7, 1), ms: 600, sessions: 1),
        ListeningBucket(start: DateTime.utc(2026, 7, 4), ms: 900, sessions: 1),
      ]);

      expect(values, <int>[600, 0, 0, 900]);
      expect(summary, contains('by day, 4 bars from 7/1 to 7/4'));
    });

    testWidgets('weeks step from Monday to Monday', (tester) async {
      final (values, summary) = await drawn(tester, 'week', [
        ListeningBucket(start: DateTime.utc(2026, 6, 29), ms: 600, sessions: 1),
        ListeningBucket(start: DateTime.utc(2026, 7, 20), ms: 900, sessions: 1),
      ]);

      expect(values, <int>[600, 0, 0, 900]);
      expect(summary, contains('by week, 4 bars from 6/29 to 7/20'));
    });

    testWidgets('months step by the calendar', (tester) async {
      final (values, summary) = await drawn(tester, 'month', [
        ListeningBucket(start: DateTime.utc(2025, 11, 1), ms: 600, sessions: 1),
        ListeningBucket(start: DateTime.utc(2026, 2, 1), ms: 900, sessions: 1),
      ]);

      expect(values, <int>[600, 0, 0, 900]);
      expect(summary, contains('by month, 4 bars from 11/1 to 2/1'));
    });
  });

  group('an empty chart', () {
    ListeningStats empty(String range) => ListeningStats(
      range: range,
      bucket: 'day',
      timezone: 'UTC',
      totalMs: 0,
      sessions: 0,
      timeSavedMs: 0,
    );

    // A listener of one medium opens on another: the medium is the cause,
    // not the range.
    const titles = <StatsMediaType, String>{
      StatsMediaType.music: 'No music in this range',
      StatsMediaType.podcast: 'No podcasts in this range',
      StatsMediaType.audiobook: 'No audiobooks in this range',
      StatsMediaType.radio: 'No radio in this range',
    };
    const allTime = <StatsMediaType, String>{
      StatsMediaType.music: 'No music has played yet.',
      StatsMediaType.podcast: 'No podcasts have played yet.',
      StatsMediaType.audiobook: 'No audiobooks have played yet.',
      StatsMediaType.radio: 'No radio has played yet.',
    };

    testWidgets('names the medium of the answer it shows, not the one being '
        'fetched', (tester) async {
      // A slow switch from an empty Music to Podcasts holds Music's empty
      // answer on screen; it is still Music that has nothing.
      final repo = _statsRepo()..listeningStats = empty('30d');
      await _pumpTall(tester, repo);
      expect(find.text(titles[StatsMediaType.music]!), findsOneWidget);

      final gate = Completer<void>();
      repo.statsGate = gate;
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.statsMedia('podcast')),
      );
      await tester.pump();

      expect(repo.listeningStatsCalls.last.mediaType, StatsMediaType.podcast);
      expect(find.text(titles[StatsMediaType.music]!), findsOneWidget);
      expect(find.text(titles[StatsMediaType.podcast]!), findsNothing);

      repo.statsGate = null;
      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text(titles[StatsMediaType.podcast]!), findsOneWidget);
      expect(find.text(titles[StatsMediaType.music]!), findsNothing);
    });

    for (final media in StatsMediaType.values) {
      testWidgets('of ${media.wireName} names it, and points to a longer '
          'range or another medium', (tester) async {
        final repo = _statsRepo()..listeningStats = empty('30d');
        await _pumpTall(tester, repo);
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.statsMedia(media.wireName)),
        );
        await tester.pumpAndSettle();

        expect(find.text(titles[media]!), findsOneWidget);
        expect(
          find.text('Pick a longer range or another medium.'),
          findsOneWidget,
        );
      });

      testWidgets('of ${media.wireName} over all time says none has played', (
        tester,
      ) async {
        final repo = _statsRepo()..listeningStats = empty('all');
        await _pumpTall(tester, repo);
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.statsMedia(media.wireName)),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.statsRange('all')),
        );
        await tester.pumpAndSettle();

        expect(find.text(titles[media]!), findsOneWidget);
        expect(find.text(allTime[media]!), findsOneWidget);
        expect(find.textContaining('longer range'), findsNothing);
      });
    }
  });

  testWidgets('switching the range refetches stats and the top list', (
    tester,
  ) async {
    final repo = _statsRepo();
    await _pump(tester, repo);

    expect(repo.listeningStatsCalls.last, (
      range: '30d',
      bucket: 'day',
      mediaType: _music,
    ));
    expect(repo.topListCalls.last.range, '30d');

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.statsRange('7d')));
    await tester.pumpAndSettle();

    expect(repo.listeningStatsCalls.last, (
      range: '7d',
      bucket: 'day',
      mediaType: _music,
    ));
    expect(repo.topListCalls.last.range, '7d');
  });

  testWidgets('switching the bucket refetches with the new bucket', (
    tester,
  ) async {
    final repo = _statsRepo();
    await _pump(tester, repo);

    // The bucket is a picker rather than a segmented row: three values
    // on the trailing edge of a chart, not a filter over the page.
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.statsBucket));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Week').last);
    await tester.pumpAndSettle();

    expect(repo.listeningStatsCalls.last, (
      range: '30d',
      bucket: 'week',
      mediaType: _music,
    ));
  });

  testWidgets('a range change keeps the old numbers until the new ones land', (
    tester,
  ) async {
    final repo = _statsRepo();
    await _pump(tester, repo);

    final gate = Completer<void>();
    repo.statsGate = gate;
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.statsRange('7d')));
    await tester.pump();

    // Riverpod hands the rebuild an AsyncLoading still carrying the last
    // value. Nothing may fall back to a skeleton over it - that is the
    // double reflow this screen was reported for.
    expect(repo.listeningStatsCalls.last, (
      range: '7d',
      bucket: 'day',
      mediaType: _music,
    ));
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
    await _pump(tester, repo);
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

  testWidgets('the page opens on music and the medium scopes every read', (
    tester,
  ) async {
    final repo = _statsRepo();
    await _pumpTall(tester, repo);

    expect(repo.listeningStatsCalls.single.mediaType, _music);
    expect(repo.heatmapCalls.single.mediaType, _music);
    expect(repo.topListCalls.single.kind, 'artists');

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.statsMedia('podcast')),
    );
    await tester.pumpAndSettle();

    // One read of each, each for the new medium: the top list reads
    // with the medium's own first kind, never once more with the old.
    expect(repo.listeningStatsCalls, hasLength(2));
    expect(repo.listeningStatsCalls.last.mediaType, StatsMediaType.podcast);
    expect(repo.heatmapCalls, hasLength(2));
    expect(repo.heatmapCalls.last.mediaType, StatsMediaType.podcast);
    expect(
      <String>[for (final c in repo.topListCalls) c.kind],
      <String>['artists', 'shows'],
    );
  });

  testWidgets('the top chips follow the medium', (tester) async {
    final repo = _statsRepo();
    await _pumpTall(tester, repo);

    expect(_kindsShown(), <String>['artists', 'albums', 'tracks', 'genres']);

    for (final (media, kinds) in <(StatsMediaType, List<String>)>[
      (StatsMediaType.podcast, <String>['shows', 'episodes']),
      (StatsMediaType.audiobook, <String>['books', 'authors']),
      (StatsMediaType.radio, <String>['stations']),
    ]) {
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.statsMedia(media.wireName)),
      );
      await tester.pumpAndSettle();
      expect(_kindsShown(), kinds, reason: media.wireName);
    }
  });

  testWidgets('a medium change starts its top list at its first kind', (
    tester,
  ) async {
    final repo = _statsRepo();
    await _pumpTall(tester, repo);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.top('albums')));
    await tester.pumpAndSettle();
    expect(repo.topListCalls.last.kind, 'albums');

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.statsMedia('audiobook')),
    );
    await tester.pumpAndSettle();
    expect(repo.topListCalls.last.kind, 'books');

    // Back on music the chip is the first again, not the one left.
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.statsMedia('music')),
    );
    await tester.pumpAndSettle();
    expect(
      <String>[for (final c in repo.topListCalls) c.kind],
      <String>['artists', 'albums', 'books', 'artists'],
    );
  });

  testWidgets('the page draws no split bar', (tester) async {
    // The medium is the page's own scope now; the split stays with the
    // recap, which is cross-medium by design.
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
    await _pumpTall(tester, repo);

    expect(find.byType(MediaSplitBar), findsNothing);
  });

  testWidgets('a top row draws its rank beside its picture', (tester) async {
    final repo = _statsRepo();
    await _pumpTall(tester, repo);

    final row = tester.widget<MediaListRow>(_rowOf('The Bree Trio'));
    expect(row.rank, 1);
    expect(row.leadingIndex, isNull);
    expect(
      find.descendant(
        of: _rowOf('The Bree Trio'),
        matching: find.byType(ArtworkImage),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsIdentifier(SemanticsIds.topEntry(0)))
          .label,
      startsWith('1, The Bree Trio'),
    );
    expect(find.text('12 listens'), findsOneWidget);
  });

  group('a top row opens what it names', () {
    testWidgets('an artist opens the artist page', (tester) async {
      final repo = _statsRepo();
      await _pumpTall(tester, repo);

      await tester.tap(find.text('The Bree Trio'));
      await tester.pumpAndSettle();

      expect(find.byType(ArtistScreen), findsOneWidget);
      expect(repo.facetDrills, contains(('artist', '01JZXBREETRIO')));
    });

    testWidgets('an album opens the album page', (tester) async {
      final repo = _statsRepo()
        ..topLists['albums'] = const TopList(
          kind: 'albums',
          range: '30d',
          entries: [
            TopEntry(
              name: 'Songs of the Shire',
              pid: 'al-01JZXSHIRE',
              plays: 8,
              ms: 3600000,
            ),
          ],
        );
      await _pumpTall(tester, repo);
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.top('albums')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Songs of the Shire'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<AlbumScreen>(find.byType(AlbumScreen)).pid,
        'al-01JZXSHIRE',
      );
    });

    testWidgets('an episode opens its page', (tester) async {
      final repo = _statsRepo()
        ..topLists['episodes'] = const TopList(
          kind: 'episodes',
          range: '30d',
          entries: [
            TopEntry(
              name: 'The Price of Leaf',
              pid: 'ep-01JZXLEAF',
              plays: 2,
              ms: 1800000,
            ),
          ],
        );
      await _pumpTall(tester, repo);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.statsMedia('podcast')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.top('episodes')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('The Price of Leaf'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<EpisodeScreen>(find.byType(EpisodeScreen)).pid,
        'ep-01JZXLEAF',
      );
    });

    testWidgets('a book opens its page', (tester) async {
      final repo = _statsRepo()
        ..topLists['books'] = const TopList(
          kind: 'books',
          range: '30d',
          entries: [
            TopEntry(
              name: 'The Long Dark',
              pid: 'bk-01JZXLONGDARK',
              plays: 4,
              ms: 7200000,
            ),
          ],
        );
      await _pumpTall(tester, repo);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.statsMedia('audiobook')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('The Long Dark'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<BookScreen>(find.byType(BookScreen)).pid,
        'bk-01JZXLONGDARK',
      );
    });

    testWidgets('a show opens its page', (tester) async {
      final repo = _statsRepo()
        ..topLists['shows'] = const TopList(
          kind: 'shows',
          range: '30d',
          entries: [
            TopEntry(
              name: 'Pipeweed Economics',
              pid: 'pc-01JZXPIPEWEED',
              plays: 6,
              ms: 3600000,
            ),
          ],
        );
      await _pumpTall(tester, repo);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.statsMedia('podcast')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pipeweed Economics'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<ShowScreen>(find.byType(ShowScreen)).pid,
        'pc-01JZXPIPEWEED',
      );
    });

    testWidgets('a genre opens its listing, found by its name', (tester) async {
      final repo = _statsRepo()
        ..topLists['genres'] = const TopList(
          kind: 'genres',
          range: '30d',
          entries: [TopEntry(name: 'folk', plays: 6, ms: 3600000)],
        )
        ..facets['genre'] = const <FacetBucket>[
          FacetBucket(key: 'Folk', label: 'Folk', count: 3),
        ];
      await _pumpTall(tester, repo);
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.top('genres')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('folk'));
      await tester.pumpAndSettle();

      expect(repo.facetStartsAt, contains('folk'));
      expect(find.byType(MusicListingScreen), findsOneWidget);
    });

    testWidgets('a track plays alone', (tester) async {
      final repo = _statsRepo()
        ..topLists['tracks'] = const TopList(
          kind: 'tracks',
          range: '30d',
          entries: [
            TopEntry(
              name: 'Prancing Pony Blues',
              pid: 'tr-01JZXPONY',
              plays: 9,
              ms: 3600000,
            ),
          ],
        );
      repo.libraryItems.add(testItem('tr-01JZXPONY'));
      final container = appContainer(repo: repo);
      await _pumpTall(tester, repo, container: container);
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.top('tracks')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Prancing Pony Blues'));
      await tester.pumpAndSettle();

      final queue = container.read(queueControllerProvider);
      expect(
        <String>[for (final e in queue.entries) e.pid],
        <String>['tr-01JZXPONY'],
      );
      expect(queue.source.kind, QueueSourceKind.single);
      expect(find.byType(StatsScreen), findsOneWidget);
    });

    testWidgets('a station goes to radio', (tester) async {
      final repo = _statsRepo();
      await _pumpTall(tester, repo);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.statsMedia('radio')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bree Radio'));
      await tester.pumpAndSettle();

      expect(find.byType(RadioScreen), findsOneWidget);
    });

    testWidgets('a row with nothing to open is no button', (tester) async {
      // A name group carries no pid, and an entry whose item has left
      // has no name: neither has a page to open.
      final repo = _statsRepo()
        ..topLists['tracks'] = const TopList(
          kind: 'tracks',
          range: '30d',
          entries: [TopEntry(name: '', pid: 'tr-01JZXGONE', plays: 2, ms: 1)],
        );
      final container = appContainer(repo: repo);
      await _pumpTall(tester, repo, container: container);

      expect(
        tester.getSemantics(
          find.bySemanticsIdentifier(SemanticsIds.topEntry(0)),
        ),
        isSemantics(isButton: true),
      );
      // Weathertop Quartet is a name group: no pid.
      expect(
        tester.getSemantics(
          find.bySemanticsIdentifier(SemanticsIds.topEntry(1)),
        ),
        isNot(isSemantics(isButton: true)),
      );
      await tester.tap(find.text('Weathertop Quartet'));
      await tester.pumpAndSettle();
      expect(find.byType(ArtistScreen), findsNothing);

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.top('tracks')));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(
          find.bySemanticsIdentifier(SemanticsIds.topEntry(0)),
        ),
        isNot(isSemantics(isButton: true)),
      );
      await tester.tap(find.text('Removed item'));
      await tester.pumpAndSettle();
      expect(container.read(queueControllerProvider).entries, isEmpty);
    });
  });

  testWidgets('top list tabs switch the kind', (tester) async {
    final repo = _statsRepo();
    await _pump(tester, repo);

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
    await _pumpTall(tester, repo);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.statsMedia('radio')),
    );
    await tester.pumpAndSettle();

    expect(repo.topListCalls.last.kind, 'stations');
    expect(find.text('Bree Radio'), findsOneWidget);
  });

  testWidgets('the listen log pages and filters by client', (tester) async {
    final repo = _statsRepo()
      ..listenLog = [
        ListenLogEntry(
          sessionId: 'log-1',
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
          sessionId: 'log-2',
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
    await _pump(tester, repo);

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

  testWidgets('two listens of one item from one start and one client are '
      'two rows', (tester) async {
    // An untimed scrobble naming a song twice records two sessions alike
    // in all but their ids.
    final repo = _statsRepo()
      ..listenLog = [
        for (final id in ['twice-a', 'twice-b'])
          ListenLogEntry(
            sessionId: id,
            pid: 'tr-01JZX5N8QW3F4V9T2B7KDLOG001',
            title: 'Prancing Pony Blues',
            artist: 'The Bree Trio',
            mediaType: StatsMediaType.music,
            startedAt: DateTime.utc(2026, 7, 20, 12),
            msPlayed: 214000,
            finished: true,
            client: 'subsonic',
            source: 'live',
          ),
      ];
    final container = appContainer(repo: repo);
    await pumpApp(tester, const StatsScreen(), container: container);

    await tester.scrollUntilVisible(
      find.bySemanticsIdentifier(SemanticsIds.openListenLog),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.openListenLog));
    await tester.pumpAndSettle();
    expect(find.text('Prancing Pony Blues'), findsNWidgets(2));

    // Read again where it stands, as a catalog write's sweep does.
    container.read(catalogQuietFanOutProvider).sweep();
    await tester.pumpAndSettle();

    expect(find.text('Prancing Pony Blues'), findsNWidgets(2));
  });

  testWidgets('the log draws a station as radio', (tester) async {
    // A radio row carries no client - the server measured it rather
    // than a device reporting it - and its media type is one the item
    // enum has no value for, which is why the log maps through the
    // stats sibling.
    final repo = _statsRepo()
      ..listenLog = [
        ListenLogEntry(
          sessionId: 'log-3',
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
    await _pump(tester, repo);

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
