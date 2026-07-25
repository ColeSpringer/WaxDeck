import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/users_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';
import 'routed_host.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: routedHost(const UsersScreen()),
);

UserAccount _account(
  String id, {
  String username = 'barliman',
  List<String> roles = const ['user'],
  bool disabled = false,
  bool pending = false,
}) => UserAccount(
  id: id,
  username: username,
  roles: roles,
  createdAt: DateTime.utc(2026, 7, 1),
  libraryAccess: const LibraryAccess(mode: 'all'),
  disabled: disabled,
  pending: pending,
);

void main() {
  testWidgets('lists accounts with role chips and state badges', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.usersById['us-1'] = _account(
      'us-1',
      username: 'gandalf',
      roles: const ['admin'],
    );
    repo.usersById['us-2'] = _account(
      'us-2',
      username: 'lotho',
      disabled: true,
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    final adminRow = find.byKey(const ValueKey('user-row-us-1'));
    expect(adminRow, findsOneWidget);
    expect(
      find.descendant(of: adminRow, matching: find.text('admin')),
      findsOneWidget,
    );
    final disabledRow = find.byKey(const ValueKey('user-row-us-2'));
    expect(
      find.descendant(of: disabledRow, matching: find.text('disabled')),
      findsOneWidget,
    );
  });

  testWidgets('approving a request rides the editor choices along', (
    tester,
  ) async {
    // Tall viewport: the editor's save button must be built, not lazy.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeRepository();
    repo.usersById['us-9'] = _account(
      'us-9',
      username: 'pippin',
      pending: true,
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Requests'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('request-row-us-9')), findsOneWidget);

    await tester.tap(find.byKey(const Key('request-approve-us-9')));
    await tester.pumpAndSettle();

    // Grant the admin role and uploads in the prefilled editor.
    await tester.tap(find.byKey(const Key('user-admin-role')));
    await tester.tap(find.byKey(const Key('user-upload-enabled')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('user-save')));
    await tester.tap(find.byKey(const Key('user-save')));
    await tester.pumpAndSettle();

    final call = repo.approveSignupCalls.single;
    expect(call.userId, 'us-9');
    expect(call.roles, ['admin']);
    expect(call.uploadEnabled, isTrue);
    expect(repo.usersById['us-9']!.pending, isFalse);
    // Back on the requests tab, the request is gone.
    expect(find.byKey(const ValueKey('request-row-us-9')), findsNothing);
  });

  testWidgets('rejecting a request removes it after the confirm', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.usersById['us-9'] = _account(
      'us-9',
      username: 'wormtongue',
      pending: true,
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Requests'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('request-reject-us-9')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('request-reject-confirm')));
    await tester.pumpAndSettle();

    expect(repo.rejectSignupCalls, ['us-9']);
    expect(find.byKey(const ValueKey('request-row-us-9')), findsNothing);
  });

  testWidgets('creating an invite shows the one-time token', (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Invites'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('invite-create')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('invite-note')), 'For Samwise');
    await tester.tap(find.byKey(const Key('invite-create-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('invite-token')), findsOneWidget);
    expect(find.text('invite-token-0'), findsOneWidget);
    expect(repo.invitesById.values.single.note, 'For Samwise');
  });

  testWidgets('revoking an invite flags the row', (tester) async {
    final repo = FakeRepository();
    repo.invitesById['iv-1'] = Invite(
      id: 'iv-1',
      note: 'Old invite',
      roles: const ['user'],
      maxUses: 5,
      usedCount: 2,
      createdAt: DateTime.utc(2026, 7, 1),
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Invites'));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('invite-row-iv-1'));
    expect(
      find.descendant(of: row, matching: find.text('user, uses 2/5')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('invite-revoke-iv-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('invite-revoke-confirm')));
    await tester.pumpAndSettle();

    expect(repo.revokeInviteCalls, ['iv-1']);
    expect(
      find.descendant(of: row, matching: find.text('revoked')),
      findsOneWidget,
    );
  });
}
