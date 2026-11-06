import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:waxdeck/src/admin/admin_providers.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/async_sliver_face.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/tools/tasks_screen.dart';
import 'package:waxdeck/src/tools/tool_tasks_provider.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';
import 'row_nodes.dart';
import 'wax_finders.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
  ],
  child: routedHost(const TasksScreen()),
);

Finder _row(String id) => find.bySemanticsIdentifier(SemanticsIds.taskRow(id));

/// The glyph a row draws when a tap on it opens something.
Finder _forward(Finder row) => find.descendant(
  of: row,
  matching: find.byWidgetPredicate(
    (w) => w is WaxIcon && w.glyph == WaxIcons.forward,
  ),
);

/// What a screen reader hears on the row's tappable node, which is the
/// node the forward glyph lands in.
String _heard(WidgetTester tester, Finder row) {
  final node = tester.getSemantics(_forward(row));
  expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
  return node.label;
}

/// When a waiting task in these tests tries next: ahead of the clock, so
/// the row says when.
final _retryAt = DateTime.now().toUtc().add(const Duration(hours: 2));

Finder _job(String pid) => find.bySemanticsIdentifier(SemanticsIds.jobRow(pid));

/// A finished task of [type].
ToolTask _doneTask(String id, String type) => ToolTask(
  id: id,
  type: type,
  state: 'done',
  createdAt: DateTime.utc(2026, 7, 1),
  finishedAt: DateTime.utc(2026, 7, 1, 1),
);

/// Pages the tasks fifty at a time, the second page holding one.
class _PagedTasks extends FakeRepository {
  final cursors = <String?>[];

  @override
  Future<ToolTaskPage> listToolTasks({String? cursor, int? limit}) async {
    cursors.add(cursor);
    return cursor == null
        ? ToolTaskPage(
            tasks: [for (var i = 0; i < 50; i++) _doneTask('tt-$i', 'acquire')],
            nextCursor: 'c2',
          )
        : ToolTaskPage(tasks: [_doneTask('tt-50', 'acquire')]);
  }
}

/// Holds every tool task sweep until [release] completes.
class _HeldSweep extends FakeRepository {
  _HeldSweep({super.sessionState});

  final release = Completer<void>();

  @override
  Future<ToolTasksCleared> clearFinishedToolTasks({bool all = false}) async {
    clearFinishedToolTaskCalls++;
    await release.future;
    clearFinishedToolTaskCalls--;
    return super.clearFinishedToolTasks(all: all);
  }
}

const _admin = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  username: 'admin',
  roles: ['admin'],
);

void main() {
  testWidgets('a refresh redraws the tasks it already has', (tester) async {
    // Through the shared face, which decides from the value rather than
    // from the state's runtime type: a reload carries the rows it had.
    final repo = FakeRepository();
    repo.toolTasksById['tt-1'] = ToolTask(
      id: 'tt-1',
      type: 'book-merge',
      state: 'done',
      itemPid: 'bk-1',
      createdAt: DateTime.utc(2026, 7, 1),
      finishedAt: DateTime.utc(2026, 7, 1, 1),
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();
    expect(find.byType(AsyncSliverFace<ToolTasksState>), findsOneWidget);
    expect(_row('tt-1'), findsOneWidget);

    final gate = Completer<void>();
    repo.listToolTasksGate = gate;
    ProviderScope.containerOf(
      tester.element(find.byType(WaxScaffold).first),
    ).invalidate(toolTasksProvider);
    await tester.pump();
    await tester.pump();

    expect(_row('tt-1'), findsOneWidget);
    expect(
      find.byType(SkeletonShapes),
      findsNothing,
      reason: 'a reload must not blank the rows it already holds',
    );
    gate.complete();
    repo.listToolTasksGate = null;
    await tester.pumpAndSettle();
  });

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
      find.descendant(of: runningRow, matching: find.byType(WaxProgressBar)),
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

  testWidgets('a book task waiting on a passing failure says so, why, when '
      'it tries next, and that the book is in the trash', (tester) async {
    final repo = FakeRepository();
    repo.toolTasksById['tt-w'] = ToolTask(
      id: 'tt-w',
      type: 'book-merge',
      state: 'running',
      itemPid: 'bk-1',
      itemTitle: 'The Merge Book',
      progressPct: 100,
      error:
          'the library folder refused the write: permission denied (the '
          'task tries again on its own)',
      waitReason: 'storage-unwritable',
      retryAt: _retryAt,
      bookInTrash: true,
      createdAt: DateTime.utc(2026, 7, 1),
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    final row = _row('tt-w');
    Finder inRow(String text) =>
        find.descendant(of: row, matching: find.text(text));
    expect(inRow('Waiting'), findsOneWidget);
    expect(find.textContaining('Running'), findsNothing);
    expect(find.textContaining('100%'), findsNothing);
    expect(
      find.descendant(of: row, matching: find.byType(WaxProgressBar)),
      findsNothing,
      reason: 'a finished bar over a task that waits reads as done',
    );
    expect(
      inRow(
        'A folder it writes to refuses the server. Fix its ownership and '
        'permissions.',
      ),
      findsOneWidget,
    );
    // The time of the next try, not a countdown, which would be wrong as
    // soon as the row stood still.
    expect(
      inRow('Next try at ${DateFormat.jm('en').format(_retryAt.toLocal())}'),
      findsOneWidget,
    );
    expect(
      inRow("The book's files are in the trash until this finishes."),
      findsOneWidget,
    );
    // The server's words stay, as detail rather than as a failure.
    final detail = inRow(
      'the library folder refused the write: permission denied (the task '
      'tries again on its own)',
    );
    expect(detail, findsOneWidget);
    final colors = WaxColors.of(tester.element(row));
    for (final text in tester.widgetList<Text>(
      find.descendant(of: row, matching: find.byType(Text)),
    )) {
      expect(text.style?.color, isNot(colors.error), reason: text.data);
    }
    expect(
      find.bySemanticsIdentifier(SemanticsIds.taskDismiss('tt-w')),
      findsNothing,
    );
  });

  testWidgets('a next try that has come says it is trying now, and the row '
      'says so when the time comes', (tester) async {
    final repo = FakeRepository();
    repo.toolTasksById['tt-past'] = ToolTask(
      id: 'tt-past',
      type: 'book-merge',
      state: 'running',
      waitReason: 'catalog-busy',
      retryAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      createdAt: DateTime.utc(2026, 7, 1, 2),
    );
    final soon = DateTime.now().toUtc().add(const Duration(minutes: 1));
    repo.toolTasksById['tt-soon'] = ToolTask(
      id: 'tt-soon',
      type: 'book-split',
      state: 'running',
      waitReason: 'catalog-busy',
      retryAt: soon,
      createdAt: DateTime.utc(2026, 7, 1, 1),
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    Finder inRow(String id, String text) =>
        find.descendant(of: _row(id), matching: find.text(text));
    expect(inRow('tt-past', 'Trying again now'), findsOneWidget);
    expect(
      inRow(
        'tt-soon',
        'Next try at ${DateFormat.jm('en').format(soon.toLocal())}',
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(minutes: 1, seconds: 1));
    expect(inRow('tt-soon', 'Trying again now'), findsOneWidget);
  });

  testWidgets('every wait reason has its sentence, and one this app does not '
      'know reads as passing', (tester) async {
    final repo = FakeRepository();
    const reasons = {
      'catalog-busy': 'Another job holds the catalog.',
      'catalog-maintenance': 'The catalog is under maintenance.',
      'read-only':
          'A library it works in is read-only. Turn that off for it or the '
          'server.',
      'storage-unwritable':
          'A folder it writes to refuses the server. Fix its ownership and '
          'permissions.',
      'engine-unavailable': 'The audio engine is not available.',
      'part-missing':
          'A book file is missing; if it stays gone, this undoes its moves '
          'and stops.',
      'put-back-blocked':
          'A file cannot leave the trash: free its place or fix its folder.',
      'stopped': 'Cut short by a server stop or a time limit.',
      'other': 'Something passing got in the way.',
      'a-reason-from-later': 'Something passing got in the way.',
    };
    var i = 0;
    for (final reason in reasons.keys) {
      repo.toolTasksById['tt-$i'] = ToolTask(
        id: 'tt-$i',
        type: 'cue-split',
        state: 'running',
        waitReason: reason,
        retryAt: DateTime.now().add(const Duration(minutes: 5)),
        createdAt: DateTime.utc(2026, 7, 1, 0, i),
      );
      i++;
    }
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    i = 0;
    for (final sentence in reasons.values) {
      final row = _row('tt-$i');
      await tester.scrollUntilVisible(row, 200);
      expect(
        find.descendant(of: row, matching: find.text(sentence)),
        findsOneWidget,
        reason: reasons.keys.elementAt(i),
      );
      // A CUE split has no book to put in the trash.
      expect(
        find.descendant(
          of: row,
          matching: find.textContaining('in the trash until'),
        ),
        findsNothing,
      );
      i++;
    }
  });

  testWidgets('a waiting task reads in Spanish too', (tester) async {
    final repo = FakeRepository();
    repo.toolTasksById['tt-w'] = ToolTask(
      id: 'tt-w',
      type: 'book-split',
      state: 'running',
      waitReason: 'read-only',
      retryAt: _retryAt,
      bookInTrash: true,
      createdAt: DateTime.utc(2026, 7, 1),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        ],
        child: routedHost(const TasksScreen(), locale: const Locale('es')),
      ),
    );
    await tester.pumpAndSettle();

    final row = _row('tt-w');
    Finder inRow(String text) =>
        find.descendant(of: row, matching: find.text(text));
    expect(inRow('En espera'), findsOneWidget);
    expect(
      inRow(
        'Una biblioteca en la que trabaja es de solo lectura. Desactiva la '
        'solo lectura en ella o en el servidor.',
      ),
      findsOneWidget,
    );
    expect(
      inRow(
        'Próximo intento: ${DateFormat.jm('es').format(_retryAt.toLocal())}',
      ),
      findsOneWidget,
    );
    expect(
      inRow(
        'Los archivos del libro están en la papelera hasta que esto '
        'termine.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a book task at work in its trash step says where the book '
      'is', (tester) async {
    final repo = FakeRepository();
    repo.toolTasksById['tt-r'] = ToolTask(
      id: 'tt-r',
      type: 'book-split',
      state: 'running',
      progressPct: 60,
      bookInTrash: true,
      createdAt: DateTime.utc(2026, 7, 1),
    );
    await tester.pumpWidget(_host(repo));
    await tester.pump();
    await tester.pump();

    final row = _row('tt-r');
    expect(
      find.descendant(
        of: row,
        matching: find.text(AppLocalizationsEn().toolsStateRunningPct(60)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row,
        matching: find.text(
          "The book's files are in the trash until this finishes.",
        ),
      ),
      findsOneWidget,
    );
  });

  ToolTask parkedMerge() => ToolTask(
    id: 'tt-p',
    type: 'book-merge',
    state: 'parked',
    itemPid: 'bk-1',
    progressPct: 100,
    error:
        'stopped: its last 3 runs ended with the server and never came '
        "back; the trash holds 2 of the book's files under book-merge: "
        'Ada/Book/part 1.m4b, Ada/Book/part 2.m4b',
    bookInTrash: true,
    createdAt: DateTime.utc(2026, 7, 1),
    finishedAt: DateTime.utc(2026, 7, 1, 1),
  );

  testWidgets('a parked task asks for attention, says where its files are, '
      'and is dismissed like a failed one', (tester) async {
    final repo = FakeRepository();
    repo.toolTasksById['tt-p'] = parkedMerge();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    final row = _row('tt-p');
    final status = find.descendant(
      of: row,
      matching: find.text('Needs attention'),
    );
    expect(status, findsOneWidget);
    expect(find.text('parked'), findsNothing, reason: 'no raw wire strings');
    expect(
      tester.widget<Text>(status).style?.color,
      WaxColors.of(tester.element(row)).error,
    );
    expect(
      find.descendant(
        of: row,
        matching: find.text(
          'stopped: its last 3 runs ended with the server and never came '
          "back; the trash holds 2 of the book's files under book-merge: "
          'Ada/Book/part 1.m4b, Ada/Book/part 2.m4b',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.byType(WaxProgressBar)),
      findsNothing,
    );
    // Finished, so it says nothing of a trash it is no longer working
    // through: the line above says where each file is.
    expect(find.textContaining('until this finishes'), findsNothing);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.taskDismiss('tt-p')),
    );
    await tester.pumpAndSettle();

    expect(repo.deleteToolTaskCalls, ['tt-p']);
    expect(row, findsNothing);
  });

  testWidgets('a long account folds to its first lines, opens whole, and '
      'can be selected', (tester) async {
    final repo = FakeRepository();
    final names = [for (var i = 1; i <= 60; i++) 'Ada/Book/part $i.m4b'];
    final account =
        'stopped: its last 3 runs ended with the server and never came '
        "back; the trash holds 60 of the book's files under book-merge: "
        '${names.join(', ')}';
    repo.toolTasksById['tt-p'] = ToolTask(
      id: 'tt-p',
      type: 'book-merge',
      state: 'parked',
      error: account,
      createdAt: DateTime.utc(2026, 7, 1),
      finishedAt: DateTime.utc(2026, 7, 1, 1),
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    final row = _row('tt-p');
    final text = find.descendant(of: row, matching: find.text(account));
    expect(text, findsOneWidget);
    // Selectable, so the paths can be copied out to put things right.
    expect(
      find.ancestor(of: text, matching: find.byType(WaxProse)),
      findsOneWidget,
    );
    final folded = tester.getSize(row).height;
    final whole = tester.getSize(text).height;
    expect(folded, lessThan(whole / 2), reason: 'folded to its first lines');

    await tester.tap(find.descendant(of: row, matching: find.text('Show all')));
    await tester.pumpAndSettle();
    expect(tester.getSize(row).height, greaterThan(whole));
    await tester.tap(
      find.descendant(of: row, matching: find.text('Show less')),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(row).height, folded);
  });

  testWidgets('clear finished sweeps a parked task too', (tester) async {
    final repo = FakeRepository();
    repo.toolTasksById['tt-p'] = parkedMerge();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.tasksClearFinished),
    );
    await tester.pumpAndSettle();

    expect(repo.clearFinishedToolTaskCalls, 1);
    expect(shellMessageText(raisedMessage(tester)), 'Cleared 1 task');
    expect(_row('tt-p'), findsNothing);
  });

  testWidgets('a book task row names the book it works on', (tester) async {
    final repo = FakeRepository();
    repo.toolTasksById['tt-1'] = ToolTask(
      id: 'tt-1',
      type: 'book-merge',
      state: 'done',
      itemPid: 'bk-1',
      itemTitle: 'The Fixture Book',
      createdAt: DateTime.utc(2026, 7, 1),
      finishedAt: DateTime.utc(2026, 7, 1, 1),
    );
    repo.toolTasksById['tt-2'] = ToolTask(
      id: 'tt-2',
      type: 'book-split',
      state: 'done',
      itemPid: 'bk-2',
      createdAt: DateTime.utc(2026, 7, 1),
      finishedAt: DateTime.utc(2026, 7, 1, 1),
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.text('Book merge: The Fixture Book'), findsOneWidget);
    // A task queued with no title keeps its plain label.
    expect(find.text('Book split'), findsOneWidget);
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
    expect(_heard(tester, row), endsWith('Open the review queue'));
    // The review-entry ids are never shown as produced library items.
    expect(find.textContaining('rv-1'), findsNothing);

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('Review queue'), findsOneWidget);
  });

  testWidgets('a finished download with nothing to count draws no "open" '
      'line, and its glyph names the way', (tester) async {
    final repo = FakeRepository();
    repo.toolTasksById['tt-dl'] = ToolTask(
      id: 'tt-dl',
      type: 'acquire',
      state: 'done',
      createdAt: DateTime.utc(2026, 7, 1),
      finishedAt: DateTime.utc(2026, 7, 1, 1),
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    final row = _row('tt-dl');
    expect(find.text('Open the review queue'), findsNothing);
    expect(_forward(row), findsOneWidget);
    expect(_heard(tester, row), endsWith('Open the review queue'));
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
    expect(
      find.descendant(of: _row('tt-m'), matching: find.text('1 item')),
      findsOneWidget,
    );
    expect(_heard(tester, _row('tt-m')), endsWith('Open the result'));

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
      find.descendant(of: _row('tt-s'), matching: find.text('2 items')),
      findsOneWidget,
    );
    expect(_forward(_row('tt-s')), findsOneWidget);
    expect(_heard(tester, _row('tt-s')), endsWith('Open the results'));
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
    expect(_heard(tester, row), endsWith('Open the report'));

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
    expect(_forward(row), findsOneWidget);
    // A screen reader is told the row opens the report, as the glyph
    // tells a sighted reader.
    expect(_heard(tester, row), endsWith('Open the report'));
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
    // Nothing to open here, so no forward glyph beside the dismiss.
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
    expect(_forward(_row('tt-a')), findsNothing);

    repo.toolTasksById.remove('tt-a');
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.taskDismiss('tt-a')),
    );
    await tester.pumpAndSettle();

    expect(_row('tt-a'), findsNothing);
    expect(raisedMessage(tester), isNull);
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
    expect(repo.clearFinishedToolTaskScopes, [
      false,
    ], reason: 'a member has one sweep, and it is their own');
    expect(shellMessageText(raisedMessage(tester)), 'Cleared 2 tasks');
    expect(find.text('No tool tasks'), findsOneWidget);
    expect(find.textContaining('report their progress'), findsNothing);
  });

  group('an administrator clearing finished tasks', () {
    FakeRepository adminRepo() {
      final repo = FakeRepository(
        sessionState: const SessionState(authenticated: true, user: _admin),
      );
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
      return repo;
    }

    Future<void> tapId(WidgetTester tester, String id) async {
      await tester.tap(find.bySemanticsIdentifier(id));
      await tester.pumpAndSettle();
    }

    testWidgets('chooses between their own tasks and everyone\'s', (
      tester,
    ) async {
      final repo = adminRepo();
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      // The control opens a menu rather than sweeping.
      await tapId(tester, SemanticsIds.tasksClearFinished);
      expect(repo.clearFinishedToolTaskCalls, 0);
      expect(find.text('Clear my finished'), findsOneWidget);
      expect(find.text('Clear everyone\'s finished'), findsOneWidget);

      await tapId(tester, SemanticsIds.tasksClearFinishedMine);

      expect(repo.clearFinishedToolTaskScopes, [false]);
      expect(shellMessageText(raisedMessage(tester)), 'Cleared 2 tasks');
    });

    testWidgets('clearing everyone\'s asks first', (tester) async {
      final repo = adminRepo();
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      await tapId(tester, SemanticsIds.tasksClearFinished);
      await tapId(tester, SemanticsIds.tasksClearFinishedAll);

      expect(repo.clearFinishedToolTaskCalls, 0, reason: 'nothing before yes');
      expect(repo.clearFinishedJobCalls, 0, reason: 'nor for the jobs');
      expect(
        find.text('Clear every member\'s finished tasks?'),
        findsOneWidget,
      );
      expect(find.textContaining('unread reports included'), findsOneWidget);

      // Declining leaves every row where it was.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.clearFinishedToolTaskCalls, 0);
      expect(repo.clearFinishedJobCalls, 0);
      expect(_row('tt-a'), findsOneWidget);

      await tapId(tester, SemanticsIds.tasksClearFinished);
      await tapId(tester, SemanticsIds.tasksClearFinishedAll);
      await tapId(tester, SemanticsIds.tasksClearFinishedConfirm);

      expect(repo.clearFinishedToolTaskScopes, [true]);
      expect(shellMessageText(raisedMessage(tester)), 'Cleared 2 tasks');
      expect(find.text('No tool tasks'), findsOneWidget);
    });
  });

  testWidgets('clear finished says how many it kept, and why', (tester) async {
    final repo = FakeRepository()..clearFinishedKept = 2;
    repo.toolTasksById['tt-a'] = ToolTask(
      id: 'tt-a',
      type: 'book-merge',
      state: 'done',
      createdAt: DateTime.utc(2026, 7, 1),
      finishedAt: DateTime.utc(2026, 7, 1, 1),
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.tasksClearFinished),
    );
    await tester.pumpAndSettle();

    expect(
      shellMessageText(raisedMessage(tester)),
      'Cleared 1 task\n2 tasks kept: their files could not move',
    );
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

  group('clearing the library jobs with the tasks', () {
    FakeRepository adminRepo() =>
        FakeRepository(
            sessionState: const SessionState(authenticated: true, user: _admin),
          )
          ..jobs = [
            Job(
              pid: 'jb-scan',
              kind: 'scan',
              state: 'done',
              startedAt: DateTime.utc(2026, 9, 29, 10),
              finishedAt: DateTime.utc(2026, 9, 29, 10, 5),
            ),
          ];

    Future<void> tapId(WidgetTester tester, String id) async {
      await tester.tap(find.bySemanticsIdentifier(id));
      await tester.pumpAndSettle();
    }

    testWidgets('a finished job alone offers the sweep, and either choice '
        'clears it', (tester) async {
      for (final id in [
        SemanticsIds.tasksClearFinishedMine,
        SemanticsIds.tasksClearFinishedAll,
      ]) {
        final repo = adminRepo();
        await tester.pumpWidget(_host(repo));
        await tester.pumpAndSettle();
        expect(_job('jb-scan'), findsOneWidget);

        await tapId(tester, SemanticsIds.tasksClearFinished);
        expect(repo.clearFinishedJobCalls, 0, reason: 'a menu, not a sweep');
        if (id == SemanticsIds.tasksClearFinishedAll) {
          await tapId(tester, id);
          await tapId(tester, SemanticsIds.tasksClearFinishedConfirm);
        } else {
          await tapId(tester, id);
        }

        expect(repo.clearFinishedJobCalls, 1, reason: id);
        expect(_job('jb-scan'), findsNothing, reason: id);
        expect(
          shellMessageText(raisedMessage(tester)),
          contains('Cleared 1 library job'),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('the sweep counts only the jobs the list shows', (
      tester,
    ) async {
      // A finished run of one item is off the list, so it is neither
      // swept nor counted: the server clears by the caller's own list.
      final repo = adminRepo()
        ..jobs.add(
          Job(
            pid: 'jb-one',
            kind: 'enrich',
            state: 'done',
            target: const JobTarget(type: 'item', pid: 'tr-1'),
            startedAt: DateTime.utc(2026, 9, 29, 11),
            finishedAt: DateTime.utc(2026, 9, 29, 11, 1),
          ),
        );
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      await tapId(tester, SemanticsIds.tasksClearFinished);
      await tapId(tester, SemanticsIds.tasksClearFinishedMine);

      expect(
        shellMessageText(raisedMessage(tester)),
        contains('Cleared 1 library job'),
      );
      // Cleared from the list, not from the server: each still answers.
      expect((await repo.getJob('jb-scan')).state, 'done');
      expect((await repo.getJob('jb-one')).state, 'done');
    });

    testWidgets('a sweep of both lists says what each cleared', (tester) async {
      final repo = adminRepo();
      repo.toolTasksById['tt-a'] = ToolTask(
        id: 'tt-a',
        type: 'book-merge',
        state: 'done',
        createdAt: DateTime.utc(2026, 7, 1),
        finishedAt: DateTime.utc(2026, 7, 1, 1),
      );
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      await tapId(tester, SemanticsIds.tasksClearFinished);
      await tapId(tester, SemanticsIds.tasksClearFinishedMine);

      expect(
        shellMessageText(raisedMessage(tester)),
        'Cleared 1 task\nCleared 1 library job',
      );
      expect(_row('tt-a'), findsNothing);
      expect(_job('jb-scan'), findsNothing);
    });

    testWidgets('the toast reads in Spanish', (tester) async {
      final repo = adminRepo();
      repo.toolTasksById['tt-a'] = ToolTask(
        id: 'tt-a',
        type: 'book-merge',
        state: 'done',
        createdAt: DateTime.utc(2026, 7, 1),
        finishedAt: DateTime.utc(2026, 7, 1, 1),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            credentialStoreProvider.overrideWithValue(
              InMemoryCredentialStore(),
            ),
          ],
          child: routedHost(const TasksScreen(), locale: const Locale('es')),
        ),
      );
      await tester.pumpAndSettle();

      await tapId(tester, SemanticsIds.tasksClearFinished);
      await tapId(tester, SemanticsIds.tasksClearFinishedMine);

      expect(
        shellMessageText(raisedMessage(tester)),
        'Se ha borrado 1 tarea\n'
        'Se ha borrado 1 trabajo de la biblioteca',
      );
    });

    testWidgets('a running job alone offers no sweep', (tester) async {
      final repo = adminRepo()
        ..jobs = [
          Job(
            pid: 'jb-run',
            kind: 'scan',
            state: 'running',
            progress: 0.4,
            startedAt: DateTime.utc(2026, 9, 29, 10),
          ),
        ];
      await tester.pumpWidget(_host(repo));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }

      expect(_job('jb-run'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.tasksClearFinished),
        findsNothing,
      );
    });

    testWidgets('a member never calls it', (tester) async {
      final repo =
          FakeRepository(
              sessionState: const SessionState(
                authenticated: true,
                user: WaxDeckUser(id: 'us-2', username: 'sam'),
              ),
            )
            ..jobs = adminRepo().jobs
            ..toolTasksById['tt-a'] = ToolTask(
              id: 'tt-a',
              type: 'book-merge',
              state: 'done',
              createdAt: DateTime.utc(2026, 7, 1),
              finishedAt: DateTime.utc(2026, 7, 1, 1),
            );
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      expect(_job('jb-scan'), findsNothing);
      await tapId(tester, SemanticsIds.tasksClearFinished);

      expect(repo.clearFinishedToolTaskCalls, 1);
      expect(repo.clearFinishedJobCalls, 0);
    });

    testWidgets('a refused job clear is told beside what did clear', (
      tester,
    ) async {
      final repo = adminRepo()
        ..clearFinishedJobsError = const WaxDeckApiException(
          code: 'catalog-maintenance',
          message: 'busy',
          statusCode: 503,
        );
      repo.toolTasksById['tt-a'] = ToolTask(
        id: 'tt-a',
        type: 'book-merge',
        state: 'done',
        createdAt: DateTime.utc(2026, 7, 1),
        finishedAt: DateTime.utc(2026, 7, 1, 1),
      );
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      await tapId(tester, SemanticsIds.tasksClearFinished);
      await tapId(tester, SemanticsIds.tasksClearFinishedMine);

      expect(
        shellMessageText(raisedMessage(tester)),
        'Cleared 1 task\n'
        'The library is busy with maintenance. Try again shortly.',
      );
      expect(_row('tt-a'), findsNothing);
      expect(_job('jb-scan'), findsOneWidget, reason: 'nothing was hidden');
    });

    testWidgets('a sweep that kept some says so after the jobs line', (
      tester,
    ) async {
      final repo = adminRepo()..clearFinishedKept = 2;
      repo.toolTasksById['tt-a'] = ToolTask(
        id: 'tt-a',
        type: 'book-merge',
        state: 'done',
        createdAt: DateTime.utc(2026, 7, 1),
        finishedAt: DateTime.utc(2026, 7, 1, 1),
      );
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      await tapId(tester, SemanticsIds.tasksClearFinished);
      await tapId(tester, SemanticsIds.tasksClearFinishedMine);

      expect(
        shellMessageText(raisedMessage(tester)),
        'Cleared 1 task\nCleared 1 library job\n'
        '2 tasks kept: their files could not move',
      );
    });
  });

  group('kind glyphs', () {
    testWidgets("a finished scan row's glyph is not the refresh action", (
      tester,
    ) async {
      final repo = FakeRepository(
        sessionState: const SessionState(authenticated: true, user: _admin),
      )..jobs = [Job(pid: 'jb-scan', kind: 'scan', state: 'done')];
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      final glyph = tester
          .widget<WaxIcon>(
            find
                .descendant(of: _job('jb-scan'), matching: find.byType(WaxIcon))
                .first,
          )
          .glyph;
      expect(glyph, WaxIcons.library);
      expect(glyph, isNot(WaxIcons.refresh));
    });

    testWidgets("a playlist sync row's glyph is not the refresh action", (
      tester,
    ) async {
      final repo = FakeRepository();
      repo.toolTasksById['tt-sync'] = ToolTask(
        id: 'tt-sync',
        type: 'playlist-sync',
        state: 'done',
        createdAt: DateTime.utc(2026, 10, 1),
        finishedAt: DateTime.utc(2026, 10, 1, 1),
      );
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      final glyph = tester
          .widget<WaxIcon>(
            find
                .descendant(of: _row('tt-sync'), matching: find.byType(WaxIcon))
                .first,
          )
          .glyph;
      expect(glyph, WaxIcons.library);
      expect(glyph, isNot(WaxIcons.refresh));
    });

    // The glyphs the app draws on its controls: a row nothing presses that
    // leads with one reads as a button.
    const actions = <WaxGlyph>{
      WaxIcons.refresh,
      WaxIcons.delete,
      WaxIcons.edit,
      WaxIcons.upload,
      WaxIcons.search,
      WaxIcons.downloads,
      WaxIcons.add,
      WaxIcons.close,
      WaxIcons.check,
    };

    WaxGlyph leading(WidgetTester tester, Finder row) => tester
        .widget<WaxIcon>(
          find.descendant(of: row, matching: find.byType(WaxIcon)).first,
        )
        .glyph;

    void tall(WidgetTester tester) {
      tester.view
        ..physicalSize = const Size(1200, 6000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('no job row leads with a glyph the app draws on a control', (
      tester,
    ) async {
      tall(tester);
      const kinds = [
        'scan',
        'enrich',
        'analyze',
        'organize',
        'organize-undo',
        'restore',
        'empty-trash',
        'purge-trash',
        'delete',
        'remove-root',
        'import',
        'set-kind',
        'something-new',
      ];
      final repo =
          FakeRepository(
              sessionState: const SessionState(
                authenticated: true,
                user: _admin,
              ),
            )
            ..jobs = [
              for (final kind in kinds)
                Job(
                  pid: 'jb-$kind',
                  kind: kind,
                  state: 'done',
                  startedAt: DateTime.utc(2026, 9, 29, 10),
                  finishedAt: DateTime.utc(2026, 9, 29, 10, 5),
                ),
            ];
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      for (final kind in kinds) {
        expect(
          actions,
          isNot(contains(leading(tester, _job('jb-$kind')))),
          reason: kind,
        );
      }
    });

    testWidgets('no task row leads with a glyph the app draws on a control', (
      tester,
    ) async {
      tall(tester);
      const types = [
        'book-merge',
        'book-split',
        'cue-split',
        'acquire',
        'playlist-sync',
        'genre-normalize',
        'catalog-repair',
        'health-fix',
        'import-navidrome',
        'something-new',
      ];
      final repo = FakeRepository();
      for (final type in types) {
        repo.toolTasksById['tt-$type'] = _doneTask('tt-$type', type);
      }
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      for (final type in types) {
        expect(
          actions,
          isNot(contains(leading(tester, _row('tt-$type')))),
          reason: type,
        );
      }
    });
  });

  testWidgets('a first page that fits the window brings the next', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1200, 8000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _PagedTasks();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(repo.cursors, [null, 'c2']);
    expect(_row('tt-50'), findsOneWidget);
  });

  group('a sweep in flight', () {
    testWidgets('draws its control busy and takes no second press', (
      tester,
    ) async {
      final repo = _HeldSweep();
      repo.toolTasksById['tt-a'] = _doneTask('tt-a', 'book-merge');
      repo.toolTasksById['tt-b'] = _doneTask('tt-b', 'cue-split');
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      final control = find.bySemanticsIdentifier(
        SemanticsIds.tasksClearFinished,
      );
      await tester.tap(control);
      await tester.pump();
      expect(
        tester
            .widget<WaxIconButton>(
              waxControl<WaxIconButton>(SemanticsIds.tasksClearFinished),
            )
            .busy,
        isTrue,
      );
      await tester.tap(control, warnIfMissed: false);
      await tester.pump();
      expect(repo.clearFinishedToolTaskCalls, 1);

      repo.release.complete();
      await tester.pumpAndSettle();
      expect(repo.clearFinishedToolTaskScopes, [false]);
      expect(shellMessageText(raisedMessage(tester)), 'Cleared 2 tasks');
    });

    testWidgets("an administrator's menu gives way to a busy control", (
      tester,
    ) async {
      final repo = _HeldSweep(
        sessionState: const SessionState(authenticated: true, user: _admin),
      );
      repo.toolTasksById['tt-a'] = _doneTask('tt-a', 'book-merge');
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.tasksClearFinished),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.tasksClearFinishedMine),
      );
      // Past the menu's way out; the busy control spins, so nothing settles.
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester
            .widget<WaxIconButton>(
              waxControl<WaxIconButton>(SemanticsIds.tasksClearFinished),
            )
            .busy,
        isTrue,
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.tasksClearFinished),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.bySemanticsIdentifier(SemanticsIds.tasksClearFinishedMine),
        findsNothing,
      );

      repo.release.complete();
      await tester.pumpAndSettle();
      expect(repo.clearFinishedToolTaskScopes, [false]);
      expect(repo.clearFinishedJobCalls, 1);
      expect(shellMessageText(raisedMessage(tester)), 'Cleared 1 task');
    });
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

  testWidgets('an administrator follows the catalog jobs above the tasks', (
    tester,
  ) async {
    final started = DateTime.utc(2026, 9, 29, 10);
    final repo =
        FakeRepository(
            sessionState: const SessionState(authenticated: true, user: _admin),
          )
          ..jobs = [
            Job(
              pid: 'jb-2',
              kind: 'enrich',
              state: 'done',
              startedAt: started,
              finishedAt: started.add(const Duration(minutes: 3)),
              result: const {
                'lyricsMatched': 3,
                'artFetched': 2,
                'auxArtFetched': 1,
              },
            ),
            Job(
              pid: 'jb-3',
              kind: 'import',
              state: 'done',
              startedAt: started,
              finishedAt: started,
            ),
            Job(
              pid: 'jb-4',
              kind: 'analyze',
              state: 'crashed',
              error: 'the server stopped',
              startedAt: started,
              finishedAt: started,
            ),
            Job(
              pid: 'jb-6',
              kind: 'scan',
              state: 'canceled',
              error: 'interrupted before it finished',
              startedAt: started,
              finishedAt: started,
            ),
            Job(
              pid: 'jb-1',
              kind: 'scan',
              state: 'running',
              progress: 0.42,
              message: 'Reading tags',
              startedAt: started.subtract(const Duration(hours: 1)),
            ),
            Job(
              pid: 'jb-5',
              kind: 'enrich',
              state: 'running',
              startedAt: started,
              target: const JobTarget(
                type: 'item',
                pid: 'tr-1',
                name: 'Amber Waves',
              ),
            ),
          ];
    await tester.pumpWidget(_host(repo));
    // A running job's bar animates forever: frames, not a settle, while
    // the session and then the jobs answer.
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }

    final scan = _job('jb-1');
    expect(
      find.descendant(of: scan, matching: find.text('Library scan')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: scan, matching: find.text('Running · 42%')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: scan, matching: find.text('Reading tags')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _job('jb-2'),
        matching: find.text('lyrics 3, covers 2, pictures 1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _job('jb-4'), matching: find.text('Crashed')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _job('jb-4'),
        matching: find.text('the server stopped'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _job('jb-6'), matching: find.text('Stopped')),
      findsOneWidget,
      reason: 'nobody cancels a job; the server stopped under it',
    );
    expect(
      _job('jb-3'),
      findsOneWidget,
      reason: 'the server decides which finished jobs list',
    );
    expect(
      find.descendant(
        of: _job('jb-5'),
        matching: find.text('Enrichment: Amber Waves'),
      ),
      findsOneWidget,
      reason: 'a running targeted job names its target',
    );
    // Running first, whatever its age.
    expect(
      tester.getTopLeft(scan).dy,
      lessThan(tester.getTopLeft(_job('jb-2')).dy),
    );
  });

  testWidgets('a finished scan lists its copies and what it could not read', (
    tester,
  ) async {
    final started = DateTime.utc(2026, 9, 29, 10);
    Map<String, Object?> run(
      String name,
      int files,
      int copies, {
      bool gone = false,
    }) => {
      'libraryPid': 'lb-$name',
      'library': name,
      'audioFiles': files,
      'copies': copies,
      'rootUnreachable': gone,
    };
    final repo =
        FakeRepository(
            sessionState: const SessionState(authenticated: true, user: _admin),
          )
          ..jobs = [
            Job(
              pid: 'jb-7',
              kind: 'scan',
              state: 'done',
              startedAt: started,
              finishedAt: started.add(const Duration(minutes: 1)),
              result: {
                'created': 3,
                'updated': 1,
                'copies': 2,
                'missing': 0,
                'errored': 0,
                'walkErrors': 1,
                'rootUnreachable': true,
                'runs': [
                  run('Music', 412, 2),
                  run('Archive', 0, 0, gone: true),
                ],
              },
            ),
          ];
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    final scan = _job('jb-7');
    expect(
      find.descendant(
        of: scan,
        matching: find.text(
          'added 3, updated 1, copies 2, missing 0, errored 0, '
          'unreadable 1, folder not reachable',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: scan,
        matching: find.text('Music: 412 files, 2 copies'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: scan,
        matching: find.text('Archive: folder not reachable'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a finished analysis counts the fingerprints that fell back', (
    tester,
  ) async {
    final started = DateTime.utc(2026, 9, 29, 10);
    final repo =
        FakeRepository(
            sessionState: const SessionState(authenticated: true, user: _admin),
          )
          ..jobs = [
            Job(
              pid: 'jb-8',
              kind: 'analyze',
              state: 'done',
              startedAt: started,
              finishedAt: started.add(const Duration(minutes: 5)),
              result: const {
                'analyzed': 60,
                'errored': 0,
                'fingerprintFallbacks': 58,
                'fingerprintPartialReads': 2,
              },
            ),
            Job(
              pid: 'jb-9',
              kind: 'analyze',
              state: 'done',
              startedAt: started,
              finishedAt: started.add(const Duration(minutes: 5)),
              result: const {
                'analyzed': 4,
                'errored': 0,
                'fingerprintFallbacks': 0,
              },
            ),
          ];
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: _job('jb-8'),
        matching: find.text('analyzed 60, errored 0, fell back 58'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _job('jb-9'),
        matching: find.text('analyzed 4, errored 0'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a finished kind change says what changed and what folded', (
    tester,
  ) async {
    final started = DateTime.utc(2026, 10, 14, 10);
    final repo =
        FakeRepository(
            sessionState: const SessionState(authenticated: true, user: _admin),
          )
          ..jobs = [
            Job(
              pid: 'jb-k',
              kind: 'set-kind',
              state: 'done',
              // Targeted, as the server starts it, and listed finished
              // all the same.
              target: const JobTarget(
                type: 'item',
                pid: 'bk-1',
                name: 'The Loose Chapters',
              ),
              startedAt: started,
              finishedAt: started.add(const Duration(seconds: 3)),
              result: const {
                'converted': ['bk-1'],
                'absorbed': {'tr-2': 'bk-1', 'tr-3': 'bk-1'},
                'created': <String>[],
                'writeBackFailures': [
                  {'filePid': 'fl-1', 'reason': 'read-only'},
                ],
              },
            ),
          ];
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: _job('jb-k'),
        matching: find.text('Kind change: The Loose Chapters'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _job('jb-k'),
        matching: find.text('changed 1, folded 2, not written 1'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a job that lands above the others leaves them their rows', (
    tester,
  ) async {
    final at = DateTime.utc(2026, 9, 29, 10);
    Job scan(String pid, int minutes) => Job(
      pid: pid,
      kind: 'scan',
      state: 'done',
      startedAt: at,
      finishedAt: at.add(Duration(minutes: minutes)),
    );
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
    )..jobs = [scan('jb-2', 2), scan('jb-1', 1)];
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await expectRowsKeepTheirNodes(
      tester,
      [SemanticsIds.jobRow('jb-1'), SemanticsIds.jobRow('jb-2')],
      () async {
        repo.jobs = [scan('jb-3', 3), ...repo.jobs];
        ProviderScope.containerOf(
          tester.element(find.byType(WaxScaffold).first),
        ).invalidate(adminJobsProvider);
        await tester.pumpAndSettle();
      },
    );
    expect(_job('jb-3'), findsOneWidget);
  });

  testWidgets('a task that lands above the others leaves them their rows', (
    tester,
  ) async {
    ToolTask merge(String id, int hour) => ToolTask(
      id: id,
      type: 'book-merge',
      state: 'done',
      itemPid: 'bk-1',
      createdAt: DateTime.utc(2026, 7, 1, hour),
      finishedAt: DateTime.utc(2026, 7, 1, hour, 30),
    );
    final repo = FakeRepository();
    repo.toolTasksById
      ..['tt-2'] = merge('tt-2', 2)
      ..['tt-1'] = merge('tt-1', 1);
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await expectRowsKeepTheirNodes(
      tester,
      [SemanticsIds.taskRow('tt-1'), SemanticsIds.taskRow('tt-2')],
      () async {
        final older = repo.toolTasksById.values.toList();
        repo.toolTasksById
          ..clear()
          ..['tt-3'] = merge('tt-3', 3)
          ..addAll({for (final task in older) task.id: task});
        ProviderScope.containerOf(
          tester.element(find.byType(WaxScaffold).first),
        ).invalidate(toolTasksProvider);
        await tester.pumpAndSettle();
      },
    );
    expect(_row('tt-3'), findsOneWidget);
  });

  testWidgets("a listener's tasks read no jobs", (tester) async {
    final repo = FakeRepository(
      sessionState: const SessionState(
        authenticated: true,
        user: WaxDeckUser(id: 'us-2', username: 'sam'),
      ),
    )..jobs = [const Job(pid: 'jb-1', kind: 'scan', state: 'running')];
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(repo.jobReads, 0);
    expect(_job('jb-1'), findsNothing);
  });

  testWidgets('a health fix that failed before it counted anything offers '
      'no report', (tester) async {
    // Its summary carries the rule from the start, for the row's name;
    // that is not a report.
    final repo = FakeRepository();
    repo.toolTasksById['tt-fix'] = ToolTask(
      id: 'tt-fix',
      type: 'health-fix',
      state: 'failed',
      error: 'gave up after repeated attempts',
      createdAt: DateTime.utc(2026, 9, 29),
      finishedAt: DateTime.utc(2026, 9, 29, 1),
      summary: const {'rule': 'missing-lyrics'},
    );
    await tester.pumpWidget(_host(repo));
    await tester.pump();
    await tester.pump();

    expect(
      find.descendant(
        of: _row('tt-fix'),
        matching: find.text('Fix: Missing lyrics'),
      ),
      findsOneWidget,
    );
    expect(_forward(_row('tt-fix')), findsNothing);
  });

  testWidgets('a health fix and a genre clean-up say what they are', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.toolTasksById['tt-fix'] = ToolTask(
      id: 'tt-fix',
      type: 'health-fix',
      state: 'done',
      createdAt: DateTime.utc(2026, 9, 29),
      finishedAt: DateTime.utc(2026, 9, 29, 1),
      summary: const {
        'rule': 'missing-lyrics',
        'attempted': 5,
        'filled': 3,
        'failed': 0,
        'skipped': {'no match': 2},
      },
    );
    repo.toolTasksById['tt-genre'] = ToolTask(
      id: 'tt-genre',
      type: 'genre-normalize',
      state: 'queued',
      createdAt: DateTime.utc(2026, 9, 29),
    );
    await tester.pumpWidget(_host(repo));
    await tester.pump();
    await tester.pump();

    expect(
      find.descendant(
        of: _row('tt-fix'),
        matching: find.text('Fix: Missing lyrics'),
      ),
      findsOneWidget,
    );
    expect(find.text('filled 3 of 5, skipped 2, failed 0'), findsOneWidget);
    expect(
      find.descendant(
        of: _row('tt-genre'),
        matching: find.text('Genre clean-up'),
      ),
      findsOneWidget,
    );
  });
}
