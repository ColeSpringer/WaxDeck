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

/// Whether the wifi-only gate is what holds an unfinished transfer back:
/// shut, and the transfer one the manager moves and the listener has not
/// paused. One reading for an item's own state and for the Downloads
/// screen's rows.
bool heldForWifi({
  required bool gateShut,
  required bool paused,
  required bool active,
}) => gateShut && active && !paused;

/// Whether the wifi-only gate holds transfers back now: one answer for
/// every transfer, followed once however many surfaces draw one.
///
/// Follows the gate before asking it, so a change in between is not
/// missed, and keeps only the latest answer: an ask that waited on the
/// platform may come back after a newer change.
final transfersHeldProvider = StreamProvider.autoDispose<bool>((ref) {
  final WifiOnlyGate gate;
  try {
    gate = ref.watch(transferGateProvider);
  } on Object {
    // A gate that cannot be built holds nothing back this can name.
    return Stream<bool>.value(false);
  }
  final out = StreamController<bool>();
  var asks = 0;
  final changes = gate.changes.listen((open) {
    asks++;
    out.add(!open);
  }, onError: (Object _) {});
  final ask = ++asks;
  unawaited(
    gate.isOpen().then((open) {
      if (ask == asks && !out.isClosed) out.add(!open);
    }, onError: (Object _) {}),
  );
  ref.onDispose(() {
    unawaited(changes.cancel());
    unawaited(out.close());
  });
  return out.stream.distinct();
});
