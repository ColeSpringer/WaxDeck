import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/health/health_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

const _admin = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  username: 'admin',
  roles: ['admin'],
);

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
  ],
  child: const MaterialApp(home: HealthScreen()),
);

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

void main() {
  testWidgets('renders the score and rule counts', (tester) async {
    await tester.pumpWidget(_host(_repo()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('health-score')), findsOneWidget);
    expect(find.text('87'), findsOneWidget);
    expect(find.text('Missing artwork'), findsOneWidget);
    expect(find.text('5 failing'), findsOneWidget);
    // Only fixable rules with failures get a Fix button.
    expect(
      find.byKey(const ValueKey('health-fix-missing-art')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('health-fix-no-mbid')), findsNothing);
  });

  testWidgets('warming up replaces the score with progress', (tester) async {
    final repo = _repo();
    repo.healthSummary = const HealthSummary(
      score: 0,
      totalItems: 120,
      evaluatedItems: 48,
      warmingUp: true,
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('health-warming-up')), findsOneWidget);
    expect(find.text('Still warming up'), findsOneWidget);
    expect(find.text('Evaluated 48 of 120 items'), findsOneWidget);
    expect(find.byKey(const Key('health-score')), findsNothing);
  });

  testWidgets('fix queues the failing items', (tester) async {
    final repo = _repo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('health-fix-missing-art')));
    await tester.pumpAndSettle();

    expect(repo.fixHealthCalls, hasLength(1));
    expect(repo.fixHealthCalls.single.rule, 'missing-art');
    expect(find.text('Queued 5 items'), findsOneWidget);
  });

  testWidgets('a rule opens its paginated issue list', (tester) async {
    await tester.pumpWidget(_host(_repo()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('health-rule-missing-art')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('health-issue-tr-0')), findsOneWidget);
    expect(find.text('Track 0'), findsOneWidget);
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
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('duplicate-merge-ar-1')),
    );
    await tester.tap(find.byKey(const ValueKey('duplicate-merge-ar-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('duplicate-merge-confirm')));
    await tester.pumpAndSettle();

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
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('upgrade-resolve-tr-flac')),
    );
    await tester.tap(find.byKey(const ValueKey('upgrade-resolve-tr-flac')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('upgrade-resolve-confirm')));
    await tester.pumpAndSettle();

    expect(repo.resolveUpgradeCalls, hasLength(1));
    expect(repo.resolveUpgradeCalls.single.keepItemPid, 'tr-flac');
    expect(repo.resolveUpgradeCalls.single.removeItemPids, ['tr-mp3']);
  });
}
