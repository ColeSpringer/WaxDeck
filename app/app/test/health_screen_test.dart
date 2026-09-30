import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/health/health_controller.dart';
import 'package:waxdeck/src/health/health_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

const _admin = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  username: 'admin',
  roles: ['admin'],
);

ProviderContainer _container(FakeRepository repo) {
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _host(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: routedHost(const HealthScreen()),
);

/// Wide enough for the console tables to be tables.
Future<void> _pump(WidgetTester tester, Widget host) async {
  tester.view.physicalSize = const Size(1280, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(host);
  await tester.pumpAndSettle();
}

/// The stock summary, with missing art's fix under way or not.
HealthSummary _summary({bool fixing = false, int failing = 5}) => HealthSummary(
  score: 87.4,
  totalItems: 120,
  evaluatedItems: 120,
  rules: [
    HealthRuleCount(
      rule: 'missing-art',
      label: 'Missing artwork',
      failing: failing,
      fixable: true,
      fixing: fixing,
    ),
    const HealthRuleCount(
      rule: 'no-mbid',
      label: 'Unidentified',
      failing: 2,
      fixable: false,
    ),
  ],
);

/// Busy rings held still, so the frames settle.
void _reducedMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

FakeRepository _repo() {
  final repo = FakeRepository(
    sessionState: const SessionState(authenticated: true, user: _admin),
  );
  repo.healthSummary = _summary();
  repo.healthIssues = [
    for (var i = 0; i < 5; i++)
      HealthIssue(
        pid: 'tr-$i',
        title: 'Track $i',
        mediaType: MediaType.music,
        rules: const ['missing-art'],
      ),
  ];
  return repo;
}

/// The Fix control of one rule.
WaxIconButton _fixButton(WidgetTester tester, String rule) =>
    tester.widget<WaxIconButton>(
      find.byWidgetPredicate(
        (w) =>
            w is WaxIconButton && w.semanticsId == SemanticsIds.healthFix(rule),
      ),
    );

/// Types the word a destructive confirmation asks for, then accepts.
Future<void> _confirm(WidgetTester tester, String word) async {
  await tester.enterText(
    find.bySemanticsIdentifier(SemanticsIds.confirmField),
    word,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.confirmAccept));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the score and rule counts', (tester) async {
    await _pump(tester, _host(_container(_repo())));

    expect(
      find.bySemanticsIdentifier(SemanticsIds.healthScore),
      findsOneWidget,
    );
    expect(find.text('87'), findsOneWidget);
    // The client's own word for the rule, not the label the server sent
    // beside it: the token is the boundary, and the server's label is
    // the fallback for a rule this app does not know.
    expect(find.text('Missing cover art'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    // Only fixable rules with failures get a Fix button.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.healthFix('missing-art')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.healthFix('no-mbid')),
      findsNothing,
    );
  });

  testWidgets('warming up replaces the score with progress', (tester) async {
    final repo = _repo();
    repo.healthSummary = const HealthSummary(
      score: 0,
      totalItems: 120,
      evaluatedItems: 48,
      warmingUp: true,
    );
    await _pump(tester, _host(_container(repo)));

    expect(
      find.bySemanticsIdentifier(SemanticsIds.healthWarmingUp),
      findsOneWidget,
    );
    expect(find.text('Still warming up'), findsOneWidget);
    expect(find.text('Evaluated 48 of 120 items'), findsOneWidget);
    expect(find.bySemanticsIdentifier(SemanticsIds.healthScore), findsNothing);
  });

  testWidgets('a fix is busy from the press until the summary says it '
      'ended', (tester) async {
    _reducedMotion(tester);
    final repo = _repo()
      ..fixHealthGate = Completer<void>()
      ..fixHealthStart = const HealthFixStart(queued: 5, taskId: 'tk-fix');
    final container = _container(repo);
    await _pump(tester, _host(container));

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.healthFix('missing-art')),
    );
    await tester.pumpAndSettle();
    expect(_fixButton(tester, 'missing-art').busy, isTrue);

    // The server has it, and the summary says the rule is fixing.
    repo.healthSummary = _summary(fixing: true);
    repo.fixHealthGate!.complete();
    await tester.pumpAndSettle();

    expect(repo.fixHealthCalls.single.rule, 'missing-art');
    final message = container.read(shellMessengerProvider);
    expect(shellMessageText(message), 'Fixing Missing cover art');
    expect(message?.actionSemanticsId, SemanticsIds.openTasks);
    expect(
      _fixButton(tester, 'missing-art').busy,
      isTrue,
      reason: 'the fix is still running',
    );

    // Its re-check lands, and the rule can be fixed again.
    repo.healthSummary = _summary(failing: 2);
    container.invalidate(healthProvider);
    await tester.pumpAndSettle();
    expect(_fixButton(tester, 'missing-art').busy, isFalse);

    message!.onAction!();
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.tasksScreen),
      findsOneWidget,
    );
  });

  testWidgets('a pass-backed fix stays busy through its re-check', (
    tester,
  ) async {
    _reducedMotion(tester);
    final repo = _repo()
      ..fixHealthStart = const HealthFixStart(queued: 5, jobPid: 'jb-fix')
      // The pass itself has ended; its re-check has not landed.
      ..jobs = [const Job(pid: 'jb-fix', kind: 'enrich', state: 'done')];
    final container = _container(repo);
    await _pump(tester, _host(container));

    repo.healthSummary = _summary(fixing: true);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.healthFix('missing-art')),
    );
    await tester.pumpAndSettle();
    expect(
      _fixButton(tester, 'missing-art').busy,
      isTrue,
      reason: 'the counts move at the re-check, not at the end of the pass',
    );

    repo.healthSummary = _summary(failing: 1);
    container.invalidate(healthProvider);
    await tester.pumpAndSettle();
    expect(_fixButton(tester, 'missing-art').busy, isFalse);
  });

  testWidgets('a fix refused while a pass runs says so', (tester) async {
    final repo = _repo();
    final container = _container(repo);
    await _pump(tester, _host(container));
    repo.fixHealthError = const WaxDeckApiException(
      code: 'conflict',
      message: 'an enrichment pass is already running',
      statusCode: 409,
    );

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.healthFix('missing-art')),
    );
    await tester.pumpAndSettle();

    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'An enrichment pass is already running. Fix this when it ends.',
    );
    expect(_fixButton(tester, 'missing-art').busy, isFalse);
  });

  testWidgets('a fix a read-only library refuses says so', (tester) async {
    final repo = _repo();
    final container = _container(repo);
    await _pump(tester, _host(container));
    repo.fixHealthError = const WaxDeckApiException(
      code: 'read-only',
      message: 'the library is read-only on this server',
      statusCode: 409,
    );

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.healthFix('missing-art')),
    );
    await tester.pumpAndSettle();

    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'The library is read-only right now, so nothing can be changed.',
    );
    expect(_fixButton(tester, 'missing-art').busy, isFalse);
  });

  testWidgets('a fix refused because the rule is being fixed says that', (
    tester,
  ) async {
    _reducedMotion(tester);
    final repo = _repo();
    final container = _container(repo);
    await _pump(tester, _host(container));
    // Another session started it; this screen has not heard yet.
    repo
      ..fixHealthError = const WaxDeckApiException(
        code: 'conflict',
        message: 'a fix for this rule is already running',
        statusCode: 409,
      )
      ..healthSummary = _summary(fixing: true);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.healthFix('missing-art')),
    );
    await tester.pumpAndSettle();

    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'A fix for Missing cover art is already running',
    );
    expect(_fixButton(tester, 'missing-art').busy, isTrue);
  });

  test(
    'a started fix does not wait out a summary read being retried',
    () async {
      // A transport failure is retried with backoff, about thirteen seconds
      // of it, and the summary's future does not settle meanwhile.
      final repo = _repo();
      final container = _container(repo);
      container.listen(healthProvider, (_, _) {});
      await container.read(healthProvider.future);
      repo.healthError = const WaxDeckApiException(
        code: 'transport',
        message: 'the network went away',
      );
      await container
          .read(healthFixesProvider.notifier)
          .start('missing-art')
          .timeout(const Duration(seconds: 3));
      expect(container.read(healthFixingProvider('missing-art')), isFalse);
    },
  );

  test(
    'a sweep request does not wait out a summary read being retried',
    () async {
      final repo = _repo();
      final container = _container(repo);
      container.listen(healthProvider, (_, _) {});
      await container.read(healthProvider.future);
      repo.healthError = const WaxDeckApiException(
        code: 'transport',
        message: 'the network went away',
      );
      await container
          .read(healthSweepRequestProvider.notifier)
          .send()
          .timeout(const Duration(seconds: 3));
      expect(container.read(healthSweepRequestProvider), isFalse);
    },
  );

  testWidgets('a failed sweep says the numbers are from an earlier one', (
    tester,
  ) async {
    final repo = _repo();
    repo.healthSummary = HealthSummary(
      score: 87.4,
      totalItems: 120,
      evaluatedItems: 120,
      sweepFailed: true,
      rules: _summary().rules,
    );
    await _pump(tester, _host(_container(repo)));
    expect(
      find.text(
        'The last sweep failed, so these numbers are from an earlier one',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a blocked rule says what it lacks and offers no fix', (
    tester,
  ) async {
    final repo = _repo()
      ..healthSummary = const HealthSummary(
        score: 90,
        totalItems: 4,
        evaluatedItems: 4,
        rules: [
          HealthRuleCount(
            rule: 'missing-lyrics',
            failing: 4,
            fixable: false,
            fixBlocked: 'needs-contact',
          ),
        ],
      );
    await _pump(tester, _host(_container(repo)));

    expect(
      find.bySemanticsIdentifier(SemanticsIds.healthFix('missing-lyrics')),
      findsNothing,
    );
    const reason =
        'Needs an enrichment contact, which lets this server ask the '
        'free public sources.';
    final blocked = find.bySemanticsIdentifier(
      SemanticsIds.healthFixBlocked('missing-lyrics'),
    );
    expect(blocked, findsOneWidget);
    expect(tester.getSemantics(blocked).label, reason);
    expect(find.text(reason), findsOneWidget);
  });

  testWidgets('a fix that writes files is blocked on a read-only server', (
    tester,
  ) async {
    final repo = _repo()
      ..healthSummary = const HealthSummary(
        score: 90,
        totalItems: 4,
        evaluatedItems: 4,
        rules: [
          HealthRuleCount(
            rule: 'path-mismatch',
            failing: 4,
            fixable: false,
            fixBlocked: 'read-only',
          ),
        ],
      );
    await _pump(tester, _host(_container(repo)));

    expect(
      find.bySemanticsIdentifier(SemanticsIds.healthFix('path-mismatch')),
      findsNothing,
    );
    expect(
      find.text('Writes files, and the server is read-only.'),
      findsOneWidget,
    );
  });

  testWidgets('a listener sees the standing and no fixes', (tester) async {
    final repo = _repo()
      ..sessionState = const SessionState(
        authenticated: true,
        user: WaxDeckUser(id: 'us-2', username: 'sam'),
      )
      ..healthSummary = const HealthSummary(
        score: 90,
        totalItems: 4,
        evaluatedItems: 4,
        rules: [
          HealthRuleCount(rule: 'missing-art', failing: 4, fixable: true),
          HealthRuleCount(
            rule: 'missing-lyrics',
            failing: 4,
            fixable: false,
            fixBlocked: 'needs-contact',
          ),
        ],
      );
    await _pump(tester, _host(_container(repo)));

    expect(find.text('Missing cover art'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.healthFix('missing-art')),
      findsNothing,
    );
    expect(
      find.bySemanticsIdentifier(
        SemanticsIds.healthFixBlocked('missing-lyrics'),
      ),
      findsNothing,
    );
  });

  testWidgets('a sweep stays busy from the press to the summary saying so', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final repo = _repo();
    await _pump(tester, _host(_container(repo)));
    WaxIconButton sweep() => tester.widget<WaxIconButton>(
      find.byWidgetPredicate(
        (w) => w is WaxIconButton && w.semanticsId == SemanticsIds.healthSweep,
      ),
    );

    // The request lands, and the summary that says so is still on its way.
    repo
      ..healthGate = Completer<void>()
      ..healthSummary = const HealthSummary(
        score: 87.4,
        totalItems: 120,
        evaluatedItems: 120,
        sweeping: true,
      );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.healthSweep));
    await tester.pump();
    await tester.pump();
    expect(sweep().busy, isTrue);

    repo.healthGate!.complete();
    await tester.pumpAndSettle();
    expect(sweep().busy, isTrue, reason: 'the summary says one is sweeping');
  });

  testWidgets('sweep is busy while the summary says one is sweeping', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final repo = _repo()
      ..healthSummary = const HealthSummary(
        score: 90,
        totalItems: 4,
        evaluatedItems: 4,
        sweeping: true,
      );
    await _pump(tester, _host(_container(repo)));

    final sweep = tester.widget<WaxIconButton>(
      find.byWidgetPredicate(
        (w) => w is WaxIconButton && w.semanticsId == SemanticsIds.healthSweep,
      ),
    );
    expect(sweep.busy, isTrue);
  });

  testWidgets('a rule opens its paginated issue list', (tester) async {
    await _pump(tester, _host(_container(_repo())));

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.health('missing-art')),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.healthIssue('tr-0')),
      findsOneWidget,
    );
    expect(find.text('Track 0'), findsOneWidget);
  });

  testWidgets('a duration mismatch names both lengths', (tester) async {
    final repo = _repo()
      ..healthSummary = const HealthSummary(
        score: 99,
        totalItems: 120,
        evaluatedItems: 120,
        rules: [
          HealthRuleCount(
            rule: 'duration-mismatch',
            label: 'Header duration disagrees with the audio',
            failing: 1,
            fixable: false,
          ),
        ],
      )
      ..healthIssues = const [
        HealthIssue(
          pid: 'tr-9',
          title: 'Half Song',
          mediaType: MediaType.music,
          rules: ['duration-mismatch'],
          detail: HealthIssueDetail(headerMs: 221000, decodedMs: 192000),
        ),
      ];
    await _pump(tester, _host(_container(repo)));

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.health('duration-mismatch')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Header 3:41, audio 3:12'), findsOneWidget);
  });

  testWidgets('a mismatch names the file its lengths are of', (tester) async {
    final repo = _repo()
      ..healthSummary = const HealthSummary(
        score: 99,
        totalItems: 120,
        evaluatedItems: 120,
        rules: [
          HealthRuleCount(
            rule: 'duration-mismatch',
            label: 'Header duration disagrees with the audio',
            failing: 2,
            fixable: false,
          ),
        ],
      )
      ..healthIssues = const [
        HealthIssue(
          pid: 'ab-1',
          title: 'Long Book',
          mediaType: MediaType.audiobook,
          rules: ['duration-mismatch'],
          detail: HealthIssueDetail(
            headerMs: 3000,
            decodedMs: 6000,
            partIndex: 2,
          ),
        ),
        HealthIssue(
          pid: 'tr-7',
          title: 'Carved Track',
          mediaType: MediaType.music,
          rules: ['duration-mismatch'],
          detail: HealthIssueDetail(
            headerMs: 3240000,
            decodedMs: 3600000,
            wholeFile: true,
          ),
        ),
      ];
    await _pump(tester, _host(_container(repo)));

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.health('duration-mismatch')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Part 3: header 0:03, audio 0:06'), findsOneWidget);
    expect(
      find.text('Whole file: header 54:00, audio 1:00:00'),
      findsOneWidget,
    );
  });

  testWidgets('merging duplicates confirms and calls the repository', (
    tester,
  ) async {
    final repo = _repo();
    repo.duplicateGroups = const [
      DuplicateGroup(
        entityType: 'artist',
        survivor: DuplicateEntity(pid: 'ar-1', name: 'The Cardinal Waves'),
        losers: [DuplicateEntity(pid: 'ar-2', name: 'Cardinal Waves')],
      ),
    ];
    await _pump(tester, _host(_container(repo)));

    final merge = find.bySemanticsIdentifier(
      SemanticsIds.duplicateMerge('ar-1'),
    );
    await tester.ensureVisible(merge);
    await tester.pumpAndSettle();
    await tester.tap(merge);
    await tester.pumpAndSettle();
    await _confirm(tester, 'merge');

    expect(repo.mergeDuplicatesCalls, hasLength(1));
    expect(repo.mergeDuplicatesCalls.single.survivorPid, 'ar-1');
    expect(repo.mergeDuplicatesCalls.single.loserPids, ['ar-2']);
  });

  testWidgets('resolving an upgrade keeps the best and trashes the rest', (
    tester,
  ) async {
    final repo = _repo();
    repo.upgradeGroups = const [
      UpgradeGroup(
        members: [
          UpgradeMember(
            itemPid: 'tr-flac',
            title: 'Neon Meridian',
            codec: 'flac',
            lossless: true,
            best: true,
          ),
          UpgradeMember(
            itemPid: 'tr-mp3',
            title: 'Neon Meridian',
            codec: 'mp3',
            bitrate: 192000,
            lossless: false,
            best: false,
          ),
        ],
      ),
    ];
    await _pump(tester, _host(_container(repo)));

    final resolve = find.bySemanticsIdentifier(
      SemanticsIds.upgradeResolve('tr-flac'),
    );
    await tester.ensureVisible(resolve);
    await tester.pumpAndSettle();
    await tester.tap(resolve);
    await tester.pumpAndSettle();
    await _confirm(tester, 'resolve');

    expect(repo.resolveUpgradeCalls, hasLength(1));
    expect(repo.resolveUpgradeCalls.single.keepItemPid, 'tr-flac');
    expect(repo.resolveUpgradeCalls.single.removeItemPids, ['tr-mp3']);
  });
}
