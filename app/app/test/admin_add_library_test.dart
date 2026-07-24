import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/server_settings_section.dart';
import 'package:waxdeck/src/providers.dart';

import 'fakes.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: const ServerSettingsSection(),
      ),
    ),
  ),
);

void main() {
  testWidgets('adding a library creates it and refreshes the list', (
    tester,
  ) async {
    final repo = FakeRepository();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('add-library-name')),
      'audiobooks',
    );
    await tester.enterText(
      find.byKey(const Key('add-library-path')),
      '/srv/media/audiobooks',
    );
    await tester.ensureVisible(find.byKey(const Key('add-library-create')));
    await tester.tap(find.byKey(const Key('add-library-create')));
    await tester.pumpAndSettle();

    // The create call reached the repository and the list picked it up.
    expect(repo.libraries.map((l) => l.name), contains('audiobooks'));
    expect(find.textContaining('Library "audiobooks" created'), findsOneWidget);
    // The new root now shows in the per-library read-only section.
    expect(find.text('audiobooks'), findsWidgets);
  });

  testWidgets('a blank name or path is refused before any call', (
    tester,
  ) async {
    final repo = FakeRepository();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('add-library-create')));
    await tester.tap(find.byKey(const Key('add-library-create')));
    await tester.pumpAndSettle();

    expect(repo.libraries, isEmpty);
    expect(
      find.textContaining('name and an absolute path are required'),
      findsOneWidget,
    );
  });
}
