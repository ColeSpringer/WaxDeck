import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/tools/tasks_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

/// Tasks over a finished import whose report carries [summary].
Future<void> _pump(
  WidgetTester tester,
  Map<String, Object?> summary, {
  Locale? locale,
}) async {
  final repo = FakeRepository();
  repo.toolTasksById['tt-imp'] = ToolTask(
    id: 'tt-imp',
    type: 'import-spotify',
    state: 'done',
    createdAt: DateTime.utc(2026, 7, 20),
    finishedAt: DateTime.utc(2026, 7, 20, 1),
    summary: summary,
  );
  await pumpApp(
    tester,
    const TasksScreen(),
    container: appContainer(repo: repo),
    locale: locale ?? const Locale('en'),
  );
}

void main() {
  testWidgets('an import that took ties counts them beside the matches', (
    tester,
  ) async {
    await _pump(tester, const {
      'matched': 120,
      'ties': 4,
      'unmatched': 3,
      'listens': 9,
    });
    expect(
      find.text('matched 120, tied 4, unmatched 3, listens 9'),
      findsOneWidget,
    );
  });

  testWidgets('the ties counter is worded in Spanish too', (tester) async {
    await _pump(tester, const {
      'matched': 120,
      'ties': 4,
      'unmatched': 3,
    }, locale: const Locale('es'));
    expect(
      find.text('coincidencias 120, empatadas 4, sin coincidencia 3'),
      findsOneWidget,
    );
  });
}
