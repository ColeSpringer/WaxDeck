import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/connectivity/connectivity_port.dart';
import 'package:waxdeck/src/player/playback_session.dart';
import 'package:waxdeck/src/player/stream_quality.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/client_prefs.dart';
import 'package:waxdeck/src/settings/client_settings_providers.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

class _FakeConnectivity implements ConnectivityPort {
  final _controller = StreamController<ConnectionCost>.broadcast();
  ConnectionCost current = ConnectionCost.unmetered;

  void push(ConnectionCost cost) {
    current = cost;
    _controller.add(cost);
  }

  @override
  Future<ConnectionCost> cost() async => current;

  @override
  Stream<ConnectionCost> get costs => _controller.stream;
}

ProviderContainer _container({
  required bool mobile,
  ConnectivityPort? connectivity,
}) {
  final container = ProviderContainer(
    overrides: [
      mobileProvider.overrideWithValue(mobile),
      if (connectivity != null)
        connectivityProvider.overrideWithValue(connectivity),
      clientSettingsStoreProvider.overrideWithValue(
        MemoryClientSettingsStore(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('the quality words map to their caps, and Auto to none', () {
    expect(streamQualityKbps(StreamQuality.auto), isNull);
    expect(streamQualityKbps(StreamQuality.high), 320);
    expect(streamQualityKbps(StreamQuality.normal), 192);
    expect(streamQualityKbps(StreamQuality.low), 128);
  });

  test('off the mobile platforms the Wi-Fi value answers everywhere', () {
    final container = _container(mobile: false);
    expect(container.read(streamMaxBitrateKbpsProvider), isNull);
    container
        .read(streamQualityWifiProvider.notifier)
        .set(StreamQuality.normal);
    // The metered value is unreachable on a platform that cannot tell.
    container
        .read(streamQualityMeteredProvider.notifier)
        .set(StreamQuality.low);
    expect(container.read(streamMaxBitrateKbpsProvider), 192);
  });

  test('mobile resolves by the connection in use', () async {
    final connectivity = _FakeConnectivity();
    final container = _container(mobile: true, connectivity: connectivity);
    container.read(streamQualityWifiProvider.notifier).set(StreamQuality.high);
    container
        .read(streamQualityMeteredProvider.notifier)
        .set(StreamQuality.low);
    final sub = container.listen(streamMaxBitrateKbpsProvider, (_, _) {});
    addTearDown(sub.close);

    connectivity.push(ConnectionCost.metered);
    await pumpEventQueue();
    expect(sub.read(), 128);

    connectivity.push(ConnectionCost.unmetered);
    await pumpEventQueue();
    expect(sub.read(), 320);
  });

  test(
    'an unresolved first read guesses metered, then the seed answers',
    () async {
      final connectivity = _FakeConnectivity();
      final container = _container(mobile: true, connectivity: connectivity);
      container
          .read(streamQualityWifiProvider.notifier)
          .set(StreamQuality.high);
      container
          .read(streamQualityMeteredProvider.notifier)
          .set(StreamQuality.low);
      final sub = container.listen(streamMaxBitrateKbpsProvider, (_, _) {});
      addTearDown(sub.close);

      // Cold: nothing has answered yet, so the metered quality holds the
      // line - the setting exists to guard a data plan, and the change
      // stream alone would stay silent until the network moved.
      expect(sub.read(), 128);

      // The one-shot seed resolves without any change event firing.
      await pumpEventQueue();
      expect(sub.read(), 320);
    },
  );

  test('both on Auto resolves to no cap without asking the network', () {
    // No connectivity override at all: reaching for the port would throw
    // through the default, and the resolver must not need it for the
    // default answer.
    final container = _container(mobile: true);
    expect(container.read(streamMaxBitrateKbpsProvider), isNull);
  });

  test('a session passes its cap to every play-info it mints', () async {
    final repo = FakeRepository(items: [testItem('tr-AAA')]);
    final engine = FakeEngine();
    final session = PlaybackSession(
      repository: repo,
      engine: engine,
      item: testItem('tr-AAA'),
      clientId: 'test',
      maxBitrateKbps: 192,
    );
    await session.start();
    expect(repo.playInfoMaxBitrates, [192]);
    await session.dispose();
  });
}
