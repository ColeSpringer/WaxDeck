import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_drag.dart';
import 'package:waxdeck/src/queue/queue_panel.dart';
import 'package:waxdeck/src/queue/queue_view.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

ItemSummary _track(String pid, String title) =>
    testItem(pid, title: title, durationMs: 180000);

/// A listing row beside the queue panel, which is the arrangement the
/// gesture exists for: the panel is only there at sidebar width, and a
/// drag needs somewhere to start and somewhere to land.
Widget _rowBesidePanel(QueueDrop drop) => Row(
  children: <Widget>[
    SizedBox(
      width: 400,
      child: QueueDraggable(
        drop: drop,
        child: MediaListRow(
          data: const MediaTileData(title: 'Alpha Song'),
          onTap: () {},
        ),
      ),
    ),
    const Expanded(child: QueuePanel()),
  ],
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeRepository repo,
  QueueDrop drop,
) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      audioEngineProvider.overrideWithValue(FakeEngine()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: routedHost(_rowBesidePanel(drop)),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Picks the row up with a mouse and drops it on the panel.
///
/// The hover is the whole gate, so it is sent as its own event first: a
/// press with no hover before it is what a finger does, and a finger
/// must not drag.
Future<void> _dragRowOntoPanel(
  WidgetTester tester, {
  bool hover = true,
  Offset? onto,
}) async {
  final from = tester.getCenter(find.byType(MediaListRow).first);
  final to = onto ?? tester.getCenter(find.byType(QueuePanel));
  if (hover) {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: from);
    addTearDown(mouse.removePointer);
    await tester.pumpAndSettle();
  }
  final drag = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
  await tester.pump(const Duration(milliseconds: 100));
  // Stepped, so the target sees a move before the release: the slot a
  // drop lands in is resolved while the pointer is over it.
  await drag.moveTo(Offset(to.dx, (from.dy + to.dy) / 2));
  await tester.pump(const Duration(milliseconds: 50));
  await drag.moveTo(to);
  await tester.pump(const Duration(milliseconds: 100));
  await drag.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a row dragged onto the panel is appended to the queue', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      FakeRepository(),
      QueueDrop.item(_track('tr-1', 'Alpha Song')),
    );
    container.read(queueControllerProvider.notifier).playNow(
      ['tr-9'],
      source: const QueueSource(
        kind: QueueSourceKind.album,
        label: 'Gullwing',
        pid: 'al-1',
      ),
    );
    await tester.pumpAndSettle();

    await _dragRowOntoPanel(tester);

    // Appended, not played: a drop must not interrupt what is playing.
    final entries = container.read(queueControllerProvider).entries;
    expect(entries.map((e) => e.pid), <String>['tr-9', 'tr-1']);
    expect(
      container.read(shellMessengerProvider)?.text,
      'Added Alpha Song to the queue',
    );
  });

  // A drop lands where it was released, not at the end: the row under
  // the pointer names the slot, and which half of it decides above or
  // below.
  testWidgets('a drop onto a row lands at that row', (tester) async {
    final container = await _pump(
      tester,
      FakeRepository(),
      QueueDrop.item(_track('tr-new', 'Alpha Song')),
    );
    container.read(queueControllerProvider.notifier).playNow(
      ['tr-1', 'tr-2', 'tr-3'],
      source: const QueueSource(
        kind: QueueSourceKind.album,
        label: 'Gullwing',
        pid: 'al-1',
      ),
    );
    await tester.pumpAndSettle();

    // Onto the top half of the second up-next row, which is the third
    // entry: the drop goes above it.
    final rows = find.byType(QueueRow);
    expect(rows, findsNWidgets(3));
    final target = rows.at(2);
    final box = tester.getRect(target);
    await _dragRowOntoPanel(
      tester,
      onto: Offset(box.center.dx, box.top + box.height * 0.25),
    );

    expect(
      container.read(queueControllerProvider).entries.map((e) => e.pid),
      <String>['tr-1', 'tr-2', 'tr-new', 'tr-3'],
    );
  });

  testWidgets('a drop below a row lands after it', (tester) async {
    final container = await _pump(
      tester,
      FakeRepository(),
      QueueDrop.item(_track('tr-new', 'Alpha Song')),
    );
    container.read(queueControllerProvider.notifier).playNow(
      ['tr-1', 'tr-2', 'tr-3'],
      source: const QueueSource(
        kind: QueueSourceKind.album,
        label: 'Gullwing',
        pid: 'al-1',
      ),
    );
    await tester.pumpAndSettle();

    final box = tester.getRect(find.byType(QueueRow).at(1));
    await _dragRowOntoPanel(
      tester,
      onto: Offset(box.center.dx, box.bottom - box.height * 0.25),
    );

    expect(
      container.read(queueControllerProvider).entries.map((e) => e.pid),
      <String>['tr-1', 'tr-2', 'tr-new', 'tr-3'],
    );
  });

  // The gesture is pointer-only by decision: a touch drag would collide
  // with the long press that starts a queue selection, and touch already
  // reaches the same outcome through the row's own menu.
  testWidgets('a touch drag moves nothing', (tester) async {
    final container = await _pump(
      tester,
      FakeRepository(),
      QueueDrop.item(_track('tr-1', 'Alpha Song')),
    );

    final from = tester.getCenter(find.byType(MediaListRow).first);
    final onto = tester.getCenter(find.byType(QueuePanel));
    final drag = await tester.startGesture(from, kind: PointerDeviceKind.touch);
    await tester.pump(const Duration(milliseconds: 100));
    await drag.moveTo(onto);
    await tester.pump(const Duration(milliseconds: 100));
    await drag.up();
    await tester.pumpAndSettle();

    expect(container.read(queueControllerProvider).isEmpty, isTrue);
  });

  // An index bucket has a name and a count and no items, so the tracks
  // are fetched when the drop lands rather than carried by the drag.
  testWidgets('a bucket resolves its tracks on the drop', (tester) async {
    final repo = FakeRepository()
      ..facetItems['album gullwing'] = <ItemSummary>[
        _track('tr-1', 'Alpha Song'),
        _track('tr-2', 'Bravo Song'),
      ];
    final container = await _pump(
      tester,
      repo,
      QueueDrop.bucket(
        label: 'Gullwing',
        repository: repo,
        facet: 'album',
        facetKey: 'gullwing',
      ),
    );
    // Something already playing, so the drop is an append rather than
    // the start of a session - which is the case the gesture is for.
    container.read(queueControllerProvider.notifier).playNow(
      ['tr-9'],
      source: const QueueSource(
        kind: QueueSourceKind.album,
        label: 'Gullwing',
        pid: 'al-1',
      ),
    );
    await tester.pumpAndSettle();

    await _dragRowOntoPanel(tester);

    // The drill the drop made, rather than a listing it happened to
    // share with the screen behind it.
    expect(repo.facetDrills, <(String, String)>[('album', 'gullwing')]);
    expect(
      container.read(queueControllerProvider).entries.map((e) => e.pid),
      <String>['tr-9', 'tr-1', 'tr-2'],
    );
    expect(
      container.read(shellMessengerProvider)?.text,
      'Added 2 tracks to the queue',
    );
  });

  // The playing row is the likeliest row to aim at, and the one a
  // marker is easiest to forget: with none, the pointer finds nothing
  // and the drop falls back to the end of the queue.
  testWidgets('a drop onto the playing row lands next, not last', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      FakeRepository(),
      QueueDrop.item(_track('tr-new', 'Alpha Song')),
    );
    container.read(queueControllerProvider.notifier).playNow(
      ['tr-1', 'tr-2', 'tr-3'],
      source: const QueueSource(
        kind: QueueSourceKind.album,
        label: 'Gullwing',
        pid: 'al-1',
      ),
    );
    await tester.pumpAndSettle();

    // The current entry's own row, aimed at its top half - which on any
    // other row would mean "above", and here cannot: nothing queues
    // before what is playing.
    final box = tester.getRect(find.byType(QueueRow).first);
    await _dragRowOntoPanel(
      tester,
      onto: Offset(box.center.dx, box.top + box.height * 0.25),
    );

    expect(
      container.read(queueControllerProvider).entries.map((e) => e.pid),
      <String>['tr-1', 'tr-new', 'tr-2', 'tr-3'],
    );
  });

  // The slot is aimed before the fetch and applied after it, so it is
  // resolved against the row it was aimed at rather than against an
  // index that may name a different row by the time the tracks arrive.
  testWidgets('a drop lands beside its row even if the queue moved', (
    tester,
  ) async {
    final gate = Completer<List<ItemSummary>>();
    final container = await _pump(
      tester,
      FakeRepository(),
      QueueDrop(label: 'Gullwing', resolve: () => gate.future),
    );
    final queue = container.read(queueControllerProvider.notifier);
    queue.playNow(
      ['tr-1', 'tr-2', 'tr-3', 'tr-4'],
      source: const QueueSource(
        kind: QueueSourceKind.album,
        label: 'Gullwing',
        pid: 'al-1',
      ),
    );
    await tester.pumpAndSettle();

    // Aimed above the last row, which is index 3 while the drag is
    // happening.
    final box = tester.getRect(find.byType(QueueRow).last);
    await _dragRowOntoPanel(
      tester,
      onto: Offset(box.center.dx, box.top + box.height * 0.25),
    );

    // A row before it goes while the fetch is out, so index 3 now names
    // something else.
    queue.removeAt(1);
    await tester.pumpAndSettle();
    gate.complete(<ItemSummary>[_track('tr-new', 'Alpha Song')]);
    await tester.pumpAndSettle();

    // Still above tr-4, which is what the line was drawn against.
    expect(
      container.read(queueControllerProvider).entries.map((e) => e.pid),
      <String>['tr-1', 'tr-3', 'tr-new', 'tr-4'],
    );
  });

  // A bucket resolves over the network, and the panel it was dropped on
  // can close while that is in flight - the listener toggles it shut, or
  // the window narrows past the breakpoint. The drop was accepted, so
  // the tracks still land: what must not happen is the panel's own
  // disposal taking the enqueue down with it.
  testWidgets('a drop still lands when the panel closes mid-fetch', (
    tester,
  ) async {
    final gate = Completer<List<ItemSummary>>();
    final container = await _pump(
      tester,
      FakeRepository(),
      QueueDrop(label: 'Gullwing', resolve: () => gate.future),
    );
    container.read(queueControllerProvider.notifier).playNow(
      ['tr-9'],
      source: const QueueSource(
        kind: QueueSourceKind.album,
        label: 'Gullwing',
        pid: 'al-1',
      ),
    );
    await tester.pumpAndSettle();

    await _dragRowOntoPanel(tester);

    // Gone, with the fetch still out.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(const SizedBox.shrink()),
      ),
    );
    await tester.pumpAndSettle();

    gate.complete(<ItemSummary>[_track('tr-1', 'Alpha Song')]);
    await tester.pumpAndSettle();

    expect(
      container.read(queueControllerProvider).entries.map((e) => e.pid),
      <String>['tr-9', 'tr-1'],
    );
  });

  // The one drop that reaches the network is the one that can fail on
  // its way in, and it has to say so rather than doing nothing.
  testWidgets('a bucket that will not load says why', (tester) async {
    final repo = FakeRepository()
      ..listError = const WaxDeckApiException(
        code: 'catalog-maintenance',
        message: 'the catalog is being rebuilt',
        statusCode: 503,
      );
    final container = await _pump(
      tester,
      repo,
      QueueDrop.bucket(
        label: 'Gullwing',
        repository: repo,
        facet: 'album',
        facetKey: 'gullwing',
      ),
    );

    await _dragRowOntoPanel(tester);

    expect(container.read(queueControllerProvider).isEmpty, isTrue);
    // The code's sentence: a bucket that could not be read is a failed
    // operation, not a refusal of something typed, so the table answers.
    expect(
      container.read(shellMessengerProvider)?.text,
      'The library is busy with maintenance. Try again shortly.',
    );
  });
}
