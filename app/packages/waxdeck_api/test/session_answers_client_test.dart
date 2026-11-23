import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'support/recording_adapter.dart';

const _user = {
  'id': 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  'username': 'listener',
  'roles': ['user'],
  'uploadEnabled': false,
};

Map<String, Object> _login(String token, String csrf, String session) => {
  'user': _user,
  'token': token,
  'csrfToken': csrf,
  'sessionId': session,
};

/// Answers each request by the last segment of its path, in the order the
/// requests arrive; a path given a hold waits for it.
class _Server implements HttpClientAdapter {
  final answers = <String, List<(int, Object?)>>{};
  final holds = <String, Completer<void>>{};
  final requests = <RequestOptions>[];

  void answer(String path, int status, [Object? body]) =>
      (answers[path] ??= []).add((status, body));

  Completer<void> hold(String path) => holds[path] = Completer<void>();

  /// The headers of the request last sent to [path].
  Map<String, dynamic> sentTo(String path) =>
      requests.lastWhere((each) => each.path.endsWith(path)).headers;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.path.split('/').last;
    final queued = answers[path];
    final (status, body) = queued == null || queued.isEmpty
        ? (204, null)
        : queued.removeAt(0);
    await holds[path]?.future;
    final text = body == null ? '' : jsonEncode(body);
    return ResponseBody.fromString(
      text,
      status,
      headers: {
        if (text.isNotEmpty) Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// The three ways to sign in, each answering [answer] at its path.
final _signIns =
    <(String, String, Future<LoginResult> Function(WaxDeckClient))>[
      ('a sign-in', 'login', (c) => c.login(username: 'b', password: 'p')),
      (
        'a first administrator\'s',
        'bootstrap',
        (c) => c.bootstrap(username: 'b', password: 'p'),
      ),
      (
        'a single sign-on exchange',
        'exchange',
        (c) => c.oidcExchange(code: 'one-time'),
      ),
    ];

/// Every answer that holds a session says which, by the id the device list
/// gives it. A sign-in a sign-out has been asked since is answered to its
/// caller and not taken up, and a sign-out presents what was held when it
/// was asked.
void main() {
  test('a session read says which session answered it', () async {
    final server = _Server()
      ..answer('session', 200, {
        'authenticated': true,
        'user': _user,
        'csrfToken': 'csrf-ann',
        'sessionId': 'se-ann',
      })
      ..answer('session', 200, {'authenticated': false});
    final client = clientOn(server);

    expect((await client.getSession()).sessionId, 'se-ann');
    expect((await client.getSession()).sessionId, isNull);
  });

  for (final (road, path, signIn) in [
    ..._signIns,
    ('a token rotation', 'refresh', (WaxDeckClient c) => c.refreshToken()),
  ]) {
    test('$road that names no session does not read', () async {
      final server = _Server()
        ..answer(
          path,
          200,
          {..._login('tok-ben', 'csrf-ben', 'se-ben')}..remove('sessionId'),
        );
      await expectLater(
        signIn(clientOn(server)..authToken = 'tok-ann'),
        throwsA(
          isA<WaxDeckApiException>()
              .having((e) => e.code, 'code', 'transport-decode')
              .having((e) => e.message, 'message', contains('sessionId')),
        ),
      );
    });
  }

  for (final (road, path, signIn) in _signIns) {
    test('$road says which session it made', () async {
      final server = _Server()
        ..answer(path, 200, _login('tok-ben', 'csrf-ben', 'se-ben'));
      final result = await signIn(clientOn(server));
      expect(result.sessionId, 'se-ben');
    });

    test('$road answered after the bearer was dropped is answered and not '
        'taken up', () async {
      final server = _Server()
        ..answer(path, 200, _login('tok-ben', 'csrf-ben', 'se-ben'));
      final client = clientOn(server)..authToken = 'tok-ann';
      final held = server.hold(path);

      final answer = signIn(client);
      await pumpEventQueue();
      client.authToken = null;
      held.complete();

      expect((await answer).token, 'tok-ben');
      expect(client.authToken, isNull);
      await client.putPlayState('tr-x', 1000);
      expect(server.sentTo('play-state').containsKey('Authorization'), isFalse);
      expect(server.sentTo('play-state').containsKey('X-CSRF-Token'), isFalse);
    });
  }

  test('a sign-in sent before a sign-out was asked, answered after it, is not '
      'taken up: one sent since keeps its credentials', () async {
    final server = _Server()
      ..answer('login', 200, _login('tok-ben', 'csrf-ben', 'se-ben'))
      ..answer('login', 200, _login('tok-cid', 'csrf-cid', 'se-cid'));
    final client = clientOn(server);
    final held = server.hold('login');

    final first = client.login(username: 'ben', password: 'p');
    await pumpEventQueue();
    await client.logout();
    server.holds.remove('login');
    await client.login(username: 'cid', password: 'p');
    held.complete();
    await first;

    expect(client.authToken, 'tok-cid');
    await client.putPlayState('tr-x', 1000);
    expect(server.sentTo('play-state')['Authorization'], 'Bearer tok-cid');
    client.authToken = null;
    await client.putPlayState('tr-x', 1000);
    expect(server.sentTo('play-state')['X-CSRF-Token'], 'csrf-cid');
  });

  test('a sign-out presents the bearer held when it was asked, though it is '
      'dropped before the request goes', () async {
    final server = _Server();
    final client = clientOn(server)..authToken = 'tok-ann';

    final out = client.logout();
    client.authToken = null;
    await out;

    expect(server.sentTo('logout')['Authorization'], 'Bearer tok-ann');
  });

  test('a sign-out leaves what was taken up while it was out', () async {
    final server = _Server()
      ..answer('login', 200, _login('tok-ben', 'csrf-ben', 'se-ben'));
    final client = clientOn(server)..authToken = 'tok-ann';
    final held = server.hold('logout');

    final out = client.logout();
    await pumpEventQueue();
    client.authToken = null;
    await client.login(username: 'ben', password: 'p');
    held.complete();
    await out;

    expect(client.authToken, 'tok-ben');
    client.authToken = null;
    await client.putPlayState('tr-x', 1000);
    expect(server.sentTo('play-state')['X-CSRF-Token'], 'csrf-ben');
  });

  test('a sign-out by a given token presents it and moves nothing the '
      'client holds', () async {
    final server = _Server()
      ..answer('login', 200, _login('tok-ben', 'csrf-ben', 'se-ben'));
    final client = clientOn(server);
    await client.login(username: 'ben', password: 'p');

    await client.logoutToken('tok-ann');

    expect(server.sentTo('logout')['Authorization'], 'Bearer tok-ann');
    expect(server.sentTo('logout').containsKey('X-CSRF-Token'), isFalse);
    expect(client.authToken, 'tok-ben');
    await client.putPlayState('tr-x', 1000);
    expect(server.sentTo('play-state')['Authorization'], 'Bearer tok-ben');
  });
}
