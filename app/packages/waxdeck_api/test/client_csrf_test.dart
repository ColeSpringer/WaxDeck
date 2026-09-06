import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

/// Serves canned responses in call order and records every request, so
/// tests can pin exactly which headers the client attaches.
class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<(int, String)> _canned = [];

  void enqueue(int status, [Object? body]) {
    _canned.add((status, body == null ? '' : jsonEncode(body)));
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (_canned.isEmpty) {
      fail('unexpected request ${options.method} ${options.path}');
    }
    final (status, body) = _canned.removeAt(0);
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        if (body.isNotEmpty) Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _userJson = {
  'id': 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  'username': 'admin',
  'roles': ['admin'],
  'uploadEnabled': true,
};

Map<String, Object> _loginJson({
  String token = 'tok-1',
  String csrf = 'csrf-1',
}) => {'user': _userJson, 'token': token, 'csrfToken': csrf};

(_RecordingAdapter, WaxDeckClient) _client() {
  final adapter = _RecordingAdapter();
  final dio = Dio()..httpClientAdapter = adapter;
  return (adapter, WaxDeckClient(baseUrl: 'http://host:4420', dio: dio));
}

void main() {
  _exitBeaconTests();

  test(
    'cookie mode: mutations echo the CSRF token from the session probe',
    () async {
      final (adapter, client) = _client();
      adapter.enqueue(200, {
        'authenticated': true,
        'user': _userJson,
        'csrfToken': 'csrf-web',
      });
      adapter.enqueue(204);

      final session = await client.getSession();
      expect(session.authenticated, isTrue);

      await client.putPlayState('tr-x', 1000);
      final put = adapter.requests.last;
      expect(put.method, 'PUT');
      expect(put.headers['X-CSRF-Token'], 'csrf-web');
      expect(put.headers.containsKey('Authorization'), isFalse);
    },
  );

  test('cookie mode: reads never carry the CSRF token', () async {
    final (adapter, client) = _client();
    adapter.enqueue(200, {
      'authenticated': true,
      'user': _userJson,
      'csrfToken': 'csrf-web',
    });
    adapter.enqueue(200, {'items': <Object>[]});

    await client.getSession();
    await client.listItems();
    final get = adapter.requests.last;
    expect(get.method, 'GET');
    expect(get.headers.containsKey('X-CSRF-Token'), isFalse);
  });

  test('bearer mode: mutations carry the token and skip CSRF', () async {
    final (adapter, client) = _client();
    adapter.enqueue(200, _loginJson(token: 'tok-native'));
    adapter.enqueue(204);

    final result = await client.login(
      username: 'admin',
      password: 'pw',
      deviceName: 'Study desktop',
    );
    expect(result.token, 'tok-native');
    expect(client.authToken, 'tok-native');
    expect(
      adapter.requests.first.data,
      containsPair('deviceName', 'Study desktop'),
    );

    await client.putPlayState('tr-x', 1000);
    final put = adapter.requests.last;
    expect(put.headers['Authorization'], 'Bearer tok-native');
    expect(put.headers.containsKey('X-CSRF-Token'), isFalse);
  });

  test('an unauthenticated probe drops a stale CSRF token', () async {
    final (adapter, client) = _client();
    adapter.enqueue(200, {
      'authenticated': true,
      'user': _userJson,
      'csrfToken': 'csrf-old',
    });
    adapter.enqueue(200, {'authenticated': false});
    adapter.enqueue(204);

    await client.getSession();
    await client.getSession();
    await client.putPlayState('tr-x', 1000);
    expect(adapter.requests.last.headers.containsKey('X-CSRF-Token'), isFalse);
  });

  test('logout clears both credentials', () async {
    final (adapter, client) = _client();
    adapter.enqueue(200, _loginJson());
    adapter.enqueue(204);
    adapter.enqueue(204);

    await client.login(username: 'admin', password: 'pw');
    await client.logout();
    expect(client.authToken, isNull);

    await client.putPlayState('tr-x', 1000);
    final put = adapter.requests.last;
    expect(put.headers.containsKey('Authorization'), isFalse);
    expect(put.headers.containsKey('X-CSRF-Token'), isFalse);
  });

  test('refresh adopts the rotated token', () async {
    final (adapter, client) = _client();
    adapter.enqueue(200, _loginJson(token: 'tok-old'));
    adapter.enqueue(200, _loginJson(token: 'tok-new'));
    adapter.enqueue(204);

    await client.login(username: 'admin', password: 'pw');
    final rotated = await client.refreshToken();
    expect(rotated.token, 'tok-new');
    expect(client.authToken, 'tok-new');

    await client.putPlayState('tr-x', 1000);
    expect(adapter.requests.last.headers['Authorization'], 'Bearer tok-new');
  });

  test('a restored token is applied without any login call', () async {
    final (adapter, client) = _client();
    adapter.enqueue(204);

    client.authToken = 'tok-restored';
    await client.putPlayState('tr-x', 1000);
    expect(
      adapter.requests.single.headers['Authorization'],
      'Bearer tok-restored',
    );
  });
}

// Each exit beacon stands alone. A closing tab can hold a gapless
// rendering and have nothing to check point beside it - the session
// already reported, or the item went away while the stream played on -
// and that release is the one thing here nothing else can do later:
// the server counts the listener as listening until it hears otherwise.
void _exitBeaconTests() {
  test('a release rides on its own with nothing to check point', () {
    final (_, client) = _client();
    final sent = client.exitRequests(timelinePids: const ['tl-alone']);
    expect(sent, hasLength(1));
    expect(sent.single.method, 'DELETE');
    expect(sent.single.path, endsWith('/api/v1/player/timeline/tl-alone'));
  });

  // A queue edit mints a replacement beside the rendering playing, and
  // the server counts the listener as being on both: a slot is per
  // listener, so releasing one and leaving the other means the release
  // frees nothing at all.
  test('every rendering held is handed back, not just the one playing', () {
    final (_, client) = _client();
    final sent = client.exitRequests(
      pid: 'tr-1',
      positionMs: 10,
      timelinePids: const ['tl-playing', 'tl-pending'],
    );
    final released = [
      for (final r in sent)
        if (r.method == 'DELETE') r.path,
    ];
    expect(released, hasLength(2));
    expect(released.first, endsWith('tl-playing'));
    expect(released.last, endsWith('tl-pending'));
  });

  test('a checkpoint with no rendering rides on its own too', () {
    final (_, client) = _client();
    final sent = client.exitRequests(pid: 'tr-1', positionMs: 4200);
    expect(sent, hasLength(1));
    expect(sent.single.method, 'PUT');
    expect(sent.single.path, endsWith('/api/v1/items/tr-1/play-state'));
  });
}
