import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/connect/connect_bus.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

void main() {
  test('command acks resolve their own futures', () async {
    final sent = <Map<String, Object?>>[];
    final bus = ConnectBus(
      send: (f) {
        sent.add(f);
        return true;
      },
    );

    final first = bus.sendCmd('ps-1', 'pause');
    final second = bus.sendCmd('ps-1', 'seek', positionMs: 5000);
    expect(sent, hasLength(2));
    final firstId = sent[0]['id'] as String;
    final secondId = sent[1]['id'] as String;
    expect(firstId, isNot(secondId));
    expect(sent[1]['positionMs'], 5000);

    // Answer out of order; each future resolves on its own id.
    bus.handleFrame({'type': 'ack', 'id': secondId});
    await second;
    bus.handleFrame({'type': 'ack', 'id': firstId});
    await first;
  });

  test('error frames reject with the carried code', () async {
    final bus = ConnectBus(send: (_) => true);
    final future = bus.sendCmd('ps-1', 'play');
    bus.handleFrame({
      'type': 'error',
      'id': 'c1',
      'code': 'endpoint-offline',
      'message': 'gone',
    });
    await expectLater(
      future,
      throwsA(
        isA<WaxDeckApiException>().having(
          (e) => e.code,
          'code',
          'endpoint-offline',
        ),
      ),
    );
  });

  test('a refusal keeps its params over the socket too', () async {
    // One refusal can arrive over REST or over the socket, and the
    // explainer reads `params` to tell one `feature-unavailable` from
    // another - dropping them here would flatten every refusal on this
    // channel into the umbrella sentence.
    final bus = ConnectBus(send: (_) => true);
    final future = bus.sendCmd('ps-1', 'play');
    bus.handleFrame({
      'type': 'error',
      'id': 'c1',
      'code': 'feature-unavailable',
      'message': 'this track is a window into a larger file',
      'params': {'feature': 'windowed-track', 'pid': 'tr-x'},
    });
    await expectLater(
      future,
      throwsA(
        isA<WaxDeckApiException>().having((e) => e.params, 'params', {
          'feature': 'windowed-track',
          'pid': 'tr-x',
        }),
      ),
    );
  });

  test('a frame without params carries none', () async {
    // Null rather than an empty map: the explainer branches on a key
    // being there, and a pre-params server sends no field at all.
    final bus = ConnectBus(send: (_) => true);
    final future = bus.sendCmd('ps-1', 'play');
    bus.handleFrame({
      'type': 'error',
      'id': 'c1',
      'code': 'conflict',
      'message': 'busy',
    });
    await expectLater(
      future,
      throwsA(
        isA<WaxDeckApiException>().having((e) => e.params, 'params', isNull),
      ),
    );
  });

  test('an offline channel rejects immediately', () async {
    final bus = ConnectBus(send: (_) => false);
    await expectLater(
      bus.sendCmd('ps-1', 'play'),
      throwsA(
        isA<WaxDeckApiException>().having(
          (e) => e.code,
          'code',
          'local-channel-offline',
        ),
      ),
    );
  });

  test('registration resolves to the endpoint id', () async {
    final sent = <Map<String, Object?>>[];
    final bus = ConnectBus(
      send: (f) {
        sent.add(f);
        return true;
      },
    );
    final future = bus.registerEndpoint(name: 'Phone');
    bus.handleFrame({
      'type': 'ack',
      'id': sent.single['id'],
      'endpointId': 'pe-abc',
    });
    expect(await future, 'pe-abc');
  });

  test('pong computes the server clock offset NTP style', () {
    var now = DateTime.utc(2026, 7, 21, 12, 0, 0);
    final bus = ConnectBus(send: (_) => true, now: () => now);
    bus.ping();
    // The round trip takes 200ms; the server stamped 5 seconds ahead
    // of the local midpoint.
    now = now.add(const Duration(milliseconds: 200));
    final midpoint = DateTime.utc(2026, 7, 21, 12, 0, 0, 100);
    final serverAt = midpoint.add(const Duration(seconds: 5));
    bus.handleFrame({
      'type': 'pong',
      't': 0,
      'at': serverAt.millisecondsSinceEpoch,
    });
    expect(bus.serverClockOffset, const Duration(seconds: 5));
  });

  test('watch routes only the watched session to the stream', () async {
    final bus = ConnectBus(send: (_) => true);
    final frames = <PlaybackSessionInfo>[];
    bus.watchFrames.listen(frames.add);
    bus.watch('ps-watched');

    Map<String, Object?> sessionFrame(String id) => {
      'type': 'session',
      'session': {
        'id': id,
        'endpointId': 'pe-1',
        'mine': true,
        'authority': 'remote',
        'playing': true,
        'index': 0,
        'positionMs': 1000,
        'positionAt': '2026-07-21T12:00:00.000Z',
        'rate': 1.0,
        'queueVersion': 1,
      },
    };
    bus.handleFrame(sessionFrame('ps-other'));
    bus.handleFrame(sessionFrame('ps-watched'));
    await Future<void>.delayed(Duration.zero);
    expect(frames, hasLength(1));
    expect(frames.single.id, 'ps-watched');
  });
}
