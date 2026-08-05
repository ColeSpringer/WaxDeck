import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/review/review_entry_screen.dart';
import 'package:waxdeck/src/review/review_screen.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

Widget _host(FakeRepository repo, String entryId) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: MaterialApp(home: ReviewEntryScreen(entryId: entryId)),
);

ReviewEntryDetail _detail({String status = 'pending'}) => ReviewEntryDetail(
  id: 'rv-1',
  kind: 'match',
  status: status,
  mediaType: MediaType.music,
  origin: 'upload',
  title: 'Neon Meridian',
  artist: 'The Cardinal Waves',
  trackCount: 2,
  createdAt: DateTime.utc(2026, 7, 1),
  candidates: const [
    ReviewCandidate(
      mbid: 'mb-1',
      title: 'Neon Meridian',
      artist: 'The Cardinal Waves',
      year: 2011,
      label: 'Cardinal',
      country: 'GB',
      similarityPct: 94,
      components: [
        CandidateComponent(name: 'artist', distance: 0.02, weight: 3),
        CandidateComponent(name: 'tracks', distance: 0.1, weight: 2),
      ],
      pairings: [
        CandidatePairing(
          trackIndex: 0,
          position: 1,
          title: 'Opening Tide',
          artist: 'The Cardinal Waves',
          distance: 0.05,
        ),
      ],
      missingTitles: ['Closing Tide'],
      extraTrackIndexes: [1],
    ),
    ReviewCandidate(
      mbid: 'mb-2',
      title: 'Neon Meridian (Deluxe)',
      artist: 'The Cardinal Waves',
      year: 2012,
      similarityPct: 71,
    ),
  ],
  tracks: const [
    ReviewTrack(
      pid: 'tr-1',
      path: '/music/a.flac',
      title: 'opening tide (untagged)',
      trackNo: 1,
      durationMs: 200000,
    ),
    ReviewTrack(path: '/music/b.flac', title: 'bonus jam', durationMs: 100000),
  ],
);

FakeRepository _repoWith(ReviewEntryDetail detail) {
  final repo = FakeRepository();
  repo.reviewEntries = [
    testReviewEntry(detail.id, status: detail.status, origin: detail.origin),
  ];
  repo.reviewEntryDetails[detail.id] = detail;
  return repo;
}

/// Tall enough for the diff to be laid out below the candidate list
/// without the decision bar overrunning it.
Future<void> _pump(WidgetTester tester, Widget host) async {
  tester.view.physicalSize = const Size(700, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(host);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders candidates and the track diff', (tester) async {
    final repo = _repoWith(_detail());
    await _pump(tester, _host(repo, 'rv-1'));

    expect(
      find.bySemanticsIdentifier(SemanticsIds.candidate('mb-1')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.candidate('mb-2')),
      findsOneWidget,
    );
    expect(find.text('94%'), findsOneWidget);
    expect(find.text('2011, Cardinal, GB'), findsOneWidget);

    final firstRow = find.bySemanticsIdentifier(SemanticsIds.diffRow(0));
    expect(
      find.descendant(
        of: firstRow,
        matching: find.text('1. opening tide (untagged)'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: firstRow,
        matching: find.text('1. Opening Tide (The Cardinal Waves)'),
      ),
      findsOneWidget,
    );
    final extraRow = find.bySemanticsIdentifier(SemanticsIds.diffRow(1));
    expect(
      find.descendant(
        of: extraRow,
        matching: find.text('Extra file, no counterpart'),
      ),
      findsOneWidget,
    );
    final missingRow = find.bySemanticsIdentifier(SemanticsIds.diffMissing(0));
    expect(
      find.descendant(of: missingRow, matching: find.text('Closing Tide')),
      findsOneWidget,
    );
    // Cataloged tracks get the metadata menu; loose files do not.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.trackMenu('tr-1')),
      findsOneWidget,
    );
  });

  testWidgets('approve sends the selected candidate', (tester) async {
    final repo = _repoWith(_detail());
    await _pump(tester, _host(repo, 'rv-1'));

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.candidate('mb-2')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
    await tester.pumpAndSettle();

    expect(repo.decideReviewCalls, hasLength(1));
    expect(repo.decideReviewCalls.single.action, 'approve');
    expect(repo.decideReviewCalls.single.candidateMbid, 'mb-2');
  });

  testWidgets('the other decisions and the upload discard work', (
    tester,
  ) async {
    final repo = _repoWith(_detail());
    await _pump(tester, _host(repo, 'rv-1'));

    // Upload entries expose Discard next to the standard actions.
    expect(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.reviewUnofficial),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewDiscard));
    await tester.pumpAndSettle();

    expect(repo.decideReviewCalls.single.action, 'discard');
  });

  testWidgets('a wide surface draws the entry beside the queue', (
    tester,
  ) async {
    final repo = _repoWith(_detail());
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: routedHost(const ReviewSurface(openEntryId: 'rv-1')),
      ),
    );
    await tester.pumpAndSettle();

    // The queue keeps its rows and its keys while the entry is open.
    expect(find.bySemanticsIdentifier(SemanticsIds.reviewPane), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.reviewRow('rv-1')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.reviewPaneClose),
      findsOneWidget,
    );
  });

  testWidgets('opening an entry keeps the queue it opened from', (
    tester,
  ) async {
    final repo = _repoWith(_detail());
    repo.reviewEntries = [
      for (var i = 0; i < 40; i++) testReviewEntry('rv-$i'),
    ];
    repo.reviewEntryDetails['rv-30'] = _detail();
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: routedHost(const Scaffold()),
      ),
    );
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    router.go(WaxRoute.review);
    await tester.pumpAndSettle();

    // By its fixed row extent: the console's section list and the
    // pane's body are ListViews too.
    final queue = find.byWidgetPredicate(
      (w) => w is ListView && w.itemExtent != null,
    );
    await tester.drag(queue, const Offset(0, -600));
    await tester.pumpAndSettle();
    final scroll = tester.widget<ListView>(queue).controller!;
    expect(scroll.offset, greaterThan(0));
    final offset = scroll.offset;

    router.go(WaxRoute.reviewEntry('rv-30'));
    await tester.pumpAndSettle();

    // The same controller at the same offset: a second surface stacked
    // over the first would build a fresh state scrolled to the top.
    expect(find.bySemanticsIdentifier(SemanticsIds.reviewPane), findsOneWidget);
    final after = tester.widget<ListView>(queue);
    expect(identical(after.controller, scroll), isTrue);
    expect(scroll.offset, offset);
  });

  testWidgets('the queue key approves the candidate the pane shows', (
    tester,
  ) async {
    final repo = _repoWith(_detail());
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: routedHost(const ReviewSurface(openEntryId: 'rv-1')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.candidate('mb-2')),
    );
    await tester.pumpAndSettle();
    // `a` in the queue, not the pane's own Approve: the two controls
    // are on screen together and must decide the same release.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();

    expect(repo.decideReviewCalls.single.action, 'approve');
    expect(repo.decideReviewCalls.single.candidateMbid, 'mb-2');
  });

  testWidgets('a narrow surface gives the entry the whole page', (
    tester,
  ) async {
    final repo = _repoWith(_detail());
    // Above the "sidebar" size class and below the room two panes need:
    // the arrangement follows what this screen is given, not the window.
    tester.view.physicalSize = const Size(700, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: routedHost(const ReviewSurface(openEntryId: 'rv-1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier(SemanticsIds.reviewPane), findsNothing);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.reviewRow('rv-1')),
      findsNothing,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.reviewApprove),
      findsOneWidget,
    );
  });

  testWidgets('applied entries show status and revert', (tester) async {
    final repo = _repoWith(_detail(status: 'applied'));
    await _pump(tester, _host(repo, 'rv-1'));

    expect(find.text('Decided: applied'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.reviewApprove),
      findsNothing,
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewRevert));
    await tester.pumpAndSettle();

    expect(repo.revertedReviewEntryIds, ['rv-1']);
  });
}
