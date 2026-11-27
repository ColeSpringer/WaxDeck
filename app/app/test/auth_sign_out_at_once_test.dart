import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/auth/oidc_flow.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_persistence.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import 'app_host.dart';
import 'fakes.dart';

/// A sign-out shows the signed-out screen at once, whatever sign-in is out
/// at the server. That sign-in, sent before the press, is undone when it
/// lands: on native its session is ended by its own token, which is kept
/// nowhere.

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

const _sso = OidcProvider(
  id: 'corp',
  displayName: 'Corp SSO',
  startUrl: 'http://server.test/api/v1/auth/oidc/start?provider=corp',
);

/// A server that says which bearer each sign-out presented, and answers a
/// session read presenting a sign-in's token for whoever it signed in.
class _Server extends FakeRepository {
  _Server()
    : super(
        sessionState: const SessionState(authenticated: true, user: _ann),
        items: [testItem('tr-A')],
      );

  final presented = <String?>[];

  @override
  Future<void> logout() {
    presented.add(authToken);
    return super.logout();
  }

  @override
  Future<SessionState> getSession() async => switch ((authToken, signsIn)) {
    ('test-token', final user?) => SessionState(
      authenticated: true,
      user: user,
    ),
    _ => await super.getSession(),
  };
}

/// A keychain that keeps every token it is asked to write.
class _Keychain extends InMemoryCredentialStore {
  final written = <String>[];

  @override
  Future<void> writeToken(String value) {
    written.add(value);
    return super.writeToken(value);
  }
}

/// An identity provider that comes back with the one-time code only when
/// told to.
class _Browser implements UrlOpenerPort, DeepLinkPort {
  final _links = StreamController<Uri>.broadcast();
  var opened = 0;

  void comeBack() => _links.add(Uri.parse('waxdeck://auth?code=one-time'));

  @override
  Future<void> open(String url) async => opened++;

  @override
  Stream<Uri> get uriLinkStream => _links.stream;
}

typedef _Device = ({
  ProviderContainer container,
  _Server server,
  _Keychain keychain,
  _Browser browser,
});

/// A device signed in as Ann, on a token of hers.
_Device _annsDevice() {
  final server = _Server();
  final keychain = _Keychain()..token = 'token-ann';
  final browser = _Browser();
  final container = appContainer(
    repo: server,
    credentials: keychain,
    settings: MemoryClientSettingsStore(),
    extra: [
      urlOpenerProvider.overrideWithValue(browser),
      deepLinkProvider.overrideWithValue(browser),
      queueSaveDebounceProvider.overrideWithValue(Duration.zero),
    ],
  );
  return (
    container: container,
    server: server,
    keychain: keychain,
    browser: browser,
  );
}

AuthController _auth(ProviderContainer container) =>
    container.read(authControllerProvider.notifier);

final _form = find.bySemanticsIdentifier(SemanticsIds.loginSubmit);
final _home = find.bySemanticsIdentifier(SemanticsIds.homeScreen);

/// Pumps frames until [finder] shows, for at most [within].
Future<bool> _shows(
  WidgetTester tester,
  Finder finder, {
  Duration within = const Duration(seconds: 1),
}) async {
  for (var waited = Duration.zero; waited < within;) {
    if (finder.evaluate().isNotEmpty) return true;
    await tester.pump(const Duration(milliseconds: 50));
    waited += const Duration(milliseconds: 50);
  }
  return finder.evaluate().isNotEmpty;
}

/// Ann's device in the whole app, her home up.
Future<_Device> _annsHome(WidgetTester tester) async {
  final device = _annsDevice();
  await mountHost(tester, const WaxDeckApp(), container: device.container);
  expect(await _shows(tester, _home), isTrue);
  return device;
}

void main() {
  testWidgets('pressed while a password sign-in is out, shows the signed-out '
      'screen at once; the sign-in, landing after, is ended by its own token '
      'and never stored', (tester) async {
    final device = await _annsHome(tester);
    final server = device.server
      ..signsIn = _ben
      ..loginGate = Completer<void>();

    bool? took;
    unawaited(
      _auth(device.container)
          .login(username: 'ben', password: 'pw')
          .then((answer) => took = answer),
    );
    await tester.pump();
    final ann = server.authToken;
    expect(ann, isNotNull);
    unawaited(_auth(device.container).logout());

    expect(await _shows(tester, _form), isTrue);
    expect(took, isNull);
    expect(server.presented, [ann]);
    expect(server.authToken, isNull);
    expect(device.keychain.token, isNull);

    server.loginGate!.complete();
    await tester.pump();
    await tester.pump();
    expect(took, isFalse);
    expect(server.tokenLogouts, ['test-token']);
    expect(server.authToken, isNull);
    expect(device.keychain.token, isNull);
    expect(device.keychain.written, isNot(contains('test-token')));
    expect(_form, findsOneWidget);
    expect(device.container.read(authControllerProvider).value?.user, isNull);
  });

  testWidgets('pressed while a single sign-on round trip is out, shows the '
      'signed-out screen at once; the code that comes back after is never '
      'redeemed', (tester) async {
    final device = await _annsHome(tester);
    final server = device.server;

    bool? took;
    unawaited(
      _auth(device.container)
          .loginWithOidc(_sso)
          .then((answer) => took = answer),
    );
    await tester.pump();
    expect(device.browser.opened, 1);
    unawaited(_auth(device.container).logout());

    expect(await _shows(tester, _form), isTrue);
    expect(took, isNull);

    device.browser.comeBack();
    await tester.pump();
    await tester.pump();
    expect(took, isFalse);
    expect(server.oidcExchangeCalls, isEmpty);
    expect(server.authToken, isNull);
    expect(device.keychain.token, isNull);
    expect(_form, findsOneWidget);
  });

  testWidgets('pressed while a single sign-on exchange is out, shows the '
      'signed-out screen at once; the session it makes is ended by its own '
      'token and never stored', (tester) async {
    final device = await _annsHome(tester);
    final server = device.server..oidcExchangeGate = Completer<void>();

    bool? took;
    unawaited(
      _auth(device.container)
          .loginWithOidc(_sso)
          .then((answer) => took = answer),
    );
    await tester.pump();
    device.browser.comeBack();
    await tester.pump();
    expect(server.oidcExchangeCalls, hasLength(1));
    unawaited(_auth(device.container).logout());

    expect(await _shows(tester, _form), isTrue);
    expect(took, isNull);

    server.oidcExchangeGate!.complete();
    await tester.pump();
    await tester.pump();
    expect(took, isFalse);
    expect(server.tokenLogouts, ['oidc-token']);
    expect(server.authToken, isNull);
    expect(device.keychain.token, isNull);
    expect(device.keychain.written, isNot(contains('oidc-token')));
    expect(_form, findsOneWidget);
  });

  test('a sign-in sent after the press is not undone by it', () async {
    final device = _annsDevice();
    final container = device.container;
    await container.read(authControllerProvider.future);

    await _auth(container).logout();
    device.server.signsIn = _ben;
    expect(
      await _auth(container).login(username: 'ben', password: 'pw'),
      isTrue,
    );
    await pumpEventQueue();
    expect(container.read(authControllerProvider).value?.user?.username, 'ben');
    expect(device.server.tokenLogouts, isEmpty);
    expect(device.keychain.token, 'test-token');
  });

  test('a sign-in out while the server ends the session showing, no sign-out '
      'pressed, signs in on its own token', () async {
    final device = _annsDevice();
    final container = device.container;
    await container.read(authControllerProvider.future);
    final server = device.server
      ..signsIn = _ben
      ..loginGate = Completer<void>();

    final signing = _auth(container).login(username: 'ben', password: 'pw');
    await pumpEventQueue();
    server.sessionState = const SessionState(authenticated: false);
    expect(await _auth(container).refreshSession(), SessionRecheck.left);
    expect(server.authToken, isNull);

    server.loginGate!.complete();
    expect(await signing, isTrue);
    await pumpEventQueue();
    expect(container.read(authControllerProvider).value?.user?.username, 'ben');
    expect(server.authToken, 'test-token');
    expect(device.keychain.token, 'test-token');
    expect(server.tokenLogouts, isEmpty);
  });
}
