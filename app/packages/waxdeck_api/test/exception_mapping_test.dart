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
}
