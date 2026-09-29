import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
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

FakeRepository _repo() {
  final repo = FakeRepository(
    sessionState: const SessionState(authenticated: true, user: _admin),
  );
  repo.healthSummary = const HealthSummary(
    score: 87.4,
    totalItems: 120,
    evaluatedItems: 120,
    rules: [
      HealthRuleCount(
        rule: 'missing-art',
        label: 'Missing artwork',
        failing: 5,
        fixable: true,
      ),
      HealthRuleCount(
        rule: 'no-mbid',
        label: 'Unidentified',
        failing: 2,
        fixable: false,
      ),
    ],
  );
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

  testWidgets('fix queues the failing items', (tester) async {
    final repo = _repo();
    final container = _container(repo);
    await _pump(tester, _host(container));

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.healthFix('missing-art')),
    );
    await tester.pumpAndSettle();

    expect(repo.fixHealthCalls, hasLength(1));
    expect(repo.fixHealthCalls.single.rule, 'missing-art');
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'Queued 5 items',
    );
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
