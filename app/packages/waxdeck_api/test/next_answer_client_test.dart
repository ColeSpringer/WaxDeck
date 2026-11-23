import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'support/recording_adapter.dart';

const _session = {
  'authenticated': true,
  'user': {
    'id': 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
    'username': 'listener',
    'roles': ['user'],
    'uploadEnabled': false,
  },
  'csrfToken': 'csrf-1',
};

const _items = {'items': <Object>[]};

/// Fails every request before any answer, as [fail] says.
class _OutOfReach implements HttpClientAdapter {
  _OutOfReach(this.fail);

  final DioException Function(RequestOptions options) fail;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => throw fail(options);

  @override
  void close({bool force = false}) {}
}

/// Answers every request with a page that is not the server's.
class _Portal implements HttpClientAdapter {
  _Portal(this.status);

  final int status;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '<html>Sign in to this network</html>',
    status,
    headers: {
      Headers.contentTypeHeader: ['text/html'],
    },
  );

  @override
  void close({bool force = false}) {}
}

/// What a client tells whoever waits to hear that the server is in reach:
/// the next answer that is the server's own, once.
void main() {
  late int heard;

  setUp(() => heard = 0);

  WaxDeckClient listening(HttpClientAdapter adapter) =>
      clientOn(adapter)..onNextAnswer = () => heard++;

  test('a call the server answers is said, once, and then forgotten', () async {
    final client = listening(RecordingAdapter(body: _items));

    await client.listItems();
    expect(heard, 1);
    expect(client.onNextAnswer, isNull);

    await client.listItems();
    expect(heard, 1);
  });

  test('a refusal in the server\'s own words is its answer too', () async {
    final client = listening(
      RecordingAdapter(
        status: 401,
        body: const {
          'code': 'unauthenticated',
          'message': 'no valid session or token was presented',
        },
      ),
    );

    await expectLater(
      client.listItems(),
      throwsA(
        isA<WaxDeckApiException>().having(
          (e) => e.code,
          'code',
          'unauthenticated',
        ),
      ),
    );
    expect(heard, 1);
  });

  test('a failure of the server\'s in its own words is its answer '
      'too', () async {
    final client = listening(
      RecordingAdapter(
        status: 500,
        body: const {'code': 'internal', 'message': 'internal error'},
      ),
    );

    await expectLater(client.listItems(), throwsA(isA<WaxDeckApiException>()));
    expect(heard, 1);
  });

  final notTheServer = <String, HttpClientAdapter>{
    'a refused connect': _OutOfReach(
      (options) => DioException.connectionError(
        requestOptions: options,
        reason: 'Connection refused',
      ),
    ),
    'a deadline': _OutOfReach(
      (options) => DioException.receiveTimeout(
        timeout: const Duration(seconds: 30),
        requestOptions: options,
      ),
    ),
    'a gateway with nothing behind it': RecordingAdapter(status: 502),
    'a sign-in page in front of the server': _Portal(401),
    'a page served in the server\'s place': _Portal(200),
  };
  for (final MapEntry(key: what, value: adapter) in notTheServer.entries) {
    test('$what is not the server answering', () async {
      final client = listening(adapter);

      await expectLater(
        client.listItems(),
        throwsA(isA<WaxDeckApiException>()),
      );
      expect(heard, 0);
      expect(client.onNextAnswer, isNotNull);
    });
  }

  test('a session read is heard by whoever asked it, and the next answer '
      'still waits', () async {
    final adapter = RecordingAdapter()
      ..enqueue(200, _session)
      ..enqueue(200, _items);
    final client = listening(adapter);

    await client.getSession();
    expect(heard, 0);

    await client.listItems();
    expect(heard, 1);
  });

  test('one set while an answer is said hears the answer after', () async {
    final client = clientOn(RecordingAdapter(body: _items));
    client.onNextAnswer = () {
      heard++;
      client.onNextAnswer = () => heard += 10;
    };

    await client.listItems();
    expect(heard, 1);
    await client.listItems();
    expect(heard, 11);
  });
}
