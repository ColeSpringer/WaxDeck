import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/server_settings_screen.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';
import 'wax_finders.dart';

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpApp(
    tester,
    const ServerSettingsScreen(),
    container: container,
    routed: false,
  );
}

/// Holds every settings write until the test lets it through, so two can
/// be in flight at once.
class _ParkedWrites extends FakeRepository {
  final parked = <Completer<void>>[];
  final bodies = <AdminSettingsChange>[];

  @override
  Future<AdminSettings> putAdminSettings(AdminSettingsChange change) async {
    bodies.add(change);
    final gate = Completer<void>();
    parked.add(gate);
    await gate.future;
    return super.putAdminSettings(change);
  }
}

/// Records the body of every settings write.
class _RecordedWrites extends FakeRepository {
  final bodies = <AdminSettingsChange>[];

  @override
  Future<AdminSettings> putAdminSettings(AdminSettingsChange change) {
    bodies.add(change);
    return super.putAdminSettings(change);
  }
}

/// Transcoding limits refused while [limitsError] is set.
class _LimitsDown extends FakeRepository {
  WaxDeckApiException? limitsError = const WaxDeckApiException(
    code: 'forbidden',
    message: 'not an administrator',
    statusCode: 403,
  );

  @override
  Future<TranscodingLimits> getTranscodingLimits() async {
    if (limitsError case final error?) throw error;
    return super.getTranscodingLimits();
  }
}

bool _switchOn(WidgetTester tester, String id) => tester
    .widget<WaxSwitch>(
      find.byWidgetPredicate((w) => w is WaxSwitch && w.semanticsId == id),
    )
    .value;

String _boxText(WidgetTester tester, String id) =>
    tester.widget<WaxTextField>(waxControl<WaxTextField>(id)).controller!.text;

void main() {
  testWidgets('a second toggle while the first is saving keeps both', (
    tester,
  ) async {
    final repo = _ParkedWrites();
    await _pump(tester, appContainer(repo: repo));

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.settingSignupEnabled),
    );
    await tester.pump();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.settingReadOnly));
    await tester.pump();
    // Let each write through as it parks, in order.
    for (var i = 0; i < 2; i++) {
      await tester.pumpAndSettle();
      repo.parked[i].complete();
    }
    await tester.pumpAndSettle();

    // Each write names its own switch and nothing else.
    expect(repo.bodies, hasLength(2));
    expect(repo.bodies[0].signupEnabled, isTrue);
    expect(repo.bodies[0].readOnly, isNull);
    expect(repo.bodies[1].readOnly, isTrue);
    expect(repo.bodies[1].signupEnabled, isNull);
    expect(repo.adminSettings.signupEnabled, isTrue);
    expect(repo.adminSettings.readOnly, isTrue);
    expect(_switchOn(tester, SemanticsIds.settingSignupEnabled), isTrue);
    expect(_switchOn(tester, SemanticsIds.settingReadOnly), isTrue);
  });

  testWidgets('a switch flip sends one field and makes one request', (
    tester,
  ) async {
    final repo = _ParkedWrites();
    await _pump(tester, appContainer(repo: repo));
    expect(repo.adminSettingsReads, 1, reason: 'the screen reads once');

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.settingSignupEnabled),
    );
    await tester.pumpAndSettle();
    repo.parked.single.complete();
    await tester.pumpAndSettle();

    expect(repo.adminSettingsReads, 1, reason: 'no read before the write');
    expect(repo.bodies, hasLength(1));
    final body = repo.bodies.single;
    expect(body.signupEnabled, isTrue);
    expect([
      body.readOnly,
      body.sonicAnalysis,
      body.backupKeepCount,
      body.backupKeepBytes,
      body.trashRetentionDays,
      body.taskRetentionDays,
      body.radioExternalArt,
    ], everyElement(isNull));
  });

  testWidgets('another administrator\'s change survives a toggle', (
    tester,
  ) async {
    final repo = FakeRepository();
    await _pump(tester, appContainer(repo: repo));

    // Stored behind the open screen: it still draws read-only off.
    repo.adminSettings = repo.adminSettings.copyWith(
      readOnly: true,
      trashRetentionDays: 21,
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.settingSignupEnabled),
    );
    await tester.pumpAndSettle();

    expect(repo.adminSettings.signupEnabled, isTrue);
    expect(repo.adminSettings.readOnly, isTrue);
    expect(repo.adminSettings.trashRetentionDays, 21);
    // The answer is the stored document, so the screen catches up.
    expect(_switchOn(tester, SemanticsIds.settingReadOnly), isTrue);
  });

  testWidgets('toggling signup and read-only saves server-wide', (
    tester,
  ) async {
    final repo = FakeRepository();
    await _pump(tester, appContainer(repo: repo));

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

  testWidgets('limits that fail to load say so in place of the group, and '
      'asking again reads them', (tester) async {
    final repo = _LimitsDown();
    await _pump(tester, appContainer(repo: repo));

    expect(find.text('Could not load the transcoding limits'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.transcodingMaxConcurrent),
      findsNothing,
    );
    repo.limitsError = null;
    final retry = find.widgetWithText(WaxButton, 'Try again');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.transcodingMaxConcurrent),
      findsOneWidget,
    );
  });

  testWidgets('saves transcoding limits', (tester) async {
    final repo = FakeRepository();
    final container = appContainer(repo: repo);
    await _pump(tester, container);

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
    await _pump(tester, appContainer(repo: repo));

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
    await _pump(tester, appContainer(repo: repo));

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
    await _pump(tester, appContainer(repo: repo));
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
    final container = appContainer(repo: repo);
    await _pump(tester, container);

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
    final container = appContainer(repo: repo);
    await _pump(tester, container);

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

  testWidgets('a retention save sends only the window the admin changed', (
    tester,
  ) async {
    final repo = _RecordedWrites();
    await _pump(tester, appContainer(repo: repo));
    Future<void> save({String? trash, String? task}) async {
      if (trash != null) {
        await tester.enterText(
          find.bySemanticsIdentifier(SemanticsIds.trashRetentionDays),
          trash,
        );
      }
      if (task != null) {
        await tester.enterText(
          find.bySemanticsIdentifier(SemanticsIds.taskRetentionDays),
          task,
        );
      }
      await tester.ensureVisible(
        find.bySemanticsIdentifier(SemanticsIds.trashRetentionSave),
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.trashRetentionSave),
      );
      await tester.pumpAndSettle();
    }

    await save(task: '14');
    expect(repo.bodies.single.taskRetentionDays, 14);
    expect(repo.bodies.single.trashRetentionDays, isNull);

    // Another administrator moves the task window while this one edits
    // the trash one: the save must not put the stale task window back.
    repo.adminSettings = repo.adminSettings.copyWith(taskRetentionDays: 21);
    await save(trash: '5');
    expect(repo.bodies.last.trashRetentionDays, 5);
    expect(repo.bodies.last.taskRetentionDays, isNull);
    expect(repo.adminSettings.trashRetentionDays, 5);
    expect(repo.adminSettings.taskRetentionDays, 21);

    // Back to the value the box first showed still counts as a change.
    await save(trash: '0');
    expect(repo.bodies.last.trashRetentionDays, 0);
  });

  testWidgets('an untouched retention box takes what the server stored, and '
      'a typed one keeps the typing', (tester) async {
    final repo = _RecordedWrites();
    await _pump(tester, appContainer(repo: repo));

    // Another administrator moves both windows while this one types in
    // the trash box, and the answer to this one's next write carries them.
    repo.adminSettings = repo.adminSettings.copyWith(
      trashRetentionDays: 12,
      taskRetentionDays: 21,
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.trashRetentionDays),
      '9',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.settingSignupEnabled),
    );
    await tester.pumpAndSettle();

    expect(_boxText(tester, SemanticsIds.taskRetentionDays), '21');
    expect(_boxText(tester, SemanticsIds.trashRetentionDays), '9');
  });

  testWidgets('a retention save compares each box with what is stored', (
    tester,
  ) async {
    final repo = _RecordedWrites();
    await _pump(tester, appContainer(repo: repo));
    Future<void> save({String? trash, String? task}) async {
      if (trash != null) {
        await tester.enterText(
          find.bySemanticsIdentifier(SemanticsIds.trashRetentionDays),
          trash,
        );
      }
      if (task != null) {
        await tester.enterText(
          find.bySemanticsIdentifier(SemanticsIds.taskRetentionDays),
          task,
        );
      }
      await tester.ensureVisible(
        find.bySemanticsIdentifier(SemanticsIds.trashRetentionSave),
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.trashRetentionSave),
      );
      await tester.pumpAndSettle();
    }

    // Another administrator moves the task window while this one saves
    // the trash one: the answer brings it, and the untouched box shows it.
    repo.adminSettings = repo.adminSettings.copyWith(taskRetentionDays: 21);
    await save(trash: '5');
    expect(repo.bodies.last.taskRetentionDays, isNull);
    expect(_boxText(tester, SemanticsIds.taskRetentionDays), '21');

    // The stored value typed back is no change and sends nothing.
    await save(task: '21');
    expect(repo.bodies.last.taskRetentionDays, isNull);

    // The value the box showed before is stale now, so it is sent over
    // the newer one.
    await save(task: '30');
    expect(repo.bodies.last.taskRetentionDays, 30);
    expect(repo.adminSettings.taskRetentionDays, 30);
  });

  testWidgets('the task window saves beside the trash one', (tester) async {
    final repo = FakeRepository();
    final container = appContainer(repo: repo);
    await _pump(tester, container);

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
