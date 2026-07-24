import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/health/diagnostics_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: const MaterialApp(home: DiagnosticsScreen()),
);

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
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    // Both codes show as chips and both rows render.
    expect(
      find.byKey(const Key('diagnostic-chip-unsupported_format')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('diagnostic-chip-tag_write_unsynced')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('diagnostic-row-/music/a.wma')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('diagnostic-row-/music/b.flac')),
      findsOneWidget,
    );

    // Filtering by a code narrows the list to that code.
    await tester.tap(
      find.byKey(const Key('diagnostic-chip-unsupported_format')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('diagnostic-row-/music/a.wma')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('diagnostic-row-/music/b.flac')), findsNothing);
  });
}
