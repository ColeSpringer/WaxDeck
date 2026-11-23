import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/auth/oidc_flow.dart';
import 'package:waxdeck/src/auth/owed_revoke.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_persistence.dart';
import 'package:waxdeck/src/settings/client_settings/browser_settings_store.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import 'app_host.dart';
import 'fakes.dart';

/// A browser keeps which session its cookie holds, as the server's last
/// answer said, and a sign-out its server did not hear names that session:
/// delivered, it ends that session, and no session made since.

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

const _lost = WaxDeckApiException(
  code: 'transport',
  message: 'connection refused',
);
const _refused = WaxDeckApiException(
  code: 'internal',
  message: 'refused at the proxy',
  statusCode: 502,
);
const _gateway = WaxDeckApiException(
  code: 'transport',
  message: 'bad gateway',
  statusCode: 502,
);
const _refusedInFront = WaxDeckApiException(
  code: 'transport',
  message: 'forbidden at the proxy',
  statusCode: 403,
);
const _noSession = WaxDeckApiException(
  code: 'unauthenticated',
  message: 'no valid session or token was presented',
  statusCode: 401,
);
const _wrongProof = WaxDeckApiException(
  code: 'forbidden',
  message: 'missing or wrong CSRF token',
  statusCode: 403,
);
const _noSuch = WaxDeckApiException(
  code: 'not-found',
  message: 'no session with that id',
  statusCode: 404,
);

const _sso = OidcProvider(
  id: 'corp',
  displayName: 'Corp SSO',
  startUrl: 'http://server.test/api/v1/auth/oidc/start?provider=corp',
);

/// A server as one browser reaches it: one cookie for every tab, which
/// names a session, and the CSRF token of the session the page's client
/// last read or signed in, which a mutation over the cookie must carry, as
/// the server's middleware demands. A fresh page holds none.
class _Server extends FakeRepository {
  _Server() : super(items: [testItem('tr-A')]);

  final _owners = <String, WaxDeckUser>{};
  var _opened = 0;

  /// The session the browser's cookie names, ended or not.
  String? cookie;
  String? _proof;

  /// Every request fails, as with the server out of reach, while set.
  var down = false;

  /// Session reads say which session they hold, as the server's do, while
  /// set. A sign-in's answer always does.
  var names = true;

  /// A sign-in makes its session and sets the cookie, and the page that
  /// asked never hears the answer, while set.
  var answersLost = false;

  /// What every sign-out and revoke by id is refused with, as by a proxy,
  /// while set.
  WaxDeckApiException? revokesRefused;

  /// Holds each session read, each sign-in and each sign-out (made when
  /// answered) until completed, when set.
  Completer<void>? sessionHeld;
  Completer<void>? signInHeld;
  Completer<void>? logoutHeld;

  /// Who the next sign-in signs in.
  WaxDeckUser next = _ann;

  /// What was asked, in order: `session`, `sessions`, `revoke <id>`,
  /// `logout`, `logout <token>`, `sign-in`.
  final asked = <String>[];

  final _meanwhile = <(bool Function(String), void Function())>[];

  /// [lands] as the first request [matching] arrives, before it is
  /// answered.
  void meanwhile(bool Function(String asked) matching, void Function() lands) =>
      _meanwhile.add((matching, lands));

  String open(WaxDeckUser user) {
    final id = 'se-${++_opened}';
    _owners[id] = user;
    return id;
  }

  bool live(String id) => _owners.containsKey(id);

  void end(String id) => _owners.remove(id);

  /// A sign-in in another tab, or a single sign-on's return: the cookie
  /// names a new session.
  String signInElsewhere(WaxDeckUser user) => cookie = open(user);

  /// A page loaded afresh: its client holds no CSRF token.
  void newPage() => _proof = null;

  void _ask(String what) {
    asked.add(what);
    final at = _meanwhile.indexWhere((hook) => hook.$1(what));
    if (at >= 0) _meanwhile.removeAt(at).$2();
    if (down) throw _lost;
  }

  @override
  Future<SessionState> getSession() async {
    _ask('session');
    await sessionHeld?.future;
    final user = _owners[cookie];
    _proof = user == null ? null : cookie;
    return user == null
        ? const SessionState(authenticated: false)
        : SessionState(
            authenticated: true,
            user: user,
            sessionId: names ? cookie : null,
          );
  }

  @override
  Future<List<DeviceSession>> listSessions() async {
    _ask('sessions');
    final user = _owners[cookie];
    if (user == null) throw _noSession;
    return [
      for (final MapEntry(:key, :value) in _owners.entries)
        if (value.id == user.id)
          testSession(key, kind: SessionKind.web, current: key == cookie),
    ];
  }

  @override
  Future<void> revokeSession(String sessionId) async {
    _ask('revoke $sessionId');
    if (revokesRefused case final refusal?) throw refusal;
    final user = _owners[cookie];
    if (user == null) throw _noSession;
    if (_proof != cookie) throw _wrongProof;
    if (_owners[sessionId]?.id != user.id) throw _noSuch;
    _owners.remove(sessionId);
    if (sessionId == cookie) cookie = null;
  }

  @override
  Future<void> logout() async {
    _ask('logout');
    // It ends the session the cookie named when it was sent, and its answer
    // expires whatever cookie the browser holds when it lands.
    final presented = cookie;
    await logoutHeld?.future;
    if (revokesRefused case final refusal?) throw refusal;
    _owners.remove(presented);
    cookie = null;
    _proof = null;
  }

  @override
  Future<void> logoutToken(String token) async {
    _ask('logout $token');
  }

  LoginResult _signIn() {
    final made = cookie = _proof = open(next);
    return LoginResult(
      user: next,
      token: 'token-${next.username}',
      sessionId: made,
    );
  }

  @override
  Future<LoginResult> login({
    required String username,
    required String password,
    String? deviceName,
  }) async {
    _ask('sign-in');
    await signInHeld?.future;
    if (down) throw _lost;
    final answer = _signIn();
    if (answersLost) await Completer<void>().future;
    return answer;
  }

  @override
  Future<LoginResult> oidcExchange({
    required String code,
    String? verifier,
    String? deviceName,
  }) async {
    _ask('sign-in');
    return _signIn();
  }
}

/// The page's storage, which every tab of the browser shares.
class _Storage implements BrowserStorage {
  final values = <String, String>{};

  @override
  String? getItem(String key) => values[key];

  @override
  void setItem(String key, String value) => values[key] = value;

  @override
  void removeItem(String key) => values.remove(key);
}

/// A browser keeps no token, and no session for one: its build reads the
/// session with nothing restored.
class _NoKeychain extends InMemoryCredentialStore {
  @override
  Future<void> writeToken(String value) async {}

  @override
  Future<void> writeSession(String value) async {}
}

/// An identity provider that comes straight back with the one-time code,
/// and says what the browser's storage owed when the flow started.
class _Browser implements UrlOpenerPort, DeepLinkPort {
  _Browser(this.storage);

  final _Storage? storage;
  final _links = StreamController<Uri>.broadcast();
  final owedAtStart = <String?>[];

  @override
  Future<void> open(String url) async {
    owedAtStart.add(storage?.values[OwedRevoke.storageKey]);
    _links.add(Uri.parse('waxdeck://auth?code=one-time'));
  }

  @override
  Stream<Uri> get uriLinkStream => _links.stream;
}

/// A tab of the browser: a client of [server] over the page's [storage],
/// or over none, as a native client is.
ProviderContainer _tab(_Server server, _Storage? storage, {_Browser? sso}) {
  final browser = sso ?? _Browser(storage);
  return appContainer(
    repo: server,
    credentials: _NoKeychain(),
    settings: MemoryClientSettingsStore(),
    extra: [
      if (storage != null)
        owedRevokeProvider.overrideWithValue(OwedRevoke(storage)),
      urlOpenerProvider.overrideWithValue(browser),
      deepLinkProvider.overrideWithValue(browser),
      queueSaveDebounceProvider.overrideWithValue(Duration.zero),
    ],
  );
}

AuthController _auth(ProviderContainer container) =>
    container.read(authControllerProvider.notifier);

/// Whose session the tab holds: a name, or `out`.
String _session(ProviderContainer container) =>
    container.read(authControllerProvider).value?.user?.username ?? 'out';

/// What the page's storage says is owed: a session's id, `unnamed` for a
/// revoke that names none, null for nothing.
String? _owed(_Storage storage) =>
    switch (storage.values[OwedRevoke.storageKey]) {
      null => null,
      _ when OwedRevoke(storage).session == null => 'unnamed',
      final mark => mark,
    };

/// Which session the page's storage says the cookie holds.
String? _held(_Storage storage) => storage.values[OwedRevoke.heldKey];

/// The controller built again, as Riverpod does after a build that failed:
/// what its build answers.
Future<SessionState> _builtAgain(ProviderContainer container) {
  container.invalidate(authControllerProvider);
  return container.read(authControllerProvider.future);
}

/// The controller built again, its build left to fail or answer.
Future<void> _buildsAgain(ProviderContainer container) async {
  container.invalidate(authControllerProvider);
  container.read(authControllerProvider);
  await pumpEventQueue();
}

typedef _Page = ({
  ProviderContainer container,
  _Server server,
  _Storage storage,
  String session,
});

/// The page loaded again: a new client over the same browser.
Future<ProviderContainer> _reloaded(_Page page) async {
  page.container.dispose();
  page.server.newPage();
  final container = _tab(page.server, page.storage);
  container.read(authControllerProvider);
  await pumpEventQueue();
  return container;
}

/// Ann's tab, signed in on a session of hers that the page knows by id.
Future<_Page> _annIn({_Server? on, _Storage? storage}) async {
  final server = on ?? _Server();
  final session = server.cookie ??= server.open(_ann);
  final kept = storage ?? _Storage();
  final container = _tab(server, kept);
  await container.read(authControllerProvider.future);
  await pumpEventQueue();
  expect(_session(container), 'ann');
  expect(_held(kept), server.names ? session : isNull);
  return (
    container: container,
    server: server,
    storage: kept,
    session: session,
  );
}

/// [page] just after Ann signed out with the server out of reach: the page
/// is signed out and her session still lives. The server is back unless
/// told otherwise.
Future<void> _leftUnheard(_Page page, {bool back = true}) async {
  page.server.down = true;
  await _auth(page.container).logout();
  expect(_session(page.container), 'out');
  expect(page.server.live(page.session), isTrue);
  page.server
    ..down = !back
    ..asked.clear();
}

void main() {
  group('which session the browser holds', () {
    test('is said by every answer that holds one, and forgotten at one that '
        'finds none, with no session list read', () async {
      final page = await _annIn();
      final server = page.server;

      final since = server.signInElsewhere(_ann);
      expect(
        await _auth(page.container).refreshSession(),
        SessionRecheck.stands,
      );
      expect(_held(page.storage), since);

      page.server.next = _ben;
      expect(
        await _auth(page.container).login(username: 'b', password: 'p'),
        isTrue,
      );
      final bens = server.cookie;
      expect(_held(page.storage), bens);
      await pumpEventQueue();

      server.end(bens!);
      expect(await _auth(page.container).refreshSession(), SessionRecheck.left);
      expect(_held(page.storage), isNull);
      expect(server.asked, isNot(contains('sessions')));
    });

    test('is not known from an answer that does not say', () async {
      final page = await _annIn();
      page.server.names = false;

      expect(
        await _auth(page.container).refreshSession(),
        SessionRecheck.stands,
      );
      expect(_held(page.storage), isNull);
    });

    test('is not kept without browser storage, as on native', () async {
      final server = _Server();
      server.cookie = server.open(_ann);
      final container = _tab(server, null);
      await container.read(authControllerProvider.future);
      await _auth(container).refreshSession();
      await pumpEventQueue();
      expect(server.asked, isNot(contains('sessions')));
      expect(container.read(owedRevokeProvider).held, isNull);
    });
  });

  group('a sign-out', () {
    test('that the server hears is a plain sign-out of whatever the cookie '
        'holds, and owes nothing', () async {
      final page = await _annIn();
      page.server.asked.clear();

      await _auth(page.container).logout();
      expect(page.server.asked, ['logout']);
      expect(page.server.live(page.session), isFalse);
      expect(_owed(page.storage), isNull);
      expect(_held(page.storage), isNull);
      expect(_session(page.container), 'out');
    });

    test('that the server does not hear owes the revoke of the session the '
        'cookie holds, by its id', () async {
      final page = await _annIn();
      await _leftUnheard(page, back: false);
      expect(_owed(page.storage), page.session);
    });

    test('is owed by name the moment it is pressed, and shows nobody while '
        'its request is out: a reload then delivers it', () async {
      final page = await _annIn();
      page.server.logoutHeld = Completer<void>();

      unawaited(_auth(page.container).logout());
      expect(_owed(page.storage), page.session);
      await pumpEventQueue();
      expect(_session(page.container), 'out');

      page.server.asked.clear();
      final reloaded = await _reloaded(page);
      expect(page.server.asked, [
        'session',
        'revoke ${page.session}',
        'session',
      ]);
      expect(page.server.live(page.session), isFalse);
      expect(_session(reloaded), 'out');
      expect(_owed(page.storage), isNull);
    });

    test('pressed while a sign-in is out shows nobody at once and ends the '
        'session the cookie holds; the sign-in, landing after, is undone, '
        'and a reload shows nobody', () async {
      final page = await _annIn();
      final server = page.server
        ..next = _ben
        ..signInHeld = Completer<void>();

      final signing = _auth(page.container).login(username: 'b', password: 'p');
      await pumpEventQueue();
      final leaving = _auth(page.container).logout();
      // Not known: the sign-in's answer may replace the cookie any moment.
      expect(_owed(page.storage), 'unnamed');
      await pumpEventQueue();
      expect(_session(page.container), 'out');
      expect(server.asked.last, 'logout');
      expect(server.live(page.session), isFalse);
      // Heard, and still owed for the sign-in out.
      expect(_owed(page.storage), 'unnamed');

      server.signInHeld!.complete();
      expect(await signing, isFalse);
      await leaving;
      await pumpEventQueue();
      final made = server.asked
          .lastWhere((what) => what.startsWith('revoke '))
          .substring('revoke '.length);
      expect(server.live(made), isFalse);
      expect(server.cookie, isNull);
      expect(_session(page.container), 'out');
      expect(_owed(page.storage), isNull);

      final reloaded = await _reloaded(page);
      expect(_session(reloaded), 'out');
    });

    test('pressed while a sign-in is out, its own request still out when the '
        'sign-in lands: what that sign-in owes is delivered once the request '
        'lands', () async {
      final page = await _annIn();
      final server = page.server
        ..next = _ben
        ..signInHeld = Completer<void>()
        ..logoutHeld = Completer<void>();

      final signing = _auth(page.container).login(username: 'b', password: 'p');
      await pumpEventQueue();
      final leaving = _auth(page.container).logout();
      await pumpEventQueue();
      server.signInHeld!.complete();
      await pumpEventQueue();
      final made = server.cookie!;
      expect(server.live(made), isTrue);

      expect(_owed(page.storage), made);

      // The sign-out's answer, landing last, expires the cookie the
      // sign-in set: the delivery finds no session to end.
      server.logoutHeld!.complete();
      expect(await signing, isFalse);
      await leaving;
      await pumpEventQueue();
      expect(server.asked.last, 'session');
      expect(server.cookie, isNull);
      expect(_owed(page.storage), isNull);
      expect(_session(page.container), 'out');
    });

    test('pressed while a sign-in is out, the page reloaded before its answer '
        'comes back: the reload ends the session it made', () async {
      final page = await _annIn();
      final server = page.server
        ..next = _ben
        ..signInHeld = Completer<void>()
        ..answersLost = true;

      unawaited(_auth(page.container).login(username: 'b', password: 'p'));
      await pumpEventQueue();
      unawaited(_auth(page.container).logout());
      await pumpEventQueue();
      expect(server.live(page.session), isFalse);

      // The server makes the session and sets the cookie; the page that
      // asked is gone before it hears.
      page.container.dispose();
      server.signInHeld!.complete();
      await pumpEventQueue();
      final made = server.cookie!;
      expect(server.live(made), isTrue);

      server.asked.clear();
      final reloaded = await _reloaded(page);
      expect(server.asked, ['logout', 'session']);
      expect(server.live(made), isFalse);
      expect(_session(reloaded), 'out');
      expect(_owed(page.storage), isNull);
    });

    test('pressed while a sign-in is out that fails settles what it owed once '
        'that sign-in lands', () async {
      final page = await _annIn();
      final server = page.server..signInHeld = Completer<void>();

      final signing = _auth(page.container).login(username: 'a', password: 'p');
      await pumpEventQueue();
      await _auth(page.container).logout();
      expect(_owed(page.storage), 'unnamed');

      server.down = true;
      server.signInHeld!.complete();
      await expectLater(signing, throwsA(_lost));
      expect(_owed(page.storage), isNull);
    });

    test('unheard, with the session the cookie holds not known, owes one that '
        'names none, delivered as a plain sign-out', () async {
      final server = _Server()..names = false;
      server.cookie = server.open(_ann);
      final storage = _Storage();
      final container = _tab(server, storage);
      await container.read(authControllerProvider.future);
      server.down = true;
      await _auth(container).logout();
      expect(_owed(storage), 'unnamed');

      server
        ..down = false
        ..asked.clear();
      expect((await _builtAgain(container)).authenticated, isFalse);
      expect(server.asked, ['logout', 'session']);
      expect(_owed(storage), isNull);
    });
  });

  test('a sign-in\'s answer settles only the revoke owed when it was sent, '
      'never one another tab owed since', () async {
    final storage = _Storage();
    final server = _Server()..names = false;
    final page = await _annIn(on: server, storage: storage);
    final other = await _annIn(on: server, storage: storage);
    await _leftUnheard(page);
    final first = storage.values[OwedRevoke.storageKey];

    // Its delivery refused, the sign-in goes all the same, and is held.
    server
      ..revokesRefused = _refused
      ..signInHeld = Completer<void>();
    final signing = _auth(page.container).login(username: 'a', password: 'p');
    await pumpEventQueue();
    expect(server.asked, ['logout', 'sign-in']);

    // The other tab signs out meanwhile, unheard too.
    await _auth(other.container).logout();
    final since = storage.values[OwedRevoke.storageKey];
    expect(since, isNot(first));
    expect(_owed(storage), 'unnamed');

    server.signInHeld!.complete();
    expect(await signing, isTrue);
    expect(storage.values[OwedRevoke.storageKey], since);
  });

  group('a revoke owed by name', () {
    test('from a fresh page, which holds no CSRF token, is delivered: a read '
        'hands the page the token, and the revoke by id ends it', () async {
      final page = await _annIn();
      await _leftUnheard(page);

      final reloaded = await _reloaded(page);
      expect(page.server.asked, [
        'session',
        'revoke ${page.session}',
        'session',
      ]);
      expect(page.server.live(page.session), isFalse);
      expect(page.server.cookie, isNull);
      expect(_session(reloaded), 'out');
      expect(_owed(page.storage), isNull);
    });

    for (final (who, same) in [(_ann, true), (_ben, false)]) {
      for (final (moment, landed) in [
        ('since', (_Page page, void Function() land) => land()),
        (
          'as its token read arrives',
          (_Page page, void Function() land) =>
              page.server.meanwhile((what) => what == 'session', land),
        ),
      ]) {
        test('with a sign-in of ${same ? 'the same' : 'another'} account '
            '$moment, ends ${same ? 'the old session' : 'nothing'} and keeps '
            'the new one', () async {
          final page = await _annIn();
          await _leftUnheard(page);
          late String made;
          landed(page, () => made = page.server.signInElsewhere(who));

          final built = await _builtAgain(page.container);
          expect(built.user?.username, who.username);
          expect(page.server.asked, contains('revoke ${page.session}'));
          expect(page.server.live(made), isTrue);
          expect(page.server.cookie, made);
          expect(page.server.live(page.session), !same);
          expect(_owed(page.storage), isNull);
        });
      }
    }

    test('with a sign-in landing between the read that hands it its token and '
        'the revoke, is refused that token and stays owed; the next asking '
        'reads afresh, ends the old one and keeps the new', () async {
      final page = await _annIn();
      await _leftUnheard(page);
      late String made;
      page.server.meanwhile(
        (what) => what == 'revoke ${page.session}',
        () => made = page.server.signInElsewhere(_ann),
      );

      await _buildsAgain(page.container);
      expect(page.container.read(authControllerProvider).error, _wrongProof);
      expect(_session(page.container), 'out');
      expect(_owed(page.storage), page.session);
      expect(page.server.live(page.session), isTrue);

      expect((await _builtAgain(page.container)).user?.username, 'ann');
      expect(page.server.live(made), isTrue);
      expect(page.server.cookie, made);
      expect(page.server.live(page.session), isFalse);
      expect(_owed(page.storage), isNull);
    });

    test('names the session another tab signed in again since, which shared '
        'storage says the cookie holds: its delivery ends that one', () async {
      final storage = _Storage();
      final server = _Server();
      final page = await _annIn(on: server, storage: storage);
      final other = await _annIn(on: server, storage: storage);

      // The other tab signs out and back in; this one reads nothing since.
      await _auth(other.container).logout();
      expect(
        await _auth(other.container).login(username: 'a', password: 'p'),
        isTrue,
      );
      await pumpEventQueue();
      final again = server.cookie!;
      expect(_session(page.container), 'ann');

      await _leftUnheard((
        container: page.container,
        server: server,
        storage: storage,
        session: again,
      ));
      expect(_owed(storage), again);
      expect((await _builtAgain(page.container)).authenticated, isFalse);
      expect(server.live(again), isFalse);
      expect(server.cookie, isNull);
    });

    test('pressed in one tab while another is away at single sign-on: the '
        'return keeps the session it made, and ends the one owed', () async {
      final page = await _annIn();
      await _leftUnheard(page);

      // The provider's answer sets the cookie, and the return page starts.
      final made = page.server.signInElsewhere(_ann);
      final returned = await _reloaded(page);
      expect(_session(returned), 'ann');
      expect(page.server.live(made), isTrue);
      expect(page.server.cookie, made);
      expect(page.server.live(page.session), isFalse);
      expect(page.server.asked, isNot(contains('logout')));
      expect(_owed(page.storage), isNull);
    });

    test('with another account signed in since: the server has no such '
        'session for it, so it is settled and that session left '
        'alone', () async {
      final page = await _annIn();
      await _leftUnheard(page);
      final bens = page.server.signInElsewhere(_ben);

      expect((await _builtAgain(page.container)).user?.username, 'ben');
      expect(page.server.asked, [
        'session',
        'revoke ${page.session}',
        'session',
      ]);
      expect(page.server.live(bens), isTrue);
      expect(_owed(page.storage), isNull);
    });

    test('with another account signed in since, on a server whose reads do '
        'not say which session: the server says it has no such session, and '
        'it is settled', () async {
      final page = await _annIn();
      await _leftUnheard(page);
      page.server.names = false;
      final bens = page.server.signInElsewhere(_ben);

      expect((await _builtAgain(page.container)).user?.username, 'ben');
      expect(page.server.asked, contains('revoke ${page.session}'));
      expect(page.server.live(bens), isTrue);
      expect(_owed(page.storage), isNull);
    });

    test('with the cookie holding no session any more: settled, and nothing '
        'sent', () async {
      final page = await _annIn();
      await _leftUnheard(page);
      page.server.end(page.session);

      expect((await _builtAgain(page.container)).authenticated, isFalse);
      expect(page.server.asked, ['session', 'session']);
      expect(_owed(page.storage), isNull);
    });

    test('with its session ended between the read that hands the token and '
        'the revoke: the server hears no session, and it is settled', () async {
      final page = await _annIn();
      await _leftUnheard(page);
      page.server.meanwhile(
        (what) => what == 'revoke ${page.session}',
        () => page.server.end(page.session),
      );

      expect((await _builtAgain(page.container)).authenticated, isFalse);
      expect(page.server.asked, contains('revoke ${page.session}'));
      expect(_owed(page.storage), isNull);
    });

    test('out of reach is still owed by name, and nobody shows', () async {
      final page = await _annIn();
      await _leftUnheard(page, back: false);

      await _buildsAgain(page.container);
      expect(page.container.read(authControllerProvider).error, _lost);
      expect(_session(page.container), 'out');
      expect(_owed(page.storage), page.session);
    });

    for (final (how, refusal) in [
      ('in no words, as a gateway does', _gateway),
      ('in words', _refused),
    ]) {
      test('refused by something in front of the server, $how, while the '
          'cookie still holds it is still owed, and nobody shows', () async {
        final page = await _annIn();
        await _leftUnheard(page);
        page.server.revokesRefused = refusal;

        await _buildsAgain(page.container);
        expect(page.container.read(authControllerProvider).error, refusal);
        expect(_session(page.container), 'out');
        expect(_owed(page.storage), page.session);
        expect(page.server.live(page.session), isTrue);
      });
    }

    for (final (how, refusal) in [
      ('a gateway\'s answer in no words', _gateway),
      ('a refusal in no words from something in front', _refusedInFront),
    ]) {
      test('for a session the cookie no longer holds, answered by $how, is '
          'let go, and the start goes on', () async {
        final page = await _annIn();
        await _leftUnheard(page);
        final made = page.server.signInElsewhere(_ann);
        page.server.revokesRefused = refusal;

        expect((await _builtAgain(page.container)).user?.username, 'ann');
        expect(page.server.asked, contains('revoke ${page.session}'));
        expect(page.server.cookie, made);
        expect(_owed(page.storage), isNull);
      });
    }

    test('for a session the cookie no longer holds, refused its proof by a '
        'sign-in landing before the revoke, stays owed, and the next asking '
        'ends it by its id', () async {
      final page = await _annIn();
      await _leftUnheard(page);
      page.server.signInElsewhere(_ann);
      late String made;
      page.server.meanwhile(
        (what) => what == 'revoke ${page.session}',
        () => made = page.server.signInElsewhere(_ann),
      );

      await _buildsAgain(page.container);
      expect(page.container.read(authControllerProvider).error, _wrongProof);
      expect(_session(page.container), 'out');
      expect(_owed(page.storage), page.session);
      expect(page.server.live(page.session), isTrue);

      expect((await _builtAgain(page.container)).user?.username, 'ann');
      expect(page.server.live(page.session), isFalse);
      expect(page.server.live(made), isTrue);
      expect(page.server.cookie, made);
      expect(_owed(page.storage), isNull);
    });

    test('for a session the cookie no longer holds, with no answer to its '
        'revoke, is still owed, and nobody shows', () async {
      final page = await _annIn();
      await _leftUnheard(page);
      page.server
        ..signInElsewhere(_ann)
        ..revokesRefused = _lost;

      await _buildsAgain(page.container);
      expect(page.server.asked, contains('revoke ${page.session}'));
      expect(page.container.read(authControllerProvider).error, _lost);
      expect(_session(page.container), 'out');
      expect(_owed(page.storage), page.session);
    });

    test('whose client is closed while the read that hands it the token is '
        'out sends nothing more, and is still owed', () async {
      final page = await _annIn();
      await _leftUnheard(page);
      page.server.sessionHeld = Completer<void>();

      await _buildsAgain(page.container);
      expect(page.server.asked, ['session']);
      page.container.dispose();
      page.server.sessionHeld!.complete();
      await pumpEventQueue();
      expect(page.server.asked, ['session']);
      expect(_owed(page.storage), page.session);
    });

    test('and a sign-in whose delivery of it fails: the sign-in goes on, and '
        'the delivery after ends the old session and none it made', () async {
      final page = await _annIn();
      await _leftUnheard(page);
      // Refused for the sign-in's own delivery only.
      page.server
        ..revokesRefused = _refused
        ..meanwhile(
          (what) => what == 'sign-in',
          () => page.server.revokesRefused = null,
        );

      expect(
        await _auth(page.container).login(username: 'a', password: 'p'),
        isTrue,
      );
      final made = page.server.cookie!;
      await pumpEventQueue();
      expect(_session(page.container), 'ann');
      expect(page.server.live(made), isTrue);
      expect(page.server.cookie, made);
      expect(page.server.live(page.session), isFalse);
      expect(_owed(page.storage), isNull);
    });
  });

  group('single sign-on', () {
    test('lets an account that signs in only so in while a revoke owed by '
        'name cannot be delivered, a proxy refusing it for good', () async {
      final page = await _annIn();
      await _leftUnheard(page);
      page.server.revokesRefused = _refused;

      expect(await _auth(page.container).loginWithOidc(_sso), isTrue);
      await pumpEventQueue();
      expect(
        page.container.read(authControllerProvider).value?.authenticated,
        isTrue,
      );
      expect(page.server.live(page.server.cookie!), isTrue);
      expect(_owed(page.storage), isNull);
    });

    test('names a revoke owed that names none before the flow starts, so '
        'that its return ends only the session the cookie held', () async {
      final server = _Server()..names = false;
      server.cookie = server.open(_ann);
      final storage = _Storage();
      final browser = _Browser(storage);
      final container = _tab(server, storage, sso: browser);
      await container.read(authControllerProvider.future);
      final old = server.cookie!;
      server.down = true;
      await _auth(container).logout();
      expect(_owed(storage), 'unnamed');
      server
        ..down = false
        ..names = true
        ..revokesRefused = _refused;

      expect(await _auth(container).loginWithOidc(_sso), isTrue);
      expect(browser.owedAtStart, [old]);
      await pumpEventQueue();
      expect(
        container.read(authControllerProvider).value?.authenticated,
        isTrue,
      );
      expect(server.live(server.cookie!), isTrue);
      expect(_owed(storage), isNull);
    });
  });
}
