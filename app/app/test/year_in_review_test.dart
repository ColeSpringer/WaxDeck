import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/artwork/artwork_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck/src/stats/share_card_export.dart';
import 'package:waxdeck/src/stats/share_cards.dart';
import 'package:waxdeck/src/stats/year_in_review_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

/// Keeps whatever it is handed, so a test can read the card back.
class _FakeExporter implements ShareCardExporter {
  _FakeExporter({this.canExport = true});

  @override
  final bool canExport;

  final List<({List<int> png, String fileName})> exports = [];

  @override
  Future<ShareCardOutcome> export({
    required List<int> png,
    required String fileName,
    required String subject,
  }) async {
    exports.add((png: png, fileName: fileName));
    return const ShareCardSaved('Downloads');
  }
}

/// The width and height a PNG declares in its IHDR, which is the only
/// part of it this test cares about: the card's whole promise is that it
/// comes out at the size the format names, whatever device drew it.
(int, int) _pngSize(List<int> png) {
  int at(int offset) =>
      (png[offset] << 24) |
      (png[offset + 1] << 16) |
      (png[offset + 2] << 8) |
      png[offset + 3];
  return (at(16), at(20));
}

ProviderContainer _container(
  FakeRepository repo, {
  ShareCardExporter? exporter,
  ArtworkStore? artwork,
}) {
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      artworkStoreProvider.overrideWithValue(artwork ?? FakeArtworkStore()),
      if (exporter != null)
        shareCardExporterProvider.overrideWithValue(exporter),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _host(
  FakeRepository repo, {
  ShareCardExporter? exporter,
  ArtworkStore? artwork,
}) => _hosted(_container(repo, exporter: exporter, artwork: artwork));

/// A one-pixel opaque PNG, so a cover is really fetched, really decoded,
/// and really painted into the captured frame. The card's whole
/// artwork story is "decoded before the frame", and a fake that skips
/// the decode would prove none of it.
final _onePixelPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
  0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
  0xde, 0x00, 0x00, 0x00, 0x0c, 0x49, 0x44, 0x41,
  0x54, 0x08, 0xd7, 0x63, 0xf8, 0xcf, 0xc0, 0x00,
  0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xdd, 0x8d,
  0xb0, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e,
  0x44, 0xae, 0x42, 0x60, 0x82,
]);

Widget _hosted(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
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

/// Five top artists: three with covers, one without, one past the
/// widest card's room.
YearInReview _recapWithCovers(int year) => YearInReview(
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
  topArtists: const <TopEntry>[
    TopEntry(name: 'The Bree Trio', artUrl: '/art/ar-1', plays: 12, ms: 720000),
    TopEntry(name: 'Bombadil', artUrl: '/art/ar-2', plays: 9, ms: 540000),
    TopEntry(name: 'Gaffer', plays: 7, ms: 420000),
    TopEntry(name: 'Rosie', plays: 5, ms: 300000),
    TopEntry(name: 'Fatty', plays: 3, ms: 180000),
    TopEntry(name: 'Lobelia', artUrl: '/art/ar-4', plays: 1, ms: 60000),
  ],
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
    // Nothing to put on a card either.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.shareCardOpen),
      findsNothing,
    );
  });

  testWidgets('the recap exports a card at its declared pixel size', (
    tester,
  ) async {
    // Tall enough for the sheet to hold both previews without the
    // horizontal list clipping the one under test.
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = FakeRepository()..yearInReview = _recap(DateTime.now().year);
    final exporter = _FakeExporter();
    final container = _container(repo, exporter: exporter);
    await tester.pumpWidget(_hosted(container));
    await tester.pumpAndSettle();

    final door = find.bySemanticsIdentifier(SemanticsIds.shareCardOpen);
    await tester.ensureVisible(door);
    await tester.pumpAndSettle();
    await tester.tap(door);
    await tester.pumpAndSettle();

    // Both shapes are offered, drawn as they will export.
    for (final format in ShareCardFormat.values) {
      expect(
        find.bySemanticsIdentifier(SemanticsIds.shareCardPreview(format.name)),
        findsOneWidget,
      );
    }

    // Through runAsync: `toImage` is real raster work and the fake
    // clock never lets it complete. Polled, like the share-intake test.
    await tester.runAsync(() async {
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.shareCardExport('square')),
      );
      for (var waited = 0; waited < 5000; waited += 10) {
        await tester.pump();
        if (exporter.exports.isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    expect(exporter.exports, hasLength(1));
    expect(
      exporter.exports.single.fileName,
      'waxdeck-${DateTime.now().year}-square.png',
    );
    // At the format's own pixel size, not the preview's: the boundary
    // wraps the card's own 1080-wide layout and the shrinking is a
    // transform above it.
    expect(_pngSize(exporter.exports.single.png), (1080, 1080));
    expect(container.read(shellMessengerProvider)?.text, 'Saved to Downloads');
  });

  // The card used to be names alone, with `TopEntry.artUrl` arriving on
  // the wire and being dropped on the floor.
  testWidgets('covers are fetched on open and exported in the frame', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..yearInReview = _recapWithCovers(DateTime.now().year);
    final artwork = FakeArtworkStore()
      ..bytes['/art/ar-1'] = _onePixelPng
      ..bytes['/art/ar-2'] = _onePixelPng;
    final exporter = _FakeExporter();
    final container = _container(repo, exporter: exporter, artwork: artwork);

    await tester.runAsync(() async {
      await tester.pumpWidget(_hosted(container));
      await tester.pumpAndSettle();

      final door = find.bySemanticsIdentifier(SemanticsIds.shareCardOpen);
      await tester.ensureVisible(door);
      await tester.pumpAndSettle();
      await tester.tap(door);
      await tester.pumpAndSettle();

      // Asked for on open, at one rung, once each - the preview is the
      // export, so waiting for the button would show a card the export
      // did not match.
      for (var waited = 0; waited < 5000; waited += 10) {
        await tester.pump();
        if (artwork.byteRequests.length >= 2) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        artwork.byteRequests.map((r) => r.url),
        containsAll(<String>['/art/ar-1', '/art/ar-2']),
      );
      // The artist with no cover is never asked about, and the fourth
      // is past what even the story shape draws.
      expect(
        artwork.byteRequests.map((r) => r.url),
        isNot(contains('/art/ar-4')),
      );

      // Both shapes export at their own size with the covers painted -
      // the story's fixed 1920 has to absorb five cover rows, which is
      // the shape that could overflow.
      for (final format in ShareCardFormat.values) {
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.shareCardExport(format.name)),
        );
        for (var waited = 0; waited < 5000; waited += 10) {
          await tester.pump();
          if (exporter.exports.any((e) => e.fileName.contains(format.name))) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
    });

    expect(exporter.exports, hasLength(2));
    for (final format in ShareCardFormat.values) {
      final png = exporter.exports
          .firstWhere((e) => e.fileName.contains(format.name))
          .png;
      expect(_pngSize(png), (
        format.size.width.toInt(),
        format.size.height.toInt(),
      ));
    }
    expect(tester.takeException(), isNull);
  });

  // Offline, or a cover the server has no bytes for: the card still
  // renders and still exports, with a monogram where the picture would
  // be. One frame, no network in it.
  testWidgets('a card whose covers do not arrive still exports', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..yearInReview = _recapWithCovers(DateTime.now().year);
    final exporter = _FakeExporter();
    final container = _container(
      repo,
      exporter: exporter,
      artwork: FakeArtworkStore(),
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(_hosted(container));
      await tester.pumpAndSettle();
      final door = find.bySemanticsIdentifier(SemanticsIds.shareCardOpen);
      await tester.ensureVisible(door);
      await tester.pumpAndSettle();
      await tester.tap(door);
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.shareCardExport('square')),
      );
      for (var waited = 0; waited < 5000; waited += 10) {
        await tester.pump();
        if (exporter.exports.isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    expect(exporter.exports, hasLength(1));
    expect(_pngSize(exporter.exports.single.png), (1080, 1080));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a build that cannot keep an image says so', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = FakeRepository()..yearInReview = _recap(DateTime.now().year);
    await tester.pumpWidget(
      _host(repo, exporter: _FakeExporter(canExport: false)),
    );
    await tester.pumpAndSettle();

    final door = find.bySemanticsIdentifier(SemanticsIds.shareCardOpen);
    await tester.ensureVisible(door);
    await tester.pumpAndSettle();
    await tester.tap(door);
    await tester.pumpAndSettle();

    expect(find.textContaining('preview only'), findsOneWidget);
  });
}
