import 'dart:async';

import 'package:dio/dio.dart';
import 'package:waxdeck_api/waxdeck_api.dart' show owedRevokeRequest;

/// Where a signed-in session that can be in doubt holds the API transport:
/// a browser's, whose cookie another tab can sign another account in over.
/// The web sync binder binds its doubt's `pass` for as long as it lives; a
/// native session, whose bearer names one session, binds nothing.
class SessionGate {
  Future<bool> Function()? _pass;

  /// Whether a session holds requests here now.
  bool get bound => _pass != null;

  /// [pass] answers, for each request, whether it may go; it is asked in
  /// the request's own zone, so it can tell [inSessionWork].
  void bind(Future<bool> Function() pass) => _pass = pass;

  /// Lets go of [pass], unless another was bound since.
  void unbind(Future<bool> Function() pass) {
    if (identical(_pass, pass)) _pass = null;
  }
}

/// Holds each request on the [gate]'s binding, and fails one it refuses as
/// a transport failure without sending it.
///
/// The session's own routes ([sessionRoutes]) go at once, and so does the
/// revoke a sign-out owes, by the mark on its request: the read that ends
/// a doubt waits on some of them (a revoke owed goes first), and signing
/// in or out says whose the cookie is rather than asking. Every other
/// request asks, the caller's list of its sessions and a revoke from the
/// devices screen included.
class SessionGateInterceptor extends Interceptor {
  SessionGateInterceptor(this.gate);

  final SessionGate gate;

  /// The session's own routes, as `METHOD /path` with the spec's path
  /// template: the session read, signing in, up and out, the token's
  /// refresh, the first account's bootstrap and the OIDC sign-in. Any
  /// other route asks, under `/auth/` too.
  static const sessionRoutes = <String>{
    'GET /auth/session',
    'POST /auth/login',
    'POST /auth/logout',
    'POST /auth/signup',
    'POST /auth/refresh',
    'GET /auth/bootstrap',
    'POST /auth/bootstrap',
    'GET /auth/oidc/providers',
    'GET /auth/oidc/start',
    'GET /auth/oidc/callback',
    'POST /auth/oidc/exchange',
  };

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final pass = gate._pass;
    if (pass == null || _sessionsOwn(options)) {
      handler.next(options);
      return;
    }
    Future.sync(pass).then(
      (go) => go ? handler.next(options) : handler.reject(_refused(options)),
      onError: (Object _) => handler.reject(_refused(options)),
    );
  }

  static bool _sessionsOwn(RequestOptions options) =>
      options.extra[owedRevokeRequest] == true ||
      sessionRoutes.contains('${options.method.toUpperCase()} ${options.path}');

  /// What a refused request fails with, unsent: the transport, as for a
  /// link that is down, with why for whoever reads a log.
  static DioException _refused(RequestOptions options) => DioException(
    requestOptions: options,
    type: DioExceptionType.connectionError,
    error: StateError(
      'not sent: the session it would go out under is in doubt',
    ),
  );
}

/// Runs [work] as the session flow's own: a session read, or a road one
/// joins. A gated request made in it while the session is in doubt fails
/// at once, unsent: the read it would wait on may be waiting on it, and
/// the client may hold another account's cookie and token by then.
Future<T> asSessionWork<T>(Future<T> Function() work) async {
  final mark = _SessionWork();
  try {
    return await runZoned(
      () => Future.sync(work),
      zoneValues: {_sessionWorkKey: mark},
    );
  } finally {
    mark.out = false;
  }
}

/// Whether this runs in session work still under way. Work it left behind
/// (a timer, a listener) is not: the mark ends as the work lands.
bool get inSessionWork => switch (Zone.current[_sessionWorkKey]) {
  _SessionWork(out: true) => true,
  _ => false,
};

final _sessionWorkKey = Object();

class _SessionWork {
  var out = true;
}
