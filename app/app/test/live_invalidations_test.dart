import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/sync/live_invalidations.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

/// A channel whose connect resolves only when the test says so, which
/// is what a sign-out racing a slow handshake looks like.
class _GatedChannel extends EventsChannel {
  _GatedChannel({
    required this.gate,
    required super.onFrame,
    required super.onDone,
    required super.subscribe,
  }) : super(url: 'ws://gated', authToken: null);

  final Completer<void> gate;

  @override
  Future<void> connect() => gate.future;

  @override
  Future<void> close() async {}
}

void main() {
  test('a connect that resolves after stop() reports nothing', () async {
    final gate = Completer<void>();
    var caughtUp = 0;
    var reportedConnected = 0;
    final live = LiveInvalidations(
      channelFactory:
          ({required onFrame, required onDone, required subscribe}) =>
              _GatedChannel(
                gate: gate,
                onFrame: onFrame,
                onDone: onDone,
                subscribe: subscribe,
              ),
      onCatalog: () => caughtUp++,
      onUser: () => caughtUp++,
    );
    live.onConnectionChanged = (_) => reportedConnected++;

    live.start();
    // The session ends while the handshake is still in flight; the
    // socket then comes up for nobody.
    live.stop();
    gate.complete();
    await gate.future;
    await Future<void>.delayed(Duration.zero);

    expect(caughtUp, 0, reason: 'no refresh lands on a dead session');
    expect(reportedConnected, 0, reason: 'and no banner state changes');
  });

  test('a connect that resolves while running catches up once', () async {
    final gate = Completer<void>();
    var catalog = 0;
    var user = 0;
    final live = LiveInvalidations(
      channelFactory:
          ({required onFrame, required onDone, required subscribe}) =>
              _GatedChannel(
                gate: gate,
                onFrame: onFrame,
                onDone: onDone,
                subscribe: subscribe,
              ),
      onCatalog: () => catalog++,
      onUser: () => user++,
    );
    addTearDown(live.stop);

    live.start();
    gate.complete();
    await gate.future;
    await Future<void>.delayed(Duration.zero);

    expect(catalog, 1, reason: 'the may-have-missed-changes refresh');
    expect(user, 1);
  });

  test('a throw from the connected body is not a dropped socket', () async {
    final gate = Completer<void>();
    var factoryCalls = 0;
    var wentDown = 0;
    final live = LiveInvalidations(
      channelFactory:
          ({required onFrame, required onDone, required subscribe}) {
            factoryCalls++;
            return _GatedChannel(
              gate: gate,
              onFrame: onFrame,
              onDone: onDone,
              subscribe: subscribe,
            );
          },
      // The catch-up refresh breaks, the way a fan-out bug would.
      onCatalog: () => throw StateError('fan-out bug'),
      onUser: () {},
    );
    live.onConnectionChanged = (connected) {
      if (!connected) wentDown++;
    };
    addTearDown(live.stop);

    // The connect wiring happens inside start(), so the guarded zone
    // has to hold it: an unlistened future's error reports to the zone
    // its callbacks were registered in.
    final surfaced = <Object>[];
    runZonedGuarded(live.start, (error, _) => surfaced.add(error));
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(surfaced, [isA<StateError>()], reason: 'the bug is heard as itself');
    expect(wentDown, 0, reason: 'a healthy socket is not reported down');
    expect(factoryCalls, 1, reason: 'and no reconnect is scheduled');
  });

  test('an invalidation frame routes to its topic', () {
    // The frame path is the onFrame callback the listener hands its
    // channel; capturing it is how a test speaks as the server.
    late void Function(String) deliver;
    var user = 0;
    final live = LiveInvalidations(
      channelFactory:
          ({required onFrame, required onDone, required subscribe}) {
            deliver = onFrame;
            return _GatedChannel(
              gate: Completer<void>(),
              onFrame: onFrame,
              onDone: onDone,
              subscribe: subscribe,
            );
          },
      onCatalog: () => fail('catalog was not the topic'),
      onUser: () => user++,
    );
    addTearDown(live.stop);

    live.start();
    deliver(
      jsonEncode(const <String, Object?>{
        'type': 'invalidate',
        'topic': 'user',
      }),
    );
    expect(user, 1);
  });

  test('a resync naming an unknown topic still refreshes everything', () async {
    final gate = Completer<void>()..complete();
    var catalog = 0, user = 0, radio = 0;
    late void Function(String) deliver;
    final live = LiveInvalidations(
      channelFactory:
          ({required onFrame, required onDone, required subscribe}) {
            deliver = onFrame;
            return _GatedChannel(
              gate: gate,
              onFrame: onFrame,
              onDone: onDone,
              subscribe: subscribe,
            );
          },
      onCatalog: () => catalog++,
      onUser: () => user++,
    );
    live.onRadio = () => radio++;
    live.start();
    addTearDown(live.stop);
    await gate.future;
    await Future<void>.delayed(Duration.zero);
    catalog = 0;
    user = 0;

    // Continuity recovery must not narrow as cursorless topics are added.
    deliver(jsonEncode({'type': 'resync', 'topic': 'radio'}));

    expect(catalog, 1);
    expect(user, 1);
    expect(radio, 0, reason: 'a resync is not a nudge');
  });

  test('a radio frame nudges only the radio listener', () async {
    final gate = Completer<void>()..complete();
    var catalog = 0, user = 0, player = 0, radio = 0;
    late void Function(String) deliver;
    final live = LiveInvalidations(
      channelFactory:
          ({required onFrame, required onDone, required subscribe}) {
            deliver = onFrame;
            return _GatedChannel(
              gate: gate,
              onFrame: onFrame,
              onDone: onDone,
              subscribe: subscribe,
            );
          },
      onCatalog: () => catalog++,
      onUser: () => user++,
    );
    live.onPlayer = () => player++;
    live.onRadio = () => radio++;
    live.start();
    addTearDown(live.stop);
    await gate.future;
    await Future<void>.delayed(Duration.zero);
    // The connect itself catches up once; only the frame is under test.
    catalog = 0;
    user = 0;

    deliver(jsonEncode({'type': 'invalidate', 'topic': 'radio'}));

    expect(radio, 1);
    expect(player, 0, reason: 'a radio frame is not a player frame');
    expect(catalog, 0);
    expect(user, 0, reason: 'and pulls no mirrored stream');
  });
}
