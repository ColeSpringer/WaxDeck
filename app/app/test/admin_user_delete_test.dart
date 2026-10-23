import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/users_screen.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

const _admin = WaxDeckUser(id: 'us-0', username: 'admin', roles: ['admin']);

FakeRepository _repo() {
  final repo = FakeRepository(
    sessionState: const SessionState(authenticated: true, user: _admin),
  );
  repo.usersById['us-3'] = UserAccount(
    id: 'us-3',
    username: 'merry',
    roles: const ['user'],
    createdAt: DateTime.utc(2026, 7, 1),
    libraryAccess: const LibraryAccess(mode: 'all'),
  );
  return repo;
}

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
  ],
  child: routedHost(const UsersScreen()),
);

Future<void> _openDeleteDialog(
  WidgetTester tester, {
  Size size = const Size(1200, 4000),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.userRow('us-3')));
  await tester.pumpAndSettle();
  final delete = find.bySemanticsIdentifier(SemanticsIds.userDelete);
  await tester.ensureVisible(delete);
  await tester.pumpAndSettle();
  // The account's own page is laid out for the width it has, in the test's
  // wide placeholder font; what a test here asks of the layout is the
  // dialog's, so what the page behind it reports is not counted.
  tester.takeException();
  await tester.tap(delete, warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('deleting an account hands its shared playlists over by default', (
    tester,
  ) async {
    final repo = _repo();
    await tester.pumpWidget(_host(repo));
    await _openDeleteDialog(tester);

    expect(find.text('Delete account?'), findsOneWidget);
    // Both answers on screen at once, each with what it costs, and the
    // one that keeps people's playlists is the one already chosen.
    final hand = find.bySemanticsIdentifier(
      SemanticsIds.userDeletePlaylists('transfer'),
    );
    expect(hand, findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.userDeletePlaylists('delete')),
      findsOneWidget,
    );
    expect(find.text('Hand their shared playlists to me'), findsOneWidget);
    expect(
      find.textContaining('Their private playlists are deleted'),
      findsOneWidget,
    );
    // What a smart playlist becomes when it depends on the account.
    expect(
      find.textContaining(
        'A smart playlist that depends on their stars, ratings, plays or '
        'private playlists becomes a fixed list of its tracks.',
      ),
      findsOneWidget,
    );
    // The dialog says what happens to their links, whichever answer is chosen.
    expect(
      find.textContaining('share links, which stop working'),
      findsOneWidget,
    );
    expect(find.text('Delete their playlists'), findsOneWidget);
    expect(tester.getSemantics(hand), isSemantics(isChecked: true));

    await tester.tap(find.byKey(const Key('user-confirm')));
    await tester.pumpAndSettle();

    expect(repo.deletedUserIds, ['us-3']);
    expect(repo.deletedUserPlaylists, ['transfer']);
  });

  testWidgets('the other answer deletes the playlists', (tester) async {
    final repo = _repo();
    await tester.pumpWidget(_host(repo));
    await _openDeleteDialog(tester);

    final remove = find.bySemanticsIdentifier(
      SemanticsIds.userDeletePlaylists('delete'),
    );
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(tester.getSemantics(remove), isSemantics(isChecked: true));

    await tester.tap(find.byKey(const Key('user-confirm')));
    await tester.pumpAndSettle();

    expect(repo.deletedUserPlaylists, ['delete']);
  });

  // The dialog's two answers each carry a line of what they cost, which on
  // a phone is more than the screen holds: the content scrolls, so the
  // lower answer can be reached and a tap meant for it never lands on the
  // button under it.
  for (final (:name, :size, :scale)
      in <({String name, Size size, double scale})>[
        (name: 'a short phone', size: const Size(360, 640), scale: 1.0),
        (
          name: 'a short phone with larger text',
          size: const Size(360, 640),
          scale: 1.5,
        ),
        (
          name: 'a tall phone with larger text',
          size: const Size(393, 852),
          scale: 1.5,
        ),
        (name: 'a phone on its side', size: const Size(640, 360), scale: 1.0),
      ]) {
    testWidgets('the lower answer is reachable on $name', (tester) async {
      final repo = _repo();
      await tester.pumpWidget(_host(repo));
      await _openDeleteDialog(tester, size: size, textScale: scale);

      final remove = find.bySemanticsIdentifier(
        SemanticsIds.userDeletePlaylists('delete'),
      );
      await tester.ensureVisible(remove);
      await tester.pumpAndSettle();
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(tester.getSemantics(remove), isSemantics(isChecked: true));

      await tester.ensureVisible(find.byKey(const Key('user-confirm')));
      await tester.tap(find.byKey(const Key('user-confirm')));
      await tester.pumpAndSettle();

      expect(repo.deletedUserPlaylists, ['delete']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cancelling deletes nothing', (tester) async {
    final repo = _repo();
    await tester.pumpWidget(_host(repo));
    await _openDeleteDialog(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repo.deletedUserIds, isEmpty);
    expect(repo.usersById, contains('us-3'));
  });
}
