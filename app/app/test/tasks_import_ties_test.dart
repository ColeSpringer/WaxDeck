import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/tools/tasks_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

/// A finished import whose report carries [summary].
Widget _host(Map<String, Object?> summary, {Locale? locale}) {
  final repo = FakeRepository();
  repo.toolTasksById['tt-imp'] = ToolTask(
    id: 'tt-imp',
    type: 'import-spotify',
    state: 'done',
    createdAt: DateTime.utc(2026, 7, 20),
    finishedAt: DateTime.utc(2026, 7, 20, 1),
    summary: summary,
  );
  return ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
    ],
    child: routedHost(
      const TasksScreen(),
      locale: locale ?? const Locale('en'),
    ),
  );
}

void main() {
  testWidgets('an import that took ties counts them beside the matches', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const {'matched': 120, 'ties': 4, 'unmatched': 3, 'listens': 9}),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('matched 120, tied 4, unmatched 3, listens 9'),
      findsOneWidget,
    );
  });

  testWidgets('the ties counter is worded in Spanish too', (tester) async {
    await tester.pumpWidget(
      _host(const {
        'matched': 120,
        'ties': 4,
        'unmatched': 3,
      }, locale: const Locale('es')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('coincidencias 120, empatadas 4, sin coincidencia 3'),
      findsOneWidget,
    );
  });
}
