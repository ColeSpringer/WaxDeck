import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/review/review_controller.dart';
import 'package:waxdeck/src/review/review_entry_screen.dart';
import 'package:waxdeck/src/review/review_screen.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck/src/shell/shortcuts.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'localized_host.dart';
import 'routed_host.dart';

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
  testWidgets('the Decided chip counts reverted and discarded entries', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry('rv-1'),
      testReviewEntry('rv-2', status: 'applied'),
      testReviewEntry('rv-3', status: 'reverted'),
      testReviewEntry('rv-4', status: 'discarded'),
    ];
    await _pump(tester, _host(_container(repo)));
    await tester.pumpAndSettle();

    expect(find.text('Pending (1)'), findsOneWidget);
    expect(find.text('Decided (3)'), findsOneWidget);
  });

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

  testWidgets('a row says how many of its files the library holds', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry('rv-1', origin: 'upload', duplicateCount: 2),
      testReviewEntry('rv-2', origin: 'upload'),
    ];
    await _pump(tester, _host(_container(repo)));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: _row('rv-1'), matching: find.text('2 duplicates')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _row('rv-2'),
        matching: find.textContaining('duplicate'),
      ),
      findsNothing,
    );
  });

  testWidgets('a decided row drops its duplicates chip', (tester) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry('rv-1', origin: 'upload', duplicateCount: 1),
      testReviewEntry(
        'rv-2',
        origin: 'upload',
        status: 'as-is',
        duplicateCount: 1,
      ),
    ];
    await _pump(tester, _host(_container(repo)));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(
        SemanticsIds.reviewFilter(ReviewFilter.decided.name),
      ),
    );
    await tester.pumpAndSettle();

    expect(_row('rv-2'), findsOneWidget);
    expect(
      find.descendant(of: _row('rv-2'), matching: find.text('1 duplicate')),
      findsNothing,
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
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'Decided 2 entries',
    );
  });

  testWidgets('a busy library offers the same decision again', (tester) async {
    final repo = FakeRepository();
    repo.reviewEntries = [testReviewEntry('rv-1')];
    final container = _container(repo);
    await _pump(tester, _host(container));
    await tester.pumpAndSettle();

    repo.reviewError = const WaxDeckApiException(
      code: 'catalog-busy',
      message: 'a conflicting catalog job is already running',
      statusCode: 409,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    final message = container.read(shellMessengerProvider)!;
    expect(
      shellMessageText(message),
      "Another job is holding the library's files. Try again shortly.",
    );
    expect(message.actionLabel, 'Retry');

    repo.reviewError = null;
    message.onAction!();
    await tester.pumpAndSettle();
    expect(repo.decideReviewCalls, hasLength(2));
    expect(repo.decideReviewCalls.last.entryId, 'rv-1');
    expect(repo.reviewEntries.single.status, isNot('pending'));
  });

  testWidgets('a bulk decision says what the server warned of and sends the '
      'busy entries again', (tester) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry('rv-1'),
      testReviewEntry('rv-2', title: 'Second Album'),
    ];
    repo.bulkOutcomes.addAll({
      'rv-1': const ReviewBulkOutcome(
        entryId: 'rv-1',
        ok: true,
        warnings: ['one.flac: already in the library; nothing was added'],
      ),
      'rv-2': const ReviewBulkOutcome(
        entryId: 'rv-2',
        ok: false,
        code: 'catalog-busy',
        error: 'a conflicting catalog job is already running',
      ),
    });
    final container = _container(repo);
    await _pump(tester, _host(container));
    await tester.pumpAndSettle();

    await tester.longPress(_row('rv-1'));
    await tester.pumpAndSettle();
    await tester.tap(_row('rv-2'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip));
    await tester.pumpAndSettle();

    final message = container.read(shellMessengerProvider)!;
    expect(
      shellMessageText(message),
      'Decided 1 entry, 1 failed\n'
      "Another job is holding the library's files. Try again shortly.\n"
      'one.flac: already in the library; nothing was added',
    );
    expect(message.actionLabel, 'Retry');
    message.onAction!();
    await tester.pumpAndSettle();
    expect(repo.decideBulkCalls.last.entryIds, ['rv-2']);
    expect(repo.decideBulkCalls.last.action, 'skip');
  });

  testWidgets('a decision refused for a reason keeps the server\'s words', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.reviewEntries = [testReviewEntry('rv-1', origin: 'upload')];
    final container = _container(repo);
    await _pump(tester, _host(container));
    await tester.pumpAndSettle();

    repo.reviewError = const WaxDeckApiException(
      code: 'conflict',
      message: 'a.flac: destination already exists in the library',
      statusCode: 409,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();

    // Which file and why: the table's "something changed first" would
    // send the person to try the same thing again.
    final message = container.read(shellMessengerProvider)!;
    expect(
      shellMessageText(message),
      'a.flac: destination already exists in the library',
    );
    expect(message.actionLabel, isNull, reason: 'trying again changes nothing');
  });

  testWidgets('a bulk decision names the one refusal it met', (tester) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry('rv-1'),
      testReviewEntry('rv-2', title: 'Second Album'),
    ];
    repo.bulkOutcomes['rv-2'] = const ReviewBulkOutcome(
      entryId: 'rv-2',
      ok: false,
      code: 'conflict',
      error: 'b.flac: destination already exists in the library',
    );
    final container = _container(repo);
    await _pump(tester, _host(container));
    await tester.pumpAndSettle();

    await tester.longPress(_row('rv-1'));
    await tester.pumpAndSettle();
    await tester.tap(_row('rv-2'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip));
    await tester.pumpAndSettle();

    final message = container.read(shellMessengerProvider)!;
    expect(
      shellMessageText(message),
      'Decided 1 entry, 1 failed\n'
      'b.flac: destination already exists in the library',
    );
    expect(message.actionLabel, isNull);
  });

  testWidgets('a bulk approve passes over entries holding duplicates', (
    tester,
  ) async {
    // What the a and u keys do, for the same reason: the pane holds
    // those two back from a unit the library already has, and the row
    // only knows that something matched.
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry('rv-1'),
      testReviewEntry('rv-2', origin: 'upload', duplicateCount: 2),
      testReviewEntry('rv-3', origin: 'upload', duplicateCount: 1),
    ];
    final container = _container(repo);
    await _pump(tester, _host(container));
    await tester.pumpAndSettle();

    await tester.longPress(_row('rv-1'));
    await tester.pumpAndSettle();
    await tester.tap(_row('rv-2'));
    await tester.pumpAndSettle();
    await tester.tap(_row('rv-3'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.reviewBulkApprove),
    );
    await tester.pumpAndSettle();

    expect(repo.decideBulkCalls.single.entryIds, ['rv-1']);
    expect(
      {for (final e in repo.reviewEntries) e.id: e.status},
      {'rv-1': 'applied', 'rv-2': 'pending', 'rv-3': 'pending'},
    );
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'Decided 1 entry\n'
      '2 entries hold duplicates; open each to decide',
    );
  });

  testWidgets('a bulk approve of entries that all hold duplicates sends '
      'nothing', (tester) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry('rv-1', origin: 'upload', duplicateCount: 2),
      testReviewEntry('rv-2'),
    ];
    final container = _container(repo);
    await _pump(tester, _host(container));
    await tester.pumpAndSettle();

    await tester.longPress(_row('rv-1'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.reviewBulkApprove),
    );
    await tester.pumpAndSettle();

    expect(repo.decideBulkCalls, isEmpty);
    expect(repo.reviewEntries.first.status, 'pending');
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      '1 entry holds duplicates; open it to decide',
    );
    // Out of selection, where a tap on the row opens it.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.reviewBulkApprove),
      findsNothing,
    );
  });

  testWidgets('a bulk skip still decides entries holding duplicates', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry('rv-1', origin: 'upload', duplicateCount: 2),
    ];
    final container = _container(repo);
    await _pump(tester, _host(container));
    await tester.pumpAndSettle();

    await tester.longPress(_row('rv-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip));
    await tester.pumpAndSettle();

    expect(repo.decideBulkCalls.single.entryIds, ['rv-1']);
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'Decided 1 entry',
    );
  });

  testWidgets('a bulk Retry leaves a selection made since alone', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      for (final id in ['rv-1', 'rv-2', 'rv-5', 'rv-6']) testReviewEntry(id),
    ];
    repo.bulkOutcomes['rv-2'] = const ReviewBulkOutcome(
      entryId: 'rv-2',
      ok: false,
      code: 'catalog-busy',
      error: 'a conflicting catalog job is already running',
    );
    final container = _container(repo);
    await _pump(tester, _host(container));
    await tester.pumpAndSettle();

    await tester.longPress(_row('rv-1'));
    await tester.pumpAndSettle();
    await tester.tap(_row('rv-2'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip));
    await tester.pumpAndSettle();
    final retry = container.read(shellMessengerProvider)!;
    expect(retry.actionLabel, 'Retry');

    // A new selection, then the old offer taken up.
    await tester.longPress(_row('rv-5'));
    await tester.pumpAndSettle();
    await tester.tap(_row('rv-6'));
    await tester.pumpAndSettle();
    retry.onAction!();
    await tester.pumpAndSettle();
    expect(repo.decideBulkCalls.last.entryIds, ['rv-2']);

    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip));
    await tester.pumpAndSettle();
    expect(repo.decideBulkCalls.last.entryIds, ['rv-5', 'rv-6']);
  });

  for (final (key, action) in [
    (LogicalKeyboardKey.keyA, 'approve'),
    (LogicalKeyboardKey.keyU, 'unofficial'),
  ]) {
    testWidgets('$action from the list opens an entry holding duplicates', (
      tester,
    ) async {
      // The pane can tell which decisions a copy of the library's own
      // audio leaves open; the row only knows that something matched.
      final repo = FakeRepository();
      repo.reviewEntries = [
        testReviewEntry('rv-1', origin: 'upload', duplicateCount: 2),
      ];
      final container = _container(repo);
      await _pump(
        tester,
        UncontrolledProviderScope(
          container: container,
          child: routedHost(const ReviewScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pump();
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();

      expect(repo.decideReviewCalls, isEmpty);
      expect(find.byType(ReviewEntryScreen), findsOneWidget);
    });
  }

  testWidgets('a and u on the entry its pane already shows say where it is '
      'decided', (tester) async {
    // Opening it again would land where the reviewer already is.
    final repo = FakeRepository()
      ..reviewEntries = [
        testReviewEntry('rv-1', origin: 'upload', duplicateCount: 1),
      ];
    final container = _container(repo);
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(
          const ReviewSurface(openEntryId: 'rv-1'),
          at: '/review/rv-1',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsIdentifier(SemanticsIds.reviewPane), findsOneWidget);
    final raised = <String?>[];
    container.listen(
      shellMessengerProvider,
      (_, next) => raised.add(shellMessageText(next)),
    );

    for (final key in [LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyU]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    expect(raised, [
      for (var i = 0; i < 2; i++)
        'This entry holds duplicates; decide it with its own buttons.',
    ]);
    expect(repo.decideReviewCalls, isEmpty);
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
    // Singles deliberately non-default, so the survival assert below
    // can only pass if the write actually carried the stored value.
    repo.matchingModes['lb-1'] = const LibraryMatching(
      mode: 'auto',
      singlesAutoApply: true,
    );
    await _pump(tester, _host(_container(repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.matchingMenu));
    await tester.pumpAndSettle();
    expect(find.text('Music: Review everything'), findsOneWidget);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.matchingOption('lb-1', 'review')),
    );
    await tester.pumpAndSettle();
    expect(repo.matchingModes['lb-1']!.mode, 'review');
    // A mode change is a full-replace write that must not flip the
    // singles switch along the way.
    expect(repo.matchingModes['lb-1']!.singlesAutoApply, isTrue);
  });

  testWidgets('an admin toggles singles auto-apply from the bar', (
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
    // A non-default mode, so the survival assert below can only pass
    // if the toggle's full-replace write re-sent the stored mode.
    repo.matchingModes['lb-1'] = const LibraryMatching(mode: 'review');
    await _pump(tester, _host(_container(repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.matchingMenu));
    await tester.pumpAndSettle();
    expect(find.text('Music: Auto-apply confident singles'), findsOneWidget);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.matchingSingles('lb-1')),
    );
    await tester.pumpAndSettle();
    expect(repo.matchingModes['lb-1']!.singlesAutoApply, isTrue);
    // The toggle rides the same full-replace write; the mode survives.
    expect(repo.matchingModes['lb-1']!.mode, 'review');

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.matchingMenu));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.matchingSingles('lb-1')),
    );
    await tester.pumpAndSettle();
    expect(repo.matchingModes['lb-1']!.singlesAutoApply, isFalse);
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

  testWidgets('the podcast library offers no matching rows', (tester) async {
    // Its episodes come from their feeds, and the server refuses a
    // matching change on it.
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
    repo.libraries.addAll(const [
      LibraryInfo(pid: 'lb-1', name: 'Music'),
      LibraryInfo(pid: 'lb-p', name: 'Podcasts', media: 'podcast'),
    ]);
    await _pump(tester, _host(_container(repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.matchingMenu));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.matchingOption('lb-1', 'auto')),
      findsOneWidget,
    );
    for (final mode in const ['auto', 'review', 'off']) {
      expect(
        find.bySemanticsIdentifier(SemanticsIds.matchingOption('lb-p', mode)),
        findsNothing,
      );
    }
    expect(
      find.bySemanticsIdentifier(SemanticsIds.matchingSingles('lb-p')),
      findsNothing,
    );
  });

  testWidgets('a server whose only library is the podcast one offers no '
      'matching menu', (tester) async {
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
    repo.libraries.add(
      const LibraryInfo(pid: 'lb-p', name: 'Podcasts', media: 'podcast'),
    );
    await _pump(tester, _host(_container(repo)));
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier(SemanticsIds.matchingMenu), findsNothing);
  });

  group('the two panes', () {
    /// The width the report came from: a 1020-pixel window, less the
    /// shell rail and the console list that used to sit in front of
    /// this screen, is about what it gets to lay itself out in.
    Future<WaxSplitter> pumpSurface(
      WidgetTester tester,
      ProviderContainer container, {
      double width = 900,
    }) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: localizedHost(const ReviewSurface(openEntryId: 'rv-1')),
        ),
      );
      await tester.pumpAndSettle();
      return tester.widget<WaxSplitter>(find.byType(WaxSplitter));
    }

    testWidgets('leave the majority to the entry somebody opened', (
      tester,
    ) async {
      final repo = FakeRepository()..reviewEntries = [testReviewEntry('rv-1')];
      final container = _container(repo);
      final seam = await pumpSurface(tester, container);

      // A third of the room, bounded, which is well under half of it.
      expect(
        find.bySemanticsIdentifier(SemanticsIds.reviewSplitter),
        findsOneWidget,
      );
      expect(seam.position, greaterThanOrEqualTo(ReviewSurface.listMin));
      expect(seam.position, lessThanOrEqualTo(ReviewSurface.listMax));
      expect(seam.min, ReviewSurface.listMin);

      // The point of the whole arrangement: the submission being read
      // gets more than the queue of one-line rows beside it, and never
      // less than the diff table's own minimum. It used to get 343
      // against the list's 380.
      final pane = tester
          .getSize(find.bySemanticsIdentifier(SemanticsIds.reviewPane))
          .width;
      expect(pane, greaterThanOrEqualTo(ReviewSurface.paneMin));
      expect(pane, greaterThan(seam.position));
      // Which is also the seam's own limit: dragging can take room from
      // the entry, but not the room the table needs to be read at all.
      expect(
        seam.max,
        lessThanOrEqualTo(seam.position + pane - ReviewSurface.paneMin),
      );
    });

    testWidgets('remember where the seam was dragged to, and reset', (
      tester,
    ) async {
      final repo = FakeRepository()..reviewEntries = [testReviewEntry('rv-1')];
      final container = _container(repo);
      // Wider than the threshold by enough to have somewhere to drag
      // to: at the narrowest two-pane width the seam is pinned between
      // the two floors, which is what those floors are for.
      await pumpSurface(tester, container, width: 1100);

      double seamAt() =>
          tester.widget<WaxSplitter>(find.byType(WaxSplitter)).position;

      // Two moves rather than one: the first crosses the drag slop the
      // arena withholds, and the second is what the seam has to follow
      // one for one - a splitter that lags the pointer by a constant is
      // a splitter nobody can put anywhere on purpose.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(WaxSplitter)),
      );
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      final grabbed = seamAt();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(seamAt(), grabbed + 40);
      // Nothing is written down yet: a preference is what somebody
      // settled on, and a drag has not settled on anything.
      expect(container.read(reviewListWidthProvider), 0);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(container.read(reviewListWidthProvider), seamAt().round());
      expect(seamAt(), greaterThan(ReviewSurface.listMin));

      // A double tap hands it back to the layout, which is the only way
      // out of a width somebody dragged and then regretted.
      await tester.tap(find.byType(WaxSplitter));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(WaxSplitter));
      await tester.pumpAndSettle();
      expect(container.read(reviewListWidthProvider), 0);
    });

    testWidgets('give the whole page to the entry rather than a squeezed '
        'pair', (tester) async {
      final repo = FakeRepository()..reviewEntries = [testReviewEntry('rv-1')];
      final container = _container(repo);
      // The width the report came from: a 1020-pixel window, less the
      // shell rail and the console list that used to sit in front of
      // this screen. Two panes here would leave the diff table 398 of
      // the 420 it declares, so the answer is one pane at 724 rather
      // than a split that brings the scrollbar back - and the
      // submission still goes from the 343 it had to the whole width.
      tester.view.physicalSize = const Size(724, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: localizedHost(const ReviewSurface(openEntryId: 'rv-1')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(WaxSplitter), findsNothing);
      expect(
        tester.getSize(find.byType(ReviewEntryScreen)).width,
        greaterThan(ReviewSurface.paneMin),
      );
    });

    testWidgets('are not drawn where the entry could not be read', (
      tester,
    ) async {
      final repo = FakeRepository()..reviewEntries = [testReviewEntry('rv-1')];
      final container = _container(repo);
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: localizedHost(const ReviewSurface(openEntryId: 'rv-1')),
        ),
      );
      await tester.pumpAndSettle();

      // The entry takes the screen, so there is nothing to divide - the
      // same answer a phone gets, and the reason the seam is not a
      // control anybody has to find on one.
      expect(find.byType(WaxSplitter), findsNothing);
    });
  });
}
