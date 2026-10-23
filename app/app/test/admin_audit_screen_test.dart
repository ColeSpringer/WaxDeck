import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/audit_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'disclosure_glyph.dart';
import 'fakes.dart';
import 'localized_host.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: localizedHost(const AuditScreen()),
);

void main() {
  testWidgets('a row points right while closed and down while open', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.auditEvents = [
      AuditEvent(
        id: 'au-1',
        action: 'user.create',
        detail: const {
          'roles': ['user'],
        },
        createdAt: DateTime.utc(2026, 7, 1),
      ),
    ];
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();
    final row = find.bySemanticsIdentifier(SemanticsIds.auditRow('au-1'));

    expectDisclosure(tester, row, open: false);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expectDisclosure(tester, row, open: true);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expectDisclosure(tester, row, open: false);
  });

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

    final row = find.bySemanticsIdentifier(SemanticsIds.auditRow('au-1'));
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

  testWidgets('a change renders from and to, above the stored detail', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.auditEvents = [
      AuditEvent(
        id: 'au-1',
        actorName: 'gandalf',
        action: 'user.update',
        targetName: 'pippin',
        detail: const {
          'changes': {
            'displayName': {'from': '', 'to': 'Pip'},
            'permissions.download': {'from': true, 'to': false},
            'roles': {
              'from': ['user'],
              'to': ['user', 'admin'],
            },
          },
        },
        createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
      ),
      AuditEvent(
        id: 'au-2',
        action: 'user.create',
        detail: const {
          'roles': ['user'],
        },
        createdAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
      ),
    ];
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    // Collapsed, a row is its action and who did it, nothing more.
    expect(find.textContaining(' -> '), findsNothing);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.auditRow('au-1')));
    await tester.pumpAndSettle();

    final name = find.text('displayName: "" -> Pip');
    expect(name, findsOneWidget);
    expect(find.text('permissions.download: true -> false'), findsOneWidget);
    expect(
      find.text('roles: ["user"] -> ["user","admin"]'),
      findsOneWidget,
      reason: 'a list reads as the list it is',
    );
    // The stored detail is still there for whoever wants it whole, below.
    final json = find.textContaining('"changes"');
    expect(json, findsOneWidget);
    expect(
      tester.getTopLeft(name).dy,
      lessThan(tester.getTopLeft(json).dy),
      reason: 'the readable rows come first',
    );

    // An event that recorded no change shows its detail alone.
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.auditRow('au-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.auditRow('au-2')));
    await tester.pumpAndSettle();
    expect(find.textContaining(' -> '), findsNothing);
    expect(find.textContaining('"roles"'), findsOneWidget);
  });

  testWidgets('a changes block that is not from and to is left to the JSON', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.auditEvents = [
      AuditEvent(
        id: 'au-1',
        action: 'user.update',
        detail: const {
          'changes': {
            'roles': 'admin',
            'disabled': {'to': true},
          },
        },
        createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
      ),
    ];
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.auditRow('au-1')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining(' -> '), findsNothing);
    expect(find.textContaining('"changes"'), findsOneWidget);
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
    expect(
      find.bySemanticsIdentifier(SemanticsIds.auditRow('au-2')),
      findsOneWidget,
    );

    await tester.enterText(find.bySemanticsIdentifier('audit-filter'), 'user.');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.auditRow('au-1')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.auditRow('au-2')),
      findsNothing,
    );

    await tester.tap(find.bySemanticsIdentifier('audit-filter-clear'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.auditRow('au-2')),
      findsOneWidget,
    );
  });
}
