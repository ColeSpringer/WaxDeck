import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/auth/oidc_flow.dart';
import 'package:waxdeck/src/auth/owed_revoke.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_persistence.dart';
import 'package:waxdeck/src/settings/client_settings/browser_settings_store.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import 'app_host.dart';
import 'fakes.dart';

/// A browser's session is its server's cookie, which the page cannot
/// remove. A sign-out the server did not hear leaves it live, so the
/// revoke is owed: kept in the page's storage and delivered before the
/// cookie is read as a session again, by whichever road reads it.

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
const _anns = SessionState(authenticated: true, user: _ann);

const _lost = WaxDeckApiException(
  code: 'transport',
  message: 'connection refused',
);
const _broken = WaxDeckApiException(
  code: 'internal',
  message: 'catalog not open',
  statusCode: 500,
);

const _sso = OidcProvider(
  id: 'corp',
  displayName: 'Corp SSO',
  startUrl: 'http://server.test/api/v1/auth/oidc/start?provider=corp',
);

/// A server as a browser reaches it: its cookie is the session, so a
/// session read answers for whoever is signed in whatever bearer the
/// client holds, and only a sign-out the server hears ends that.
class _Server extends FakeRepository {
  _Server({super.sessionState}) : super(items: [testItem('tr-A')]);

  /// Every request fails, as with the server out of reach, while set.
  var down = false;

  /// What a sign-out fails with, reached, while set.
  WaxDeckApiException? revokeRefusal;

  /// What a sign-in fails with, reached, while set.
  WaxDeckApiException? signInRefusal;

  /// Holds each sign-out until completed.
  Completer<void>? revokeHeld;

  /// What the server was asked, in order: `revoke` (a sign-out, or a revoke
  /// by id), `session`, `sign-in`.
  final asked = <String>[];

  void _reach() {
    if (down) throw _lost;
  }

  @override
  Future<SessionState> getSession() async {
    asked.add('session');
    _reach();
    return super.getSession();
  }

  @override
  Future<void> logout() async {
    asked.add('revoke');
    await revokeHeld?.future;
    _reach();
    if (revokeRefusal case final refusal?) throw refusal;
    await super.logout();
  }

  /// A revoke by id ends the session the cookie holds when it names it.
  @override
  Future<void> revokeSession(String sessionId) async {
    asked.add('revoke');
    await revokeHeld?.future;
    _reach();
    if (revokeRefusal case final refusal?) throw refusal;
    if (sessionState.sessionId == sessionId) {
      sessionState = const SessionState(authenticated: false);
    }
  }

  @override
  Future<LoginResult> login({
    required String username,
    required String password,
    String? deviceName,
  }) async {
    asked.add('sign-in');
    await loginGate?.future;
    _reach();
    if (signInRefusal case final refusal?) throw refusal;
    sessionState = const SessionState(
      authenticated: true,
      user: _ben,
      sessionId: 'se-ben',
    );
    authToken = 'token-ben';
    return const LoginResult(
      user: _ben,
      token: 'token-ben',
      sessionId: 'se-ben',
    );
  }

  @override
  Future<BootstrapStatus> bootstrapStatus() async {
    _reach();
    return super.bootstrapStatus();
  }

  @override
  Future<List<OidcProvider>> oidcProviders() async {
    _reach();
    return super.oidcProviders();
  }
}

/// The page's storage, which every tab of the browser shares.
class _Storage implements BrowserStorage {
  final values = <String, String>{};

  /// Every call throws while set, as a denied `localStorage` does.
  var denied = false;

  /// Takes a write and keeps nothing, while set.
  var forgetful = false;

  void _check() {
    if (denied) throw StateError('storage denied');
  }

  @override
  String? getItem(String key) {
    _check();
    return values[key];
  }

  @override
  void setItem(String key, String value) {
    _check();
    if (!forgetful) values[key] = value;
  }

  @override
  void removeItem(String key) {
    _check();
    values.remove(key);
  }
}

/// A browser keeps no token, and no session for one: its build reads the
/// session with nothing restored.
class _NoKeychain extends InMemoryCredentialStore {
  @override
  Future<void> writeToken(String value) async {}

  @override
  Future<void> writeSession(String value) async {}
}

/// A browser that comes straight back with the one-time code.
class _Browser implements UrlOpenerPort, DeepLinkPort {
  final _links = StreamController<Uri>.broadcast();
  final opened = <String>[];

  @override
  Future<void> open(String url) async {
    opened.add(url);
    _links.add(Uri.parse('waxdeck://auth?code=one-time'));
  }

  @override
  Stream<Uri> get uriLinkStream => _links.stream;
}

/// A tab of the browser: a client of [server] over the page's [storage],
/// or over none, as a native client is.
ProviderContainer _tab(_Server server, _Storage? storage, {_Browser? browser}) {
  final opener = browser ?? _Browser();
  return appContainer(
    repo: server,
    credentials: _NoKeychain(),
    settings: MemoryClientSettingsStore(),
    extra: [
      if (storage != null)
        owedRevokeProvider.overrideWithValue(OwedRevoke(storage)),
      urlOpenerProvider.overrideWithValue(opener),
      deepLinkProvider.overrideWithValue(opener),
      queueSaveDebounceProvider.overrideWithValue(Duration.zero),
    ],
  );
}

AuthController _auth(ProviderContainer container) =>
    container.read(authControllerProvider.notifier);

/// Whose session the tab holds: a name, or `out`.
String _session(ProviderContainer container) =>
    container.read(authControllerProvider).value?.user?.username ?? 'out';

bool _marked(_Storage storage) =>
    storage.values.containsKey(OwedRevoke.storageKey);

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
});

/// Ann's tab just after she signed out with the server out of reach: the
/// page is signed out and the server still answers for her. The server is
/// left out of reach unless it is [back].
Future<_Page> _annLeftUnheard({
  bool back = true,
  _Storage? storage,
  _Server? of,
}) async {
  final server = of ?? _Server(sessionState: _anns);
  final kept = storage ?? _Storage();
  final container = _tab(server, kept);
  await container.read(authControllerProvider.future);
  expect(_session(container), 'ann');

  server.down = true;
  await _auth(container).logout();
  expect(_session(container), 'out');
  expect(server.sessionState.authenticated, isTrue);
  server
    ..down = !back
    ..asked.clear();
  return (container: container, server: server, storage: kept);
}

final _form = find.bySemanticsIdentifier(SemanticsIds.loginSubmit);
final _home = find.bySemanticsIdentifier(SemanticsIds.homeScreen);

void main() {
  group('a sign-out the server did not hear', () {
    test('signs the page out, and is owed', () async {
      final page = await _annLeftUnheard(back: false);

      expect(_marked(page.storage), isTrue);
      expect(page.container.read(owedRevokeProvider).owed, isTrue);
    });

    test('is delivered before a build reads the session, which then finds '
        'nobody', () async {
      final page = await _annLeftUnheard();

      final built = await _builtAgain(page.container);
      expect(page.server.asked, ['revoke', 'session']);
      expect(built.authenticated, isFalse);
      expect(_session(page.container), 'out');
      expect(_marked(page.storage), isFalse);
      expect(page.server.sessionState.authenticated, isFalse);
    });

    test('still out of reach fails the build as its read would: no session '
        'is read, nobody shows, and it is still owed', () async {
      final page = await _annLeftUnheard(back: false);

      await _buildsAgain(page.container);
      expect(page.server.asked, isNotEmpty);
      expect(page.server.asked, everyElement('revoke'));
      final state = page.container.read(authControllerProvider);
      expect(state.error, _lost);
      expect(_session(page.container), 'out');
      expect(_marked(page.storage), isTrue);
    });

    test('is delivered by a reload before it reads the session', () async {
      final page = await _annLeftUnheard();
      page.container.dispose();

      final reloaded = _tab(page.server, page.storage);
      final built = await reloaded.read(authControllerProvider.future);
      expect(page.server.asked, ['revoke', 'session']);
      expect(built.authenticated, isFalse);
      expect(_marked(page.storage), isFalse);
    });

    test('still out of reach at a reload: nobody shows, no session is read, '
        'and it is still owed', () async {
      final page = await _annLeftUnheard(back: false);
      page.container.dispose();

      final reloaded = _tab(page.server, page.storage);
      reloaded.read(authControllerProvider);
      await pumpEventQueue();
      expect(page.server.asked, isNotEmpty);
      expect(page.server.asked, everyElement('revoke'));
      final state = reloaded.read(authControllerProvider);
      expect(state.error, _lost);
      expect(state.value, isNull);
      expect(_marked(page.storage), isTrue);
    });

    test('is owed from the moment it is asked: a page closed before the '
        'server answered is signed out at its next start', () async {
      final server = _Server(sessionState: _anns);
      final storage = _Storage();
      final container = _tab(server, storage);
      await container.read(authControllerProvider.future);

      // The request never lands, and the page goes with it out.
      server.revokeHeld = Completer<void>();
      unawaited(_auth(container).logout());
      await pumpEventQueue();
      expect(_marked(storage), isTrue);
      container.dispose();
      server
        ..revokeHeld = null
        ..asked.clear();

      final reopened = _tab(server, storage);
      final built = await reopened.read(authControllerProvider.future);
      expect(server.asked, ['revoke', 'session']);
      expect(built.authenticated, isFalse);
      expect(_marked(storage), isFalse);
    });

    test('goes as the one revoke every road waits for: a build and a session '
        'read that fall due while its request is out send no second, and '
        'read only once it has landed', () async {
      final server = _Server(sessionState: _anns);
      final storage = _Storage();
      final container = _tab(server, storage);
      await container.read(authControllerProvider.future);
      server.asked.clear();

      server.revokeHeld = Completer<void>();
      final leaving = _auth(container).logout();
      await pumpEventQueue();
      container.invalidate(authControllerProvider);
      container.read(authControllerProvider);
      final read = _auth(container).refreshSession();
      await pumpEventQueue();
      expect(server.asked, ['revoke']);
      // The sign-out shows at once, its request still on its way.
      expect(_session(container), 'out');

      server.revokeHeld!.complete();
      await leaving;
      await read;
      await pumpEventQueue();
      expect(server.asked, ['revoke', 'session', 'session']);
      expect(_session(container), 'out');
      expect(_marked(storage), isFalse);
    });

    test('that the server did hear owes nothing', () async {
      final server = _Server(sessionState: _anns);
      final storage = _Storage();
      final container = _tab(server, storage);
      await container.read(authControllerProvider.future);

      await _auth(container).logout();
      expect(_marked(storage), isFalse);
      server.asked.clear();
      await _builtAgain(container);
      expect(server.asked, ['session']);
    });

    testWidgets('in the whole app, with Riverpod still asking after a start '
        'out of reach: nobody is signed back in when the server answers '
        'again', (tester) async {
      final server = _Server()..down = true;
      final storage = _Storage();
      final container = _tab(server, storage);
      await mountHost(tester, const WaxDeckApp(), container: container);
      final seen = <String>[];
      Future<void> wait(Duration time) async {
        for (var frame = 0; frame < time.inMilliseconds ~/ 50; frame++) {
          await tester.pump(const Duration(milliseconds: 50));
          expect(tester.takeException(), isNull);
          final now = [
            if (_form.evaluate().isNotEmpty) 'sign-in',
            if (_home.evaluate().isNotEmpty) 'home',
          ].join('+');
          if (now.isNotEmpty && (seen.isEmpty || seen.last != now)) {
            seen.add(now);
          }
        }
      }

      // The form opens on the first failed read; the build is asked again
      // behind it, each time later.
      await wait(const Duration(seconds: 4));
      expect(seen, ['sign-in']);

      // Back for a sign-in, then out of reach again: the next asking
      // fails under the session, so there is another to come.
      server.down = false;
      unawaited(_auth(container).login(username: 'ben', password: 'pw'));
      await wait(const Duration(milliseconds: 150));
      server.down = true;
      await wait(const Duration(seconds: 4));
      expect(seen.last, 'home');

      unawaited(_auth(container).logout());
      await wait(const Duration(seconds: 2));
      expect(seen.last, 'sign-in');
      expect(_session(container), 'out');
      expect(server.sessionState.authenticated, isTrue);
      seen.clear();

      // The server answers again, and the build's next asking falls due.
      server
        ..down = false
        ..asked.clear();
      await wait(const Duration(seconds: 8));
      expect(server.asked, containsAllInOrder(['revoke', 'session']));
      // The sign-in named its session, so the revoke goes by id, after the
      // read that hands it its token.
      expect(server.asked.take(2), ['session', 'revoke']);
      expect(seen, ['sign-in']);
      expect(_session(container), 'out');
      expect(_marked(storage), isFalse);
      expect(server.sessionState.authenticated, isFalse);
    });
  });

  group('a sign-in while a revoke is owed', () {
    test('delivers it first, then signs in: the session it makes is not '
        'the one revoked', () async {
      final page = await _annLeftUnheard();
      final container = page.container;

      final took = await _auth(
        container,
      ).login(username: 'ben', password: 'pw');
      await pumpEventQueue();
      expect(took, isTrue);
      expect(page.server.asked.take(2), ['revoke', 'sign-in']);
      expect(page.server.asked.where((what) => what == 'revoke'), hasLength(1));
      expect(_session(container), 'ben');
      expect(_marked(page.storage), isFalse);

      expect((await _builtAgain(container)).user?.username, 'ben');
      expect(page.server.asked.where((what) => what == 'revoke'), hasLength(1));
      expect(page.server.sessionState.user?.username, 'ben');
    });

    test('whose revoke cannot be delivered signs in all the same, and '
        'nothing is owed after: its session took the place of the one '
        'owed', () async {
      final page = await _annLeftUnheard();
      final container = page.container;
      page.server.revokeRefusal = _broken;

      final took = await _auth(
        container,
      ).login(username: 'ben', password: 'pw');
      await pumpEventQueue();
      expect(took, isTrue);
      expect(page.server.asked.take(2), ['revoke', 'sign-in']);
      expect(_marked(page.storage), isFalse);

      // Nothing sent from here on can end the session the sign-in made.
      page.server
        ..revokeRefusal = null
        ..asked.clear();
      expect((await _builtAgain(container)).user?.username, 'ben');
      expect(await _auth(container).refreshSession(), SessionRecheck.stands);
      expect(page.server.asked, isNot(contains('revoke')));
      expect(page.server.sessionState.user?.username, 'ben');
    });

    test('that the server refuses, its revoke undelivered too, leaves it '
        'owed', () async {
      final page = await _annLeftUnheard();
      page.server
        ..revokeRefusal = _broken
        ..signInRefusal = const WaxDeckApiException(
          code: 'unauthenticated',
          message: 'invalid credentials',
          statusCode: 401,
        );

      await expectLater(
        _auth(page.container).login(username: 'ben', password: 'no'),
        throwsA(isA<WaxDeckApiException>()),
      );
      expect(page.server.asked, ['revoke', 'sign-in']);
      expect(_marked(page.storage), isTrue);
      expect(_session(page.container), 'out');
    });

    test('asked while the revoke is on its way waits for it to land, and '
        'no second one is sent', () async {
      final page = await _annLeftUnheard();
      final container = page.container;
      final server = page.server;

      // A build's delivery, held on its way.
      server.revokeHeld = Completer<void>();
      final building = _builtAgain(container);
      await pumpEventQueue();
      expect(server.asked, ['revoke']);

      final signing = _auth(container).login(username: 'ben', password: 'pw');
      await pumpEventQueue();
      expect(server.asked, ['revoke']);

      server.revokeHeld!.complete();
      expect(await signing, isTrue);
      await building;
      await pumpEventQueue();
      expect(server.asked.where((what) => what == 'revoke'), hasLength(1));
      expect(server.asked, contains('sign-in'));
      expect(_session(container), 'ben');
      expect(server.sessionState.user?.username, 'ben');
      expect(_marked(page.storage), isFalse);
    });

    test('is not crossed by a revoke: a build that falls due while the '
        'sign-in is out, the revoke still owed, sends none beside '
        'it', () async {
      final page = await _annLeftUnheard();
      final container = page.container;
      final server = page.server;

      // The sign-in's own delivery fails, and the sign-in is out.
      server
        ..revokeRefusal = _broken
        ..loginGate = Completer<void>();
      final signing = _auth(container).login(username: 'ben', password: 'pw');
      await pumpEventQueue();
      expect(server.asked, ['revoke', 'sign-in']);
      expect(_marked(page.storage), isTrue);

      // The server would take a revoke now, and a build is due.
      server.revokeRefusal = null;
      final building = _builtAgain(container);
      await pumpEventQueue();
      expect(server.asked, ['revoke', 'sign-in']);

      server.loginGate!.complete();
      expect(await signing, isTrue);
      await building;
      await pumpEventQueue();
      expect(server.asked.where((what) => what == 'revoke'), hasLength(1));
      expect(_session(container), 'ben');
      expect(server.sessionState.user?.username, 'ben');
      expect(_marked(page.storage), isFalse);
    });

    test('that fails while a build waits for it lets the build deliver the '
        'revoke, and nobody shows', () async {
      final page = await _annLeftUnheard();
      final container = page.container;
      final server = page.server;

      server
        ..revokeRefusal = _broken
        ..signInRefusal = _broken
        ..loginGate = Completer<void>();
      final signing = _auth(container).login(username: 'ben', password: 'pw');
      await pumpEventQueue();
      server.revokeRefusal = null;
      final building = _builtAgain(container);
      await pumpEventQueue();
      expect(server.asked, ['revoke', 'sign-in']);

      server.loginGate!.complete();
      await expectLater(signing, throwsA(_broken));
      expect((await building).authenticated, isFalse);
      expect(server.asked, ['revoke', 'sign-in', 'revoke', 'session']);
      expect(_session(container), 'out');
      expect(_marked(page.storage), isFalse);
    });
  });

  group('single sign-on while a revoke is owed', () {
    test('starts all the same when it cannot be delivered, and signs in: the '
        'revoke, owed for the session before it, is tried once and settled '
        'by its answer', () async {
      final server = _Server(sessionState: _anns);
      final storage = _Storage();
      final browser = _Browser();
      final container = _tab(server, storage, browser: browser);
      await container.read(authControllerProvider.future);
      server.down = true;
      await _auth(container).logout();
      // The server is reached again, and refuses every sign-out, as a proxy
      // in front of it would.
      server
        ..down = false
        ..revokeRefusal = _broken
        ..asked.clear();

      expect(await _auth(container).loginWithOidc(_sso), isTrue);
      await pumpEventQueue();
      expect(server.asked.first, 'revoke');
      expect(server.asked.where((what) => what == 'revoke'), hasLength(1));
      expect(browser.opened, hasLength(1));
      expect(_marked(storage), isFalse);
      expect(container.read(authControllerProvider).value?.authenticated, true);
    });
  });

  group('a session read while a revoke is owed', () {
    test('delivers it first, and finds nobody', () async {
      final page = await _annLeftUnheard();

      expect(await _auth(page.container).refreshSession(), SessionRecheck.left);
      expect(page.server.asked, ['revoke', 'session']);
      expect(_session(page.container), 'out');
      expect(_marked(page.storage), isFalse);
    });

    test('with the server still out of reach reads nothing, and answers '
        'that the server did not', () async {
      final page = await _annLeftUnheard(back: false);

      expect(
        await _auth(page.container).refreshSession(),
        SessionRecheck.unanswered,
      );
      expect(page.server.asked, ['revoke']);
      expect(_session(page.container), 'out');
      expect(_marked(page.storage), isTrue);
    });
  });

  group('a road overtaken while the revoke it waits for is on its way', () {
    test('a build reads nothing: the build that took its place joins the '
        'same revoke, and reads once', () async {
      final page = await _annLeftUnheard();
      final container = page.container;
      final server = page.server;

      server.revokeHeld = Completer<void>();
      container.invalidate(authControllerProvider);
      container.read(authControllerProvider);
      await pumpEventQueue();
      final building = _builtAgain(container);
      await pumpEventQueue();
      expect(server.asked, ['revoke']);

      server.revokeHeld!.complete();
      expect((await building).authenticated, isFalse);
      await pumpEventQueue();
      expect(server.asked, ['revoke', 'session']);
    });

    test('a session read reads nothing, and answers for what the client '
        'holds', () async {
      final page = await _annLeftUnheard();
      final container = page.container;
      final server = page.server;

      server.revokeHeld = Completer<void>();
      final read = _auth(container).refreshSession();
      await pumpEventQueue();
      final building = _builtAgain(container);
      await pumpEventQueue();
      expect(server.asked, ['revoke']);

      server.revokeHeld!.complete();
      expect(await read, SessionRecheck.unanswered);
      expect((await building).authenticated, isFalse);
      await pumpEventQueue();
      expect(server.asked, ['revoke', 'session']);
    });

    test('a client closed meanwhile asks the server nothing more and '
        'throws nothing, by any road', () async {
      final page = await _annLeftUnheard();
      final container = page.container;
      final server = page.server;

      server.revokeHeld = Completer<void>();
      final read = _auth(container).refreshSession();
      final signing = _auth(container).login(username: 'ben', password: 'pw');
      final singleSignOn = _auth(container).loginWithOidc(_sso);
      container.invalidate(authControllerProvider);
      container.read(authControllerProvider);
      await pumpEventQueue();
      expect(server.asked, ['revoke']);

      container.dispose();
      server.revokeHeld!.complete();
      expect(await read, SessionRecheck.left);
      expect(await signing, isFalse);
      expect(await singleSignOn, isFalse);
      await pumpEventQueue();
      expect(server.asked, ['revoke']);
      expect(_marked(page.storage), isFalse);
    });

    test('a client closed while a build waits for a sign-in to land asks '
        'the server nothing more', () async {
      final page = await _annLeftUnheard();
      final container = page.container;
      final server = page.server;

      server
        ..revokeRefusal = _broken
        ..signInRefusal = _broken
        ..loginGate = Completer<void>();
      final signing = _auth(container).login(username: 'ben', password: 'pw');
      await pumpEventQueue();
      container.invalidate(authControllerProvider);
      container.read(authControllerProvider);
      await pumpEventQueue();
      expect(server.asked, ['revoke', 'sign-in']);

      container.dispose();
      server.loginGate!.complete();
      await expectLater(signing, throwsA(_broken));
      await pumpEventQueue();
      expect(server.asked, ['revoke', 'sign-in']);
      expect(_marked(page.storage), isTrue);
    });
  });

  group('another tab of the browser, still signed in on the cookie a '
      'revoke is owed for', () {
    /// Ann signed out in one tab, the server out of reach; her other tab,
    /// signed in on the same cookie, is the second this answers.
    Future<(_Page, ProviderContainer)> twoTabs({required bool back}) async {
      final storage = _Storage();
      final server = _Server(sessionState: _anns);
      final other = _tab(server, storage);
      await other.read(authControllerProvider.future);
      final page = await _annLeftUnheard(
        back: back,
        storage: storage,
        of: server,
      );
      expect(_session(other), 'ann');
      return (page, other);
    }

    test('delivers it at its next session read, and is signed out by the '
        'answer as by any sign-out of the server\'s', () async {
      final (page, other) = await twoTabs(back: true);

      expect(await _auth(other).refreshSession(), SessionRecheck.left);
      expect(page.server.asked, ['revoke', 'session']);
      expect(_session(other), 'out');
      expect(_marked(page.storage), isFalse);
    });

    test('keeps its session while the server is out of reach: only the '
        'server\'s answer signs it out', () async {
      final (page, other) = await twoTabs(back: false);

      expect(await _auth(other).refreshSession(), SessionRecheck.unanswered);
      expect(page.server.asked, ['revoke']);
      expect(_session(other), 'ann');
      expect(_marked(page.storage), isTrue);
    });
  });

  test('a revoke settled by a sign-in in another tab is not delivered by '
      'the tab that owed it: the cookie is that sign-in\'s now', () async {
    final page = await _annLeftUnheard();
    final server = page.server;

    // Another tab, whose own delivery fails, signs Ben in.
    server.revokeRefusal = _broken;
    final other = _tab(server, page.storage);
    other.read(authControllerProvider);
    await pumpEventQueue();
    expect(await _auth(other).login(username: 'ben', password: 'pw'), isTrue);
    await pumpEventQueue();
    expect(_marked(page.storage), isFalse);

    server
      ..revokeRefusal = null
      ..asked.clear();
    expect((await _builtAgain(page.container)).user?.username, 'ben');
    expect(server.asked, isNot(contains('revoke')));
    expect(server.sessionState.user?.username, 'ben');
  });

  group('a revoke the server holds no session for', () {
    test('is delivered by its plain answer: a server that never heard of '
        'the session, at the same origin', () async {
      final page = await _annLeftUnheard();
      page.container.dispose();

      final another = _Server();
      final reloaded = _tab(another, page.storage);
      final built = await reloaded.read(authControllerProvider.future);
      expect(another.asked, ['revoke', 'session']);
      expect(built.authenticated, isFalse);
      expect(_marked(page.storage), isFalse);
    });

    test('is delivered by a refusal that says so in the server\'s own '
        'words', () async {
      final page = await _annLeftUnheard();
      page.server
        ..sessionState = const SessionState(authenticated: false)
        ..revokeRefusal = const WaxDeckApiException(
          code: 'unauthenticated',
          message: 'no valid session or token was presented',
          statusCode: 401,
        );

      final built = await _builtAgain(page.container);
      expect(page.server.asked, ['revoke', 'session']);
      expect(built.authenticated, isFalse);
      expect(_marked(page.storage), isFalse);
    });

    test('is not delivered by any other refusal', () async {
      final page = await _annLeftUnheard();
      page.server.revokeRefusal = _broken;

      await _buildsAgain(page.container);
      expect(page.server.asked, isNotEmpty);
      expect(page.server.asked, everyElement('revoke'));
      expect(page.container.read(authControllerProvider).error, _broken);
      expect(_session(page.container), 'out');
      expect(_marked(page.storage), isTrue);
    });
  });

  group('browser storage that will not hold the mark', () {
    test('denied outright: it is held for the page, whose next build '
        'still delivers it first', () async {
      final page = await _annLeftUnheard(storage: _Storage()..denied = true);

      expect(page.container.read(owedRevokeProvider).owed, isTrue);
      final built = await _builtAgain(page.container);
      expect(page.server.asked, ['revoke', 'session']);
      expect(built.authenticated, isFalse);
      expect(page.container.read(owedRevokeProvider).owed, isFalse);
    });

    test('taking a write and keeping nothing: it is held for the page '
        'too', () async {
      final page = await _annLeftUnheard(storage: _Storage()..forgetful = true);

      expect(_marked(page.storage), isFalse);
      final built = await _builtAgain(page.container);
      expect(page.server.asked, ['revoke', 'session']);
      expect(built.authenticated, isFalse);
    });

    test('unreadable at a start: the start reads the session as it always '
        'has, and throws nothing', () async {
      final server = _Server(sessionState: _anns);
      final container = _tab(server, _Storage()..denied = true);

      final built = await container.read(authControllerProvider.future);
      expect(server.asked, ['session']);
      expect(built.user?.username, 'ann');
    });
  });

  test('with no browser storage, as on native, a sign-out the server did '
      'not hear owes nothing and no revoke is sent after it', () async {
    final server = _Server(sessionState: _anns);
    final container = _tab(server, null);
    await container.read(authControllerProvider.future);

    server.down = true;
    await _auth(container).logout();
    expect(_session(container), 'out');
    expect(container.read(owedRevokeProvider).owed, isFalse);

    server
      ..down = false
      ..asked.clear();
    await _builtAgain(container);
    await _auth(container).refreshSession();
    expect(server.asked, isNot(contains('revoke')));
  });
}
