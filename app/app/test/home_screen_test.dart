import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/home/home_screen.dart';
import 'package:waxdeck/src/home/home_shelves.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

const _uploader = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDUPLOAD',
  username: 'uploader',
  roles: ['member'],
  uploadEnabled: true,
);

const _sealed = 'tr-01JZX5N8QW3F4V9T2B7KDSEALED';
const _halfHeard = 'tr-01JZX5N8QW3F4V9T2B7KDHALF01';
const _favourite = 'tr-01JZX5N8QW3F4V9T2B7KDFAVE01';
const _book = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';

ItemSummary _track(String pid, String title) =>
    testItem(pid, title: title, artist: 'The Bree Trio');

Finder _byId(String id) => find.bySemanticsIdentifier(id);

/// A library with something on every shelf, so the screen's own hiding
/// rule is what a missing shelf means rather than an empty fixture.
FakeRepository _repo() {
  final repo = FakeRepository(
    items: <ItemSummary>[
      _track(_sealed, 'Still Sealed'),
      _track(_halfHeard, 'Half Heard'),
      _track(_favourite, 'Old Favourite'),
      ItemSummary(
        pid: _book,
        mediaType: MediaType.audiobook,
        title: 'There And Back Again',
        artist: 'B. Baggins',
        durationMs: 3600000,
      ),
    ],
  );
  repo.browseLists[DiscoveryList.recentlyPlayed] = <ItemSummary>[
    _track(_halfHeard, 'Half Heard'),
    _track(_favourite, 'Old Favourite'),
  ];
  repo.browseLists[DiscoveryList.recentlyAdded] = <ItemSummary>[
    _track(_sealed, 'Still Sealed'),
  ];
  repo.browseLists[DiscoveryList.neverPlayed] = <ItemSummary>[
    _track(_sealed, 'Still Sealed'),
  ];
  repo.browseLists[DiscoveryList.rediscover] = <ItemSummary>[
    _track(_favourite, 'Old Favourite'),
  ];
  repo.browseLists[DiscoveryList.mostPlayed] = <ItemSummary>[
    _track(_halfHeard, 'Half Heard'),
  ];
  // Half heard is in progress; the favourite was finished, which is what
  // keeps it off the resume shelf.
  repo.playPositions[_halfHeard] = 60000;
  repo.playPositions[_favourite] = 214000;
  repo.finishedPids.add(_favourite);
  return repo;
}

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    audioEngineProvider.overrideWithValue(FakeEngine()),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
    artworkStoreProvider.overrideWithValue(FakeArtworkStore()),
  ],
  child: routedHost(const HomeScreen()),
);

/// Mounts home in a window tall enough to build every shelf.
///
/// The scaffold's scroll view is lazy, which is the whole point of it:
/// off-screen slivers are not built, so a default 800x600 test window
/// draws the first two shelves and nothing else. A test about which
/// shelves exist has to be able to see them all.
Future<void> _pumpHome(WidgetTester tester, FakeRepository repo) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(repo));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every shelf that has something draws it', (tester) async {
    final repo = _repo();
    await _pumpHome(tester, repo);

    for (final shelf in <String>[
      'continue',
      'recent',
      'sealed',
      'rediscover',
      'most-played',
    ]) {
      expect(
        _byId(SemanticsIds.shelf(shelf)),
        findsOneWidget,
        reason: 'the $shelf shelf has rows and is not drawn',
      );
    }
    // Every card is addressed by its shelf, because the shelves overlap:
    // this track is on Recently added and on Never played at once.
    expect(_byId(SemanticsIds.shelfCard('recent', _sealed)), findsOneWidget);
    expect(_byId(SemanticsIds.shelfCard('sealed', _sealed)), findsOneWidget);
  });

  testWidgets('a finished item is not offered as something to continue', (
    tester,
  ) async {
    final repo = _repo();
    await _pumpHome(tester, repo);

    expect(
      _byId(SemanticsIds.shelfCard('continue', _halfHeard)),
      findsOneWidget,
    );
    expect(
      _byId(SemanticsIds.shelfCard('continue', _favourite)),
      findsNothing,
      reason: 'a finished item is an offer to hear it again, not to carry on',
    );
  });

  testWidgets('a loading shelf ghosts instead of vanishing', (tester) async {
    final repo = _repo()..browseGate = Completer<void>();
    await _pumpHome(tester, repo);

    // Before the delay: nothing, the same as a warm cache.
    expect(find.text('Continue listening'), findsNothing);

    // Past it, the shelf's name and ghost cards hold the room.
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Continue listening'), findsOneWidget);
    expect(find.byType(SkeletonShapes), findsWidgets);

    repo.browseGate!.complete();
    repo.browseGate = null;
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonShapes), findsNothing);
    expect(find.text('Half Heard'), findsWidgets);
  });

  testWidgets('a shelf with nothing on it is not drawn', (tester) async {
    final repo = _repo();
    repo.browseLists[DiscoveryList.rediscover] = const <ItemSummary>[];
    await _pumpHome(tester, repo);

    expect(_byId(SemanticsIds.shelf('rediscover')), findsNothing);
    expect(_byId(SemanticsIds.shelf('sealed')), findsOneWidget);
  });

  testWidgets('an empty library gets the first-run state, not empty shelves', (
    tester,
  ) async {
    final repo = FakeRepository();
    await _pumpHome(tester, repo);

    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(_byId(SemanticsIds.shelf('recent')), findsNothing);
  });

  testWidgets('an uploader gets the add top-right, not a floating one', (
    tester,
  ) async {
    final repo = _repo()
      ..sessionState = const SessionState(authenticated: true, user: _uploader);
    await _pumpHome(tester, repo);

    // The one floating button in the app is gone; the add sits in the
    // bar the way every hub's own add does, under the same gate the
    // FAB had.
    expect(_byId(SemanticsIds.homeAdd), findsOneWidget);
    expect(find.byType(WaxFab), findsNothing);
  });

  testWidgets('a listener without the upload right gets no add', (
    tester,
  ) async {
    final repo = _repo();
    await _pumpHome(tester, repo);
    expect(_byId(SemanticsIds.homeAdd), findsNothing);
  });

  testWidgets('the first-run state carries the add for an uploader', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..sessionState = const SessionState(authenticated: true, user: _uploader);
    await _pumpHome(tester, repo);

    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.text('Add to library'), findsOneWidget);
  });

  testWidgets('the shelves ask for the lists 6.1 names, once each', (
    tester,
  ) async {
    final repo = _repo();
    await _pumpHome(tester, repo);

    final asked = repo.browseCalls.map((call) => call.list).toList();
    expect(
      asked.toSet(),
      <DiscoveryList>{
        DiscoveryList.recentlyPlayed,
        DiscoveryList.recentlyAdded,
        DiscoveryList.neverPlayed,
        DiscoveryList.rediscover,
        DiscoveryList.mostPlayed,
      },
      reason: 'home draws the five item shelves over these five lists',
    );
    // Home is cross-domain: none of its shelves is scoped to a medium.
    expect(repo.browseCalls.every((call) => call.mediaType == null), isTrue);
  });

  testWidgets('the mix shelf carries seeds and mints one on the tap', (
    tester,
  ) async {
    final repo = _repo();
    repo.topLists['genres'] = const TopList(
      kind: 'genres',
      range: '30d',
      entries: <TopEntry>[TopEntry(name: 'Shoegaze', plays: 12, ms: 600000)],
    );
    repo.topLists['artists'] = const TopList(
      kind: 'artists',
      range: '30d',
      entries: <TopEntry>[
        TopEntry(name: 'The Bree Trio', pid: 'ar-1', plays: 9, ms: 500000),
        // No pid: a name that no longer resolves is no seed at all.
        TopEntry(name: 'Gone Band', plays: 3, ms: 100000),
      ],
    );
    repo.instantMixResult = InstantMix(
      basis: MixBasis.metadata,
      items: <ItemSummary>[_track(_sealed, 'Still Sealed')],
    );
    await _pumpHome(tester, repo);

    expect(_byId(SemanticsIds.shelf('mixes')), findsOneWidget);
    // One genre card and one artist card; the artist with no pid is not
    // offered, because there would be nothing to mix from.
    expect(_byId(SemanticsIds.homeMix(0)), findsOneWidget);
    expect(_byId(SemanticsIds.homeMix(1)), findsOneWidget);
    expect(_byId(SemanticsIds.homeMix(2)), findsNothing);

    // Nothing is mixed until something is tapped: a shelf of eight cards
    // would otherwise be eight neighbour-graph walks per visit.
    expect(repo.instantMixCalls, isEmpty);
    await tester.tap(_byId(SemanticsIds.homeMix(0)).first);
    await tester.pumpAndSettle();
    expect(repo.instantMixCalls.single.genre, 'Shoegaze');
    expect(repo.instantMixCalls.single.seedPid, isNull);
  });

  testWidgets('a listener with no history is offered no mixes', (tester) async {
    final repo = _repo();
    await _pumpHome(tester, repo);

    expect(_byId(SemanticsIds.shelf('mixes')), findsNothing);
  });

  testWidgets('a shelf is a region, and its Show all is its own control', (
    tester,
  ) async {
    // A plain `Semantics` merges with everything under it, which turned
    // a shelf into one node announcing itself as a button - header,
    // action, and every card in one label, and nothing addressable
    // inside it.
    final semantics = tester.ensureSemantics();
    final repo = _repo();
    await _pumpHome(tester, repo);

    expect(_byId(SemanticsIds.shelfAll('recent')), findsOneWidget);
    expect(
      tester.getSemantics(_byId(SemanticsIds.shelfAll('recent'))).label,
      'Show all',
      reason: 'the action carries its own name, not the whole shelf\'s',
    );
    // And the cards under it stayed addressable rather than merging into
    // the region above them.
    expect(_byId(SemanticsIds.shelfCard('recent', _sealed)), findsOneWidget);
    // Disposed here rather than in a teardown: the framework verifies
    // handles before teardowns run.
    semantics.dispose();
  });

  testWidgets('a shelf reads a window and draws a card row', (tester) async {
    final repo = _repo();
    await _pumpHome(tester, repo);

    // The window is generous on purpose: the resume shelf drops what is
    // finished, and a media-scoped shelf gets a filtered window rather
    // than a filtered list.
    expect(kHomeShelfWindow, greaterThan(kHomeShelfCards));
  });
}
