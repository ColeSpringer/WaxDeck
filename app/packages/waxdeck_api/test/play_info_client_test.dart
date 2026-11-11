import 'package:test/test.dart';

import 'support/recording_adapter.dart';

void main() {
  test('play-info says the caller plays HLS only when asked to', () async {
    final adapter = RecordingAdapter(
      body: {
        'pid': 'tr-1',
        'url': '/media/hls/master.m3u8?it=k&mt=t',
        'mimeType': 'application/vnd.apple.mpegurl',
        'durationMs': 214000,
        'seekable': true,
        'expiresAt': '2026-10-16T00:00:00Z',
      },
    );
    final client = clientOn(adapter);
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
