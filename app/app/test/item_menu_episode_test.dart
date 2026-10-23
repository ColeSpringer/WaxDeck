import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/library/item_menu.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

/// Opens an item's sheet as a row's kebab does.
class _Opener extends ConsumerWidget {
  const _Opener({required this.mediaType});

  final MediaType mediaType;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: WaxButton(
        label: 'open',
        onPressed: () => showItemMenuSheet(
          context,
          ref,
          pid: 'tr-01JZX5N8QW3F4V9T2B7KDITEM01',
          title: 'Something',
          mediaType: mediaType,
        ),
      ),
    ),
  );
}

/// An episode's files are its download's, which the podcast screens
/// offer to remove; the library's delete, which the server refuses for an
/// episode, is not on its sheet, even for an administrator.
void main() {
  for (final (mediaType, offered) in [
    (MediaType.podcast, findsNothing),
    (MediaType.music, findsOneWidget),
  ]) {
    testWidgets('an administrator\'s sheet for ${mediaType.name} '
        '${offered == findsNothing ? 'offers no' : 'offers the'} delete', (
      tester,
    ) async {
      final repo = FakeRepository(
        sessionState: const SessionState(
          authenticated: true,
          user: WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            credentialStoreProvider.overrideWithValue(
              InMemoryCredentialStore(),
            ),
          ],
          child: routedHost(_Opener(mediaType: mediaType)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier(SemanticsIds.itemMenuDelete), offered);
    });
  }
}
