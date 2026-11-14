import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../artwork/artwork_palette.dart';
import '../artwork/artwork_providers.dart';
import '../connect/remote_session.dart';
import '../l10n/off_tree.dart';
import '../providers.dart';
import '../queue/queue_persistence.dart';
import '../radio/radio_controller.dart';
import '../search/search_controller.dart';
import 'credential_store.dart';
import 'oidc_flow.dart';

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
}, retry: retryUnlessRefused);

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

/// What a session read made of the account the client held when it was
/// asked.
enum SessionRecheck {
  /// The server answered for that account: it stands.
  stands,

  /// That account is gone: the server answered for nobody or for another
  /// account, or the client moved on before the answer came.
  left,

  /// No answer came: the session is as much in doubt as it was.
  unanswered,
}

/// Session state for the whole app.
///
/// Builds by probing the server session. On native the persisted bearer
/// token is restored into the client first, so a previous login survives
/// a restart; on web a live cookie serves the same purpose. [login] and
/// friends flip the state on success and rethrow the structured API error
/// on failure so forms can show it.
class AuthController extends AsyncNotifier<SessionState> {
  /// Moves at every sign-in, sign-out and build: a session read asked
  /// before one answers for the account, or the build, it was asked of,
  /// and is dropped. `ref.mounted` cannot say so: the notifier outlives a
  /// build, and its `ref` is always the newest one's.
  var _account = 0;

  /// Above zero while an account is on its way out: from the first step of
  /// a sign-out or a swap until the session stops naming it.
  var _leaving = 0;

  /// The sign-out under way, which another joins rather than cleaning up
  /// again; null once it is over.
  Future<void>? _signingOut;

  @override
  Future<SessionState> build() async {
    _account++;
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
        // The stored token is dead (revoked, expired, or its account
        // disabled while the app was closed): it goes, and so does what
        // that account left here.
        repo.authToken = null;
        await store.clearToken();
        await _forgetAccount();
      }
    }
    // An account arriving lets go of what the last one's leaving held, as
    // a sign-in does: a build can land in the middle of a swap and drop
    // the tail that would have.
    if (session.authenticated) {
      ref.read(playbackHeldProvider.notifier).release();
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
      if (e.code == 'unauthenticated') {
        // The session died between the probe and the rotation (revoked
        // server side). Clearing just the token would leave the UI
        // signed in over a dead credential, failing on its next call,
        // so drop the whole local session and land on the login screen.
        await signOutLocally();
      }
      // Any other failure keeps the current token; it still works. A 401
      // in no words of the server's is something in front of it.
    }
  }

  /// Re-reads the session after the server said this account's rights
  /// moved or its session ended, or, in a browser, the event socket came
  /// back from a drop across which another account may have signed in.
  ///
  /// The previous session stands while the read is in flight, and a read
  /// that never reached the server leaves it standing too: only the
  /// server's answer signs anybody out. Load-bearing: the router's
  /// redirect reads `authenticated`, so a bare loading frame here would
  /// bounce a signed-in visitor to the login screen for the length of
  /// one request.
  ///
  /// A session that turns out to be another account's is a sign-out and a
  /// sign-in: the screens still up read what they show as the last
  /// account, so the router takes them down, and what only they read goes
  /// with them, before the next account's session shows.
  ///
  /// Answers what the read made of the account the client held when it
  /// was asked; one the client moved on from meanwhile (a sign-in, a
  /// sign-out, a new build) answers for what the client holds now. While
  /// an account is leaving, it has left, and nothing is read: a read then
  /// could start its leaving a second time.
  Future<SessionRecheck> refreshSession() async {
    if (_leaving > 0) return SessionRecheck.left;
    final repo = ref.read(repositoryProvider);
    final asked = _account;
    final askedFor = state.value;
    try {
      final session = await repo.getSession();
      // A sign-out, a new account or a new build can end this controller
      // mid-read, or land while it is out: either way the answer is stale.
      if (!ref.mounted || asked != _account) return _holding(askedFor);
      if (!session.authenticated) {
        // The server ended the session (the account was disabled, or this
        // device revoked), which is a sign-out like any other.
        await signOutLocally();
        return SessionRecheck.left;
      }
      if (session.user?.id != state.value?.user?.id) {
        // Another account's session in this one's place: a tab that signed
        // in over this browser's cookie. Its leftovers go before it shows.
        final adopting = ++_account;
        _leaving++;
        try {
          await _forgetAccount();
        } finally {
          _leaving--;
        }
        if (!ref.mounted || adopting != _account) return _holding(askedFor);
        final screens = ref.exists(signedInScreensProvider)
            ? ref.read(signedInScreensProvider).gone
            : null;
        state = const AsyncData(SessionState(authenticated: false));
        // No timeout, though a hidden tab holds this until shown: the next
        // session must not land on screens holding the last account's reads.
        if (screens != null) await screens;
        if (!ref.mounted || adopting != _account) return _holding(askedFor);
        ref.read(playbackHeldProvider.notifier).release();
        state = AsyncData(session);
        return SessionRecheck.left;
      }
      state = AsyncData(session);
      return SessionRecheck.stands;
    } on WaxDeckApiException catch (error) {
      if (!ref.mounted || asked != _account) return _holding(askedFor);
      // The server answers this read `authenticated: false` for a dead
      // session; a refusal in its own words (`unauthenticated`) says the
      // same, and signs out too. A 401 in no words of its own is something
      // in front of the server, a proxy's sign-in, and like any other
      // failure keeps what the client last read.
      if (error.code != 'unauthenticated') return SessionRecheck.unanswered;
      await signOutLocally();
      return SessionRecheck.left;
    }
  }

  /// Whether the client still holds the session it held when it [asked],
  /// signed in as the same user, or as none when it named none: what a read
  /// it moved on from answers. An account leaving is not held; while a new
  /// build reads the session itself, that is not known yet.
  SessionRecheck _holding(SessionState? asked) {
    if (!ref.mounted || _leaving > 0) return SessionRecheck.left;
    final held = state;
    if (held.isLoading) return SessionRecheck.unanswered;
    final session = held.value;
    return asked != null &&
            asked.authenticated &&
            session != null &&
            session.authenticated &&
            session.user?.id == asked.user?.id
        ? SessionRecheck.stands
        : SessionRecheck.left;
  }

  Future<void> _adopt(LoginResult result) async {
    _account++;
    ref.read(playbackHeldProvider.notifier).release();
    if (!kIsWeb) {
      await ref.read(credentialStoreProvider).writeToken(result.token);
    }
    state = AsyncData(SessionState(authenticated: true, user: result.user));
    // The sign-in answer names the account and no more; the server's own
    // state (read-only) arrives with the session.
    unawaited(refreshSession());
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
        page: _loopbackPage(),
        deviceName: waxDeckDeviceName,
      ),
    };
    await _adopt(result);
  }

  /// The browser tab is drawn outside the element tree.
  LoopbackPage _loopbackPage() {
    final copy = ref.read(offTreeL10nProvider);
    return (heading: copy.authLoopbackTitle, line: copy.authLoopbackMessage);
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
  /// server side is already gone (the current session was revoked). Asked
  /// while one is under way, it is that one, and fails if that one does.
  Future<void> signOutLocally() => _signingOut ??= _signOut().whenComplete(() {
    _signingOut = null;
  });

  Future<void> _signOut() async {
    _account++;
    _leaving++;
    try {
      ref.read(repositoryProvider).authToken = null;
      if (!kIsWeb) {
        await ref.read(credentialStoreProvider).clearToken();
      }
      await _forgetAccount();
      state = const AsyncData(SessionState(authenticated: false));
    } finally {
      _leaving--;
    }
  }

  /// What an account leaves on this client, dropped on every road out of
  /// it: a sign-out, a session the server ended, another account's
  /// session in its place, a stored one that died while the app was
  /// closed. Never throws: none of it is a reason to keep a session.
  Future<void> _forgetAccount() async {
    // First, so nothing started from the screens still up can outlive
    // what follows; the next account to arrive releases it.
    ref.read(playbackHeldProvider.notifier).hold();
    // Whose session this was, when the controller knows: a stored token
    // found dead at launch names nobody.
    final account = state.value?.user?.id;
    // The queue is the one piece of local state a signed-out install
    // would otherwise put back in front of whoever signs in next, since
    // the next launch offers to resume it by name.
    await forgetQueueOnSignOut(ref);
    // A station goes too: the relay scrobbles it and counts its listening
    // time for the account that tuned it, for as long as it plays. Only a
    // controller that exists can hold one, and the account leaves even if
    // the engine will not let go.
    if (ref.exists(radioPlaybackProvider)) {
      try {
        await ref.read(radioPlaybackProvider.notifier).stop();
      } on Object catch (error) {
        debugPrint('sign-out: the station did not stop: $error');
      }
    }
    // Artwork is the other: cached covers and the pins beside the
    // downloads outlive the session that was allowed to see them.
    try {
      await ref.read(artworkStoreProvider).forgetEverything();
    } on Object catch (error) {
      debugPrint('sign-out: the artwork cache did not clear: $error');
    }
    ref.read(paletteCacheProvider).clear();
    // And the account's recent searches, which are the same kind of
    // thing: strings it typed, naming things in its library. Where the
    // account is not known they stay filed under it, and no other
    // account reads them.
    if (account != null) await forgetSearchesOnSignOut(ref, account);
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
  }
}

/// A refusal is final here in the sharpest way: a rejected credential
/// is not a dropped connection, and re-asking it ten times over
/// thirteen seconds is a lockout counter climbing while the login form
/// shows a spinner. Everything that is not the server saying no keeps
/// the ladder - the session probe is exactly the read a reconnecting
/// client wants retried.
final authControllerProvider =
    AsyncNotifierProvider<AuthController, SessionState>(
      AuthController.new,
      retry: retryUnlessRefused,
    );

/// Alive while the signed-in screens are mounted: the scope the router
/// builds over them watches it.
final signedInScreensProvider = Provider.autoDispose<SignedInScreens>((ref) {
  final screens = SignedInScreens._();
  ref.onDispose(screens._gone.complete);
  return screens;
});

class SignedInScreens {
  SignedInScreens._();

  final _gone = Completer<void>();

  /// Completes once the screens are unmounted and the providers only they
  /// listened to are disposed: Riverpod disposes those in the same pass.
  Future<void> get gone => _gone.future;
}

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

/// Whether the server says it is read-only, as of the last session read.
///
/// The account marker the server sends when the switch flips is what
/// re-reads the session, so this follows without a poll.
final serverReadOnlyProvider = Provider<bool>(
  (ref) => ref.watch(authControllerProvider).value?.serverReadOnly ?? false,
);
