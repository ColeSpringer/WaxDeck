import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/home/pinned_controller.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck/src/settings/prefs_controller.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

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

  /// Holds every write at the server until completed, when set.
  Completer<void>? putGate;

  /// Holds every session read until completed, when set.
  Completer<void>? sessionGate;

  /// Thrown by every preference read while set.
  WaxDeckApiException? getPrefsError;

  @override
  Future<SessionState> getSession() async {
    await sessionGate?.future;
    return super.getSession();
  }

  @override
  Future<Prefs> getPrefs() async {
    gets++;
    final error = getPrefsError;
    if (error != null) throw error;
    final snapshot = prefs;
    await Future<void>.delayed(const Duration(milliseconds: 25));
    return snapshot;
  }

  @override
  Future<Prefs> putPrefs(Prefs next) async {
    await putGate?.future;
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

/// An engine whose preference entry can be held or made to fail.
class _HeldEngine extends SyncEngine {
  _HeldEngine({required super.db, required super.repository})
    : super(channelFactory: deadChannelFactory());

  /// Holds every queued patch until completed, when set.
  Completer<void>? queueGate;

  /// Fails the next read of the waiting patch, as a mirror that will not
  /// answer does.
  bool failNextPendingRead = false;

  @override
  Future<void> queuePrefsPatch(
    Map<String, Object?> patch, {
    required String owner,
  }) async {
    await queueGate?.future;
    return super.queuePrefsPatch(patch, owner: owner);
  }

  @override
  Future<Map<String, Object?>?> pendingPrefsPatch(String owner) {
    if (failNextPendingRead) {
      failNextPendingRead = false;
      return Future.error(StateError('the mirror would not answer'));
    }
    return super.pendingPrefsPatch(owner);
  }
}

/// A native install whose sync engine never connects: what it is handed
/// waits in the outbox until a test flushes it by hand.
({ProviderContainer container, _HeldEngine engine}) _native(
  FakeRepository repo,
) {
  final db = inMemoryMirrorDatabase();
  // The account the binder names as a session begins.
  final engine = _HeldEngine(db: db, repository: repo)..prefsOwner = _user.id;
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      syncEngineProvider.overrideWithValue(engine),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
    ],
  );
  addTearDown(() async {
    container.dispose();
    engine.dispose();
    await db.close();
  });
  return (container: container, engine: engine);
}

/// What a write looks like with no route to the server.
const _unreachable = WaxDeckApiException(
  code: 'transport',
  message: 'no route to host',
);

const _refused = WaxDeckApiException(
  code: 'invalid-request',
  message: 'refused',
  statusCode: 400,
);

/// Messages carry what to say rather than the words, so an assertion on
/// one picks the locale here.
final _l10n = AppLocalizationsEn();

/// Pins a second album with no route to the server, leaving the patch
/// waiting.
Future<void> _pinOffline(
  _LaggingRepository repo,
  ProviderContainer container,
) async {
  await container.read(prefsControllerProvider.future);
  repo.putPrefsError = _unreachable;
  await container.read(prefsControllerProvider.notifier).setPinned(const [
    'AL-1',
    'AL-2',
  ]);
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

      expect(repo.prefs.radioFavorites, <String>[
        'rs-9',
      ], reason: "the previous account's write must not land here");
      expect(
        repo.putPrefsCalls.where(
          (p) => p.radioFavorites?.contains('rs-2') ?? false,
        ),
        isEmpty,
        reason: 'no write from the old session should have gone out',
      );
    },
  );

  test('a tap while the next account loads waits for its document', () async {
    // The document on screen is still the last account's while the next
    // one's is read. A change built on it and sent would put the last
    // account's settings into this one's.
    final repo = _repo(radioFavorites: const <String>['rs-1']);
    final container = _container(repo);
    container.listen(prefsControllerProvider, (_, _) {});
    await container.read(prefsControllerProvider.future);

    repo
      ..sessionState = const SessionState(authenticated: true, user: _other)
      ..prefs = const Prefs(
        timezone: 'Europe/Madrid',
        radioFavorites: <String>['rs-9'],
      );
    container.invalidate(authControllerProvider);
    await pumpEventQueue();
    await container.read(prefsControllerProvider.notifier).setLocale('es');

    expect(repo.prefs.timezone, 'Europe/Madrid');
    expect(repo.prefs.radioFavorites, <String>['rs-9']);
    expect(repo.prefs.locale, 'es');
  });

  test('a tap the moment the account changes waits for its document', () async {
    // The session names the next account before this provider has
    // rebuilt for it: the document on hand, and the account it is kept
    // for, are still the last one's.
    final repo = _repo(radioFavorites: const <String>['rs-1']);
    final container = _container(repo);
    container.listen(prefsControllerProvider, (_, _) {});
    await container.read(prefsControllerProvider.future);

    repo
      ..sessionState = const SessionState(authenticated: true, user: _other)
      ..prefs = const Prefs(
        timezone: 'Europe/Madrid',
        radioFavorites: <String>['rs-9'],
      );
    container.invalidate(authControllerProvider);
    await container.read(authControllerProvider.future);
    await container.read(prefsControllerProvider.notifier).setLocale('es');

    expect(repo.prefs.timezone, 'Europe/Madrid');
    expect(repo.prefs.radioFavorites, <String>['rs-9']);
    expect(repo.prefs.locale, 'es');
  });

  test('a late answer for the last account is not the next one\'s', () async {
    // What the server stored for the last account arrives after the next
    // one's document has landed. Taken as confirmed, it is what the next
    // refused write would put back on this account's screen.
    final repo = _repo(radioFavorites: const <String>['rs-1']);
    final container = _container(repo);
    container.listen(prefsControllerProvider, (_, _) {});
    await container.read(prefsControllerProvider.future);
    final gate = repo.putGate = Completer<void>();
    final lastAccount = container
        .read(prefsControllerProvider.notifier)
        .setLocale('fr');
    await pumpEventQueue();

    repo
      ..sessionState = const SessionState(authenticated: true, user: _other)
      ..prefs = const Prefs(timezone: 'Europe/Madrid');
    container.invalidate(authControllerProvider);
    await container.read(prefsControllerProvider.future);
    gate.complete();
    await lastAccount;
    repo
      ..putGate = null
      ..putPrefsError = _refused;
    await expectLater(
      container.read(prefsControllerProvider.notifier).setLocale('es'),
      throwsA(isA<WaxDeckApiException>()),
    );

    final shown = container.read(prefsControllerProvider).value;
    expect(shown?.timezone, 'Europe/Madrid');
    expect(shown?.locale, isNull);
  });

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
      expect(loaded.radioFavorites, <String>[
        'rs-9',
      ], reason: 'the held document belongs to the account that stored it');
    },
  );

  group('with no route to the server', () {
    test('a write stands and waits as what it changed', () async {
      final repo = _repo(pinned: const ['AL-1']);
      final h = _native(repo);
      await h.container.read(prefsControllerProvider.future);
      final reads = repo.gets;

      await _pinOffline(repo, h.container);

      expect(h.container.read(prefsControllerProvider).value?.pinned, [
        'AL-1',
        'AL-2',
      ]);
      expect(await h.engine.pendingPrefsPatch(_user.id), {
        'pinned': ['AL-1', 'AL-2'],
      });
      expect(repo.gets, reads, reason: 'nothing was put back or read back');
    });

    test('a write behind a waiting patch waits too', () async {
      // The server answers again before the socket does. Sent at once,
      // this write would land first and the flush would then put the
      // waiting patch's older values over it.
      final repo = _repo(pinned: const ['AL-1']);
      final h = _native(repo);
      await _pinOffline(repo, h.container);

      repo.putPrefsError = null;
      await h.container.read(prefsControllerProvider.notifier).setLocale('es');

      expect(repo.putPrefsCalls, isEmpty);
      expect(await h.engine.pendingPrefsPatch(_user.id), {
        'pinned': ['AL-1', 'AL-2'],
        'locale': 'es',
      });
    });

    test('a write the server refuses is still put back', () async {
      final repo = _repo();
      final h = _native(repo);
      await h.container.read(prefsControllerProvider.future);
      repo.putPrefsError = _refused;

      await expectLater(
        h.container
            .read(prefsControllerProvider.notifier)
            .setTimezone('Mars/Olympus'),
        throwsA(isA<WaxDeckApiException>()),
      );

      expect(
        h.container.read(prefsControllerProvider).value?.timezone,
        'America/Denver',
      );
      expect(await h.engine.pendingPrefsPatch(_user.id), isNull);
    });

    test('a read while a patch waits shows the patch', () async {
      // A refetch before the flush - another device's change, a new
      // session - answers with a document that has not heard of the
      // patch, and would take the change back off every surface.
      final repo = _repo(pinned: const ['AL-1']);
      final h = _native(repo);
      await _pinOffline(repo, h.container);

      h.container.invalidate(prefsControllerProvider);
      final loaded = await h.container.read(prefsControllerProvider.future);

      expect(loaded.pinned, ['AL-1', 'AL-2']);
      expect(repo.prefs.pinned, ['AL-1'], reason: 'nothing was sent');
    });

    test('the flush reads the document back', () async {
      final repo = _repo(pinned: const ['AL-1']);
      final h = _native(repo);
      h.container.listen(prefsControllerProvider, (_, _) {});
      await _pinOffline(repo, h.container);

      // Back, and another device moved the timezone meanwhile.
      repo
        ..putPrefsError = null
        ..prefs = repo.prefs.copyWith(timezone: 'Europe/Madrid');
      await h.engine.flushOutbox();
      await pumpEventQueue();
      final loaded = await h.container.read(prefsControllerProvider.future);

      expect(loaded.timezone, 'Europe/Madrid');
      expect(loaded.pinned, ['AL-1', 'AL-2']);
    });

    test('a refused patch says so and reads the document back', () async {
      final repo = _repo(pinned: const ['AL-1']);
      final h = _native(repo);
      h.container.listen(prefsControllerProvider, (_, _) {});
      await _pinOffline(repo, h.container);

      repo.putPrefsError = _refused;
      await h.engine.flushOutbox();
      await pumpEventQueue();
      final loaded = await h.container.read(prefsControllerProvider.future);

      expect(
        h.container.read(shellMessengerProvider)?.resolve(_l10n),
        'Some settings changed offline were not saved',
      );
      expect(loaded.pinned, ['AL-1']);
    });

    test('a patch the last account left is not the next one\'s', () async {
      // The outbox outlives the session, and a session can end without a
      // sign-out (a token found dead at launch, a session read again).
      // The next account neither sees the patch nor has it sent into its
      // document; it waits for the account that made it.
      final repo = _repo(pinned: const ['AL-1']);
      final h = _native(repo);
      h.container.listen(prefsControllerProvider, (_, _) {});
      await _pinOffline(repo, h.container);

      repo
        ..putPrefsError = null
        ..sessionState = const SessionState(authenticated: true, user: _other)
        ..prefs = const Prefs(pinned: ['AL-9']);
      h.engine.prefsOwner = _other.id;
      h.container.invalidate(authControllerProvider);
      final loaded = await h.container.read(prefsControllerProvider.future);
      await h.engine.flushOutbox();

      expect(loaded.pinned, ['AL-9']);
      expect(repo.prefs.pinned, ['AL-9']);
      expect(await h.engine.pendingPrefsPatch(_user.id), {
        'pinned': ['AL-1', 'AL-2'],
      });
    });

    test(
      'turning a setting back while its change waits sends it back',
      () async {
        // Measured against what the server last said alone, the second
        // change is no change at all, and the first goes out on its own.
        final repo = _repo();
        repo.prefs = repo.prefs.copyWith(autoplay: true);
        final h = _native(repo);
        await h.container.read(prefsControllerProvider.future);
        repo.putPrefsError = _unreachable;
        final prefs = h.container.read(prefsControllerProvider.notifier);
        await prefs.setAutoplay(false);

        await prefs.setAutoplay(true);
        repo.putPrefsError = null;
        await h.engine.flushOutbox();

        expect(repo.prefs.autoplay, isTrue);
      },
    );

    test(
      'a timezone is not queued: the server decides what names exist',
      () async {
        // The editor shows what the server says of a name. Queued, a bad
        // one would be taken now and refused later, with every change
        // queued beside it dropped and the server's sentence never read.
        final repo = _repo();
        final h = _native(repo);
        await h.container.read(prefsControllerProvider.future);
        repo.putPrefsError = _unreachable;

        await expectLater(
          h.container
              .read(prefsControllerProvider.notifier)
              .setTimezone('Mars/Olympus'),
          throwsA(isA<WaxDeckApiException>()),
        );

        expect(await h.engine.pendingPrefsPatch(_user.id), isNull);
        expect(
          h.container.read(prefsControllerProvider).value?.timezone,
          'America/Denver',
        );
      },
    );

    test('a timezone behind a waiting patch sends the patch first', () async {
      final repo = _repo(pinned: const ['AL-1']);
      final h = _native(repo);
      await _pinOffline(repo, h.container);
      repo.putPrefsError = null;

      await h.container
          .read(prefsControllerProvider.notifier)
          .setTimezone('Europe/Madrid');

      expect(repo.prefs.pinned, ['AL-1', 'AL-2']);
      expect(repo.prefs.timezone, 'Europe/Madrid');
      expect(await h.engine.pendingPrefsPatch(_user.id), isNull);
    });

    test(
      'a write behind a waiting patch sends it without the socket',
      () async {
        // The server answers again and the socket does not (a proxy that
        // will not upgrade it, a reconnect still backing off): the write
        // that queues behind the patch sends both.
        final repo = _repo(pinned: const ['AL-1']);
        final h = _native(repo);
        await _pinOffline(repo, h.container);
        repo.putPrefsError = null;

        final sent = h.engine.prefsFlushed.first;
        await h.container
            .read(prefsControllerProvider.notifier)
            .setLocale('es');
        await sent.timeout(const Duration(seconds: 2));

        expect(repo.prefs.pinned, ['AL-1', 'AL-2']);
        expect(repo.prefs.locale, 'es');
        expect(await h.engine.pendingPrefsPatch(_user.id), isNull);
      },
    );

    test(
      'a write after a refused one does not wait for the read back',
      () async {
        // The refusal asks for the document again; with no route that read
        // is retried for seconds, and the next change is what the listener
        // is making now.
        final repo = _repo(pinned: const ['AL-1']);
        final h = _native(repo);
        h.container.listen(prefsControllerProvider, (_, _) {});
        await h.container.read(prefsControllerProvider.future);
        repo.putPrefsError = _refused;
        await expectLater(
          h.container.read(prefsControllerProvider.notifier).setLocale('xx'),
          throwsA(isA<WaxDeckApiException>()),
        );
        repo
          ..getPrefsError = _unreachable
          ..putPrefsError = _unreachable;

        await h.container
            .read(prefsControllerProvider.notifier)
            .setPinned(const ['AL-1', 'AL-2'])
            .timeout(const Duration(seconds: 2));

        expect(await h.engine.pendingPrefsPatch(_user.id), {
          'pinned': ['AL-1', 'AL-2'],
        });
      },
    );

    test('a flush shows what the server stored without reading it', () async {
      final repo = _repo(pinned: const ['AL-1']);
      final h = _native(repo);
      h.container.listen(prefsControllerProvider, (_, _) {});
      await _pinOffline(repo, h.container);
      repo
        ..putPrefsError = null
        ..prefs = repo.prefs.copyWith(timezone: 'Europe/Madrid');
      final reads = repo.gets;

      await h.engine.flushOutbox();
      await pumpEventQueue();

      // The flush's own read, to lay the patch over, and no other.
      expect(repo.gets, reads + 1);
      final shown = h.container.read(prefsControllerProvider).value;
      expect(shown?.timezone, 'Europe/Madrid');
      expect(shown?.pinned, ['AL-1', 'AL-2']);
    });

    test('a waiting patch that no longer reads is left off', () async {
      // Written by a build that spelled a field some other way: the flush
      // will drop it, and until then the document is the server's.
      final repo = _repo(pinned: const ['AL-1']);
      final h = _native(repo);
      await h.engine.db.customStatement(
        'INSERT INTO outbox_mutations (kind, pid, payload, recorded_at) '
        "VALUES ('prefs', 'me', '{\"crossfadeSeconds\": \"loud\"}', 0)",
      );

      final loaded = await h.container
          .read(prefsControllerProvider.future)
          .timeout(const Duration(seconds: 5));

      expect(loaded.pinned, ['AL-1']);
    });

    test(
      'a refusal that lands while the document is read again says so',
      () async {
        final repo = _repo(pinned: const ['AL-1']);
        final h = _native(repo);
        h.container.listen(prefsControllerProvider, (_, _) {});
        await _pinOffline(repo, h.container);
        repo.putPrefsError = _refused;

        // The session is read again, the document with it, and the refusal
        // lands in between.
        final gate = repo.sessionGate = Completer<void>();
        h.container.invalidate(authControllerProvider);
        await pumpEventQueue();
        await h.engine.flushOutbox();
        gate.complete();
        await pumpEventQueue();

        expect(
          h.container.read(shellMessengerProvider)?.resolve(_l10n),
          'Some settings changed offline were not saved',
        );
      },
    );

    test('a flush that lands mid-write is read back after it', () async {
      final repo = _repo(pinned: const ['AL-1']);
      final h = _native(repo);
      h.container.listen(prefsControllerProvider, (_, _) {});
      await _pinOffline(repo, h.container);
      repo.putPrefsError = null;
      final gate = h.engine.queueGate = Completer<void>();
      final write = h.container
          .read(prefsControllerProvider.notifier)
          .setLocale('es');
      await pumpEventQueue();

      // Sent while the write is still on its way into the outbox, and
      // another device moved the timezone meanwhile.
      repo.prefs = repo.prefs.copyWith(timezone: 'Europe/Madrid');
      await h.engine.flushOutbox();
      // The read the flush asks for happens now, with the write still
      // held, so it answers from the document the write holds.
      await h.container.read(prefsControllerProvider.future);
      gate.complete();
      await write;
      await pumpEventQueue();
      final loaded = await h.container.read(prefsControllerProvider.future);

      expect(loaded.timezone, 'Europe/Madrid');
      expect(loaded.pinned, ['AL-1', 'AL-2']);
      expect(loaded.locale, 'es');
    });

    test('a write that can be neither sent nor kept is put back', () async {
      final repo = _repo();
      final h = _native(repo);
      await h.container.read(prefsControllerProvider.future);
      h.engine.failNextPendingRead = true;

      await expectLater(
        h.container.read(prefsControllerProvider.notifier).setLocale('es'),
        throwsA(isA<StateError>()),
      );

      expect(h.container.read(prefsControllerProvider).value?.locale, 'en-US');
    });

    test(
      'a write that loses its route after a sign-out waits for its account',
      () async {
        // The write went out under the account that made it, and its
        // failure comes back once that account has gone.
        final repo = _repo(pinned: const ['AL-1']);
        final h = _native(repo);
        await h.container.read(prefsControllerProvider.future);
        final gate = repo.putGate = Completer<void>();
        repo.putPrefsError = _unreachable;
        final write = h.container
            .read(prefsControllerProvider.notifier)
            .setPinned(const ['AL-1', 'AL-2']);
        await pumpEventQueue();

        await h.container
            .read(authControllerProvider.notifier)
            .signOutLocally();
        gate.complete();
        await write;

        // Kept for the account that made it, measured against what that
        // account's server document was: only the change.
        expect(await h.engine.pendingPrefsPatch(_user.id), {
          'pinned': ['AL-1', 'AL-2'],
        });
      },
    );
  });
}
