import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/schedules_screen.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpApp(
    tester,
    const SchedulesScreen(),
    container: container,
    routed: false,
  );
}

void main() {
  testWidgets('a failed read shows its error at once, while it retries', (
    tester,
  ) async {
    // The app's own retry left on: while an attempt runs a failing read
    // is AsyncLoading still carrying the last error.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await mountApp(
      tester,
      const SchedulesScreen(),
      container: appContainer(repo: _SchedulesDown()),
      routed: false,
    );
    await tester.pump();
    // Past the first retry's delay: the read is loading again.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.byType(ErrorState), findsOneWidget);
    // The retry Riverpod is running is drawn as running: busy, no press.
    final retry = find.widgetWithText(WaxButton, 'Try again');
    expect(tester.widget<WaxButton>(retry).busy, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('lists every schedule with what it costs', (tester) async {
    final repo = FakeRepository();
    await _pump(tester, appContainer(repo: repo));

    for (final kind in const <String>[
      'scan',
      'backup',
      'prune',
      'analyze',
      'enrich',
    ]) {
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
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.scheduleRow('prune')),
        matching: find.textContaining('Permanently clears'),
      ),
      findsOneWidget,
    );
    // Enrich has a cost an administrator cannot guess either: the nightly
    // cap, which a run started by hand is exempt from.
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.scheduleRow('enrich')),
        matching: find.textContaining('Capped at 2000 items a night'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.scheduleRow('enrich')),
        matching: find.textContaining('Enrich metadata'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an invalid cron surfaces the server message', (tester) async {
    final repo = FakeRepository();
    final container = appContainer(repo: repo);
    await _pump(tester, container);

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.scheduleCron('scan')),
      'whenever feels right',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.scheduleSave('scan')),
    );
    await tester.pumpAndSettle();

    expect(repo.putScheduleCalls.single.kind, 'scan');
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'invalid cron expression',
    );
    // The stored schedule is untouched.
    expect(repo.schedules['scan']!.cron, '0 3 * * *');
  });

  testWidgets('a valid save stores cron and enablement', (tester) async {
    final repo = FakeRepository();
    final container = appContainer(repo: repo);
    await _pump(tester, container);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.scheduleEnabled('backup')),
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.scheduleCron('backup')),
      '30 4 * * 1',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.scheduleSave('backup')),
    );
    await tester.pumpAndSettle();

    expect(repo.schedules['backup']!.cron, '30 4 * * 1');
    expect(repo.schedules['backup']!.enabled, isTrue);
  });
}

/// Fails the first read at once and holds every retry, as a server that
/// has gone away does.
class _SchedulesDown extends FakeRepository {
  var _reads = 0;

  @override
  Future<List<Schedule>> listSchedules() async {
    if (_reads++ > 0) await Completer<void>().future;
    throw const WaxDeckApiException(
      code: 'internal',
      message: 'down',
      statusCode: 500,
    );
  }
}
