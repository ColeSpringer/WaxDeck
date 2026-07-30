import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/books/book_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
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

/// Taps the row or control carrying [id], scrolling to it first: the
/// book screen is one long list and its chapters sit below the fold.
Future<void> _tap(WidgetTester tester, String id) async {
  final finder = _byId(id).first;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _byId(String id) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.identifier == id,
);

void main() {
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

  testWidgets('the settings sheet PUTs the per-book settings', (tester) async {
    final repo = _repo();
    await tester.pumpWidget(_host(repo, FakeEngine()));
    await tester.pumpAndSettle();

    await _tap(tester, SemanticsIds.bookSettingsOpen);
    await tester.tap(find.byKey(const Key('book-settings-trim')));
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
      expect(find.text('Marked finished'), findsOneWidget);

      // The undo puts back where the listener actually was, which is the
      // position read before the write rather than zero.
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(repo.putPlayStateCalls.last.positionMs, 600000);
    });

    testWidgets('the undo outlives the screen that offered it', (tester) async {
      // The toast is a `ScaffoldMessenger` surface: it stays up while the
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

      // Replace the screen, keeping the messenger's toast on screen.
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
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(repo.putPlayStateCalls.last.positionMs, 600000);
    });

    testWidgets('starts the book over from zero', (tester) async {
      final repo = _repo()..playPositions[bookPid] = 600000;
      await tester.pumpWidget(_host(repo, FakeEngine()));
      await tester.pumpAndSettle();

      await openOverflow(tester);
      await _tap(tester, SemanticsIds.bookStartOver);

      expect(repo.putPlayStateCalls.last.positionMs, 0);
      expect(find.text('Back to the beginning'), findsOneWidget);
    });

    testWidgets('an admin merges a multi-file book', (tester) async {
      final repo = _adminRepo(testBook(bookPid, partCount: 3));
      await tester.pumpWidget(_host(repo, FakeEngine()));
      await tester.pumpAndSettle();

      await openOverflow(tester);
      expect(find.text('Split at chapters'), findsNothing);
      await tester.tap(find.text('Merge into one chaptered file'));
      await tester.pumpAndSettle();

      expect(repo.mergeBookCalls.map((c) => c.pid), [bookPid]);
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
      expect(find.text('Merge into one chaptered file'), findsNothing);
      await tester.tap(find.text('Split at chapters'));
      await tester.pumpAndSettle();

      expect(repo.splitBookCalls.map((c) => c.pid), [bookPid]);
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
      // The position verbs are everyone's.
      expect(find.text('Mark finished'), findsOneWidget);
    });
  });
}

FakeRepository _adminRepo(BookDetail book) => FakeRepository(
  sessionState: const SessionState(
    authenticated: true,
    user: WaxDeckUser(
      id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
      username: 'admin',
      roles: ['admin'],
    ),
  ),
)..books[bookPid] = book;
