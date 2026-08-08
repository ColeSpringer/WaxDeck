import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/radio/radio_saved_controller.dart';
import 'package:waxdeck/src/radio/radio_saved_screen.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

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
}
