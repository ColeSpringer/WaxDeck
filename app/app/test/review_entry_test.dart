import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/review/review_controller.dart';
import 'package:waxdeck/src/review/review_entry_screen.dart';
import 'package:waxdeck/src/review/review_screen.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'localized_host.dart';
import 'routed_host.dart';

Widget _host(FakeRepository repo, String entryId) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: localizedHost(ReviewEntryScreen(entryId: entryId)),
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

/// The pane at one exact width, which is what the review screen's
/// two-pane threshold hands it.
Future<void> _pumpAtWidth(
  WidgetTester tester,
  FakeRepository repo,
  double width,
) async {
  tester.view.physicalSize = Size(width + 200, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      // Over a Scaffold, which is what the review screen mounts it in:
      // the rows carry ink and ink needs a Material above it.
      child: localizedHost(
        Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: const ReviewEntryView(entryId: 'rv-1'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// How far the diff table's own scroller can move. Zero is a table that
/// fits; anything else is the horizontal scrollbar under the thing
/// being read.
double _diffOverflow(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
        matching: find.byType(Scrollable),
      ),
    )
    .position
    .maxScrollExtent;

void main() {
  group('an entry that cannot be shown', () {
    test('one that is gone settles at once', () async {
      final container = ProviderContainer(
        overrides: [repositoryProvider.overrideWithValue(FakeRepository())],
      );
      addTearDown(container.dispose);
      final entry = reviewEntryProvider('rv-gone');
      final sub = container.listen(entry, (_, _) {});
      addTearDown(sub.close);

      await expectLater(
        container.read(entry.future).timeout(const Duration(seconds: 2)),
        throwsA(isA<WaxDeckApiException>()),
      );
    });

    testWidgets('one that does not exist says so at once, with no retry', (
      tester,
    ) async {
      // A decided entry can be gone by the time a link to it is opened,
      // and it answers 404 on every ask after that.
      await tester.pumpWidget(_host(FakeRepository(), 'rv-gone'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Could not load the entry'), findsOneWidget);
      expect(find.text('That is not here any more.'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(find.byType(SkeletonShapes), findsNothing);
    });

    testWidgets('a transport failure offers Try again', (tester) async {
      final repo = _repoWith(_detail())
        ..reviewError = const WaxDeckApiException(
          code: 'transport',
          message: 'connection refused',
        );
      await tester.pumpWidget(_host(repo, 'rv-1'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Could not load the entry'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      // Riverpod keeps asking on its own; the scope going away ends it.
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the pane', () {
    testWidgets('holds its diff table at the width it declares', (
      tester,
    ) async {
      await _pumpAtWidth(
        tester,
        _repoWith(_detail()),
        ReviewEntryView.minWidth,
      );
      expect(_diffOverflow(tester), 0);
    });

    testWidgets('and one pixel under it does not', (tester) async {
      // Which is what makes the constant a boundary rather than a
      // guess: the pane spends its own padding and the table's border
      // before the table is measured, so a threshold set to the table's
      // 420 hands it 386 and brings the scrollbar back.
      await _pumpAtWidth(
        tester,
        _repoWith(_detail()),
        ReviewEntryView.minWidth - 1,
      );
      expect(_diffOverflow(tester), greaterThan(0));
    });
  });

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
    // A band between the two groups, once and only where there is a
    // second group: the missing rows sat in the same bordered box with
    // nothing between them and the last file that is actually here.
    final band = find.bySemanticsIdentifier(SemanticsIds.diffMissingBand);
    expect(band, findsOneWidget);
    expect(
      find.descendant(of: band, matching: find.text('Not in your library (1)')),
      findsOneWidget,
    );
    final missingRow = find.bySemanticsIdentifier(SemanticsIds.diffMissing(0));
    expect(
      find.descendant(of: missingRow, matching: find.text('Closing Tide')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(band).dy,
      greaterThan(tester.getTopLeft(extraRow).dy),
    );
    expect(
      tester.getTopLeft(missingRow).dy,
      greaterThan(tester.getTopLeft(band).dy),
    );
    // Cataloged tracks get the metadata menu; loose files do not.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.trackMenu('tr-1')),
      findsOneWidget,
    );
  });

  testWidgets('a one-file unit is not told eleven files are missing', (
    tester,
  ) async {
    // The rest of the release is context for a single rip, not absence:
    // the rows already say "On the release" in a neutral colour, and a
    // band over them reading "Not in your library" turns a perfect
    // match into a wall of defects.
    final full = _detail();
    final repo = _repoWith(
      ReviewEntryDetail(
        id: full.id,
        kind: full.kind,
        status: full.status,
        mediaType: full.mediaType,
        origin: full.origin,
        title: full.title,
        artist: full.artist,
        trackCount: 1,
        createdAt: full.createdAt,
        candidates: full.candidates,
        tracks: full.tracks.take(1).toList(),
      ),
    );
    await _pump(tester, _host(repo, 'rv-1'));

    final band = find.bySemanticsIdentifier(SemanticsIds.diffMissingBand);
    expect(band, findsOneWidget);
    expect(
      find.descendant(of: band, matching: find.text('Also on the release (1)')),
      findsOneWidget,
    );
    expect(find.text('Not in your library (1)'), findsNothing);
  });

  testWidgets('nothing missing draws no band', (tester) async {
    // The second candidate proposes nothing this unit does not already
    // have, so there is no second group and nothing to separate.
    final repo = _repoWith(_detail());
    await _pump(tester, _host(repo, 'rv-1'));

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.candidate('mb-2')),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.diffMissingBand),
      findsNothing,
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

  testWidgets('a decision refused for a reason keeps the server\'s words', (
    tester,
  ) async {
    final repo = _repoWith(_detail());
    await _pump(tester, _host(repo, 'rv-1'));
    repo.reviewError = const WaxDeckApiException(
      code: 'conflict',
      message: 'a.flac: destination already exists in the library',
      statusCode: 409,
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs));
    await tester.pumpAndSettle();

    final message = raisedMessage(tester)!;
    expect(
      shellMessageText(message),
      'a.flac: destination already exists in the library',
    );
    expect(message.actionLabel, isNull);
  });

  testWidgets('a busy library offers the same decision again', (tester) async {
    final repo = _repoWith(_detail());
    await _pump(tester, _host(repo, 'rv-1'));
    repo.reviewError = const WaxDeckApiException(
      code: 'catalog-busy',
      message: 'a conflicting catalog job is already running',
      statusCode: 409,
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs));
    await tester.pumpAndSettle();
    final message = raisedMessage(tester)!;
    expect(
      shellMessageText(message),
      "Another job is holding the library's files. Try again shortly.",
    );
    expect(message.actionLabel, 'Retry');

    repo.reviewError = null;
    await pressRaisedAction(tester);
    expect(repo.decideReviewCalls, hasLength(2));
    expect(repo.decideReviewCalls.last.action, 'as-is');
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

  testWidgets('a unit the library already holds says so and offers a copy', (
    tester,
  ) async {
    const holder = DuplicateWarning(
      itemPid: 'tr-9',
      kind: 'content',
      title: 'Opening Tide',
      artist: 'The Cardinal Waves',
    );
    final repo = _repoWith(
      ReviewEntryDetail(
        id: 'rv-1',
        kind: 'import',
        status: 'pending',
        mediaType: MediaType.music,
        origin: 'acquisition',
        title: 'Neon Meridian',
        trackCount: 2,
        createdAt: DateTime.utc(2026, 7, 1),
        duplicateCount: 2,
        candidates: _detail().candidates,
        tracks: const [
          ReviewTrack(
            path: 'a.flac',
            title: 'opening tide',
            durationMs: 200000,
            duplicate: holder,
          ),
          ReviewTrack(
            path: 'b.flac',
            title: 'closing tide',
            durationMs: 100000,
            duplicate: DuplicateWarning(kind: 'content'),
          ),
        ],
      ),
    );
    await _pump(tester, _host(repo, 'rv-1'));

    final banner = find.bySemanticsIdentifier(SemanticsIds.reviewDuplicate);
    expect(banner, findsOneWidget);
    expect(
      find.descendant(
        of: banner,
        matching: find.text('2 files are already in your library'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.reviewDuplicateRow(0)),
        matching: find.text('a.flac: Opening Tide by The Cardinal Waves'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.reviewDuplicateRow(1)),
        matching: find.text('b.flac: an item in a library you cannot open'),
      ),
      findsOneWidget,
      reason: 'a holder the reader cannot see is not named',
    );
    // Every file joins what the library has: approving or marking
    // metadata has nothing to land on, and as-is is a copy.
    final approve = tester.widget<WaxButton>(
      find.ancestor(
        of: find.bySemanticsIdentifier(SemanticsIds.reviewApprove),
        matching: find.byType(WaxButton),
      ),
    );
    expect(approve.onPressed, isNull);
    expect(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs), findsNothing);
    expect(find.text('Add as another copy'), findsOneWidget);
    // An acquisition's staged files can be thrown away too.
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewDiscard));
    await tester.pumpAndSettle();
    expect(repo.decideReviewCalls.single.action, 'discard');

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewAddCopy));
    await tester.pumpAndSettle();
    expect(repo.decideReviewCalls.last.action, 'as-is');
  });

  testWidgets('a unit with new files beside a duplicate keeps its decisions', (
    tester,
  ) async {
    final base = _detail();
    final repo = _repoWith(
      ReviewEntryDetail(
        id: 'rv-1',
        kind: 'import',
        status: 'pending',
        mediaType: MediaType.music,
        origin: 'upload',
        trackCount: 2,
        createdAt: DateTime.utc(2026, 7, 1),
        duplicateCount: 1,
        candidates: base.candidates,
        tracks: const [
          ReviewTrack(
            path: 'a.flac',
            title: 'opening tide',
            durationMs: 200000,
            duplicate: DuplicateWarning(kind: 'name', itemPid: 'tr-9'),
          ),
          ReviewTrack(path: 'b.flac', title: 'bonus jam', durationMs: 100000),
        ],
      ),
    );
    await _pump(tester, _host(repo, 'rv-1'));

    // A name match is a guess: the banner says the file may be there.
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.reviewDuplicate),
        matching: find.text('1 file may already be in your library'),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs), findsOneWidget);
    final approve = tester.widget<WaxButton>(
      find.ancestor(
        of: find.bySemanticsIdentifier(SemanticsIds.reviewApprove),
        matching: find.byType(WaxButton),
      ),
    );
    expect(approve.onPressed, isNotNull);
    // Nor does Discard lead the decisions on a guess.
    final order = [
      for (final b in tester.widgetList<WaxButton>(find.byType(WaxButton)))
        b.semanticsId,
    ];
    expect(
      order.indexOf(SemanticsIds.reviewDiscard),
      greaterThan(order.indexOf(SemanticsIds.reviewApprove)),
    );
  });

  testWidgets('a decided file that joined an item says so', (tester) async {
    final repo = _repoWith(
      ReviewEntryDetail(
        id: 'rv-1',
        kind: 'import',
        status: 'as-is',
        mediaType: MediaType.music,
        origin: 'upload',
        trackCount: 1,
        createdAt: DateTime.utc(2026, 7, 1),
        tracks: const [
          ReviewTrack(
            pid: 'tr-9',
            path: 'a.flac',
            title: 'opening tide',
            durationMs: 200000,
            joined: true,
          ),
        ],
      ),
    );
    await _pump(tester, _host(repo, 'rv-1'));

    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.diffRow(0)),
        matching: find.text('Added to an item the library already had'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.trackMenu('tr-9')),
      findsNothing,
      reason: 'the item is not this entry\'s to edit',
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.reviewDuplicate),
      findsNothing,
    );
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

    expect(find.text('Decided: Applied'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.reviewApprove),
      findsNothing,
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewRevert));
    await tester.pumpAndSettle();

    expect(repo.revertedReviewEntryIds, ['rv-1']);
  });
}
