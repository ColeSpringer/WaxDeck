import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_store.dart';
import 'package:waxdeck/src/auth/account_binder.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_persistence.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
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

  @override
  Future<LoginResult> login({
    required String username,
    required String password,
    String? deviceName,
  }) async {
    sessionState = SessionState(authenticated: true, user: next);
    return LoginResult(user: next, token: 'token-${next.username}');
  }
}

/// The device's queue store, holding what the last launch left.
class _Disk implements QueueStore {
  _Disk([this.saved]);

  StoredQueue? saved;

  @override
  Future<StoredQueue?> load() async => saved;

  @override
  Future<void> save(StoredQueue queue) async => saved = queue;

  @override
  Future<void> clear() async => saved = null;
}

/// Artwork whose wipe waits on [gate]: the cleanup is held there, after
/// the queue and the station went and before the session flips.
class _HeldArtwork extends FakeArtworkStore {
  final gate = Completer<void>();
  final _reached = Completer<void>();

  Future<void> get reached => _reached.future;

  @override
  Future<void> forgetEverything() async {
    if (!_reached.isCompleted) _reached.complete();
    await gate.future;
    await super.forgetEverything();
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
}) {
  final server = _Server(sessionState: session);
  final bus = ServerEventBus();
  final engine = FakeEngine();
  final store = _Disk(disk);
  final credentials = InMemoryCredentialStore()..token = storedToken;
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

/// The server says the account moved, and the client settles on the
/// session it then reads: [settled] says when.
Future<void> _accountMarker(
  _Client client,
  bool Function(SessionState session) settled,
) {
  final done = Completer<void>();
  final watch = client.container.listen(authControllerProvider, (_, next) {
    final session = next.value;
    if (session != null && settled(session) && !done.isCompleted) {
      done.complete();
    }
  });
  client.bus.add(const ServerSyncEvent(kind: 'account'));
  return done.future.whenComplete(watch.close);
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
}
