import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/tools/tasks_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';
import 'routed_host.dart';

const _admin = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  username: 'admin',
  roles: ['admin'],
);

void main() {
  // The Libraries screen sends an administrator here to follow a removal,
  // so the row names what runs rather than the job's wire kind.
  testWidgets('a library removal reads as one in Tasks', (tester) async {
    final repo =
        FakeRepository(
            sessionState: const SessionState(authenticated: true, user: _admin),
          )
          ..jobs = [
            Job(
              pid: 'jb-1',
              kind: 'remove-root',
              state: 'running',
              progress: 0.5,
              startedAt: DateTime.utc(2026, 10, 1),
              target: const JobTarget(
                type: 'library',
                pid: 'lb-2',
                name: 'spare',
              ),
            ),
          ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        ],
        child: routedHost(const TasksScreen()),
      ),
    );
    // A running job's bar animates forever: frames, not a settle.
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.jobRow('jb-1')),
        matching: find.text('Library removal: spare'),
      ),
      findsOneWidget,
    );
  });

  // An ended removal stays listed, and says what it let go of, as its
  // notice does; trash entries only when it dropped any.
  testWidgets('an ended library removal says what it let go of', (
    tester,
  ) async {
    final started = DateTime.utc(2026, 10, 1, 9);
    Job removal(String pid, Map<String, Object?> result) => Job(
      pid: pid,
      kind: 'remove-root',
      state: 'done',
      startedAt: started,
      finishedAt: started.add(const Duration(minutes: 1)),
      target: JobTarget(type: 'library', pid: 'lb-$pid', name: 'spare'),
      result: result,
    );
    final repo =
        FakeRepository(
            sessionState: const SessionState(authenticated: true, user: _admin),
          )
          ..jobs = [
            removal('jb-2', const {
              'filesDetached': 120,
              'itemsArchived': 4,
              'trashRowsDropped': 2,
            }),
            removal('jb-1', const {
              'filesDetached': 3,
              'itemsArchived': 0,
              'trashRowsDropped': 0,
            }),
          ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        ],
        child: routedHost(const TasksScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.jobRow('jb-2')),
        matching: find.text(
          'detached 120, archived 4, trash entries dropped 2',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.jobRow('jb-1')),
        matching: find.text('detached 3, archived 0'),
      ),
      findsOneWidget,
    );
  });
}
