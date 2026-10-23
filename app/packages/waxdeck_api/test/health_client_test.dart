import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

/// Answers every request with one health body.
class _HealthAdapter implements HttpClientAdapter {
  _HealthAdapter(this.body);

  final Map<String, Object?> body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(body),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

Future<ServerHealth> _health(Map<String, Object?> body) => WaxDeckClient(
  baseUrl: 'http://host:4420',
  dio: Dio()..httpClientAdapter = _HealthAdapter(body),
).health();

void main() {
  const base = {'status': 'ok', 'version': '1.0.0', 'apiVersion': 1};

  test('health carries the streaming engine and the podcast switch', () async {
    final health = await _health({
      ...base,
      'streaming': {
        'configured': true,
        'connected': false,
        'timelines': false,
        'voiceBoost': false,
        'fileTools': false,
      },
      'podcasts': false,
    });
    expect(health.streaming?.configured, isTrue);
    expect(health.streaming?.connected, isFalse);
    expect(health.podcasts, isFalse);

    final up = await _health({
      ...base,
      'streaming': {
        'configured': true,
        'connected': true,
        'timelines': true,
        'voiceBoost': true,
        'fileTools': true,
      },
      'podcasts': true,
    });
    final streaming = up.streaming!;
    expect(streaming.connected && streaming.timelines, isTrue);
    expect(streaming.voiceBoost && streaming.fileTools, isTrue);
    expect(up.podcasts, isTrue);
  });

  test('an older server says nothing of either', () async {
    final health = await _health(base);
    expect(health.streaming, isNull);
    expect(health.podcasts, isNull);
  });
}
