import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart' show Backoff;

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
import 'owed_revoke.dart';

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

/// How long a start that remembers its session waits for the server's
/// answer before it opens on what it remembers. A server slower than this
/// is still the one believed: its answer lands on the open app as any
/// session read's does.
const kRememberedSessionWait = Duration(seconds: 3);

/// Session state for the whole app.
///
/// Builds by probing the server session. On native the persisted bearer
/// token is restored into the client first, so a previous login survives
/// a restart; on web a live cookie serves the same purpose. [login] and
/// friends flip the state on success and rethrow the structured API error
/// on failure so forms can show it. They answer whether the session that
/// shows is theirs: false for one overtaken first (a sign-out, another
/// sign-in, a new build), which shows nothing.
///
/// A native start whose probe does not reach the server opens on the
/// session the device remembers for its token, the last one the server
/// answered for it, so what was downloaded for exactly that case can be
/// reached. That session is [unconfirmed] until the server is reached and
/// [refreshSession] hears it. With nothing remembered the probe fails as
/// it always has.
class AuthController extends AsyncNotifier<SessionState> {
  /// Moves at every sign-in, sign-out and build: a session read asked
  /// before one answers for the account, or the build, it was asked of,
  /// and is dropped. `ref.mounted` cannot say so: the notifier outlives a
  /// build, and its `ref` is always the newest one's.
  var _account = 0;

  /// Above zero while an account is on its way out: from the first step of
  /// a sign-out or a swap until the session stops naming it.
  var _leaving = 0;

  /// What a session arriving meanwhile waits on: completed once nobody is
  /// on the way out. Null with nothing waiting.
  Completer<void>? _left;

  /// The sign-out under way, which another joins rather than cleaning up
  /// again; null once it is over.
  Future<void>? _signingOut;

  /// The revoke a browser owes on its way to the server, which whatever
  /// asks meanwhile waits for; null with none out.
  Future<void>? _revoking;

  /// How many sign-ins are out at the server, and what a revoke owed
  /// meanwhile waits on. Each may replace the browser's cookie, and a
  /// revoke sent beside one could end the session it makes, or its answer
  /// expire that session's cookie.
  var _signIns = 0;
  Completer<void>? _signedIn;

  /// Moves at every sign-out pressed: a sign-in out across one is undone
  /// when it lands.
  var _presses = 0;

  /// The marks of a browser's sign-outs the server heard while sign-ins
  /// sent before them were out: settled once the last of those lands,
  /// unless one of them owed its own session in their place.
  final _pressesHeard = <String>[];

  /// The session last kept for a start out of reach, and the [_account]
  /// it was kept under: what a token rotation keeps again for the token
  /// it brings.
  (int, SessionState)? _kept;

  /// How many session reads [_settle] has out.
  var _reading = 0;

  var _unconfirmed = false;

  /// The client told to say the server's next answer, while the session
  /// is unconfirmed.
  ServerAnswers? _listening;

  /// Whether the server answered a request since a read was last asked to
  /// confirm the session.
  var _heard = false;

  /// Runs after a session read the server did not answer, while the
  /// session is unconfirmed: until it ends, an answer heard asks nothing.
  /// A second, doubling to a minute while such reads keep failing, which
  /// is how `SessionDoubt` spaces the same read.
  Timer? _floor;
  final _floorWait = Backoff();

  /// Whether the session held is what the device remembered at a start
  /// the server did not answer, with no answer of the server's for it
  /// since. Whatever reaches the server while this holds asks
  /// [refreshSession]: the sync engine's socket coming up, and the next
  /// request the server answers.
  bool get unconfirmed => _unconfirmed;

  @override
  Future<SessionState> build() async {
    final built = ++_account;
    // The build before can mark the session after its own cleanup ran:
    // it is invalidated a moment before this one begins.
    _noLongerUnconfirmed();
    // Before the next build too, and when the controller goes.
    ref.onDispose(_noLongerUnconfirmed);
    // No server, no probe: an unconfigured native build answers signed
    // out at once and the router's redirect owns the connect screen.
    if (!ref.watch(serverConfiguredProvider)) {
      return const SessionState(authenticated: false);
    }
    final repo = ref.watch(repositoryProvider);
    final store = ref.watch(credentialStoreProvider);
    final rotation = _rotation;
    var restored = false;
    SessionState? remembered;
    if (!kIsWeb) {
      var stored = await store.readToken();
      if (stored != null && rotation != null) {
        // A rotation was out when the store was asked: the token to
        // restore is the one it leaves there. Its failure is not this
        // build's, and is raised as it is with nobody waiting.
        try {
          await rotation;
        } on Object catch (error, stack) {
          Zone.current.handleUncaughtError(error, stack);
        }
        stored = await store.readToken();
      }
      if (!_current(built)) return _overtaken();
      if (stored != null) {
        repo.authToken = stored;
        restored = true;
        remembered = await _remembered(store, stored);
      }
    }
    // A browser's sign-out the server has yet to hear goes before any read
    // of the session it left. Undelivered, the build fails as a read does.
    final revoke = _owedRevoke();
    if (revoke != null) {
      await revoke;
      if (!_current(built)) return _overtaken();
    }
    final SessionState session;
    if (remembered == null) {
      session = await repo.getSession();
      if (!_current(built)) return _overtaken();
    } else {
      final answer = await _answerInTime(repo.getSession(), built, remembered);
      if (!_current(built)) return _overtaken();
      if (answer == null) {
        final way = _wayFor(built, remembered, building: true);
        if (way != null) await way;
        if (!_current(built)) return _overtaken();
        _unconfirmed = true;
        _listenForAnswer(built);
        ref.read(playbackHeldProvider.notifier).release();
        return remembered;
      }
      session = answer;
    }
    ref.read(owedRevokeProvider).hold(session.sessionId);
    if (session.authenticated) {
      // Before anything is done for the session: a build overtaken while
      // it waits has rotated nothing and kept nothing.
      final way = _wayFor(built, session, building: true);
      if (way != null) await way;
      final held = state.value;
      if (!_current(built)) return _overtaken();
      if (held != null &&
          held.authenticated &&
          held.user?.id != session.user?.id) {
        // Another account's session where one shows, as when a browser's
        // cookie changed hands. A session read sees that account out as it
        // does at any swap, and the build answers the session held until
        // it has.
        unawaited(_handOver(built, session));
        return held;
      }
    }
    if (restored) {
      if (session.authenticated) {
        // Fire and forget: rotate the long-lived token on cold start. The
        // old token stays valid through a short server-side grace window,
        // so racing in-flight requests is safe. A rotation this build
        // waited for is its rotation.
        if (rotation == null) unawaited(_rotateStoredToken(repo, store));
        _remember(session);
      } else {
        // The stored token is dead (revoked, expired, or its account
        // disabled while the app was closed): it goes, and so does what
        // that account left here.
        repo.authToken = null;
        await store.clearToken();
        // An account can sign in while the store clears, and while what
        // the dead token left is forgotten: it is not forgotten with it,
        // nor answered signed out.
        if (!_current(built)) return _overtaken();
        await _forgetAccount();
        if (!_current(built)) return _overtaken();
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

  /// Whether the build, sign-in or swap that counted [taken] is still the
  /// last thing to happen to the session, in a controller that is still
  /// there. Each looks after every await it goes on to act from.
  bool _current(int taken) => ref.mounted && taken == _account;

  /// What a build answers once it is no longer [_current]: a newer
  /// build, a sign-in or a sign-out came after it began, or its
  /// controller went. It acts on nothing: the token, the store and what
  /// is remembered are theirs by then, or nobody's. A newer build and a
  /// controller that went drop this answer; after a sign-in or a sign-out
  /// it becomes the state, so it is the session held by then, none where
  /// none is yet, and never this build's own.
  SessionState _overtaken() =>
      (ref.mounted ? state.value : null) ??
      const SessionState(authenticated: false);

  /// The session the device remembers for [token], when it is one a start
  /// can open on. One kept for another token is as good as none.
  Future<SessionState?> _remembered(
    CredentialStorePort store,
    String token,
  ) async {
    final record = await store.readSession();
    if (record == null) return null;
    final text = rememberedFor(token, record);
    if (text == null) return null;
    final session = SessionState.fromStored(text);
    return session != null && session.authenticated ? session : null;
  }

  /// Whether a failed session read is the server saying, in its own
  /// words, that there is no session: what its `authenticated: false`
  /// answer says. The one failure that ends a session held or remembered.
  /// Any other leaves it standing, a 401 in no words of the server's
  /// included: that is something in front of the server, a proxy's
  /// sign-in.
  static bool _saysNoSession(WaxDeckApiException error) =>
      error.code == 'unauthenticated';

  /// What [read] answers, or null for the start to open on [remembered]:
  /// the read failed, or it is still out after [kRememberedSessionWait].
  /// A failure is heard as [refreshSession] hears one: [_saysNoSession]
  /// answers no session, which takes the token, and no other failure
  /// does. One still out is heard when it lands, by the same rule.
  Future<SessionState?> _answerInTime(
    Future<SessionState> read,
    int built,
    SessionState remembered,
  ) async {
    try {
      final answer = await read
          .then<SessionState?>((session) => session)
          .timeout(kRememberedSessionWait, onTimeout: () => null);
      if (answer == null) _settle(() => read, built, remembered).ignore();
      return answer;
    } on WaxDeckApiException catch (error) {
      return _saysNoSession(error)
          ? const SessionState(authenticated: false)
          : null;
    }
  }

  /// Keeps [session], the server's answer for the token held, for a start
  /// that cannot reach the server. A session with no token, a browser's
  /// cookie, is never kept.
  void _remember(SessionState session) {
    if (kIsWeb) return;
    final token = ref.read(repositoryProvider).authToken;
    if (token == null) return;
    _keep(ref.read(credentialStoreProvider), token, session);
  }

  /// Keeps [session] in [store] as the one the server answered for
  /// [token]. Not awaited: the store takes its writes in the order they
  /// are asked, so a sign-out after this still clears it.
  void _keep(CredentialStorePort store, String token, SessionState session) {
    _kept = (_account, session);
    store.writeSession(rememberedRecord(token, session.toStored())).ignore();
  }

  /// Whether the session held is still the one [asked] to be confirmed.
  bool _awaited(int asked) => ref.mounted && _unconfirmed && asked == _account;

  /// Has the client say the next request the server answers, while the
  /// session held is unconfirmed: the socket is not the only road back to
  /// a server, and a proxy can pass requests and not the upgrade. A
  /// session read's own answer is not such a request.
  void _listenForAnswer(int asked) {
    if (ref.read(repositoryProvider) case final ServerAnswers server) {
      _listening = server;
      server.onNextAnswer = () {
        if (!_awaited(asked)) return;
        _heard = true;
        _listenForAnswer(asked);
        _confirmIfHeard(asked);
      };
    }
  }

  /// Asks for the session to be confirmed when the server was heard to
  /// answer, unless a session read is out, whoever asked it, or [_floor]
  /// runs: what was heard is kept until the one lands, unanswered or
  /// stale, and the other ends.
  void _confirmIfHeard(int asked) {
    if (!_awaited(asked) || !_heard || _reading > 0 || _floor != null) return;
    _heard = false;
    unawaited(_confirm(asked));
  }

  /// One read for the session to be confirmed. Nothing it throws is left
  /// uncaught under the request whose answer started it: what is no API
  /// error is reported as the framework reports its own, and counts as a
  /// read the server did not answer.
  Future<void> _confirm(int asked) async {
    try {
      await refreshSession();
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'waxdeck session',
        ),
      );
      _unanswered(asked);
    }
  }

  /// The server did not answer a read of the session [asked] to be
  /// confirmed: the next is not asked before [_floor] ends.
  void _unanswered(int asked) {
    if (!_awaited(asked) || _floor != null) return;
    _floor = Timer(_floorWait.take(), () {
      _floor = null;
      _confirmIfHeard(asked);
    });
  }

  /// The session held is no longer one opened on from memory: the server
  /// answered for it, it left, or the controller builds again or is gone.
  /// Nothing listens for the server's next answer and nothing waits to
  /// ask. No `ref`: this runs on dispose too.
  void _noLongerUnconfirmed() {
    _unconfirmed = false;
    _heard = false;
    _floor?.cancel();
    _floor = null;
    _floorWait.reset();
    _listening?.onNextAnswer = null;
    _listening = null;
  }

  /// The server answered [session] for the account held: it is kept, and
  /// one opened on from memory is confirmed, which is when its start's
  /// token rotation is made.
  void _answered(SessionState session) {
    _remember(session);
    if (!_unconfirmed) return;
    _noLongerUnconfirmed();
    unawaited(
      _rotateStoredToken(
        ref.read(repositoryProvider),
        ref.read(credentialStoreProvider),
      ),
    );
  }

  /// The token rotation out. A second is not asked beside it: the server
  /// keeps one token back for a short overlap, so of two rotations the
  /// earlier one's token dies with that overlap, whoever holds it.
  Future<void>? _rotation;

  Future<void> _rotateStoredToken(
    WaxDeckRepository repo,
    CredentialStorePort store,
  ) => _rotation ??= _rotate(repo, store).whenComplete(() => _rotation = null);

  Future<void> _rotate(
    WaxDeckRepository repo,
    CredentialStorePort store,
  ) async {
    final asked = _account;
    final rotating = repo.authToken;
    try {
      final rotated = await repo.refreshToken();
      // Stored only as the client's bearer. One the client did not take
      // up, its credentials having moved while this was out, is nobody's.
      if (repo.authToken != rotated.token) return;
      if (asked != _account) {
        // The account moved on while this was out and the bearer did not.
        // The token is stored only where the one it rotated is still the
        // one held, and nothing moved again while the store was asked.
        final moved = _account;
        final held = await store.readToken();
        if (held != rotating || moved != _account) return;
      }
      final stored = store.writeToken(rotated.token);
      // What is remembered follows its token, or the next start out of
      // reach would find it kept for another. No `ref` here: the
      // controller may be gone by now.
      if (_kept case (final account, final session) when account == _account) {
        _keep(store, rotated.token, session);
      }
      await stored;
    } on WaxDeckApiException catch (e) {
      // A refusal of a token the client no longer holds says nothing of
      // the session it holds now.
      if (_saysNoSession(e) && asked == _account) {
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
  /// moved or its session ended, after the server is first reached by a
  /// start that opened on the session it remembered, or, in a browser,
  /// after the event socket came back from a drop across which another
  /// account may have signed in.
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
    return _settle(
      repo.getSession,
      _account,
      state.value,
      after: _owedRevoke(),
    );
  }

  /// Hears [read], a session read [asked] of the account that held
  /// [askedFor], by [refreshSession]'s rule. The read is made once [after],
  /// a revoke owed, is delivered; undelivered, it is a read the server did
  /// not answer.
  Future<SessionRecheck> _settle(
    Future<SessionState> Function() read,
    int asked,
    SessionState? askedFor, {
    Future<void>? after,
  }) async {
    try {
      if (after != null) {
        await after;
        if (!ref.mounted || asked != _account) return _stale(askedFor);
      }
      final session = await _out(read);
      // A sign-out, a new account or a new build can end this controller
      // mid-read, or land while it is out: either way the answer is stale.
      if (!ref.mounted || asked != _account) return _stale(askedFor);
      ref.read(owedRevokeProvider).hold(session.sessionId);
      if (!session.authenticated) {
        // The server ended the session (the account was disabled, or this
        // device revoked), which is a sign-out like any other.
        await signOutLocally();
        return SessionRecheck.left;
      }
      if (session.user?.id != state.value?.user?.id) {
        // Another account's session in this one's place: a tab that signed
        // in over this browser's cookie. Its leftovers go before it shows.
        if (!await _swapTo(session)) return _holding(askedFor);
        return SessionRecheck.left;
      }
      state = AsyncData(session);
      _answered(session);
      return SessionRecheck.stands;
    } on WaxDeckApiException catch (error) {
      if (!ref.mounted || asked != _account) return _stale(askedFor);
      // Any failure but the one keeps what the client last read.
      if (!_saysNoSession(error)) {
        _unanswered(asked);
        return SessionRecheck.unanswered;
      }
      await signOutLocally();
      return SessionRecheck.left;
    } on Object {
      // No API error, and thrown on to whoever asked. For the session
      // held it is a read the server did not answer; a stale one is as
      // any stale read.
      if (asked == _account) {
        _unanswered(asked);
      } else {
        _confirmIfHeard(_account);
      }
      rethrow;
    }
  }

  /// Shows [session], another account's the server answered, once the
  /// account showing is seen out. False, with nothing shown, once
  /// overtaken.
  Future<bool> _swapTo(SessionState session) async {
    final adopting = ++_account;
    // A start from here on must not open as the account leaving. Not
    // awaited, as [_remember]'s write is not.
    if (!kIsWeb) ref.read(credentialStoreProvider).clearSession().ignore();
    if (!await _seenOut(adopting)) return false;
    ref.read(playbackHeldProvider.notifier).release();
    state = AsyncData(session);
    _answered(session);
    return true;
  }

  /// The build [built] found [found], another account's session, where
  /// one shows: a session read sees that account out. When the server does
  /// not answer that read, [found], a moment older, is the one shown,
  /// unless a revoke is owed: that is delivered before any session shows,
  /// so the account showing is seen out and nobody shows.
  Future<void> _handOver(int built, SessionState found) async {
    final recheck = await refreshSession();
    if (recheck != SessionRecheck.unanswered || !_current(built)) return;
    if (_leaving > 0 || state.value?.user?.id == found.user?.id) return;
    if (!ref.read(owedRevokeProvider).owed) {
      await _swapTo(found);
      return;
    }
    final leaving = ++_account;
    if (!kIsWeb) ref.read(credentialStoreProvider).clearSession().ignore();
    await _seenOut(leaving);
  }

  /// What a read the client moved on from answers. It read nothing of
  /// the session held now, so an answer heard and kept while it was out
  /// is asked at once, unless [_floor] runs.
  SessionRecheck _stale(SessionState? askedFor) {
    _confirmIfHeard(_account);
    return _holding(askedFor);
  }

  /// [read], counted in [_reading] until it lands.
  Future<SessionState> _out(Future<SessionState> Function() read) async {
    _reading++;
    try {
      return await read();
    } finally {
      _reading--;
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

  /// What completes once the signed-in screens now up are gone, null with
  /// none up. No timeout, though a hidden tab holds it until shown.
  Future<void>? get _screensUp => ref.exists(signedInScreensProvider)
      ? ref.read(signedInScreensProvider).gone
      : null;

  /// One account fewer on its way out.
  void _hasLeft() {
    if (--_leaving > 0) return;
    _left?.complete();
    _left = null;
  }

  /// Sees the account whose session shows out, for one arriving: what it
  /// left here goes, then its session, then its screens, so the next
  /// session never lands on screens holding its reads. Answers whether the
  /// road that counted [taken] is still [_current].
  Future<bool> _seenOut(int taken) async {
    _leaving++;
    try {
      await _forgetAccount();
    } finally {
      _hasLeft();
    }
    if (!_current(taken)) return false;
    final screens = _screensUp;
    state = const AsyncData(SessionState(authenticated: false));
    if (screens != null) await screens;
    return _current(taken);
  }

  /// What a session of [arriving]'s account waits on before it shows, on
  /// the road that counted [taken]; null when nothing is in its way, which
  /// costs that road no turn. An account on its way out is let finish, and
  /// this is asked again. Then the screens up are staying only under a
  /// session of the same account. Under none, they are leaving and are
  /// waited for. Under another's, that account is [_seenOut], except by a
  /// build ([building]): that sets the session signed out before the build
  /// has answered, and what awaits the build's answer would take it for
  /// the answer. A build hands a session the server answered to a session
  /// read instead.
  ///
  /// The road looks whether it is still [_current] after this, waited or
  /// not: reading the state runs a rebuild that was due, which overtakes
  /// it, and then nobody is seen out here.
  Future<void>? _wayFor(
    int taken,
    SessionState arriving, {
    bool building = false,
  }) {
    if (_leaving > 0) {
      return (_left ??= Completer<void>()).future.then<void>(
        (_) => _current(taken)
            ? _wayFor(taken, arriving, building: building)
            : null,
      );
    }
    final held = state.value;
    if (!_current(taken)) return null;
    if (held == null || !held.authenticated) return _screensUp;
    if (building || held.user?.id == arriving.user?.id) return null;
    return _seenOut(taken);
  }

  /// The revoke a browser owes for a sign-out its server did not hear, on
  /// its way there: what a road waits for before it reads that browser's
  /// cookie as a session. Null with none owed, which costs the road no
  /// turn. Fails as the revoke does, and then it is still owed and the
  /// road shows nobody. A sign-in out at the server is let land first, and
  /// a revoke on its way, and this is asked again: either may have settled
  /// what is owed, or owed another.
  Future<void>? _owedRevoke() {
    final owed = ref.read(owedRevokeProvider);
    if (!owed.owed) return null;
    if (_signIns > 0) {
      return (_signedIn ??= Completer<void>()).future.then<void>(
        (_) => ref.mounted ? _owedRevoke() : null,
      );
    }
    if (_revoking case final out?) {
      return out.then<void>((_) => ref.mounted ? _owedRevoke() : null);
    }
    return _sending(_revoke(owed, ref.read(repositoryProvider)));
  }

  /// [revoke], as the one on its way until it lands.
  Future<void> _sending(Future<void> revoke) {
    late final Future<void> out;
    out = revoke.whenComplete(() {
      if (identical(_revoking, out)) _revoking = null;
    });
    return _revoking = out;
  }

  /// Ends the session owed, and no other. By id, with the CSRF token of the
  /// session the cookie holds, which only a session read hands the client:
  /// the server ends the one owed when it is the cookie's, or an older one
  /// of the same account, and leaves the cookie's; another account's it
  /// says it has no such session; and a sign-in landing since the read is
  /// refused that proof, and stays. With none named, ends whatever the
  /// cookie holds.
  Future<void> _revoke(OwedRevoke owed, WaxDeckRepository repo) async {
    final mark = owed.mark;
    if (mark == null) return;
    final named = owed.session;
    var heldElsewhere = false;
    try {
      if (named == null) {
        await repo.logout();
        owed.release();
      } else {
        final presented = await repo.getSession();
        if (!ref.mounted) return;
        owed.hold(presented.sessionId);
        if (presented.authenticated) {
          final held = presented.sessionId;
          heldElsewhere = held != null && held != named;
          await repo.revokeSession(named);
        }
        owed.release(named);
      }
    } on WaxDeckApiException catch (error) {
      // No session to end is the revoke delivered; by id, so is a session
      // the account presenting the cookie has none of. One the cookie no
      // longer holds signs nobody back in: answered at all, by the server or
      // anything in front of it, it is let go, or a refusal for good would
      // fail every start. Except the server refusing its proof, which the
      // next asking reads afresh and then ends it.
      final settled =
          _saysNoSession(error) ||
          named != null && error.code == 'not-found' ||
          heldElsewhere &&
              error.statusCode != null &&
              error.code != 'forbidden';
      if (!settled) rethrow;
    }
    owed.settle(mark);
  }

  /// Names a revoke owed that names no session after the session the
  /// cookie holds, when the server can say: with no sign-in since, that is
  /// the session it was owed for. A cookie that holds none owes nothing.
  Future<void> _nameOwed() async {
    final owed = ref.read(owedRevokeProvider);
    final mark = owed.mark;
    if (mark == null || owed.session != null) return;
    try {
      final presented = await ref.read(repositoryProvider).getSession();
      if (!ref.mounted || owed.mark != mark) return;
      owed.hold(presented.sessionId);
      if (!presented.authenticated) {
        owed.settle(mark);
      } else if (presented.sessionId case final session?) {
        owed.owe(session);
      }
    } on WaxDeckApiException {
      // Still owed as it was.
    }
  }

  /// Signs in by [ask] and shows the session it answers, as [_adopt]
  /// does. A revoke owed goes first, unless it was already asked
  /// ([delivered]), and delivered or not the sign-in is asked. A revoke
  /// that named no session and was owed when the sign-in was sent is
  /// settled by its answer, which it would otherwise end; one owed by
  /// name stays, and ends no session made since. No revoke is sent while
  /// the sign-in is out. A sign-out pressed while it is out undoes it.
  Future<bool> _signIn(
    Future<LoginResult> Function() ask, {
    void Function()? answered,
    bool delivered = false,
  }) async {
    final owed = ref.read(owedRevokeProvider);
    final repo = ref.read(repositoryProvider);
    final revoke = delivered ? null : _owedRevoke();
    if (revoke != null) {
      try {
        await revoke;
      } on WaxDeckApiException {
        // Still owed.
      }
      if (!ref.mounted) return false;
    }
    final pressed = _presses;
    final unnamed = owed.session == null ? owed.mark : null;
    final LoginResult result;
    final bool undone;
    _signIns++;
    try {
      result = await ask();
      // A sign-out pressed while this was out is the later intent: the
      // session this made goes too.
      undone = _presses != pressed;
      // The cookie holds that session now, whatever becomes of it.
      owed.hold(result.sessionId);
      if (undone) {
        owed.owe(result.sessionId);
      } else if (unnamed != null) {
        owed.settle(unnamed);
      }
    } finally {
      if (--_signIns == 0) {
        for (final mark in _pressesHeard) {
          owed.settle(mark);
        }
        _pressesHeard.clear();
        _signedIn?.complete();
        _signedIn = null;
      }
    }
    if (ref.mounted) answered?.call();
    if (undone && !owed.keeps) {
      // A native client never took up its token, which ends it once and is
      // kept nowhere.
      try {
        await repo.logoutToken(result.token);
      } on WaxDeckApiException {
        // Not heard: it lives until it expires, and nothing presents it.
      }
      return false;
    }
    if (!ref.mounted) return false;
    if (!undone) return _adopt(result);
    // A browser's cookie holds it, and its revoke is owed by name above.
    try {
      await _owedRevoke();
    } on WaxDeckApiException {
      // Still owed, and delivered before the cookie is next read.
    }
    return false;
  }

  /// Shows the session [result] signed in. Answers false, with nothing
  /// shown, when a sign-out, another sign-in or a new build came first.
  Future<bool> _adopt(LoginResult result) async {
    final adopting = ++_account;
    _noLongerUnconfirmed();
    final session = SessionState(
      authenticated: true,
      user: result.user,
      sessionId: result.sessionId,
    );
    if (!kIsWeb) {
      // The client takes up no sign-in a sign-out was asked across, and
      // one not pressed (a session the server ended, a stored token found
      // dead) does not undo this one.
      ref.read(repositoryProvider).authToken = result.token;
      // The token, then who the server said it is, kept as that token's.
      // Two writes, and either can fail alone: a session one of them left
      // from the last token is not read as this one's. Overtaken at
      // either, it writes no more: a sign-out or a sign-in wrote after it,
      // and a build restores what is there.
      final store = ref.read(credentialStoreProvider);
      await store.writeToken(result.token);
      if (!_current(adopting)) return false;
      await store.writeSession(
        rememberedRecord(result.token, session.toStored()),
      );
      if (!_current(adopting)) return false;
    }
    // Waited for with the token already stored: a session read that finds
    // this account meanwhile shows it in this one's place, and stores none.
    final way = _wayFor(adopting, session);
    if (way != null) await way;
    if (!_current(adopting)) return false;
    // Not before: a play started from screens on their way out would
    // outlive them.
    ref.read(playbackHeldProvider.notifier).release();
    state = AsyncData(session);
    // The sign-in answer names the account and no more; the server's own
    // state (read-only) arrives with the session.
    unawaited(refreshSession());
    return true;
  }

  Future<bool> login({required String username, required String password}) =>
      _signIn(
        () => ref
            .read(repositoryProvider)
            .login(
              username: username,
              password: password,
              deviceName: waxDeckDeviceName,
            ),
      );

  /// Creates the first administrator and lands signed in.
  Future<bool> bootstrap({
    required String username,
    required String password,
    String? displayName,
  }) => _signIn(
    () => ref
        .read(repositoryProvider)
        .bootstrap(
          username: username,
          password: password,
          displayName: displayName,
        ),
    answered: () => ref.invalidate(bootstrapStatusProvider),
  );

  /// Runs the platform-appropriate OIDC flow for [provider]. On web this
  /// navigates the browser away and never flips the state here; the SPA
  /// reloads authenticated, and this answers true for a form that keeps
  /// waiting. On native it completes the exchange and signs in. Rethrows
  /// structured API errors and [TimeoutException] for the login form to
  /// show.
  Future<bool> loginWithOidc(OidcProvider provider) async {
    final flow = ref.read(oidcFlowProvider);
    // A revoke owed goes first, as before any sign-in, and undelivered the
    // flow starts all the same. A browser's flow comes back as a new start,
    // whose delivery ends only the session it names: one naming none is
    // named here, when the server can say which session the cookie holds.
    final revoke = _owedRevoke();
    if (revoke != null) {
      try {
        await revoke;
      } on WaxDeckApiException {
        await _nameOwed();
      }
      if (!ref.mounted) return false;
    }
    if (kIsWeb) {
      await flow.startWeb(provider);
      return true;
    }
    // A sign-out pressed during the round trip is the later intent, and
    // holds nothing back: the code that comes back after it is never
    // redeemed. One pressed while the exchange is out is [_signIn]'s.
    final pressed = _presses;
    bool wanted() => _presses == pressed;
    try {
      return await _signIn(
        () => switch (defaultTargetPlatform) {
          TargetPlatform.android => flow.loginWithDeepLink(
            provider,
            deviceName: waxDeckDeviceName,
            wanted: wanted,
          ),
          _ => flow.loginWithLoopback(
            provider,
            page: _loopbackPage(),
            deviceName: waxDeckDeviceName,
            wanted: wanted,
          ),
        },
        delivered: true,
      );
    } on OidcAbandoned {
      return false;
    }
  }

  /// The browser tab is drawn outside the element tree.
  LoopbackPage _loopbackPage() {
    final copy = ref.read(offTreeL10nProvider);
    return (heading: copy.authLoopbackTitle, line: copy.authLoopbackMessage);
  }

  /// Signs out: on screen at once, whatever is out at the server. A
  /// sign-in out at the press is undone when it lands ([_signIn]).
  Future<void> logout() async {
    _presses++;
    final owed = ref.read(owedRevokeProvider);
    final repo = ref.read(repositoryProvider);
    final Future<void> heard;
    if (owed.keeps) {
      // A browser's session is the server's cookie, which only the server
      // ends. Owed from here, before anything is awaited, so a reload or a
      // closed tab still delivers it: naming the session the cookie holds
      // when that is known, which it is not while a sign-in is out, since
      // its answer may replace the cookie at any moment.
      final mark = owed.owe(_signIns > 0 ? null : owed.held);
      heard = _sending(_signOutHeard(repo, owed, mark, _revoking));
    } else {
      // Asked before the local sign-out drops the token it presents.
      heard = repo.logout();
    }
    // Listened to before the local sign-out runs, which it can fail
    // during. Not heard, the local session goes all the same: a native
    // session goes with its token, which nothing presents again; a
    // browser's stays owed, and is revoked before its cookie is next read
    // as a session.
    final answered = heard.catchError(
      (Object _) {},
      test: (error) => error is WaxDeckApiException,
    );
    await signOutLocally();
    await answered;
  }

  /// A browser's sign-out of whatever the cookie holds, once [before], a
  /// revoke on its way, lands. Heard, the [mark] it owed is settled, unless
  /// a sign-in sent before it is still out: that one settles it as it
  /// lands, or owes its own session in its place.
  Future<void> _signOutHeard(
    WaxDeckRepository repo,
    OwedRevoke owed,
    String mark,
    Future<void>? before,
  ) async {
    if (before != null) {
      try {
        await before;
      } on WaxDeckApiException {
        // Still owed; this sign-out's own request goes all the same.
      }
      if (!ref.mounted) return;
    }
    await repo.logout();
    // Settled whether this client is still there or not: the server heard.
    owed.release();
    if (_signIns == 0) {
      owed.settle(mark);
    } else {
      _pressesHeard.add(mark);
    }
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
      _noLongerUnconfirmed();
      ref.read(repositoryProvider).authToken = null;
      if (!kIsWeb) {
        await ref.read(credentialStoreProvider).clearToken();
      }
      // The session this ends. Read once the token's clearing is asked:
      // the read runs a rebuild that was due, which must find no token.
      final ending = state.value;
      await _forgetAccount();
      // Not the counter: a session arriving meanwhile moved it, and waits
      // for this line to take the screens down. Only a session shown since
      // is not this sign-out's to end, the same account's included.
      if (!ref.mounted || !identical(state.value, ending)) return;
      state = const AsyncData(SessionState(authenticated: false));
    } finally {
      _hasLeft();
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
