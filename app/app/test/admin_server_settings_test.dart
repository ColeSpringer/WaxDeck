import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/server_settings_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';

ProviderContainer _container(FakeRepository repo) {
  final container = ProviderContainer(
    overrides: [repositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _host(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: const MaterialApp(home: ServerSettingsScreen()),
);

Future<void> _pump(WidgetTester tester, Widget host) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(host);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('toggling signup and read-only saves server-wide', (
    tester,
  ) async {
    final repo = FakeRepository();
    await _pump(tester, _host(_container(repo)));

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.settingSignupEnabled),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(repo.adminSettings.signupEnabled, isTrue);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.settingReadOnly),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(repo.adminSettings.readOnly, isTrue);
    // The first toggle survived the second save.
    expect(repo.adminSettings.signupEnabled, isTrue);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.settingSonicAnalysis),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(repo.adminSettings.sonicAnalysis, isFalse);
    expect(repo.adminSettings.readOnly, isTrue);
  });

  testWidgets('saves transcoding limits', (tester) async {
    final repo = FakeRepository();
    final container = _container(repo);
    await _pump(tester, _host(container));

    await tester.enterText(
      find.bySemanticsIdentifier('transcoding-max-concurrent'),
      '4',
    );
    await tester.enterText(
      find.bySemanticsIdentifier('transcoding-default-kbps'),
      '256',
    );
    await tester.ensureVisible(find.bySemanticsIdentifier('transcoding-save'));
    await tester.tap(
      find.bySemanticsIdentifier('transcoding-save'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(repo.transcodingLimits.maxConcurrent, 4);
    expect(repo.transcodingLimits.defaultMaxBitrateKbps, 256);
    expect(
      container.read(shellMessengerProvider)?.text,
      'Transcoding limits saved',
    );
  });

  // Refused outright rather than silently stored as the old value while
  // reporting success.
  testWidgets('a retention that is not a whole number is refused', (
    tester,
  ) async {
    final repo = FakeRepository();
    final container = _container(repo);
    await _pump(tester, _host(container));

    await tester.enterText(
      find.bySemanticsIdentifier('trash-retention-days'),
      'soon',
    );
    await tester.ensureVisible(
      find.bySemanticsIdentifier('trash-retention-save'),
    );
    await tester.tap(
      find.bySemanticsIdentifier('trash-retention-save'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(
      container.read(shellMessengerProvider)?.text,
      contains('whole number of days'),
    );

    await tester.enterText(
      find.bySemanticsIdentifier('trash-retention-days'),
      '007',
    );
    await tester.tap(
      find.bySemanticsIdentifier('trash-retention-save'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(repo.adminSettings.trashRetentionDays, 7);
    // Reflected back as what was stored, not as what was typed.
    expect(find.text('7'), findsOneWidget);
  });
}
