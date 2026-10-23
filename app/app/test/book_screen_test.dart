import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/books/book_screen.dart';
import 'package:waxdeck/src/books/books_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/tools/tasks_screen.dart';
import 'package:waxdeck/src/tools/tool_tasks_provider.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

const bookPid = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';

Widget _host(FakeRepository repo, FakeEngine engine) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    audioEngineProvider.overrideWithValue(engine),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
  ],
  child: routedHost(const BookScreen(pid: bookPid)),
);

FakeRepository _repo() => FakeRepository()
  ..books[bookPid] = testBook(
    bookPid,
    durationMs: 3600000,
    chapters: const [
      ChapterMark(index: 0, title: 'An Unexpected Party', startMs: 0),
      ChapterMark(index: 1, title: 'Roast Mutton', startMs: 600000),
    ],
  );

/// A single-file book with a chapter mark inside it: one a split can cut.
BookDetail _splittableBook() => testBook(
  bookPid,
  chapters: const [
    ChapterMark(index: 0, title: 'One', startMs: 0),
    ChapterMark(index: 1, title: 'Two', startMs: 600000),
  ],
);

/// Taps the row or control carrying [id], scrolling to it first: the
/// book screen is one long list and its chapters sit below the fold.
Future<void> _tap(WidgetTester tester, String id) async {
  final finder = _byId(id).first;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// A server the book read never reaches.
class _UnreachableBooks extends FakeRepository {
  @override
  Future<BookDetail> getBook(String pid) async =>
      throw const WaxDeckApiException(
        code: 'transport',
        message: 'connection refused',
      );
}

/// An administrator's repository that counts the task list's reads.
class _TaskListings extends FakeRepository {
  _TaskListings(BookDetail book) : super(sessionState: _adminSession) {
    books[bookPid] = book;
  }

  var listings = 0;

  @override
  Future<ToolTaskPage> listToolTasks({String? cursor, int? limit}) {
    listings++;
    return super.listToolTasks(cursor: cursor, limit: limit);
  }
}

Finder _byId(String id) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.identifier == id,
);

void main() {
  test('a pid that is no longer a book settles at once', () async {
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(FakeRepository())],
    );
    addTearDown(container.dispose);
    final sub = container.listen(bookDetailProvider('bk-gone'), (_, _) {});
    addTearDown(sub.close);
    await expectLater(
      container
          .read(bookDetailProvider('bk-gone').future)
          .timeout(const Duration(seconds: 2)),
      throwsA(isA<WaxDeckApiException>()),
    );
  });

  group('a book that cannot be shown', () {
    testWidgets('one that does not exist says so at once, with no retry', (
      tester,
    ) async {
      // A pid that stopped being a book answers 404 every time. The
      // backoff ladder held this screen on a skeleton for half a minute
      // and then offered to ask again.
      await tester.pumpWidget(_host(FakeRepository(), FakeEngine()));
      await tester.pump();
      await tester.pump();

      expect(find.text('Could not load this book'), findsOneWidget);
      expect(find.text('That is not here any more.'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(find.byType(SkeletonShapes), findsNothing);
    });

    testWidgets('a slow read shows the skeleton, not an error', (tester) async {
      final repo = _repo()..getBookGate = Completer<void>();
      await tester.pumpWidget(_host(repo, FakeEngine()));
      await tester.pump();

      expect(find.byType(SkeletonShapes), findsOneWidget);
      expect(find.byType(ErrorState), findsNothing);
      repo.getBookGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('An Unexpected Party'), findsOneWidget);
    });

    testWidgets('a transport failure offers Try again', (tester) async {
      // Unlike a refusal, a dropped connection is worth asking again.
      await tester.pumpWidget(_host(_UnreachableBooks(), FakeEngine()));
      await tester.pump();
      await tester.pump();

      expect(find.text('Could not load this book'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byType(SkeletonShapes), findsNothing);
      // Riverpod keeps asking on its own; the scope going away ends it.
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('renders the header, the people, and the chapters', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_repo(), FakeEngine()));
    await tester.pumpAndSettle();

    expect(find.text('There And Back Again'), findsWidgets);
    expect(
      find.textContaining('By B. Baggins'),
      findsOneWidget,
      reason: 'the header names the author',
    );
    expect(find.textContaining('Read by Frodo'), findsOneWidget);
    expect(find.text('An Unexpected Party'), findsOneWidget);
    expect(find.text('Roast Mutton'), findsOneWidget);
    expect(_byId(SemanticsIds.chapter(0)), findsOneWidget);
    expect(_byId(SemanticsIds.chapter(1)), findsOneWidget);
  });

  testWidgets('the header says how long the book is', (tester) async {
    await tester.pumpWidget(_host(_repo(), FakeEngine()));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 hour'), findsOneWidget);
  });

  testWidgets('Resume names the chapter it will land in', (tester) async {
    final repo = _repo()
      ..bookResumes[bookPid] = const BookResume(
        positionMs: 720000,
        chapter: ChapterMark(index: 1, title: 'Roast Mutton', startMs: 600000),
      );
    final engine = FakeEngine(mediaDuration: const Duration(hours: 1));
    await tester.pumpWidget(_host(repo, engine));
    await tester.pumpAndSettle();

    expect(find.text('Resume Roast Mutton'), findsOneWidget);
    // And the caption says how far in, so the verb is not the only clue.
    expect(find.textContaining('20 percent'), findsOneWidget);

    await _tap(tester, SemanticsIds.bookResume);
    expect(engine.position, const Duration(minutes: 12));
    expect(engine.playing, isTrue);
  });

  testWidgets('an unstarted book offers Play, not Resume', (tester) async {
    await tester.pumpWidget(_host(_repo(), FakeEngine()));
    await tester.pumpAndSettle();
    expect(find.text('Play'), findsOneWidget);
    expect(find.textContaining('Resume'), findsNothing);
  });

  testWidgets('a finished book plays from the top, not from its end', (
    tester,
  ) async {
    final repo = _repo()
      ..playPositions[bookPid] = 3600000
      ..finishedPids.add(bookPid)
      ..bookResumes[bookPid] = const BookResume(positionMs: 3600000);
    final engine = FakeEngine(mediaDuration: const Duration(hours: 1));
    await tester.pumpWidget(_host(repo, engine));
    await tester.pumpAndSettle();

    expect(find.text('Play'), findsOneWidget);
    await _tap(tester, SemanticsIds.bookResume);
    expect(engine.position, Duration.zero);
  });

  testWidgets('tapping a chapter starts playback at its start', (tester) async {
    final engine = FakeEngine(mediaDuration: const Duration(hours: 1));
    await tester.pumpWidget(_host(_repo(), engine));
    await tester.pumpAndSettle();

    await _tap(tester, SemanticsIds.chapter(1));

    expect(engine.position, const Duration(minutes: 10));
    expect(engine.playing, isTrue);
  });

  testWidgets('a tapped chapter selects itself while the session plays', (
    tester,
  ) async {
    // The screen is the tap's own feedback now that play lands in the
    // dock: the selected row follows the live session position, where
    // the stored resume lags until a checkpoint writes it back.
    bool selectedOf(String id) =>
        (tester.widget(_byId(id).first) as Semantics).properties.selected ??
        false;
    final engine = FakeEngine(mediaDuration: const Duration(hours: 1));
    await tester.pumpWidget(_host(_repo(), engine));
    await tester.pumpAndSettle();

    expect(selectedOf(SemanticsIds.chapter(1)), isFalse);

    await _tap(tester, SemanticsIds.chapter(1));

    expect(selectedOf(SemanticsIds.chapter(1)), isTrue);
    expect(selectedOf(SemanticsIds.chapter(0)), isFalse);
  });

  testWidgets('the settings sheet PUTs the per-book settings', (tester) async {
    final repo = _repo();
    await tester.pumpWidget(_host(repo, FakeEngine()));
    await tester.pumpAndSettle();

    await _tap(tester, SemanticsIds.bookSettingsOpen);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('book-settings-trim')),
        matching: find.byType(WaxSwitch),
      ),
    );
    await tester.pump();
    await _tap(tester, SemanticsIds.bookSettingsSave);

    expect(repo.putBookSettingsCalls, hasLength(1));
    final saved = repo.putBookSettingsCalls.single;
    expect(saved.pid, bookPid);
    expect(saved.settings.trimSilence, isTrue);
    expect(saved.settings.speed, closeTo(1.0, 0.001));
  });

  testWidgets('a multi-file book says so, and a single-file one does not', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        FakeRepository()..books[bookPid] = testBook(bookPid, partCount: 3),
        FakeEngine(),
      ),
    );
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.bookPartsNote), findsOneWidget);
    expect(find.textContaining('3 files'), findsOneWidget);

    await tester.pumpWidget(_host(_repo(), FakeEngine()));
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.bookPartsNote), findsNothing);
  });

  testWidgets('the edition rows are behind an expander', (tester) async {
    await tester.pumpWidget(
      _host(
        FakeRepository()
          ..books[bookPid] = testBook(
            bookPid,
            publisher: 'Bree Press',
            isbn: '9780000000001',
          ),
        FakeEngine(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bree Press'), findsNothing);
    await _tap(tester, SemanticsIds.bookEdition);
    expect(find.text('Bree Press'), findsOneWidget);
    expect(find.text('9780000000001'), findsOneWidget);
  });

  group('the overflow', () {
    Future<void> openOverflow(WidgetTester tester) =>
        _tap(tester, SemanticsIds.bookOverflow);

    testWidgets('marks the book finished at its own end, with an undo', (
      tester,
    ) async {
      final repo = _repo()..playPositions[bookPid] = 600000;
      await tester.pumpWidget(_host(repo, FakeEngine()));
      await tester.pumpAndSettle();

      await openOverflow(tester);
      await _tap(tester, SemanticsIds.bookMarkFinished);

      expect(repo.putPlayStateCalls.last.positionMs, 3600000);
      expect(shellMessageText(raisedMessage(tester)), 'Marked finished');
      expect(raisedMessage(tester)!.actionLabel, 'Undo');
      expect(raisedMessage(tester)!.persist, isTrue);

      // The undo puts back where the listener actually was, which is the
      // position read before the write rather than zero - and it rides
      // the same request as the flags, so a completion checkpoint from
      // another device cannot land between the two.
      await pressRaisedAction(tester);
      expect(repo.setPlayedCalls.last.positionMs, 600000);
      expect(repo.playPositions[bookPid], 600000);
      // No second write: the mark's own position write is still the last
      // one this test made.
      expect(repo.putPlayStateCalls.last.positionMs, 3600000);

      // And the flags with it. Writing the position back alone left the
      // book finished forever - the completion rules only ever mark -
      // so the mis-tap put it in the Finished shelf with the hub's
      // unfinished filter hiding it. The play count the mark added goes
      // too, rather than being left standing.
      expect(repo.setPlayedCalls.last.played, isFalse);
      expect(repo.setPlayedCalls.last.finished, isFalse);
      expect(repo.setPlayedCalls.last.playCount, 0);
      expect(repo.finishedPids, isNot(contains(bookPid)));
    });

    testWidgets('a server that ignores the position gets the old write', (
      tester,
    ) async {
      // One too old for `positionMs` answers with the position it kept,
      // which is how the client tells the field was dropped rather than
      // applied. The fallback is then the old path whole - position,
      // then the flags again - because a checkpoint re-derives
      // completion from the position it writes, so a restored
      // past-threshold position with nothing after it would re-mark
      // what the undo just cleared.
      final repo = _repo()
        ..playPositions[bookPid] = 600000
        ..setPlayedIgnoresPosition = true;
      await tester.pumpWidget(_host(repo, FakeEngine()));
      await tester.pumpAndSettle();

      await openOverflow(tester);
      await _tap(tester, SemanticsIds.bookMarkFinished);
      final marked = repo.setPlayedCalls.length;
      await pressRaisedAction(tester);

      final undo = repo.setPlayedCalls.skip(marked).toList();
      expect(undo, hasLength(2), reason: 'the atomic try, then the old pair');
      expect(undo.first.positionMs, 600000);
      // The flag write is the one nothing runs after.
      expect(undo.last.positionMs, isNull);
      expect(undo.last.played, isFalse);
      expect(undo.last.finished, isFalse);
      expect(repo.putPlayStateCalls.last.positionMs, 600000);
      expect(repo.playPositions[bookPid], 600000);
      expect(repo.finishedPids, isNot(contains(bookPid)));
    });

    testWidgets('a refused flag write still puts the position back', (
      tester,
    ) async {
      // Two writes in one try meant any failure of the first skipped the
      // second and landed in an empty catch: the toast dismissed and
      // nothing moved at all, where before this verb existed the
      // position at least went back.
      final repo = _repo()..playPositions[bookPid] = 600000;
      await tester.pumpWidget(_host(repo, FakeEngine()));
      await tester.pumpAndSettle();

      await openOverflow(tester);
      await _tap(tester, SemanticsIds.bookMarkFinished);
      repo.playStateError = const WaxDeckApiException(
        statusCode: 503,
        code: 'unavailable',
        message: 'the catalog is busy',
      );
      await pressRaisedAction(tester);

      expect(tester.takeException(), isNull);
      expect(repo.putPlayStateCalls.last.positionMs, 600000);
    });

    testWidgets('undoing a book that was already played keeps its count', (
      tester,
    ) async {
      // The catalog refuses a played row with a zero count, so an undo
      // over a book somebody had finished before must not send one.
      final repo = _repo()
        ..playPositions[bookPid] = 600000
        ..finishedPids.add(bookPid);
      await tester.pumpWidget(_host(repo, FakeEngine()));
      await tester.pumpAndSettle();

      await openOverflow(tester);
      await _tap(tester, SemanticsIds.bookMarkFinished);
      await pressRaisedAction(tester);

      expect(repo.setPlayedCalls.last.played, isTrue);
      expect(repo.setPlayedCalls.last.finished, isTrue);
      expect(repo.setPlayedCalls.last.playCount, isNot(0));
    });

    testWidgets('the undo outlives the screen that offered it', (tester) async {
      // The toast is the shell's: it stays up while the
      // visitor walks away, so the undo has to run through the provider
      // container rather than through this row's `WidgetRef`, which is
      // dead the moment its element is disposed. The comment said so
      // before the code did.
      final repo = _repo()..playPositions[bookPid] = 600000;
      await tester.pumpWidget(_host(repo, FakeEngine()));
      await tester.pumpAndSettle();

      await openOverflow(tester);
      await _tap(tester, SemanticsIds.bookMarkFinished);
      expect(repo.putPlayStateCalls.last.positionMs, 3600000);

      // Replace the screen; the shell's toast stays up.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            audioEngineProvider.overrideWithValue(FakeEngine()),
            credentialStoreProvider.overrideWithValue(
              InMemoryCredentialStore(),
            ),
          ],
          child: routedHost(const BookScreen(pid: 'bk-somewhere-else')),
        ),
      );
      await tester.pumpAndSettle();

      // Whatever is on screen, the write still lands.
      await pressRaisedAction(tester);
      expect(tester.takeException(), isNull);
      expect(repo.setPlayedCalls.last.positionMs, 600000);
      expect(repo.playPositions[bookPid], 600000);
    });

    testWidgets('starts the book over from zero', (tester) async {
      final repo = _repo()..playPositions[bookPid] = 600000;
      await tester.pumpWidget(_host(repo, FakeEngine()));
      await tester.pumpAndSettle();

      await openOverflow(tester);
      await _tap(tester, SemanticsIds.bookStartOver);

      expect(repo.putPlayStateCalls.last.positionMs, 0);
      expect(shellMessageText(raisedMessage(tester)), 'Back to the beginning');
    });

    testWidgets('an admin merges a multi-file book, asked first', (
      tester,
    ) async {
      final repo = _adminRepo(testBook(bookPid, partCount: 3));
      await tester.pumpWidget(_host(repo, FakeEngine()));
      await tester.pumpAndSettle();

      await openOverflow(tester);
      expect(_byId(SemanticsIds.bookSplit), findsNothing);
      await _tap(tester, SemanticsIds.bookMerge);

      // Nothing is queued until the dialog is answered.
      expect(find.text('Merge 3 files into one?'), findsOneWidget);
      expect(repo.mergeBookCalls, isEmpty);
      await _tap(tester, SemanticsIds.bookMergeKeep);
      await _tap(tester, SemanticsIds.bookMergeConfirm);

      expect(repo.mergeBookCalls.single.pid, bookPid);
      expect(repo.mergeBookCalls.single.keepOriginals, isTrue);
      expect(raisedMessage(tester)!.actionLabel, 'Tasks');
      expect(raisedMessage(tester)!.persist, isTrue);
    });

    testWidgets('a merge left alone trashes the parts', (tester) async {
      final repo = _adminRepo(testBook(bookPid, partCount: 2));
      await tester.pumpWidget(_host(repo, FakeEngine()));
      await tester.pumpAndSettle();

      await openOverflow(tester);
      await _tap(tester, SemanticsIds.bookMerge);
      await _tap(tester, SemanticsIds.bookMergeConfirm);

      expect(repo.mergeBookCalls.single.keepOriginals, isFalse);
    });

    for (final (name, refusal, sentence) in [
      (
        'a copy elsewhere',
        const WaxDeckApiException(
          code: 'conflict',
          message:
              'the book has a copy, Ada/Book/part 1.m4b in the Spare library',
          statusCode: 409,
          params: {
            'reason': 'copy-elsewhere',
            'copy': 'Ada/Book/part 1.m4b',
            'library': 'Spare',
          },
        ),
        'This book has a copy at Ada/Book/part 1.m4b in the Spare library, '
            'which would be left as the book. Delete the copy, or keep the '
            'originals.',
      ),
      (
        'a merge still at work',
        const WaxDeckApiException(
          code: 'conflict',
          message: 'a merge or split of this book has not finished yet',
          statusCode: 409,
          params: {'reason': 'task-running', 'task': 'tk-1'},
        ),
        'A merge or split of this is still at work. Try again once it has '
            'finished.',
      ),
      (
        'a merge or split that stopped and waits in Tasks',
        const WaxDeckApiException(
          code: 'conflict',
          message:
              'a merge or split of this book stopped and needs attention: '
              'clear it in Tasks, then try again',
          statusCode: 409,
          params: {'reason': 'task-parked', 'task': 'tk-1'},
        ),
        'An earlier merge or split of this stopped and needs attention. '
            'Clear it in Tasks, then try again.',
      ),
      (
        'a folder the server cannot write',
        const WaxDeckApiException(
          code: 'storage-unwritable',
          message: 'the library folder refused the write: permission denied',
          statusCode: 409,
        ),
        "The server cannot write to that library's folder, so nothing was "
            "changed. Check the folder's ownership and permissions.",
      ),
    ]) {
      testWidgets('a merge refused for $name says why in the app\'s words', (
        tester,
      ) async {
        final repo = _adminRepo(testBook(bookPid, partCount: 2));
        await tester.pumpWidget(_host(repo, FakeEngine()));
        await tester.pumpAndSettle();

        await openOverflow(tester);
        await _tap(tester, SemanticsIds.bookMerge);
        repo.toolError = refusal;
        await _tap(tester, SemanticsIds.bookMergeConfirm);
        repo.toolError = null;

        expect(shellMessageText(raisedMessage(tester)), sentence);
        expect(repo.mergeBookCalls, isEmpty);
      });
    }

    testWidgets('a merge refused while another is at work leads to the '
        'Tasks screen; other refusals offer nothing', (tester) async {
      final repo = _adminRepo(testBook(bookPid, partCount: 2));
      await tester.pumpWidget(_host(repo, FakeEngine()));
      await tester.pumpAndSettle();

      await openOverflow(tester);
      await _tap(tester, SemanticsIds.bookMerge);
      repo.toolError = const WaxDeckApiException(
        code: 'conflict',
        message: 'the book has a copy, Ada/Book/part 1.m4b',
        statusCode: 409,
        params: {'reason': 'copy-elsewhere', 'copy': 'Ada/Book/part 1.m4b'},
      );
      await _tap(tester, SemanticsIds.bookMergeConfirm);
      expect(raisedMessage(tester)!.actionLabel, isNull);
      expect(raisedMessage(tester)!.onAction, isNull);

      await openOverflow(tester);
      await _tap(tester, SemanticsIds.bookMerge);
      repo.toolError = const WaxDeckApiException(
        code: 'conflict',
        message: 'a merge or split of this book has not finished yet',
        statusCode: 409,
        params: {'reason': 'task-running', 'task': 'tk-1'},
      );
      await _tap(tester, SemanticsIds.bookMergeConfirm);
      repo.toolError = null;

      final message = raisedMessage(tester)!;
      expect(message.actionLabel, 'Tasks');
      expect(message.actionSemanticsId, SemanticsIds.openTasks);
      await pressRaisedAction(tester);
      expect(find.byType(TasksScreen), findsOneWidget);
    });

    testWidgets('a merge refused for a parked task leads to Tasks too', (
      tester,
    ) async {
      final repo = _adminRepo(testBook(bookPid, partCount: 2));
      await tester.pumpWidget(_host(repo, FakeEngine()));
      await tester.pumpAndSettle();

      await openOverflow(tester);
      await _tap(tester, SemanticsIds.bookMerge);
      repo.toolError = const WaxDeckApiException(
        code: 'conflict',
        message: 'a merge or split of this book stopped and needs attention',
        statusCode: 409,
        params: {'reason': 'task-parked', 'task': 'tk-1'},
      );
      await _tap(tester, SemanticsIds.bookMergeConfirm);
      repo.toolError = null;

      final message = raisedMessage(tester)!;
      expect(message.actionLabel, 'Tasks');
      expect(message.actionSemanticsId, SemanticsIds.openTasks);
    });

    testWidgets('an admin splits a single-file book with chapters', (
      tester,
    ) async {
      final repo = _adminRepo(
        testBook(
          bookPid,
          chapters: const [
            ChapterMark(index: 0, title: 'One', startMs: 0),
            ChapterMark(index: 1, title: 'Two', startMs: 600000),
          ],
        ),
      );
      await tester.pumpWidget(_host(repo, FakeEngine()));
      await tester.pumpAndSettle();

      await openOverflow(tester);
      expect(_byId(SemanticsIds.bookMerge), findsNothing);
      await _tap(tester, SemanticsIds.bookSplit);

      expect(find.text('Split at 2 chapters?'), findsOneWidget);
      expect(repo.splitBookCalls, isEmpty);
      await _tap(tester, SemanticsIds.bookSplitKeep);
      await _tap(tester, SemanticsIds.bookSplitConfirm);

      expect(repo.splitBookCalls.single.pid, bookPid);
      expect(repo.splitBookCalls.single.keepOriginals, isTrue);
    });

    testWidgets('split is hidden for a one-chapter book', (tester) async {
      final repo = _adminRepo(
        testBook(
          bookPid,
          chapters: const [ChapterMark(index: 0, title: 'One', startMs: 0)],
        ),
      );
      await tester.pumpWidget(_host(repo, FakeEngine()));
      await tester.pumpAndSettle();

      await openOverflow(tester);
      // A split needs a mark inside the book to cut at.
      expect(find.text('Split at chapters'), findsNothing);
      expect(_byId(SemanticsIds.bookSplit), findsNothing);
    });

    // Parked is an end too: the task will not move again, so what it left
    // of the book is read as it stands.
    for (final ending in ['done', 'parked']) {
      testWidgets('the book is read again when its merge ends $ending', (
        tester,
      ) async {
        final repo = _adminRepo(testBook(bookPid, partCount: 3));
        await tester.pumpWidget(_host(repo, FakeEngine()));
        await tester.pumpAndSettle();
        expect(_byId(SemanticsIds.bookPartsNote), findsOneWidget);

        await openOverflow(tester);
        await _tap(tester, SemanticsIds.bookMerge);
        await _tap(tester, SemanticsIds.bookMergeConfirm);

        // The task ends on the server, the book is one file now, and the
        // task list hears of it.
        final queued = repo.toolTasksById.values.single;
        repo.books[bookPid] = testBook(bookPid, partCount: 1);
        repo.toolTasksById[queued.id] = ToolTask(
          id: queued.id,
          type: queued.type,
          state: ending,
          itemPid: bookPid,
          resultPids: ending == 'done' ? const [bookPid] : const [],
          createdAt: queued.createdAt,
        );
        ProviderScope.containerOf(
          tester.element(find.byType(BookScreen)),
        ).invalidate(toolTasksProvider);
        await tester.pumpAndSettle();

        expect(_byId(SemanticsIds.bookPartsNote), findsNothing);
      });
    }

    // Cleared by another administrator, pruned, or pushed past the first
    // page: nothing more will say the task ended, so its leaving is the
    // end the book is read again for.
    testWidgets('the book is read again when its merge leaves the task list '
        'unfinished', (tester) async {
      final repo = _adminRepo(testBook(bookPid, partCount: 3));
      await tester.pumpWidget(_host(repo, FakeEngine()));
      await tester.pumpAndSettle();
      expect(_byId(SemanticsIds.bookPartsNote), findsOneWidget);

      await openOverflow(tester);
      await _tap(tester, SemanticsIds.bookMerge);
      await _tap(tester, SemanticsIds.bookMergeConfirm);

      final queued = repo.toolTasksById.values.single;
      repo.books[bookPid] = testBook(bookPid, partCount: 1);
      repo.toolTasksById.remove(queued.id);
      ProviderScope.containerOf(
        tester.element(find.byType(BookScreen)),
      ).invalidate(toolTasksProvider);
      await tester.pumpAndSettle();

      expect(_byId(SemanticsIds.bookPartsNote), findsNothing);
    });

    testWidgets('the task list is not kept live once the book screen is '
        'gone', (tester) async {
      final repo = _TaskListings(testBook(bookPid, partCount: 3));
      final showing = ValueNotifier(true);
      addTearDown(showing.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            audioEngineProvider.overrideWithValue(FakeEngine()),
            credentialStoreProvider.overrideWithValue(
              InMemoryCredentialStore(),
            ),
          ],
          child: routedHost(
            ValueListenableBuilder<bool>(
              valueListenable: showing,
              builder: (context, show, _) => show
                  ? const BookScreen(pid: bookPid)
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openOverflow(tester);
      await _tap(tester, SemanticsIds.bookMerge);
      await _tap(tester, SemanticsIds.bookMergeConfirm);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(BookScreen)),
      );
      // Live while the screen waits on the merge.
      final whileUp = repo.listings;
      container.invalidate(toolTasksProvider);
      await tester.pumpAndSettle();
      expect(repo.listings, whileUp + 1);

      // The merge is still at work as the reader leaves the book.
      showing.value = false;
      await tester.pumpAndSettle();
      final before = repo.listings;
      container.invalidate(toolTasksProvider);
      await tester.pumpAndSettle();

      expect(repo.listings, before);
    });

    testWidgets('a holder of the delete right deletes the book', (
      tester,
    ) async {
      final repo = _adminRepo(testBook(bookPid, partCount: 2))
        ..libraryItems.add(testItem(bookPid));
      await tester.pumpWidget(_host(repo, FakeEngine()));
      await tester.pumpAndSettle();

      await openOverflow(tester);
      await _tap(tester, SemanticsIds.itemMenuDelete);
      expect(repo.deleteItemsCalls.single.pids, [bookPid]);
      expect(repo.deleteItemsCalls.single.dryRun, isTrue);
      await tester.tap(find.byKey(const Key(SemanticsIds.itemDeleteConfirm)));
      await tester.pumpAndSettle();

      expect(repo.deleteItemsCalls.last.dryRun, isFalse);
      expect(
        find.byType(BookScreen),
        findsNothing,
        reason: 'the book is gone; the screen leaves for the hub',
      );
    });

    testWidgets('a book a file of which stayed keeps its screen', (
      tester,
    ) async {
      final repo = _adminRepo(testBook(bookPid, partCount: 2))
        ..libraryItems.add(testItem(bookPid))
        ..deleteItemsFailed = 1;
      await tester.pumpWidget(_host(repo, FakeEngine()));
      await tester.pumpAndSettle();

      await openOverflow(tester);
      await _tap(tester, SemanticsIds.itemMenuDelete);
      await tester.tap(find.byKey(const Key(SemanticsIds.itemDeleteConfirm)));
      await tester.pumpAndSettle();

      expect(repo.deleteItemsCalls.last.dryRun, isFalse);
      expect(
        find.byType(BookScreen),
        findsOneWidget,
        reason: 'a part stayed, so the book did',
      );
    });

    testWidgets('an admin folds a split series into another spelling', (
      tester,
    ) async {
      const loser = 'sr-01JZX5N8QW3F4V9T2B7KDLOSER1';
      const survivor = 'sr-01JZX5N8QW3F4V9T2B7KDSURVIV';
      final repo =
          _adminRepo(
              testBook(bookPid, series: 'Harbour Chronicles', seriesPid: loser),
            )
            ..bookSeries.addAll(const <BookSeries>[
              BookSeries(pid: loser, name: 'Harbour Chronicles', bookCount: 1),
              BookSeries(
                pid: survivor,
                name: 'Harbor Chronicles',
                bookCount: 4,
              ),
            ]);
      await tester.pumpWidget(_host(repo, FakeEngine()));
      await tester.pumpAndSettle();

      await openOverflow(tester);
      await _tap(tester, SemanticsIds.seriesMerge);

      // The book's own series is the loser, so it is not offered as a
      // target: merging a thing into itself is not a choice.
      expect(_byId(SemanticsIds.seriesMergeTarget(loser)), findsNothing);
      await _tap(tester, SemanticsIds.seriesMergeTarget(survivor));

      final call = repo.mergeDuplicatesCalls.single;
      expect(call.entityType, 'series');
      expect(call.survivorPid, survivor);
      expect(call.loserPids, [loser]);
    });

    testWidgets('someone who may edit the book turns it back into music', (
      tester,
    ) async {
      final repo = _repo();
      await tester.pumpWidget(_host(repo, FakeEngine()));
      await tester.pumpAndSettle();

      await openOverflow(tester);
      await tester.tap(find.text('Treat as music').last);
      await tester.pumpAndSettle();
      expect(find.text('Make this music?'), findsOneWidget);
      await tester.tap(_byId(SemanticsIds.kindConfirm));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(repo.setKindCalls.single.pids, [bookPid]);
      expect(repo.setKindCalls.single.mediaType, 'music');
      expect(
        find.byType(BookScreen),
        findsNothing,
        reason: 'the book is gone; the screen leaves for its tracks',
      );
    });

    testWidgets('a listener who may not edit it is not offered music', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(_repo()..mayCurateItems = false, FakeEngine()),
      );
      await tester.pumpAndSettle();
      await openOverflow(tester);
      expect(find.text('Treat as music'), findsNothing);
    });

    for (final (name, streaming) in [
      (
        'runs without one',
        const ServerStreaming(configured: false, connected: false),
      ),
      (
        'cannot reach it',
        const ServerStreaming(configured: true, connected: false),
      ),
    ]) {
      testWidgets('merge is hidden while the server $name', (tester) async {
        final repo = _adminRepo(testBook(bookPid, partCount: 3))
          ..serverStreaming = streaming;
        await tester.pumpWidget(_host(repo, FakeEngine()));
        await tester.pumpAndSettle();

        await openOverflow(tester);
        expect(_byId(SemanticsIds.bookMerge), findsNothing);
        expect(find.text('Edit metadata'), findsOneWidget);
      });

      testWidgets('split is hidden while the server $name', (tester) async {
        final repo = _adminRepo(_splittableBook())..serverStreaming = streaming;
        await tester.pumpWidget(_host(repo, FakeEngine()));
        await tester.pumpAndSettle();

        await openOverflow(tester);
        expect(_byId(SemanticsIds.bookSplit), findsNothing);
        expect(find.text('Edit metadata'), findsOneWidget);
      });
    }

    const runsFileTools = ServerStreaming(
      configured: true,
      connected: true,
      fileTools: true,
    );

    testWidgets('merge is offered while the engine runs the file tools', (
      tester,
    ) async {
      final repo = _adminRepo(testBook(bookPid, partCount: 3))
        ..serverStreaming = runsFileTools;
      await tester.pumpWidget(_host(repo, FakeEngine()));
      await tester.pumpAndSettle();

      await openOverflow(tester);
      expect(_byId(SemanticsIds.bookMerge), findsOneWidget);
    });

    testWidgets('split is offered while the engine runs the file tools', (
      tester,
    ) async {
      final repo = _adminRepo(_splittableBook())
        ..serverStreaming = runsFileTools;
      await tester.pumpWidget(_host(repo, FakeEngine()));
      await tester.pumpAndSettle();

      await openOverflow(tester);
      expect(_byId(SemanticsIds.bookSplit), findsOneWidget);
    });

    testWidgets('a merge refused while the engine is away says so', (
      tester,
    ) async {
      final repo = _adminRepo(testBook(bookPid, partCount: 2));
      await tester.pumpWidget(_host(repo, FakeEngine()));
      await tester.pumpAndSettle();

      await openOverflow(tester);
      await _tap(tester, SemanticsIds.bookMerge);
      repo.toolError = const WaxDeckApiException(
        code: 'feature-unavailable',
        message:
            'book merging needs the streaming engine, which is not '
            'reachable right now',
        statusCode: 503,
        params: {'feature': 'streaming-engine'},
      );
      await _tap(tester, SemanticsIds.bookMergeConfirm);
      repo.toolError = null;

      expect(
        shellMessageText(raisedMessage(tester)),
        'The streaming engine is not reachable right now. Originals still '
        'play; transcoding, gapless playback, voice boost and merging or '
        'splitting files wait for it.',
      );
    });

    testWidgets('the file tools are hidden from a listener', (tester) async {
      await tester.pumpWidget(
        _host(
          _repo()..books[bookPid] = testBook(bookPid, partCount: 3),
          FakeEngine(),
        ),
      );
      await tester.pumpAndSettle();

      await openOverflow(tester);
      expect(find.text('Merge into one chaptered file'), findsNothing);
      expect(find.text('Edit metadata'), findsNothing);
      expect(_byId(SemanticsIds.itemMenuDelete), findsNothing);
      // The position verbs are everyone's.
      expect(find.text('Mark finished'), findsOneWidget);
    });
  });
}

const _adminSession = SessionState(
  authenticated: true,
  user: WaxDeckUser(
    id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
    username: 'admin',
    roles: ['admin'],
  ),
);

FakeRepository _adminRepo(BookDetail book) =>
    FakeRepository(sessionState: _adminSession)..books[bookPid] = book;
