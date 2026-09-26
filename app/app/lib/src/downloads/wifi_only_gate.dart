import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import '../connectivity/connectivity_port.dart';
import '../providers.dart';
import '../settings/client_prefs.dart';

/// The download manager's wifi-only hold: shut while the setting asks for
/// an unmetered connection and this one is not.
class WifiOnlyGate implements TransferGate {
  WifiOnlyGate({required this.connectivity, required this.wifiOnly});

  final ConnectivityPort connectivity;
  final bool Function() wifiOnly;

  final _settings = StreamController<void>.broadcast();

  @override
  Future<bool> isOpen() async =>
      !wifiOnly() || await connectivity.cost() == ConnectionCost.unmetered;

  @override
  Stream<bool> get changes {
    ConnectionCost? cost;
    final subscriptions = <StreamSubscription<Object?>>[];
    late final StreamController<bool> out;
    // Only the latest answer is said: one that waited on the platform may
    // come back after a newer one that did not.
    var asked = 0;
    Future<void> emit() async {
      final ask = ++asked;
      final open =
          !wifiOnly() ||
          (cost ?? await connectivity.cost()) == ConnectionCost.unmetered;
      if (ask == asked && !out.isClosed) out.add(open);
    }

    out = StreamController<bool>(
      onListen: () => subscriptions
        ..add(
          connectivity.costs.listen((next) {
            cost = next;
            unawaited(emit());
          }, onError: (Object _) {}),
        )
        ..add(_settings.stream.listen((_) => unawaited(emit()))),
      onCancel: () => Future.wait([for (final s in subscriptions) s.cancel()]),
    );
    return out.stream.distinct();
  }

  /// Re-asks after the setting moved.
  void settingChanged() => _settings.add(null);

  void dispose() => _settings.close();
}

/// The manager's gate, told when the setting moves.
final transferGateProvider = Provider<WifiOnlyGate>((ref) {
  final gate = WifiOnlyGate(
    connectivity: ref.read(connectivityProvider),
    wifiOnly: () => ref.read(downloadsOnWifiOnlyProvider),
  );
  // On the container: the manager reads this once and nothing watches it,
  // and an unwatched provider's own listeners are paused.
  final setting = ref.container.listen(
    downloadsOnWifiOnlyProvider,
    (_, _) => gate.settingChanged(),
  );
  ref.onDispose(() {
    setting.close();
    gate.dispose();
  });
  return gate;
});
