import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_panel.dart';
import 'package:waxdeck/src/queue/queue_persistence.dart';
import 'package:waxdeck/src/queue/queue_screen.dart';
import 'package:waxdeck/src/queue/queue_state.dart' as queue_state;
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/queue/queue_view.dart';
import 'package:waxdeck/src/settings/client_settings_providers.dart';
import 'package:waxdeck/src/shell/commands.dart';
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

/// The queue screen over a router arranged the way the app arranges it,
/// which the plain [routedHost] cannot be: the key map has to sit inside
/// the router and above the navigator the screen is on, and a shell
/// route is where the app satisfies both.
Widget _keyboardHost(Widget screen) {
  final router = GoRouter(
    initialLocation: '/under-test/queue',
    routes: <RouteBase>[
      ShellRoute(
        builder: (context, state, child) => CommandShortcuts(child: child),
        routes: <RouteBase>[
          GoRoute(
            path: '/under-test',
            builder: (context, state) => const Scaffold(),
            routes: <RouteBase>[
              GoRoute(path: 'queue', builder: (context, state) => screen),
            ],
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  return MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: waxLocalizationsDelegates,
    supportedLocales: waxSupportedLocales,
  );
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

    testWidgets('putting a session back offers the live queue back', (
      tester,
    ) async {
      // The one undo affordance for a replaced queue, and the reason
      // `undoReplace` stayed when the "Replaced what was playing" toast
      // went: restoring from here replaces something that is playing, so
      // a mis-tap in a list of old sessions has to be recoverable.
      final repository = FakeRepository()
        ..sessionHistory = <PlaybackSessionHistoryEntry>[
          _session('ps-1', pids: ['tr-9', 'tr-8'], index: 1),
        ];
      final container = await _pump(tester, repository: repository);
      container
          .read(queueControllerProvider.notifier)
          .playNow(['tr-1', 'tr-2'], source: _album, startIndex: 1);
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.queueRestoreSession('ps-1')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));

      expect(container.read(queueControllerProvider).pids, ['tr-9', 'tr-8']);
      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final queue = container.read(queueControllerProvider);
      expect(queue.pids, ['tr-1', 'tr-2']);
      expect(queue.currentPid, 'tr-2');
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

  group('picking a set of up-next rows', () {
    /// The queue ids of the entries at [positions].
    List<String> idsAt(ProviderContainer container, List<int> positions) {
      final entries = container.read(queueControllerProvider).entries;
      return [for (final at in positions) entries[at].queueId];
    }

    /// A press and hold on one up-next row, which is the way in.
    ///
    /// `warnIfMissed` off throughout this group: the row's identifier
    /// sits on its content region, a wrapper the hit test walks past
    /// rather than into, so the warning is about the finder rather than
    /// about the gesture. What proves each press landed is the count the
    /// selection bar draws.
    Future<void> longPress(WidgetTester tester, String queueId) async {
      await tester.longPress(
        find.bySemanticsIdentifier(SemanticsIds.queueEntry(queueId)),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a long press starts a selection and the bar counts it', (
      tester,
    ) async {
      final container = await _pump(tester);
      container.read(queueControllerProvider.notifier).playNow([
        'tr-1',
        'tr-2',
        'tr-3',
        'tr-4',
      ], source: _album);
      await tester.pumpAndSettle();

      // Nothing picked means no bar: an empty set is not a mode.
      expect(
        find.bySemanticsIdentifier(SemanticsIds.queueSelectionRemove),
        findsNothing,
      );

      await longPress(tester, idsAt(container, [1]).single);
      expect(find.text('1 selected'), findsOneWidget);

      // The current entry is out of scope: the batch verbs are about
      // what has not played yet.
      expect(
        find.bySemanticsIdentifier(
          SemanticsIds.queueEntrySelect(idsAt(container, [0]).single),
        ),
        findsNothing,
      );

      // While selecting, a tap picks rather than jumps.
      await tester.tap(
        find.bySemanticsIdentifier(
          SemanticsIds.queueEntry(idsAt(container, [3]).single),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      expect(container.read(queueControllerProvider).currentIndex, 0);

      // And the checkbox is its own control beside the row.
      await tester.tap(
        find.bySemanticsIdentifier(
          SemanticsIds.queueEntrySelect(idsAt(container, [3]).single),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('the bar removes the set and moves it in one go', (
      tester,
    ) async {
      final container = await _pump(tester);
      container.read(queueControllerProvider.notifier).playNow([
        'tr-1',
        'tr-2',
        'tr-3',
        'tr-4',
      ], source: _album);
      await tester.pumpAndSettle();

      await longPress(tester, idsAt(container, [2]).single);
      await longPress(tester, idsAt(container, [3]).single);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.queueSelectionTop),
      );
      await tester.pumpAndSettle();

      // Gathered at the top of up-next, under what is playing, in their
      // own order - and the selection survives, so a second move works.
      expect(container.read(queueControllerProvider).pids, [
        'tr-1',
        'tr-3',
        'tr-4',
        'tr-2',
      ]);
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.queueSelectionBottom),
      );
      await tester.pumpAndSettle();
      expect(container.read(queueControllerProvider).pids, [
        'tr-1',
        'tr-2',
        'tr-3',
        'tr-4',
      ]);

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.queueSelectionRemove),
      );
      await tester.pumpAndSettle();

      // Removing clears the selection: what was picked is gone.
      expect(container.read(queueControllerProvider).pids, ['tr-1', 'tr-2']);
      expect(find.textContaining('selected'), findsNothing);
    });

    testWidgets('shift+click extends a range from the last row touched', (
      tester,
    ) async {
      final container = await _pump(tester);
      container.read(queueControllerProvider.notifier).playNow([
        'tr-1',
        'tr-2',
        'tr-3',
        'tr-4',
        'tr-5',
      ], source: _album);
      await tester.pumpAndSettle();

      Future<void> shiftTap(String queueId) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.queueEntry(queueId)),
          // The row's identifier sits on its content region, which is a
          // wrapper the hit test walks past rather than into. What proves
          // the tap landed is the count below.
          warnIfMissed: false,
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
        await tester.pumpAndSettle();
      }

      // The first shift+click is a way *into* selection: the row becomes
      // the anchor and the range is itself, rather than the gesture
      // doing nothing until something is already picked.
      await shiftTap(idsAt(container, [1]).single);
      expect(find.text('1 selected'), findsOneWidget);
      // Nothing jumped: a plain click is what plays a row.
      expect(container.read(queueControllerProvider).currentIndex, 0);

      // And the second covers everything between the anchor and it,
      // in either direction.
      await shiftTap(idsAt(container, [4]).single);
      expect(find.text('4 selected'), findsOneWidget);

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.queueSelectionRemove),
      );
      await tester.pumpAndSettle();
      expect(container.read(queueControllerProvider).pids, ['tr-1']);
    });

    // Where a dragged block lands, at the edges of the coordinate space
    // the reorderable list hands out. `onReorderItem` has already
    // subtracted one for the row leaving its old slot - it does so
    // whenever the drop is below the drag origin, which a drop past the
    // last row always is - so `to` tops out at one less than the row
    // count, and the anchor it looks up is always inside the list.
    test('a drop target is resolved at both ends of the list', () {
      // Named through the queue's own library: `waxdeck_data` exports a
      // `QueueEntry` too - the persisted row - so the bare name is
      // ambiguous in this file.
      final entries = [
        for (final id in ['q0', 'q1', 'q2', 'q3'])
          queue_state.QueueEntry(queueId: id, pid: 'tr-$id'),
      ];
      const upNext = ['q1', 'q2', 'q3'];
      int target(Set<String> moving, int from, int to) => queueDropTarget(
        entries: entries,
        currentIndex: 0,
        upNextIds: upNext,
        moving: moving,
        from: from,
        to: to,
      );

      // The far end: three up-next rows, so `to` arrives as 2 at most.
      // One past that is what a raw drop index would be, and it never
      // reaches here - the list subtracts it away first.
      expect(target({'q1'}, 0, 2), 3);
      // The top of up-next, which is the entry after the current one.
      expect(target({'q1'}, 0, 0), 1);
      // A block whose every anchor is travelling with it walks off the
      // front of the list and lands at the top, rather than reading past
      // it.
      expect(target({'q1', 'q2', 'q3'}, 0, 2), 1);
      // And one that lands after a row staying put sits behind it.
      expect(target({'q1', 'q3'}, 0, 1), 2);
    });

    testWidgets('a selected block dragged to the end lands there', (
      tester,
    ) async {
      // The same edge through the real widget: a synthetic drag past the
      // last row is what produces the largest index the list ever hands
      // out, and nothing about resolving it may read off the end.
      final container = await _pump(tester);
      container.read(queueControllerProvider.notifier).playNow([
        'tr-1',
        'tr-2',
        'tr-3',
        'tr-4',
      ], source: _album);
      await tester.pumpAndSettle();

      await longPress(tester, idsAt(container, [1]).single);
      await longPress(tester, idsAt(container, [2]).single);

      final handle = find.bySemanticsIdentifier(
        SemanticsIds.queueEntryDrag(idsAt(container, [1]).single),
      );
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveBy(const Offset(0, 400));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // The whole set travelled, contiguous and in its own order.
      expect(container.read(queueControllerProvider).pids, [
        'tr-1',
        'tr-4',
        'tr-2',
        'tr-3',
      ]);
    });

    testWidgets('un-ticking the last row leaves no anchor behind', (
      tester,
    ) async {
      final container = await _pump(tester);
      container.read(queueControllerProvider.notifier).playNow([
        'tr-1',
        'tr-2',
        'tr-3',
        'tr-4',
        'tr-5',
      ], source: _album);
      await tester.pumpAndSettle();

      // In and straight back out through the row, rather than through
      // Clear. Both leave the surface not selecting, so both have to
      // leave the next shift+click with nothing to extend from.
      final second = idsAt(container, [2]).single;
      await longPress(tester, second);
      await longPress(tester, second);
      expect(find.textContaining('selected'), findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.tap(
        find.bySemanticsIdentifier(
          SemanticsIds.queueEntry(idsAt(container, [4]).single),
        ),
        warnIfMissed: false,
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pumpAndSettle();

      // Just the row clicked - not a range running back to a row that
      // was un-ticked out of the previous selection.
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('a swipe is inert while a set is picked', (tester) async {
      final container = await _pump(tester);
      container.read(queueControllerProvider.notifier).playNow([
        'tr-1',
        'tr-2',
        'tr-3',
      ], source: _album);
      await tester.pumpAndSettle();

      await longPress(tester, idsAt(container, [1]).single);
      await tester.drag(
        find.bySemanticsIdentifier(
          SemanticsIds.queueEntry(idsAt(container, [2]).single),
        ),
        const Offset(500, 0),
      );
      await tester.pumpAndSettle();

      // The row-shaped verbs belong to the bar while a set is picked, and
      // a swipe landing on a checkbox is the likeliest accident there is.
      expect(container.read(queueControllerProvider).pids, [
        'tr-1',
        'tr-2',
        'tr-3',
      ]);
    });

    testWidgets('the clear button and Escape both end the selection', (
      tester,
    ) async {
      final container = await _pump(tester);
      container.read(queueControllerProvider.notifier).playNow([
        'tr-1',
        'tr-2',
        'tr-3',
      ], source: _album);
      await tester.pumpAndSettle();

      await longPress(tester, idsAt(container, [1]).single);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.queueSelectionClear),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('selected'), findsNothing);
    });

    testWidgets('Escape ends the selection, and only while there is one', (
      tester,
    ) async {
      // Over a router arranged the way the app arranges it: the key map
      // has to be inside the router and above the navigator, which is
      // what the plain host cannot give.
      tester.view.physicalSize = const Size(500, 900);
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
          child: _keyboardHost(const QueueScreen()),
        ),
      );
      container.read(queueControllerProvider.notifier).playNow([
        'tr-1',
        'tr-2',
        'tr-3',
      ], source: _album);
      await tester.pumpAndSettle();

      // Registered so it prints in the palette and the shortcut sheet
      // for free, which a local key map would not.
      container.listen(commandRegistryProvider, (_, _) {});
      await tester.pumpAndSettle();
      expect(
        container.read(commandRegistryProvider).map((c) => c.id),
        contains('queue-clear-selection'),
      );

      await longPress(tester, idsAt(container, [1]).single);
      expect(find.text('1 selected'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.textContaining('selected'), findsNothing);
      // Still on the queue: Escape ended a mode rather than the screen.
      expect(find.byType(QueueScreen), findsOneWidget);
    });

    testWidgets('the same selection drives the panel', (tester) async {
      // One provider behind both surfaces: the panel and the screen are
      // the same queue, so picking rows on one is picking them on the
      // other.
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
      container.read(queueControllerProvider.notifier).playNow([
        'tr-1',
        'tr-2',
        'tr-3',
      ], source: _album);
      await tester.pumpAndSettle();

      await tester.longPress(
        find.bySemanticsIdentifier(
          SemanticsIds.queueEntry(idsAt(container, [1]).single),
        ),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(container.read(queueSelectionProvider), hasLength(1));
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
