import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/connectivity/connectivity_port.dart';
import 'package:waxdeck/src/downloads/downloads_controller.dart';
import 'package:waxdeck/src/downloads/downloads_screen.dart';
import 'package:waxdeck/src/downloads/wifi_only_gate.dart';
import 'package:waxdeck/src/settings/client_prefs.dart';
import 'package:waxdeck/src/shell/async_sliver_face.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

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
    WifiOnlyGate? gate,
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
    await pumpApp(
      tester,
      const DownloadsScreen(),
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
