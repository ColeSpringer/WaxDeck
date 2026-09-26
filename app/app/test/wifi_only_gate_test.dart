import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/connectivity/connectivity_port.dart';
import 'package:waxdeck/src/downloads/wifi_only_gate.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/client_prefs.dart';
import 'package:waxdeck/src/settings/client_settings_providers.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

class _FakeConnectivity implements ConnectivityPort {
  ConnectionCost now = ConnectionCost.metered;
  final _costs = StreamController<ConnectionCost>.broadcast();

  /// Held open, [cost] answers what was true when it was asked.
  Completer<void>? costGate;

  @override
  Future<ConnectionCost> cost() async {
    final answer = now;
    if (costGate case final gate?) await gate.future;
    return answer;
  }

  @override
  Stream<ConnectionCost> get costs => _costs.stream;

  void move(ConnectionCost cost) {
    now = cost;
    _costs.add(cost);
  }
}

void main() {
  late _FakeConnectivity net;

  setUp(() => net = _FakeConnectivity());

  WifiOnlyGate gate({required bool wifiOnly}) {
    final gate = WifiOnlyGate(connectivity: net, wifiOnly: () => wifiOnly);
    addTearDown(gate.dispose);
    return gate;
  }

  test('open on any connection with the setting off', () async {
    expect(await gate(wifiOnly: false).isOpen(), isTrue);
  });

  test('shut on a metered connection with the setting on', () async {
    expect(await gate(wifiOnly: true).isOpen(), isFalse);
  });

  test('open on an unmetered connection with the setting on', () async {
    net.now = ConnectionCost.unmetered;

    expect(await gate(wifiOnly: true).isOpen(), isTrue);
  });

  test('says when the connection opens or shuts it', () async {
    final seen = <bool>[];
    final sub = gate(wifiOnly: true).changes.listen(seen.add);
    addTearDown(sub.cancel);

    net.move(ConnectionCost.unmetered);
    await pumpEventQueue();
    net.move(ConnectionCost.metered);
    await pumpEventQueue();

    expect(seen, [true, false]);
  });

  test('a slow answer never overrides a newer one', () async {
    final held = net.costGate = Completer<void>();
    final shut = gate(wifiOnly: true);
    final seen = <bool>[];
    final sub = shut.changes.listen(seen.add);
    addTearDown(sub.cancel);

    shut.settingChanged();
    await pumpEventQueue();
    net.move(ConnectionCost.unmetered);
    await pumpEventQueue();
    held.complete();
    await pumpEventQueue();

    expect(seen, [true], reason: 'the metered answer was asked for first');
  });

  test('the setting turning off releases the hold', () async {
    final container = ProviderContainer(
      overrides: [
        connectivityProvider.overrideWithValue(net),
        clientSettingsStoreProvider.overrideWithValue(
          MemoryClientSettingsStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final gate = container.read(transferGateProvider);
    expect(await gate.isOpen(), isFalse);
    final seen = <bool>[];
    final sub = gate.changes.listen(seen.add);
    addTearDown(sub.cancel);

    container.read(downloadsOnWifiOnlyProvider.notifier).set(false);
    await pumpEventQueue();

    expect(seen, [true]);
  });
}
