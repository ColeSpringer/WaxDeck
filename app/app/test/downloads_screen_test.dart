import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_store.dart';
import 'package:waxdeck/src/artwork/artwork_store_io.dart';
import 'package:waxdeck/src/connectivity/connectivity_port.dart';
import 'package:waxdeck/src/downloads/download_state.dart';
import 'package:waxdeck/src/downloads/downloads_controller.dart';
import 'package:waxdeck/src/downloads/downloads_screen.dart';
import 'package:waxdeck/src/downloads/held_covers.dart';
import 'package:waxdeck/src/downloads/wifi_only_gate.dart';
import 'package:waxdeck/src/music/album_screen.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/notifications/notifications_controller.dart';
import 'package:waxdeck/src/notifications/notifications_screen.dart';
import 'package:waxdeck/src/settings/client_prefs.dart';
import 'package:waxdeck/src/shell/async_sliver_face.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart'
    show AlbumDetail, SessionState, WaxDeckUser;
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'artwork_fixtures.dart';
import 'fakes.dart';

const _track = 'tr-01JZX5N8QW3F4V9T2B7KDTRACK1';
const _episode = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';
const _book = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';
const _album = 'al-01JZX5N8QW3F4V9T2B7KDALBUM1';
const _base = 'http://deck.local:4420';
const _trackArt = '$_base/api/v1/items/$_track/art';
const _bookArt = '$_base/api/v1/items/$_book/art';

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
    WifiOnlyGate? gate,
    MirrorDatabase? mirror,
    ArtworkStore? store,
  }) async {
    downloads.setStored(stored);
    final db = mirror ?? await _mirror();
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
    final repo = ArtUnderBase(_base);
    await pumpApp(
      tester,
      const DownloadsScreen(),
      container: appContainer(
        repo: repo,
        mirror: db,
        downloads: downloads,
        artwork: store ?? artwork,
        sync: SyncEngine(
          db: db,
          repository: repo,
          channelFactory: deadChannelFactory(),
        ),
        extra: [if (gate != null) transferGateProvider.overrideWithValue(gate)],
      ),
    );
  }

  testWidgets('a refresh redraws the rows it already has', (tester) async {
    // Through the shared face, which decides from the value rather than
    // from the state's runtime type: a reload carries what it had.
    await pump(tester, stored: <DownloadedItem>[_stored(_track)]);
    expect(find.byType(AsyncSliverFace<DownloadsState>), findsOneWidget);
    expect(find.text('Prancing Pony Blues'), findsWidgets);

    final gate = Completer<void>();
    downloads.storedGate = gate;
    ProviderScope.containerOf(
      tester.element(find.byType(AsyncSliverFace<DownloadsState>)),
    ).invalidate(downloadsProvider);
    await tester.pump();
    await tester.pump();

    expect(find.text('Prancing Pony Blues'), findsWidgets);
    expect(
      find.byType(SkeletonShapes),
      findsNothing,
      reason: 'a reload must not blank the rows it already holds',
    );
    gate.complete();
    downloads.storedGate = null;
    await tester.pumpAndSettle();
  });

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
    expect(shellMessageText(raisedMessage(tester)), 'Removed 1 episode');
  });

  test('the sweep waits out its grace window', () async {
    // Two finished episodes, one past the window and one not.
    const stale = 'tr-01JZX5N8QW3F4V9T2B7KDEP0002';
    downloads.setStored(<DownloadedItem>[_stored(_episode), _stored(stale)]);
    final db = await _mirror();
    await db
        .into(db.mirrorItems)
        .insert(
          MirrorItemsCompanion.insert(
            pid: stale,
            ulid: stale.substring(3),
            mediaType: 'podcast',
            title: 'Second Breakfast',
            durationMs: 3600000,
            sortKey: 'second breakfast',
          ),
        );
    for (final row in <(String, DateTime)>[
      (_episode, DateTime.now().subtract(const Duration(minutes: 10))),
      (stale, DateTime.now().subtract(const Duration(days: 3))),
    ]) {
      await db
          .into(db.mirrorPlayStates)
          .insert(
            MirrorPlayStatesCompanion.insert(
              pid: row.$1,
              positionMs: const Value(3600000),
              finished: const Value(true),
              updatedAt: Value(row.$2),
            ),
          );
    }

    final repo = FakeRepository();
    final container = appContainer(
      repo: repo,
      mirror: db,
      downloads: downloads,
      artwork: artwork,
      sync: SyncEngine(
        db: db,
        repository: repo,
        channelFactory: deadChannelFactory(),
      ),
    );
    await container.read(downloadsProvider.future);

    // Off is off: the binder holds no timer and sweeps nothing.
    final idle = container.listen(downloadsTidyBinderProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(downloads.removed, isEmpty);
    idle.close();

    container.read(autoRemoveFinishedProvider.notifier).set(true);
    container.read(autoRemoveFinishedAfterHoursProvider.notifier).set(24);
    final alive = container.listen(downloadsTidyBinderProvider, (_, _) {});
    addTearDown(alive.close);
    await container.read(downloadsProvider.future);
    await Future<void>.delayed(Duration.zero);

    expect(downloads.removed, <String>[stale]);
    expect(artwork.unpinned, <String>[stale]);
  });

  testWidgets('remove-finished says so when there is nothing to remove', (
    tester,
  ) async {
    await pump(tester, stored: <DownloadedItem>[_stored(_episode)]);

    await _tap(tester, SemanticsIds.downloadsOverflow);
    await _tap(tester, SemanticsIds.downloadsRemoveFinished);

    expect(downloads.removed, isEmpty);
    expect(
      shellMessageText(raisedMessage(tester)),
      'No finished episodes to remove',
    );
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

    testWidgets('a pause that finds nothing left to fetch flips nothing', (
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
      // It landed under the tap, and the row is about to say so.
      expect(_byId(SemanticsIds.downloadPause(_book)), findsOneWidget);
      expect(_byId(SemanticsIds.downloadResume(_book)), findsNothing);
      expect(raisedMessage(tester), isNull);
    });

    testWidgets('a pause from an earlier run offers resume', (tester) async {
      await pump(
        tester,
        stored: <DownloadedItem>[
          const DownloadedItem(
            pid: _book,
            sizeBytes: 4194304,
            files: 3,
            complete: false,
            paused: true,
          ),
        ],
      );

      await _tap(tester, SemanticsIds.downloadResume(_book));

      expect(downloads.resumed, [_book]);
      expect(_byId(SemanticsIds.downloadPause(_book)), findsOneWidget);
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
      // it re-reads the store from inside a stream callback - worth a
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

    // Ended away from this screen: the notification's cancel, a sync
    // commit's free, or the manager giving up. The row must go with it.
    for (final (name, ending) in <(String, DownloadProgress)>[
      (
        'a stop from outside',
        const DownloadProgress(
          pid: _book,
          fraction: 0,
          complete: false,
          stopped: true,
        ),
      ),
      (
        'a failure',
        const DownloadProgress(
          pid: _book,
          fraction: 0,
          complete: false,
          failure: DownloadFailure.interrupted,
        ),
      ),
    ]) {
      testWidgets('$name reloads the list and drops the transfer', (
        tester,
      ) async {
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
        expect(find.text('Transferring'), findsOneWidget);

        downloads.setStored(const <DownloadedItem>[]);
        downloads.emit(ending);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Transferring'), findsNothing);
        expect(find.byType(MediaListRow), findsNothing);
      });
    }

    testWidgets('a transfer the wifi-only gate holds reads as held', (
      tester,
    ) async {
      // One state, one reading: the row says what the book's pill and the
      // player's icon say, and stops once the gate opens.
      final net = _Net();
      final gate = WifiOnlyGate(connectivity: net, wifiOnly: () => true);
      addTearDown(gate.dispose);
      await pump(
        tester,
        stored: <DownloadedItem>[
          const DownloadedItem(
            pid: _book,
            sizeBytes: 4194304,
            files: 3,
            complete: false,
            active: true,
          ),
        ],
        gate: gate,
      );

      MediaTileData row() =>
          tester.widget<MediaListRow>(find.byType(MediaListRow).first).data;
      expect(row().trailingDetail, 'Waiting for wifi');
      expect(
        row().trailingDetailSpoken,
        'Waiting for wifi. Download on wifi only is on',
      );

      net.move(ConnectionCost.unmetered);
      await tester.pumpAndSettle();
      expect(row().trailingDetail, isNull);
    });

    testWidgets('every row reads the one gate, and no row asks the device', (
      tester,
    ) async {
      final net = _Net();
      final gate = WifiOnlyGate(connectivity: net, wifiOnly: () => true);
      addTearDown(gate.dispose);
      downloads.dispose();
      final counting = downloads = _CountingDownloads();
      await pump(
        tester,
        stored: <DownloadedItem>[
          for (final pid in [_book, _track])
            DownloadedItem(
              pid: pid,
              sizeBytes: 1024,
              files: 1,
              complete: false,
              active: true,
            ),
        ],
        gate: gate,
      );

      final rows = tester.widgetList<MediaListRow>(find.byType(MediaListRow));
      expect(
        [for (final r in rows) r.data.trailingDetail],
        ['Waiting for wifi', 'Waiting for wifi'],
      );
      expect(net.asked, 1);
      expect(counting.probes, 0);
    });

    testWidgets('a paused row is not held, and is again once resumed', (
      tester,
    ) async {
      final net = _Net();
      final gate = WifiOnlyGate(connectivity: net, wifiOnly: () => true);
      addTearDown(gate.dispose);
      await pump(
        tester,
        stored: <DownloadedItem>[
          const DownloadedItem(
            pid: _book,
            sizeBytes: 4194304,
            files: 3,
            complete: false,
            active: true,
          ),
        ],
        gate: gate,
      );
      MediaTileData row() =>
          tester.widget<MediaListRow>(find.byType(MediaListRow).first).data;
      expect(row().trailingDetail, 'Waiting for wifi');

      await _tap(tester, SemanticsIds.downloadPause(_book));
      expect(row().trailingDetail, isNull);
      expect(row().trailingDetailSpoken, isNull);

      await _tap(tester, SemanticsIds.downloadResume(_book));
      expect(row().trailingDetail, 'Waiting for wifi');
    });

    testWidgets('a pause keeps the bar where it was and reloads the row', (
      tester,
    ) async {
      await pump(
        tester,
        stored: <DownloadedItem>[
          const DownloadedItem(
            pid: _book,
            sizeBytes: 4194304,
            files: 3,
            complete: false,
            active: true,
          ),
        ],
      );
      downloads.emit(
        const DownloadProgress(pid: _book, fraction: 0.4, complete: false),
      );
      await tester.pumpAndSettle();

      // Paused by something other than this screen's button.
      downloads.setStored(<DownloadedItem>[
        const DownloadedItem(
          pid: _book,
          sizeBytes: 4194304,
          files: 3,
          complete: false,
          paused: true,
        ),
      ]);
      downloads.emit(
        const DownloadProgress(
          pid: _book,
          fraction: 0.4,
          complete: false,
          paused: true,
        ),
      );
      await tester.pumpAndSettle();

      final row = tester.widget<MediaListRow>(find.byType(MediaListRow).first);
      expect(row.data.progress, closeTo(0.4, 0.001));
      expect(_byId(SemanticsIds.downloadResume(_book)), findsOneWidget);
    });

    testWidgets('a transfer nothing moves is not held, as its pill is not', (
      tester,
    ) async {
      // Parked on a not-found, or rows left with no transfer: the book's
      // pill offers the download, so the row must not say it is waiting.
      final net = _Net();
      final gate = WifiOnlyGate(connectivity: net, wifiOnly: () => true);
      addTearDown(gate.dispose);
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
        gate: gate,
      );

      final row = tester.widget<MediaListRow>(find.byType(MediaListRow).first);
      expect(row.data.trailingDetail, isNull);
      expect(row.data.trailingDetailSpoken, isNull);
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

    testWidgets('a pause from an earlier run, resumed with the gate shut, '
        'reads held', (tester) async {
      final gate = WifiOnlyGate(connectivity: _Net(), wifiOnly: () => true);
      addTearDown(gate.dispose);
      await pump(
        tester,
        stored: <DownloadedItem>[
          // What the manager recovers a pause as: paused, and not active.
          const DownloadedItem(
            pid: _book,
            sizeBytes: 4194304,
            files: 3,
            complete: false,
            paused: true,
          ),
        ],
        gate: gate,
      );
      MediaTileData row() =>
          tester.widget<MediaListRow>(find.byType(MediaListRow).first).data;
      expect(row().trailingDetail, isNull);

      await _tap(tester, SemanticsIds.downloadResume(_book));

      expect(downloads.resumed, [_book]);
      expect(_byId(SemanticsIds.downloadPause(_book)), findsOneWidget);
      expect(row().trailingDetail, 'Waiting for wifi');
    });

    testWidgets('a pause from an earlier visit, resumed with the gate shut, '
        'reads held', (tester) async {
      final gate = WifiOnlyGate(connectivity: _Net(), wifiOnly: () => true);
      addTearDown(gate.dispose);
      downloads.setStored(<DownloadedItem>[
        const DownloadedItem(
          pid: _book,
          sizeBytes: 4194304,
          files: 3,
          complete: false,
          active: true,
        ),
      ]);
      final db = await _mirror();
      final repo = FakeRepository();
      final visible = ValueNotifier<bool>(true);
      addTearDown(visible.dispose);
      await pumpApp(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (context, shown, _) =>
              shown ? const DownloadsScreen() : const SizedBox.shrink(),
        ),
        container: appContainer(
          repo: repo,
          mirror: db,
          downloads: downloads,
          artwork: artwork,
          sync: SyncEngine(
            db: db,
            repository: repo,
            channelFactory: deadChannelFactory(),
          ),
          extra: [transferGateProvider.overrideWithValue(gate)],
        ),
      );
      MediaTileData row() =>
          tester.widget<MediaListRow>(find.byType(MediaListRow).first).data;
      await _tap(tester, SemanticsIds.downloadPause(_book));
      expect(row().trailingDetail, isNull);

      // Leaving the screen takes the progress fold with it; the list of
      // what is held outlives it.
      visible.value = false;
      await tester.pumpAndSettle();
      visible.value = true;
      await tester.pumpAndSettle();
      await _tap(tester, SemanticsIds.downloadResume(_book));

      expect(downloads.resumed, [_book]);
      expect(_byId(SemanticsIds.downloadPause(_book)), findsOneWidget);
      expect(row().trailingDetail, 'Waiting for wifi');
    });
  });

  group('covers pinned for offline', () {
    MediaTileData row(WidgetTester tester) =>
        tester.widget<MediaListRow>(find.byType(MediaListRow)).data;

    testWidgets('a row with nothing pinned draws its monogram and asks for '
        'nothing', (tester) async {
      await pump(tester, stored: <DownloadedItem>[_stored(_track)]);

      expect(row(tester).artwork, isNull);
      expect(artwork.requested, isEmpty);
    });

    group('with the real store', () {
      // Built outside the test's fake clock, as the walk awaits the mirror
      // from real time and a database opened under the fake one never
      // answers it there.
      var reach = false;
      late Directory temp;
      late MirrorDatabase db;
      late FakeArtServer server;
      late FakeArtCache cache;
      late CachedArtworkStore store;

      setUp(() async {
        temp = Directory.systemTemp.createTempSync('waxdeck-downloads');
        db = await _mirror();
        // The walk asks about a pin only for an item the device holds.
        await db
            .into(db.downloadRecords)
            .insert(
              DownloadRecordsCompanion.insert(
                pid: _track,
                fileIndex: 0,
                essenceHash: 'essence',
                etag: '1-1',
                fileName: 'track.flac',
                localPath: '/downloads/track.flac',
                sizeBytes: 4194304,
                state: 'complete',
              ),
            );
        final pins = DriftArtworkPinStore(db);
        final old = await artPng(40);
        for (final rung in kOfflineArtworkRungs) {
          final file = File('${temp.path}/$rung.img')..writeAsBytesSync(old);
          await pins.put(
            ArtworkPinRecord(
              pid: _track,
              sizePx: rung,
              artUrl: _trackArt,
              etag: '"old-$rung"',
              localPath: file.path,
              sizeBytes: old.length,
              pinnedAt: DateTime.utc(2026, 11, 18),
            ),
          );
        }
        reach = false;
        server = FakeArtServer();
        cache = FakeArtCache();
        store = CachedArtworkStore(
          baseUrl: _base,
          pins: pins,
          client: Dio()..httpClientAdapter = server,
          pinDirectory: temp,
          cache: cache,
          reachable: () => reach,
        );
      });

      tearDown(() async {
        store.dispose();
        temp.deleteSync(recursive: true);
      });

      testWidgets('a stored row draws its pinned cover with no server, and '
          'the new one once a cover change rewrites the pin', (tester) async {
        await pump(
          tester,
          stored: <DownloadedItem>[_stored(_track)],
          mirror: db,
          store: store,
        );
        expect(row(tester).artwork?.cover, _trackArt);
        await coverDraws(tester, 40);
        expect(cache.asked, isEmpty, reason: 'the disk cache fetches nothing');
        expect(
          server.requested,
          isEmpty,
          reason: 'the pin is read, and the store asks nothing of its own',
        );

        // What a frame naming the item does, with the server back long
        // enough for the walk to bring the pin up to date.
        final fresh = (await tester.runAsync(() => artPng(24)))!;
        for (final rung in kOfflineArtworkRungs) {
          server.serveBytes('$_trackArt?size=$rung', fresh);
        }
        await tester.runAsync(() async {
          await store.evict(_trackArt);
          await store.settled;
        });
        for (final rung in kOfflineArtworkRungs) {
          server.cut('$_trackArt?size=$rung');
        }
        await coverDraws(tester, 24);
        expect(cache.asked, isEmpty);
      });

      testWidgets('a row whose cover a sign-out took draws it once the server '
          'is in reach, and off its pin with the server gone again', (
        tester,
      ) async {
        // The audio kept, every pin dropped.
        await tester.runAsync(store.forgetEverything);
        final picture = (await tester.runAsync(() => artPng(24)))!;
        for (final rung in kOfflineArtworkRungs) {
          server.serveBytes('$_trackArt?size=$rung', picture);
        }
        await pump(
          tester,
          stored: <DownloadedItem>[_stored(_track)],
          mirror: db,
          store: store,
        );
        expect(row(tester).artwork, isNull);

        reach = true;
        final container = ProviderScope.containerOf(
          tester.element(find.byType(DownloadsScreen)),
        );
        await tester.runAsync(() async {
          await pinHeldCovers(container);
          await store.settled;
        });
        await tester.pumpAndSettle();
        expect(row(tester).artwork?.cover, _trackArt);
        await coverDraws(tester, 24);

        // A later visit, nothing decoded and nobody to ask.
        reach = false;
        for (final rung in kOfflineArtworkRungs) {
          server.cut('$_trackArt?size=$rung');
        }
        server.requested.clear();
        cache.asked.clear();
        await tester.pumpWidget(const SizedBox());
        PaintingBinding.instance.imageCache.clear();
        await pump(
          tester,
          stored: <DownloadedItem>[_stored(_track)],
          mirror: db,
          store: store,
        );
        expect(row(tester).artwork?.cover, _trackArt);
        await coverDraws(tester, 24);
        expect(cache.asked, isEmpty);
        expect(server.requested, isEmpty);
      });
    });

    testWidgets('a cover pinned while the server was at another address is '
        "the row's under this one", (tester) async {
      final db = await _mirror();
      await DriftArtworkPinStore(db).put(
        ArtworkPinRecord(
          pid: _track,
          sizePx: 1024,
          artUrl: 'http://old.local:4420/api/v1/items/$_track/art',
          etag: '"1024"',
          localPath: '/art/$_track-1024.img',
          sizeBytes: 1024,
          pinnedAt: DateTime.utc(2026, 11, 18),
        ),
      );

      await pump(tester, stored: <DownloadedItem>[_stored(_track)], mirror: db);

      expect(row(tester).artwork?.cover, _trackArt);
    });

    testWidgets('a cover pinned after the list was built reaches its row', (
      tester,
    ) async {
      final db = await _mirror();
      final pinning = _PinningArtworkStore(db);
      await pump(
        tester,
        stored: <DownloadedItem>[
          const DownloadedItem(
            pid: _book,
            sizeBytes: 4194304,
            files: 1,
            complete: false,
          ),
        ],
        mirror: db,
        store: pinning,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(DownloadsScreen)),
      );
      final starting = container
          .read(downloadStateProvider(_book).notifier)
          .start(artUrl: _bookArt);
      await tester.pump();

      // The audio lands and the list is built again, before the cover has.
      downloads.byPid[_book] = testLocal('/books/one.m4b');
      downloads.setStored(<DownloadedItem>[_stored(_book)]);
      downloads.emit(
        const DownloadProgress(pid: _book, fraction: 1, complete: true),
      );
      await tester.pumpAndSettle();
      expect(pinning.pinned, [_book]);
      expect(row(tester).artwork, isNull);

      pinning.landing.complete();
      await tester.pumpAndSettle();
      await starting;

      expect(row(tester).artwork?.cover, _bookArt);
      expect(pinning.requested, contains(_bookArt));
    });

    testWidgets('a cover that lands after the app has let go of its '
        'providers is not an error', (tester) async {
      final db = await _mirror();
      final pinning = _PinningArtworkStore(db);
      await pump(
        tester,
        stored: <DownloadedItem>[
          const DownloadedItem(
            pid: _book,
            sizeBytes: 4194304,
            files: 1,
            complete: false,
          ),
        ],
        mirror: db,
        store: pinning,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(DownloadsScreen)),
      );
      final starting = container
          .read(downloadStateProvider(_book).notifier)
          .start(artUrl: _bookArt);
      await tester.pump();
      downloads.byPid[_book] = testLocal('/books/one.m4b');
      downloads.setStored(<DownloadedItem>[_stored(_book)]);
      downloads.emit(
        const DownloadProgress(pid: _book, fraction: 1, complete: true),
      );
      await tester.pumpAndSettle();
      expect(pinning.pinned, [_book]);

      // The tree goes, and its container with it.
      await tester.pumpWidget(const SizedBox());
      pinning.landing.complete();
      await tester.pumpAndSettle();
      await starting;
    });
  });

  testWidgets('a download notification opens the screen, and its arrow walks '
      'back through Notifications to the album', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeRepository(
      sessionState: const SessionState(
        authenticated: true,
        user: WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']),
      ),
    )..albums[_album] = const AlbumDetail(pid: _album, title: 'Gullwing');
    final container = await pumpWholeApp(
      tester,
      container: appContainer(repo: repo, downloads: downloads),
      disableAnimations: true,
    );
    final router = container.read(routerProvider);
    router.go(WaxRoute.musicBucket(MusicDimension.albums, _album));
    await tester.pumpAndSettle();
    router.go(WaxRoute.notifications);
    await tester.pumpAndSettle();
    container
        .read(localNotificationsProvider.notifier)
        .recordDownloadCompleted(at: DateTime.now());
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsIdentifier(
        SemanticsIds.notificationRowPlain(NotificationKind.download.token),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DownloadsScreen), findsOneWidget);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.navBack));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsScreen), findsOneWidget);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.navBack));
    await tester.pumpAndSettle();
    expect(find.byType(AlbumScreen), findsOneWidget);
  });
}

/// Pins a cover in the mirror once [landing] is let go: a cover still on
/// its way when the audio has landed.
class _PinningArtworkStore extends FakeArtworkStore {
  _PinningArtworkStore(this.db);

  final MirrorDatabase db;
  final landing = Completer<void>();

  @override
  Future<void> pinForOffline(String pid, String? artUrl) async {
    await super.pinForOffline(pid, artUrl);
    await landing.future;
    await DriftArtworkPinStore(db).put(
      ArtworkPinRecord(
        pid: pid,
        sizePx: 1024,
        artUrl: artUrl!,
        etag: '"1024"',
        localPath: '/art/$pid-1024.img',
        sizeBytes: 1024,
        pinnedAt: DateTime.utc(2026, 11, 18),
      ),
    );
  }
}

/// A connection that starts on mobile data and moves when told.
class _Net implements ConnectivityPort {
  ConnectionCost now = ConnectionCost.metered;
  final _costs = StreamController<ConnectionCost>.broadcast();

  /// How many times the platform was asked.
  var asked = 0;

  @override
  Future<ConnectionCost> cost() async {
    asked++;
    return now;
  }

  @override
  Stream<ConnectionCost> get costs => _costs.stream;

  @override
  Stream<void> get returns => const Stream<void>.empty();

  void move(ConnectionCost cost) {
    now = cost;
    _costs.add(cost);
  }
}

/// Counts the reads a per-item download state makes of the device.
class _CountingDownloads extends FakeDownloads {
  var probes = 0;

  @override
  Future<DownloadedItem?> storedItem(String pid) {
    probes++;
    return super.storedItem(pid);
  }

  @override
  Future<bool> isComplete(String pid) {
    probes++;
    return super.isComplete(pid);
  }
}
