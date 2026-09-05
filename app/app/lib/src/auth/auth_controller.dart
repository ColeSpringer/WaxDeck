import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../artwork/artwork_palette.dart';
import '../artwork/artwork_providers.dart';
import '../connect/remote_session.dart';
import '../providers.dart';
import '../queue/queue_persistence.dart';
import '../search/search_controller.dart';
import 'credential_store.dart';

/// The pre-auth server probe: first-run setup state and whether open
/// signup is on. Probed only while unauthenticated;
/// [AuthController.bootstrap] invalidates it once setup completes so a
/// later logout lands on the login screen. Behind the connect gate the
/// probe never fires at all: there is no server to ask, and Riverpod's
/// retry ladder would hammer a localhost nobody chose.
final bootstrapStatusProvider = FutureProvider<BootstrapStatus>((ref) {
  if (!ref.watch(serverConfiguredProvider)) {
    return const BootstrapStatus(required: false);
  }
  return ref.watch(repositoryProvider).bootstrapStatus();
});

/// Whether the server is waiting for its first administrator.
final bootstrapRequiredProvider = FutureProvider<bool>(
  (ref) async => (await ref.watch(bootstrapStatusProvider.future)).required,
);

/// Whether open self-signup is on, for the login screen's affordance
/// label. Invite-token signups work regardless.
final signupEnabledProvider = FutureProvider<bool>(
  (ref) async =>
      (await ref.watch(bootstrapStatusProvider.future)).signupEnabled,
);

/// Session state for the whole app.
///
/// Builds by probing the server session. On native the persisted bearer
/// token is restored into the client first, so a previous login survives
/// a restart; on web a live cookie serves the same purpose. [login] and
/// friends flip the state on success and rethrow the structured API error
/// on failure so forms can show it.
class AuthController extends AsyncNotifier<SessionState> {
  @override
  Future<SessionState> build() async {
    // No server, no probe: an unconfigured native build answers signed
    // out at once and the router's redirect owns the connect screen.
    if (!ref.watch(serverConfiguredProvider)) {
      return const SessionState(authenticated: false);
    }
    final repo = ref.watch(repositoryProvider);
    final store = ref.watch(credentialStoreProvider);
    var restored = false;
    if (!kIsWeb) {
      final stored = await store.readToken();
      if (stored != null) {
        repo.authToken = stored;
        restored = true;
      }
    }
    final session = await repo.getSession();
    if (restored) {
      if (session.authenticated) {
        // Fire and forget: rotate the long-lived token on cold start. The
        // old token stays valid through a short server-side grace window,
        // so racing in-flight requests is safe.
        unawaited(_rotateStoredToken(repo, store));
      } else {
        // The stored token is dead (revoked or expired); drop it.
        repo.authToken = null;
        await store.clearToken();
      }
    }
    return session;
  }

  Future<void> _rotateStoredToken(
    WaxDeckRepository repo,
    CredentialStorePort store,
  ) async {
    try {
      final rotated = await repo.refreshToken();
      await store.writeToken(rotated.token);
    } on WaxDeckApiException catch (e) {
      if (e.statusCode == 401) {
        // The session died between the probe and the rotation (revoked
        // server side). Clearing just the token would leave the UI
        // signed in over a dead credential, failing on its next call,
        // so drop the whole local session and land on the login screen.
        await signOutLocally();
      }
      // Any other failure keeps the current token; it still works.
    }
  }

  /// Re-reads the session after the server said this account's rights
  /// moved.
  ///
  /// The previous session stands while the read is in flight, and a
  /// failed read leaves it standing too. Load-bearing: the router's
  /// redirect reads `authenticated`, so a bare loading frame here would
  /// bounce a signed-in visitor to the login screen for the length of
  /// one request.
  Future<void> refreshSession() async {
    final repo = ref.read(repositoryProvider);
    try {
      state = AsyncData(await repo.getSession());
    } on WaxDeckApiException {
      // Nothing to show and nothing to unwind: the 401 path is the
      // session layer's own, and any other failure just means the
      // client keeps believing what it last read.
    }
  }

  Future<void> _adopt(LoginResult result) async {
    if (!kIsWeb) {
      await ref.read(credentialStoreProvider).writeToken(result.token);
    }
    state = AsyncData(SessionState(authenticated: true, user: result.user));
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    final result = await ref
        .read(repositoryProvider)
        .login(
          username: username,
          password: password,
          deviceName: waxDeckDeviceName,
        );
    await _adopt(result);
  }

  /// Creates the first administrator and lands signed in.
  Future<void> bootstrap({
    required String username,
    required String password,
    String? displayName,
  }) async {
    final result = await ref
        .read(repositoryProvider)
        .bootstrap(
          username: username,
          password: password,
          displayName: displayName,
        );
    ref.invalidate(bootstrapStatusProvider);
    await _adopt(result);
  }

  /// Runs the platform-appropriate OIDC flow for [provider]. On web this
  /// navigates the browser away and never flips the state here; the SPA
  /// reloads authenticated. On native it completes the exchange and signs
  /// in. Rethrows structured API errors and [TimeoutException] for the
  /// login form to show.
  Future<void> loginWithOidc(OidcProvider provider) async {
    final flow = ref.read(oidcFlowProvider);
    if (kIsWeb) {
      await flow.startWeb(provider);
      return;
    }
    final result = switch (defaultTargetPlatform) {
      TargetPlatform.android => await flow.loginWithDeepLink(
        provider,
        deviceName: waxDeckDeviceName,
      ),
      _ => await flow.loginWithLoopback(
        provider,
        deviceName: waxDeckDeviceName,
      ),
    };
    await _adopt(result);
  }

  Future<void> logout() async {
    try {
      await ref.read(repositoryProvider).logout();
    } on WaxDeckApiException {
      // Losing the server-side revoke is acceptable; drop the local session.
    }
    await signOutLocally();
  }

  /// Drops the local session without calling the server, for when the
  /// server side is already gone (the current session was revoked).
  Future<void> signOutLocally() async {
    ref.read(repositoryProvider).authToken = null;
    if (!kIsWeb) {
      await ref.read(credentialStoreProvider).clearToken();
    }
    // The queue is the one piece of local state a signed-out install
    // would otherwise put back in front of whoever signs in next, since
    // the next launch offers to resume it by name.
    await forgetQueueOnSignOut(ref);
    // Artwork is the other: cached covers and the pins beside the
    // downloads outlive the session that was allowed to see them.
    await ref.read(artworkStoreProvider).forgetEverything();
    ref.read(paletteCacheProvider).clear();
    // And the recent searches, which are the same kind of thing: strings
    // the departing listener typed, naming things in their library, in a
    // browser store the next account on this machine can read back.
    await forgetSearchesOnSignOut(ref);
    // A session on another endpoint stays playing - stepping away from a
    // cast has never silenced the room and signing out is no different -
    // but this client stops controlling it, so the next account does not
    // inherit a deck bar pointed at someone else's speaker.
    releaseRemoteOnSignOut(ref);
    // The rest of the per-device settings deliberately stand. A
    // collapsed sidebar describes the machine rather than the account,
    // and wiping it would make signing out a factory reset of a shared
    // desktop. Which side of that line a preference falls on is a
    // question each one answers for itself.
    state = const AsyncData(SessionState(authenticated: false));
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, SessionState>(AuthController.new);

/// Who is signed in, as a value that changes exactly when the account
/// does.
///
/// The session state carries a whole user and a probe's loading and
/// error states, so a provider watching it rebuilds on a refresh that
/// changed nothing about who this is. Anything that has to reset per
/// account (the notifications bell's session-scoped list) watches this
/// instead. Null while signed out.
final signedInAccountProvider = Provider<String?>(
  (ref) => ref.watch(authControllerProvider).value?.user?.id,
);
