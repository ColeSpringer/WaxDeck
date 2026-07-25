import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/books/book_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

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

void main() {
  testWidgets('renders the header and the chapters', (tester) async {
    await tester.pumpWidget(_host(_repo(), FakeEngine()));
    await tester.pumpAndSettle();

    expect(find.text('There And Back Again'), findsWidgets);
    expect(find.text('By B. Baggins'), findsOneWidget);
    expect(find.text('Read by Frodo'), findsOneWidget);
    expect(find.byKey(const ValueKey('chapter-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('chapter-1')), findsOneWidget);
  });

  testWidgets('Continue starts the player at the resumed book position', (
    tester,
  ) async {
    final repo = _repo()
      ..bookResumes[bookPid] = const BookResume(positionMs: 720000);
    final engine = FakeEngine(mediaDuration: const Duration(hours: 1));
    await tester.pumpWidget(_host(repo, engine));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book-resume')));
    await tester.pumpAndSettle();

    expect(engine.position, const Duration(minutes: 12));
    expect(engine.playing, isTrue);
  });

  testWidgets('tapping a chapter starts playback at its start', (tester) async {
    final repo = _repo();
    final engine = FakeEngine(mediaDuration: const Duration(hours: 1));
    await tester.pumpWidget(_host(repo, engine));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chapter-1')));
    await tester.pumpAndSettle();

    expect(engine.position, const Duration(minutes: 10));
    expect(engine.playing, isTrue);
  });

  testWidgets('the settings sheet PUTs the per-book settings', (tester) async {
    final repo = _repo();
    await tester.pumpWidget(_host(repo, FakeEngine()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book-settings-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-settings-trim')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('book-settings-save')));
    await tester.pumpAndSettle();

    expect(repo.putBookSettingsCalls, hasLength(1));
    final saved = repo.putBookSettingsCalls.single;
    expect(saved.pid, bookPid);
    expect(saved.settings.trimSilence, isTrue);
    expect(saved.settings.speed, closeTo(1.0, 0.001));
  });

  FakeRepository adminRepo(BookDetail book) => FakeRepository(
    sessionState: const SessionState(
      authenticated: true,
      user: WaxDeckUser(
        id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
        username: 'admin',
        roles: ['admin'],
      ),
    ),
  )..books[bookPid] = book;

  testWidgets('an admin merges a multi-file book from the tools menu', (
    tester,
  ) async {
    final repo = adminRepo(testBook(bookPid, partCount: 3));
    await tester.pumpWidget(_host(repo, FakeEngine()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book-tools-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-split')), findsNothing);
    await tester.tap(find.byKey(const Key('book-merge')));
    await tester.pumpAndSettle();

    expect(repo.mergeBookCalls.map((c) => c.pid), [bookPid]);
  });

  testWidgets('an admin splits a single-file book with chapters', (
    tester,
  ) async {
    final repo = adminRepo(
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

    await tester.tap(find.byKey(const Key('book-tools-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-merge')), findsNothing);
    await tester.tap(find.byKey(const Key('book-split')));
    await tester.pumpAndSettle();

    expect(repo.splitBookCalls.map((c) => c.pid), [bookPid]);
  });

  testWidgets('the book tools menu is hidden from non-admins', (tester) async {
    await tester.pumpWidget(
      _host(
        _repo()..books[bookPid] = testBook(bookPid, partCount: 3),
        FakeEngine(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-tools-menu')), findsNothing);
  });
}
