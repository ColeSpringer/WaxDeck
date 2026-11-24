import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/review/review_controller.dart';
import 'package:waxdeck/src/review/review_entry_screen.dart';
import 'package:waxdeck/src/review/review_screen.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';
import 'wax_finders.dart';

ReviewEntryDetail _detail({
  String status = 'pending',
  String origin = 'upload',
  MediaType mediaType = MediaType.music,
  String? libraryPid,
  bool landed = false,
  bool? mediumFixed,
}) => ReviewEntryDetail(
  id: 'rv-1',
  kind: 'match',
  status: status,
  mediaType: mediaType,
  origin: origin,
  libraryPid: libraryPid,
  mediumFixed: mediumFixed ?? landed,
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
  tracks: [
    ReviewTrack(
      pid: landed ? 'tr-1' : null,
      path: '/music/a.flac',
      title: 'opening tide (untagged)',
      trackNo: 1,
      durationMs: 200000,
    ),
    const ReviewTrack(
      path: '/music/b.flac',
      title: 'bonus jam',
      durationMs: 100000,
    ),
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

/// Decides at once, then holds the answer until [release] completes; the
/// entry reads decided from then on.
class _HeldDecisions extends FakeRepository {
  final release = Completer<void>();

  @override
  Future<ReviewDecideResult> decideReviewEntry(
    String entryId, {
    required String action,
    String? candidateMbid,
    String? mediaType,
  }) async {
    final decided = await super.decideReviewEntry(
      entryId,
      action: action,
      candidateMbid: candidateMbid,
      mediaType: mediaType,
    );
    await release.future;
    reviewEntryDetails.remove(entryId);
    return decided;
  }
}

/// Fails the targets read with something other than a refusal, which
/// the provider holds as an error.
class _BrokenTargets extends FakeRepository {
  @override
  Future<List<UploadTarget>> listUploadTargets() async =>
      throw StateError('the targets read broke');
}

/// Tall enough for the diff to be laid out below the candidate list
/// without the decision bar overrunning it. At the entry's own location,
/// since a decision leaves the page for the queue.
Future<void> _pump(WidgetTester tester, FakeRepository repo) async {
  tester.view.physicalSize = const Size(700, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpApp(
    tester,
    const ReviewEntryScreen(entryId: 'rv-1'),
    container: appContainer(repo: repo),
    at: WaxRoute.reviewEntry('rv-1'),
  );
}

String _location(WidgetTester tester) => GoRouter.of(
  tester.element(find.byType(Navigator).first),
).routerDelegate.currentConfiguration.uri.path;

/// The review surface open on the entry, settled.
Future<void> _pumpSurface(WidgetTester tester, FakeRepository repo) => pumpApp(
  tester,
  const ReviewSurface(openEntryId: 'rv-1'),
  container: appContainer(repo: repo),
);

/// A blank page, for a test that navigates to the review locations itself.
Future<void> _mountBlank(WidgetTester tester, FakeRepository repo) =>
    mountApp(tester, const Scaffold(), container: appContainer(repo: repo));

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
  await pumpApp(
    tester,
    // Over a Scaffold, which is what the review screen mounts it in:
    // the rows carry ink and ink needs a Material above it.
    Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: const ReviewEntryView(entryId: 'rv-1'),
        ),
      ),
    ),
    container: appContainer(repo: repo),
    routed: false,
  );
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
      final container = appContainer();
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
      await mountApp(
        tester,
        const ReviewEntryScreen(entryId: 'rv-gone'),
        routed: false,
      );
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
      await mountApp(
        tester,
        const ReviewEntryScreen(entryId: 'rv-1'),
        container: appContainer(repo: repo),
        routed: false,
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Could not load the entry'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      // Riverpod keeps asking on its own; the scope going away ends it.
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets("the decision bar's surface reaches the window's edges at the "
      'foot of the page, its controls and the entry above it clear of the '
      'insets', (tester) async {
    const insets = FakeViewPadding(left: 40, right: 30, bottom: 20);
    tester.view
      ..physicalSize = const Size(1000, 900)
      ..devicePixelRatio = 1
      ..padding = insets
      ..viewPadding = insets;
    addTearDown(tester.view.reset);
    await mountApp(
      tester,
      const ReviewEntryScreen(entryId: 'rv-1'),
      container: appContainer(repo: _repoWith(_detail())),
      routed: false,
    );
    await tester.pumpAndSettle();

    final bar = tester.getRect(find.byType(WaxFootBar));
    expect((bar.left, bar.right, bar.bottom), (0.0, 1000.0, 900.0));
    final first = tester.getRect(
      find.bySemanticsIdentifier(SemanticsIds.reviewMedium),
    );
    expect(first.left, 40 + 12.0, reason: 'its controls, the start');
    expect(
      tester
          .getRect(
            find.descendant(
              of: find.byType(WaxFootBar),
              matching: find.byType(Wrap),
            ),
          )
          .bottom,
      900 - 20 - 12.0,
      reason: 'its controls, the foot',
    );
    final entry = tester.getRect(
      find
          .descendant(
            of: find.byType(ReviewEntryView),
            matching: find.byType(ListView),
          )
          .first,
    );
    expect((entry.left, entry.right, entry.bottom), (40.0, 970.0, bar.top));
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

    testWidgets('wraps the line saying it is still identifying rather than '
        'running past its narrowest width', (tester) async {
      tester.view.physicalSize = const Size(ReviewEntryView.minWidth, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final detail = _detail();
      await mountApp(
        tester,
        Scaffold(body: ReviewEntryView(entryId: detail.id)),
        container: appContainer(
          repo: _repoWith(
            ReviewEntryDetail(
              id: detail.id,
              kind: detail.kind,
              status: detail.status,
              mediaType: detail.mediaType,
              origin: detail.origin,
              title: detail.title,
              artist: detail.artist,
              trackCount: detail.trackCount,
              createdAt: detail.createdAt,
              identifying: true,
            ),
          ),
        ),
        routed: false,
      );
      // Frames rather than settling: its spinner never stops.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(
        find.text('Identifying: candidate lookup is still running'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
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
    final repo = _repoWith(_detail(landed: true));
    await _pump(tester, repo);

    expect(
      find.bySemanticsIdentifier(SemanticsIds.candidate('mb-1')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.candidate('mb-2')),
      findsOneWidget,
    );
    expect(find.text('94%'), findsOneWidget);
    expect(find.byType(WaxInkTappable), findsAtLeastNWidgets(2));
    expect(find.byType(WaxProgressBar), findsWidgets);
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
    await _pump(tester, repo);

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
    await _pump(tester, repo);

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
    await _pump(tester, repo);

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

  group('reviewMediaOffered', () {
    const both = [MediaType.music, MediaType.audiobook];
    const music = UploadTarget(
      pid: 'lb-music',
      name: 'Music',
      mediaTypes: [MediaType.music],
      managed: true,
    );

    test('an entry naming no library offers both', () {
      expect(reviewMediaOffered(MediaType.music, null, null), both);
      expect(reviewMediaOffered(MediaType.music, '', const [music]), both);
    });

    test('a named library not read yet offers only the entry\'s own', () {
      expect(reviewMediaOffered(MediaType.music, 'lb-music', null), [
        MediaType.music,
      ]);
      expect(reviewMediaOffered(MediaType.audiobook, 'lb-music', null), [
        MediaType.audiobook,
      ]);
    });

    test('a named library offers the entry\'s own and what it takes', () {
      expect(reviewMediaOffered(MediaType.music, 'lb-music', const [music]), [
        MediaType.music,
      ]);
      expect(
        reviewMediaOffered(MediaType.audiobook, 'lb-music', const [music]),
        both,
      );
    });

    test('a named library the targets do not hold offers both', () {
      expect(
        reviewMediaOffered(MediaType.music, 'lb-gone', const [music]),
        both,
      );
      expect(reviewMediaOffered(MediaType.music, 'lb-music', const []), both);
    });
  });

  group('medium of a staged entry', () {
    Finder option(MediaType type) => find.bySemanticsIdentifier(
      SemanticsIds.reviewMediumOption(type.wireName),
    );

    for (final origin in ['upload', 'acquisition']) {
      testWidgets('a $origin entry is decided as the medium chosen', (
        tester,
      ) async {
        final repo = _repoWith(_detail(origin: origin));
        await _pump(tester, repo);

        expect(
          find.bySemanticsIdentifier(SemanticsIds.reviewMedium),
          findsOneWidget,
        );
        await tester.tap(option(MediaType.audiobook));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs));
        await tester.pumpAndSettle();

        expect(repo.decideReviewCalls.single.action, 'as-is');
        expect(repo.decideReviewCalls.single.mediaType, 'audiobook');
      });
    }

    testWidgets('the release search follows the medium chosen', (tester) async {
      final search = find.bySemanticsIdentifier(
        SemanticsIds.reviewIdentifyGroup,
      );
      await _pump(tester, _repoWith(_detail()));
      expect(search, findsOneWidget);

      await tester.tap(option(MediaType.audiobook));
      await tester.pumpAndSettle();
      expect(search, findsNothing);

      await tester.tap(option(MediaType.music));
      await tester.pumpAndSettle();
      expect(search, findsOneWidget);
    });

    testWidgets('an audiobook entry offers the release search once switched '
        'to music', (tester) async {
      final search = find.bySemanticsIdentifier(
        SemanticsIds.reviewIdentifyGroup,
      );
      await _pump(tester, _repoWith(_detail(mediaType: MediaType.audiobook)));
      expect(search, findsNothing);

      await tester.tap(option(MediaType.music));
      await tester.pumpAndSettle();
      expect(search, findsOneWidget);
    });

    testWidgets('an untouched toggle sends the entry\'s own medium', (
      tester,
    ) async {
      final repo = _repoWith(_detail());
      await _pump(tester, repo);

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs));
      await tester.pumpAndSettle();

      expect(repo.decideReviewCalls.single.mediaType, 'music');
    });

    testWidgets('the toggle starts at the entry\'s own medium', (tester) async {
      final repo = _repoWith(_detail(mediaType: MediaType.audiobook));
      await _pump(tester, repo);

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs));
      await tester.pumpAndSettle();

      expect(repo.decideReviewCalls.single.mediaType, 'audiobook');
    });

    testWidgets('scan and rematch entries have no toggle and send no medium', (
      tester,
    ) async {
      for (final origin in ['scan', 'rematch']) {
        final repo = _repoWith(_detail(origin: origin));
        await _pump(tester, repo);

        expect(
          find.bySemanticsIdentifier(SemanticsIds.reviewMedium),
          findsNothing,
          reason: origin,
        );
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs));
        await tester.pumpAndSettle();
        expect(repo.decideReviewCalls.single.mediaType, isNull, reason: origin);
      }
    });

    testWidgets('approve is offered only while music is chosen', (
      tester,
    ) async {
      final repo = _repoWith(_detail());
      await _pump(tester, repo);
      final approve = find.bySemanticsIdentifier(SemanticsIds.reviewApprove);

      expect(approve, findsOneWidget);
      await tester.tap(option(MediaType.audiobook));
      await tester.pumpAndSettle();
      expect(approve, findsNothing);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.reviewAsIs),
        findsOneWidget,
      );
      await tester.tap(option(MediaType.music));
      await tester.pumpAndSettle();
      expect(approve, findsOneWidget);
    });

    testWidgets(
      'an audiobook entry offers no approve whatever its candidates',
      (tester) async {
        final repo = _repoWith(_detail(mediaType: MediaType.audiobook));
        await _pump(tester, repo);

        expect(
          find.bySemanticsIdentifier(SemanticsIds.candidate('mb-1')),
          findsOneWidget,
        );
        expect(
          find.bySemanticsIdentifier(SemanticsIds.reviewApprove),
          findsNothing,
        );
      },
    );

    testWidgets(
      'a refusal reads as the server worded it and keeps the choice',
      (tester) async {
        final repo = _repoWith(_detail());
        await _pump(tester, repo);
        repo.reviewError = const WaxDeckApiException(
          code: 'conflict',
          message: 'a.flac was already imported as music',
          statusCode: 409,
        );
        await tester.tap(option(MediaType.audiobook));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs));
        await tester.pumpAndSettle();

        expect(
          shellMessageText(raisedMessage(tester)!),
          'a.flac was already imported as music',
        );
        repo.reviewError = null;
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs));
        await tester.pumpAndSettle();
        expect(repo.decideReviewCalls.last.mediaType, 'audiobook');
      },
    );

    testWidgets('a fixed medium leaves the toggle out with no track landed', (
      tester,
    ) async {
      final repo = _repoWith(_detail(mediumFixed: true));
      await _pump(tester, repo);

      expect(
        find.bySemanticsIdentifier(SemanticsIds.reviewMedium),
        findsNothing,
      );
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs));
      await tester.pumpAndSettle();
      expect(repo.decideReviewCalls.single.mediaType, 'music');
    });

    testWidgets('a medium not fixed keeps the toggle with no track landed', (
      tester,
    ) async {
      final repo = _repoWith(_detail(mediumFixed: false));
      await _pump(tester, repo);

      expect(
        find.bySemanticsIdentifier(SemanticsIds.reviewMedium),
        findsOneWidget,
      );
    });

    testWidgets('an entry with a track landed has no toggle', (tester) async {
      final repo = _repoWith(_detail(landed: true));
      await _pump(tester, repo);

      expect(
        find.bySemanticsIdentifier(SemanticsIds.reviewMedium),
        findsNothing,
      );
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs));
      await tester.pumpAndSettle();
      expect(repo.decideReviewCalls.single.mediaType, 'music');
    });

    testWidgets('a medium picked before a track landed is not sent', (
      tester,
    ) async {
      final repo = _repoWith(_detail());
      final container = appContainer(repo: repo);
      tester.view.physicalSize = const Size(700, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpApp(
        tester,
        const ReviewEntryScreen(entryId: 'rv-1'),
        container: container,
        at: WaxRoute.reviewEntry('rv-1'),
      );
      await tester.tap(option(MediaType.audiobook));
      await tester.pumpAndSettle();

      repo.reviewEntryDetails['rv-1'] = _detail(landed: true);
      container.invalidate(reviewEntryProvider('rv-1'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier(SemanticsIds.reviewMedium),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.reviewApprove),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs));
      await tester.pumpAndSettle();

      expect(repo.decideReviewCalls.single.mediaType, 'music');
    });

    testWidgets('a landed track leaves the toggle out whatever the library '
        'takes', (tester) async {
      final repo = _repoWith(_detail(libraryPid: 'lb-mixed', landed: true))
        ..uploadTargets.add(
          const UploadTarget(
            pid: 'lb-mixed',
            name: 'lb-mixed',
            mediaTypes: [MediaType.music, MediaType.audiobook],
            managed: true,
          ),
        );
      await _pump(tester, repo);

      expect(
        find.bySemanticsIdentifier(SemanticsIds.reviewMedium),
        findsNothing,
      );
    });

    UploadTarget target(String pid, List<MediaType> media) =>
        UploadTarget(pid: pid, name: pid, mediaTypes: media, managed: true);

    testWidgets('an entry whose library takes only its own medium has no '
        'toggle', (tester) async {
      final repo = _repoWith(_detail(libraryPid: 'lb-music'))
        ..uploadTargets.addAll([
          target('lb-music', const [MediaType.music]),
          target('lb-mixed', const [MediaType.music, MediaType.audiobook]),
        ]);
      await _pump(tester, repo);

      expect(
        find.bySemanticsIdentifier(SemanticsIds.reviewMedium),
        findsNothing,
      );
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs));
      await tester.pumpAndSettle();
      expect(repo.decideReviewCalls.single.mediaType, 'music');
    });

    testWidgets('an entry whose library takes both offers both', (
      tester,
    ) async {
      final repo = _repoWith(_detail(libraryPid: 'lb-mixed'))
        ..uploadTargets.addAll([
          target('lb-music', const [MediaType.music]),
          target('lb-mixed', const [MediaType.music, MediaType.audiobook]),
        ]);
      await _pump(tester, repo);

      expect(option(MediaType.music), findsOneWidget);
      expect(option(MediaType.audiobook), findsOneWidget);
    });

    testWidgets('an entry whose library the targets read cannot name offers '
        'both', (tester) async {
      final repo = _repoWith(_detail(libraryPid: 'lb-music'))
        ..uploadTargetsError = const WaxDeckApiException(
          code: 'forbidden',
          message: 'no',
          statusCode: 403,
        );
      await _pump(tester, repo);

      expect(option(MediaType.music), findsOneWidget);
      expect(option(MediaType.audiobook), findsOneWidget);
    });

    testWidgets('an entry whose targets read fails offers both', (
      tester,
    ) async {
      final repo = _BrokenTargets();
      final detail = _detail(libraryPid: 'lb-music');
      repo.reviewEntries = [
        testReviewEntry(
          detail.id,
          status: detail.status,
          origin: detail.origin,
        ),
      ];
      repo.reviewEntryDetails[detail.id] = detail;
      await _pump(tester, repo);

      expect(option(MediaType.music), findsOneWidget);
      expect(option(MediaType.audiobook), findsOneWidget);
    });

    testWidgets('an entry naming no library offers both, as the server '
        'takes either', (tester) async {
      final repo = _repoWith(_detail())
        ..uploadTargets.add(target('lb-music', const [MediaType.music]));
      await _pump(tester, repo);

      expect(option(MediaType.music), findsOneWidget);
      expect(option(MediaType.audiobook), findsOneWidget);
    });
  });

  testWidgets('a decision in flight draws busy and takes no second press', (
    tester,
  ) async {
    final repo = _HeldDecisions();
    final detail = _detail();
    repo.reviewEntries = [
      testReviewEntry(detail.id, status: detail.status, origin: detail.origin),
    ];
    repo.reviewEntryDetails[detail.id] = detail;
    await _pump(tester, repo);

    WaxButton button(String id) =>
        tester.widget<WaxButton>(waxControl<WaxButton>(id));
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
    await tester.pump();
    expect(button(SemanticsIds.reviewApprove).busy, isTrue);
    expect(button(SemanticsIds.reviewSkip).onPressed, isNull);
    expect(button(SemanticsIds.reviewDiscard).onPressed, isNull);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.reviewApprove),
      warnIfMissed: false,
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.reviewSkip),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(repo.decideReviewCalls, hasLength(1));

    repo.release.complete();
    await tester.pumpAndSettle();
    expect(repo.decideReviewCalls.single.action, 'approve');
    // Answered, the page leaves the decided entry for the queue.
    expect(_location(tester), WaxRoute.review);
  });

  testWidgets('a decision refused for a reason keeps the server\'s words', (
    tester,
  ) async {
    final repo = _repoWith(_detail());
    await _pump(tester, repo);
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
    await _pump(tester, repo);
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
    await _pump(tester, repo);

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
    await _pump(tester, repo);

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

    // The decision left the page; the canned entry reads pending again.
    GoRouter.of(
      tester.element(find.byType(Navigator).first),
    ).go(WaxRoute.reviewEntry('rv-1'));
    await tester.pumpAndSettle();
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
    await _pump(tester, repo);

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
    await _pump(tester, repo);

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
    await _pumpSurface(tester, repo);

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
    await _mountBlank(tester, repo);
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

  testWidgets('a cursor j moved off the open entry follows the next entry '
      'opened', (tester) async {
    final repo = FakeRepository()
      ..reviewEntries = [
        testReviewEntry('rv-1'),
        testReviewEntry('rv-2', title: 'Second Album'),
        testReviewEntry('rv-3', title: 'Third Album'),
      ];
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _mountBlank(tester, repo);
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    router.go(WaxRoute.reviewEntry('rv-1'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();

    router.go(WaxRoute.reviewEntry('rv-3'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();

    expect(repo.decideReviewCalls.map((c) => c.entryId), ['rv-3']);
  });

  testWidgets('the queue key approves the candidate the pane shows', (
    tester,
  ) async {
    final repo = _repoWith(_detail());
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpSurface(tester, repo);

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

  testWidgets('the queue key and the pane decide an entry once between '
      'them', (tester) async {
    final repo = _HeldDecisions();
    final detail = _detail();
    repo.reviewEntries = [
      testReviewEntry(detail.id, status: detail.status, origin: detail.origin),
    ];
    repo.reviewEntryDetails[detail.id] = detail;
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpSurface(tester, repo);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    WaxButton button(String id) =>
        tester.widget<WaxButton>(waxControl<WaxButton>(id));
    expect(button(SemanticsIds.reviewApprove).busy, isTrue);
    expect(button(SemanticsIds.reviewSkip).onPressed, isNull);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.reviewApprove),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(repo.decideReviewCalls, hasLength(1));

    repo.release.complete();
    await tester.pumpAndSettle();
    expect(repo.decideReviewCalls.single.action, 'approve');
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
    await _pumpSurface(tester, repo);

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

  testWidgets('a decision on the page of its own returns to the queue', (
    tester,
  ) async {
    final repo = _repoWith(_detail());
    repo.reviewEntries = [
      ...repo.reviewEntries,
      testReviewEntry('rv-2', title: 'Second Album'),
    ];
    tester.view.physicalSize = const Size(700, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _mountBlank(tester, repo);
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    router.go(WaxRoute.reviewEntry('rv-1'));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewEntryScreen), findsOneWidget);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs));
    await tester.pumpAndSettle();

    expect(repo.decideReviewCalls.single.action, 'as-is');
    expect(_location(tester), WaxRoute.review);
    expect(find.byType(ReviewEntryScreen), findsNothing);
    expect(find.byType(ReviewScreen), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.reviewRow('rv-2')),
      findsOneWidget,
    );
    expect(shellMessageText(raisedMessage(tester)), 'Decided 1 entry');
  });

  testWidgets('a decision on the page of its own that lands once the '
      'visitor went elsewhere leaves them there', (tester) async {
    final repo = _repoWith(_detail());
    repo.reviewEntries = [
      ...repo.reviewEntries,
      testReviewEntry('rv-2', title: 'Second Album'),
    ];
    tester.view.physicalSize = const Size(700, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _mountBlank(tester, repo);
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    router.go(WaxRoute.reviewEntry('rv-1'));
    await tester.pumpAndSettle();
    final gate = repo.decideReviewGate = Completer<void>();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewAsIs));
    await tester.pump();
    router.go(WaxRoute.home);
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repo.decideReviewCalls.single.action, 'as-is');
    expect(_location(tester), WaxRoute.home);
    expect(shellMessageText(raisedMessage(tester)), 'Decided 1 entry');
  });

  testWidgets('an approve made on the page of its own is undone from the '
      'queue, which stays', (tester) async {
    final repo = _repoWith(_detail());
    repo.reviewEntries = [
      ...repo.reviewEntries,
      testReviewEntry('rv-2', title: 'Second Album'),
    ];
    tester.view.physicalSize = const Size(700, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _mountBlank(tester, repo);
    GoRouter.of(
      tester.element(find.byType(Scaffold).first),
    ).go(WaxRoute.reviewEntry('rv-1'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
    await tester.pumpAndSettle();
    expect(_location(tester), WaxRoute.review);
    expect(raisedMessage(tester)!.actionLabel, 'Undo');

    await pressRaisedAction(tester);
    expect(repo.revertedReviewEntryIds, ['rv-1']);
    expect(_location(tester), WaxRoute.review);
    expect(find.byType(ReviewEntryScreen), findsNothing);
    // Reverted is decided: the queue the visitor is on holds the rest.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.reviewRow('rv-2')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.reviewRow('rv-1')),
      findsNothing,
    );
    expect(shellMessageText(raisedMessage(tester)), 'Decision undone');
  });

  testWidgets('applied entries show status and revert', (tester) async {
    final repo = _repoWith(_detail(status: 'applied'));
    await _pump(tester, repo);

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
