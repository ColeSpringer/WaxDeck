import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/server_settings_screen.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'localized_host.dart';
import 'wax_finders.dart';

ProviderContainer _container(FakeRepository repo) {
  final container = ProviderContainer(
    overrides: [repositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _host(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: localizedHost(const ServerSettingsScreen()),
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
    );
    await tester.pumpAndSettle();
    expect(repo.adminSettings.signupEnabled, isTrue);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.settingReadOnly));
    await tester.pumpAndSettle();
    expect(repo.adminSettings.readOnly, isTrue);
    // The first toggle survived the second save.
    expect(repo.adminSettings.signupEnabled, isTrue);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.settingSonicAnalysis),
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
      find.bySemanticsIdentifier(SemanticsIds.transcodingMaxConcurrent),
      '4',
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.transcodingDefaultKbps),
      '256',
    );
    await tester.ensureVisible(
      find.bySemanticsIdentifier(SemanticsIds.transcodingSave),
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.transcodingSave));
    await tester.pumpAndSettle();

    expect(repo.transcodingLimits.maxConcurrent, 4);
    expect(repo.transcodingLimits.defaultMaxBitrateKbps, 256);
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
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
    expect(find.text('3 engine-backed sessions right now.'), findsOneWidget);
    // What the number is not rides an info tip rather than a printed line.
    expect(find.textContaining('holds one slot'), findsNothing);
    expect(find.textContaining('gapless queue.'), findsNothing);
    expect(
      tester.widget<WaxInfoTip>(find.byType(WaxInfoTip)).message,
      contains('holds one slot'),
    );
    // A tap on web reaches a tip only if no ancestor excludes or merges.
    expect(hasOwnSemanticsNode(tester, find.byType(WaxInfoTip)), isTrue);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.transcodingActivityInfo),
      findsOneWidget,
    );
    // Read once when the screen opened. A settings form is not a
    // monitor, and nothing here polls.
    expect(repo.transcodingActivityReads, 1);
  });

  // A gapless queue holds one slot however many renderings it keeps
  // live, so the same count means something else when queues fill it.
  testWidgets('the count says how many sessions are gapless queues', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..activeTranscodeSessions = 3
      ..activeTranscodeTimelines = 2;
    await _pump(tester, _host(_container(repo)));

    final line = find.text(
      '3 engine-backed sessions right now. 2 of them are gapless queues.',
    );
    expect(line, findsOneWidget);
    // The tip starts where the words end, as on every title it trails.
    expect(
      tester.getRect(find.byType(WaxInfoTip)).left,
      moreOrLessEquals(tester.getRect(line).right, epsilon: 0.01),
    );

    Future<void> refresh(int timelines) async {
      repo.activeTranscodeTimelines = timelines;
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.transcodingActivityRefresh),
      );
      await tester.pumpAndSettle();
    }

    await refresh(1);
    expect(
      find.text(
        '3 engine-backed sessions right now. One of them is a gapless queue.',
      ),
      findsOneWidget,
    );
    // None is no clause at all, and no space left where it would be.
    await refresh(0);
    expect(find.text('3 engine-backed sessions right now.'), findsOneWidget);
  });

  test(
    'the count and its gapless clause are one message in each language',
    () async {
      final es = await AppLocalizations.delegate.load(const Locale('es'));
      expect(
        es.adminServerActivityCount(3, 0),
        '3 sesiones con motor ahora mismo.',
      );
      expect(
        es.adminServerActivityCount(3, 1),
        '3 sesiones con motor ahora mismo. Una de ellas es una cola sin pausas.',
      );
      expect(
        es.adminServerActivityCount(3, 2),
        '3 sesiones con motor ahora mismo. 2 de ellas son colas sin pausas.',
      );
    },
  );

  testWidgets('the running count refreshes when asked, and only then', (
    tester,
  ) async {
    final repo = FakeRepository()..activeTranscodeSessions = 1;
    await _pump(tester, _host(_container(repo)));
    expect(find.text('1 engine-backed session right now.'), findsOneWidget);

    repo.activeTranscodeSessions = 5;
    await tester.pump(const Duration(seconds: 30));
    // Still one: nothing arrives on a timer.
    expect(repo.transcodingActivityReads, 1);

    await tester.ensureVisible(
      find.bySemanticsIdentifier(SemanticsIds.transcodingActivityRefresh),
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.transcodingActivityRefresh),
    );
    await tester.pumpAndSettle();

    expect(repo.transcodingActivityReads, 2);
    expect(find.text('5 engine-backed sessions right now.'), findsOneWidget);
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
      find.bySemanticsIdentifier(SemanticsIds.trashRetentionDays),
      'soon',
    );
    await tester.ensureVisible(
      find.bySemanticsIdentifier(SemanticsIds.trashRetentionSave),
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.trashRetentionSave),
    );
    await tester.pumpAndSettle();

    // Named, not just refused: one save writes two windows.
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      allOf(contains('whole number of days'), contains('Purge trashed files')),
    );

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.trashRetentionDays),
      '007',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.trashRetentionSave),
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
      find.bySemanticsIdentifier(SemanticsIds.taskRetentionDays),
      'never',
    );
    await tester.ensureVisible(
      find.bySemanticsIdentifier(SemanticsIds.trashRetentionSave),
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.trashRetentionSave),
    );
    await tester.pumpAndSettle();

    expect(
      shellMessageText(container.read(shellMessengerProvider)),
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
      find.bySemanticsIdentifier(SemanticsIds.taskRetentionDays),
      '14',
    );
    await tester.ensureVisible(
      find.bySemanticsIdentifier(SemanticsIds.trashRetentionSave),
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.trashRetentionSave),
    );
    await tester.pumpAndSettle();
    expect(repo.adminSettings.taskRetentionDays, 14);
    // Zero is a choice here, not a default, so it has to store.
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.taskRetentionDays),
      '0',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.trashRetentionSave),
    );
    await tester.pumpAndSettle();
    expect(repo.adminSettings.taskRetentionDays, 0);
  });
}
