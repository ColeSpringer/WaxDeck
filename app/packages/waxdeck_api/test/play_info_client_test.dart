import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

/// Answers every request with one HLS play-info and records it.
class _PlayInfoAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({
        'pid': 'tr-1',
        'url': '/media/hls/master.m3u8?it=k&mt=t',
        'mimeType': 'application/vnd.apple.mpegurl',
        'durationMs': 214000,
        'seekable': true,
        'expiresAt': '2026-10-16T00:00:00Z',
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('play-info says the caller plays HLS only when asked to', () async {
    final adapter = _PlayInfoAdapter();
    final client = WaxDeckClient(
      baseUrl: 'http://host:4420',
      dio: Dio()..httpClientAdapter = adapter,
    );
    final info = await client.getPlayInfo(
      'tr-1',
      maxBitrateKbps: 96,
      hls: true,
    );
    expect(adapter.requests.last.uri.queryParameters['hls'], 'true');
    expect(info.url, 'http://host:4420/media/hls/master.m3u8?it=k&mt=t');
    expect(info.seekable, isTrue);

    await client.getPlayInfo('tr-1', maxBitrateKbps: 96);
    expect(
      adapter.requests.last.uri.queryParameters.containsKey('hls'),
      isFalse,
    );
  });
}
