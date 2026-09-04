import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/radio/radio_saved_controller.dart';
import 'package:waxdeck/src/radio/radio_saved_screen.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

RadioSavedSong _song({
  required String pid,
  required String line,
  String? artist,
  String? title,
  String? inLibraryPid,
  bool hasArt = false,
}) => RadioSavedSong(
  pid: pid,
  nowPlaying: line,
  artist: artist,
  title: title,
  stationPid: 'rs-01JZX5N8QW3F4V9T2B7KDSTATN1',
  stationName: 'Coastal FM',
  heardAt: DateTime.utc(2026, 7, 1),
  inLibraryPid: inLibraryPid,
  hasArt: hasArt,
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeRepository repo,
) async {
  // Desktop-sized: the identify handoff pushes the review entry, which
  // sits inside the admin console's sidebar shell and wants the width.
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: routedHost(const RadioSavedScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('the list names what was heard and where', (tester) async {
    final repo = FakeRepository()
      ..seedSavedSong(
        _song(
          pid: 'rw-1',
          line: 'Salt Harbour - The Bree Trio',
          artist: 'Salt Harbour',
          title: 'The Bree Trio',
        ),
      )
      // An announcement nothing parsed out of still saves, and the row
      // leads with the line the listener saw.
      ..seedSavedSong(_song(pid: 'rw-2', line: 'Coastal FM overnight'));
    await _pump(tester, repo);

    expect(find.text('The Bree Trio'), findsOneWidget);
    // Who it is by and where it was heard ride one caption, so the
    // row's own controls keep the end of it.
    expect(find.text('Salt Harbour · Coastal FM'), findsOneWidget);
    expect(find.text('Coastal FM overnight'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.radioSavedEntry('rw-1')),
      findsOneWidget,
    );
  });

  testWidgets('a row the library has since acquired says so', (tester) async {
    final repo = FakeRepository()
      ..seedSavedSong(
        _song(
          pid: 'rw-1',
          line: 'Salt Harbour - The Bree Trio',
          artist: 'Salt Harbour',
          title: 'The Bree Trio',
          inLibraryPid: 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
        ),
      )
      ..seedSavedSong(
        _song(
          pid: 'rw-2',
          line: 'Nobody - Nothing',
          artist: 'Nobody',
          title: 'Nothing',
        ),
      );
    await _pump(tester, repo);

    expect(find.textContaining('In your library now'), findsOneWidget);
  });

  testWidgets('a row can be forgotten and leaves the list', (tester) async {
    final repo = FakeRepository()
      ..seedSavedSong(
        _song(
          pid: 'rw-1',
          line: 'Salt Harbour - The Bree Trio',
          artist: 'Salt Harbour',
          title: 'The Bree Trio',
        ),
      );
    final container = await _pump(tester, repo);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.radioSavedRemove('rw-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('The Bree Trio'), findsNothing);
    expect(container.read(radioSavedProvider).value?.songs, isEmpty);
    expect((await repo.listRadioSavedSongs()).songs, isEmpty);
  });

  testWidgets('half a parsed pair searches the announcement instead', (
    tester,
  ) async {
    // The schema makes artist and title independently optional even
    // though this server sends them as a pair, and half a pair
    // interpolated would put the word "null" in a search box.
    final repo = FakeRepository()
      ..seedSavedSong(
        _song(
          pid: 'rw-1',
          line: 'Salt Harbour - The Bree Trio',
          artist: 'Salt Harbour',
        ),
      );
    await _pump(tester, repo);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.radioSavedFind('rw-1')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('null'), findsNothing);
  });

  testWidgets('an empty list explains where rows come from', (tester) async {
    await _pump(tester, FakeRepository());

    expect(find.text('Nothing saved yet'), findsOneWidget);
    expect(find.textContaining('Tap the heart'), findsOneWidget);
  });

  testWidgets('the row menu hands the song to Add-from-URL', (tester) async {
    final repo = FakeRepository()
      ..seedSavedSong(
        _song(
          pid: 'rw-1',
          line: 'Salt Harbour - The Bree Trio',
          artist: 'Salt Harbour',
          title: 'The Bree Trio',
        ),
      );
    await _pump(tester, repo);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.radioSavedMore('rw-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.radioSavedAcquire),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add from URL'), findsOneWidget);
  });

  testWidgets('finding a song and identifying one do not share a glyph', (
    tester,
  ) async {
    // Two actions on the same row drawn with the same magnifying glass:
    // the always-visible one searches the library for the title, and
    // the menu's one works out what the recording is. A glance could
    // not tell them apart.
    final repo = FakeRepository()
      ..seedSavedSong(
        _song(
          pid: 'rw-1',
          line: 'Salt Harbour - The Bree Trio',
          artist: 'Salt Harbour',
          title: 'The Bree Trio',
        ),
      );
    await _pump(tester, repo);

    expect(
      tester
          .widget<WaxIconButton>(
            find.ancestor(
              of: find.bySemanticsIdentifier(
                SemanticsIds.radioSavedFind('rw-1'),
              ),
              matching: find.byType(WaxIconButton),
            ),
          )
          .glyph,
      WaxIcons.search,
    );

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.radioSavedMore('rw-1')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<WaxOptionRow>(
            find.ancestor(
              of: find.bySemanticsIdentifier(SemanticsIds.radioSavedIdentify),
              matching: find.byType(WaxOptionRow),
            ),
          )
          .glyph,
      WaxIcons.fingerprint,
    );
  });

  testWidgets('the identify handoff lists pending singles and hands the '
      'parse to the one picked', (tester) async {
    final repo = FakeRepository()
      ..seedSavedSong(
        _song(
          pid: 'rw-1',
          line: 'Salt Harbour - The Bree Trio',
          artist: 'Salt Harbour',
          title: 'The Bree Trio',
        ),
      );
    repo.reviewEntries = <ReviewEntry>[
      _reviewEntry('rv-1'),
      // An album-sized unit cannot honestly be one radio song, and a
      // decided entry has nothing left to search.
      _reviewEntry('rv-2', trackCount: 9),
      _reviewEntry('rv-3', status: 'applied'),
    ];
    repo.reviewEntryDetails['rv-1'] = _reviewEntry('rv-1');
    await _pump(tester, repo);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.radioSavedMore('rw-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.radioSavedIdentify),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.radioSavedIdentifyEntry('rv-1')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.radioSavedIdentifyEntry('rv-2')),
      findsNothing,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.radioSavedIdentifyEntry('rv-3')),
      findsNothing,
    );

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.radioSavedIdentifyEntry('rv-1')),
    );
    await tester.pumpAndSettle();

    expect(repo.reidentifyCalls.single, (
      entryId: 'rv-1',
      artist: 'Salt Harbour',
      album: null,
      title: 'The Bree Trio',
    ));
    // Onto the entry, where the candidates the search finds land: the
    // route mounts the review surface with this entry open, and the
    // identify group is the part of it the handoff exists to reach.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.reviewIdentifyGroup),
      findsOneWidget,
    );
  });

  testWidgets('an unparsed announcement hands the whole line', (tester) async {
    final repo = FakeRepository()
      ..seedSavedSong(_song(pid: 'rw-1', line: 'Coastal FM overnight'));
    repo.reviewEntries = <ReviewEntry>[_reviewEntry('rv-1')];
    repo.reviewEntryDetails['rv-1'] = _reviewEntry('rv-1');
    await _pump(tester, repo);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.radioSavedMore('rw-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.radioSavedIdentify),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.radioSavedIdentifyEntry('rv-1')),
    );
    await tester.pumpAndSettle();

    expect(repo.reidentifyCalls.single, (
      entryId: 'rv-1',
      artist: null,
      album: null,
      title: 'Coastal FM overnight',
    ));
  });

  testWidgets('no pending singles says where they come from', (tester) async {
    final repo = FakeRepository()
      ..seedSavedSong(
        _song(
          pid: 'rw-1',
          line: 'Salt Harbour - The Bree Trio',
          artist: 'Salt Harbour',
          title: 'The Bree Trio',
        ),
      );
    await _pump(tester, repo);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.radioSavedMore('rw-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.radioSavedIdentify),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No pending single tracks'), findsOneWidget);
    expect(repo.reidentifyCalls, isEmpty);
  });
}

/// A review entry in the fake's queue; the defaults are the shape the
/// identify sheet offers, and a test departs from them one field at a
/// time.
ReviewEntryDetail _reviewEntry(
  String id, {
  int trackCount = 1,
  String status = 'pending',
}) => ReviewEntryDetail(
  id: id,
  kind: 'import',
  status: status,
  mediaType: MediaType.music,
  origin: 'acquisition',
  title: 'brree trio official audio',
  artist: 'Topic Channel',
  trackCount: trackCount,
  createdAt: DateTime.utc(2026, 8, 1),
  candidates: const [],
);
