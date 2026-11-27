import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:waxdeck/src/admin/admin_providers.dart';
import 'package:waxdeck/src/l10n/formats.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations.dart'
    show lookupAppLocalizations;
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_es.dart';
import 'package:waxdeck/src/shell/async_sliver_face.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/tools/tasks_screen.dart';
import 'package:waxdeck/src/tools/tool_tasks_provider.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';
import 'row_nodes.dart';
import 'wax_finders.dart';

/// The tasks screen over [repo], settled.
Future<void> _pump(WidgetTester tester, FakeRepository repo) async {
  await pumpApp(
    tester,
    const TasksScreen(),
    container: appContainer(repo: repo),
  );
}

/// The tasks screen over [repo], mounted and not settled.
Future<void> _mount(WidgetTester tester, FakeRepository repo) =>
    mountApp(tester, const TasksScreen(), container: appContainer(repo: repo));

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
    await _pump(tester, repo);
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
    await _mount(tester, repo);
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
    await _pump(tester, repo);

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
    await _pump(tester, repo);

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
      'source-retry': 'The source had a problem. It will try again.',
      'rate-limited': 'The source asked it to slow down.',
      'stalled': 'The download stalled. It will start again.',
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
    await _pump(tester, repo);

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

  testWidgets('the wait sentences added for downloads read in Spanish', (
    tester,
  ) async {
    final es = AppLocalizationsEs();
    final reasons = {
      'source-retry': es.toolsWaitSourceRetry,
      'rate-limited': es.toolsWaitRateLimited,
      'stalled': es.toolsWaitStalled,
      'other': es.toolsWaitOther,
    };
    final repo = FakeRepository();
    var i = 0;
    for (final reason in reasons.keys) {
      repo.toolTasksById['tt-$i'] = ToolTask(
        id: 'tt-$i',
        type: 'acquire',
        state: 'running',
        waitReason: reason,
        createdAt: DateTime.utc(2026, 7, 1, 0, i),
      );
      i++;
    }
    await pumpApp(
      tester,
      const TasksScreen(),
      container: appContainer(repo: repo),
      locale: const Locale('es'),
    );

    i = 0;
    for (final sentence in reasons.values) {
      expect(
        find.descendant(of: _row('tt-$i'), matching: find.text(sentence)),
        findsOneWidget,
        reason: reasons.keys.elementAt(i),
      );
      i++;
    }
    // The words are Spanish, not the English fallthrough.
    expect(es.toolsWaitStalled, isNot(AppLocalizationsEn().toolsWaitStalled));
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
    await pumpApp(
      tester,
      const TasksScreen(),
      container: appContainer(repo: repo),
      locale: const Locale('es'),
    );

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
    await _mount(tester, repo);
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
    await _pump(tester, repo);

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
    await _pump(tester, repo);

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
    await _pump(tester, repo);

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
    await _pump(tester, repo);

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
    await _pump(tester, repo);

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
    await _pump(tester, repo);

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
    await _pump(tester, repo);
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
    await _pump(tester, repo);

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
    await _pump(tester, repo);

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
    await _pump(tester, repo);

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

  testWidgets('a failure whose summary holds only what the task was queued '
      'with offers no report', (tester) async {
    // Queue-time keys are the row's name and scope, and a download's entry
    // keys say what it opened: none of them is a report to open.
    final repo = FakeRepository();
    final summaries = <String, (String, Map<String, Object?>)>{
      'tt-url': ('acquire', {'url': 'https://v.example/x', 'source': 'video'}),
      'tt-ran': (
        'acquire',
        {
          'url': 'https://v.example/x',
          'source': 'video',
          'entries': 2,
          'truncated': false,
        },
      ),
      'tt-imp': ('import-jellyfin', {'target': 'music', 'dryRun': false}),
      'tt-gn': ('genre-normalize', {'dryRun': true, 'scoped': true}),
    };
    for (final MapEntry(key: id, value: (type, summary)) in summaries.entries) {
      repo.toolTasksById[id] = ToolTask(
        id: id,
        type: type,
        state: 'failed',
        error: 'the source refused it',
        summary: summary,
        createdAt: DateTime.utc(2026, 7, 1),
        finishedAt: DateTime.utc(2026, 7, 1, 1),
      );
    }
    repo.toolTasksById['tt-rep'] = ToolTask(
      id: 'tt-rep',
      type: 'import-jellyfin',
      state: 'failed',
      error: 'the server went away mid-import',
      summary: const {'target': 'music', 'dryRun': false, 'matched': 4},
      createdAt: DateTime.utc(2026, 7, 1),
      finishedAt: DateTime.utc(2026, 7, 1, 1),
    );
    await _pump(tester, repo);

    for (final id in summaries.keys) {
      expect(_forward(_row(id)), findsNothing, reason: id);
    }
    expect(_forward(_row('tt-rep')), findsOneWidget);
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
    await _pump(tester, repo);
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
    await _pump(tester, repo);

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
    await _pump(tester, repo);

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
      await _pump(tester, repo);

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
      await _pump(tester, repo);

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
    await _pump(tester, repo);

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
    await _mount(tester, repo);
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
        await _pump(tester, repo);
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
      await _pump(tester, repo);

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
      await _pump(tester, repo);

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
      await pumpApp(
        tester,
        const TasksScreen(),
        container: appContainer(repo: repo),
        locale: const Locale('es'),
      );

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
      await _mount(tester, repo);
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
      await _pump(tester, repo);

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
      await _pump(tester, repo);

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
      await _pump(tester, repo);

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
      await _pump(tester, repo);

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
      await _pump(tester, repo);

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
      await _pump(tester, repo);

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
      await _pump(tester, repo);

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
    await _pump(tester, repo);

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
      await _pump(tester, repo);

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
      await _pump(tester, repo);

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
    await pumpApp(tester, const TasksScreen());

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
    await _mount(tester, repo);
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
    await _mount(tester, repo);
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
      reason: 'a canceled job reads as stopped',
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
    await _pump(tester, repo);

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
    await _pump(tester, repo);

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
    await _pump(tester, repo);

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
    await _pump(tester, repo);

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
    await _pump(tester, repo);

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
    await _pump(tester, repo);

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
    await _mount(tester, repo);
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
    await _mount(tester, repo);
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

  group('a failed task', () {
    ToolTask failed({
      String? code,
      Map<String, String>? params,
      String? error = 'video unavailable (private)',
    }) => ToolTask(
      id: 'tt-f',
      type: 'acquire',
      state: 'failed',
      error: error,
      errorCode: code,
      errorParams: params,
      createdAt: DateTime.utc(2026, 7, 1),
      finishedAt: DateTime.utc(2026, 7, 1, 1),
    );

    Finder inRow(String text) =>
        find.descendant(of: _row('tt-f'), matching: find.text(text));

    testWidgets('headlines the translated sentence for its code and folds '
        'the server sentence out', (tester) async {
      final repo = FakeRepository();
      repo.toolTasksById['tt-f'] = failed(
        code: 'source-refused',
        params: const {'reason': 'video-private'},
      );
      await _pump(tester, repo);

      expect(
        inRow(AppLocalizationsEn().errorSourceVideoPrivate),
        findsOneWidget,
      );
      expect(inRow('video unavailable (private)'), findsNothing);

      // One control under one id, whichever way it reads.
      final toggle = find.bySemanticsIdentifier(
        SemanticsIds.taskErrorDetails('tt-f'),
      );
      expect(toggle, findsOneWidget);
      await tester.tap(toggle);
      await tester.pump();
      expect(inRow('video unavailable (private)'), findsOneWidget);
      expect(
        inRow(AppLocalizationsEn().errorSourceVideoPrivate),
        findsOneWidget,
      );

      await tester.tap(find.text('Hide details'));
      await tester.pump();
      expect(inRow('video unavailable (private)'), findsNothing);
    });

    testWidgets('a parked row keeps its server sentence whatever code it '
        'carries', (tester) async {
      final repo = FakeRepository();
      repo.toolTasksById['tt-f'] = ToolTask(
        id: 'tt-f',
        type: 'book-merge',
        state: 'parked',
        error: 'stopped: its last 3 runs ended with the server',
        errorCode: 'source-refused',
        errorParams: const {'reason': 'video-private'},
        createdAt: DateTime.utc(2026, 7, 1),
        finishedAt: DateTime.utc(2026, 7, 1, 1),
      );
      await _pump(tester, repo);

      expect(
        inRow('stopped: its last 3 runs ended with the server'),
        findsOneWidget,
      );
      expect(inRow(AppLocalizationsEn().errorSourceVideoPrivate), findsNothing);
      expect(find.text('Show details'), findsNothing);
    });

    testWidgets('a code this app does not know shows the server sentence '
        'once, with nothing to fold', (tester) async {
      final repo = FakeRepository();
      repo.toolTasksById['tt-f'] = failed(code: 'a-code-from-later');
      await _pump(tester, repo);

      expect(inRow('video unavailable (private)'), findsOneWidget);
      expect(find.text('Show details'), findsNothing);
    });

    testWidgets('an internal code shows the server sentence once, with '
        'nothing to fold', (tester) async {
      // The server codes an unclassified failure `internal`, which says
      // less than the sentence it came with.
      final repo = FakeRepository();
      repo.toolTasksById['tt-f'] = failed(code: 'internal');
      await _pump(tester, repo);

      expect(inRow('video unavailable (private)'), findsOneWidget);
      expect(inRow(AppLocalizationsEn().errorInternal), findsNothing);
      expect(find.text('Show details'), findsNothing);
    });

    testWidgets('an internal code with no server sentence headlines its own '
        'copy', (tester) async {
      for (final error in <String?>[null, '']) {
        final repo = FakeRepository();
        repo.toolTasksById['tt-f'] = failed(code: 'internal', error: error);
        await _pump(tester, repo);

        expect(
          inRow(AppLocalizationsEn().errorInternal),
          findsOneWidget,
          reason: '$error',
        );
        expect(find.text('Show details'), findsNothing);
      }
    });

    testWidgets('a code with no server sentence has no details to open', (
      tester,
    ) async {
      final repo = FakeRepository();
      repo.toolTasksById['tt-f'] = failed(code: 'timeout', error: null);
      await _pump(tester, repo);

      expect(inRow(AppLocalizationsEn().errorTimeout), findsOneWidget);
      expect(find.text('Show details'), findsNothing);
    });

    testWidgets('with no code keeps the server sentence as it was', (
      tester,
    ) async {
      final repo = FakeRepository();
      repo.toolTasksById['tt-f'] = failed();
      await _pump(tester, repo);

      expect(inRow('video unavailable (private)'), findsOneWidget);
      expect(find.text('Show details'), findsNothing);
    });

    testWidgets('reads in Spanish', (tester) async {
      final repo = FakeRepository();
      repo.toolTasksById['tt-f'] = failed(
        code: 'source-refused',
        params: const {'reason': 'video-private'},
      );
      await pumpApp(
        tester,
        const TasksScreen(),
        container: appContainer(repo: repo),
        locale: const Locale('es'),
      );

      expect(
        inRow(AppLocalizationsEs().errorSourceVideoPrivate),
        findsOneWidget,
      );
      expect(find.text('Ver detalles'), findsOneWidget);
    });
  });

  group('a running task', () {
    ToolTask running(
      ToolTaskActivity? activity, {
      double? pct,
      String? waitReason,
      String type = 'acquire',
      Map<String, Object?>? summary,
    }) => ToolTask(
      id: 'tt-a',
      type: type,
      summary: summary,
      state: 'running',
      progressPct: pct,
      activity: activity,
      waitReason: waitReason,
      createdAt: DateTime.utc(2026, 7, 1),
    );

    Future<void> showRow(WidgetTester tester, ToolTask task) async {
      final repo = FakeRepository();
      repo.toolTasksById[task.id] = task;
      await _mount(tester, repo);
      // No pumpAndSettle: a bar animates.
      await tester.pump();
      await tester.pump();
    }

    Finder inRow(String text) =>
        find.descendant(of: _row('tt-a'), matching: find.text(text));

    ToolTaskActivity phase(
      String phase, {
      int? done,
      int? total,
      String? title,
      int? bytes,
      int? bytesTotal,
      DateTime? at,
    }) => ToolTaskActivity(
      phase: phase,
      at: at ?? clock.now(),
      itemsDone: done,
      itemsTotal: total,
      itemTitle: title,
      bytesDone: bytes,
      bytesTotal: bytesTotal,
    );

    testWidgets('says what it is doing, phase by phase', (tester) async {
      final cases = <(ToolTaskActivity, String)>[
        (phase('listing'), 'Listing the playlist'),
        (phase('importing'), 'Opening review entries'),
        (phase('processing'), 'Processing'),
        (
          phase('processing', title: 'Long Division'),
          'Processing Long Division',
        ),
        (phase('downloading'), 'Downloading'),
        (
          phase('downloading', title: 'Long Division'),
          'Downloading Long Division',
        ),
        // One item is not "1 of 1".
        (
          phase('downloading', done: 0, total: 1, title: 'Long Division'),
          'Downloading Long Division',
        ),
        (phase('downloading', done: 2, total: 37), 'Downloading 3 of 37'),
        (
          phase('downloading', done: 2, total: 37, title: 'Long Division'),
          'Downloading 3 of 37: Long Division',
        ),
        (
          phase(
            'downloading',
            done: 2,
            total: 37,
            title: 'Long Division',
            bytes: 4404019,
            bytesTotal: 10276045,
          ),
          'Downloading 3 of 37: Long Division (4.2 MB of 9.8 MB)',
        ),
        (
          phase(
            'downloading',
            title: 'Long Division',
            bytes: 900 * 1024,
            bytesTotal: 10276045,
          ),
          'Downloading Long Division (900 KB of 9.8 MB)',
        ),
        // A size the source never gave leaves the bytes out.
        (
          phase('downloading', title: 'Long Division', bytes: 4404019),
          'Downloading Long Division',
        ),
      ];
      for (final (activity, caption) in cases) {
        await showRow(tester, running(activity));
        expect(inRow(caption), findsOneWidget, reason: caption);
      }
    });

    testWidgets('listing follows the link: a channel, a playlist, a sync', (
      tester,
    ) async {
      final cases = <(String, Map<String, Object?>?, String)>[
        ('acquire', {'source': 'channel'}, 'Listing the channel'),
        ('acquire', {'source': 'playlist'}, 'Listing the playlist'),
        ('acquire', null, 'Listing the playlist'),
        ('playlist-sync', null, 'Listing the playlist'),
      ];
      for (final (type, summary, caption) in cases) {
        await showRow(
          tester,
          running(phase('listing'), type: type, summary: summary),
        );
        expect(inRow(caption), findsOneWidget, reason: '$type $summary');
      }
    });

    testWidgets('listing a channel reads in Spanish', (tester) async {
      final es = AppLocalizationsEs();
      final repo = FakeRepository();
      repo.toolTasksById['tt-a'] = running(
        phase('listing'),
        summary: const {'source': 'channel'},
      );
      await mountApp(
        tester,
        const TasksScreen(),
        container: appContainer(repo: repo),
        locale: const Locale('es'),
      );
      await tester.pump();
      await tester.pump();
      expect(inRow(es.toolsActivityListingChannel), findsOneWidget);
      expect(inRow(es.toolsActivityListing), findsNothing);
    });

    testWidgets('importing follows the kind: review entries for a download '
        'or a sync, the library for the rest', (tester) async {
      for (final type in ['acquire', 'playlist-sync']) {
        await showRow(tester, running(phase('importing'), type: type));
        expect(inRow('Opening review entries'), findsOneWidget, reason: type);
      }
      for (final type in ['book-merge', 'book-split', 'cue-split']) {
        await showRow(tester, running(phase('importing'), type: type));
        expect(inRow('Adding to the library'), findsOneWidget, reason: type);
        expect(inRow('Opening review entries'), findsNothing, reason: type);
      }
      // A listening-history import writes no library item.
      for (final type in [
        'import-jellyfin',
        'import-lastfm',
        'import-spotify',
      ]) {
        await showRow(tester, running(phase('importing'), type: type));
        expect(inRow('Importing'), findsOneWidget, reason: type);
        expect(inRow('Adding to the library'), findsNothing, reason: type);
        expect(inRow('Opening review entries'), findsNothing, reason: type);
      }
    });

    testWidgets('importing reads in Spanish by kind', (tester) async {
      final es = AppLocalizationsEs();
      final repo = FakeRepository();
      repo.toolTasksById['tt-a'] = running(
        phase('importing'),
        type: 'book-merge',
      );
      await mountApp(
        tester,
        const TasksScreen(),
        container: appContainer(repo: repo),
        locale: const Locale('es'),
      );
      await tester.pump();
      await tester.pump();
      expect(inRow(es.toolsActivityImportingLibrary), findsOneWidget);
      expect(inRow(es.toolsActivityImporting), findsNothing);

      repo.toolTasksById['tt-a'] = running(
        phase('importing'),
        type: 'import-lastfm',
      );
      await mountApp(
        tester,
        const TasksScreen(),
        container: appContainer(repo: repo),
        locale: const Locale('es'),
      );
      await tester.pump();
      await tester.pump();
      expect(inRow(es.toolsActivityImportingPlain), findsOneWidget);
    });

    testWidgets('a phase this app does not know adds no caption', (
      tester,
    ) async {
      // No server sets these two, so they draw nothing.
      await showRow(tester, running(phase('probing', title: 'X')));
      expect(inRow('X'), findsNothing);
      expect(inRow('Checking the link'), findsNothing);
      await showRow(tester, running(phase('waiting', title: 'X')));
      expect(inRow('X'), findsNothing);
      await showRow(tester, running(phase('rewinding-tape', title: 'X')));
      expect(inRow('X'), findsNothing);
      expect(find.textContaining('No activity'), findsNothing);
    });

    testWidgets('its bar is determinate once it reports, and indeterminate '
        'before', (tester) async {
      WaxProgressBar bar() => tester.widget<WaxProgressBar>(
        find.descendant(
          of: _row('tt-a'),
          matching: find.byType(WaxProgressBar),
        ),
      );

      await showRow(tester, running(null));
      expect(bar().value, isNull);

      await showRow(tester, running(null, pct: 0));
      expect(bar().value, isNull);
      // A bar that sweeps says no percent.
      expect(inRow('Running'), findsOneWidget);
      expect(inRow('Running · 0%'), findsNothing);

      await showRow(tester, running(null, pct: 40));
      expect(bar().value, closeTo(0.4, 1e-9));

      // Activity with nothing finished is an empty bar, not one that sweeps.
      await showRow(tester, running(phase('downloading')));
      expect(bar().value, 0);

      await showRow(
        tester,
        running(phase('downloading', done: 2, total: 37), pct: 8.1),
      );
      expect(bar().value, closeTo(0.081, 1e-9));
      expect(inRow('Running · 8%'), findsOneWidget);
    });

    testWidgets('says nothing of a stall until the last activity is two '
        'minutes old, then counts the minutes', (tester) async {
      final seen = clock.now();
      await showRow(
        tester,
        running(
          phase(
            'downloading',
            title: 'Long Division',
            at: seen.subtract(const Duration(seconds: 70)),
          ),
        ),
      );
      expect(find.textContaining('No activity'), findsNothing);

      // 70 s old, plus 49 s: still short of two minutes.
      await tester.pump(const Duration(seconds: 49));
      expect(find.textContaining('No activity'), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      expect(inRow('No activity for 2 min'), findsOneWidget);
      expect(
        tester.widget<Text>(inRow('No activity for 2 min')).style?.color,
        WaxColors.of(tester.element(_row('tt-a'))).textSecondary,
      );
      // What it was doing stays beside it.
      expect(inRow('Downloading Long Division'), findsOneWidget);

      // The count follows the clock without another fetch.
      await tester.pump(const Duration(minutes: 3));
      expect(inRow('No activity for 5 min'), findsOneWidget);
    });

    testWidgets('only the phases whose source reports activity can stall', (
      tester,
    ) async {
      final old = clock.now().subtract(const Duration(minutes: 9));
      for (final name in ['downloading', 'listing']) {
        await showRow(tester, running(phase(name, at: old)));
        expect(inRow('No activity for 9 min'), findsOneWidget, reason: name);
      }
      for (final name in [
        'processing',
        'importing',
        'probing',
        'waiting',
        'rewinding-tape',
      ]) {
        await showRow(tester, running(phase(name, at: old)));
        expect(find.textContaining('No activity'), findsNothing, reason: name);
      }
    });

    testWidgets('a fresh sign of life clears the stall', (tester) async {
      final repo = FakeRepository();
      repo.toolTasksById['tt-a'] = running(
        phase(
          'downloading',
          at: clock.now().subtract(const Duration(minutes: 9)),
        ),
      );
      await _mount(tester, repo);
      await tester.pump();
      await tester.pump();
      expect(inRow('No activity for 9 min'), findsOneWidget);

      repo.toolTasksById['tt-a'] = running(phase('downloading'));
      ProviderScope.containerOf(
        tester.element(find.byType(TasksScreen)),
      ).invalidate(toolTasksProvider);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('No activity'), findsNothing);
    });

    testWidgets('a waiting task is not called stalled, and shows no phase', (
      tester,
    ) async {
      await showRow(
        tester,
        running(
          phase(
            'downloading',
            title: 'Long Division',
            at: clock.now().subtract(const Duration(minutes: 9)),
          ),
          waitReason: 'rate-limited',
        ),
      );
      expect(find.textContaining('No activity'), findsNothing);
      expect(inRow('Downloading Long Division'), findsNothing);
      expect(inRow('The source asked it to slow down.'), findsOneWidget);
    });

    testWidgets('a queued task has no stall to report', (tester) async {
      await showRow(
        tester,
        ToolTask(
          id: 'tt-a',
          type: 'acquire',
          state: 'queued',
          createdAt: DateTime.utc(2026, 7, 1),
        ),
      );
      expect(find.textContaining('No activity'), findsNothing);
    });

    testWidgets('reads in Spanish', (tester) async {
      final repo = FakeRepository();
      repo.toolTasksById['tt-a'] = running(
        phase(
          'downloading',
          done: 2,
          total: 37,
          title: 'Long Division',
          bytes: 4404019,
          bytesTotal: 10276045,
          at: clock.now().subtract(const Duration(minutes: 3)),
        ),
      );
      await mountApp(
        tester,
        const TasksScreen(),
        container: appContainer(repo: repo),
        locale: const Locale('es'),
      );
      await tester.pump();
      await tester.pump();
      final es = AppLocalizationsEs();
      expect(
        inRow(
          es.toolsActivityBytes(
            es.toolsActivityDownloadingCountTitled(3, 37, 'Long Division'),
            es.formatBytes(4404019),
            es.formatBytes(10276045),
          ),
        ),
        findsOneWidget,
      );
      expect(inRow(es.toolsActivityStalled(3)), findsOneWidget);
    });
  });

  group('a canceled task that left files', () {
    ToolTask canceledMerge() => ToolTask(
      id: 'tt-c',
      type: 'book-merge',
      state: 'canceled',
      itemPid: 'bk-1',
      error:
          'canceled; these files could not be removed and are still in '
          'Ada/Book: part 1.tmp, part 2.tmp',
      createdAt: DateTime.utc(2026, 7, 1),
      finishedAt: DateTime.utc(2026, 7, 1, 1),
    );

    const hidden = WaxDeckApiException(
      code: 'conflict',
      message: 'the files could not be removed',
      statusCode: 409,
      params: {
        'reason': 'outputs-hidden',
        'folder': 'Ada/Book',
        'cause': 'permission denied',
      },
    );
    final sentence = AppLocalizationsEn().errorToolOutputsHidden(
      'Ada/Book',
      'permission denied',
    );

    testWidgets('says what it could not remove, as a parked row does', (
      tester,
    ) async {
      final repo = FakeRepository();
      repo.toolTasksById['tt-c'] = canceledMerge();
      await _pump(tester, repo);

      final row = _row('tt-c');
      expect(
        find.descendant(of: row, matching: find.text('Canceled')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text(canceledMerge().error!)),
        findsOneWidget,
      );
    });

    testWidgets('dismissing it words a refusal to clear its files', (
      tester,
    ) async {
      final repo = FakeRepository()..deleteToolTaskError = hidden;
      repo.toolTasksById['tt-c'] = canceledMerge();
      await _pump(tester, repo);

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.taskDismiss('tt-c')),
      );
      await tester.pumpAndSettle();

      expect(repo.deleteToolTaskCalls, ['tt-c']);
      expect(shellMessageText(raisedMessage(tester)), sentence);
      expect(_row('tt-c'), findsOneWidget, reason: 'the task stays');
    });

    testWidgets('Clear finished words the same refusal', (tester) async {
      final repo = FakeRepository()..deleteToolTaskError = hidden;
      repo.toolTasksById['tt-c'] = canceledMerge();
      await _pump(tester, repo);

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.tasksClearFinished),
      );
      await tester.pumpAndSettle();

      expect(repo.clearFinishedToolTaskCalls, 1);
      expect(shellMessageText(raisedMessage(tester)), sentence);
    });
  });

  group('canceling a task', () {
    ToolTask task(
      String id, {
      String type = 'acquire',
      String state = 'running',
      bool cancelRequested = false,
      String? waitReason,
      double? pct,
      ToolTaskActivity? activity,
    }) => ToolTask(
      id: id,
      type: type,
      state: state,
      cancelRequested: cancelRequested,
      waitReason: waitReason,
      progressPct: pct,
      activity: activity,
      createdAt: DateTime.utc(2026, 7, 1),
      finishedAt: switch (state) {
        'queued' || 'running' => null,
        _ => DateTime.utc(2026, 7, 1, 1),
      },
    );

    ToolTaskActivity downloading({int? done, int? total}) => ToolTaskActivity(
      phase: 'downloading',
      at: clock.now(),
      itemsDone: done,
      itemsTotal: total,
      itemTitle: 'Long Division',
    );

    Finder cancelControl(String id) =>
        find.bySemanticsIdentifier(SemanticsIds.taskCancel(id));
    Finder dismissControl(String id) =>
        find.bySemanticsIdentifier(SemanticsIds.taskDismiss(id));
    Finder confirm() =>
        find.bySemanticsIdentifier(SemanticsIds.taskCancelConfirm);
    Finder inRow(String id, String text) =>
        find.descendant(of: _row(id), matching: find.text(text));

    // No pumpAndSettle: a running row's bar animates.
    Future<void> advance(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<FakeRepository> show(
      WidgetTester tester,
      List<ToolTask> tasks, {
      Locale locale = const Locale('en'),
    }) async {
      final repo = FakeRepository();
      for (final t in tasks) {
        repo.toolTasksById[t.id] = t;
      }
      await mountApp(
        tester,
        const TasksScreen(),
        container: appContainer(repo: repo),
        locale: locale,
      );
      await advance(tester);
      return repo;
    }

    testWidgets('is offered on queued, running and waiting rows only', (
      tester,
    ) async {
      await show(tester, [
        task('tt-queued', state: 'queued'),
        task('tt-running'),
        task('tt-waiting', waitReason: 'rate-limited'),
        task('tt-unknown', state: 'a-new-state'),
        task('tt-done', state: 'done'),
        task('tt-failed', state: 'failed'),
        task('tt-parked', state: 'parked'),
        task('tt-canceled', state: 'canceled'),
        task('tt-winding', cancelRequested: true),
      ]);

      for (final id in [
        'tt-queued',
        'tt-running',
        'tt-waiting',
        'tt-unknown',
      ]) {
        expect(cancelControl(id), findsOneWidget, reason: id);
        expect(dismissControl(id), findsNothing, reason: id);
      }
      for (final id in [
        'tt-done',
        'tt-failed',
        'tt-parked',
        'tt-canceled',
        'tt-winding',
      ]) {
        expect(cancelControl(id), findsNothing, reason: id);
      }
      for (final id in ['tt-done', 'tt-failed', 'tt-parked', 'tt-canceled']) {
        expect(dismissControl(id), findsOneWidget, reason: id);
      }
      expect(dismissControl('tt-winding'), findsNothing);
    });

    testWidgets(
      'a queued task stops at once and reads Canceled, then dismisses',
      (tester) async {
        final repo = await show(tester, [task('tt-a', state: 'queued')]);

        await tester.tap(cancelControl('tt-a'));
        await advance(tester);

        expect(repo.cancelToolTaskCalls, ['tt-a']);
        expect(confirm(), findsNothing);
        expect(inRow('tt-a', 'Canceled'), findsOneWidget);
        expect(cancelControl('tt-a'), findsNothing);
        expect(find.byType(WaxProgressBar), findsNothing);
        expect(raisedMessage(tester), isNull);

        await tester.tap(dismissControl('tt-a'));
        await advance(tester);
        expect(repo.deleteToolTaskCalls, ['tt-a']);
        expect(_row('tt-a'), findsNothing);
      },
    );

    testWidgets('a canceled task counts as finished for Clear finished', (
      tester,
    ) async {
      final repo = await show(tester, [task('tt-a', state: 'canceled')]);

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.tasksClearFinished),
      );
      await advance(tester);

      expect(repo.clearFinishedToolTaskCalls, 1);
      expect(_row('tt-a'), findsNothing);
    });

    testWidgets('a running task with nothing staged cancels without asking and '
        'winds down on its row', (tester) async {
      final repo = await show(tester, [
        task('tt-a', type: 'genre-normalize', pct: 40),
        task('tt-b', activity: downloading(done: 0, total: 3)),
      ]);

      await tester.tap(cancelControl('tt-a'));
      await advance(tester);
      expect(confirm(), findsNothing, reason: 'only a download stages items');
      expect(repo.cancelToolTaskCalls, ['tt-a']);

      await tester.tap(cancelControl('tt-b'));
      await advance(tester);
      expect(confirm(), findsNothing, reason: 'none done, none counted');
      expect(repo.cancelToolTaskCalls, ['tt-a', 'tt-b']);

      // Winding down: still a bar and its caption, no control, no word of
      // a finished state.
      expect(inRow('tt-b', 'Canceling'), findsOneWidget);
      expect(inRow('tt-b', 'Running'), findsNothing);
      expect(cancelControl('tt-b'), findsNothing);
      expect(dismissControl('tt-b'), findsNothing);
      expect(
        find.descendant(
          of: _row('tt-b'),
          matching: find.byType(WaxProgressBar),
        ),
        findsOneWidget,
      );
      expect(
        inRow('tt-b', 'Downloading 1 of 3: Long Division'),
        findsOneWidget,
      );
    });

    testWidgets('puts the answer in the row without reading the list again', (
      tester,
    ) async {
      final repo = await show(tester, [task('tt-a', state: 'queued')]);
      final reads = repo.listToolTasksCalls;

      await tester.tap(cancelControl('tt-a'));
      await advance(tester);

      expect(inRow('tt-a', 'Canceled'), findsOneWidget);
      expect(repo.listToolTasksCalls, reads);
    });

    testWidgets('a reply that lands after a newer read leaves that read', (
      tester,
    ) async {
      final repo = FakeRepository();
      repo.toolTasksById['tt-a'] = task('tt-a');
      final container = appContainer(repo: repo);
      await mountApp(tester, const TasksScreen(), container: container);
      await advance(tester);
      final held = Completer<void>();
      repo.cancelToolTaskHeld = held.future;

      await tester.tap(cancelControl('tt-a'));
      await advance(tester);
      // The end's marker reads the list before the reply comes back.
      repo.toolTasksById['tt-a'] = task('tt-a', state: 'canceled');
      container.invalidate(toolTasksProvider);
      await advance(tester);
      expect(inRow('tt-a', 'Canceled'), findsOneWidget);

      held.complete();
      await advance(tester);
      expect(inRow('tt-a', 'Canceled'), findsOneWidget);
      expect(inRow('tt-a', 'Canceling'), findsNothing);
    });

    testWidgets('a read the server answered before it took the cancel keeps '
        'Canceling when it lands after the reply; a read showing the end '
        'shows the end', (tester) async {
      final repo = FakeRepository();
      repo.toolTasksById['tt-a'] = task('tt-a', type: 'genre-normalize');
      final container = appContainer(repo: repo);
      await mountApp(tester, const TasksScreen(), container: container);
      await advance(tester);
      final held = Completer<void>();
      repo.cancelToolTaskHeld = held.future;

      await tester.tap(cancelControl('tt-a'));
      await advance(tester);
      // A read begun while the cancel is out, answered before the server
      // took it.
      final stale = repo.listToolTasksGate = Completer<void>();
      container.invalidate(toolTasksProvider);
      await advance(tester);
      held.complete();
      await advance(tester);
      expect(inRow('tt-a', 'Canceling'), findsOneWidget);

      repo.toolTasksById['tt-a'] = task('tt-a', type: 'genre-normalize');
      stale.complete();
      repo.listToolTasksGate = null;
      await advance(tester);
      expect(inRow('tt-a', 'Canceling'), findsOneWidget);
      expect(cancelControl('tt-a'), findsNothing);

      repo.toolTasksById['tt-a'] = task(
        'tt-a',
        type: 'genre-normalize',
        state: 'canceled',
      );
      container.invalidate(toolTasksProvider);
      await advance(tester);
      expect(inRow('tt-a', 'Canceled'), findsOneWidget);
      expect(inRow('tt-a', 'Canceling'), findsNothing);
    });

    testWidgets('a waiting task cancels from its row and winds down', (
      tester,
    ) async {
      final repo = await show(tester, [
        task('tt-a', waitReason: 'rate-limited'),
      ]);
      expect(cancelControl('tt-a'), findsOneWidget);

      await tester.tap(cancelControl('tt-a'));
      await advance(tester);

      expect(repo.cancelToolTaskCalls, ['tt-a']);
      expect(inRow('tt-a', 'Canceling'), findsOneWidget);
      expect(cancelControl('tt-a'), findsNothing);
    });

    testWidgets('a row both waiting and asked to cancel reads Canceling with '
        'no control, and keeps its wait sentence', (tester) async {
      await show(tester, [
        task('tt-a', waitReason: 'rate-limited', cancelRequested: true),
      ]);

      expect(inRow('tt-a', 'Canceling'), findsOneWidget);
      expect(inRow('tt-a', 'Waiting'), findsNothing);
      expect(cancelControl('tt-a'), findsNothing);
      expect(dismissControl('tt-a'), findsNothing);
      expect(
        inRow('tt-a', 'The source asked it to slow down.'),
        findsOneWidget,
      );
    });

    testWidgets('a playlist sync with nothing staged cancels without asking', (
      tester,
    ) async {
      final repo = await show(tester, [
        task(
          'tt-a',
          type: 'playlist-sync',
          activity: downloading(done: 0, total: 4),
        ),
      ]);

      await tester.tap(cancelControl('tt-a'));
      await advance(tester);

      expect(confirm(), findsNothing);
      expect(find.text('Cancel this task?'), findsNothing);
      expect(repo.cancelToolTaskCalls, ['tt-a']);
    });

    testWidgets('a task the server no longer has leaves the list, quietly', (
      tester,
    ) async {
      final repo = await show(tester, [
        task('tt-a', state: 'queued'),
        task('tt-b', state: 'queued'),
      ]);
      repo.cancelToolTaskError = const WaxDeckApiException(
        code: 'not-found',
        message: 'no such task',
        statusCode: 404,
      );
      final reads = repo.listToolTasksCalls;

      await tester.tap(cancelControl('tt-a'));
      await advance(tester);

      expect(_row('tt-a'), findsNothing);
      expect(_row('tt-b'), findsOneWidget);
      expect(raisedMessage(tester), isNull);
      expect(repo.listToolTasksCalls, reads);
    });

    for (final locale in const [Locale('en'), Locale('es')]) {
      testWidgets(
        'each cancel control names its task (${locale.languageCode})',
        (tester) async {
          final handle = tester.ensureSemantics();
          await show(tester, [
            ToolTask(
              id: 'tt-a',
              type: 'acquire',
              state: 'running',
              itemTitle: 'Long Division',
              createdAt: DateTime.utc(2026, 7, 1),
            ),
            ToolTask(
              id: 'tt-b',
              type: 'book-merge',
              state: 'queued',
              itemTitle: 'The Book',
              createdAt: DateTime.utc(2026, 7, 1),
            ),
          ], locale: locale);

          final l10n = lookupAppLocalizations(locale);
          String heard(String id) =>
              tester.getSemantics(cancelControl(id)).label;
          expect(
            heard('tt-a'),
            l10n.toolsCancelTask(
              l10n.toolsTaskTitled(l10n.toolsTaskAcquire, 'Long Division'),
            ),
          );
          expect(
            heard('tt-b'),
            l10n.toolsCancelTask(
              l10n.toolsTaskTitled(l10n.toolsTaskBookMerge, 'The Book'),
            ),
          );
          expect(heard('tt-a'), isNot(heard('tt-b')));
          handle.dispose();
        },
      );
    }

    group('with items already staged', () {
      final staged = <(String, ToolTask)>[
        (
          'a download with items done',
          task('tt-a', activity: downloading(done: 2, total: 5)),
        ),
        ('a download with a percentage', task('tt-a', pct: 12)),
        (
          'a playlist sync with items done',
          task(
            'tt-a',
            type: 'playlist-sync',
            activity: downloading(done: 1, total: 4),
          ),
        ),
      ];

      for (final (name, running) in staged) {
        testWidgets(
          '$name asks first, and keeping it running cancels nothing',
          (tester) async {
            final repo = await show(tester, [running]);

            await tester.tap(cancelControl('tt-a'));
            await advance(tester);

            expect(repo.cancelToolTaskCalls, isEmpty);
            expect(find.text('Cancel this task?'), findsOneWidget);
            expect(
              find.textContaining('stay in the review queue'),
              findsOneWidget,
            );

            await tester.tap(find.text('Keep running'));
            await advance(tester);
            expect(find.text('Cancel this task?'), findsNothing);
            expect(repo.cancelToolTaskCalls, isEmpty);
            expect(cancelControl('tt-a'), findsOneWidget);
          },
        );
      }

      testWidgets('with activity, only items done say anything is staged', (
        tester,
      ) async {
        // A percentage carries the byte fraction of the item in hand,
        // which opened no entry.
        final repo = await show(tester, [
          task('tt-a', pct: 12, activity: downloading(done: 0, total: 3)),
        ]);

        await tester.tap(cancelControl('tt-a'));
        await advance(tester);

        expect(find.text('Cancel this task?'), findsNothing);
        expect(repo.cancelToolTaskCalls, ['tt-a']);
      });

      testWidgets('confirming posts the cancel', (tester) async {
        final repo = await show(tester, [
          task('tt-a', activity: downloading(done: 2, total: 5)),
        ]);

        await tester.tap(cancelControl('tt-a'));
        await advance(tester);
        await tester.tap(confirm());
        await advance(tester);

        expect(repo.cancelToolTaskCalls, ['tt-a']);
        expect(find.text('Cancel this task?'), findsNothing);
        expect(inRow('tt-a', 'Canceling'), findsOneWidget);
        expect(cancelControl('tt-a'), findsNothing);
      });
    });

    testWidgets('an answer that says it had already finished shows the row as '
        'it ended', (tester) async {
      final repo = await show(tester, [task('tt-a', type: 'genre-normalize')]);
      repo.toolTasksById['tt-a'] = task(
        'tt-a',
        type: 'genre-normalize',
        state: 'done',
      );

      await tester.tap(cancelControl('tt-a'));
      await advance(tester);

      expect(inRow('tt-a', 'Done'), findsOneWidget);
      expect(cancelControl('tt-a'), findsNothing);
      expect(dismissControl('tt-a'), findsOneWidget);
      expect(raisedMessage(tester), isNull);
    });

    testWidgets('a task that has started moving files says it cannot stop', (
      tester,
    ) async {
      final repo = await show(tester, [task('tt-a', type: 'book-merge')]);
      repo.cancelToolTaskError = const WaxDeckApiException(
        code: 'conflict',
        message: 'committed',
        statusCode: 409,
        params: {'reason': 'task-committed'},
      );

      await tester.tap(cancelControl('tt-a'));
      await advance(tester);

      expect(
        shellMessageText(raisedMessage(tester)),
        'It has started moving files, so it can no longer be canceled. It '
        'finishes, or puts them back, on its own.',
      );
      expect(cancelControl('tt-a'), findsOneWidget);
      expect(inRow('tt-a', 'Running'), findsOneWidget);
    });

    testWidgets('reads in Spanish', (tester) async {
      final es = AppLocalizationsEs();
      final repo = await show(tester, [
        task('tt-a', activity: downloading(done: 2, total: 5)),
        task('tt-b', type: 'book-merge'),
        task('tt-c', state: 'canceled'),
        task('tt-d', cancelRequested: true),
      ], locale: const Locale('es'));

      expect(inRow('tt-c', es.toolsStateTaskCanceled), findsOneWidget);
      expect(inRow('tt-d', es.toolsStateCanceling), findsOneWidget);

      await tester.tap(cancelControl('tt-a'));
      await advance(tester);
      expect(find.text(es.toolsCancelTitle), findsOneWidget);
      expect(find.text(es.toolsCancelBody), findsOneWidget);
      await tester.tap(find.text(es.toolsCancelKeep));
      await advance(tester);

      repo.cancelToolTaskError = const WaxDeckApiException(
        code: 'conflict',
        message: 'committed',
        statusCode: 409,
        params: {'reason': 'task-committed'},
      );
      await tester.tap(cancelControl('tt-b'));
      await advance(tester);
      expect(
        shellMessageText(raisedMessage(tester)),
        es.errorToolTaskCommitted,
      );
    });
  });

  group('canceling a library job', () {
    final started = DateTime.utc(2026, 9, 29, 10);
    Job job(
      String pid, {
      String kind = 'scan',
      String state = 'running',
      bool cancelable = false,
      bool cancelRequested = false,
      String? error,
    }) => Job(
      pid: pid,
      kind: kind,
      state: state,
      cancelable: cancelable,
      cancelRequested: cancelRequested,
      error: error,
      progress: state == 'running' ? 0.3 : null,
      startedAt: started,
      finishedAt: state == 'running' ? null : started,
    );

    Finder cancelControl(String pid) =>
        find.bySemanticsIdentifier(SemanticsIds.jobCancel(pid));
    Finder confirm() =>
        find.bySemanticsIdentifier(SemanticsIds.jobCancelConfirm);
    Finder inRow(String pid, String text) =>
        find.descendant(of: _job(pid), matching: find.text(text));

    // No pumpAndSettle: a running row's bar animates.
    Future<void> advance(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<(FakeRepository, ProviderContainer)> show(
      WidgetTester tester,
      List<Job> jobs, {
      Locale locale = const Locale('en'),
    }) async {
      final repo = FakeRepository(
        sessionState: const SessionState(authenticated: true, user: _admin),
      )..jobs = jobs;
      final container = appContainer(repo: repo);
      await mountApp(
        tester,
        const TasksScreen(),
        container: container,
        locale: locale,
      );
      await advance(tester);
      return (repo, container);
    }

    testWidgets('is offered on a running job the server can cancel only', (
      tester,
    ) async {
      await show(tester, [
        job('jb-scan', cancelable: true),
        job('jb-kind', kind: 'set-kind'),
        job('jb-winding', kind: 'enrich', cancelRequested: true),
        job('jb-done', state: 'done'),
        job('jb-canceled', state: 'canceled'),
      ]);

      expect(cancelControl('jb-scan'), findsOneWidget);
      expect(
        tester.getSemantics(cancelControl('jb-scan')).label,
        'Cancel Library scan',
      );
      for (final pid in ['jb-kind', 'jb-winding', 'jb-done', 'jb-canceled']) {
        expect(cancelControl(pid), findsNothing, reason: pid);
      }
      expect(inRow('jb-winding', 'Canceling'), findsOneWidget);
      expect(inRow('jb-canceled', 'Stopped'), findsOneWidget);
    });

    testWidgets('asks first, saying what stays, and keeping it posts nothing', (
      tester,
    ) async {
      final (repo, _) = await show(tester, [job('jb-a', cancelable: true)]);

      await tester.tap(cancelControl('jb-a'));
      await advance(tester);
      expect(find.text('Cancel this job?'), findsOneWidget);
      expect(
        find.text(
          'What it has done stays, and its next run carries on from '
          'there. A forced run does not resume: start it again.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Keep running'));
      await advance(tester);
      expect(find.text('Cancel this job?'), findsNothing);
      expect(repo.cancelJobCalls, isEmpty);
      expect(cancelControl('jb-a'), findsOneWidget);
    });

    testWidgets(
      'confirmed, the row reads Canceling, and Stopped once it ends',
      (tester) async {
        final (repo, container) = await show(tester, [
          job('jb-a', kind: 'analyze', cancelable: true),
        ]);
        final reads = repo.jobReads;

        await tester.tap(cancelControl('jb-a'));
        await advance(tester);
        await tester.tap(confirm());
        await advance(tester);

        expect(repo.cancelJobCalls, ['jb-a']);
        expect(
          repo.jobReads,
          reads,
          reason: 'the cancel\'s reply stands in until the next read',
        );
        expect(inRow('jb-a', 'Canceling'), findsOneWidget);
        expect(inRow('jb-a', 'Running · 30%'), findsNothing);
        expect(cancelControl('jb-a'), findsNothing);
        expect(
          find.descendant(
            of: _job('jb-a'),
            matching: find.byType(WaxProgressBar),
          ),
          findsOneWidget,
        );
        expect(raisedMessage(tester), isNull);

        // Its end is the job marker's news, which reads the list again. The
        // state says it stopped; the catalog's own sentence is not drawn,
        // while a failure keeps its error.
        repo.jobs = [
          job(
            'jb-a',
            kind: 'analyze',
            state: 'canceled',
            error: 'interrupted before it finished',
          ),
          job('jb-f', state: 'failed', error: 'the disk went away'),
        ];
        container.invalidate(adminJobsProvider);
        await advance(tester);
        expect(inRow('jb-a', 'Stopped'), findsOneWidget);
        expect(inRow('jb-a', 'interrupted before it finished'), findsNothing);
        expect(inRow('jb-f', 'the disk went away'), findsOneWidget);
        expect(cancelControl('jb-a'), findsNothing);
      },
    );

    testWidgets('the cancel\'s reply reads at once, before any reload', (
      tester,
    ) async {
      final (repo, _) = await show(tester, [
        job('jb-a', kind: 'enrich', cancelable: true),
        job('jb-b', cancelable: true),
      ]);
      final reads = repo.jobReads;

      repo.cancelJobAnswer = job('jb-a', kind: 'enrich', cancelRequested: true);
      await tester.tap(cancelControl('jb-a'));
      await advance(tester);
      await tester.tap(confirm());
      await advance(tester);
      expect(repo.jobReads, reads, reason: 'nothing read the list again');
      expect(inRow('jb-a', 'Canceling'), findsOneWidget);
      expect(cancelControl('jb-a'), findsNothing);

      // One that ended before the reply answers as it ended.
      repo.cancelJobAnswer = job(
        'jb-b',
        state: 'canceled',
        error: 'interrupted before it finished',
      );
      await tester.tap(cancelControl('jb-b'));
      await advance(tester);
      await tester.tap(confirm());
      await advance(tester);
      expect(repo.jobReads, reads, reason: 'nothing read the list again');
      expect(inRow('jb-b', 'Stopped'), findsOneWidget);
      expect(cancelControl('jb-b'), findsNothing);
    });

    testWidgets('a reply that lands after a newer read leaves that read', (
      tester,
    ) async {
      final (repo, container) = await show(tester, [
        job('jb-a', kind: 'enrich', cancelable: true),
      ]);
      final held = Completer<void>();
      repo
        ..cancelJobHeld = held.future
        ..cancelJobAnswer = job('jb-a', kind: 'enrich', cancelRequested: true);

      await tester.tap(cancelControl('jb-a'));
      await advance(tester);
      await tester.tap(confirm());
      await advance(tester);
      // The end's marker reads the list before the reply comes back.
      repo.jobs = [job('jb-a', kind: 'enrich', state: 'canceled')];
      container.invalidate(adminJobsProvider);
      await advance(tester);
      expect(inRow('jb-a', 'Stopped'), findsOneWidget);

      held.complete();
      await advance(tester);
      expect(inRow('jb-a', 'Stopped'), findsOneWidget);
      expect(inRow('jb-a', 'Canceling'), findsNothing);
    });

    testWidgets('a read the server answered before it took the cancel keeps '
        'Canceling when it lands after the reply; a read showing the end '
        'shows the end', (tester) async {
      final (repo, container) = await show(tester, [
        job('jb-a', kind: 'enrich', cancelable: true),
      ]);
      final held = Completer<void>();
      repo
        ..cancelJobHeld = held.future
        ..cancelJobAnswer = job('jb-a', kind: 'enrich', cancelRequested: true);

      await tester.tap(cancelControl('jb-a'));
      await advance(tester);
      await tester.tap(confirm());
      await advance(tester);
      // A read begun while the cancel is out, answered before the server
      // took it.
      final stale = repo.listJobsGate = Completer<void>();
      container.invalidate(adminJobsProvider);
      await advance(tester);
      held.complete();
      await advance(tester);
      expect(inRow('jb-a', 'Canceling'), findsOneWidget);

      stale.complete();
      repo.listJobsGate = null;
      await advance(tester);
      expect(inRow('jb-a', 'Canceling'), findsOneWidget);
      expect(cancelControl('jb-a'), findsNothing);

      repo.jobs = [job('jb-a', kind: 'enrich', state: 'canceled')];
      container.invalidate(adminJobsProvider);
      await advance(tester);
      expect(inRow('jb-a', 'Stopped'), findsOneWidget);
      expect(inRow('jb-a', 'Canceling'), findsNothing);
    });

    testWidgets('a job gone before its cancel leaves the list, unexplained', (
      tester,
    ) async {
      final (repo, _) = await show(tester, [
        job('jb-a', cancelable: true),
        job('jb-b', cancelable: true),
      ]);
      repo.cancelJobError = const WaxDeckApiException(
        code: 'not-found',
        message: 'no job with pid jb-a',
        statusCode: 404,
      );

      await tester.tap(cancelControl('jb-a'));
      await advance(tester);
      await tester.tap(confirm());
      await advance(tester);
      expect(_job('jb-a'), findsNothing);
      expect(_job('jb-b'), findsOneWidget);
      expect(raisedMessage(tester), isNull);
    });

    testWidgets('a cancel the server refuses says why and keeps the control', (
      tester,
    ) async {
      final (repo, _) = await show(tester, [job('jb-a', cancelable: true)]);
      repo.cancelJobError = const WaxDeckApiException(
        code: 'conflict',
        message: 'not held',
        statusCode: 409,
        params: {'reason': 'job-not-held'},
      );

      await tester.tap(cancelControl('jb-a'));
      await advance(tester);
      await tester.tap(confirm());
      await advance(tester);

      expect(
        shellMessageText(raisedMessage(tester)),
        'This server holds no way to stop this job: it was started from the '
        'command line, or it runs inside other work. It runs to its end.',
      );
      expect(cancelControl('jb-a'), findsOneWidget);
    });

    testWidgets('reads in Spanish', (tester) async {
      final es = AppLocalizationsEs();
      final (repo, _) = await show(tester, [
        job('jb-a', cancelable: true),
        job('jb-b', kind: 'enrich', cancelRequested: true),
      ], locale: const Locale('es'));

      expect(inRow('jb-b', es.toolsStateCanceling), findsOneWidget);
      await tester.tap(cancelControl('jb-a'));
      await advance(tester);
      expect(find.text(es.toolsJobCancelTitle), findsOneWidget);
      expect(find.text(es.toolsJobCancelBody), findsOneWidget);
      repo.cancelJobError = const WaxDeckApiException(
        code: 'conflict',
        message: 'runs to its end',
        statusCode: 409,
        params: {'reason': 'job-runs-to-end'},
      );
      await tester.tap(find.text(es.toolsJobCancelAction));
      await advance(tester);
      expect(shellMessageText(raisedMessage(tester)), es.errorJobRunsToEnd);
    });
  });
}
