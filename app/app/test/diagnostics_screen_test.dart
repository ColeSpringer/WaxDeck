import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/health/diagnostics_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: const MaterialApp(home: DiagnosticsScreen()),
);

/// Wide enough for the table to be a table rather than a card list.
Future<void> _pump(WidgetTester tester, Widget host) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(host);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows summary chips and rows, and filters by code', (
    tester,
  ) async {
    final repo = FakeRepository();
    final now = DateTime.utc(2026, 7, 20);
    repo.diagnosticCounts.addAll([
      const DiagnosticCount(
        origin: 'scan',
        code: 'unsupported_format',
        severity: 'info',
        count: 2,
      ),
      const DiagnosticCount(
        origin: 'edit',
        code: 'tag_write_unsynced',
        severity: 'warn',
        count: 1,
      ),
    ]);
    repo.fileDiagnostics.addAll([
      FileDiagnostic(
        path: '/music/a.wma',
        origin: 'scan',
        code: 'unsupported_format',
        severity: 'info',
        seenAt: now,
      ),
      FileDiagnostic(
        path: '/music/b.flac',
        origin: 'edit',
        code: 'tag_write_unsynced',
        severity: 'warn',
        seenAt: now,
      ),
    ]);
    await _pump(tester, _host(repo));

    // Both codes show as chips and both rows render.
    expect(
      find.bySemanticsIdentifier(
        SemanticsIds.diagnosticCode('unsupported_format'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(
        SemanticsIds.diagnosticCode('tag_write_unsynced'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.diagnosticRow('/music/a.wma')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.diagnosticRow('/music/b.flac')),
      findsOneWidget,
    );

    // Filtering by a code narrows the list to that code.
    await tester.tap(
      find.bySemanticsIdentifier(
        SemanticsIds.diagnosticCode('unsupported_format'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.diagnosticRow('/music/a.wma')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.diagnosticRow('/music/b.flac')),
      findsNothing,
    );

    // And pressing the lit chip again clears it: the row is the filter
    // as well as the summary, so the cleared state has to be reachable
    // from it.
    await tester.tap(
      find.bySemanticsIdentifier(
        SemanticsIds.diagnosticCode('unsupported_format'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.diagnosticRow('/music/b.flac')),
      findsOneWidget,
    );
  });
}
