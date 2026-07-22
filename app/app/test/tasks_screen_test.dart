import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/tools/tasks_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: const MaterialApp(home: TasksScreen()),
);

void main() {
  testWidgets('renders task states, progress, errors, and results', (
    tester,
  ) async {
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
    );
    repo.toolTasksById['tt-3'] = ToolTask(
      id: 'tt-3',
      type: 'book-split',
      state: 'done',
      itemPid: 'bk-2',
      resultPids: const ['bk-3', 'bk-4'],
      createdAt: DateTime.utc(2026, 7, 1),
      finishedAt: DateTime.utc(2026, 7, 1, 1),
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    final runningRow = find.byKey(const ValueKey('task-row-tt-1'));
    expect(runningRow, findsOneWidget);
    expect(
      find.descendant(of: runningRow, matching: find.text('Book merge: bk-1')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: runningRow,
        matching: find.byType(LinearProgressIndicator),
      ),
      findsOneWidget,
    );

    final failedRow = find.byKey(const ValueKey('task-row-tt-2'));
    expect(
      find.descendant(of: failedRow, matching: find.text('failed')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: failedRow,
        matching: find.text('cue sheet does not match the audio'),
      ),
      findsOneWidget,
    );

    final doneRow = find.byKey(const ValueKey('task-row-tt-3'));
    expect(
      find.descendant(of: doneRow, matching: find.text('Produced: bk-3, bk-4')),
      findsOneWidget,
    );
  });

  testWidgets('an acquire task labels its results as ready for review', (
    tester,
  ) async {
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

    final row = find.byKey(const ValueKey('task-row-tt-acq'));
    expect(
      find.descendant(of: row, matching: find.text('2 ready for review')),
      findsOneWidget,
    );
    // The review-entry ids are never shown as produced library items.
    expect(find.textContaining('rv-1'), findsNothing);
    expect(find.textContaining('Produced'), findsNothing);
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

    final row = find.byKey(const ValueKey('task-row-tt-imp'));
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

  testWidgets('an empty task list shows the empty state', (tester) async {
    await tester.pumpWidget(_host(FakeRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No tool tasks yet'), findsOneWidget);
  });

  testWidgets('book merge and split stay reachable through the repository', (
    tester,
  ) async {
    // The tasks screen is read-only by design: the merge and split
    // entry points belong on the media detail screens, which are
    // outside this feature's wiring surface. The repository flow is
    // pinned here so the screen picks queued tasks up.
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
    expect(find.byKey(const ValueKey('task-row-tt-FAKE0')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-row-tt-FAKE1')), findsOneWidget);
  });
}
