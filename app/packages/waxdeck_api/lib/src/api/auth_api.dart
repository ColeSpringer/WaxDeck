import '../models.dart';

/// Sign-up, login, sessions and single sign-on.
abstract interface class AuthApi {
  /// `GET /auth/bootstrap`: whether first-run setup is needed.
  Future<BootstrapStatus> bootstrapStatus();

  /// `POST /auth/bootstrap`: creates the server's first administrator and
  /// logs it in, exactly like [login]. Fails with `conflict` once any
  /// account exists.
  Future<LoginResult> bootstrap({
    required String username,
    required String password,
    String? displayName,
  });

  /// `POST /auth/login`: establishes a session. On success the client keeps
  /// the returned bearer token and applies it to subsequent calls; web
  /// builds additionally get the HttpOnly session cookie from the browser.
  /// [deviceName] labels the session in the device list.
  Future<LoginResult> login({
    required String username,
    required String password,
    String? deviceName,
  });

  /// `GET /auth/session`: whether the caller is authenticated, and as whom.
  /// Unauthenticated callers get a false state, never an error.
  Future<SessionState> getSession();

  /// `POST /auth/refresh`: rotates the caller's bearer token. The presented
  /// token stays valid for a short overlap window. Bearer-authenticated
  /// callers only.
  Future<LoginResult> refreshToken();

  /// `POST /auth/logout`: revokes the current session.
  Future<void> logout();

  /// `GET /auth/sessions`: every live session belonging to the calling
  /// user, newest first. Doubles as the device list.
  Future<List<DeviceSession>> listSessions();

  /// `PATCH /auth/sessions/{id}`: relabels one of the caller's sessions
  /// in the device list. The name is trimmed server-side and must not be
  /// empty afterwards.
  Future<DeviceSession> renameSession(String sessionId, String deviceName);

  /// `DELETE /auth/sessions/{id}`: revokes one of the caller's sessions.
  /// Revoking the session serving the request acts as a logout.
  Future<void> revokeSession(String sessionId);

  /// `GET /auth/oidc/providers`: configured single-sign-on providers, for
  /// rendering login buttons. Empty when SSO is not configured.
  Future<List<OidcProvider>> oidcProviders();

  /// `POST /auth/oidc/exchange`: redeems a one-time OIDC code for a
  /// session, exactly like [login]. [verifier] is required when the flow
  /// sent a challenge; first-party clients always send one.
  Future<LoginResult> oidcExchange({
    required String code,
    String? verifier,
    String? deviceName,
  });

  /// `POST /auth/signup`: requests an account. Anonymous; the result
  /// says whether the account is active now (invite or open signup
  /// with auto-approval) or pending administrator approval.
  Future<SignupResult> signup({
    required String username,
    required String password,
    String? displayName,
    String? inviteToken,
  });
}
