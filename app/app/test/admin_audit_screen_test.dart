import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/audit_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: const MaterialApp(home: AuditScreen()),
);

void main() {
  testWidgets('renders events and expands to the pretty detail', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.auditEvents = [
      AuditEvent(
        id: 'au-1',
        actorName: 'gandalf',
        action: 'user.create',
        targetName: 'pippin',
        detail: const {
          'roles': ['user'],
        },
        createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
      ),
      AuditEvent(
        id: 'au-2',
        action: 'backup.create',
        createdAt: DateTime.now().toUtc().subtract(const Duration(days: 3)),
      ),
    ];
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    final row = find.bySemanticsIdentifier('audit-row-au-1');
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('gandalf, pippin, 2h ago')),
      findsOneWidget,
    );
    // The system-actor row falls back to "system".
    expect(find.textContaining('system, 3d ago'), findsOneWidget);

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.textContaining('"roles"'), findsOneWidget);
  });

  testWidgets('the action filter narrows the list and clears', (tester) async {
    final repo = FakeRepository();
    repo.auditEvents = [
      AuditEvent(
        id: 'au-1',
        action: 'user.create',
        createdAt: DateTime.utc(2026, 7, 20),
      ),
      AuditEvent(
        id: 'au-2',
        action: 'backup.create',
        createdAt: DateTime.utc(2026, 7, 19),
      ),
    ];
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();
    expect(find.bySemanticsIdentifier('audit-row-au-2'), findsOneWidget);

    await tester.enterText(find.bySemanticsIdentifier('audit-filter'), 'user.');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier('audit-row-au-1'), findsOneWidget);
    expect(find.bySemanticsIdentifier('audit-row-au-2'), findsNothing);

    await tester.tap(find.bySemanticsIdentifier('audit-filter-clear'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsIdentifier('audit-row-au-2'), findsOneWidget);
  });
}
