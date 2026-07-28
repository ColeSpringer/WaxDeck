import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_persistence.dart';
import 'package:waxdeck/src/queue/queue_panel.dart';
import 'package:waxdeck/src/queue/queue_screen.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/settings/client_settings_providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

const _album = QueueSource(
  kind: QueueSourceKind.album,
  label: 'Gullwing',
  pid: 'al-1',
);

PlaybackSessionHistoryEntry _session(
  String id, {
  List<String> pids = const ['tr-1', 'tr-2'],
  int index = 0,
  String? endpointName = 'The kitchen',
  DateTime? stoppedAt,
}) => PlaybackSessionHistoryEntry(
  id: id,
  endpointId: 'pe-1',
  endpointName: endpointName,
  authority: 'mirror',
  index: index,
  positionMs: 42000,
  positionAt: stoppedAt ?? DateTime.utc(2026, 7, 28, 9),
  rate: 1,
  entries: <PlaybackSessionEntry>[
    for (final pid in pids)
      PlaybackSessionEntry(pid: pid, title: 'Track $pid', artist: 'Nightjar'),
  ],
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  FakeRepository? repository,
  ClientSettingsStore? settings,
  Size size = const Size(500, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repository ?? FakeRepository()),
      audioEngineProvider.overrideWithValue(FakeEngine()),
      if (settings != null)
        clientSettingsStoreProvider.overrideWithValue(settings),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: routedHost(const QueueScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

List<String> _rowTitles(WidgetTester tester) => tester
    .widgetList<MediaListRow>(find.byType(MediaListRow))
    .map((row) => row.data.title)
    .toList();

void main() {
  group('the queue screen', () {
    testWidgets('an empty queue says so', (tester) async {
      await _pump(tester);

      expect(find.text('Nothing queued'), findsOneWidget);
    });

    testWidgets('lists what is playing and what follows it', (tester) async {
      final container = await _pump(tester);
      container
          .read(queueControllerProvider.notifier)
          .playNow(['tr-1', 'tr-2', 'tr-3'], source: _album, startIndex: 1);
      await tester.pumpAndSettle();

      expect(find.text('Playing from Gullwing'), findsOneWidget);
      expect(find.text('UP NEXT'), findsOneWidget);
      // The played head is collapsed: one entry behind, one ahead, and
      // the current one pinned at the top.
      expect(find.text('PREVIOUSLY (1)'), findsOneWidget);
      expect(_rowTitles(tester), hasLength(2));
    });

    testWidgets('the played head opens and closes', (tester) async {
      final container = await _pump(tester);
      container
          .read(queueControllerProvider.notifier)
          .playNow(['tr-1', 'tr-2', 'tr-3'], source: _album, startIndex: 2);
      await tester.pumpAndSettle();

      expect(_rowTitles(tester), hasLength(1));
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.queueHistory));
      await tester.pumpAndSettle();
      expect(_rowTitles(tester), hasLength(3));
    });

    testWidgets('a row drops out when its remove is pressed', (tester) async {
      final container = await _pump(tester);
      final queue = container.read(queueControllerProvider.notifier);
      queue.playNow(['tr-1', 'tr-2', 'tr-3'], source: _album);
      await tester.pumpAndSettle();

      final entries = container.read(queueControllerProvider).entries;
      await tester.tap(
        find.bySemanticsIdentifier(
          SemanticsIds.queueEntryRemove(entries[2].queueId),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(queueControllerProvider).pids, ['tr-1', 'tr-2']);
    });

    testWidgets('a swipe drops a row too', (tester) async {
      final container = await _pump(tester);
      container.read(queueControllerProvider.notifier).playNow([
        'tr-1',
        'tr-2',
        'tr-3',
      ], source: _album);
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Dismissible).first, const Offset(600, 0));
      await tester.pumpAndSettle();

      expect(container.read(queueControllerProvider).pids, ['tr-1', 'tr-3']);
    });

    testWidgets('a drag reorders what is up next, not the played head', (
      tester,
    ) async {
      final container = await _pump(tester);
      final queue = container.read(queueControllerProvider.notifier);
      queue.playNow(
        ['tr-1', 'tr-2', 'tr-3', 'tr-4'],
        source: _album,
        startIndex: 1,
      );
      await tester.pumpAndSettle();

      final entries = container.read(queueControllerProvider).entries;
      // The list under the drag holds tr-3 and tr-4; the queue holds
      // tr-1 in front of them, which is exactly the offset a reorder
      // gets wrong when the surface forgets the played head.
      final handle = find.bySemanticsIdentifier(
        SemanticsIds.queueEntryDrag(entries[3].queueId),
      );
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(container.read(queueControllerProvider).pids, [
        'tr-1',
        'tr-2',
        'tr-4',
        'tr-3',
      ]);
    });

    testWidgets('a drag down moves an entry past the one below it', (
      tester,
    ) async {
      // The other direction from the drag above, which is where the two
      // reorder conventions differ: `onReorderItem` has already adjusted
      // for the removal, and a surface still subtracting one for it
      // would land this a row short.
      final container = await _pump(tester);
      container.read(queueControllerProvider.notifier).playNow([
        'tr-1',
        'tr-2',
        'tr-3',
      ], source: _album);
      await tester.pumpAndSettle();

      final entries = container.read(queueControllerProvider).entries;
      final handle = find.bySemanticsIdentifier(
        SemanticsIds.queueEntryDrag(entries[1].queueId),
      );
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(container.read(queueControllerProvider).pids, [
        'tr-1',
        'tr-3',
        'tr-2',
      ]);
    });

    testWidgets('a rolling window says it is one', (tester) async {
      final container = await _pump(tester);
      container.read(queueControllerProvider.notifier).playNow(
        ['tr-1', 'tr-2'],
        source: const QueueSource(
          kind: QueueSourceKind.genre,
          label: 'Jazz',
          pid: 'ge-1',
          rolling: true,
          cursor: 'c-1',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('A window over a larger scope'),
        findsOneWidget,
      );
    });

    testWidgets('an earlier session can be put back from here', (tester) async {
      final repository = FakeRepository()
        ..sessionHistory = <PlaybackSessionHistoryEntry>[
          _session('ps-1', pids: ['tr-9', 'tr-8'], index: 1),
        ];
      final container = await _pump(tester, repository: repository);

      expect(find.text('EARLIER'), findsOneWidget);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.queueRestoreSession('ps-1')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final queue = container.read(queueControllerProvider);
      expect(queue.pids, ['tr-9', 'tr-8']);
      expect(queue.currentPid, 'tr-8');
      container.read(queueControllerProvider.notifier).clear();
      await tester.pumpAndSettle();
    });

    testWidgets('a server with no history offers nothing', (tester) async {
      await _pump(tester);

      expect(find.text('EARLIER'), findsNothing);
    });
  });

  group('the queue panel', () {
    testWidgets('shows the same queue the screen does', (tester) async {
      // The panel and the screen are one set of slivers at two widths;
      // only the frame around them differs, and a test that drove one of
      // them would not have said so.
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(FakeRepository()),
          audioEngineProvider.overrideWithValue(FakeEngine()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: routedHost(const QueuePanel()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nothing queued'), findsOneWidget);

      container.read(queueControllerProvider.notifier).playNow([
        'tr-1',
        'tr-2',
      ], source: _album);
      await tester.pumpAndSettle();

      expect(find.text('Playing from Gullwing'), findsOneWidget);
      expect(_rowTitles(tester), hasLength(2));

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.queueClear));
      await tester.pumpAndSettle();
      expect(container.read(queueControllerProvider).isEmpty, isTrue);
    });
  });

  group('the launch offer from the server', () {
    test(
      'a launch with nothing on disk offers the account\'s last session',
      () async {
        final repository = FakeRepository()
          ..sessionHistory = <PlaybackSessionHistoryEntry>[
            _session('ps-1', pids: ['tr-1', 'tr-2'], index: 1),
          ];
        final container = ProviderContainer(
          overrides: [repositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);

        final offer = await container.read(queueRestoreProvider.future);

        expect(offer, isNotNull);
        expect(offer!.queue.pids, ['tr-1', 'tr-2']);
        expect(offer.queue.currentIndex, 1);
        expect(offer.sessionId, 'ps-1');
        expect(offer.currentItem?.title, 'Track tr-2');
      },
    );

    test(
      'a session already turned down on this device is not offered again',
      () async {
        final settings = MemoryClientSettingsStore();
        await settings.write(
          ClientSettingKeys.resumeDeclinedThrough,
          DateTime.utc(2026, 7, 28, 9).toIso8601String(),
        );
        final repository = FakeRepository()
          ..sessionHistory = <PlaybackSessionHistoryEntry>[_session('ps-1')];
        final container = ProviderContainer(
          overrides: [
            repositoryProvider.overrideWithValue(repository),
            clientSettingsStoreProvider.overrideWithValue(settings),
          ],
        );
        addTearDown(container.dispose);

        expect(await container.read(queueRestoreProvider.future), isNull);
      },
    );

    test(
      'turning a server offer down records it rather than clearing a disk',
      () async {
        final settings = MemoryClientSettingsStore();
        final repository = FakeRepository()
          ..sessionHistory = <PlaybackSessionHistoryEntry>[_session('ps-7')];
        final container = ProviderContainer(
          overrides: [
            repositoryProvider.overrideWithValue(repository),
            clientSettingsStoreProvider.overrideWithValue(settings),
          ],
        );
        addTearDown(container.dispose);
        await container.read(queueRestoreProvider.future);

        await container.read(queueRestoreProvider.notifier).dismiss();

        expect(
          await settings.read(ClientSettingKeys.resumeDeclinedThrough),
          DateTime.utc(2026, 7, 28, 9).toIso8601String(),
        );
        expect(container.read(queueRestoreProvider).value, isNull);
      },
    );

    test('declining an offer declines the sessions behind it too', () async {
      // One stored id would offer the next-oldest session at the next
      // launch, and the one after that at the one after: the history is
      // newest first, so a decline is about everything up to it.
      final settings = MemoryClientSettingsStore();
      final repository = FakeRepository()
        ..sessionHistory = <PlaybackSessionHistoryEntry>[
          _session('ps-new', stoppedAt: DateTime.utc(2026, 7, 28, 12)),
          _session('ps-old', stoppedAt: DateTime.utc(2026, 7, 28, 9)),
        ];
      ProviderContainer launch() {
        final container = ProviderContainer(
          overrides: [
            repositoryProvider.overrideWithValue(repository),
            clientSettingsStoreProvider.overrideWithValue(settings),
          ],
        );
        addTearDown(container.dispose);
        return container;
      }

      final first = launch();
      await first.read(queueRestoreProvider.future);
      await first.read(queueRestoreProvider.notifier).dismiss();

      expect(await launch().read(queueRestoreProvider.future), isNull);

      // One that stopped later is newer than the decision, and is
      // offered.
      repository.sessionHistory = <PlaybackSessionHistoryEntry>[
        _session('ps-newest', stoppedAt: DateTime.utc(2026, 7, 28, 18)),
      ];
      expect(
        (await launch().read(queueRestoreProvider.future))?.sessionId,
        'ps-newest',
      );
    });

    test('a launch offline offers nothing rather than failing', () async {
      final repository = FakeRepository()
        ..sessionHistoryError = const WaxDeckApiException(
          code: 'internal',
          message: 'offline',
        );
      final container = ProviderContainer(
        overrides: [repositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      expect(await container.read(queueRestoreProvider.future), isNull);
    });

    test('an ended session with an empty queue is not an offer', () async {
      final repository = FakeRepository()
        ..sessionHistory = <PlaybackSessionHistoryEntry>[
          _session('ps-1', pids: const []),
          _session('ps-2', pids: const ['tr-5']),
        ];
      final container = ProviderContainer(
        overrides: [repositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      final offer = await container.read(queueRestoreProvider.future);

      expect(offer!.sessionId, 'ps-2');
    });

    test('a book in a restored session keeps its own shape', () async {
      final repository = FakeRepository()
        ..sessionHistory = <PlaybackSessionHistoryEntry>[
          _session('ps-1', pids: const ['bk-1']),
        ];
      final container = ProviderContainer(
        overrides: [repositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      final offer = await container.read(queueRestoreProvider.future);

      expect(offer!.currentItem?.mediaType, MediaType.audiobook);
    });
  });
}
