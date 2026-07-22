import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/server_settings_section.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: const MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: ServerSettingsSection())),
  ),
);

void main() {
  testWidgets('toggling signup and read-only saves server-wide', (
    tester,
  ) async {
    final repo = FakeRepository();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('setting-signup-enabled')));
    await tester.pumpAndSettle();
    expect(repo.adminSettings.signupEnabled, isTrue);

    await tester.tap(find.byKey(const Key('setting-read-only')));
    await tester.pumpAndSettle();
    expect(repo.adminSettings.readOnly, isTrue);
    // The first toggle survived the second save.
    expect(repo.adminSettings.signupEnabled, isTrue);

    await tester.tap(find.byKey(const Key('setting-sonic-analysis')));
    await tester.pumpAndSettle();
    expect(repo.adminSettings.sonicAnalysis, isFalse);
    expect(repo.adminSettings.readOnly, isTrue);
  });

  testWidgets('saves transcoding limits and per-library read-only', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.libraries.add(const LibraryInfo(pid: 'li-1', name: 'Music'));
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('transcoding-max-concurrent')),
      '4',
    );
    await tester.enterText(
      find.byKey(const Key('transcoding-default-kbps')),
      '256',
    );
    await tester.ensureVisible(find.byKey(const Key('transcoding-save')));
    await tester.tap(find.byKey(const Key('transcoding-save')));
    await tester.pumpAndSettle();

    expect(repo.transcodingLimits.maxConcurrent, 4);
    expect(repo.transcodingLimits.defaultMaxBitrateKbps, 256);
    expect(find.text('Transcoding limits saved'), findsOneWidget);

    // Let the save snackbar expire; it overlaps the bottom rows and
    // would swallow the tap.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('library-read-only-li-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-read-only-li-1')));
    await tester.pumpAndSettle();
    expect(repo.libraryReadOnlyByPid['li-1'], isTrue);
  });
}
