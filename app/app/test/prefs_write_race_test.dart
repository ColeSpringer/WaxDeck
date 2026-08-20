import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/home/pinned_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck/src/settings/prefs_controller.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

const _user = WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']);
const _other = WaxDeckUser(id: 'us-2', username: 'guest');

const _stations = <String>['rs-1', 'rs-2', 'rs-3'];
const _entities = <String>['al-1', 'al-2', 'al-3'];

/// A repository that reads and writes the way the real one does under a
/// burst: a GET is served from the document as it stood when the read
/// started and delivered later, and a PUT takes longer still. Both are
/// what makes a poll racing a write able to answer with a document that
/// does not hold the write.
class _LaggingRepository extends FakeRepository {
  int gets = 0;

  @override
  Future<Prefs> getPrefs() async {
    gets++;
    final snapshot = prefs;
    await Future<void>.delayed(const Duration(milliseconds: 25));
    return snapshot;
  }

  @override
  Future<Prefs> putPrefs(Prefs next) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return super.putPrefs(next);
  }
}

_LaggingRepository _repo({
  List<String> radioFavorites = const <String>[],
  List<String> pinned = const <String>[],
  WaxDeckUser user = _user,
}) => _LaggingRepository()
  ..sessionState = SessionState(authenticated: true, user: user)
  ..prefs = Prefs(
    timezone: 'America/Denver',
    locale: 'en-US',
    radioFavorites: radioFavorites,
    pinned: pinned,
  );

ProviderContainer _container(FakeRepository repo) {
  final container = ProviderContainer(
    overrides: [repositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('three radio pins in a row all reach the document', () async {
    final repo = _repo(radioFavorites: _stations);
    final container = _container(repo);
    // Listened rather than read: the fan-out's invalidations have to
    // reach the dial the way they do in the app.
    container.listen(radioFavoritesProvider, (_, _) {});
    await container.read(prefsControllerProvider.future);
    expect(container.read(radioFavoritesProvider), _stations);

    // Three unpins with nothing pacing them, each followed by the
    // server's own echo of the write - which is what the user fan-out
    // turns into an invalidation of this provider.
    final favorites = container.read(radioFavoritesProvider.notifier);
    final taps = <Future<RadioPinRefusal?>>[];
    for (final pid in _stations) {
      taps.add(favorites.toggle(pid));
      container.invalidate(prefsControllerProvider);
    }
    expect(await Future.wait(taps), everyElement(isNull));
    await container.read(prefsControllerProvider.future);

    expect(
      repo.prefs.radioFavorites,
      isEmpty,
      reason: 'every unpin must reach the stored document',
    );
    expect(
      container.read(radioFavoritesProvider),
      isEmpty,
      reason: 'a stale read must not put the unpinned stations back',
    );
    // The rest of the document is not the dial's to lose on the way.
    expect(repo.prefs.timezone, 'America/Denver');
    expect(repo.prefs.locale, 'en-US');
  });

  test('three home pins in a row all reach the document', () async {
    // The same shape over the other field, because it is the same bug
    // in the same place: both notifiers replace their list with
    // whatever the document says.
    final repo = _repo(pinned: _entities);
    final container = _container(repo);
    container.listen(pinnedEntitiesProvider, (_, _) {});
    await container.read(prefsControllerProvider.future);

    final pinned = container.read(pinnedEntitiesProvider.notifier);
    final taps = <Future<PinRefusal?>>[];
    for (final pid in _entities) {
      taps.add(pinned.toggle(pid));
      container.invalidate(prefsControllerProvider);
    }
    expect(await Future.wait(taps), everyElement(isNull));
    await container.read(prefsControllerProvider.future);

    expect(repo.prefs.pinned, isEmpty);
    expect(container.read(pinnedEntitiesProvider), isEmpty);
  });

  test('a burst never rewinds the list mid-run', () async {
    // Each write answers with the server's echo of its own document,
    // which is older than what the taps after it published. Publishing
    // that echo puts stars back on the dial under the thumb that just
    // took them off - and a tap landing in that window computes from
    // the rewound list, which is the lost write this path closes.
    final repo = _repo(radioFavorites: _stations);
    final container = _container(repo);
    final seen = <List<String>>[];
    container.listen(radioFavoritesProvider, (_, next) => seen.add(next));
    await container.read(prefsControllerProvider.future);

    final favorites = container.read(radioFavoritesProvider.notifier);
    final taps = <Future<RadioPinRefusal?>>[];
    for (final pid in _stations) {
      taps.add(favorites.toggle(pid));
      // The server's echo of each write, which is what makes the
      // rebuild read back through the held document as well as through
      // the state - a rewind can arrive by either door.
      container.invalidate(prefsControllerProvider);
    }
    await Future.wait(taps);
    await container.read(prefsControllerProvider.future);

    // The list only ever shortens. A rewind shows up as a step back to
    // a longer list, which is exactly what a listener would see.
    for (var i = 1; i < seen.length; i++) {
      expect(
        seen[i].length,
        lessThanOrEqualTo(seen[i - 1].length),
        reason: 'the dial went from ${seen[i - 1]} back to ${seen[i]}',
      );
    }
    expect(container.read(radioFavoritesProvider), isEmpty);
  });

  test(
    'a write queued across a sign-out never reaches the next account',
    () async {
      // The tap belongs to a session that is gone. Its deferred body must
      // not resume against whoever signed in behind it: applying one
      // account's change to another's document and PUTting it is somebody
      // else's pin appearing in your prefs.
      final repo = _repo(radioFavorites: const <String>['rs-1']);
      final container = _container(repo);
      await container.read(prefsControllerProvider.future);

      // Fired, not awaited: the body has not started.
      final pending = container
          .read(radioFavoritesProvider.notifier)
          .toggle('rs-2');

      // The account changes under it, the way a sign-out does.
      repo
        ..sessionState = const SessionState(authenticated: true, user: _other)
        ..prefs = const Prefs(radioFavorites: <String>['rs-9']);
      container.invalidate(authControllerProvider);
      container.invalidate(prefsControllerProvider);
      await container.read(prefsControllerProvider.future);
      await pending;

      expect(
        repo.prefs.radioFavorites,
        <String>['rs-9'],
        reason: "the previous account's write must not land here",
      );
      expect(
        repo.putPrefsCalls.where(
          (p) => p.radioFavorites?.contains('rs-2') ?? false,
        ),
        isEmpty,
        reason: 'no write from the old session should have gone out',
      );
    },
  );

  test('a settled document is refetched, so another device lands', () async {
    // The held document answers only while a write is in flight. If the
    // flag were never cleared this provider would stop reading, and a
    // pin made elsewhere would never arrive.
    final repo = _repo(radioFavorites: const <String>['rs-1']);
    final container = _container(repo);
    container.listen(radioFavoritesProvider, (_, _) {});
    await container.read(prefsControllerProvider.future);

    await container.read(radioFavoritesProvider.notifier).toggle('rs-2');
    expect(container.read(radioFavoritesProvider), <String>['rs-1', 'rs-2']);

    // Another device pins a third, and the server tells this one.
    repo.prefs = repo.prefs.copyWith(
      radioFavorites: const <String>['rs-1', 'rs-2', 'rs-3'],
    );
    final readsBefore = repo.gets;
    container.invalidate(prefsControllerProvider);
    await container.read(prefsControllerProvider.future);

    expect(
      repo.gets,
      greaterThan(readsBefore),
      reason: 'with no write in flight the document must be refetched',
    );
    expect(container.read(radioFavoritesProvider), <String>[
      'rs-1',
      'rs-2',
      'rs-3',
    ]);
  });

  test(
    'signing in as someone else never answers with the last account',
    () async {
      final repo = _repo(radioFavorites: const <String>['rs-1']);
      final container = _container(repo);
      await container.read(prefsControllerProvider.future);
      await container.read(radioFavoritesProvider.notifier).toggle('rs-2');
      expect(repo.prefs.radioFavorites, <String>['rs-1', 'rs-2']);

      // A different account, with a document of its own.
      repo
        ..sessionState = const SessionState(authenticated: true, user: _other)
        ..prefs = const Prefs(radioFavorites: <String>['rs-9']);
      container.invalidate(authControllerProvider);
      container.invalidate(prefsControllerProvider);

      final loaded = await container.read(prefsControllerProvider.future);
      expect(
        loaded.radioFavorites,
        <String>['rs-9'],
        reason: 'the held document belongs to the account that stored it',
      );
    },
  );
}
