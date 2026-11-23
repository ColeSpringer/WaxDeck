import 'dart:async';

import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [AuthApi] for `FakeRepository`.
mixin FakeAuth on FakeRepositoryState implements AuthApi {
  /// Thrown by [login] when set, to exercise the error path.
  WaxDeckApiException? loginError;

  /// Thrown by [bootstrap] when set, to exercise the error path.
  WaxDeckApiException? bootstrapError;

  /// Hold [login], [bootstrap] and [signup] open, when set, until
  /// completed.
  Completer<void>? loginGate;
  Completer<void>? bootstrapGate;
  Completer<void>? signupGate;

  /// Holds [oidcExchange], when set, until completed.
  Completer<void>? oidcExchangeGate;

  /// Thrown by [refreshToken] when set, to exercise rotation failures.
  WaxDeckApiException? refreshError;

  final List<({String username, String password, String? deviceName})>
  loginCalls = [];
  final List<({String username, String password, String? displayName})>
  bootstrapCalls = [];
  final List<({String code, String? verifier, String? deviceName})>
  oidcExchangeCalls = [];
  final List<String> revokedSessionIds = [];
  final List<({String id, String deviceName})> renamedSessions = [];

  /// When set, renameSession fails with it instead of storing.
  WaxDeckApiException? renameError;

  int refreshCalls = 0;

  /// The tokens [logoutToken] was asked to end, in order.
  final List<String> tokenLogouts = [];

  /// Who a sign-in by password signs in; the fake's own administrator
  /// while unset.
  WaxDeckUser? signsIn;

  static const _user = WaxDeckUser(
    id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
    username: 'admin',
    roles: ['admin'],
  );

  /// Whether the server this fake stands for is in read-only mode, as a
  /// session it opens reports.
  bool serverReadOnly = false;

  /// Moves as the client's count of its credentials does: at every
  /// sign-in and sign-out, and whenever the bearer is set to another.
  var _credentials = 0;

  /// Moves as the client's count of its sign-outs does: when the bearer is
  /// dropped, and when a sign-out is asked.
  var _signOuts = 0;

  @override
  set authToken(String? token) {
    if (token != super.authToken) _credentials++;
    if (token == null && super.authToken != null) _signOuts++;
    super.authToken = token;
  }

  /// What a sign-in asked at the count [asked] answers: as the client, one
  /// a sign-out was asked since is answered and not taken up.
  LoginResult _signInAsked(
    int asked, {
    WaxDeckUser user = _user,
    String token = 'test-token',
  }) => asked == _signOuts
      ? _signIn(user: user, token: token, session: 'se-$token')
      : LoginResult(user: user, token: token, sessionId: 'se-$token');

  /// Signs in on [token], whose session the reads after it name [session];
  /// its answer names it as the server's does, a rotation the one it
  /// rotated.
  LoginResult _signIn({
    WaxDeckUser user = _user,
    String token = 'test-token',
    String? session,
  }) {
    sessionState = SessionState(
      authenticated: true,
      user: user,
      serverReadOnly: serverReadOnly,
      sessionId: session,
    );
    _credentials++;
    super.authToken = token;
    return LoginResult(
      user: user,
      token: token,
      sessionId: session ?? 'se-$token',
    );
  }

  @override
  Future<BootstrapStatus> bootstrapStatus() async => BootstrapStatus(
    required: bootstrapNeeded,
    signupEnabled: adminSettings.signupEnabled,
  );

  @override
  Future<LoginResult> bootstrap({
    required String username,
    required String password,
    String? displayName,
  }) async {
    final asked = _signOuts;
    bootstrapCalls.add((
      username: username,
      password: password,
      displayName: displayName,
    ));
    await bootstrapGate?.future;
    final error = bootstrapError;
    if (error != null) throw error;
    bootstrapNeeded = false;
    return _signInAsked(
      asked,
      user: WaxDeckUser(
        id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
        username: username,
        displayName: displayName,
        roles: const ['admin'],
      ),
    );
  }

  @override
  Future<LoginResult> login({
    required String username,
    required String password,
    String? deviceName,
  }) async {
    final asked = _signOuts;
    loginCalls.add((
      username: username,
      password: password,
      deviceName: deviceName,
    ));
    await loginGate?.future;
    final error = loginError;
    if (error != null) throw error;
    return _signInAsked(asked, user: signsIn ?? _user);
  }

  /// Holds every session read until completed, when set: the session
  /// a screen is mounted under has not answered yet.
  Completer<void>? getSessionGate;

  @override
  Future<SessionState> getSession() async {
    await getSessionGate?.future;
    return sessionState;
  }

  /// Holds [refreshToken] open, when set, until completed.
  Completer<void>? refreshGate;

  @override
  Future<LoginResult> refreshToken() async {
    refreshCalls++;
    final asked = _credentials;
    if (refreshGate case final gate?) await gate.future;
    final error = refreshError;
    if (error != null) throw error;
    // As the client: a rotation its credentials moved under while it was
    // out is answered and not taken up, even with the same bearer back.
    if (_credentials != asked) {
      return LoginResult(
        user: sessionState.user ?? _user,
        token: 'rotated-token',
        sessionId: sessionState.sessionId ?? 'se-rotated-token',
      );
    }
    return _signIn(token: 'rotated-token', session: sessionState.sessionId);
  }

  @override
  Future<void> logout() async {
    _signOuts++;
    sessionState = const SessionState(authenticated: false);
    _credentials++;
    super.authToken = null;
  }

  /// [WaxDeckRepository.logoutToken]: answered, and only recorded.
  Future<void> logoutToken(String token) async {
    tokenLogouts.add(token);
  }

  @override
  Future<List<DeviceSession>> listSessions() async => List.of(deviceSessions);

  /// Holds [renameSession] until completed.
  Completer<void>? renameGate;

  @override
  Future<DeviceSession> renameSession(
    String sessionId,
    String deviceName,
  ) async {
    if (renameGate case final gate?) await gate.future;
    final failure = renameError;
    if (failure != null) throw failure;
    // The server trims; the fake stores what a trimming server would.
    final name = deviceName.trim();
    if (name.isEmpty) {
      throw const WaxDeckApiException(
        code: 'invalid-request',
        message: 'deviceName must be 1 to 128 characters after trimming',
      );
    }
    renamedSessions.add((id: sessionId, deviceName: name));
    final at = deviceSessions.indexWhere((s) => s.id == sessionId);
    if (at < 0) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no session with that id',
        statusCode: 404,
      );
    }
    final was = deviceSessions[at];
    final now = DeviceSession(
      id: was.id,
      kind: was.kind,
      createdAt: was.createdAt,
      current: was.current,
      deviceName: name,
      client: was.client,
      lastSeenAt: was.lastSeenAt,
    );
    deviceSessions[at] = now;
    return now;
  }

  @override
  Future<void> revokeSession(String sessionId) async {
    revokedSessionIds.add(sessionId);
    deviceSessions.removeWhere((s) => s.id == sessionId);
  }

  @override
  Future<List<OidcProvider>> oidcProviders() async => List.of(ssoProviders);

  @override
  Future<LoginResult> oidcExchange({
    required String code,
    String? verifier,
    String? deviceName,
  }) async {
    final asked = _signOuts;
    oidcExchangeCalls.add((
      code: code,
      verifier: verifier,
      deviceName: deviceName,
    ));
    await oidcExchangeGate?.future;
    return _signInAsked(asked, token: 'oidc-token');
  }

  /// Thrown by [signup] when set.
  WaxDeckApiException? signupError;

  final List<
    ({
      String username,
      String password,
      String? displayName,
      String? inviteToken,
    })
  >
  signupCalls = [];

  @override
  Future<SignupResult> signup({
    required String username,
    required String password,
    String? displayName,
    String? inviteToken,
  }) async {
    signupCalls.add((
      username: username,
      password: password,
      displayName: displayName,
      inviteToken: inviteToken,
    ));
    await signupGate?.future;
    final error = signupError;
    if (error != null) throw error;
    // An invite activates the account immediately; open signup queues it.
    final active = inviteToken != null;
    final account = UserAccount(
      id: 'us-FAKE${userSeq++}',
      username: username,
      displayName: displayName,
      roles: const ['user'],
      createdAt: DateTime.utc(2026, 7, 15),
      libraryAccess: const LibraryAccess(mode: 'all'),
      pending: !active,
    );
    usersById[account.id] = account;
    return SignupResult(state: active ? 'active' : 'pending');
  }
}
