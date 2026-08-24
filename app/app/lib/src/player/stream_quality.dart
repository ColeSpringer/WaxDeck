import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connectivity/connectivity_port.dart';
import '../providers.dart';
import '../settings/client_prefs.dart';

/// The connection cost as a live value, so a per-network setting can be
/// resolved synchronously at session build. Seeded with the one-shot
/// answer before following changes: the change stream is change-only,
/// so without the seed a cold launch reads nothing until the network
/// moves - which on cellular is the whole listen.
final connectionCostProvider = StreamProvider<ConnectionCost>((ref) async* {
  final port = ref.watch(connectivityProvider);
  yield await port.cost();
  yield* port.costs;
});

/// The bitrate cap play-info is asked for on the connection in use
/// right now; null streams the original. Resolved through the same
/// connectivity signal the Wi-Fi-only switches read; platforms that
/// cannot tell a metered connection apart resolve the Wi-Fi value
/// everywhere. Both settings on Auto skip the connectivity watch
/// entirely, so the default costs nothing.
final streamMaxBitrateKbpsProvider = Provider<int?>((ref) {
  final wifi = ref.watch(streamQualityWifiProvider);
  if (!ref.watch(mobileProvider)) return streamQualityKbps(wifi);
  final metered = ref.watch(streamQualityMeteredProvider);
  if (wifi == StreamQuality.auto && metered == StreamQuality.auto) {
    return null;
  }
  final cost = ref.watch(connectionCostProvider).value;
  // A read the seed has not resolved yet guesses metered, the port's
  // own documented direction: holding one track to the metered quality
  // on a connection that turns out to be wifi costs a little fidelity
  // once; the other way around spends somebody's data plan.
  final onMetered = (cost ?? ConnectionCost.metered) == ConnectionCost.metered;
  return streamQualityKbps(onMetered ? metered : wifi);
});
