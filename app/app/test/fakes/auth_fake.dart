import 'dart:async';

import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [AuthApi] for `FakeRepository`.
mixin FakeAuth on FakeRepositoryState implements AuthApi {
  /// Thrown by [login] when set, to exercise the error path.
  WaxDeckApiException? loginError;

  /// Thrown by [bootstrap] when set, to exercise the error path.
  WaxDeckApiException? bootstrapError;

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

  static const _user = WaxDeckUser(
    id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
    username: 'admin',
    roles: ['admin'],
  );

  /// Whether the server this fake stands for is in read-only mode, as a
  /// session it opens reports.
  bool serverReadOnly = false;

  LoginResult _signIn({WaxDeckUser user = _user, String token = 'test-token'}) {
    sessionState = SessionState(
      authenticated: true,
      user: user,
      serverReadOnly: serverReadOnly,
    );
    authToken = token;
    return LoginResult(user: user, token: token);
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
    bootstrapCalls.add((
      username: username,
      password: password,
      displayName: displayName,
    ));
    final error = bootstrapError;
    if (error != null) throw error;
    bootstrapNeeded = false;
    return _signIn(
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
    loginCalls.add((
      username: username,
      password: password,
      deviceName: deviceName,
    ));
    final error = loginError;
    if (error != null) throw error;
    return _signIn();
  }

  /// Holds every session read until completed, when set: the session
  /// a screen is mounted under has not answered yet.
  Completer<void>? getSessionGate;

  @override
  Future<SessionState> getSession() async {
    await getSessionGate?.future;
    return sessionState;
  }

  @override
  Future<LoginResult> refreshToken() async {
    refreshCalls++;
    final error = refreshError;
    if (error != null) throw error;
    return _signIn(token: 'rotated-token');
  }

  @override
  Future<void> logout() async {
    sessionState = const SessionState(authenticated: false);
    authToken = null;
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
    oidcExchangeCalls.add((
      code: code,
      verifier: verifier,
      deviceName: deviceName,
    ));
    return _signIn(token: 'oidc-token');
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
