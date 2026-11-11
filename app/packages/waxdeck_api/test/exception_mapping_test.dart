import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

DioException _dioError(Object? data, {int status = 400}) {
  final options = RequestOptions(path: '/api/v1/test');
  return DioException(
    requestOptions: options,
    response: Response(requestOptions: options, statusCode: status, data: data),
    message: 'transport-level detail',
  );
}

void main() {
  test('parsed map bodies surface the structured error', () {
    final e = apiExceptionFromDio(
      _dioError({'code': 'invalid-request', 'message': 'bad cursor'}),
    );
    expect(e.code, 'invalid-request');
    expect(e.message, 'bad cursor');
    expect(e.statusCode, 400);
  });

  test('raw string bodies are decoded before falling back', () {
    final e = apiExceptionFromDio(
      _dioError('{"code":"not-found","message":"no such item"}', status: 404),
    );
    expect(e.code, 'not-found');
    expect(e.message, 'no such item');
    expect(e.statusCode, 404);
  });

  test('non-JSON string bodies fall back to a transport error', () {
    final e = apiExceptionFromDio(_dioError('<html>gateway timeout</html>'));
    expect(e.code, 'transport');
    expect(e.message, 'transport-level detail');
  });

  test('JSON bodies without the error shape fall back too', () {
    final e = apiExceptionFromDio(_dioError('["not","an","error"]'));
    expect(e.code, 'transport');
  });

  test('a bytes body is read as the error it carries', () {
    // A call that asks for bytes gets its error body as bytes too.
    final e = apiExceptionFromDio(
      _dioError(
        Uint8List.fromList(
          utf8.encode('{"code":"not-found","message":"no such item"}'),
        ),
        status: 404,
      ),
    );
    expect(e.code, 'not-found');
    expect(e.message, 'no such item');
    expect(e.statusCode, 404);
  });

  test('a bytes body that is not an error falls back with its status', () {
    final e = apiExceptionFromDio(
      _dioError(Uint8List.fromList(utf8.encode('Bad Gateway')), status: 502),
    );
    expect(e.code, 'transport');
    expect(e.statusCode, 502);
  });

  // A deadline has no response to read a code out of, so it is
  // recognized by type. All three of dio's timeout types map to one
  // name: what a caller does about "the server did not answer in time"
  // is the same whichever phase ran out.
  test('every dio timeout maps to the transport-timeout code', () {
    // Client-minted, and deliberately not the spec's `timeout`: that
    // enum value means a player-routed command whose endpoint is still
    // connected, and a handler written to it must not also catch plain
    // HTTP deadlines.
    final options = RequestOptions(path: '/api/v1/test');
    for (final type in <DioExceptionType>[
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
    ]) {
      final e = apiExceptionFromDio(
        DioException(requestOptions: options, type: type, message: 'timed out'),
      );
      expect(e.code, 'transport-timeout', reason: '$type');
      expect(e.statusCode, isNull);
    }
  });

  // The detail behind an umbrella code. A caller keys on it instead of
  // matching the message's prose, so what does and does not become a
  // param has to be exact.
  test('only no answer, a 503 or a proxy\'s gateway error is out of reach', () {
    // The one rule both outboxes queue on: a refusal is an answer, and a
    // change the server refused must not wait to be refused again.
    WaxDeckApiException failure(int? status, {String code = 'x'}) =>
        WaxDeckApiException(code: code, message: 'x', statusCode: status);
    expect(failure(null).unreachable, isTrue);
    expect(failure(503).unreachable, isTrue);
    expect(failure(500).unreachable, isFalse);
    expect(failure(400).unreachable, isFalse);
    expect(failure(401).unreachable, isFalse);
    // A gateway answering without the server's words: the server is down
    // or restarting behind it. 521 to 524 and 530 are a CDN or tunnel
    // saying the same for an origin it cannot reach.
    for (final status in [502, 504, 521, 522, 523, 524, 530]) {
      expect(
        failure(status, code: 'transport').unreachable,
        isTrue,
        reason: '$status',
      );
      // The server's own words make it an answer about something else.
      expect(
        failure(status, code: 'service-unreachable').unreachable,
        isFalse,
        reason: '$status',
      );
    }
    expect(failure(504, code: 'feed-unreachable').unreachable, isFalse);
    expect(failure(500, code: 'transport').unreachable, isFalse);
  });

  test('an answer that arrived is never out of reach', () {
    for (final code in ['transport-empty', 'transport-decode']) {
      expect(
        WaxDeckApiException(
          code: code,
          message: 'x',
          statusCode: 200,
        ).unreachable,
        isFalse,
        reason: code,
      );
    }
  });

  group('an error object off the wire', () {
    test('is a string code and message, with its status', () {
      final e = apiErrorFromWire({
        'code': 'not-found',
        'message': 'no such item',
        'params': {'pid': 'tr-1'},
      }, statusCode: 404);
      expect(e?.code, 'not-found');
      expect(e?.message, 'no such item');
      expect(e?.statusCode, 404);
      expect(e?.params, {'pid': 'tr-1'});
    });

    test('is nothing else', () {
      for (final raw in <Object?>[
        null,
        'not-found',
        ['not-found', 'no'],
        {'message': 'no'},
        {'code': 'not-found'},
        {'code': 404, 'message': 'no'},
        {'code': 'not-found', 'message': 7},
      ]) {
        expect(apiErrorFromWire(raw), isNull, reason: '$raw');
      }
    });
  });

  group('structured params', () {
    test('a string map carries through', () {
      final e = apiExceptionFromDio(
        _dioError({
          'code': 'feature-unavailable',
          'message': 'this track is a window into a larger file',
          'params': {'feature': 'windowed-track', 'pid': 'tr-1'},
        }),
      );
      expect(e.params, {'feature': 'windowed-track', 'pid': 'tr-1'});
    });

    test('an error without params reports null, not an empty map', () {
      final e = apiExceptionFromDio(
        _dioError({'code': 'not-found', 'message': 'no such item'}),
      );
      expect(e.params, isNull);
    });

    test('a value that is not a string drops its key', () {
      final e = apiExceptionFromDio(
        _dioError({
          'code': 'feature-unavailable',
          'message': 'nope',
          'params': {'feature': 'windowed-track', 'parts': 3},
        }),
      );
      expect(e.params, {'feature': 'windowed-track'});
    });

    test('params that are not an object at all report null', () {
      final e = apiExceptionFromDio(
        _dioError({
          'code': 'feature-unavailable',
          'message': 'nope',
          'params': 'windowed-track',
        }),
      );
      expect(e.params, isNull);
    });
  });

  test('the client arms connect and receive deadlines, and not send', () {
    final dio = Dio();
    WaxDeckClient(baseUrl: 'http://example.invalid', dio: dio);
    expect(dio.options.connectTimeout, const Duration(seconds: 10));
    expect(dio.options.receiveTimeout, const Duration(seconds: 30));
    // Unset on purpose: it budgets the request body, and an upload chunk
    // on a slow uplink is a legitimate slow send.
    expect(dio.options.sendTimeout, isNull);
  });

  test('a refusal is a 4xx and nothing else', () {
    bool refused(int? status) => WaxDeckApiException(
      code: 'x',
      message: 'x',
      statusCode: status,
    ).isRefusal;
    expect([400, 404, 409, 499].map(refused), everyElement(isTrue));
    expect([null, 304, 399, 500, 503].map(refused), everyElement(isFalse));
  });

  test('a 4xx without the server\'s own error code is not its refusal', () {
    // Something in front of the server answered: a proxy with no route
    // for the path, or a server too old to have it. Neither is the server
    // saying no, and asking again may well get another answer.
    const proxied = WaxDeckApiException(
      code: 'transport',
      message: '404 page not found',
      statusCode: 404,
    );
    expect(proxied.isRefusal, isFalse);
    expect(proxied.isNotFound, isFalse);
  });

  test('not-found is the server\'s own code, however it arrived', () {
    // Over HTTP with its status, or over the socket with none.
    for (final status in <int?>[404, null]) {
      expect(
        WaxDeckApiException(
          code: 'not-found',
          message: 'no such item',
          statusCode: status,
        ).isNotFound,
        isTrue,
      );
    }
  });

  test('a job has ended in exactly the four states the contract names', () {
    bool ended(String state) =>
        Job(pid: 'jb-1', kind: 'scan', state: state).ended;
    expect(
      ['done', 'failed', 'crashed', 'canceled'].map(ended),
      everyElement(isTrue),
    );
    // An unknown state reads as unfinished, as the contract has it.
    expect(['queued', 'running', 'settling'].map(ended), everyElement(isFalse));
  });
}
