import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/review/review_screen.dart';
import 'package:waxdeck/src/shell/shortcuts.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
  ],
  child: const MaterialApp(home: ReviewScreen()),
);

void main() {
  testWidgets('renders entries with best-candidate and identifying rows', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry(
        'rv-1',
        best: const CandidateSummary(
          mbid: 'mb-1',
          title: 'Neon Meridian',
          artist: 'The Cardinal Waves',
          year: 2011,
          similarityPct: 94,
        ),
      ),
      testReviewEntry(
        'rv-2',
        title: 'Mystery Tape',
        identifying: true,
        origin: 'upload',
      ),
    ];
    await tester.pumpWidget(_host(repo));
    // No pumpAndSettle: the identifying row's spinner animates forever.
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('review-row-rv-1')), findsOneWidget);
    expect(
      find.text('94% Neon Meridian, The Cardinal Waves (2011)'),
      findsOneWidget,
    );
    expect(find.text('10 tracks'), findsNWidgets(2));
    final identifyingRow = find.byKey(const ValueKey('review-row-rv-2'));
    expect(
      find.descendant(
        of: identifyingRow,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: identifyingRow, matching: find.text('Upload')),
      findsOneWidget,
    );
  });

  testWidgets('j and k move the selection and a approves it', (tester) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry('rv-1'),
      testReviewEntry('rv-2', title: 'Second Album'),
    ];
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    // Down twice, back up once: the selection must land on the first
    // row again, and a decides exactly that row.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();

    expect(repo.decideReviewCalls, hasLength(1));
    expect(repo.decideReviewCalls.single.entryId, 'rv-1');
    expect(repo.decideReviewCalls.single.action, 'approve');
  });

  testWidgets('the selected row is highlighted', (tester) async {
    final repo = FakeRepository();
    repo.reviewEntries = [testReviewEntry('rv-1')];
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    // The dual-tagged key sits on the row's Material, whose color is
    // the selection highlight.
    final material = tester.widget<Material>(
      find.byKey(const ValueKey('review-row-rv-1')),
    );
    final context = tester.element(
      find.byKey(const ValueKey('review-row-rv-1')),
    );
    expect(material.color, Theme.of(context).colorScheme.secondaryContainer);
  });

  testWidgets('typing in a text field does not trigger shortcuts', (
    tester,
  ) async {
    // Exercises the AppShortcuts guard the review screen's bindings sit
    // behind: a binding fires while the shortcut scope holds focus, and
    // stays silent once an EditableText takes primary focus.
    var fired = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyA): () => fired++,
            },
            child: const TextField(key: Key('guard-field')),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(fired, 1);

    await tester.tap(find.byKey(const Key('guard-field')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(fired, 1);
  });

  testWidgets('bulk select decides every checked entry', (tester) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry('rv-1'),
      testReviewEntry('rv-2', title: 'Second Album'),
    ];
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('review-row-rv-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('review-row-rv-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-bulk-skip')));
    await tester.pumpAndSettle();

    expect(
      repo.reviewEntries.where((e) => e.status == 'skipped'),
      hasLength(2),
    );
    expect(find.text('Decided 2 entries'), findsOneWidget);
  });

  testWidgets('a failing queue shows the error with a retry', (tester) async {
    final repo = FakeRepository();
    repo.reviewError = const WaxDeckApiException(
      code: 'internal',
      message: 'queue exploded',
      statusCode: 500,
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.text('queue exploded'), findsOneWidget);
    repo.reviewError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing waiting for review'), findsOneWidget);
  });

  testWidgets('an admin sets a library matching mode from the app bar', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(
        authenticated: true,
        user: WaxDeckUser(
          id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
          username: 'admin',
          roles: ['admin'],
        ),
      ),
    );
    repo.libraries.add(const LibraryInfo(pid: 'lb-1', name: 'Music'));
    repo.matchingModes['lb-1'] = 'auto';
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('matching-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Music'), findsOneWidget);

    await tester.tap(find.byKey(const Key('matching-lb-1-review')));
    await tester.pumpAndSettle();
    expect(repo.matchingModes['lb-1'], 'review');
  });

  testWidgets('the matching control is hidden from non-admins', (tester) async {
    final repo = FakeRepository(
      sessionState: const SessionState(
        authenticated: true,
        user: WaxDeckUser(
          id: 'us-01JZX5N8QW3F4V9T2B7KDUSER001',
          username: 'plain',
          roles: ['user'],
        ),
      ),
    );
    repo.libraries.add(const LibraryInfo(pid: 'lb-1', name: 'Music'));
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('matching-menu')), findsNothing);
  });
}
