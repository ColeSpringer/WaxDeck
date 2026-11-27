import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/artwork/artwork_store.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/auth/login_screen.dart';
import 'package:waxdeck/src/auth/oidc_flow.dart';
import 'package:waxdeck/src/auth/setup_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_persistence.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';
import 'wax_finders.dart';

/// A session never shows while the screens of the account that left are
/// still up. A sign-in that lands inside a sign-out's transition waits for
/// them to go, by whichever road it comes; one that finds none up waits
/// for nothing.

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

const _anns = SessionState(authenticated: true, user: _ann);
const _bens = SessionState(authenticated: true, user: _ben);
const _nobody = SessionState(authenticated: false);

const _sso = OidcProvider(
  id: 'corp',
  displayName: 'Corp SSO',
  startUrl: 'http://server.test/api/v1/auth/oidc/start?provider=corp',
);

/// A server whose sign-ins, by whichever road, answer whoever [next]
/// names, with a token of their own.
class _Server extends FakeRepository {
  _Server({required super.sessionState}) : super(items: [testItem('tr-A')]) {
    browseLists[DiscoveryList.recentlyAdded] = [testItem('tr-A')];
  }

  WaxDeckUser next = _ben;

  /// Session reads fail, as with the server out of reach, while set.
  var down = false;
  var reads = 0;

  LoginResult _answer() {
    final token = 'token-${next.username}';
    final session = 'se-${next.username}';
    sessionState = SessionState(
      authenticated: true,
      user: next,
      sessionId: session,
    );
    authToken = token;
    return LoginResult(user: next, token: token, sessionId: session);
  }

  @override
  Future<LoginResult> login({
    required String username,
    required String password,
    String? deviceName,
  }) async => _answer();

  @override
  Future<LoginResult> bootstrap({
    required String username,
    required String password,
    String? displayName,
  }) async => _answer();

  @override
  Future<LoginResult> oidcExchange({
    required String code,
    String? verifier,
    String? deviceName,
  }) async => _answer();

  /// A session decoded afresh, as the real client's every read is.
  @override
  Future<SessionState> getSession() async {
    reads++;
    if (down) {
      throw const WaxDeckApiException(code: 'transport', message: 'down');
    }
    final read = await super.getSession();
    return SessionState.fromStored(read.toStored()) ?? _nobody;
  }

  /// A rotation answers for whoever holds the session.
  @override
  Future<LoginResult> refreshToken() async {
    refreshCalls++;
    final user = sessionState.user ?? next;
    final token = 'rotated-${user.username}';
    authToken = token;
    return LoginResult(
      user: user,
      token: token,
      sessionId: sessionState.sessionId ?? 'se-${user.username}',
    );
  }
}

/// A keychain that takes what it is asked one at a time and in order, as
/// the device's does; [hold] makes one kind of ask, and all behind it,
/// wait.
class _Keychain extends InMemoryCredentialStore {
  final asked = <String>[];
  final _holds = <String, Completer<void>>{};
  Future<void> _last = Future<void>.value();

  Completer<void> hold(String what) => _holds[what] = Completer<void>();

  Future<T> _inTurn<T>(String what, Future<T> Function() ask) {
    asked.add(what);
    final turn = _last.then((_) => _holds[what]?.future).then((_) => ask());
    _last = turn.then<void>((_) {});
    return turn;
  }

  @override
  Future<String?> readToken() => _inTurn('readToken', super.readToken);

  @override
  Future<void> writeToken(String value) =>
      _inTurn('writeToken', () => super.writeToken(value));

  @override
  Future<void> clearToken() => _inTurn('clearToken', super.clearToken);

  @override
  Future<String?> readSession() => _inTurn('readSession', super.readSession);

  @override
  Future<void> writeSession(String value) =>
      _inTurn('writeSession', () => super.writeSession(value));

  @override
  Future<void> clearSession() => _inTurn('clearSession', super.clearSession);
}

/// A keychain that says when a session has been written.
class _Told extends InMemoryCredentialStore {
  void Function()? onSessionWritten;

  @override
  Future<void> writeSession(String value) async {
    await super.writeSession(value);
    onSessionWritten?.call();
  }
}

/// Artwork whose wipe waits on [gate]: an account's leaving is held
/// there, its session still showing.
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

/// A browser that comes straight back with the one-time code.
class _Browser implements UrlOpenerPort, DeepLinkPort {
  final _links = StreamController<Uri>.broadcast();

  @override
  Future<void> open(String url) async =>
      _links.add(Uri.parse('waxdeck://auth?code=one-time'));

  @override
  Stream<Uri> get uriLinkStream => _links.stream;
}

/// Each road by which the controller adopts a session a person asked for.
final _roads = <String, Future<void> Function(AuthController auth)>{
  'the sign-in form': (auth) => auth.login(username: 'ben', password: 'pw'),
  'a first-run setup': (auth) =>
      auth.bootstrap(username: 'ben', password: 'pw'),
  'a single sign-on return': (auth) => auth.loginWithOidc(_sso),
};

typedef _Client = ({
  ProviderContainer container,
  _Server server,
  InMemoryCredentialStore store,
});

/// A client with no router: the test says when signed-in screens are up.
_Client _client({
  SessionState session = _anns,
  InMemoryCredentialStore? keychain,
  ArtworkStore? artwork,
}) {
  final server = _Server(sessionState: session);
  final store = keychain ?? InMemoryCredentialStore();
  final browser = _Browser();
  final container = appContainer(
    repo: server,
    credentials: store,
    artwork: artwork,
    settings: MemoryClientSettingsStore(),
    extra: [
      urlOpenerProvider.overrideWithValue(browser),
      deepLinkProvider.overrideWithValue(browser),
      queueSaveDebounceProvider.overrideWithValue(Duration.zero),
    ],
  );
  return (container: container, server: server, store: store);
}

AuthController _auth(ProviderContainer container) =>
    container.read(authControllerProvider.notifier);

/// Whose session the client holds: a name, or `out`.
String _session(ProviderContainer container) =>
    container.read(authControllerProvider).value?.user?.username ?? 'out';

/// Every session the client goes on to show, as [_session] names them.
List<String> _shown(ProviderContainer container) {
  final shown = <String>[];
  final watch = container.listen(
    authControllerProvider,
    (_, next) => shown.add(next.value?.user?.username ?? 'out'),
  );
  addTearDown(watch.close);
  return shown;
}

/// Who the device would open as at a start out of the server's reach.
String? _remembered(InMemoryCredentialStore store) {
  final token = store.token;
  final record = store.session;
  if (token == null || record == null) return null;
  final text = rememberedFor(token, record);
  return text == null ? null : SessionState.fromStored(text)?.user?.username;
}

/// Ann's client just after she signed out, her screens still up: closing
/// what this answers takes them down.
Future<(_Client, ProviderSubscription<SignedInScreens>)> _annLeft() async {
  final client = _client();
  final container = client.container;
  await container.read(authControllerProvider.future);
  client.server.authToken = 'token-ann';
  client.store
    ..token = 'token-ann'
    ..session = rememberedRecord('token-ann', _anns.toStored());
  final screens = container.listen(signedInScreensProvider, (_, _) {});
  await _auth(container).signOutLocally();
  expect(_session(container), 'out');
  expect(container.read(playbackHeldProvider), isTrue);
  return (client, screens);
}

/// Ben's token and the session kept for it on the device, as a sign-in of
/// his that got no further left them, and the server answering for him.
void _bensTokenStored(_Client client) {
  client.server.sessionState = _bens;
  client.store
    ..token = 'token-ben'
    ..session = rememberedRecord('token-ben', _bens.toStored());
}

/// The controller built again, as Riverpod does after a build that failed
/// and as a new server address does: what its build answers.
Future<SessionState> _builtAgain(ProviderContainer container) {
  container.invalidate(authControllerProvider);
  return container.read(authControllerProvider.future);
}

/// The network under the engine's socket: each connect waits, unanswered.
class _Net {
  final attempts = <_Attempt>[];

  EventsChannelFactory get factory =>
      ({required onFrame, required onDone, required subscribe}) {
        final attempt = _Attempt(
          onFrame: onFrame,
          onDone: onDone,
          subscribe: subscribe,
        );
        attempts.add(attempt);
        return attempt;
      };
}

class _Attempt extends EventsChannel {
  _Attempt({
    required super.onFrame,
    required super.onDone,
    required super.subscribe,
  }) : super(url: 'ws://held', authToken: null);

  final _answer = Completer<void>();

  @override
  Future<void> connect() => _answer.future;

  @override
  bool send(String frame) => false;

  @override
  Future<void> close() async {}
}

typedef _Device = ({
  ProviderContainer container,
  _Server server,
  SyncEngine engine,
  _Net net,
});

/// A device over a real sync engine, for the whole app: at a cold start
/// with Ann's token stored, or with nobody's.
_Device _device({bool signedIn = true}) {
  final db = inMemoryMirrorDatabase();
  addTearDown(db.close);
  final downloads = FakeDownloads();
  addTearDown(downloads.dispose);
  final server = _Server(sessionState: signedIn ? _anns : _nobody);
  final net = _Net();
  final engine = SyncEngine(
    db: db,
    repository: server,
    channelFactory: net.factory,
  );
  addTearDown(engine.dispose);
  final store = InMemoryCredentialStore();
  if (signedIn) {
    store
      ..token = 'token-ann'
      ..session = rememberedRecord('token-ann', _anns.toStored());
  }
  final browser = _Browser();
  final container = appContainer(
    repo: server,
    engine: FakeEngine(mediaDuration: const Duration(minutes: 3)),
    credentials: store,
    sync: engine,
    mirror: db,
    downloads: downloads,
    settings: MemoryClientSettingsStore(),
    extra: [
      urlOpenerProvider.overrideWithValue(browser),
      deepLinkProvider.overrideWithValue(browser),
      queueSaveDebounceProvider.overrideWithValue(Duration.zero),
    ],
  );
  return (container: container, server: server, engine: engine, net: net);
}

final _home = find.bySemanticsIdentifier(SemanticsIds.homeScreen);
final _signIn = find.bySemanticsIdentifier(SemanticsIds.loginSubmit);

/// One frame of the whole app. Every pump here is timed: a bare `pump()`
/// draws a frame, and flushes what waits on one, only when a frame is
/// already scheduled.
const _frame = Duration(milliseconds: 50);

/// Frames until [found] is drawn, [each] run after every one; answers how
/// many it took.
Future<int> _until(
  WidgetTester tester,
  Finder found, {
  void Function()? each,
}) async {
  for (var frame = 0; frame < 200; frame++) {
    if (found.evaluate().isNotEmpty) return frame;
    await tester.pump(_frame);
    each?.call();
  }
  fail('never drawn: $found');
}

/// Frames until [work] is done, [each] run after every one.
Future<void> _through(
  WidgetTester tester,
  Future<void> work, {
  void Function()? each,
}) async {
  var done = false;
  unawaited(work.whenComplete(() => done = true));
  for (var frame = 0; frame < 200 && !done; frame++) {
    await tester.pump(_frame);
    each?.call();
  }
  expect(done, isTrue, reason: 'still out after 200 frames');
  await work;
}

/// Lets microtasks run and nothing else. In a widget test no frame is
/// drawn and no timer fires until a pump, and `tester.idle` would fire the
/// zero ones.
Future<void> _microtasks() async {
  for (var turn = 0; turn < 200; turn++) {
    await null;
  }
}

void main() {
  group('a sign-in while the screens of the account that left are still '
      'up', () {
    for (final MapEntry(key: road, value: signIn) in _roads.entries) {
      test('by $road shows nothing until they are gone, then its '
          'session', () async {
        final (client, screens) = await _annLeft();
        final container = client.container;
        final shown = _shown(container);

        var landed = false;
        final arriving = signIn(_auth(container))
            .whenComplete(() => landed = true);
        await pumpEventQueue();
        expect(landed, isFalse);
        expect(shown, isEmpty);
        expect(_session(container), 'out');

        screens.close();
        await arriving;
        expect(shown, isNotEmpty);
        expect(shown, everyElement('ben'));
        expect(client.server.authToken, 'token-ben');
        expect(client.store.token, 'token-ben');
        expect(_remembered(client.store), 'ben');
      });
    }

    test('leaves what that account\'s leaving held as it is until they are '
        'gone', () async {
      final (client, screens) = await _annLeft();
      final container = client.container;

      final arriving = _auth(container).login(username: 'ben', password: 'pw');
      await pumpEventQueue();
      expect(container.read(playbackHeldProvider), isTrue);

      screens.close();
      await arriving;
      expect(container.read(playbackHeldProvider), isFalse);
    });

    test('and overtaken by another account\'s sign-in shows nothing, and '
        'that account has its token and its session', () async {
      final (client, screens) = await _annLeft();
      final container = client.container;
      final shown = _shown(container);

      final first = _auth(container).login(username: 'ben', password: 'pw');
      await pumpEventQueue();
      client.server.next = _cid;
      final second = _auth(container).login(username: 'cid', password: 'pw');
      await pumpEventQueue();
      expect(shown, isEmpty);

      screens.close();
      await first;
      await second;
      await pumpEventQueue();
      expect(shown, isNotEmpty);
      expect(shown, everyElement('cid'));
      expect(client.server.authToken, 'token-cid');
      expect(client.store.token, 'token-cid');
      expect(_remembered(client.store), 'cid');
      expect(container.read(playbackHeldProvider), isFalse);
    });

    test('and overtaken by a sign-out shows nothing, and nothing of it is '
        'left', () async {
      final (client, screens) = await _annLeft();
      final container = client.container;
      final shown = _shown(container);

      final arriving = _auth(container).login(username: 'ben', password: 'pw');
      await pumpEventQueue();
      expect(client.store.token, 'token-ben');
      await _auth(container).logout();

      screens.close();
      await arriving;
      await pumpEventQueue();
      expect(shown, isNot(contains('ben')));
      expect(_session(container), 'out');
      expect(client.server.authToken, isNull);
      expect(client.store.token, isNull);
      expect(client.store.session, isNull);
      expect(container.read(playbackHeldProvider), isTrue);
    });

    test('whose client is closed while it waits shows nothing and throws '
        'nothing, and its token is kept whole for the next start', () async {
      final (client, _) = await _annLeft();
      final container = client.container;
      final shown = _shown(container);

      final arriving = _auth(container).login(username: 'ben', password: 'pw');
      await pumpEventQueue();
      container.dispose();

      await arriving;
      await pumpEventQueue();
      expect(shown, isEmpty);
      expect(client.store.token, 'token-ben');
      expect(_remembered(client.store), 'ben');
    });

    test('is shown once, with its token kept, when a session read asked '
        'while it waits finds its account first', () async {
      final (client, screens) = await _annLeft();
      final container = client.container;
      final shown = _shown(container);

      final arriving = _auth(container).login(username: 'ben', password: 'pw');
      await pumpEventQueue();
      final read = _auth(container).refreshSession();
      await pumpEventQueue();
      expect(shown, isNot(contains('ben')));
      expect(_session(container), 'out');

      screens.close();
      expect(await read, SessionRecheck.left);
      await arriving;
      await pumpEventQueue();
      expect(shown.where((who) => who == 'ben'), hasLength(1));
      expect(client.store.token, 'token-ben');
      expect(_remembered(client.store), 'ben');
      expect(container.read(playbackHeldProvider), isFalse);
    });
  });

  group('a build that restores a session while the screens of the account '
      'that left are still up', () {
    test('shows nothing until they are gone, then its session', () async {
      final (client, screens) = await _annLeft();
      final container = client.container;
      _bensTokenStored(client);
      final shown = _shown(container);

      var built = false;
      final building = _builtAgain(container).whenComplete(() => built = true);
      await pumpEventQueue();
      expect(built, isFalse);
      expect(shown, isNot(contains('ben')));
      expect(_session(container), 'out');
      expect(container.read(playbackHeldProvider), isTrue);

      screens.close();
      expect((await building).user?.username, 'ben');
      expect(_session(container), 'ben');
      expect(container.read(playbackHeldProvider), isFalse);
    });

    test('opening on what the device remembers, the server out of reach, '
        'waits for them too', () async {
      final (client, screens) = await _annLeft();
      final container = client.container;
      _bensTokenStored(client);
      client.server.down = true;
      final shown = _shown(container);

      var built = false;
      final building = _builtAgain(container).whenComplete(() => built = true);
      await pumpEventQueue();
      expect(built, isFalse);
      expect(shown, isNot(contains('ben')));
      expect(_auth(container).unconfirmed, isFalse);

      screens.close();
      expect((await building).user?.username, 'ben');
      expect(_auth(container).unconfirmed, isTrue);
      expect(container.read(playbackHeldProvider), isFalse);
    });

    test('takes the place of a sign-in waiting for them: one session '
        'shows, once they are gone, and the sign-in returns', () async {
      final (client, screens) = await _annLeft();
      final container = client.container;
      final shown = _shown(container);

      bool? took;
      final arriving = _auth(container)
          .login(username: 'ben', password: 'pw')
          .then((answer) => took = answer);
      await pumpEventQueue();
      final building = _builtAgain(container);
      await pumpEventQueue();
      expect(shown, isNot(contains('ben')));
      expect(took, isNull);

      screens.close();
      await arriving;
      expect((await building).user?.username, 'ben');
      await pumpEventQueue();
      expect(took, isFalse);
      expect(shown.where((who) => who == 'ben'), hasLength(1));
      expect(client.store.token, client.server.authToken);
      expect(_remembered(client.store), 'ben');
      expect(container.read(playbackHeldProvider), isFalse);
    });

    test('is overtaken by a sign-in that comes to wait behind it: that '
        'account\'s session is the one left showing', () async {
      final (client, screens) = await _annLeft();
      final container = client.container;
      _bensTokenStored(client);
      final shown = _shown(container);

      final building = _builtAgain(container);
      await pumpEventQueue();
      client.server.next = _cid;
      bool? took;
      final arriving = _auth(container)
          .login(username: 'cid', password: 'pw')
          .then((answer) => took = answer);
      await pumpEventQueue();
      expect(shown, isNot(anyOf(contains('ben'), contains('cid'))));

      screens.close();
      await building;
      await arriving;
      await pumpEventQueue();
      expect(took, isTrue);
      expect(shown, isNot(contains('ben')));
      expect(_session(container), 'cid');
      expect(client.server.authToken, 'token-cid');
      expect(client.store.token, 'token-cid');
      expect(_remembered(client.store), 'cid');
    });
  });

  group('a sign-in overtaken while its token is being stored, no screens '
      'up', () {
    for (final write in ['writeToken', 'writeSession']) {
      test('by a sign-out, at $write, shows nothing and leaves '
          'nothing', () async {
        final keychain = _Keychain();
        final client = _client(session: _nobody, keychain: keychain);
        final container = client.container;
        await container.read(authControllerProvider.future);
        final shown = _shown(container);

        final held = keychain.hold(write);
        bool? took;
        final arriving = _auth(container)
            .login(username: 'ben', password: 'pw')
            .then((answer) => took = answer);
        await pumpEventQueue();
        final leaving = _auth(container).signOutLocally();
        held.complete();

        await arriving;
        await leaving;
        await pumpEventQueue();
        expect(took, isFalse);
        expect(shown, isNot(contains('ben')));
        expect(_session(container), 'out');
        expect(client.server.authToken, isNull);
        expect(keychain.token, isNull);
        expect(keychain.session, isNull);
        expect(keychain.asked.last, 'clearToken');
      });
    }

    test('by a new build shows nothing itself: the build restores its '
        'token and shows its session once', () async {
      final keychain = _Keychain();
      final client = _client(session: _nobody, keychain: keychain);
      final container = client.container;
      await container.read(authControllerProvider.future);
      final shown = _shown(container);

      final held = keychain.hold('writeToken');
      bool? took;
      final arriving = _auth(container)
          .login(username: 'ben', password: 'pw')
          .then((answer) => took = answer);
      await pumpEventQueue();
      final building = _builtAgain(container);
      await pumpEventQueue();
      expect(shown, isNot(contains('ben')));
      held.complete();

      await arriving;
      expect(took, isFalse);
      expect(shown, isNot(contains('ben')));
      expect((await building).user?.username, 'ben');
      await pumpEventQueue();
      expect(shown.where((who) => who == 'ben'), hasLength(1));
      expect(keychain.token, client.server.authToken);
      expect(_remembered(keychain), 'ben');
    });

    for (final write in ['writeToken', 'writeSession']) {
      test('whose client is closed at $write throws nothing', () async {
        final keychain = _Keychain();
        final client = _client(session: _nobody, keychain: keychain);
        final container = client.container;
        await container.read(authControllerProvider.future);

        final held = keychain.hold(write);
        final arriving = _auth(container)
            .login(username: 'ben', password: 'pw');
        await pumpEventQueue();
        container.dispose();
        held.complete();

        expect(await arriving, isFalse);
      });
    }
  });

  group('a sign-in that arrives while an account is on its way out', () {
    test('waits for the sign-out to end, and is not signed out by '
        'it', () async {
      final artwork = _HeldArtwork();
      final client = _client(artwork: artwork);
      final container = client.container;
      await container.read(authControllerProvider.future);
      final shown = _shown(container);

      // Ann's sign-out, held part way: her session still shows.
      final leaving = _auth(container).signOutLocally();
      await artwork.reached;
      bool? took;
      final arriving = _auth(container)
          .login(username: 'ben', password: 'pw')
          .then((answer) => took = answer);
      await pumpEventQueue();
      final meanwhile = [...shown];

      artwork.gate.complete();
      await leaving;
      await arriving;
      await pumpEventQueue();
      // Signed in, with its token: the sign-out ended Ann's session only.
      expect(_session(container), 'ben');
      expect(took, isTrue);
      expect(client.server.authToken, 'token-ben');
      expect(client.store.token, 'token-ben');
      expect(_remembered(client.store), 'ben');
      expect(container.read(playbackHeldProvider), isFalse);
      // And not shown before it had.
      expect(meanwhile, isEmpty);
      expect(shown, ['out', 'ben']);
      expect(artwork.wipes, 1);
    });

    test('waits for the sign-out, then for the screens it takes '
        'down', () async {
      final artwork = _HeldArtwork();
      final client = _client(artwork: artwork);
      final container = client.container;
      await container.read(authControllerProvider.future);
      final screens = container.listen(signedInScreensProvider, (_, _) {});
      final shown = _shown(container);

      final leaving = _auth(container).signOutLocally();
      await artwork.reached;
      final arriving = _auth(container).login(username: 'ben', password: 'pw');
      await pumpEventQueue();
      expect(shown, isEmpty);

      artwork.gate.complete();
      await leaving;
      await pumpEventQueue();
      expect(shown, ['out']);
      expect(container.read(playbackHeldProvider), isTrue);

      screens.close();
      await arriving;
      expect(shown, ['out', 'ben']);
      expect(client.store.token, 'token-ben');
    });

    test('as the same account waits for it too, and shows on fresh '
        'screens', () async {
      final artwork = _HeldArtwork();
      final client = _client(artwork: artwork);
      final container = client.container;
      await container.read(authControllerProvider.future);
      final screens = container.listen(signedInScreensProvider, (_, _) {});
      final shown = _shown(container);

      final leaving = _auth(container).signOutLocally();
      await artwork.reached;
      client.server.next = _ann;
      final arriving = _auth(container).login(username: 'ann', password: 'pw');
      await pumpEventQueue();
      artwork.gate.complete();
      await leaving;
      await pumpEventQueue();
      expect(shown, ['out']);

      screens.close();
      await arriving;
      expect(shown, ['out', 'ann']);
      expect(client.store.token, 'token-ann');
    });

    test('and is overtaken while it waits shows nothing and sees nobody '
        'out: the sign-in that came after is the one shown', () async {
      final artwork = _HeldArtwork();
      final client = _client(artwork: artwork);
      final container = client.container;
      await container.read(authControllerProvider.future);
      final shown = _shown(container);

      final leaving = _auth(container).signOutLocally();
      await artwork.reached;
      bool? took;
      final first = _auth(container)
          .login(username: 'ben', password: 'pw')
          .then((answer) => took = answer);
      await pumpEventQueue();
      client.server.next = _cid;
      final second = _auth(container).login(username: 'cid', password: 'pw');
      await pumpEventQueue();
      expect(shown, isEmpty);

      artwork.gate.complete();
      await leaving;
      await first;
      expect(await second, isTrue);
      await pumpEventQueue();
      expect(took, isFalse);
      expect(shown, ['out', 'cid']);
      expect(artwork.wipes, 1);
      expect(client.store.token, 'token-cid');
      expect(_remembered(client.store), 'cid');
    });

    test('by a build, overtaken while it waits: the build answers the '
        'session held, and rotates and keeps nothing', () async {
      final artwork = _HeldArtwork();
      final client = _client(artwork: artwork);
      final container = client.container;
      await container.read(authControllerProvider.future);
      final shown = _shown(container);

      final leaving = _auth(container).signOutLocally();
      await artwork.reached;
      _bensTokenStored(client);
      final building = _builtAgain(container);
      await pumpEventQueue();
      client.server.next = _cid;
      final arriving = _auth(container).login(username: 'cid', password: 'pw');
      await pumpEventQueue();
      expect(shown, isNot(anyOf(contains('ben'), contains('cid'))));

      artwork.gate.complete();
      await leaving;
      expect(await arriving, isTrue);
      expect((await building).user?.username, isNot('ben'));
      await pumpEventQueue();
      expect(shown, isNot(contains('ben')));
      expect(_session(container), 'cid');
      expect(client.server.refreshCalls, 0);
      expect(client.store.token, 'token-cid');
      expect(_remembered(client.store), 'cid');
    });
  });

  group('a session arriving where another account\'s shows', () {
    test('by a sign-in sees that account out first: what it left goes, '
        'then its session, then its screens', () async {
      final artwork = _HeldArtwork()..gate.complete();
      final client = _client(artwork: artwork);
      final container = client.container;
      await container.read(authControllerProvider.future);
      final screens = container.listen(signedInScreensProvider, (_, _) {});
      final shown = _shown(container);

      bool? took;
      final arriving = _auth(container)
          .login(username: 'ben', password: 'pw')
          .then((answer) => took = answer);
      await pumpEventQueue();
      expect(shown, ['out']);
      expect(artwork.wipes, 1);
      expect(container.read(playbackHeldProvider), isTrue);
      expect(client.store.token, 'token-ben');

      screens.close();
      await arriving;
      expect(took, isTrue);
      expect(shown, ['out', 'ben']);
      expect(_remembered(client.store), 'ben');
      expect(container.read(playbackHeldProvider), isFalse);
    });

    test('by a sign-in reads nothing for the account on its way '
        'out', () async {
      final artwork = _HeldArtwork();
      final client = _client(artwork: artwork);
      final container = client.container;
      await container.read(authControllerProvider.future);

      final arriving = _auth(container).login(username: 'ben', password: 'pw');
      await pumpEventQueue();
      expect(artwork.wipes, 1);
      final reads = client.server.reads;
      expect(await _auth(container).refreshSession(), SessionRecheck.left);
      expect(client.server.reads, reads);

      artwork.gate.complete();
      await arriving;
      expect(_session(container), 'ben');
    });

    test('by a sign-in that finds a build fell due sees nobody out itself: '
        'the build goes on, and sees that account out once, as a swap '
        'does', () async {
      final artwork = _HeldArtwork()..gate.complete();
      final keychain = _Told();
      final client = _client(artwork: artwork, keychain: keychain);
      final container = client.container;
      await container.read(authControllerProvider.future);

      // Due as the sign-in's last write lands and not yet run, as a retry
      // timer that fired since the last frame leaves one.
      keychain.onSessionWritten = () {
        keychain.onSessionWritten = null;
        container.invalidate(authControllerProvider);
      };
      final took = await _auth(container)
          .login(username: 'ben', password: 'pw');
      expect(took, isFalse);

      await pumpEventQueue();
      expect(artwork.wipes, 1);
      expect(_session(container), 'ben');
    });

    test('by a build, no signed-in screens up, is handed to a session read '
        'too: the build answers the session held, and that account is seen '
        'out as a swap sees it out before the other shows', () async {
      final artwork = _HeldArtwork()..gate.complete();
      final client = _client(artwork: artwork);
      final container = client.container;
      await container.read(authControllerProvider.future);
      final shown = _shown(container);

      // The session held turns out to be Ben's, as a browser's cookie can.
      client.server.sessionState = _bens;
      expect((await _builtAgain(container)).user?.username, 'ann');
      await pumpEventQueue();
      expect(shown, containsAllInOrder(['out', 'ben']));
      expect(_session(container), 'ben');
      expect(artwork.wipes, 1);
    });

    test('by a build, that account\'s screens still up, is handed to a '
        'session read: the build answers the session held, the account is '
        'seen out as a swap sees it out, and the other shows once its '
        'screens are gone', () async {
      final artwork = _HeldArtwork()..gate.complete();
      final client = _client(artwork: artwork);
      final container = client.container;
      await container.read(authControllerProvider.future);
      final screens = container.listen(signedInScreensProvider, (_, _) {});
      final shown = _shown(container);

      // The session held turns out to be Ben's, as a browser's cookie can.
      client.server.sessionState = _bens;
      expect((await _builtAgain(container)).user?.username, 'ann');
      expect(client.server.refreshCalls, 0);
      await pumpEventQueue();
      expect(artwork.wipes, 1);
      expect(_session(container), 'out');
      expect(shown, isNot(contains('ben')));
      expect(container.read(playbackHeldProvider), isTrue);

      screens.close();
      await pumpEventQueue();
      expect(_session(container), 'ben');
      expect(shown.last, 'ben');
      expect(shown.where((who) => who == 'ben'), hasLength(1));
      expect(container.read(playbackHeldProvider), isFalse);
    });

    test('by a sign-in overtaken while what that account left goes takes '
        'no session down: here by her own sign-in, whose screens are '
        'staying', () async {
      final artwork = _HeldArtwork();
      final client = _client(artwork: artwork);
      final container = client.container;
      await container.read(authControllerProvider.future);
      final screens = container.listen(signedInScreensProvider, (_, _) {});
      addTearDown(screens.close);
      final shown = _shown(container);

      bool? took;
      final first = _auth(container)
          .login(username: 'ben', password: 'pw')
          .then((answer) => took = answer);
      await artwork.reached;
      client.server.next = _ann;
      final second = _auth(container).login(username: 'ann', password: 'pw');
      await pumpEventQueue();
      expect(shown, isEmpty);

      artwork.gate.complete();
      await pumpEventQueue();
      expect(shown, isNot(anyOf(contains('out'), contains('ben'))));
      await first;
      expect(await second, isTrue);
      expect(took, isFalse);
      expect(_session(container), 'ann');
      expect(client.store.token, 'token-ann');
      expect(_remembered(client.store), 'ann');
      expect(container.read(playbackHeldProvider), isFalse);
    });

    test('by a sign-in overtaken while it waits for that account\'s '
        'screens shows nothing: the sign-in that came after is the one '
        'shown', () async {
      final artwork = _HeldArtwork()..gate.complete();
      final client = _client(artwork: artwork);
      final container = client.container;
      await container.read(authControllerProvider.future);
      final screens = container.listen(signedInScreensProvider, (_, _) {});
      final shown = _shown(container);

      bool? took;
      final first = _auth(container)
          .login(username: 'ben', password: 'pw')
          .then((answer) => took = answer);
      await pumpEventQueue();
      expect(shown, ['out']);
      client.server.next = _cid;
      final second = _auth(container).login(username: 'cid', password: 'pw');
      await pumpEventQueue();
      expect(shown, ['out']);

      screens.close();
      await first;
      expect(await second, isTrue);
      await pumpEventQueue();
      expect(took, isFalse);
      expect(shown, ['out', 'cid']);
      expect(artwork.wipes, 1);
      expect(client.store.token, 'token-cid');
      expect(_remembered(client.store), 'cid');
    });
  });

  group('another account\'s session found by a read, overtaken while it '
      'waits for the screens', () {
    /// Ann's client, a session read having found Ben in her place: her
    /// session is taken down and his waits for her screens.
    Future<(_Client, ProviderSubscription<SignedInScreens>, Future<void>)>
    bensWaits() async {
      final client = _client();
      final container = client.container;
      await container.read(authControllerProvider.future);
      final screens = container.listen(signedInScreensProvider, (_, _) {});
      client.server.sessionState = _bens;
      final found = _auth(container).refreshSession();
      await pumpEventQueue();
      expect(_session(container), 'out');
      return (client, screens, found);
    }

    test('by a build, shows nothing of its own once they are gone', () async {
      final (client, screens, found) = await bensWaits();
      final container = client.container;
      final shown = _shown(container);

      client.server.sessionState = const SessionState(
        authenticated: true,
        user: _cid,
      );
      final building = _builtAgain(container);
      await pumpEventQueue();

      screens.close();
      await found;
      expect((await building).user?.username, 'cid');
      expect(shown, isNot(contains('ben')));
      expect(_session(container), 'cid');
    });

    test('by a sign-in, shows nothing of its own once they are '
        'gone', () async {
      final (client, screens, found) = await bensWaits();
      final container = client.container;
      final shown = _shown(container);

      client.server.next = _cid;
      final arriving = _auth(container).login(username: 'cid', password: 'pw');
      await pumpEventQueue();
      expect(shown, isEmpty);

      screens.close();
      await found;
      expect(await arriving, isTrue);
      expect(shown, ['cid']);
    });
  });

  group('a form whose sign-in was overtaken while it waited', () {
    /// What overtakes it: a sign-out, which leaves nobody signed in.
    Future<void> overtaken(WidgetTester tester, _Client client) async {
      expect(_session(client.container), 'out');
      await _through(tester, _auth(client.container).signOutLocally());
    }

    testWidgets('on the sign-in form: it is no longer busy', (tester) async {
      final client = _client(session: _nobody);
      final container = client.container;
      await mountApp(tester, const LoginScreen(), container: container);
      await tester.pump(_frame);
      final screens = container.listen(signedInScreensProvider, (_, _) {});
      WaxButton button() => tester.widget<WaxButton>(
        waxControl<WaxButton>(SemanticsIds.loginSubmit),
      );

      await tester.enterText(
        find.bySemanticsIdentifier(SemanticsIds.loginUsername),
        'ben',
      );
      await tester.enterText(
        find.bySemanticsIdentifier(SemanticsIds.loginPassword),
        'pw',
      );
      await tester.tap(_signIn);
      await tester.pump(_frame);
      expect(button().busy, isTrue);

      await overtaken(tester, client);
      screens.close();
      await tester.pump(_frame);
      await tester.pump(_frame);

      expect(_session(container), 'out');
      expect(button().busy, isFalse);
      expect(button().onPressed, isNotNull);
    });

    testWidgets('on the sign-in form: it says nothing went wrong, and '
        'keeps what was typed', (tester) async {
      final client = _client(session: _nobody);
      final container = client.container;
      await mountApp(tester, const LoginScreen(), container: container);
      await tester.pump(_frame);
      final screens = container.listen(signedInScreensProvider, (_, _) {});

      await tester.enterText(
        find.bySemanticsIdentifier(SemanticsIds.loginUsername),
        'ben',
      );
      await tester.enterText(
        find.bySemanticsIdentifier(SemanticsIds.loginPassword),
        'pw',
      );
      await tester.tap(_signIn);
      await tester.pump(_frame);

      await overtaken(tester, client);
      screens.close();
      await tester.pump(_frame);
      await tester.pump(_frame);

      expect(_session(container), 'out');
      expect(find.bySemanticsIdentifier(SemanticsIds.loginError), findsNothing);
      expect(find.widgetWithText(WaxTextField, 'ben'), findsOneWidget);
    });

    testWidgets('by single sign-on, on the sign-in form: it is no longer '
        'busy', (tester) async {
      final client = _client(session: _nobody);
      client.server.ssoProviders.add(_sso);
      final container = client.container;
      await mountApp(tester, const LoginScreen(), container: container);
      await tester.pump(_frame);
      final screens = container.listen(signedInScreensProvider, (_, _) {});
      final singleSignOn = find.bySemanticsIdentifier(
        SemanticsIds.oidcLogin(_sso.id),
      );
      WaxButton button() => tester.widget<WaxButton>(
        find.ancestor(of: singleSignOn, matching: find.byType(WaxButton)),
      );

      await tester.tap(singleSignOn);
      await tester.pump(_frame);
      expect(button().onPressed, isNull);

      await overtaken(tester, client);
      screens.close();
      await tester.pump(_frame);
      await tester.pump(_frame);

      expect(_session(container), 'out');
      expect(button().onPressed, isNotNull);
    });

    testWidgets('on the setup form: it is no longer busy', (tester) async {
      final client = _client(session: _nobody);
      final container = client.container;
      await mountApp(tester, const SetupScreen(), container: container);
      await tester.pump(_frame);
      final screens = container.listen(signedInScreensProvider, (_, _) {});
      WaxButton button() => tester.widget<WaxButton>(
        waxControl<WaxButton>(SemanticsIds.setupSubmit),
      );

      await tester.enterText(
        find.bySemanticsIdentifier(SemanticsIds.setupUsername),
        'ben',
      );
      for (final field in [
        SemanticsIds.setupPassword,
        SemanticsIds.setupConfirm,
      ]) {
        await tester.enterText(
          find.bySemanticsIdentifier(field),
          'wax-setup-pass',
        );
      }
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.setupSubmit));
      await tester.pump(_frame);
      expect(button().busy, isTrue);

      await overtaken(tester, client);
      screens.close();
      await tester.pump(_frame);
      await tester.pump(_frame);

      expect(_session(container), 'out');
      expect(button().busy, isFalse);
      expect(button().onPressed, isNotNull);
      expect(find.bySemanticsIdentifier(SemanticsIds.setupError), findsNothing);
    });
  });

  group('a sign-in with no signed-in screens up', () {
    for (final MapEntry(key: road, value: signIn) in _roads.entries) {
      testWidgets('by $road shows its session with no frame drawn and no '
          'timer run', (tester) async {
        final client = _client(session: _nobody);
        final container = client.container;
        await container.read(authControllerProvider.future);

        var landed = false;
        unawaited(signIn(_auth(container)).whenComplete(() => landed = true));
        await _microtasks();

        expect(landed, isTrue);
        expect(_session(container), 'ben');
      });
    }

    test('for the account whose session is held waits for nothing: its '
        'screens are staying', () async {
      final client = _client();
      final container = client.container;
      await container.read(authControllerProvider.future);
      final screens = container.listen(signedInScreensProvider, (_, _) {});
      addTearDown(screens.close);

      // Her own sign-in, answered after the start's read already was.
      client.server.next = _ann;
      var landed = false;
      unawaited(
        _auth(container)
            .login(username: 'ann', password: 'pw')
            .whenComplete(() => landed = true),
      );
      await pumpEventQueue();

      expect(landed, isTrue);
      expect(_session(container), 'ann');
      expect(client.store.token, 'token-ann');
    });

    testWidgets('in the whole app lands as fast at a first start, and again '
        'once a sign-out\'s screens are gone', (tester) async {
      final device = _device(signedIn: false);
      final container = device.container;
      await mountHost(tester, const WaxDeckApp(), container: container);
      await _until(tester, _signIn);

      // Signs in with no frame drawn; answers the frames Home then took.
      Future<int> lands(String who) async {
        var landed = false;
        unawaited(
          _auth(container)
              .login(username: who, password: 'pw')
              .whenComplete(() => landed = true),
        );
        await _microtasks();
        expect(landed, isTrue, reason: who);
        expect(_session(container), who);
        return _until(tester, _home);
      }

      // At a first start no signed-in screens ever were: what Home takes
      // with nothing to wait for.
      final unwaited = await lands('ben');

      await _through(tester, _auth(container).logout());
      await _until(tester, _signIn);
      // Past the transition that takes the signed-in screens away.
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(_frame);
      }
      expect(container.exists(signedInScreensProvider), isFalse);

      device.server.next = _cid;
      expect(await lands('cid'), unwaited);
      expect(tester.takeException(), isNull);
      await device.engine.stop();
    });
  });

  testWidgets('in the whole app, a build Riverpod runs again while a sign-in '
      'waits takes its place: one session shows, once the screens are '
      'gone', (tester) async {
    final device = _device(signedIn: false);
    final container = device.container;
    final server = device.server;
    await mountHost(tester, const WaxDeckApp(), container: container);
    final errors = <Object>[];
    var at = 0;
    Future<void> frame() async {
      await tester.pump(_frame);
      at++;
      if (tester.takeException() case final error?) errors.add(error);
    }

    Future<void> through(Future<void> work) async {
      var done = false;
      unawaited(work.whenComplete(() => done = true));
      for (final from = at; !done && at < from + 200;) {
        await frame();
      }
      expect(done, isTrue, reason: 'still out after 200 frames');
    }

    Future<void> until(Finder found) async {
      for (final from = at; found.evaluate().isEmpty;) {
        if (at > from + 200) fail('never drawn: $found');
        await frame();
      }
    }

    await until(_signIn);

    // A build of the open app that fails leaves Riverpod building it
    // again, each time later: through to a rung seconds before the next.
    server.down = true;
    container.invalidate(authControllerProvider);
    const lost = WaxDeckApiException(code: 'transport', message: 'down');
    final asked = server.reads;
    while (server.reads < asked + 6) {
      await frame();
    }
    final next = at + retryUnlessRefused(5, lost)!.inMilliseconds ~/ 50;
    server.down = false;

    // Ann signs in and out; Ben's sign-in is waiting when the rung comes.
    server.next = _ann;
    await through(_auth(container).login(username: 'ann', password: 'pw'));
    await until(_home);
    final attempts = device.net.attempts.length;
    var annsScreensGone = false;
    unawaited(
      container
          .read(signedInScreensProvider)
          .gone
          .then((_) => annsScreensGone = true),
    );
    final shownOverAnns = <String>[];
    final shown = <String>[];
    final watch = container.listen(authControllerProvider, (_, next) {
      final who = next.value?.user?.username;
      if (who == null) return;
      shown.add(who);
      if (!annsScreensGone) shownOverAnns.add(who);
    });
    addTearDown(watch.close);
    while (at < next - 4) {
      await frame();
    }
    await through(_auth(container).logout());
    expect(at, lessThan(next));

    server.next = _ben;
    bool? took;
    unawaited(
      _auth(container)
          .login(username: 'ben', password: 'pw')
          .then((answer) => took = answer),
    );
    final reads = server.reads;
    while (server.reads == reads && at < next + 4) {
      await frame();
    }
    // The build read the session with the sign-in still waiting.
    expect(server.reads, greaterThan(reads));
    expect(annsScreensGone, isFalse);
    expect(took, isNull);

    for (var more = 0; more < 60; more++) {
      await frame();
    }
    expect(errors, isEmpty);
    expect(annsScreensGone, isTrue);
    expect(shownOverAnns, isEmpty);
    expect(shown, ['ben']);
    expect(took, isFalse);
    expect(_home, findsOneWidget);
    expect(container.read(signedInAccountProvider), _ben.id);
    expect(device.engine.started, isTrue);
    expect(device.engine.account, _ben.id);
    expect(device.net.attempts, hasLength(attempts + 1));
    await device.engine.stop();
  });

  testWidgets('in the whole app, a build that finds another account\'s '
      'session where one shows hands it to a session read: that account\'s '
      'screens are gone before the other shows', (tester) async {
    final device = _device();
    final container = device.container;
    await mountHost(tester, const WaxDeckApp(), container: container);
    await _until(tester, _home);
    expect(device.engine.account, _ann.id);

    final errors = <Object>[];
    var annsScreensGone = false;
    unawaited(
      container
          .read(signedInScreensProvider)
          .gone
          .then((_) => annsScreensGone = true),
    );
    final shownOverAnns = <String>[];
    final watch = container.listen(authControllerProvider, (_, next) {
      final who = next.value?.user?.username;
      if (who == null || who == 'ann') return;
      if (!annsScreensGone) shownOverAnns.add(who);
    });
    addTearDown(watch.close);

    // The session held turns out to be Ben's, and the build is run again.
    device.server.sessionState = _bens;
    container.invalidate(authControllerProvider);
    for (var frame = 0; frame < 60; frame++) {
      await tester.pump(_frame);
      if (tester.takeException() case final error?) errors.add(error);
    }

    expect(errors, isEmpty);
    expect(annsScreensGone, isTrue);
    expect(shownOverAnns, isEmpty);
    expect(container.read(signedInAccountProvider), _ben.id);
    expect(_home, findsOneWidget);
    expect(device.engine.started, isTrue);
    expect(device.engine.account, _ben.id);
    await device.engine.stop();
  });

  group('in the whole app, a sign-in landing inside a sign-out\'s '
      'transition', () {
    // Frames between the sign-out and the sign-in. The transition takes
    // the signed-in screens away some nine frames in; twelve is past it.
    for (final gap in [0, 1, 2, 4, 6, 8, 12]) {
      for (final MapEntry(key: road, value: signIn) in _roads.entries) {
        testWidgets('by $road, $gap frames after, throws nothing, ends the '
            'last session\'s engine and starts its own', (tester) async {
          final device = _device();
          final container = device.container;
          await mountHost(tester, const WaxDeckApp(), container: container);
          await _until(tester, _home);
          expect(device.engine.account, _ann.id);
          expect(device.engine.started, isTrue);
          final attempts = device.net.attempts.length;

          final errors = <Object>[];
          void take() {
            if (tester.takeException() case final error?) errors.add(error);
          }

          // Ann's screens, and what stood when the next session showed.
          var annsScreensGone = false;
          unawaited(
            container
                .read(signedInScreensProvider)
                .gone
                .then((_) => annsScreensGone = true),
          );
          final shownOverAnns = <String>[];
          final shownWithHerEngine = <String>[];
          final watch = container.listen(authControllerProvider, (_, next) {
            final who = next.value?.user?.username;
            if (who == null) return;
            if (!annsScreensGone) shownOverAnns.add(who);
            if (device.engine.account == _ann.id && device.engine.started) {
              shownWithHerEngine.add(who);
            }
          });
          addTearDown(watch.close);

          await _through(tester, _auth(container).logout(), each: take);
          for (var frame = 0; frame < gap; frame++) {
            await tester.pump(_frame);
            take();
          }
          await _through(tester, signIn(_auth(container)), each: take);
          await _until(tester, _home, each: take);
          for (var frame = 0; frame < 40; frame++) {
            await tester.pump(_frame);
            take();
          }

          expect(errors, isEmpty);
          expect(annsScreensGone, isTrue);
          expect(shownOverAnns, isEmpty);
          expect(shownWithHerEngine, isEmpty);
          expect(container.read(signedInAccountProvider), _ben.id);
          expect(_home, findsOneWidget);
          expect(device.engine.started, isTrue);
          expect(device.engine.account, _ben.id);
          expect(device.net.attempts, hasLength(attempts + 1));
          await device.engine.stop();
        });
      }
    }
  });
}
