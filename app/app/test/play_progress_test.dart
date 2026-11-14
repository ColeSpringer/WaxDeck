import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/player/play_progress.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

/// Watches the progress of [items] the way a listing screen does, and hands
/// the view to [onView] each time it builds.
class _Probe extends ConsumerWidget {
  const _Probe({required this.items, required this.onView});

  final List<ItemSummary> items;
  final void Function(PlayProgressView view) onView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    onView(watchPlayProgress(ref, items));
    return const SizedBox.shrink();
  }
}

void main() {
  testWidgets('120 rows are read in windows of 50, 50 and 20, and the view '
      'answers for each', (tester) async {
    final repo = FakeRepository();
    final items = <ItemSummary>[
      for (var i = 0; i < 120; i++)
        testItem('tr-${i.toString().padLeft(3, '0')}'),
    ];
    repo.playPositions['tr-115'] = 90000;
    late PlayProgressView view;

    await pumpApp(
      tester,
      _Probe(items: items, onView: (v) => view = v),
      container: appContainer(repo: repo),
      routed: false,
    );

    expect(repo.playStateBatches.map((batch) => batch.length), <int>[
      50,
      50,
      20,
    ]);
    expect(view['tr-115'].positionMs, 90000);
    expect(view['tr-115'].inProgress, isTrue);
    // A row the read did not cover reads as not started, never as missing.
    expect(view['tr-999'], same(PlayProgress.none));
  });

  testWidgets('play counts come from the windows a list already watches for '
      'its played marks, with no read of their own', (tester) async {
    final repo = FakeRepository();
    final items = <ItemSummary>[
      for (var i = 0; i < 120; i++)
        testItem('tr-${i.toString().padLeft(3, '0')}'),
    ];
    repo.finishedPids.add('tr-007');
    repo.playCounts['tr-115'] = 3;
    late Map<String, int> counts;

    await pumpApp(
      tester,
      Column(
        children: <Widget>[
          _Probe(items: items, onView: (_) {}),
          Consumer(
            builder: (context, ref, _) {
              counts = playCountsOf(ref, items);
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      container: appContainer(repo: repo),
      routed: false,
    );

    expect(repo.playStateBatches.map((batch) => batch.length), <int>[
      50,
      50,
      20,
    ]);
    // Only what was played through: a pid with no count has no entry.
    expect(counts, <String, int>{'tr-007': 1, 'tr-115': 3});
  });

  test('the counts kept for rows read again are the account\'s own, and a '
      'sign-out drops them', () async {
    const ann = WaxDeckUser(id: 'us-ann', username: 'ann', roles: ['user']);
    const ben = WaxDeckUser(id: 'us-ben', username: 'ben', roles: ['user']);
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: ann),
    )..finishedPids.add('tr-001');
    final container = appContainer(repo: repo);
    await container.read(authControllerProvider.future);
    // A window per answer: one still alive would answer from its first read.
    Future<void> answer(String other) async {
      final window = playProgressProvider(
        playPidsKey(<String>['tr-001', other]),
      );
      final held = container.listen(window, (_, _) {});
      await container.read(window.future);
      held.close();
    }

    await answer('tr-002');
    expect(container.read(answeredPlayCountsProvider)['tr-001'], 1);

    repo.sessionState = const SessionState(authenticated: true, user: ben);
    await container.read(authControllerProvider.notifier).refreshSession();
    expect(
      container.read(answeredPlayCountsProvider)['tr-001'],
      0,
      reason: 'another account signed in',
    );

    await answer('tr-003');
    expect(container.read(answeredPlayCountsProvider)['tr-001'], 1);
    await container.read(authControllerProvider.notifier).logout();
    expect(
      container.read(answeredPlayCountsProvider)['tr-001'],
      0,
      reason: 'signed out',
    );
  });

  group('a read the window has moved past records nothing', () {
    const ann = WaxDeckUser(id: 'us-ann', username: 'ann', roles: ['user']);
    const ben = WaxDeckUser(id: 'us-ben', username: 'ben', roles: ['user']);
    final window = playProgressProvider(
      playPidsKey(<String>['tr-001', 'tr-002']),
    );

    test('an earlier account\'s read answering late leaves the next '
        'account\'s kept counts alone', () async {
      final repo = FakeRepository(
        sessionState: const SessionState(authenticated: true, user: ann),
      )..finishedPids.add('tr-001');
      final container = appContainer(repo: repo);
      await container.read(authControllerProvider.future);

      final annRead = Completer<void>();
      repo.playStatesGate = annRead;
      final held = container.listen(window, (_, _) {});
      addTearDown(held.close);
      await pumpEventQueue();
      expect(repo.playStateBatches, hasLength(1));
      repo.playStatesGate = null;

      // Adopted without a sign-out, so the window stays up and is read
      // again, for Ben, who has heard nothing.
      repo.sessionState = const SessionState(authenticated: true, user: ben);
      await container.read(authControllerProvider.notifier).refreshSession();
      expect(container.read(signedInAccountProvider), 'us-ben');
      repo.finishedPids.remove('tr-001');
      container.invalidate(window);
      expect((await container.read(window.future))['tr-001']?.playCount, 0);
      expect(container.read(answeredPlayCountsProvider)['tr-001'], 0);

      // Ann's read answers now, with Ann's count.
      repo.finishedPids.add('tr-001');
      annRead.complete();
      await pumpEventQueue();
      expect(container.read(window).value!['tr-001']?.playCount, 0);
      expect(
        container.read(answeredPlayCountsProvider)['tr-001'],
        0,
        reason: "Ann's count is not Ben's",
      );
    });

    test('an older read answering after a newer one keeps the newer '
        'count', () async {
      final repo = FakeRepository()..playCounts['tr-001'] = 1;
      final container = appContainer(repo: repo);

      final older = Completer<void>();
      repo.playStatesGate = older;
      final held = container.listen(window, (_, _) {});
      addTearDown(held.close);
      await pumpEventQueue();
      repo.playStatesGate = null;

      repo.playCounts['tr-001'] = 2;
      container.invalidate(window);
      expect((await container.read(window.future))['tr-001']?.playCount, 2);
      expect(container.read(answeredPlayCountsProvider)['tr-001'], 2);

      // The older read answers with what it saw when it went out.
      repo.playCounts['tr-001'] = 1;
      older.complete();
      await pumpEventQueue();
      expect(container.read(window).value!['tr-001']?.playCount, 2);
      expect(container.read(answeredPlayCountsProvider)['tr-001'], 2);
    });

    test('a mark that lands after another account\'s session arrived '
        'writes into neither its window nor its kept counts', () async {
      final repo = FakeRepository(
        sessionState: const SessionState(authenticated: true, user: ann),
      );
      final container = appContainer(repo: repo);
      await container.read(authControllerProvider.future);
      final held = container.listen(window, (_, _) {});
      addTearDown(held.close);
      await container.read(window.future);

      final put = Completer<void>();
      repo.putPlayStateGate = put;
      final marking = container
          .read(window.notifier)
          .markPlayed('tr-002', 60000);
      await pumpEventQueue();

      repo.sessionState = const SessionState(authenticated: true, user: ben);
      await container.read(authControllerProvider.notifier).refreshSession();
      container.invalidate(window);
      expect((await container.read(window.future))['tr-002']?.playCount, 0);

      put.complete();
      expect(await marking, isTrue);
      expect(container.read(window).value!['tr-002']?.playCount, 0);
      expect(container.read(answeredPlayCountsProvider)['tr-002'], 0);
    });
  });

  group('play windows', () {
    List<String> pidsOf(int count) => <String>[
      // Out of order, with a repeat in every window: a playlist may hold a
      // track twice, and the key is the same set either way.
      for (var i = 0; i < count; i++)
        if (i % 7 == 0)
          'tr-repeated'
        else
          'tr-${((i * 37) % count).toString().padLeft(4, '0')}',
    ];

    test('a row\'s key is the one playProgressKeysOf gives for its window', () {
      for (final count in <int>[1, 49, 50, 51, 100, 120, 233]) {
        final pids = pidsOf(count);
        final windows = PlayWindows(count, (i) => pids[i]);
        final keys = playProgressKeysOf(pids);
        for (var row = 0; row < count; row++) {
          expect(
            windows.keyFor(row),
            keys[row ~/ kPlayProgressWindow],
            reason: '$count rows, row $row',
          );
        }
      }
      final items = <ItemSummary>[for (final pid in pidsOf(120)) testItem(pid)];
      final windows = PlayWindows.ofItems(items);
      expect(<String>[
        for (var row = 0; row < 120; row += kPlayProgressWindow)
          windows.keyFor(row),
      ], playProgressKeys(items));
    });

    test('a window is made when a row of it first asks, and only then', () {
      final pids = pidsOf(2000);
      final windows = PlayWindows(pids.length, (i) => pids[i]);
      expect(
        windows.windowsAsked,
        isEmpty,
        reason: 'building the value makes no key',
      );

      final first = windows.keyFor(3);
      expect(windows.keyFor(7), same(first), reason: 'kept for the build');
      windows.keyFor(1234);
      expect(windows.windowsAsked, <int>[0, 24]);
    });

    test('a window reads its own rows and copies no more of the list', () {
      var read = 0;
      final pids = pidsOf(2000);
      final windows = PlayWindows(pids.length, (i) {
        read++;
        return pids[i];
      });
      windows.keyFor(60);
      windows.keyFor(61);
      expect(read, kPlayProgressWindow);
    });

    testWidgets('a row builds once when its window\'s answer leaves its count '
        'as drawn, and again when a count arrives', (tester) async {
      final repo = FakeRepository()..playCounts['tr-001'] = 2;
      final items = <ItemSummary>[testItem('tr-000'), testItem('tr-001')];
      final windows = PlayWindows.ofItems(items);
      // The count each row's builder was called with, call by call.
      final drawn = <String, List<int>>{};
      await pumpApp(
        tester,
        Column(
          children: <Widget>[
            for (final (index, item) in items.indexed)
              PlayCountBuilder(
                windows: windows,
                index: index,
                pid: item.pid,
                builder: (context, plays) {
                  (drawn[item.pid] ??= <int>[]).add(plays);
                  return const SizedBox.shrink();
                },
              ),
          ],
        ),
        container: appContainer(repo: repo),
        routed: false,
      );

      expect(repo.playStateBatches, hasLength(1), reason: 'the rows watch');
      expect(drawn, <String, List<int>>{
        'tr-000': <int>[0],
        'tr-001': <int>[0, 2],
      });
    });

    testWidgets('a row out of view reads nothing until it is back in view, '
        'and draws there the count that moved meanwhile', (tester) async {
      final repo = FakeRepository();
      final items = <ItemSummary>[testItem('tr-000')];
      final windows = PlayWindows.ofItems(items);
      // A route over the listing, or another tab, turns its tickers off.
      final inView = ValueNotifier<bool>(true);
      addTearDown(inView.dispose);
      var drawn = -1;
      final container = await pumpApp(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: inView,
          builder: (context, on, _) => TickerMode(
            enabled: on,
            child: PlayCountBuilder(
              windows: windows,
              index: 0,
              pid: items[0].pid,
              builder: (context, plays) {
                drawn = plays;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        container: appContainer(repo: repo),
        routed: false,
      );
      expect(repo.playStateBatches, hasLength(1));
      expect(drawn, 0);

      inView.value = false;
      await tester.pumpAndSettle();
      // A play-state change elsewhere: every window is to read again.
      repo.playCounts['tr-000'] = 3;
      container.invalidate(playProgressProvider);
      await tester.pumpAndSettle();
      expect(repo.playStateBatches, hasLength(1), reason: 'out of view');
      expect(drawn, 0);

      inView.value = true;
      await tester.pumpAndSettle();
      expect(repo.playStateBatches, hasLength(2), reason: 'the read it owed');
      expect(drawn, 3);

      inView.value = false;
      await tester.pumpAndSettle();
      // A report the user stream echoes into the window, which needs no read.
      for (final window in container.read(liveProgressWindowsProvider)) {
        window.apply(
          PlayState(
            pid: 'tr-000',
            positionMs: 0,
            played: true,
            finished: true,
            playCount: 4,
            starred: false,
            updatedAt: DateTime.utc(2026, 11, 14),
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(drawn, 3, reason: 'out of view');

      inView.value = true;
      await tester.pumpAndSettle();
      expect(drawn, 4);
      expect(repo.playStateBatches, hasLength(2), reason: 'none was owed');
    });

    testWidgets('a row and a watch over the same rows share one read per '
        'window', (tester) async {
      final repo = FakeRepository();
      final items = <ItemSummary>[
        for (var i = 0; i < 120; i++)
          testItem('tr-${i.toString().padLeft(3, '0')}'),
      ];
      final windows = PlayWindows.ofItems(items);
      await pumpApp(
        tester,
        Column(
          children: <Widget>[
            _Probe(items: items, onView: (_) {}),
            PlayCountBuilder(
              windows: windows,
              index: 0,
              pid: items[0].pid,
              builder: (context, plays) => const SizedBox.shrink(),
            ),
            PlayCountBuilder(
              windows: windows,
              index: 60,
              pid: items[60].pid,
              builder: (context, plays) => const SizedBox.shrink(),
            ),
          ],
        ),
        container: appContainer(repo: repo),
        routed: false,
      );

      expect(repo.playStateBatches.map((batch) => batch.length), <int>[
        50,
        50,
        20,
      ]);
    });
  });
}
