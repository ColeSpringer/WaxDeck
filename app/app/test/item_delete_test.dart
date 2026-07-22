import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/library/item_delete.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

const _admin = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  username: 'admin',
  roles: ['admin'],
);

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
  ],
  child: const MaterialApp(
    home: Scaffold(
      body: Center(child: ItemDeleteAction(pid: 'tr-1')),
    ),
  ),
);

void main() {
  testWidgets('previews with a dry run, then deletes with the chosen mode', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
      items: [testItem('tr-1')],
    );
    repo.deletePlansByPid['tr-1'] = const DeletePlanEntry(
      pid: 'tr-1',
      name: 'Prancing Pony Blues',
      files: 3,
      bytes: 5 * 1024 * 1024,
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('item-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete files...'));
    await tester.pumpAndSettle();

    // The preview came from a dry run: nothing deleted yet.
    expect(repo.deleteItemsCalls.single.dryRun, isTrue);
    expect(repo.libraryItems, hasLength(1));
    expect(find.text('This removes 3 files, 5.0 MB.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('item-delete-mode-permanent')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-delete-confirm')));
    await tester.pumpAndSettle();

    final applied = repo.deleteItemsCalls.last;
    expect(applied.dryRun, isFalse);
    expect(applied.mode, 'permanent');
    expect(repo.libraryItems, isEmpty);
    expect(find.text('Deleted 3 files for good'), findsOneWidget);
  });

  testWidgets('cancelling the dialog deletes nothing', (tester) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
      items: [testItem('tr-1')],
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('item-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete files...'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repo.deleteItemsCalls, hasLength(1));
    expect(repo.deleteItemsCalls.single.dryRun, isTrue);
    expect(repo.libraryItems, hasLength(1));
  });

  testWidgets('hidden for non-administrators', (tester) async {
    final repo = FakeRepository(
      sessionState: const SessionState(
        authenticated: true,
        user: WaxDeckUser(id: 'us-2', username: 'sam', roles: ['user']),
      ),
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-delete')), findsNothing);
  });
}
