import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

/// One browser's cookie: a sign-in or a session read answers for whoever
/// it names now, and every request is kept with the CSRF token it carried.
class _Cookie implements HttpClientAdapter {
  String account = 'ann';

  /// Every request that reached the server, as `PUT /items/tr-1/star
  /// csrf-ann` (`-` for none).
  final presented = <String>[];

  Map<String, Object?> get _user => {
    'id': 'us-$account',
    'username': account,
    'roles': ['user'],
    'uploadEnabled': false,
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst('/api/v1', '');
    final csrf = options.headers['X-CSRF-Token'];
    presented.add('${options.method} $path ${csrf ?? '-'}');
    final body = switch ((options.method, path)) {
      ('POST', '/auth/login') => {
        'user': _user,
        'token': 'token-$account',
        'sessionId': 'se-$account',
        'csrfToken': 'csrf-$account',
      },
      ('GET', '/auth/session') => {
        'authenticated': true,
        'user': _user,
        'sessionId': 'se-$account',
        'csrfToken': 'csrf-$account',
      },
      ('PUT', _) => {
        'pid': 'tr-1',
        'positionMs': 0,
        'played': false,
        'finished': false,
        'playCount': 0,
        'starred': true,
      },
      _ => <String, Object?>{},
    };
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Holds each request but the session's own until [release] completes,
/// while one is set: a gate in front of the client's own credentials, as
/// the app's is.
class _Held extends Interceptor {
  Completer<void>? release;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!options.path.startsWith('/auth/')) await release?.future;
    handler.next(options);
  }
}

/// What [call] ended as: `answered`, or the API error's code.
Future<String> _outcome(Future<Object?> call) => call.then<String>(
  (_) => 'answered',
  onError: (Object e) => e is WaxDeckApiException ? e.code : '$e',
);

void main() {
  late _Cookie server;
  late _Held held;
  late WaxDeckClient client;

  /// Signed in as [who] over the cookie, as a browser's client rides it.
  Future<void> signIn(String who) async {
    server.account = who;
    await client.login(username: who, password: 'pw');
    client.authToken = null;
  }

  setUp(() {
    server = _Cookie();
    held = _Held();
    client = WaxDeckClient(
      baseUrl: 'http://server.test',
      dio: Dio()
        ..interceptors.add(held)
        ..httpClientAdapter = server,
    );
  });

  test('an account\'s view lends the client\'s own credentials, and is the '
      'same one each time it is asked for', () async {
    await signIn('ann');
    final anns = client.forAccount('us-ann');
    expect(client.forAccount('us-ann'), same(anns));
    expect((anns as AccountCredentials).boundAccount, 'us-ann');
    expect(client.boundAccount, isNull);

    expect(await _outcome(anns.setStar('tr-1', true)), 'answered');
    expect(server.presented.last, 'PUT /items/tr-1/star csrf-ann');
    // A credential set on the client is the view's too.
    client.authToken = 'token-ann';
    expect(anns.authToken, 'token-ann');
  });

  test('the views of accounts that left are let go; the account held keeps '
      'its own', () async {
    await signIn('ann');
    final anns = client.forAccount('us-ann');
    await signIn('ben');
    final bens = client.forAccount('us-ben');

    expect(client.forAccount('us-ben'), same(bens));
    expect(client.forAccount('us-ann'), isNot(same(anns)));

    await client.logout();
    expect(client.forAccount('us-ben'), isNot(same(bens)));
  });

  test('a call made through a view once the client holds another account '
      'is refused unsent, and so is one made before and let go after; the '
      'client\'s own and the next account\'s view go', () async {
    await signIn('ann');
    final anns = client.forAccount('us-ann');

    held.release = Completer<void>();
    final waiting = _outcome(anns.setStar('tr-1', true));
    await pumpEventQueue();
    await signIn('ben');
    held.release!.complete();
    held.release = null;
    expect(await waiting, 'transport');

    final from = server.presented.length;
    expect(await _outcome(anns.setStar('tr-1', true)), 'transport');
    expect(server.presented.skip(from), isEmpty);

    expect(await _outcome(client.setStar('tr-1', true)), 'answered');
    expect(
      await _outcome(client.forAccount('us-ben').setStar('tr-1', true)),
      'answered',
    );
    expect(server.presented.skip(from), [
      'PUT /items/tr-1/star csrf-ben',
      'PUT /items/tr-1/star csrf-ben',
    ]);
  });

  test('what a view refuses is told apart from a link that failed', () async {
    await signIn('ann');
    final anns = client.forAccount('us-ann');
    await signIn('ben');

    final refused = await anns
        .setStar('tr-1', true)
        .then<Object?>((_) => null, onError: (Object e) => e);
    expect(refused, isA<AccountNotHeldException>());
    final error = refused! as WaxDeckApiException;
    expect(error.code, 'transport');
    expect(error.unreachable, isTrue);
  });

  test('a view\'s calls are its own account\'s whatever work runs them; the '
      'client\'s own are the work\'s', () async {
    await signIn('ben');
    final anns = client.forAccount('us-ann');
    final bens = client.forAccount('us-ben');

    expect(
      await madeFor('us-ben', () => _outcome(anns.setStar('tr-1', true))),
      'transport',
    );
    expect(
      await madeFor('us-ann', () => _outcome(bens.setStar('tr-1', true))),
      'answered',
    );
    expect(
      await madeFor('us-ann', () => _outcome(client.setStar('tr-1', true))),
      'transport',
    );
  });

  test('a view whose account the client no longer holds has nothing to send '
      'on the way out', () async {
    await signIn('ann');
    final anns = client.forAccount('us-ann');
    expect(anns.exitRequests(pid: 'tr-1', positionMs: 1000), hasLength(1));
    expect(
      anns
          .exitRequests(pid: 'tr-1', positionMs: 1000)
          .single
          .headers['X-CSRF-Token'],
      'csrf-ann',
    );

    await signIn('ben');
    expect(anns.exitRequests(pid: 'tr-1', positionMs: 1000), isEmpty);
    expect(
      client.forAccount('us-ben').exitRequests(pid: 'tr-1', positionMs: 1000),
      hasLength(1),
    );
  });

  test('a revoke owed presents the token the last read found, another '
      'account\'s included; a revoke by id presents the one held', () async {
    await signIn('ann');
    server.account = 'ben';
    expect((await client.getSession()).user?.id, 'us-ben');

    await client.revokeSession('se-ann-2');
    expect(server.presented.last, 'DELETE /auth/sessions/se-ann-2 csrf-ann');
    await client.revokeOwedSession('se-old');
    expect(server.presented.last, 'DELETE /auth/sessions/se-old csrf-ben');
  });
}
