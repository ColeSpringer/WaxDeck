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

  test('the client arms connect and receive deadlines, and not send', () {
    final dio = Dio();
    WaxDeckClient(baseUrl: 'http://example.invalid', dio: dio);
    expect(dio.options.connectTimeout, const Duration(seconds: 10));
    expect(dio.options.receiveTimeout, const Duration(seconds: 30));
    // Unset on purpose: it budgets the request body, and an upload chunk
    // on a slow uplink is a legitimate slow send.
    expect(dio.options.sendTimeout, isNull);
  });
}
