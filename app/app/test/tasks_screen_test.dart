import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/tools/tasks_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';
import 'routed_host.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: routedHost(const TasksScreen()),
);

Finder _row(String id) => find.bySemanticsIdentifier(SemanticsIds.taskRow(id));

void main() {
  testWidgets('renders task states, progress, and errors', (tester) async {
    final repo = FakeRepository();
    repo.toolTasksById['tt-1'] = ToolTask(
      id: 'tt-1',
      type: 'book-merge',
      state: 'running',
      itemPid: 'bk-1',
      progressPct: 42,
      createdAt: DateTime.utc(2026, 7, 1),
    );
    repo.toolTasksById['tt-2'] = ToolTask(
      id: 'tt-2',
      type: 'cue-split',
      state: 'failed',
      itemPid: 'tr-1',
      error: 'cue sheet does not match the audio',
      createdAt: DateTime.utc(2026, 7, 1),
      finishedAt: DateTime.utc(2026, 7, 1, 1),
    );
    await tester.pumpWidget(_host(repo));
    // No pumpAndSettle: a running row's progress bar animates forever.
    await tester.pump();
    await tester.pump();

    final runningRow = _row('tt-1');
    expect(runningRow, findsOneWidget);
    expect(
      find.descendant(of: runningRow, matching: find.text('Book merge')),
      findsOneWidget,
    );
    // The wire string is humanized, with the engine's progress beside
    // it, and the bar draws underneath.
    expect(
      find.descendant(of: runningRow, matching: find.text('Running · 42%')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: runningRow,
        matching: find.byType(LinearProgressIndicator),
      ),
      findsOneWidget,
    );
    // A running task has nothing to dismiss.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.taskDismiss('tt-1')),
      findsNothing,
    );

    // The source pid stays on the row: three queued merges are three
    // rows reading "Book merge", and which one failed - and what a
    // dismiss is about to remove - needs the item named.
    expect(
      find.descendant(of: runningRow, matching: find.text('bk-1')),
      findsOneWidget,
    );

    final failedRow = _row('tt-2');
    expect(
      find.descendant(of: failedRow, matching: find.text('Failed')),
      findsOneWidget,
    );
    expect(find.text('failed'), findsNothing, reason: 'no raw wire strings');
    expect(
      find.descendant(
        of: failedRow,
        matching: find.text('cue sheet does not match the audio'),
      ),
      findsOneWidget,
    );
    // A failed row can be dismissed.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.taskDismiss('tt-2')),
      findsOneWidget,
    );
  });

  testWidgets('an acquire task opens the review queue', (tester) async {
    final repo = FakeRepository();
    repo.toolTasksById['tt-acq'] = ToolTask(
      id: 'tt-acq',
      type: 'acquire',
      state: 'done',
      resultPids: const ['rv-1', 'rv-2'],
      createdAt: DateTime.utc(2026, 7, 1),
      finishedAt: DateTime.utc(2026, 7, 1, 1),
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    final row = _row('tt-acq');
    expect(
      find.descendant(of: row, matching: find.text('2 ready for review')),
      findsOneWidget,
    );
    // The review-entry ids are never shown as produced library items.
    expect(find.textContaining('rv-1'), findsNothing);

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('Review queue'), findsOneWidget);
  });

  testWidgets('a single produced item opens per medium', (tester) async {
    const producedPid = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK03';
    final repo = FakeRepository(
      items: [
        testItem(
          producedPid,
          mediaType: MediaType.audiobook,
          title: 'There And Back Again',
        ),
      ],
    )..books[producedPid] = testBook(producedPid);
    repo.toolTasksById['tt-m'] = ToolTask(
      id: 'tt-m',
      type: 'book-merge',
      state: 'done',
      resultPids: const [producedPid],
      createdAt: DateTime.utc(2026, 7, 1),
      finishedAt: DateTime.utc(2026, 7, 1, 1),
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(_row('tt-m'));
    await tester.pumpAndSettle();

    // The merged book's own screen, reached the way a home card
    // reaches it: per medium, not a summary dialog.
    expect(find.text('There And Back Again'), findsWidgets);
    expect(find.byKey(const Key('task-summary-dialog')), findsNothing);
  });

  testWidgets('several produced items offer a sheet first', (tester) async {
    final repo = FakeRepository(
      items: [
        testItem('tr-P1', title: 'Piece One'),
        testItem('tr-P2', title: 'Piece Two'),
      ],
    );
    repo.toolTasksById['tt-s'] = ToolTask(
      id: 'tt-s',
      type: 'cue-split',
      state: 'done',
      resultPids: const ['tr-P1', 'tr-P2'],
      createdAt: DateTime.utc(2026, 7, 1),
      finishedAt: DateTime.utc(2026, 7, 1, 1),
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: _row('tt-s'),
        matching: find.text('2 items produced · tap to open'),
      ),
      findsOneWidget,
    );
    await tester.tap(_row('tt-s'));
    await tester.pumpAndSettle();

    expect(find.text('Piece One'), findsOneWidget);
    expect(find.text('Piece Two'), findsOneWidget);
  });

  testWidgets('a finished import shows its summary and expands to detail', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.toolTasksById['tt-imp'] = ToolTask(
      id: 'tt-imp',
      type: 'import-navidrome',
      state: 'done',
      createdAt: DateTime.utc(2026, 7, 20),
      finishedAt: DateTime.utc(2026, 7, 20, 1),
      summary: const {'matched': 120, 'unmatched': 3, 'listens': 987},
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    final row = _row('tt-imp');
    expect(
      find.descendant(of: row, matching: find.text('Import from Navidrome')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('task-summary-tt-imp')), findsOneWidget);
    expect(find.text('matched 120, unmatched 3, listens 987'), findsOneWidget);

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-summary-dialog')), findsOneWidget);
    expect(find.textContaining('"matched": 120'), findsOneWidget);
  });

  testWidgets('a failed task with a report still opens it', (tester) async {
    // An import that matched half the library before dying stored a
    // partial report, and "Failed" plus the error line must not bury
    // it: the report is where "which ones landed first" lives.
    final repo = FakeRepository();
    repo.toolTasksById['tt-f'] = ToolTask(
      id: 'tt-f',
      type: 'import-navidrome',
      state: 'failed',
      error: 'the server went away mid-import',
      summary: const {'matched': 41, 'unmatched': 3},
      createdAt: DateTime.utc(2026, 7, 1),
      finishedAt: DateTime.utc(2026, 7, 1, 1),
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    final row = _row('tt-f');
    expect(
      find.descendant(of: row, matching: find.text('Tap for the report')),
      findsOneWidget,
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-summary-dialog')), findsOneWidget);
    expect(find.textContaining('"matched": 41'), findsOneWidget);
  });

  testWidgets('a dismiss of a row already gone still clears it', (
    tester,
  ) async {
    // Another device swept the row first: the 404 the delete answers is
    // the outcome this tap wanted, so the row goes and nothing toasts.
    final repo = FakeRepository();
    repo.toolTasksById['tt-a'] = ToolTask(
      id: 'tt-a',
      type: 'book-merge',
      state: 'done',
      createdAt: DateTime.utc(2026, 7, 1),
      finishedAt: DateTime.utc(2026, 7, 1, 1),
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();
    expect(_row('tt-a'), findsOneWidget);

    repo.toolTasksById.remove('tt-a');
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.taskDismiss('tt-a')),
    );
    await tester.pumpAndSettle();

    expect(_row('tt-a'), findsNothing);
    expect(find.text('no such task'), findsNothing);
  });

  testWidgets('a dismiss takes its row and nothing else', (tester) async {
    final repo = FakeRepository();
    repo.toolTasksById['tt-a'] = ToolTask(
      id: 'tt-a',
      type: 'book-merge',
      state: 'done',
      createdAt: DateTime.utc(2026, 7, 1),
      finishedAt: DateTime.utc(2026, 7, 1, 1),
    );
    repo.toolTasksById['tt-b'] = ToolTask(
      id: 'tt-b',
      type: 'book-split',
      state: 'failed',
      error: 'gave up',
      createdAt: DateTime.utc(2026, 7, 2),
      finishedAt: DateTime.utc(2026, 7, 2, 1),
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.taskDismiss('tt-a')),
    );
    await tester.pumpAndSettle();

    expect(repo.deleteToolTaskCalls, ['tt-a']);
    expect(_row('tt-a'), findsNothing);
    expect(_row('tt-b'), findsOneWidget);
  });

  testWidgets('clear finished sweeps and says how many went', (tester) async {
    final repo = FakeRepository();
    repo.toolTasksById['tt-a'] = ToolTask(
      id: 'tt-a',
      type: 'book-merge',
      state: 'done',
      createdAt: DateTime.utc(2026, 7, 1),
      finishedAt: DateTime.utc(2026, 7, 1, 1),
    );
    repo.toolTasksById['tt-b'] = ToolTask(
      id: 'tt-b',
      type: 'cue-split',
      state: 'failed',
      error: 'gave up',
      createdAt: DateTime.utc(2026, 7, 2),
      finishedAt: DateTime.utc(2026, 7, 2, 1),
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.tasksClearFinished),
    );
    await tester.pumpAndSettle();

    expect(repo.clearFinishedToolTaskCalls, 1);
    expect(find.text('Cleared 2 tasks'), findsOneWidget);
    expect(find.text('No tool tasks'), findsOneWidget);
  });

  testWidgets('nothing finished offers no sweep', (tester) async {
    final repo = FakeRepository();
    repo.toolTasksById['tt-run'] = ToolTask(
      id: 'tt-run',
      type: 'book-merge',
      state: 'running',
      createdAt: DateTime.utc(2026, 7, 1),
    );
    await tester.pumpWidget(_host(repo));
    await tester.pump();
    await tester.pump();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.tasksClearFinished),
      findsNothing,
    );
  });

  testWidgets('an empty task list shows the empty state', (tester) async {
    await tester.pumpWidget(_host(FakeRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No tool tasks'), findsOneWidget);
  });

  testWidgets('book merge and split stay reachable through the repository', (
    tester,
  ) async {
    // The merge and split entry points belong on the media detail
    // screens, which are outside this feature's wiring surface. The
    // repository flow is pinned here so the screen picks queued tasks
    // up.
    final repo = FakeRepository();
    await repo.mergeBook('bk-1', titles: ['One', 'Two']);
    await repo.splitBook('bk-2');
    await tester.pumpWidget(_host(repo));
    // No pumpAndSettle: queued tasks render an indeterminate progress
    // bar, which animates forever.
    await tester.pump();
    await tester.pump();

    expect(repo.mergeBookCalls.single.pid, 'bk-1');
    expect(repo.splitBookCalls.single.pid, 'bk-2');
    expect(_row('tt-FAKE0'), findsOneWidget);
    expect(_row('tt-FAKE1'), findsOneWidget);
  });
}
