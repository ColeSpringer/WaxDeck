import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_store.dart';
import 'package:waxdeck/src/auth/account_binder.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart' show playbackHeldProvider;
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_persistence.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck/src/settings/prefs_controller.dart';
import 'package:waxdeck/src/sync/server_event_bus.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'app_host.dart';
import 'fakes.dart';

/// However a session ends, what it left on this client goes with it: the
/// next account to sign in finds none of the last one's queue, resume
/// offer or station.

const _ann = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDACCANN',
  username: 'ann',
  roles: ['user'],
);
const _ben = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDACCBEN',
  username: 'ben',
  roles: ['user'],
);
const _cid = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDACCCID',
  username: 'cid',
  roles: ['user'],
);

const _album = QueueSource(
  kind: QueueSourceKind.album,
  label: 'Kind of Blue',
  pid: 'al-1',
);

final _station = RadioStation(
  pid: 'rs-01JZX5N8QW3F4V9T2B7KDSTATN1',
  name: 'Coastal FM',
  streamUrl: 'https://stream.example/coastal',
  createdAt: DateTime.utc(2026, 7, 1),
);

/// A server whose sign-ins answer whoever [next] names.
class _Server extends FakeRepository {
  _Server({required super.sessionState})
    : super(items: [testItem('tr-A'), testItem('tr-B')]);

  WaxDeckUser next = _ben;

  /// What a session read fails with, while set.
  WaxDeckApiException? sessionError;

  int prefsReads = 0;
  int sessionReads = 0;

  @override
  Future<Prefs> getPrefs() {
    prefsReads++;
    return super.getPrefs();
  }

  @override
  Future<LoginResult> login({
    required String username,
    required String password,
    String? deviceName,
  }) async {
    sessionState = SessionState(authenticated: true, user: next);
    return LoginResult(user: next, token: 'token-${next.username}');
  }

  /// A session decoded afresh, as the real client's every read is.
  @override
  Future<SessionState> getSession() async {
    sessionReads++;
    if (sessionError case final error?) throw error;
    final read = await super.getSession();
    return SessionState(
      authenticated: read.authenticated,
      serverReadOnly: read.serverReadOnly,
      user: switch (read.user) {
        final user? => WaxDeckUser(
          id: user.id,
          username: user.username,
          displayName: user.displayName,
          roles: [...user.roles],
          uploadEnabled: user.uploadEnabled,
          managePodcasts: user.managePodcasts,
          canDelete: user.canDelete,
        ),
        null => null,
      },
    );
  }
}

/// The device's queue store, holding what the last launch left.
class _Disk implements QueueStore {
  _Disk([this.saved]);

  StoredQueue? saved;
  var clears = 0;

  @override
  Future<StoredQueue?> load() async => saved;

  @override
  Future<void> save(StoredQueue queue) async => saved = queue;

  @override
  Future<void> clear() async {
    clears++;
    saved = null;
  }
}

/// Artwork whose wipe waits on [gate]: the cleanup is held there, after
/// the queue and the station went and before the session flips.
class _HeldArtwork extends FakeArtworkStore {
  final gate = Completer<void>();
  final _reached = Completer<void>();
  var wipes = 0;

  Future<void> get reached => _reached.future;

  @override
  Future<void> forgetEverything() async {
    wipes++;
    if (!_reached.isCompleted) _reached.complete();
    await gate.future;
    await super.forgetEverything();
  }
}

/// A keychain that will not let go of the token: each clear waits on
/// [gate], then fails.
class _LockedKeychain extends InMemoryCredentialStore {
  final gate = Completer<void>();
  var clears = 0;

  @override
  Future<void> clearToken() async {
    clears++;
    await gate.future;
    throw StateError('the keychain is locked');
  }
}

/// The queue Ann was playing when she last closed the app.
StoredQueue _annsQueue() => StoredQueue(
  entries: const [StoredQueueEntry(queueId: 'q0', pid: 'tr-A', sourceRank: 0)],
  currentIndex: 0,
  shuffled: false,
  repeat: 'off',
  sourceKind: 'album',
  sourceLabel: 'Kind of Blue',
  nextQueueId: 1,
  updatedAt: DateTime.utc(2026, 10, 30),
);

typedef _Client = ({
  ProviderContainer container,
  _Server server,
  ServerEventBus bus,
  FakeEngine engine,
  _Disk disk,
  InMemoryCredentialStore credentials,
});

/// A client with the session layer mounted the way the signed-in scope
/// mounts it: the account binder hears the server's account markers.
_Client _client({
  SessionState session = const SessionState(authenticated: true, user: _ann),
  StoredQueue? disk,
  String? storedToken,
  ArtworkStore? artwork,
  InMemoryCredentialStore? keychain,
}) {
  final server = _Server(sessionState: session);
  final bus = ServerEventBus();
  final engine = FakeEngine();
  final store = _Disk(disk);
  final credentials = (keychain ?? InMemoryCredentialStore())
    ..token = storedToken;
  final container = appContainer(
    repo: server,
    engine: engine,
    credentials: credentials,
    artwork: artwork,
    settings: MemoryClientSettingsStore(),
    extra: [
      serverEventBusProvider.overrideWith((ref) => bus),
      queueStoreProvider.overrideWithValue(store),
      queueSaveDebounceProvider.overrideWithValue(Duration.zero),
    ],
  );
  addTearDown(bus.dispose);
  final binder = container.listen(accountBinderProvider, (_, _) {});
  addTearDown(binder.close);
  return (
    container: container,
    server: server,
    bus: bus,
    engine: engine,
    disk: store,
    credentials: credentials,
  );
}

/// Holds the resume offer the way the deck bar does, and answers it.
Future<RestorableQueue?> _heldOffer(ProviderContainer container) {
  final held = container.listen(queueRestoreProvider, (_, _) {});
  addTearDown(held.close);
  return container.read(queueRestoreProvider.future);
}

/// Until the client holds a session [settled] accepts.
Future<void> _until(
  ProviderContainer container,
  bool Function(SessionState session) settled,
) {
  final done = Completer<void>();
  final watch = container.listen(authControllerProvider, (_, next) {
    final session = next.value;
    if (session != null && settled(session) && !done.isCompleted) {
      done.complete();
    }
  }, fireImmediately: true);
  return done.future.whenComplete(watch.close);
}

/// The server says the account moved, and the client settles on the
/// session it then reads: [settled] says when.
Future<void> _accountMarker(
  _Client client,
  bool Function(SessionState session) settled,
) {
  final done = _until(client.container, settled);
  client.bus.add(const ServerSyncEvent(kind: 'account'));
  return done;
}

Future<void> _benSignsIn(_Client client) async {
  client.server.next = _ben;
  await client.container
      .read(authControllerProvider.notifier)
      .login(username: 'ben', password: 'pw');
  expect(client.container.read(signedInAccountProvider), _ben.id);
}

void main() {
  test('a session the server ends takes its queue and its station', () async {
    final client = _client();
    final container = client.container;
    await container.read(authControllerProvider.future);
    client.credentials.token = 'token-ann';
    container.read(queueControllerProvider.notifier)
      ..playNow(['tr-A', 'tr-B'], source: _album)
      ..setRepeat(QueueRepeat.all);
    await container.read(radioPlaybackProvider.notifier).play(_station);
    expect(client.engine.playing, isTrue);

    // An administrator disables Ann: the server sends the account marker
    // and her session no longer resolves.
    client.server.sessionState = const SessionState(authenticated: false);
    await _accountMarker(client, (session) => !session.authenticated);
    expect(client.credentials.token, isNull);

    await _benSignsIn(client);
    final queue = container.read(queueControllerProvider);
    expect(queue.isEmpty, isTrue);
    expect(queue.repeat, QueueRepeat.off);
    // The relay scrobbles a station for the account that tuned it.
    expect(container.read(radioPlaybackProvider).station, isNull);
    expect(client.engine.playing, isFalse);
  });

  test(
    'a play asked for while the account leaves does not outlive it',
    () async {
      final artwork = _HeldArtwork();
      final client = _client(artwork: artwork);
      final container = client.container;
      await container.read(authControllerProvider.future);

      // The server ends Ann's session, and the cleanup is held part way,
      // with her screens still up.
      client.server.sessionState = const SessionState(authenticated: false);
      final out = _accountMarker(client, (session) => !session.authenticated);
      await artwork.reached;
      container.read(queueControllerProvider.notifier).playNow([
        'tr-A',
      ], source: _album);
      await container.read(radioPlaybackProvider.notifier).play(_station);
      artwork.gate.complete();
      await out;

      await _benSignsIn(client);
      expect(container.read(queueControllerProvider).isEmpty, isTrue);
      expect(container.read(radioPlaybackProvider).station, isNull);
      expect(client.engine.playing, isFalse);

      // And the next account plays as it likes.
      container.read(queueControllerProvider.notifier).playNow([
        'tr-B',
      ], source: _album);
      expect(container.read(queueControllerProvider).currentPid, 'tr-B');
    },
  );

  test('a session the server ends takes its resume offer', () async {
    final client = _client(disk: _annsQueue());
    final container = client.container;
    await container.read(authControllerProvider.future);
    final offered = await _heldOffer(container);
    expect(offered?.queue.currentPid, 'tr-A');

    client.server.sessionState = const SessionState(authenticated: false);
    await _accountMarker(client, (session) => !session.authenticated);

    await _benSignsIn(client);
    expect(await client.disk.load(), isNull);
    expect(
      await container.read(queueRestoreProvider.future),
      isNull,
      reason: 'Ben is never asked whether to resume Ann\'s album',
    );
  });

  test('a session found to be another account\'s starts that account '
      'clean', () async {
    final client = _client(disk: _annsQueue());
    final container = client.container;
    await container.read(authControllerProvider.future);
    expect((await _heldOffer(container))?.queue.currentPid, 'tr-A');
    await container.read(radioPlaybackProvider.notifier).play(_station);

    // Another tab signed Ben in over this browser's cookie, so the
    // session read answers for him.
    client.server.sessionState = const SessionState(
      authenticated: true,
      user: _ben,
    );
    await _accountMarker(client, (session) => session.user?.id == _ben.id);

    expect(await client.disk.load(), isNull);
    expect(await container.read(queueRestoreProvider.future), isNull);
    expect(container.read(radioPlaybackProvider).station, isNull);
    expect(client.engine.playing, isFalse);
  });

  test('a launch whose stored session ended meanwhile leaves nothing of '
      'it', () async {
    // Ann's account was disabled while the app was closed: her token is
    // still on the device and her queue is still on the disk.
    final client = _client(
      session: const SessionState(authenticated: false),
      disk: _annsQueue(),
      storedToken: 'token-ann',
    );
    final container = client.container;
    final session = await container.read(authControllerProvider.future);
    expect(session.authenticated, isFalse);
    expect(client.credentials.token, isNull);

    await _benSignsIn(client);
    expect(await client.disk.load(), isNull);
    expect(await _heldOffer(container), isNull);
  });

  test('a session read the server refuses with a 401 signs out', () async {
    final client = _client(disk: _annsQueue());
    final container = client.container;
    await container.read(authControllerProvider.future);
    client.credentials.token = 'token-ann';

    client.server.sessionError = const WaxDeckApiException(
      code: 'unauthenticated',
      message: 'no valid session or token was presented',
      statusCode: 401,
    );
    await container.read(authControllerProvider.notifier).refreshSession();

    expect(container.read(authControllerProvider).value?.authenticated, false);
    expect(client.credentials.token, isNull);
    expect(await client.disk.load(), isNull);
  });

  test('a session read refused with a 401 in no words of the server\'s '
      'signs nobody out', () async {
    // A proxy's own sign-in in front of the server: its 401 is not the
    // server saying there is no session.
    final client = _client(disk: _annsQueue());
    final container = client.container;
    await container.read(authControllerProvider.future);
    client.credentials.token = 'token-ann';

    client.server.sessionError = const WaxDeckApiException(
      code: 'transport',
      message: 'Unauthorized',
      statusCode: 401,
    );
    final answer = await container
        .read(authControllerProvider.notifier)
        .refreshSession();

    expect(answer, SessionRecheck.unanswered);
    expect(container.read(signedInAccountProvider), _ann.id);
    expect(client.credentials.token, 'token-ann');
    expect(await client.disk.load(), isNotNull);
  });

  test('a token rotation refused with a 401 in no words of the server\'s '
      'signs nobody out', () async {
    final client = _client(storedToken: 'token-ann');
    client.server.refreshError = const WaxDeckApiException(
      code: 'transport',
      message: 'Unauthorized',
      statusCode: 401,
    );
    final container = client.container;

    await container.read(authControllerProvider.future);
    await pumpEventQueue();

    expect(container.read(signedInAccountProvider), _ann.id);
    expect(client.credentials.token, 'token-ann');
  });

  group('a session read for the same account', () {
    test('that says what the client holds is heard by nobody', () async {
      final client = _client();
      final container = client.container;
      await container.read(authControllerProvider.future);
      // What awaits the session, as the preferences do.
      final prefs = container.listen(prefsControllerProvider, (_, _) {});
      addTearDown(prefs.close);
      await container.read(prefsControllerProvider.future);
      var heard = 0;
      final session = container.listen(authControllerProvider, (_, _) {
        heard++;
      });
      addTearDown(session.close);
      final future = container.listen(authControllerProvider.future, (_, _) {
        heard++;
      });
      addTearDown(future.close);
      final reads = client.server.prefsReads;

      expect(
        await container.read(authControllerProvider.notifier).refreshSession(),
        SessionRecheck.stands,
      );
      await pumpEventQueue();

      expect(heard, 0);
      expect(client.server.prefsReads, reads, reason: 'nothing read again');
    });

    test('whose rights moved replaces the session held', () async {
      final client = _client();
      final container = client.container;
      await container.read(authControllerProvider.future);
      var heard = 0;
      final session = container.listen(authControllerProvider, (_, _) {
        heard++;
      });
      addTearDown(session.close);

      client.server.sessionState = SessionState(
        authenticated: true,
        user: WaxDeckUser(
          id: _ann.id,
          username: _ann.username,
          roles: const ['user', 'admin'],
        ),
      );
      await container.read(authControllerProvider.notifier).refreshSession();
      expect(heard, 1);
      expect(
        container.read(authControllerProvider).value?.user?.roles,
        contains('admin'),
      );

      client.server.sessionState = SessionState(
        authenticated: true,
        user: container.read(authControllerProvider).value?.user,
        serverReadOnly: true,
      );
      await container.read(authControllerProvider.notifier).refreshSession();
      expect(heard, 2);
      expect(container.read(serverReadOnlyProvider), isTrue);
    });
  });

  test(
    'a session read that cannot reach the server signs nobody out',
    () async {
      final client = _client(disk: _annsQueue());
      final container = client.container;
      await container.read(authControllerProvider.future);
      client.credentials.token = 'token-ann';

      for (final lost in const <WaxDeckApiException>[
        WaxDeckApiException(code: 'transport', message: 'connection refused'),
        WaxDeckApiException(
          code: 'transport',
          message: 'gateway',
          statusCode: 502,
        ),
        WaxDeckApiException(
          code: 'internal',
          message: 'restarting',
          statusCode: 503,
        ),
      ]) {
        client.server.sessionError = lost;
        await container.read(authControllerProvider.notifier).refreshSession();
        expect(
          container.read(signedInAccountProvider),
          _ann.id,
          reason: '$lost',
        );
      }
      expect(client.credentials.token, 'token-ann');
      expect(container.read(playbackHeldProvider), isFalse);
      expect(await client.disk.load(), isNotNull);
    },
  );

  group('a session read says what it made of the account it was asked for', () {
    Future<SessionRecheck> read(_Client client) =>
        client.container.read(authControllerProvider.notifier).refreshSession();

    test('the same account stands', () async {
      final client = _client();
      await client.container.read(authControllerProvider.future);

      expect(await read(client), SessionRecheck.stands);
    });

    test('a read that cannot reach the server is no answer', () async {
      final client = _client();
      await client.container.read(authControllerProvider.future);

      for (final lost in const <WaxDeckApiException>[
        WaxDeckApiException(code: 'transport', message: 'connection refused'),
        WaxDeckApiException(
          code: 'transport',
          message: 'gateway',
          statusCode: 502,
        ),
      ]) {
        client.server.sessionError = lost;
        expect(await read(client), SessionRecheck.unanswered, reason: '$lost');
      }
    });

    test(
      'no session, a 401, or another account is the account leaving',
      () async {
        for (final answer in <void Function(_Server)>[
          (server) =>
              server.sessionState = const SessionState(authenticated: false),
          (server) => server.sessionError = const WaxDeckApiException(
            code: 'unauthenticated',
            message: 'no valid session or token was presented',
            statusCode: 401,
          ),
          (server) => server.sessionState = const SessionState(
            authenticated: true,
            user: _ben,
          ),
        ]) {
          final client = _client();
          await client.container.read(authControllerProvider.future);
          answer(client.server);

          expect(await read(client), SessionRecheck.left);
          expect(
            client.container.read(signedInAccountProvider),
            isNot(_ann.id),
          );
        }
      },
    );

    test('a read the client moved on from says what it holds now', () async {
      final client = _client();
      final container = client.container;
      await container.read(authControllerProvider.future);

      // Held, while Ann signs out and back in.
      client.server.getSessionGate = Completer<void>();
      final again = read(client);
      await container.read(authControllerProvider.notifier).signOutLocally();
      client.server.next = _ann;
      await container
          .read(authControllerProvider.notifier)
          .login(username: 'ann', password: 'pw');
      client.server.getSessionGate!.complete();
      expect(await again, SessionRecheck.stands);

      // Held, while she signs out.
      client.server.getSessionGate = Completer<void>();
      final gone = read(client);
      await container.read(authControllerProvider.notifier).signOutLocally();
      client.server.getSessionGate!.complete();
      expect(await gone, SessionRecheck.left);
    });

    test('a read the client moved on from, of a session that names no user, '
        'says it stands while that session is held', () async {
      final client = _client(session: const SessionState(authenticated: true));
      final container = client.container;
      await container.read(authControllerProvider.future);

      // Held, while the controller is built again over the same session.
      final gate = client.server.getSessionGate = Completer<void>();
      final held = read(client);
      client.server.getSessionGate = null;
      container.invalidate(authControllerProvider);
      await container.read(authControllerProvider.future);
      gate.complete();

      expect(await held, SessionRecheck.stands);
    });

    test(
      'a read that lands while the account signs out says it left',
      () async {
        final artwork = _HeldArtwork();
        final client = _client(artwork: artwork);
        final container = client.container;
        await container.read(authControllerProvider.future);

        client.server.getSessionGate = Completer<void>();
        final held = read(client);
        final out = container
            .read(authControllerProvider.notifier)
            .signOutLocally();
        await artwork.reached;
        client.server.getSessionGate!.complete();

        expect(await held, SessionRecheck.left);
        artwork.gate.complete();
        await out;
      },
    );

    test('a read asked while the account signs out reads nothing, and says '
        'it left', () async {
      final artwork = _HeldArtwork();
      final client = _client(artwork: artwork);
      final container = client.container;
      await container.read(authControllerProvider.future);

      final out = container
          .read(authControllerProvider.notifier)
          .signOutLocally();
      await artwork.reached;
      final reads = client.server.sessionReads;

      expect(await read(client), SessionRecheck.left);
      expect(client.server.sessionReads, reads);
      artwork.gate.complete();
      await out;
    });

    test('a read that lands while another account takes its place says it '
        'left', () async {
      final artwork = _HeldArtwork();
      final client = _client(artwork: artwork);
      final container = client.container;
      await container.read(authControllerProvider.future);
      client.server.sessionState = const SessionState(
        authenticated: true,
        user: _ben,
      );

      // Two reads out: the first finds Ben and starts the swap, whose
      // cleanup is held; the second lands meanwhile.
      final first = client.server.getSessionGate = Completer<void>();
      final swap = read(client);
      final second = client.server.getSessionGate = Completer<void>();
      final stale = read(client);
      first.complete();
      await artwork.reached;
      second.complete();

      expect(await stale, SessionRecheck.left);
      artwork.gate.complete();
      expect(await swap, SessionRecheck.left);
      expect(container.read(signedInAccountProvider), _ben.id);
    });
  });

  test('a controller built again while a swap waits keeps its own '
      'answer', () async {
    final client = _client();
    final container = client.container;
    await container.read(authControllerProvider.future);
    // Signed-in screens are up, so a swap waits for them to go.
    final screens = container.listen(signedInScreensProvider, (_, _) {});

    client.server.sessionState = const SessionState(
      authenticated: true,
      user: _ben,
    );
    final swap = container
        .read(authControllerProvider.notifier)
        .refreshSession();
    await _until(container, (session) => !session.authenticated);

    // Built again meanwhile, as a new server address does, reading the
    // session afresh.
    client.server.sessionState = const SessionState(
      authenticated: true,
      user: _cid,
    );
    container.invalidate(authControllerProvider);
    await container.read(authControllerProvider.future);
    expect(container.read(signedInAccountProvider), _cid.id);

    screens.close();
    await swap;

    expect(
      container.read(signedInAccountProvider),
      _cid.id,
      reason: 'Ben\'s answer was asked of the build before',
    );
    expect(
      container.read(playbackHeldProvider),
      isFalse,
      reason: 'Cid arrived, so what Ann\'s leaving held is let go',
    );
  });

  group('a sign-out asked while one is under way', () {
    test('joins it: the cleanup runs once, and both finish', () async {
      final artwork = _HeldArtwork();
      final client = _client(artwork: artwork);
      final container = client.container;
      final auth = container.read(authControllerProvider.notifier);
      await container.read(authControllerProvider.future);

      // The server ended Ann's session, and her cleanup is held part way,
      // her screens still up: she taps sign out.
      client.server.sessionState = const SessionState(authenticated: false);
      var finished = 0;
      auth.refreshSession().then((_) => finished++).ignore();
      await artwork.reached;
      auth.logout().then((_) => finished++).ignore();
      await pumpEventQueue();

      artwork.gate.complete();
      await pumpEventQueue();
      expect(finished, 2);
      expect(artwork.wipes, 1);
      expect(client.disk.clears, 1);
      expect(_signedOut(container), isTrue);
    });

    test('that fails fails for each that joined it', () async {
      final keychain = _LockedKeychain();
      final client = _client(keychain: keychain);
      final container = client.container;
      final auth = container.read(authControllerProvider.notifier);
      await container.read(authControllerProvider.future);

      final first = auth.signOutLocally();
      final second = auth.signOutLocally();
      keychain.gate.complete();

      await expectLater(first, throwsStateError);
      await expectLater(second, throwsStateError);
      expect(keychain.clears, 1);
    });

    test('is over once it is: a sign-out after the next sign-in cleans up '
        'again', () async {
      final artwork = _HeldArtwork()..gate.complete();
      final client = _client(artwork: artwork);
      final container = client.container;
      final auth = container.read(authControllerProvider.notifier);
      await container.read(authControllerProvider.future);

      await auth.signOutLocally();
      await _benSignsIn(client);
      await auth.signOutLocally();

      expect(artwork.wipes, 2);
      expect(client.disk.clears, 2);
      expect(_signedOut(container), isTrue);
    });
  });
}

bool _signedOut(ProviderContainer container) =>
    container.read(authControllerProvider).value?.authenticated == false;
