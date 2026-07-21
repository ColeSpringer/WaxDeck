import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/connect/connect_bus.dart';
import 'package:waxdeck/src/connect/connect_controller.dart';
import 'package:waxdeck/src/player/session_registry.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

const pidA = 'tr-01JZX5N8QW3F4V9T2B7KDAAAAA1';
const pidB = 'tr-01JZX5N8QW3F4V9T2B7KDBBBBB2';

({
  ConnectEndpointController controller,
  ConnectBus bus,
  List<Map<String, Object?>> sent,
  FakeRepository repo,
  FakeEngine engine,
})
_build() {
  final sent = <Map<String, Object?>>[];
  final bus = ConnectBus(
    send: (f) {
      sent.add(Map.of(f));
      return true;
    },
  );
  final repo = FakeRepository(items: [testItem(pidA), testItem(pidB)]);
  final engine = FakeEngine(mediaDuration: const Duration(seconds: 30));
  final controller = ConnectEndpointController(
    bus: bus,
    repository: repo,
    engine: engine,
    registry: CurrentSessionRegistry(),
    deviceName: 'Test device',
    clientId: 'test-client',
  );
  controller.wire();
  return (
    controller: controller,
    bus: bus,
    sent: sent,
    repo: repo,
    engine: engine,
  );
}

Iterable<Map<String, Object?>> _ofType(
  List<Map<String, Object?>> sent,
  String type,
) => sent.where((f) => f['type'] == type);

void main() {
  test('registration acks resolve and mark the endpoint id', () async {
    final h = _build();
    final started = h.controller.start();
    final reg = _ofType(h.sent, 'register-endpoint').single;
    expect(reg['name'], 'Test device');
    h.bus.handleFrame({'type': 'ack', 'id': reg['id'], 'endpointId': 'pe-me'});
    await started;
    expect(h.controller.endpointId.value, 'pe-me');
  });

  test('a load plays the queue and reports it, then advances', () async {
    final h = _build();
    h.bus.handleFrame({
      'type': 'endpoint-cmd',
      'id': 'e1',
      'sessionId': 'ps-1',
      'verb': 'load',
      'itemPids': [pidA, pidB],
      'index': 0,
      'positionMs': 4000,
      'play': true,
    });
    await pumpEventQueue();

    // The engine plays the first item at the asked position.
    expect(h.engine.loadedUrl, contains(pidA));
    expect(h.engine.position, const Duration(seconds: 4));
    expect(h.engine.playing, isTrue);

    // Exactly one ok result answered the load.
    final results = _ofType(h.sent, 'cmd-result').toList();
    expect(results, hasLength(1));
    expect(results.single['id'], 'e1');
    expect(results.single['ok'], isTrue);

    // The report after the load carries the queue, and the load's
    // session id was adopted for later transfers from this device.
    final reports = _ofType(h.sent, 'session-report').toList();
    expect(reports, isNotEmpty);
    expect(reports.last['itemPids'], [pidA, pidB]);
    expect(h.controller.mirrorSessionId, 'ps-1');

    // Completion advances to the next item and reports the new index.
    h.engine.advance(const Duration(seconds: 40));
    await pumpEventQueue();
    expect(h.engine.loadedUrl, contains(pidB));
    final after = _ofType(h.sent, 'session-report').toList();
    expect(after.last['index'], 1);

    h.controller.dispose();
  });

  test('seek, volume, and pause commands drive the engine', () async {
    final h = _build();
    h.bus.handleFrame({
      'type': 'endpoint-cmd',
      'id': 'e1',
      'sessionId': 'ps-1',
      'verb': 'load',
      'itemPids': [pidA],
      'index': 0,
      'positionMs': 0,
      'play': true,
    });
    await pumpEventQueue();

    h.bus.handleFrame({
      'type': 'endpoint-cmd',
      'id': 'e2',
      'sessionId': 'ps-1',
      'verb': 'seek',
      'positionMs': 12000,
    });
    await pumpEventQueue();
    expect(h.engine.position, const Duration(seconds: 12));

    h.bus.handleFrame({
      'type': 'endpoint-cmd',
      'id': 'e3',
      'sessionId': 'ps-1',
      'verb': 'set-volume',
      'volume': 0.25,
    });
    await pumpEventQueue();
    expect(h.engine.volume, 0.25);

    h.bus.handleFrame({
      'type': 'endpoint-cmd',
      'id': 'e4',
      'sessionId': 'ps-1',
      'verb': 'pause',
    });
    await pumpEventQueue();
    expect(h.engine.playing, isFalse);

    final oks = _ofType(h.sent, 'cmd-result').map((f) => f['ok']).toList();
    expect(oks, everyElement(isTrue));
    h.controller.dispose();
  });

  test('queue skips step the connect queue for head units', () async {
    final h = _build();
    h.bus.handleFrame({
      'type': 'endpoint-cmd',
      'id': 'e1',
      'sessionId': 'ps-1',
      'verb': 'load',
      'itemPids': [pidA, pidB],
      'index': 0,
      'positionMs': 0,
      'play': true,
    });
    await pumpEventQueue();
    expect(h.engine.loadedUrl, contains(pidA));

    expect(await h.controller.nextInQueue(), isTrue);
    await pumpEventQueue();
    expect(h.engine.loadedUrl, contains(pidB));

    // Past the end refuses; back steps home.
    expect(await h.controller.nextInQueue(), isFalse);
    expect(await h.controller.previousInQueue(), isTrue);
    await pumpEventQueue();
    expect(h.engine.loadedUrl, contains(pidA));

    // No queue at all: skips answer false so the handler stays quiet.
    final bare = _build();
    expect(await bare.controller.nextInQueue(), isFalse);
    expect(await bare.controller.previousInQueue(), isFalse);

    h.controller.dispose();
    bare.controller.dispose();
  });

  test('a detached controller stops reporting on engine flips', () async {
    final h = _build();
    h.bus.handleFrame({
      'type': 'endpoint-cmd',
      'id': 'e1',
      'sessionId': 'ps-1',
      'verb': 'load',
      'itemPids': [pidA],
      'index': 0,
      'positionMs': 0,
      'play': true,
    });
    await pumpEventQueue();

    // Stop tears the queue down; later engine activity (another
    // surface taking the engine) must not produce session reports.
    h.bus.handleFrame({
      'type': 'endpoint-cmd',
      'id': 'e2',
      'sessionId': 'ps-1',
      'verb': 'stop',
    });
    await pumpEventQueue();
    final before = _ofType(h.sent, 'session-report').length;

    await h.engine.load('http://x/other');
    await h.engine.play();
    await pumpEventQueue();
    expect(_ofType(h.sent, 'session-report').length, before);
    h.controller.dispose();
  });

  test('an unknown verb answers ok false', () async {
    final h = _build();
    h.bus.handleFrame({
      'type': 'endpoint-cmd',
      'id': 'e9',
      'sessionId': 'ps-1',
      'verb': 'levitate',
    });
    await pumpEventQueue();
    final result = _ofType(h.sent, 'cmd-result').single;
    expect(result['id'], 'e9');
    expect(result['ok'], isFalse);
    h.controller.dispose();
  });
}
