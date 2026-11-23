@TestOn('browser')
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import 'app_host.dart';
import 'fakes.dart';

const _ann = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDACCANN',
  username: 'ann',
  roles: ['user'],
);
const _anns = SessionState(authenticated: true, user: _ann);
const _bens = SessionState(
  authenticated: true,
  user: WaxDeckUser(
    id: 'us-01JZX5N8QW3F4V9T2B7KDACCBEN',
    username: 'ben',
    roles: ['user'],
  ),
);

/// Ann, once an administrator let her upload.
const _annsNow = SessionState(
  authenticated: true,
  user: WaxDeckUser(
    id: 'us-01JZX5N8QW3F4V9T2B7KDACCANN',
    username: 'ann',
    roles: ['user'],
    uploadEnabled: true,
  ),
);

/// A store that says what was asked of it.
class _Recorded extends InMemoryCredentialStore {
  final calls = <String>[];

  @override
  Future<String?> readToken() {
    calls.add('readToken');
    return super.readToken();
  }

  @override
  Future<void> writeToken(String value) {
    calls.add('writeToken');
    return super.writeToken(value);
  }

  @override
  Future<void> clearToken() {
    calls.add('clearToken');
    return super.clearToken();
  }

  @override
  Future<String?> readSession() {
    calls.add('readSession');
    return super.readSession();
  }

  @override
  Future<void> writeSession(String value) {
    calls.add('writeSession');
    return super.writeSession(value);
  }

  @override
  Future<void> clearSession() {
    calls.add('clearSession');
    return super.clearSession();
  }
}

/// A server whose session reads fail while [sessionError] is set.
class _Server extends FakeRepository {
  _Server() : super(sessionState: _anns);

  WaxDeckApiException? sessionError;

  @override
  Future<SessionState> getSession() async {
    if (sessionError case final error?) throw error;
    return super.getSession();
  }
}

/// The web half of `auth_offline_start_test.dart`, which holds a session
/// with no token to this on the VM: `kIsWeb` is false there, so only a
/// browser can say that the build whose credential is a cookie never
/// touches the store, whatever the store holds.
void main() {
  late _Recorded store;
  late _Server server;

  /// A browser's client, its first session read failing with
  /// [sessionError] when one is given: set before anything listens,
  /// because here the build reaches that read without a pause.
  ProviderContainer start({WaxDeckApiException? sessionError}) {
    // Something a browser never wrote, to be found if anything looked.
    store = _Recorded()
      ..token = 'token-ann'
      ..session = rememberedRecord('token-ann', _anns.toStored());
    server = _Server()..sessionError = sessionError;
    final container = appContainer(
      repo: server,
      credentials: store,
      settings: MemoryClientSettingsStore(),
    );
    final watched = container.listen(authControllerProvider, (_, _) {});
    addTearDown(watched.close);
    return container;
  }

  AuthController auth(ProviderContainer container) =>
      container.read(authControllerProvider.notifier);

  SessionState? session(ProviderContainer container) =>
      container.read(authControllerProvider).value;

  test('a start, a session read, a sign-out and a sign-in remember '
      'nothing and read nothing remembered', () async {
    final container = start();
    await pumpEventQueue();
    expect(session(container), _anns);
    expect(auth(container).unconfirmed, isFalse);

    server.sessionState = _annsNow;
    expect(await auth(container).refreshSession(), SessionRecheck.stands);
    await auth(container).logout();
    await auth(container).login(username: 'admin', password: 'correct-horse');
    await pumpEventQueue();
    expect(session(container)?.authenticated, isTrue);

    expect(store.calls, isEmpty);
    expect(server.refreshCalls, 0);
  });

  test('a session that turns out to be another account\'s is a sign-out '
      'and a sign-in that touch nothing kept', () async {
    final container = start();
    await pumpEventQueue();
    expect(session(container), _anns);

    // Another tab signed in over this browser's cookie.
    server.sessionState = _bens;
    expect(await auth(container).refreshSession(), SessionRecheck.left);
    await pumpEventQueue();

    expect(session(container), _bens);
    expect(auth(container).unconfirmed, isFalse);
    expect(store.calls, isEmpty);
    expect(server.refreshCalls, 0);
  });

  test('a start out of the server\'s reach opens on nothing '
      'remembered', () async {
    final container = start(
      sessionError: const WaxDeckApiException(
        code: 'transport',
        message: 'connection refused',
      ),
    );
    await pumpEventQueue();

    expect(session(container), isNull);
    expect(auth(container).unconfirmed, isFalse);
    expect(store.calls, isEmpty);
  });
}
