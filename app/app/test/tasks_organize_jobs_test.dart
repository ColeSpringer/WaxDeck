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
  testWidgets('an organize run and its undo say what they moved', (
    tester,
  ) async {
    final started = DateTime.utc(2026, 10, 1, 9);
    final repo =
        FakeRepository(
            sessionState: const SessionState(authenticated: true, user: _admin),
          )
          ..jobs = [
            Job(
              pid: 'jb-9',
              kind: 'organize-undo',
              state: 'done',
              startedAt: started.add(const Duration(minutes: 5)),
              finishedAt: started.add(const Duration(minutes: 6)),
              target: const JobTarget(type: 'job', pid: 'jb-8'),
              // The server's skipped counts what did not move, the one
              // held back among them: one file stayed in place.
              result: const {
                'moved': 3,
                'skipped': 2,
                'held': 1,
                'errored': 0,
                'sidecarsMoved': 0,
                'dirsPruned': 2,
              },
            ),
            Job(
              pid: 'jb-8',
              kind: 'organize',
              state: 'done',
              startedAt: started,
              finishedAt: started.add(const Duration(minutes: 1)),
              result: const {
                'profile': 'waxbin-native',
                'moved': 4,
                'skipped': 0,
                'held': 0,
                'errored': 0,
                'sidecarsMoved': 0,
                'dirsPruned': 0,
              },
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
    await tester.pumpAndSettle();

    final undo = find.bySemanticsIdentifier(SemanticsIds.jobRow('jb-9'));
    expect(
      find.descendant(of: undo, matching: find.text('Organize undo')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: undo,
        matching: find.text(
          'moved 3, skipped 1, 1 held, errored 0, folders removed 2',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.jobRow('jb-8')),
        matching: find.text('moved 4, skipped 0, errored 0'),
      ),
      findsOneWidget,
      reason: 'nothing held and no folder emptied adds nothing',
    );
  });
}
