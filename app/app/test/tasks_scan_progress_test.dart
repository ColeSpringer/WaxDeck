import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/tools/tasks_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

const _admin = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  username: 'admin',
  roles: ['admin'],
);

void main() {
  testWidgets('a running scan draws how far it is, and a job that cannot '
      'say draws a bar that moves', (tester) async {
    final started = DateTime.utc(2026, 10, 1, 9);
    final repo =
        FakeRepository(
            sessionState: const SessionState(authenticated: true, user: _admin),
          )
          ..jobs = [
            Job(
              pid: 'jb-scan',
              kind: 'scan',
              state: 'running',
              progress: 0.42,
              startedAt: started,
            ),
            Job(
              pid: 'jb-enrich',
              kind: 'enrich',
              state: 'running',
              startedAt: started,
            ),
          ];
    await mountApp(
      tester,
      const TasksScreen(),
      container: appContainer(repo: repo),
    );
    // Pumped by frame: the indeterminate bar animates for as long as it
    // is drawn, so the tree never settles.
    await tester.pump();
    await tester.pump();

    Finder row(String pid) =>
        find.bySemanticsIdentifier(SemanticsIds.jobRow(pid));
    WaxProgressBar bar(String pid) => tester.widget<WaxProgressBar>(
      find.descendant(of: row(pid), matching: find.byType(WaxProgressBar)),
    );
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(bar('jb-scan').value, 0.42);
    expect(
      find.descendant(
        of: row('jb-scan'),
        matching: find.text(l10n.toolsStateRunningPct(42)),
      ),
      findsOneWidget,
    );
    expect(bar('jb-enrich').value, isNull);
    expect(
      find.descendant(
        of: row('jb-enrich'),
        matching: find.text(l10n.toolsStateRunning),
      ),
      findsOneWidget,
    );
  });
}
