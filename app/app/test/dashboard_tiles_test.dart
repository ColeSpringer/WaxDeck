import 'dart:async';

import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/dashboard_screen.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'bundled_type.dart';
import 'fakes.dart';

/// Every read the status tiles draw, failing as a restarting server's do,
/// or held as an unanswered one's are.
class _Reads extends FakeRepository {
  _Reads({required this.fail});

  final bool fail;
  final _never = Completer<Never>();

  Future<Never> _read() async {
    if (fail) {
      throw const WaxDeckApiException(
        code: 'internal',
        message: 'restarting',
        statusCode: 500,
      );
    }
    return _never.future;
  }

  @override
  Future<HealthSummary> getLibraryHealth() => _read();

  @override
  Future<ReviewStats> getReviewStats() => _read();

  @override
  Future<List<Job>> listJobs() => _read();

  @override
  Future<List<Backup>> listBackups() => _read();

  @override
  Future<List<Schedule>> listSchedules() => _read();

  @override
  Future<SimilarityStatus> getSimilarityStatus() => _read();

  @override
  Future<List<PlaybackSessionInfo>> listPlaybackSessions() => _read();

  @override
  Future<ThumbnailCacheReport> getThumbnailCache() => _read();

  @override
  Future<ServerHealth> health() => _read();
}

/// A server whose every tile read answers at once, in one shape.
class _Server extends FakeRepository {
  _Server({this.identifying = 0});

  final int identifying;

  @override
  Future<ReviewStats> getReviewStats() async => ReviewStats(
    pending: 12,
    decided: 0,
    identifying: identifying,
    applied: 0,
    autoApplied: 0,
    reverted: 0,
    revertedAutoApplied: 0,
  );
}

/// Every tile read answers but the schedules.
class _SchedulesDown extends _Server {
  @override
  Future<List<Schedule>> listSchedules() async =>
      throw const WaxDeckApiException(
        code: 'internal',
        message: 'restarting',
        statusCode: 500,
      );
}

/// The tiles by their handles.
Map<String, StatTile> _tiles(WidgetTester tester) => {
  for (final tile in tester.widgetList<StatTile>(find.byType(StatTile)))
    tile.semanticsId!: tile,
};

const _every = <String>[
  'health',
  'review',
  'jobs',
  'backups',
  'similarity',
  'thumbnails',
  'sessions',
  'streaming',
];

void main() {
  final en = AppLocalizationsEn();

  Future<void> pump(
    WidgetTester tester,
    FakeRepository repo, {
    Locale locale = const Locale('en'),
    double width = 1280,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    // A fresh scope for each server.
    await tester.pumpWidget(const SizedBox());
    await mountApp(
      tester,
      const AdminDashboardScreen(),
      container: appContainer(repo: repo),
      locale: locale,
    );
    await tester.pump();
  }

  testWidgets('a read still out reads as a dash and Loading, never a zero', (
    tester,
  ) async {
    await pump(tester, _Reads(fail: false));
    await tester.pump(const Duration(seconds: 1));

    final drawn = _tiles(tester);
    expect(drawn.keys, containsAll(_every.map(SemanticsIds.adminTile)));
    for (final tile in drawn.values) {
      expect(tile.value, '--', reason: tile.label);
      expect(tile.caption, en.adminTileLoading, reason: tile.label);
      expect(tile.tone, isNull, reason: tile.label);
    }
  });

  testWidgets('a read that failed says so in the error colour, never as a '
      'wait or a zero', (tester) async {
    await pump(tester, _Reads(fail: true));
    // Past the first retries: the reads that retry are loading again,
    // still carrying the failure.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    final error = WaxColors.of(tester.element(find.byType(StatTile).first));
    final drawn = _tiles(tester);
    expect(drawn.keys, containsAll(_every.map(SemanticsIds.adminTile)));
    for (final tile in drawn.values) {
      expect(tile.value, '--', reason: tile.label);
      expect(tile.caption, en.adminTileCouldNotRead, reason: tile.label);
      expect(tile.tone, error.error, reason: tile.label);
    }
    // Unmounted inside the test, so no retry timer outlives it.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a backup on record with its schedules unread says so in the '
      'error colour, like the other tiles do', (tester) async {
    await pump(
      tester,
      _SchedulesDown()
        ..backupsById['ba-1'] = Backup(
          id: 'ba-1',
          state: 'done',
          trigger: 'manual',
          fileName: 'waxdeck.tar.zst',
          createdAt: DateTime.now().subtract(const Duration(hours: 5)),
        ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    final error = WaxColors.of(tester.element(find.byType(StatTile).first));
    final drawn = _tiles(tester);
    final backups = drawn[SemanticsIds.adminTile('backups')]!;
    expect(backups.value, isNot('--'), reason: 'the backup itself was read');
    expect(backups.caption, en.adminTileCouldNotRead);
    expect(backups.tone, error.error);
    // The read that did answer is not painted as a failure.
    expect(drawn[SemanticsIds.adminTile('review')]!.tone, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  group('in the bundled type', () {
    setUpAll(loadBundledType);

    final now = DateTime.now();
    // Between them, every caption a tile draws.
    FakeRepository busy() => _Server(identifying: 1234)
      ..healthSummary = const HealthSummary(
        score: 72,
        totalItems: 123456,
        evaluatedItems: 98765,
      )
      ..jobs = [
        Job(
          pid: 'jb-1',
          kind: 'scan',
          state: 'running',
          startedAt: DateTime.utc(2026),
        ),
      ]
      ..backupsById['ba-1'] = Backup(
        id: 'ba-1',
        state: 'done',
        trigger: 'manual',
        fileName: 'waxdeck.tar.zst',
        createdAt: now.subtract(const Duration(hours: 5)),
      )
      ..schedules['backup'] = Schedule(
        kind: 'backup',
        cron: '0 3 * * *',
        enabled: true,
        nextRunAt: now.add(const Duration(hours: 23, minutes: 30)),
      )
      ..similarityStatus = const SimilarityStatus(
        enabled: true,
        embeddedTracks: 98765,
        totalTracks: 123456,
        coveragePct: 80,
        queueDepth: 12345,
      )
      ..thumbnailCache = const ThumbnailCacheReport(
        rows: 5,
        bytes: 1000,
        sources: 5,
        artSources: 5,
        artSourceBytes: 1000,
        rungs: <ThumbnailRung>[],
      )
      ..serverStreaming = const ServerStreaming(
        configured: true,
        connected: false,
      );
    FakeRepository quiet() => _Server()
      ..healthSummary = const HealthSummary(
        score: 100,
        totalItems: 0,
        evaluatedItems: 0,
        warmingUp: true,
      )
      ..similarityStatus = const SimilarityStatus(
        enabled: true,
        embeddedTracks: 123456,
        totalTracks: 123456,
        coveragePct: 100,
        queueDepth: 0,
      )
      ..serverStreaming = const ServerStreaming(
        configured: true,
        connected: true,
      );
    // A backup on record with its schedule off.
    FakeRepository unscheduled() => quiet()
      ..backupsById['ba-1'] = Backup(
        id: 'ba-1',
        state: 'done',
        trigger: 'manual',
        fileName: 'waxdeck.tar.zst',
        createdAt: now.subtract(const Duration(days: 2)),
      );

    /// The captions on screen, each with whether its tile cuts it short in
    /// the bundled type.
    Map<String, bool> captions(WidgetTester tester) {
      final read = <String, bool>{};
      for (final tile in tester.widgetList<StatTile>(find.byType(StatTile))) {
        final caption = tile.caption;
        if (caption == null) continue;
        read[caption] = tester
            .renderObject<RenderParagraph>(
              find.descendant(
                of: find.byWidget(tile),
                matching: find.text(caption),
              ),
            )
            .didExceedMaxLines;
      }
      return read;
    }

    /// The values on screen that their tile cuts short in the bundled type.
    List<String> valuesCut(WidgetTester tester) => <String>[
      for (final tile in tester.widgetList<StatTile>(find.byType(StatTile)))
        if (tester
            .renderObject<RenderParagraph>(
              find.descendant(
                of: find.byWidget(tile),
                matching: find.text(tile.value),
              ),
            )
            .didExceedMaxLines)
          '${tile.label}: ${tile.value}',
    ];

    for (final locale in const [Locale('en'), Locale('es')]) {
      testWidgets('every tile caption fits its tile whole at 1.0 in '
          '${locale.languageCode}', (tester) async {
        final read = <String, bool>{};
        for (final repo in [busy(), quiet(), unscheduled()]) {
          await pump(tester, repo, locale: locale);
          // Not settled: a running scan's spinner never stops.
          await tester.pump(const Duration(milliseconds: 100));
          read.addAll(captions(tester));
        }
        await pump(tester, _Reads(fail: false), locale: locale);
        read.addAll(captions(tester));
        await pump(tester, _Reads(fail: true), locale: locale);
        await tester.pump(const Duration(seconds: 1));
        read.addAll(captions(tester));
        await tester.pumpWidget(const SizedBox());

        expect(
          [
            for (final MapEntry(key: caption, value: cut) in read.entries)
              if (cut) caption,
          ],
          isEmpty,
          reason: 'cut short at 1.0',
        );
        // Each of the seventeen captions the tiles can draw, read once.
        expect(read, hasLength(17), reason: '${read.keys}');
      });

      testWidgets('at 2.0 every tile reads whole and a row is one height in '
          '${locale.languageCode}', (tester) async {
        final cut = <String>[];
        // A content area beside the console's sidebars, then one wide enough
        // for two columns, where a row has more than one tile to compare.
        for (final width in const <double>[800, 1100]) {
          for (final repo in [busy(), quiet(), unscheduled()]) {
            await pump(
              tester,
              repo,
              locale: locale,
              width: width,
              textScale: 2,
            );
            await tester.pump(const Duration(milliseconds: 100));
            cut.addAll(valuesCut(tester));
            captions(tester).forEach((caption, isCut) {
              if (isCut) cut.add(caption);
            });
            final byTop = <double, Set<double>>{};
            final tiles = tester.widgetList<StatTile>(find.byType(StatTile));
            for (final tile in tiles) {
              final rect = tester.getRect(find.byWidget(tile));
              byTop.putIfAbsent(rect.top, () => <double>{}).add(rect.height);
            }
            expect(
              byTop.values.every((heights) => heights.length == 1),
              isTrue,
              reason: '$byTop',
            );
            if (width > 1000) expect(byTop.length, lessThan(tiles.length));
          }
        }
        await tester.pumpWidget(const SizedBox());
        expect(cut, isEmpty, reason: 'cut short at 2.0');
      });
    }
  });
}
