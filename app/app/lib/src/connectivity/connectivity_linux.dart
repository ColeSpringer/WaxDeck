import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/foundation.dart';

/// Keeps a Linux session with no NetworkManager from raising at launch:
/// the stock plugin throws from inside its stream's listen, where no
/// subscriber can catch it.
void installTolerantConnectivity() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.linux) return;
  ConnectivityPlatform.instance = TolerantConnectivity(
    ConnectivityPlatform.instance,
  );
}

/// Answers ethernet where the platform cannot answer, never `none`: the
/// downloader parks a failed transfer with no retry while it believes the
/// device is offline.
class TolerantConnectivity extends ConnectivityPlatform {
  TolerantConnectivity(this._stock);

  final ConnectivityPlatform _stock;

  static const _assumed = <ConnectivityResult>[ConnectivityResult.ethernet];

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    try {
      return await _stock.checkConnectivity();
    } on Object {
      return _assumed;
    }
  }

  /// The stock stream only once a probe has answered.
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged async* {
    try {
      await _stock.checkConnectivity();
    } on Object {
      yield _assumed;
      return;
    }
    yield* _stock.onConnectivityChanged;
  }
}
