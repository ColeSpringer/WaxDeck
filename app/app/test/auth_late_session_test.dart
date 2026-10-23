import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

const _ada = WaxDeckUser(id: 'us-ada', username: 'ada', roles: ['admin']);
const _bo = WaxDeckUser(id: 'us-bo', username: 'bo', roles: ['user']);

/// A server whose session reads can be held, and whose sign-ins answer
/// whoever [next] names.
class _HeldSessions extends FakeRepository {
  WaxDeckUser next = _ada;

  /// Holds the session reads while set, each answering as of when it was
  /// asked.
  Completer<void>? gate;

  @override
  Future<LoginResult> login({
    required String username,
    required String password,
    String? deviceName,
  }) async {
    sessionState = SessionState(authenticated: true, user: next);
    return LoginResult(user: next, token: 'token-${next.id}');
  }

  @override
  Future<SessionState> getSession() async {
    final asked = sessionState;
    final held = gate;
    await held?.future;
    return asked;
  }
}

/// A session read still out when the account signs out and another signs
/// in answers for the account it was asked about: it does not take the
/// app back to it.
void main() {
  test('a late session read does not undo a sign-out and a sign-in', () async {
    final repo = _HeldSessions();
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    final auth = container.read(authControllerProvider.notifier);

    // Ada signs in; the session read her sign-in starts is held.
    final held = repo.gate = Completer<void>();
    await auth.login(username: 'ada', password: 'pw');
    expect(container.read(authControllerProvider).value?.user?.id, 'us-ada');

    // Ada signs out and Bo signs in, both before that read answers, and
    // Bo's own read answers at once.
    await auth.logout();
    repo
      ..gate = null
      ..next = _bo;
    await auth.login(username: 'bo', password: 'pw');
    await pumpEventQueue();
    expect(container.read(authControllerProvider).value?.user?.id, 'us-bo');

    held.complete();
    await pumpEventQueue();
    expect(
      container.read(authControllerProvider).value?.user?.id,
      'us-bo',
      reason: 'the read asked about Ada answered after Bo signed in',
    );
  });
}
