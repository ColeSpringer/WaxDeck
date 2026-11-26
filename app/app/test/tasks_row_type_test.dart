import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/l10n/formats.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/tools/tasks_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'bundled_type.dart';
import 'fakes.dart';

Finder _row(String id) => find.bySemanticsIdentifier(SemanticsIds.taskRow(id));

Finder _inRow(String id, String text) =>
    find.descendant(of: _row(id), matching: find.text(text));

const _admin = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  username: 'admin',
  roles: ['admin'],
);

/// The tasks screen over [tasks] (and [jobs], for an administrator), mounted
/// and read once.
Future<void> _show(
  WidgetTester tester,
  List<ToolTask> tasks, {
  List<Job> jobs = const <Job>[],
  Locale locale = const Locale('en'),
}) async {
  final repo = jobs.isEmpty
      ? FakeRepository()
      : (FakeRepository(
          sessionState: const SessionState(authenticated: true, user: _admin),
        )..jobs = jobs);
  for (final task in tasks) {
    repo.toolTasksById[task.id] = task;
  }
  await mountApp(
    tester,
    const TasksScreen(),
    container: appContainer(repo: repo),
    locale: locale,
  );
  await tester.pump();
  await tester.pump();
}

ToolTask _acquire(
  String id, {
  String? title,
  String? url,
  List<String>? entries,
  int? results,
  bool truncated = false,
  String state = 'done',
  DateTime? createdAt,
  DateTime? finishedAt,
}) => ToolTask(
  id: id,
  type: 'acquire',
  state: state,
  itemTitle: title,
  resultPids: [
    for (var i = 0; i < (results ?? entries?.length ?? 0); i++) 'rv-$id$i',
  ],
  createdAt: createdAt ?? clock.now().subtract(const Duration(hours: 3)),
  finishedAt: finishedAt ?? clock.now().subtract(const Duration(hours: 2)),
  summary: {
    'url': ?url,
    'source': 'video',
    'entries': ?entries,
    if (truncated) 'truncated': true,
  },
);

// A task row's status at large type on a narrow window, in the faces the
// app ships: the longest words it says (Needs attention, Running with its
// percentage) stay whole inside the row, in English and Spanish.
void main() {
  setUpAll(loadBundledType);

  for (final (size, scale) in const [
    (Size(360, 640), 3.0),
    (Size(320, 480), 2.0),
  ]) {
    for (final locale in const [Locale('en'), Locale('es')]) {
      testWidgets('a row keeps its status whole at ${size.width.round()} '
          'wide, text x$scale (${locale.languageCode})', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final repo = FakeRepository();
        repo.toolTasksById['tt-p'] = ToolTask(
          id: 'tt-p',
          type: 'book-merge',
          state: 'parked',
          itemTitle: 'The Merge Book',
          error: 'stopped: its last 3 runs ended with the server',
          createdAt: DateTime.utc(2026, 7, 1, 2),
          finishedAt: DateTime.utc(2026, 7, 1, 3),
        );
        repo.toolTasksById['tt-r'] = ToolTask(
          id: 'tt-r',
          type: 'book-split',
          state: 'running',
          itemTitle: 'The Split Book',
          progressPct: 100,
          createdAt: DateTime.utc(2026, 7, 1, 1),
        );
        await mountApp(
          tester,
          const TasksScreen(),
          container: appContainer(repo: repo),
          locale: locale,
        );
        await tester.pump();
        await tester.pump();

        expect(tester.takeException(), isNull);
        final l10n = lookupAppLocalizations(locale);
        for (final (id, status) in [
          ('tt-p', l10n.toolsStateParked),
          ('tt-r', l10n.toolsStateRunningPct(100)),
        ]) {
          await tester.scrollUntilVisible(_row(id), 100);
          final row = tester.getRect(_row(id));
          final label = tester.getRect(
            find.descendant(of: _row(id), matching: find.text(status)),
          );
          expect(row.intersect(label), label, reason: '$status in its row');
          expect(label.right, lessThanOrEqualTo(size.width));
        }
      });
    }
  }

  group('what a row is for', () {
    testWidgets('two finished downloads read differently', (tester) async {
      await _show(tester, [
        _acquire('tt-a', title: 'Long Division', url: 'https://x.test/a'),
        _acquire('tt-b', title: 'Plainsong', url: 'https://x.test/b'),
      ]);
      expect(_inRow('tt-a', 'URL download: Long Division'), findsOneWidget);
      expect(_inRow('tt-b', 'URL download: Plainsong'), findsOneWidget);
      expect(_inRow('tt-a', 'URL download: Plainsong'), findsNothing);
    });

    testWidgets('an untitled download shows its link as host and path', (
      tester,
    ) async {
      await _show(tester, [
        _acquire(
          'tt-a',
          url: 'https://music.example.com/watch/clip/?v=abc#t=4',
        ),
        _acquire('tt-b', title: 'Plainsong', url: 'https://x.test/b'),
      ]);
      expect(_inRow('tt-a', 'URL download'), findsOneWidget);
      expect(
        _inRow('tt-a', 'music.example.com/watch/clip?v=abc'),
        findsOneWidget,
      );
      // A titled one names itself and leaves the link out.
      expect(_inRow('tt-b', 'x.test/b'), findsNothing);
    });

    testWidgets('an untitled link keeps its port', (tester) async {
      await _show(tester, [
        _acquire('tt-a', url: 'http://127.0.0.1:4422/playlist'),
      ]);
      expect(_inRow('tt-a', '127.0.0.1:4422/playlist'), findsOneWidget);
    });

    testWidgets('untitled links to one page differ by their query, minus the '
        'scheme and www', (tester) async {
      await _show(tester, [
        _acquire('tt-a', url: 'https://www.youtube.com/watch?v=aaaaaaaaaaa'),
        _acquire(
          'tt-b',
          url: 'https://www.youtube.com/watch?v=bbbbbbbbbbb&list=PL1',
        ),
      ]);
      expect(_inRow('tt-a', 'youtube.com/watch?v=aaaaaaaaaaa'), findsOneWidget);
      expect(
        _inRow('tt-b', 'youtube.com/watch?v=bbbbbbbbbbb&list=PL1'),
        findsOneWidget,
      );
    });

    testWidgets('a finished download lists up to three entry titles', (
      tester,
    ) async {
      await _show(tester, [
        _acquire('tt-a', title: 'Mix', entries: ['One', 'Two', 'Three']),
      ]);
      expect(_inRow('tt-a', '3 ready for review'), findsOneWidget);
      for (final t in ['One', 'Two', 'Three']) {
        expect(_inRow('tt-a', t), findsOneWidget, reason: t);
      }
      expect(find.textContaining('more'), findsNothing);
    });

    testWidgets('past three it says how many more, and truncation says so', (
      tester,
    ) async {
      await _show(tester, [
        _acquire(
          'tt-a',
          title: 'Mix',
          entries: ['One', 'Two', 'Three', 'Four', 'Five'],
          truncated: true,
        ),
      ]);
      expect(_inRow('tt-a', '5 ready for review'), findsOneWidget);
      for (final t in ['One', 'Two', 'Three']) {
        expect(_inRow('tt-a', t), findsOneWidget, reason: t);
      }
      expect(_inRow('tt-a', 'Four'), findsNothing);
      expect(_inRow('tt-a', 'and 2 more'), findsOneWidget);
      expect(_inRow('tt-a', 'Only the first 200 were taken'), findsOneWidget);
    });

    testWidgets('"and N more" counts what the task opened, not the titles', (
      tester,
    ) async {
      await _show(tester, [
        // Opened 6, named 4: three drawn, three unseen.
        _acquire('tt-a', entries: ['A', 'B', 'C', 'D'], results: 6),
        // Opened 5, named only one: one drawn, four unseen.
        _acquire('tt-b', entries: ['E'], results: 5),
        // Opened 2, named 4: nothing left over to count.
        _acquire('tt-c', entries: ['F', 'G', 'H', 'I'], results: 2),
        // Opened 5, no titles at all: no "more" under nothing.
        _acquire('tt-d', entries: [], results: 5),
      ]);
      expect(_inRow('tt-a', 'and 3 more'), findsOneWidget);
      expect(_inRow('tt-b', 'and 4 more'), findsOneWidget);
      expect(
        find.descendant(
          of: _row('tt-c'),
          matching: find.textContaining('more'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: _row('tt-d'),
          matching: find.textContaining('more'),
        ),
        findsNothing,
      );
    });

    testWidgets('a playlist sync names its playlist', (tester) async {
      await _show(tester, [
        ToolTask(
          id: 'tt-p',
          type: 'playlist-sync',
          state: 'running',
          itemPid: 'pl-01ABC',
          itemTitle: 'Road Trip',
          createdAt: clock.now(),
        ),
      ]);
      expect(_inRow('tt-p', 'Playlist sync: Road Trip'), findsOneWidget);
      expect(_inRow('tt-p', 'pl-01ABC'), findsOneWidget);
    });

    testWidgets('an import dry run with no target still says so', (
      tester,
    ) async {
      await _show(tester, [
        ToolTask(
          id: 'tt-i',
          type: 'import-subsonic',
          state: 'queued',
          createdAt: clock.now(),
          summary: const {'dryRun': true},
        ),
        ToolTask(
          id: 'tt-j',
          type: 'import-subsonic',
          state: 'queued',
          createdAt: clock.now(),
          summary: const {'dryRun': false},
        ),
      ]);
      expect(_inRow('tt-i', 'Dry run'), findsOneWidget);
      expect(
        find.descendant(
          of: _row('tt-j'),
          matching: find.textContaining('Dry run'),
        ),
        findsNothing,
      );
    });

    for (final locale in const [Locale('en'), Locale('es')]) {
      testWidgets('the new lines fit at text x2 (${locale.languageCode})', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _show(tester, [
          _acquire(
            'tt-a',
            title: 'A Rather Long Playlist Title That Keeps Going',
            entries: [
              'A very long entry title that would run past the edge of the row',
              'Two',
              'Three',
              'Four',
            ],
            truncated: true,
          ),
          ToolTask(
            id: 'tt-i',
            type: 'import-jellyfin',
            state: 'queued',
            createdAt: clock.now(),
            summary: const {
              'target': 'An Account With A Very Long Display Name',
              'dryRun': true,
            },
          ),
        ], locale: locale);
        expect(tester.takeException(), isNull);
        for (final id in ['tt-a', 'tt-i']) {
          await tester.scrollUntilVisible(_row(id), 100);
          final row = tester.getRect(_row(id));
          for (final text
              in find
                  .descendant(of: _row(id), matching: find.byType(Text))
                  .evaluate()) {
            final rect = tester.getRect(
              find.byElementPredicate((e) => e == text),
            );
            expect(rect.right, lessThanOrEqualTo(row.right), reason: id);
          }
        }
      });
    }

    testWidgets('a download that was not cut short says nothing of it', (
      tester,
    ) async {
      await _show(tester, [
        _acquire('tt-a', title: 'Mix', entries: ['One']),
      ]);
      expect(find.textContaining('first 200'), findsNothing);
    });

    testWidgets('the other kinds say what they were queued with', (
      tester,
    ) async {
      final at = clock.now();
      ToolTask task(String id, String type, Map<String, Object?> summary) =>
          ToolTask(
            id: id,
            type: type,
            state: 'queued',
            createdAt: at,
            summary: summary,
          );
      await _show(tester, [
        task('tt-g', 'genre-normalize', {'dryRun': true}),
        task('tt-n', 'genre-normalize', {'dryRun': false}),
        task('tt-i', 'import-jellyfin', {'target': 'Alice', 'dryRun': false}),
        task('tt-d', 'import-spotify', {'target': 'Bob', 'dryRun': true}),
        task('tt-h', 'health-fix', {'rule': 'path-mismatch', 'scoped': 3}),
        task('tt-o', 'health-fix', {'rule': 'path-mismatch', 'scoped': 1}),
      ]);
      expect(_inRow('tt-g', 'Genre clean-up (preview)'), findsOneWidget);
      expect(_inRow('tt-n', 'Genre clean-up'), findsOneWidget);
      expect(_inRow('tt-i', 'Into Alice'), findsOneWidget);
      expect(_inRow('tt-d', 'Dry run into Bob'), findsOneWidget);
      expect(_inRow('tt-h', 'For 3 chosen items'), findsOneWidget);
      expect(_inRow('tt-o', 'For 1 chosen item'), findsOneWidget);
    });

    testWidgets('every row says when, queued or finished', (tester) async {
      final now = clock.now();
      await _show(tester, [
        ToolTask(
          id: 'tt-q',
          type: 'catalog-repair',
          state: 'queued',
          createdAt: now.subtract(const Duration(minutes: 5)),
        ),
        ToolTask(
          id: 'tt-r',
          type: 'catalog-repair',
          state: 'running',
          createdAt: now.subtract(const Duration(minutes: 12)),
        ),
        ToolTask(
          id: 'tt-f',
          type: 'catalog-repair',
          state: 'failed',
          createdAt: now.subtract(const Duration(days: 3)),
          finishedAt: now.subtract(const Duration(hours: 2)),
        ),
        ToolTask(
          id: 'tt-n',
          type: 'catalog-repair',
          state: 'queued',
          createdAt: now.subtract(const Duration(seconds: 10)),
        ),
      ]);
      expect(_inRow('tt-q', 'queued 5 min ago'), findsOneWidget);
      expect(_inRow('tt-r', 'queued 12 min ago'), findsOneWidget);
      expect(_inRow('tt-f', 'finished 2 h ago'), findsOneWidget);
      expect(_inRow('tt-n', 'queued just now'), findsOneWidget);
    });

    testWidgets('the time follows the clock without another fetch', (
      tester,
    ) async {
      await _show(tester, [
        ToolTask(
          id: 'tt-q',
          type: 'catalog-repair',
          state: 'queued',
          createdAt: clock.now().subtract(
            const Duration(minutes: 4, seconds: 50),
          ),
        ),
      ]);
      expect(_inRow('tt-q', 'queued 4 min ago'), findsOneWidget);
      await tester.pump(const Duration(seconds: 11));
      expect(_inRow('tt-q', 'queued 5 min ago'), findsOneWidget);
      await tester.pump(const Duration(hours: 1));
      expect(_inRow('tt-q', 'queued 1 h ago'), findsOneWidget);
    });

    testWidgets('reads in Spanish', (tester) async {
      await _show(tester, [
        _acquire(
          'tt-a',
          entries: ['One', 'Two', 'Three', 'Four'],
          url: 'https://x.test/a/b',
        ),
      ], locale: const Locale('es'));
      final es = lookupAppLocalizations(const Locale('es'));
      final ago = es.relativeSpaced(
        clock.now().subtract(const Duration(hours: 2)),
      );
      expect(_inRow('tt-a', es.toolsTimeFinished(ago)), findsOneWidget);
      expect(_inRow('tt-a', es.toolsEntriesMore(1)), findsOneWidget);
      expect(_inRow('tt-a', 'x.test/a/b'), findsOneWidget);
    });

    testWidgets('untitled downloads tell their cancel controls apart', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _show(tester, [
        _acquire(
          'tt-a',
          url: 'https://www.youtube.com/watch?v=aaaaaaaaaaa',
          state: 'running',
        ),
        _acquire(
          'tt-b',
          url: 'https://www.youtube.com/watch?v=bbbbbbbbbbb',
          state: 'running',
        ),
      ]);
      String heard(String id) => tester
          .getSemantics(find.bySemanticsIdentifier(SemanticsIds.taskCancel(id)))
          .label;
      expect(heard('tt-a'), contains('youtube.com/watch?v=aaaaaaaaaaa'));
      expect(heard('tt-b'), contains('youtube.com/watch?v=bbbbbbbbbbb'));
      handle.dispose();
    });

    testWidgets('a library job says when too', (tester) async {
      final now = clock.now();
      await _show(
        tester,
        const <ToolTask>[],
        jobs: [
          Job(
            pid: 'jb-run',
            kind: 'scan',
            state: 'running',
            startedAt: now.subtract(const Duration(minutes: 3)),
          ),
          Job(
            pid: 'jb-done',
            kind: 'scan',
            state: 'done',
            startedAt: now.subtract(const Duration(hours: 2, minutes: 5)),
            finishedAt: now.subtract(const Duration(hours: 2)),
          ),
        ],
      );
      Finder inJob(String pid, String text) => find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.jobRow(pid)),
        matching: find.text(text),
      );
      expect(inJob('jb-run', 'started 3 min ago'), findsOneWidget);
      expect(inJob('jb-done', 'finished 2 h ago'), findsOneWidget);
      await tester.pump(const Duration(minutes: 2));
      expect(inJob('jb-run', 'started 5 min ago'), findsOneWidget);
    });
  });
}
