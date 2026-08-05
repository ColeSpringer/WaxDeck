import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/users_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
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

    final adminRow = find.bySemanticsIdentifier('user-row-us-1');
    expect(adminRow, findsOneWidget);
    expect(
      find.descendant(of: adminRow, matching: find.text('admin')),
      findsOneWidget,
    );
    // The state is a column of its own now rather than a chip beside
    // the name: a table row says active, pending, or disabled once.
    final disabledRow = find.bySemanticsIdentifier('user-row-us-2');
    expect(
      find.descendant(of: disabledRow, matching: find.text('Disabled')),
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
    await tester.tap(
      find.bySemanticsIdentifier('user-admin-role'),
      warnIfMissed: false,
    );
    await tester.tap(
      find.bySemanticsIdentifier('user-upload-enabled'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.bySemanticsIdentifier('user-save'));
    await tester.tap(
      find.bySemanticsIdentifier('user-save'),
      warnIfMissed: false,
    );
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
  // Kids mode is admin-configured in v1 by decision: there is no
  // kid-facing UI, so the preset is the whole of it. One press, and
  // everything it set stays editable.
  testWidgets('the child preset locks the account down in one press', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeRepository();
    repo.usersById['us-3'] = _account('us-3', username: 'merry');
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier('user-row-us-3'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.userChildPreset),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.bySemanticsIdentifier('user-save'));
    await tester.tap(
      find.bySemanticsIdentifier('user-save'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    final stored = repo.usersById['us-3']!;
    expect(stored.roles, ['user']);
    expect(stored.uploadEnabled, isFalse);
    expect(stored.permissions.download, isFalse);
    expect(stored.permissions.delete, isFalse);
    expect(stored.permissions.explicitContent, isFalse);
    // A deny rule for what files actually carry: there is no canonical
    // explicit flag in music metadata, so the advisory tag is what the
    // rules act on.
    expect(
      stored.permissions.tagDeny.map((r) => '${r.key}=${r.value}'),
      contains('ITUNESADVISORY=1'),
    );
  });
}
