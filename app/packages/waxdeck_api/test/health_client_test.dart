import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'support/recording_adapter.dart';

Future<ServerHealth> _health(Map<String, Object?> body) =>
    clientOn(RecordingAdapter(body: body)).health();

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
