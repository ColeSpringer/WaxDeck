import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/home/pinned_controller.dart';
import 'package:waxdeck/src/home/pinned_shelf.dart';
import 'package:waxdeck/src/podcasts/show_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/prefs_controller.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

const _album = 'al-01JZX5N8QW3F4V9T2B7KDALBUM';
const _show = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const _departed = 'ar-01JZX5N8QW3F4V9T2B7KDGONE01';

Finder _byId(String id) => find.bySemanticsIdentifier(id);

FakeRepository _repo({List<String> pinned = const <String>[]}) {
  // Signed in, because the preference document a pin lives in is only
  // fetched for an authenticated session - which is the point of putting
  // pins on the account.
  final repo = FakeRepository(
    sessionState: const SessionState(
      authenticated: true,
      user: WaxDeckUser(
        id: 'us-1',
        username: 'admin',
        roles: <String>['admin'],
      ),
    ),
  )..prefs = Prefs(pinned: pinned);
  repo.entityCards[_album] = const EntityCard(
    pid: _album,
    kind: EntityCardKind.album,
    title: 'Long Exposure',
    artist: 'Field Notes',
    itemCount: 9,
  );
  repo.entityCards[_show] = const EntityCard(
    pid: _show,
    kind: EntityCardKind.podcast,
    title: 'Contact Sheet',
    artist: 'Nightjar Media',
  );
  return repo;
}

Future<void> _pump(WidgetTester tester, FakeRepository repo) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        audioEngineProvider.overrideWithValue(FakeEngine()),
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        artworkStoreProvider.overrideWithValue(FakeArtworkStore()),
      ],
      // A Scaffold around it, because a ScaffoldMessenger with none
      // registered queues a snackbar rather than showing it, and the
      // unpin confirmation is one of the things under test.
      child: routedHost(
        const Scaffold(
          body: CustomScrollView(slivers: <Widget>[PinnedShelf()]),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('nothing pinned draws no shelf and asks nothing', (tester) async {
    final repo = _repo();
    await _pump(tester, repo);

    expect(_byId(SemanticsIds.shelf('pinned')), findsNothing);
    // Short-circuited on the stored list: an empty shelf must not cost a
    // round trip on every home load.
    expect(repo.resolvedEntityPids, isEmpty);
  });

  testWidgets('the pins are drawn in the order they are stored', (
    tester,
  ) async {
    final repo = _repo(pinned: <String>[_show, _album]);
    await _pump(tester, repo);

    expect(_byId(SemanticsIds.shelf('pinned')), findsOneWidget);
    expect(repo.resolvedEntityPids.single, <String>[_show, _album]);
    expect(_byId(SemanticsIds.shelfCard('pinned', _album)), findsOneWidget);
    expect(_byId(SemanticsIds.shelfCard('pinned', _show)), findsOneWidget);
    // The caption says what a thing is, so a shelf mixing kinds is
    // readable without opening anything.
    expect(find.text('Album · Field Notes'), findsOneWidget);
    expect(find.text('Podcast · Nightjar Media'), findsOneWidget);
  });

  testWidgets('a pin that no longer resolves is dropped, not an error', (
    tester,
  ) async {
    final repo = _repo(pinned: <String>[_departed, _album]);
    await _pump(tester, repo);

    expect(_byId(SemanticsIds.shelfCard('pinned', _album)), findsOneWidget);
    expect(_byId(SemanticsIds.shelfCard('pinned', _departed)), findsNothing);
    // An unnamed omission stays in the document: the server withholds
    // the departed name for anything that might come back (a grant, a
    // lapsed subscription, a half-loaded library), and only the named
    // set is ever pruned.
    expect(repo.resolvedEntityPids.single, contains(_departed));
    expect(repo.prefs.pinned, contains(_departed));
  });

  testWidgets('a pid the server names departed is pruned from the '
      'document', (tester) async {
    final repo = _repo(pinned: <String>[_departed, _album]);
    repo.departedEntityPids.add(_departed);
    await _pump(tester, repo);

    // The card still draws for what resolved, and the dead slot is
    // reclaimed: 64 is a cap worth pruning for.
    expect(_byId(SemanticsIds.shelfCard('pinned', _album)), findsOneWidget);
    expect(repo.prefs.pinned, <String>[_album]);
    // The prune rewrites the list this provider watches, so one more
    // resolve goes out without the departed pid and the loop closes.
    expect(repo.resolvedEntityPids.last, <String>[_album]);
  });

  testWidgets('every pin having departed goes quiet rather than empty', (
    tester,
  ) async {
    final repo = _repo(pinned: <String>[_departed]);
    await _pump(tester, repo);

    expect(_byId(SemanticsIds.shelf('pinned')), findsNothing);
  });

  testWidgets('a card unpins through its own gesture', (tester) async {
    final repo = _repo(pinned: <String>[_album]);
    await _pump(tester, repo);

    await tester.longPress(_byId(SemanticsIds.shelfCard('pinned', _album)));
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.entityPin));
    await tester.pumpAndSettle();
    // Twice: the write is a future with no frame behind it, so the first
    // settle can return before the snackbar it schedules exists.
    await tester.pumpAndSettle();

    expect(repo.putPrefsCalls.single.pinned, isEmpty);
    expect(_byId(SemanticsIds.shelf('pinned')), findsNothing);
    expect(find.text('Unpinned Long Exposure'), findsOneWidget);
  });

  _showPinGroup();

  group('PinnedEntities', () {
    ProviderContainer container(FakeRepository repo) {
      final c = ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('a pin goes on the end, so the shelf does not reshuffle', () async {
      final repo = _repo(pinned: <String>[_album]);
      final c = container(repo);
      await c.read(prefsControllerProvider.future);

      expect(await c.read(pinnedEntitiesProvider.notifier).toggle(_show), null);

      expect(c.read(pinnedEntitiesProvider), <String>[_album, _show]);
      expect(repo.putPrefsCalls.single.pinned, <String>[_album, _show]);
    });

    test('unpinning writes the list without it', () async {
      final repo = _repo(pinned: <String>[_album, _show]);
      final c = container(repo);
      await c.read(prefsControllerProvider.future);

      await c.read(pinnedEntitiesProvider.notifier).toggle(_album);

      expect(c.read(pinnedEntitiesProvider), <String>[_show]);
    });

    test('a refused write puts the old list back and says why', () async {
      final repo = _repo(pinned: <String>[_album]);
      repo.putPrefsError = const WaxDeckApiException(
        statusCode: 400,
        code: 'invalid-request',
        message: 'not a pinnable entity pid',
      );
      final c = container(repo);
      await c.read(prefsControllerProvider.future);

      final refusal = await c
          .read(pinnedEntitiesProvider.notifier)
          .toggle(_show);

      expect(refusal, 'not a pinnable entity pid');
      expect(c.read(pinnedEntitiesProvider), <String>[_album]);
    });

    test('a full list refuses the pin rather than dropping it', () async {
      final full = <String>[
        for (var i = 0; i < PinnedEntities.limit; i++)
          'al-01JZX5N8QW3F4V9T2B7KD3M9${String.fromCharCode(65 + i % 26)}$i',
      ];
      final repo = _repo(pinned: full);
      final c = container(repo);
      await c.read(prefsControllerProvider.future);

      final refusal = await c
          .read(pinnedEntitiesProvider.notifier)
          .toggle(_show);

      expect(refusal, contains('Unpin'));
      // Not written at all: a tap that reports success and does nothing
      // is worse than one that says the list is full.
      expect(repo.putPrefsCalls, isEmpty);
    });
  });
}

// Unsubscribing is routine and reversible, and the resolver answers
// pinned shows through the caller's subscriptions - so an unsubscribed
// pin draws no card. If the show screen also hid the row, the pid would
// sit in the document holding a slot of the cap with nowhere left to
// remove it: the one departure a pin accepts is an entity that is
// gone, not one a tap can bring back.
void _showPinGroup() {
  group('a pinned show that was unsubscribed', () {
    Future<void> open(WidgetTester tester, FakeRepository repo) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            audioEngineProvider.overrideWithValue(FakeEngine()),
            credentialStoreProvider.overrideWithValue(
              InMemoryCredentialStore(),
            ),
            artworkStoreProvider.overrideWithValue(FakeArtworkStore()),
          ],
          child: routedHost(const ShowScreen(pid: _show)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_byId(SemanticsIds.showOverflow));
      await tester.pumpAndSettle();
    }

    testWidgets('still offers the row that unpins it', (tester) async {
      final repo = _repo(pinned: <String>[_show]);
      await open(tester, repo);

      expect(_byId(SemanticsIds.showPin), findsOneWidget);
      expect(find.text('Unpin from Home'), findsOneWidget);
    });

    testWidgets('an unsubscribed show nobody pinned offers no row', (
      tester,
    ) async {
      final repo = _repo();
      await open(tester, repo);

      expect(_byId(SemanticsIds.showPin), findsNothing);
    });
  });
}
