import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/organize/organize_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

const _admin = WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']);

/// The whole app over [repo], answering its router.
Future<GoRouter> _pumpApp(WidgetTester tester, FakeRepository repo) async {
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const WaxDeckApp()),
  );
  await tester.pumpAndSettle();
  return container.read(routerProvider);
}

void main() {
  testWidgets(
    'the organize location runs a dry run only when it asks for one',
    (tester) async {
      final repo = FakeRepository(
        sessionState: const SessionState(authenticated: true, user: _admin),
      );
      final router = await _pumpApp(tester, repo);
      // User input in a URL: a value the location does not name opens the
      // screen and runs nothing.
      router.go('${WaxRoute.organize}?${WaxRoute.organizePreviewParam}=x');
      await tester.pumpAndSettle();
      expect(find.byType(OrganizeScreen), findsOneWidget);
      expect(repo.previewOrganizeCalls, isEmpty);

      // Opened cold, as a link the path rule's fix shares.
      router.go(WaxRoute.home);
      await tester.pumpAndSettle();
      router.go(WaxRoute.organizePreviewOwn);
      await tester.pumpAndSettle();
      expect(find.byType(OrganizeScreen), findsOneWidget);
      expect(repo.previewOrganizeCalls, hasLength(1));
      expect(repo.previewOrganizeCalls.single.profile, isNull);
    },
  );
}
