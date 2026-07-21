import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/review/review_entry_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

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

void main() {
  testWidgets('renders candidates and the track diff', (tester) async {
    final repo = _repoWith(_detail());
    await tester.pumpWidget(_host(repo, 'rv-1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('candidate-mb-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('candidate-mb-2')), findsOneWidget);
    expect(find.text('94%'), findsOneWidget);
    expect(find.text('2011, Cardinal, GB'), findsOneWidget);

    final firstRow = find.byKey(const ValueKey('diff-row-0'));
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
    final extraRow = find.byKey(const ValueKey('diff-row-1'));
    expect(
      find.descendant(
        of: extraRow,
        matching: find.text('Extra file, no counterpart'),
      ),
      findsOneWidget,
    );
    final missingRow = find.byKey(const ValueKey('diff-missing-0'));
    expect(
      find.descendant(of: missingRow, matching: find.text('Closing Tide')),
      findsOneWidget,
    );
    // Cataloged tracks get the metadata menu; loose files do not.
    expect(find.byKey(const ValueKey('track-menu-tr-1')), findsOneWidget);
  });

  testWidgets('approve sends the selected candidate', (tester) async {
    final repo = _repoWith(_detail());
    await tester.pumpWidget(_host(repo, 'rv-1'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('candidate-mb-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-approve')));
    await tester.pumpAndSettle();

    expect(repo.decideReviewCalls, hasLength(1));
    expect(repo.decideReviewCalls.single.action, 'approve');
    expect(repo.decideReviewCalls.single.candidateMbid, 'mb-2');
  });

  testWidgets('the other decisions and the upload discard work', (
    tester,
  ) async {
    final repo = _repoWith(_detail());
    await tester.pumpWidget(_host(repo, 'rv-1'));
    await tester.pumpAndSettle();

    // Upload entries expose Discard next to the standard actions.
    expect(find.byKey(const Key('review-as-is')), findsOneWidget);
    expect(find.byKey(const Key('review-unofficial')), findsOneWidget);
    await tester.tap(find.byKey(const Key('review-discard')));
    await tester.pumpAndSettle();

    expect(repo.decideReviewCalls.single.action, 'discard');
  });

  testWidgets('applied entries show status and revert', (tester) async {
    final repo = _repoWith(_detail(status: 'applied'));
    await tester.pumpWidget(_host(repo, 'rv-1'));
    await tester.pumpAndSettle();

    expect(find.text('Decided: applied'), findsOneWidget);
    expect(find.byKey(const Key('review-approve')), findsNothing);
    await tester.tap(find.byKey(const Key('review-revert')));
    await tester.pumpAndSettle();

    expect(repo.revertedReviewEntryIds, ['rv-1']);
  });
}
