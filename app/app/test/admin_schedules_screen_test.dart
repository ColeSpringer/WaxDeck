import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/schedules_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';

ProviderContainer _container(FakeRepository repo) {
  final container = ProviderContainer(
    overrides: [repositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SchedulesScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists every schedule with what it costs', (tester) async {
    final repo = FakeRepository();
    await _pump(tester, _container(repo));

    for (final kind in const <String>['scan', 'backup', 'prune', 'analyze']) {
      expect(
        find.bySemanticsIdentifier(SemanticsIds.scheduleRow(kind)),
        findsOneWidget,
      );
    }
    // Analyze is the one whose price an administrator cannot guess from
    // its name: it is the only pass that decodes audio.
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.scheduleRow('analyze')),
        matching: find.textContaining('Decodes every audio file'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an invalid cron surfaces the server message', (tester) async {
    final repo = FakeRepository();
    final container = _container(repo);
    await _pump(tester, container);

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.scheduleCron('scan')),
      'whenever feels right',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.scheduleSave('scan')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(repo.putScheduleCalls.single.kind, 'scan');
    expect(
      container.read(shellMessengerProvider)?.text,
      'invalid cron expression',
    );
    // The stored schedule is untouched.
    expect(repo.schedules['scan']!.cron, '0 3 * * *');
  });

  testWidgets('a valid save stores cron and enablement', (tester) async {
    final repo = FakeRepository();
    final container = _container(repo);
    await _pump(tester, container);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.scheduleEnabled('backup')),
      warnIfMissed: false,
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.scheduleCron('backup')),
      '30 4 * * 1',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.scheduleSave('backup')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(repo.schedules['backup']!.cron, '30 4 * * 1');
    expect(repo.schedules['backup']!.enabled, isTrue);
  });
}
