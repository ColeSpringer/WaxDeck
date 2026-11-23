import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'support/recording_adapter.dart';

const _user = {
  'id': 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  'username': 'listener',
  'roles': ['user'],
  'uploadEnabled': false,
};

Map<String, Object> _login(String token, String csrf) => {
  'user': _user,
  'token': token,
  'csrfToken': csrf,
  'sessionId': 'se-1',
};

/// Holds the rotation's answer until [release], and answers the rest at
/// once, in call order.
class _HeldRotation implements HttpClientAdapter {
  _HeldRotation([this.rest = const []]);

  final List<(int, Object?)> rest;
  final release = Completer<void>();
  final requests = <RequestOptions>[];
  var _answered = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    Object? body;
    var status = 200;
    if (options.path.endsWith('/auth/refresh')) {
      await release.future;
      body = _login('tok-rotated', 'csrf-rotated');
    } else {
      (status, body) = rest[_answered++];
    }
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

/// A rotated token is the bearer of the credentials it was asked with. One
/// that lands after they moved, a sign-out or another sign-in, is still
/// answered to its caller and is never sent.
void main() {
  test('a rotation nothing moved under becomes the bearer', () async {
    final adapter = _HeldRotation([(204, null)]);
    final client = clientOn(adapter)..authToken = 'tok-ann';

    final rotation = client.refreshToken();
    adapter.release.complete();

    expect((await rotation).token, 'tok-rotated');
    expect(client.authToken, 'tok-rotated');
    await client.putPlayState('tr-x', 1000);
    expect(
      adapter.requests.last.headers['Authorization'],
      'Bearer tok-rotated',
    );
  });

  test('a rotation its token was dropped under is not taken up', () async {
    final adapter = _HeldRotation([(204, null)]);
    final client = clientOn(adapter)..authToken = 'tok-ann';

    final rotation = client.refreshToken();
    client.authToken = null;
    adapter.release.complete();

    expect((await rotation).token, 'tok-rotated');
    expect(client.authToken, isNull);
    await client.putPlayState('tr-x', 1000);
    final put = adapter.requests.last;
    expect(put.headers.containsKey('Authorization'), isFalse);
    expect(put.headers.containsKey('X-CSRF-Token'), isFalse);
  });

  test('a rotation another sign-in overtook leaves that sign-in\'s token '
      'and CSRF token', () async {
    final adapter = _HeldRotation([
      (200, _login('tok-ben', 'csrf-ben')),
      (204, null),
      (204, null),
    ]);
    final client = clientOn(adapter)..authToken = 'tok-ann';

    final rotation = client.refreshToken();
    await client.login(username: 'ben', password: 'pw');
    adapter.release.complete();

    expect((await rotation).token, 'tok-rotated');
    expect(client.authToken, 'tok-ben');
    await client.putPlayState('tr-x', 1000);
    expect(adapter.requests.last.headers['Authorization'], 'Bearer tok-ben');

    // Cookie mode, as a web build rides it.
    client.authToken = null;
    await client.putPlayState('tr-x', 1000);
    expect(adapter.requests.last.headers['X-CSRF-Token'], 'csrf-ben');
  });

  test('a rotation another token was restored under is not taken '
      'up', () async {
    final adapter = _HeldRotation();
    final client = clientOn(adapter)..authToken = 'tok-ann';

    final rotation = client.refreshToken();
    client.authToken = 'tok-ben';
    adapter.release.complete();
    await rotation;

    expect(client.authToken, 'tok-ben');
  });

  test('the same token set again moves nothing: its rotation is taken '
      'up', () async {
    final adapter = _HeldRotation();
    final client = clientOn(adapter)..authToken = 'tok-ann';

    final rotation = client.refreshToken();
    client.authToken = 'tok-ann';
    adapter.release.complete();
    await rotation;

    expect(client.authToken, 'tok-rotated');
  });
}
