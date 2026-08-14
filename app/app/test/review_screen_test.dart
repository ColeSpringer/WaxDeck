import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/review/review_screen.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck/src/shell/shortcuts.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'localized_host.dart';

ProviderContainer _container(FakeRepository repo) {
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _host(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: localizedHost(const ReviewScreen()),
);

/// Narrow enough that the queue is the whole page: the detail pane is
/// the two-pane arrangement's business and every test here is about the
/// list and its keys.
Future<void> _pump(WidgetTester tester, Widget host) async {
  tester.view.physicalSize = const Size(700, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(host);
}

Finder _row(String id) =>
    find.bySemanticsIdentifier(SemanticsIds.reviewRow(id));

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
    await _pump(tester, _host(_container(repo)));
    // No pumpAndSettle: the identifying row's spinner animates forever.
    await tester.pump();
    await tester.pump();

    expect(_row('rv-1'), findsOneWidget);
    expect(
      find.text('10 tracks, 94% Neon Meridian, The Cardinal Waves (2011)'),
      findsOneWidget,
    );
    final identifyingRow = _row('rv-2');
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
    await _pump(tester, _host(_container(repo)));
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

  testWidgets('deciding the last row keeps the keys working', (tester) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry('rv-1'),
      testReviewEntry('rv-2', title: 'Second Album'),
    ];
    await _pump(tester, _host(_container(repo)));
    await tester.pumpAndSettle();

    // Down to the last row and decide it: the queue shortens under the
    // cursor, which used to leave every decision key guarding itself
    // out until j or k pulled the index back into range.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();
    expect(repo.decideReviewCalls.single.entryId, 'rv-2');

    // The next key decides the row the cursor landed on, with no j or k
    // in between.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();
    expect(repo.decideReviewCalls, hasLength(2));
    expect(repo.decideReviewCalls.last.entryId, 'rv-1');
  });

  testWidgets('the selected row is highlighted', (tester) async {
    final repo = FakeRepository();
    repo.reviewEntries = [testReviewEntry('rv-1')];
    await _pump(tester, _host(_container(repo)));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    final material = tester.widget<Material>(
      find.descendant(of: _row('rv-1'), matching: find.byType(Material)).first,
    );
    final context = tester.element(_row('rv-1'));
    expect(material.color, WaxColors.of(context).accentContainer);
  });

  testWidgets('typing in a text field does not trigger shortcuts', (
    tester,
  ) async {
    // Exercises the AppShortcuts guard the review screen's bindings sit
    // behind: a binding fires while the shortcut scope holds focus, and
    // stays silent once an EditableText takes primary focus.
    var fired = 0;
    await tester.pumpWidget(
      localizedHost(
        Scaffold(
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
    final container = _container(repo);
    await _pump(tester, _host(container));
    await tester.pumpAndSettle();

    await tester.longPress(_row('rv-1'));
    await tester.pumpAndSettle();
    await tester.tap(_row('rv-2'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip));
    await tester.pumpAndSettle();

    expect(
      repo.reviewEntries.where((e) => e.status == 'skipped'),
      hasLength(2),
    );
    expect(container.read(shellMessengerProvider)?.text, 'Decided 2 entries');
  });

  testWidgets('a failing queue shows the error with a retry', (tester) async {
    final repo = FakeRepository();
    repo.reviewError = const WaxDeckApiException(
      code: 'internal',
      message: 'queue exploded',
      statusCode: 500,
    );
    await _pump(tester, _host(_container(repo)));
    await tester.pumpAndSettle();

    // The code's own sentence rather than the server's: a failed read
    // refused nothing anybody typed. The title was drawn before the
    // conversion too, so the absent server line is what proves it.
    expect(find.text('Could not load the review queue'), findsOneWidget);
    expect(
      find.text('The server ran into a problem it could not handle.'),
      findsOneWidget,
    );
    expect(find.text('queue exploded'), findsNothing);
    repo.reviewError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing waiting for review'), findsOneWidget);
  });

  testWidgets('an admin sets a library matching mode from the bar', (
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
    await _pump(tester, _host(_container(repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.matchingMenu));
    await tester.pumpAndSettle();
    expect(find.text('Music: Review everything'), findsOneWidget);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.matchingOption('lb-1', 'review')),
    );
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
    await _pump(tester, _host(_container(repo)));
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier(SemanticsIds.matchingMenu), findsNothing);
  });
}
