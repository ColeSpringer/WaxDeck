import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/dashboard_screen.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';
import 'routed_host.dart';

/// The dashboard says whether playback goes through the streaming engine:
/// connected, unreachable (originals playing directly meanwhile), or a
/// server that runs without one.
void main() {
  final en = AppLocalizationsEn();
  Finder tile() =>
      find.bySemanticsIdentifier(SemanticsIds.adminTile('streaming'));

  Future<void> pump(WidgetTester tester, ServerStreaming? streaming) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeRepository()..serverStreaming = streaming;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        ],
        child: routedHost(const AdminDashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder inTile(String text) =>
      find.descendant(of: tile(), matching: find.text(text));

  testWidgets('a connected engine reads connected', (tester) async {
    await pump(
      tester,
      const ServerStreaming(configured: true, connected: true, timelines: true),
    );
    expect(inTile(en.adminTileStreaming), findsOneWidget);
    expect(inTile(en.adminStreamingConnected), findsOneWidget);
  });

  testWidgets('an engine that is away reads unreachable, and what plays', (
    tester,
  ) async {
    await pump(
      tester,
      const ServerStreaming(configured: true, connected: false),
    );
    expect(inTile(en.adminStreamingUnreachable), findsOneWidget);
    expect(inTile(en.adminStreamingDirect), findsOneWidget);
  });

  testWidgets('a server without one says it is not configured', (tester) async {
    await pump(
      tester,
      const ServerStreaming(configured: false, connected: false),
    );
    expect(inTile(en.adminStreamingNotConfigured), findsOneWidget);
    expect(inTile(en.adminStreamingDirect), findsNothing);
  });

  testWidgets('a server too old to say gets no tile', (tester) async {
    await pump(tester, null);
    expect(tile(), findsNothing);
  });
}
