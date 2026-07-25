import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/settings_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';
import 'routed_host.dart';

const _user = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  username: 'admin',
  roles: ['admin'],
);

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
  ],
  child: routedHost(const SettingsScreen()),
);

FakeRepository _signedInRepo() => FakeRepository(
  sessionState: const SessionState(authenticated: true, user: _user),
);

Future<void> _show(WidgetTester tester, Key key) => tester.scrollUntilVisible(
  find.byKey(key),
  200,
  scrollable: find.byType(Scrollable).first,
);

void main() {
  testWidgets('the shared-stats switch round-trips the opt-out', (
    tester,
  ) async {
    final repo = _signedInRepo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await _show(tester, const Key('shared-stats-switch'));
    // Nothing stored yet reads as included.
    var tile = tester.widget<SwitchListTile>(
      find.byKey(const Key('shared-stats-switch')),
    );
    expect(tile.value, isTrue);

    await tester.tap(find.byKey(const Key('shared-stats-switch')));
    await tester.pumpAndSettle();
    expect(repo.prefs.sharedStatsOptOut, isTrue);
    tile = tester.widget<SwitchListTile>(
      find.byKey(const Key('shared-stats-switch')),
    );
    expect(tile.value, isFalse);

    await tester.tap(find.byKey(const Key('shared-stats-switch')));
    await tester.pumpAndSettle();
    expect(repo.prefs.sharedStatsOptOut, isFalse);
  });

  testWidgets('the timezone editor saves and shows the stored zone', (
    tester,
  ) async {
    final repo = _signedInRepo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await _show(tester, const Key('timezone-edit'));
    await tester.tap(find.byKey(const Key('timezone-edit')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('timezone-field')),
      'Europe/Amsterdam',
    );
    await tester.tap(find.byKey(const Key('timezone-save')));
    await tester.pumpAndSettle();

    expect(repo.prefs.timezone, 'Europe/Amsterdam');
    expect(find.byKey(const Key('timezone-field')), findsNothing);
    expect(find.text('Europe/Amsterdam'), findsOneWidget);
  });

  testWidgets('a rejected timezone shows the server message in place', (
    tester,
  ) async {
    final repo = _signedInRepo()
      ..putPrefsError = const WaxDeckApiException(
        code: 'invalid-request',
        message: 'unknown timezone',
        statusCode: 400,
      );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await _show(tester, const Key('timezone-edit'));
    await tester.tap(find.byKey(const Key('timezone-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('timezone-field')),
      'Middle/Earth',
    );
    await tester.tap(find.byKey(const Key('timezone-save')));
    await tester.pumpAndSettle();

    // The dialog stays open with the validation feedback.
    expect(find.byKey(const Key('timezone-field')), findsOneWidget);
    expect(find.text('unknown timezone'), findsOneWidget);
    expect(repo.prefs.timezone, isNull);
  });

  testWidgets('the share-links row opens the shares screen', (tester) async {
    final repo = _signedInRepo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await _show(tester, const Key('open-share-links'));
    await tester.tap(find.byKey(const Key('open-share-links')));
    await tester.pumpAndSettle();

    expect(find.text('No share links yet'), findsOneWidget);
  });

  testWidgets('administrators see the sonic-similarity coverage', (
    tester,
  ) async {
    final repo = _signedInRepo()
      ..similarityStatus = const SimilarityStatus(
        enabled: true,
        model: 'wax-embed-1',
        dims: 512,
        embeddedTracks: 80,
        totalTracks: 100,
        coveragePct: 80,
        queueDepth: 5,
      );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await _show(tester, const Key('similarity-status'));
    expect(find.text('Coverage 80%'), findsOneWidget);
    expect(find.text('80 of 100 tracks analyzed, 5 queued'), findsOneWidget);
  });
  testWidgets('clearing the timezone returns to the server default', (
    tester,
  ) async {
    final repo = _signedInRepo()
      ..prefs = const Prefs(timezone: 'Europe/Amsterdam');
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await _show(tester, const Key('timezone-edit'));
    await tester.tap(find.byKey(const Key('timezone-edit')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('timezone-field')), '');
    await tester.tap(find.byKey(const Key('timezone-save')));
    await tester.pumpAndSettle();

    expect(repo.prefs.timezone, isNull);
    expect(find.text('Server default'), findsOneWidget);
  });
}
