import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Whether this device is on a connection worth spending bytes on.
///
/// Two values, not the platform's list of transports, because two is
/// what every caller asks: a preload is armed or held back, a download
/// starts now or waits. Naming the transports here would put a switch
/// statement about VPNs and Bluetooth tethering into every reader.
enum ConnectionCost {
  /// Wifi, ethernet, or anything else nobody is billed by the byte for.
  unmetered,

  /// Mobile data, or an unknown transport read as mobile data. The
  /// direction of the guess is deliberate: holding a preload back on a
  /// connection that turned out to be free costs one track's buffering,
  /// and getting it wrong the other way spends somebody's data plan.
  metered,
}

/// What kind of connection this device is on.
///
/// The wrapping rule (`connectivity_plus` never appears above this
/// line), and a narrower question than the plugin answers. Note what it
/// deliberately does not report: whether there is a connection at all.
/// Offline is not a third value here because neither caller wants it -
/// a request on a dead connection fails on its own, and answering
/// "metered" for it holds back exactly the speculative work that would
/// have failed anyway.
abstract interface class ConnectivityPort {
  /// The cost right now.
  Future<ConnectionCost> cost();

  /// Cost changes, for readers that hold a state rather than asking at
  /// the moment they act.
  Stream<ConnectionCost> get costs;
}

/// The port over `connectivity_plus`.
///
/// The platform's own metered flag would be the exact answer and no
/// plugin exposes it portably (Android has `isActiveNetworkMetered`,
/// which is not on this plugin's surface). The transport is the honest
/// stand-in, and it happens to be
/// the question the settings themselves ask: they say "on wifi only",
/// not "on an unmetered connection".
class PluginConnectivity implements ConnectivityPort {
  PluginConnectivity([Connectivity? plugin])
    : _plugin = plugin ?? Connectivity();

  final Connectivity _plugin;

  @override
  Future<ConnectionCost> cost() async {
    try {
      return _classify(await _plugin.checkConnectivity());
    } on Object {
      // A plugin that will not answer must not decide anybody's data
      // plan for them: unmetered is what the app did before this port
      // existed, so a failure here is the old behaviour rather than a
      // silent new restriction.
      return ConnectionCost.unmetered;
    }
  }

  @override
  Stream<ConnectionCost> get costs =>
      _plugin.onConnectivityChanged.map(_classify).distinct();

  /// The plugin reports every transport the device has up at once, so a
  /// laptop on wifi with a VPN answers two. Any unmetered transport
  /// makes the connection unmetered: the OS routes over the cheap one
  /// where it can, and a VPN's own transport says nothing about what
  /// carries it.
  static ConnectionCost _classify(List<ConnectivityResult> results) {
    for (final result in results) {
      switch (result) {
        case ConnectivityResult.wifi:
        case ConnectivityResult.ethernet:
          return ConnectionCost.unmetered;
        case ConnectivityResult.none:
        case ConnectivityResult.mobile:
        case ConnectivityResult.bluetooth:
        case ConnectivityResult.vpn:
        case ConnectivityResult.satellite:
        case ConnectivityResult.other:
          continue;
      }
    }
    // Nothing unmetered was named. An empty list arrives on platforms
    // that answer nothing at all, and reads the same way every other
    // unknown does.
    return ConnectionCost.metered;
  }
}

/// The web build's answer.
///
/// A browser tab is told nothing about the connection under it that is
/// worth acting on, and neither wifi-only setting is offered there:
/// there is no download manager on web, and a listener at a desk is not
/// the person the metered brake is for.
class UnmeteredConnectivity implements ConnectivityPort {
  const UnmeteredConnectivity();

  @override
  Future<ConnectionCost> cost() async => ConnectionCost.unmetered;

  @override
  Stream<ConnectionCost> get costs => const Stream<ConnectionCost>.empty();
}

/// The port for this platform.
ConnectivityPort createConnectivityPort() =>
    kIsWeb ? const UnmeteredConnectivity() : PluginConnectivity();
