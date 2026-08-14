import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/review/review_entry_screen.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'localized_host.dart';

/// The editable identify query: three fields and a Search again, offered
/// on any pending entry rather than gated on poor results.

ReviewEntryDetail _entry({
  String status = 'pending',
  ReviewOverride? stored,
  ReviewOverride? suggested,
  int trackCount = 1,
  List<ReviewCandidate> candidates = const [],
}) => ReviewEntryDetail(
  id: 'rv-1',
  kind: 'import',
  status: status,
  mediaType: MediaType.music,
  origin: 'acquisition',
  title: "How Ya Livin' feat. Nas",
  artist: 'Blue Room Records - Topic',
  trackCount: trackCount,
  createdAt: DateTime.utc(2026, 8, 1),
  candidates: candidates,
  identifyOverride: stored,
  suggested: suggested,
);

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: localizedHost(const ReviewEntryScreen(entryId: 'rv-1')),
);

FakeRepository _repo(ReviewEntryDetail detail) {
  final repo = FakeRepository();
  repo.reviewEntries = [detail];
  repo.reviewEntryDetails['rv-1'] = detail;
  return repo;
}

Finder _field(String name) =>
    find.bySemanticsIdentifier(SemanticsIds.reviewIdentifyField(name));

void main() {
  testWidgets('the group is offered on a pending entry, collapsed', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_repo(_entry())));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.reviewIdentifyGroup),
      findsOne,
    );
    expect(_field('artist'), findsNothing, reason: 'collapsed until asked for');

    await tester.tap(find.text('Search for something else'));
    await tester.pumpAndSettle();
    expect(_field('artist'), findsOne);
    expect(_field('album'), findsOne);
    expect(_field('title'), findsOne);
  });

  testWidgets('a stored override opens the group and prefills it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _repo(
          _entry(
            stored: const ReviewOverride(
              artist: 'Nas',
              album: 'Stillmatic',
              title: "How Ya Livin'",
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open from the start: it is the only way to see, and undo, what
    // the last search was for.
    expect(_field('artist'), findsOne);
    expect(find.text('Nas'), findsOne);
    expect(find.text('Stillmatic'), findsOne);
  });

  testWidgets('Search again sends what was typed', (tester) async {
    final repo = _repo(_entry());
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search for something else'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('artist'), 'Nas');
    await tester.enterText(_field('title'), "How Ya Livin'");
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.reviewIdentifySubmit),
    );
    await tester.pumpAndSettle();

    expect(repo.reidentifyCalls, hasLength(1));
    final call = repo.reidentifyCalls.single;
    expect(call.entryId, 'rv-1');
    expect(call.artist, 'Nas');
    expect(call.album, '');
    expect(call.title, "How Ya Livin'");
  });

  testWidgets('clearing the fields and searching again is how it undoes', (
    tester,
  ) async {
    final repo = _repo(
      _entry(
        stored: const ReviewOverride(artist: 'Nas', title: 'Wrong'),
      ),
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.enterText(_field('artist'), '');
    await tester.enterText(_field('title'), '');
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.reviewIdentifySubmit),
    );
    await tester.pumpAndSettle();

    final call = repo.reidentifyCalls.single;
    expect(call.artist, '');
    expect(call.title, '');
  });

  testWidgets('a decided entry is not offered the search', (tester) async {
    await tester.pumpWidget(_host(_repo(_entry(status: 'as-is'))));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.reviewIdentifyGroup),
      findsNothing,
    );
  });

  testWidgets('Search again is held back while identification runs', (
    tester,
  ) async {
    final detail = ReviewEntryDetail(
      id: 'rv-1',
      kind: 'import',
      status: 'pending',
      mediaType: MediaType.music,
      origin: 'acquisition',
      title: 'Working',
      trackCount: 1,
      identifying: true,
      createdAt: DateTime.utc(2026, 8, 1),
      identifyOverride: const ReviewOverride(artist: 'Nas'),
    );
    await tester.pumpWidget(_host(_repo(detail)));
    // Pumped rather than settled: an identifying entry draws a spinner,
    // and pumpAndSettle waits for an animation that never ends.
    await tester.pump();
    await tester.pump();

    final submit = find.ancestor(
      of: find.bySemanticsIdentifier(SemanticsIds.reviewIdentifySubmit),
      matching: find.byType(WaxButton),
    );
    expect(tester.widget<WaxButton>(submit).onPressed, isNull);
  });

  testWidgets('a suggestion opens the group and prefills, labeled as one', (
    tester,
  ) async {
    final repo = _repo(
      _entry(
        suggested: const ReviewOverride(artist: 'Nas', title: "How Ya Livin'"),
      ),
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(_field('artist'), findsOne, reason: 'a guess is worth showing');
    expect(find.text('Nas'), findsOne);
    expect(find.textContaining('Suggested from the source title'), findsOne);

    // Accepting it as-is sends the guess, so nobody retypes what the
    // parse already read.
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.reviewIdentifySubmit),
    );
    await tester.pumpAndSettle();
    final call = repo.reidentifyCalls.single;
    expect(call.artist, 'Nas');
    expect(call.title, "How Ya Livin'");
  });

  testWidgets('a stored override wins over the suggestion, field by field', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _repo(
          _entry(
            stored: const ReviewOverride(artist: 'Nas Escobar'),
            suggested: const ReviewOverride(
              artist: 'Nas',
              title: "How Ya Livin'",
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nas Escobar'), findsOne);
    expect(find.text('Nas'), findsNothing);
    // The title the override left empty still takes the guess.
    expect(find.text("How Ya Livin'"), findsOne);
    // And the copy stops calling it a suggestion once anything is
    // stored, because half of what is shown no longer is one.
    expect(
      find.textContaining('Suggested from the source title'),
      findsNothing,
    );
  });

  testWidgets('a multi-file unit is not offered a track title', (tester) async {
    await tester.pumpWidget(_host(_repo(_entry(trackCount: 4))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search for something else'));
    await tester.pumpAndSettle();

    // The server ignores it there, so offering it would be a control
    // with nothing behind it.
    expect(_field('artist'), findsOne);
    expect(_field('album'), findsOne);
    expect(_field('title'), findsNothing);
  });

  testWidgets('a field nobody touched takes the value the server changed', (
    tester,
  ) async {
    final repo = _repo(_entry(stored: const ReviewOverride(artist: 'Nas')));
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();
    expect(find.text('Nas'), findsOne);

    // The entry refetches with a different stored value - another
    // device searched, or the server normalised what was sent.
    repo.reidentifyStoresInstead = const ReviewOverride(artist: 'Nas Escobar');
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.reviewIdentifySubmit),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nas Escobar'), findsOne);
    expect(find.text('Nas'), findsNothing);
  });

  testWidgets('a refetch never deletes what somebody is typing', (
    tester,
  ) async {
    final repo = _repo(_entry(stored: const ReviewOverride(artist: 'Nas')));
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    // Half a sentence in, a refetch lands with a different value.
    await tester.enterText(_field('artist'), 'Nas Es');
    await tester.pumpAndSettle();
    repo.reidentifyStoresInstead = const ReviewOverride(
      artist: 'Somebody Else',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.reviewIdentifySubmit),
    );
    await tester.pumpAndSettle();

    // What was being typed is what the server was sent, and it is still
    // in the field: the fresh value loses to an edit in progress.
    expect(repo.reidentifyCalls.single.artist, 'Nas Es');
    expect(find.text('Nas Es'), findsOne);
    expect(find.text('Somebody Else'), findsNothing);
  });
}
