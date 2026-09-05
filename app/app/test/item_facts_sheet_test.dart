import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/library/item_facts_sheet.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

ItemSummary _item(String pid, MediaType mediaType) => ItemSummary(
  pid: pid,
  mediaType: mediaType,
  title: 'Harbour Lights',
  artist: 'Nightjar',
  durationMs: 258000,
);

Finder _row(String key) =>
    find.bySemanticsIdentifier(SemanticsIds.itemFactsRow(key));

/// The value half of one row, which is what the sheet is about: the
/// labels are l10n keys and the numbers are the answer.
String _value(WidgetTester tester, String key) => tester
    .widget<MonoDetailRow>(
      find.ancestor(of: _row(key), matching: find.byType(MonoDetailRow)),
    )
    .value;

Future<void> _pump(
  WidgetTester tester,
  FakeRepository repository, {
  String pid = 'tr-1',
  MediaType mediaType = MediaType.music,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repository)],
      child: routedHost(ItemFactsSheet(pid: pid, mediaType: mediaType)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a track lists its play record, its tempo, and its file', (
    tester,
  ) async {
    final repository = FakeRepository(items: [_item('tr-1', MediaType.music)])
      ..finishedPids.add('tr-1')
      ..playStateLastPlayedAt['tr-1'] = DateTime.now().subtract(
        const Duration(hours: 3),
      )
      ..itemDetailBpm['tr-1'] = 128
      ..itemDetailMbid['tr-1'] = 'b9b3d3f9-1e2b-4a1e-9a4a-1a2b3c4d5e6f'
      ..itemDetailIsrc['tr-1'] = 'USRC17607839';

    await _pump(tester, repository);

    expect(_value(tester, 'plays'), '1');
    expect(_value(tester, 'last-played'), '3h ago');
    expect(_value(tester, 'bpm'), '128 BPM');
    expect(_value(tester, 'duration'), '4:18');
    expect(_value(tester, 'year'), '1975');
    expect(_value(tester, 'genres'), 'Blues');
    expect(_value(tester, 'codec'), 'FLAC');
    expect(_value(tester, 'container'), 'FLAC');
    expect(_value(tester, 'sample-rate'), '44.1 kHz');
    expect(_value(tester, 'bitrate'), '986 kbps');
    expect(_value(tester, 'mbid'), 'b9b3d3f9-1e2b-4a1e-9a4a-1a2b3c4d5e6f');
    expect(_value(tester, 'isrc'), 'USRC17607839');
  });

  testWidgets('an item nobody has finished says never rather than a date', (
    tester,
  ) async {
    final repository = FakeRepository(items: [_item('tr-1', MediaType.music)]);

    await _pump(tester, repository);

    expect(_value(tester, 'plays'), '0');
    expect(_value(tester, 'last-played'), 'Never');
  });

  testWidgets('a play marked by hand reads as unknown, not as never', (
    tester,
  ) async {
    // What the played button leaves behind: the catalog raises the
    // count to one and deliberately stamps no time, because nobody
    // listened here. "Never" beside a count of one is a contradiction.
    final repository = FakeRepository(items: [_item('tr-1', MediaType.music)])
      ..finishedPids.add('tr-1');

    await _pump(tester, repository);

    expect(_value(tester, 'plays'), '1');
    expect(_value(tester, 'last-played'), 'Unknown');
  });

  testWidgets('a play from years back keeps a scale a reader can hold', (
    tester,
  ) async {
    final repository = FakeRepository(items: [_item('tr-1', MediaType.music)])
      ..finishedPids.add('tr-1')
      ..playStateLastPlayedAt['tr-1'] = DateTime.now().subtract(
        const Duration(days: 400),
      );

    await _pump(tester, repository);

    expect(_value(tester, 'last-played'), '13mo ago');
  });

  testWidgets('a sample rate keeps the digits it needs and no others', (
    tester,
  ) async {
    // 22.05 kHz is what half of CD rate actually is, and the rate a
    // spoken-word file is usually encoded at. Rounding it to one place
    // says 22.1, which is a rate nothing uses.
    final repository = FakeRepository(items: [_item('tr-1', MediaType.music)])
      ..itemDetailSampleRate = 22050;

    await _pump(tester, repository);

    expect(_value(tester, 'sample-rate'), '22.05 kHz');
  });

  testWidgets('a detail that will not load says so and offers a retry', (
    tester,
  ) async {
    // A pid the fake holds no item for, which is what a track deleted
    // under an open listing reads as. The play rows are the catalog's
    // own and still draw; the file's half is what is missing.
    final repository = FakeRepository(items: [_item('tr-1', MediaType.music)]);

    await _pump(tester, repository, pid: 'tr-gone');

    expect(_row('plays'), findsOneWidget);
    expect(_row('codec'), findsNothing);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.itemFactsError),
      findsOneWidget,
    );
  });

  testWidgets('a row whose value the catalog does not hold is not drawn', (
    tester,
  ) async {
    // The common shape: a library that was scanned and never matched
    // carries no tempo and no identifiers at all.
    final repository = FakeRepository(items: [_item('tr-1', MediaType.music)])
      ..itemDetailYear = null
      ..itemDetailGenres = const []
      ..itemDetailBitrate = null;

    await _pump(tester, repository);

    expect(_row('bpm'), findsNothing);
    expect(_row('mbid'), findsNothing);
    expect(_row('isrc'), findsNothing);
    expect(_row('year'), findsNothing);
    expect(_row('genres'), findsNothing);
    expect(_row('bitrate'), findsNothing);
    expect(_row('codec'), findsOneWidget);
  });

  testWidgets('a book carries the play and file rows, and no tempo', (
    tester,
  ) async {
    // Tempo is a music tag; a book that somehow carries one would be
    // answering a question nobody asked of an audiobook.
    final repository = FakeRepository(
      items: [_item('bk-1', MediaType.audiobook)],
    )..itemDetailBpm['bk-1'] = 128;

    await _pump(
      tester,
      repository,
      pid: 'bk-1',
      mediaType: MediaType.audiobook,
    );

    expect(_row('bpm'), findsNothing);
    expect(_row('plays'), findsOneWidget);
    expect(_row('codec'), findsOneWidget);
  });

  testWidgets('the sheet is named for the item it was raised for', (
    tester,
  ) async {
    final repository = FakeRepository(items: [_item('tr-1', MediaType.music)]);

    await _pump(tester, repository);

    expect(
      find.bySemanticsIdentifier(SemanticsIds.itemFactsSheet('tr-1')),
      findsOneWidget,
    );
  });
}
