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

  // The limits are set blind without it: three ceilings and nothing
  // saying what they are actually bounding.
  testWidgets('the limits say what the engine is running right now', (
    tester,
  ) async {
    final repo = FakeRepository()..activeTranscodeSessions = 3;
    await _pump(tester, _host(_container(repo)));

    expect(
      find.bySemanticsIdentifier(SemanticsIds.transcodingActivity),
      findsOneWidget,
    );
    expect(find.text('3 engine-backed streams right now.'), findsOneWidget);
    // The copy says what the number is not, because it both under- and
    // over-counts what somebody means by "transcoding".
    expect(find.textContaining('HLS timelines are admitted'), findsOneWidget);
    // Read once when the screen opened. A settings form is not a
    // monitor, and nothing here polls.
    expect(repo.transcodingActivityReads, 1);
  });

  testWidgets('the running count refreshes when asked, and only then', (
    tester,
  ) async {
    final repo = FakeRepository()..activeTranscodeSessions = 1;
    await _pump(tester, _host(_container(repo)));
    expect(find.text('1 engine-backed stream right now.'), findsOneWidget);

    repo.activeTranscodeSessions = 5;
    await tester.pump(const Duration(seconds: 30));
    // Still one: nothing arrives on a timer.
    expect(repo.transcodingActivityReads, 1);

    await tester.ensureVisible(
      find.bySemanticsIdentifier(SemanticsIds.transcodingActivityRefresh),
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.transcodingActivityRefresh),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(repo.transcodingActivityReads, 2);
    expect(find.text('5 engine-backed streams right now.'), findsOneWidget);
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

    // Named, not just refused: one save writes two windows.
    expect(
      container.read(shellMessengerProvider)?.text,
      allOf(contains('whole number of days'), contains('Purge trashed files')),
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
    // The task window rode along untouched.
    expect(repo.adminSettings.taskRetentionDays, 30);
  });

  testWidgets('a bad task window names itself, not the trash one', (
    tester,
  ) async {
    final repo = FakeRepository();
    final container = _container(repo);
    await _pump(tester, _host(container));

    // The trash field is fine; the message has to name the other one.
    await tester.enterText(
      find.bySemanticsIdentifier('task-retention-days'),
      'never',
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
      allOf(contains('whole number of days'), contains('Clear finished tasks')),
    );
    // And nothing was stored: a refused save writes neither window.
    expect(repo.adminSettings.taskRetentionDays, 30);
  });

  testWidgets('the task window saves beside the trash one', (tester) async {
    final repo = FakeRepository();
    final container = _container(repo);
    await _pump(tester, _host(container));

    await tester.enterText(
      find.bySemanticsIdentifier('task-retention-days'),
      '14',
    );
    await tester.ensureVisible(
      find.bySemanticsIdentifier('trash-retention-save'),
    );
    await tester.tap(
      find.bySemanticsIdentifier('trash-retention-save'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(repo.adminSettings.taskRetentionDays, 14);
    // Zero is a choice here, not a default, so it has to store.
    await tester.enterText(
      find.bySemanticsIdentifier('task-retention-days'),
      '0',
    );
    await tester.tap(
      find.bySemanticsIdentifier('trash-retention-save'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(repo.adminSettings.taskRetentionDays, 0);
  });
}
