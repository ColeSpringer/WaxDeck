import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/tools/tasks_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';
import 'routed_host.dart';

void main() {
  testWidgets('a path fix task reads moved, not filled', (tester) async {
    final repo = FakeRepository();
    repo.toolTasksById['tt-path'] = ToolTask(
      id: 'tt-path',
      type: 'health-fix',
      state: 'done',
      createdAt: DateTime.utc(2026, 10, 1),
      finishedAt: DateTime.utc(2026, 10, 1, 1),
      summary: const {
        'rule': 'path-mismatch',
        'attempted': 5,
        'filled': 2,
        'moved': 2,
        'failed': 0,
        'held': {'occupied': 1, 'untagged': 1},
        'skipped': {'already in place': 1},
        'jobPids': ['jb-1'],
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        ],
        child: routedHost(const TasksScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.taskRow('tt-path')),
        matching: find.text('moved 2 of 5, 2 held, skipped 1, failed 0'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('filled'), findsNothing);
  });
}
