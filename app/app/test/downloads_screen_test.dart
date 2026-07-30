import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/downloads/downloads_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'offline_library_test.dart' show deadChannelFactory;
import 'routed_host.dart';

const _track = 'tr-01JZX5N8QW3F4V9T2B7KDTRACK1';
const _episode = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';
const _book = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';

DownloadedItem _stored(String pid, {int bytes = 4194304, int files = 1}) =>
    DownloadedItem(pid: pid, sizeBytes: bytes, files: files, complete: true);

/// A mirror holding the three items, so the rows can be about something.
Future<MirrorDatabase> _mirror() async {
  final db = inMemoryMirrorDatabase();
  addTearDown(db.close);
  for (final row in <(String, String, String)>[
    (_track, 'music', 'Prancing Pony Blues'),
    (_episode, 'podcast', 'Pipeweed Economics'),
    (_book, 'audiobook', 'There And Back Again'),
  ]) {
    await db
        .into(db.mirrorItems)
        .insert(
          MirrorItemsCompanion.insert(
            pid: row.$1,
            ulid: row.$1.substring(3),
            mediaType: row.$2,
            title: row.$3,
            durationMs: 3600000,
            sortKey: row.$3.toLowerCase(),
          ),
        );
  }
  return db;
}

Finder _byId(String id) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.identifier == id,
);

Future<void> _tap(WidgetTester tester, String id) async {
  final finder = _byId(id).first;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  late FakeDownloads downloads;
  late FakeArtworkStore artwork;

  setUp(() {
    downloads = FakeDownloads();
    artwork = FakeArtworkStore();
  });

  tearDown(() => downloads.dispose());

  Future<void> pump(
    WidgetTester tester, {
    List<DownloadedItem> stored = const <DownloadedItem>[],
    Map<String, int> positions = const <String, int>{},
    Set<String> finished = const <String>{},
  }) async {
    downloads.setStored(stored);
    final db = await _mirror();
    for (final entry in positions.entries) {
      await db
          .into(db.mirrorPlayStates)
          .insert(
            MirrorPlayStatesCompanion.insert(
              pid: entry.key,
              positionMs: Value(entry.value),
              finished: Value(finished.contains(entry.key)),
            ),
          );
    }
    final repo = FakeRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          audioEngineProvider.overrideWithValue(FakeEngine()),
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
          mirrorDatabaseProvider.overrideWithValue(db),
          downloadManagerProvider.overrideWithValue(downloads),
          artworkStoreProvider.overrideWithValue(artwork),
          syncEngineProvider.overrideWithValue(
            SyncEngine(
              db: db,
              repository: repo,
              channelFactory: deadChannelFactory(),
            ),
          ),
        ],
        child: routedHost(const DownloadsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('nothing downloaded says what downloading is for', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Nothing downloaded'), findsOneWidget);
    expect(_byId(SemanticsIds.downloadsStorage), findsNothing);
  });

  testWidgets('the header adds up what is held, per medium', (tester) async {
    await pump(
      tester,
      stored: <DownloadedItem>[
        _stored(_track, bytes: 10 * 1024 * 1024),
        _stored(_book, bytes: 300 * 1024 * 1024, files: 3),
      ],
    );

    expect(_byId(SemanticsIds.downloadsStorage), findsOneWidget);
    expect(find.text('310.0 MB'), findsOneWidget);
    expect(find.text('Audiobooks 300.0 MB'), findsOneWidget);
    expect(find.text('Music 10.0 MB'), findsOneWidget);
  });

  testWidgets('rows are grouped by medium, biggest group first', (
    tester,
  ) async {
    await pump(
      tester,
      stored: <DownloadedItem>[
        _stored(_track, bytes: 1024),
        _stored(_book, bytes: 1024 * 1024),
      ],
    );

    final headers = tester
        .widgetList<SectionHeader>(find.byType(SectionHeader))
        .map((h) => h.title)
        .toList();
    expect(headers, ['Audiobooks', 'Music']);
    expect(find.text('There And Back Again'), findsOneWidget);
    expect(find.text('Prancing Pony Blues'), findsOneWidget);
  });

  testWidgets('removing an item drops its audio and unpins its cover', (
    tester,
  ) async {
    await pump(tester, stored: <DownloadedItem>[_stored(_book)]);

    await _tap(tester, SemanticsIds.downloadRemove(_book));

    expect(downloads.removed, [_book], reason: 'the audio goes');
    expect(
      artwork.unpinned,
      [_book],
      reason:
          'and so does the cover pinned beside it, which nothing but a '
          'sign-out would otherwise reclaim',
    );
    expect(find.text('Nothing downloaded'), findsOneWidget);
  });

  testWidgets('clear all confirms, then reclaims everything', (tester) async {
    await pump(
      tester,
      stored: <DownloadedItem>[_stored(_track), _stored(_book)],
    );

    await _tap(tester, SemanticsIds.downloadsClearAll);
    expect(find.text('Remove every download?'), findsOneWidget);
    // Declining leaves the disk alone.
    await tester.tap(find.text('Keep them'));
    await tester.pumpAndSettle();
    expect(downloads.removed, isEmpty);

    await _tap(tester, SemanticsIds.downloadsClearAll);
    await tester.tap(find.text('Remove all'));
    await tester.pumpAndSettle();
    expect(downloads.removed, containsAll(<String>[_track, _book]));
    expect(artwork.unpinned, containsAll(<String>[_track, _book]));
  });

  testWidgets('remove-finished takes the played episodes and nothing else', (
    tester,
  ) async {
    await pump(
      tester,
      stored: <DownloadedItem>[
        _stored(_episode),
        _stored(_book),
        _stored(_track),
      ],
      positions: <String, int>{
        _episode: 3600000,
        _book: 3600000,
        _track: 3600000,
      },
      // The book is finished too, and stays: a book played through is one
      // somebody may want again, and an episode is the medium whose whole
      // point is that it is done with.
      finished: <String>{_episode, _book, _track},
    );

    await _tap(tester, SemanticsIds.downloadsOverflow);
    await _tap(tester, SemanticsIds.downloadsRemoveFinished);

    expect(downloads.removed, [_episode]);
    expect(find.text('Removed 1 episode'), findsOneWidget);
  });

  testWidgets('remove-finished says so when there is nothing to remove', (
    tester,
  ) async {
    await pump(tester, stored: <DownloadedItem>[_stored(_episode)]);

    await _tap(tester, SemanticsIds.downloadsOverflow);
    await _tap(tester, SemanticsIds.downloadsRemoveFinished);

    expect(downloads.removed, isEmpty);
    expect(find.text('No finished episodes to remove'), findsOneWidget);
  });

  testWidgets('the stale sweep asks for every held item again', (tester) async {
    await pump(
      tester,
      stored: <DownloadedItem>[_stored(_track), _stored(_book)],
    );

    await _tap(tester, SemanticsIds.downloadsOverflow);
    await _tap(tester, SemanticsIds.downloadsRefresh);

    // `download` is what compares essence hashes per file and re-fetches
    // only what moved, so asking for everything is the stale sweep.
    expect(downloads.downloaded, containsAll(<String>[_track, _book]));
  });

  group('transfers in flight', () {
    testWidgets('a pending item is a transfer, not a holding', (tester) async {
      await pump(
        tester,
        stored: <DownloadedItem>[
          const DownloadedItem(
            pid: _book,
            sizeBytes: 4194304,
            files: 3,
            complete: false,
          ),
        ],
      );

      expect(find.text('Transferring'), findsOneWidget);
      expect(_byId(SemanticsIds.downloadCancel(_book)), findsOneWidget);
      expect(_byId(SemanticsIds.downloadPause(_book)), findsOneWidget);
      // And it is not counted as bytes on disk.
      expect(find.text('0 B'), findsOneWidget);
    });

    testWidgets('canceling stops it and drops the row', (tester) async {
      await pump(
        tester,
        stored: <DownloadedItem>[
          const DownloadedItem(
            pid: _book,
            sizeBytes: 4194304,
            files: 3,
            complete: false,
          ),
        ],
      );

      await _tap(tester, SemanticsIds.downloadCancel(_book));
      expect(downloads.canceled, [_book]);
      expect(find.text('Transferring'), findsNothing);
    });

    testWidgets('a transfer that cannot pause says so and keeps running', (
      tester,
    ) async {
      downloads.pausable = false;
      await pump(
        tester,
        stored: <DownloadedItem>[
          const DownloadedItem(
            pid: _book,
            sizeBytes: 4194304,
            files: 3,
            complete: false,
          ),
        ],
      );

      await _tap(tester, SemanticsIds.downloadPause(_book));

      expect(downloads.paused, [_book]);
      expect(
        find.text('This transfer cannot be paused; cancel it instead'),
        findsOneWidget,
      );
      // The control did not flip: nothing was paused.
      expect(_byId(SemanticsIds.downloadPause(_book)), findsOneWidget);
      expect(_byId(SemanticsIds.downloadResume(_book)), findsNothing);
    });

    testWidgets('a paused flag stays with its own row', (tester) async {
      // Unkeyed state follows position: a transfer finishing and dropping
      // out used to hand its paused flag to whichever row slid up.
      await pump(
        tester,
        stored: <DownloadedItem>[
          const DownloadedItem(
            pid: _track,
            sizeBytes: 1024,
            files: 1,
            complete: false,
          ),
          const DownloadedItem(
            pid: _book,
            sizeBytes: 4194304,
            files: 3,
            complete: false,
          ),
        ],
      );

      await _tap(tester, SemanticsIds.downloadPause(_track));
      expect(_byId(SemanticsIds.downloadResume(_track)), findsOneWidget);

      // The track finishes and leaves; the book slides into its place.
      downloads.setStored(<DownloadedItem>[
        const DownloadedItem(
          pid: _book,
          sizeBytes: 4194304,
          files: 3,
          complete: false,
        ),
      ]);
      downloads.emit(
        const DownloadProgress(pid: _track, fraction: 1, complete: true),
      );
      await tester.pumpAndSettle();

      expect(
        _byId(SemanticsIds.downloadPause(_book)),
        findsOneWidget,
        reason: 'the book was never paused',
      );
      expect(_byId(SemanticsIds.downloadResume(_book)), findsNothing);
    });

    testWidgets('a paused transfer offers resume', (tester) async {
      await pump(
        tester,
        stored: <DownloadedItem>[
          const DownloadedItem(
            pid: _book,
            sizeBytes: 4194304,
            files: 3,
            complete: false,
          ),
        ],
      );

      await _tap(tester, SemanticsIds.downloadPause(_book));
      expect(_byId(SemanticsIds.downloadResume(_book)), findsOneWidget);

      await _tap(tester, SemanticsIds.downloadResume(_book));
      expect(downloads.resumed, [_book]);
    });
    testWidgets('a transfer that completes turns into a holding', (
      tester,
    ) async {
      // The progress stream is what drives the bars, and a completion on
      // it re-reads the store from inside a stream callback — worth a
      // test of its own, because an invalidate from the wrong place
      // throws at runtime and nothing else here would see it.
      await pump(
        tester,
        stored: <DownloadedItem>[
          const DownloadedItem(
            pid: _book,
            sizeBytes: 4194304,
            files: 3,
            complete: false,
          ),
        ],
      );
      expect(find.text('Transferring'), findsOneWidget);

      downloads.setStored(<DownloadedItem>[_stored(_book)]);
      downloads.emit(
        const DownloadProgress(pid: _book, fraction: 1, complete: true),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Transferring'), findsNothing);
      expect(find.text('Audiobooks'), findsOneWidget);
    });

    testWidgets('a bar moves as the stream reports', (tester) async {
      await pump(
        tester,
        stored: <DownloadedItem>[
          const DownloadedItem(
            pid: _book,
            sizeBytes: 4194304,
            files: 3,
            complete: false,
          ),
        ],
      );

      downloads.emit(
        const DownloadProgress(pid: _book, fraction: 0.4, complete: false),
      );
      await tester.pumpAndSettle();

      final row = tester.widget<MediaListRow>(find.byType(MediaListRow).first);
      expect(row.data.progress, closeTo(0.4, 0.001));
    });
  });
}
