import 'package:dio/dio.dart';
import 'package:waxdeck_api_gen/waxdeck_api_gen.dart' as gen;

import 'models.dart';

/// Thin repository layer over the generated dart-dio client.
///
/// Current surface: health only. It proves the spec to generated-client to
/// wrapper to app pipeline end to end. Auth, browse, and play-info wrappers
/// grow here over time.
class WaxDeckClient {
  /// [baseUrl] is the server origin. On web builds pass an empty string:
  /// relative URLs resolve against the single origin serving the SPA.
  WaxDeckClient({String baseUrl = ''})
    : _gen = gen.WaxdeckApiGen(
        // Strip trailing slashes so a baseUrl like "http://host:4420/" doesn't
        // produce "//api/v1", a non-canonical path the server 301-redirects,
        // which can drop the body on POST /auth/login.
        dio: Dio(
          BaseOptions(
            baseUrl: '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v1',
          ),
        ),
      );

  final gen.WaxdeckApiGen _gen;

  /// `GET /health`: liveness and version probe.
  Future<ServerHealth> health() async {
    try {
      final response = await _gen.getSystemApi().getHealth();
      final body = response.data;
      if (body == null) {
        throw const WaxDeckApiException(
          code: 'internal',
          message: 'empty health response',
        );
      }
      return ServerHealth(
        status: body.status,
        version: body.version,
        apiVersion: body.apiVersion,
      );
    } on DioException catch (e) {
      throw _asApiException(e);
    }
  }

  /// Maps transport-level failures to the spec's structured error model.
  WaxDeckApiException _asApiException(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final code = data['code'];
      final message = data['message'];
      if (code is String && message is String) {
        return WaxDeckApiException(
          code: code,
          message: message,
          statusCode: e.response?.statusCode,
        );
      }
    }
    return WaxDeckApiException(
      code: 'transport',
      message: e.message ?? 'network error',
      statusCode: e.response?.statusCode,
    );
  }
}
