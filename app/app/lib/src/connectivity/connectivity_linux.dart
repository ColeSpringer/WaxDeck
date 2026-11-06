import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/foundation.dart';

/// Keeps a Linux session with no NetworkManager, or no system bus at all,
/// from raising at launch: the stock plugin throws from inside stream
/// listens, where no subscriber can catch it.
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
  TolerantConnectivity(
    this._stock, {
    this.patience = const Duration(seconds: 5),
  });

  final ConnectivityPlatform _stock;

  /// How long the platform may take to answer. A system bus whose socket
  /// takes the connection while its daemon is wedged never does.
  final Duration patience;

  static const _assumed = <ConnectivityResult>[ConnectivityResult.ethernet];

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    try {
      return await _probe().timeout(patience);
    } on Object {
      return _assumed;
    }
  }

  /// The stock stream only once a probe has answered; one that answers
  /// past the patience brings it then.
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged async* {
    final probe = _probe();
    try {
      await probe.timeout(patience);
    } on TimeoutException {
      yield _assumed;
      try {
        await probe;
      } on Object {
        return;
      }
    } on Object {
      yield _assumed;
      return;
    }
    yield* _unheard(_stock.onConnectivityChanged);
  }

  /// The stock answer, which the stock call alone decides. It runs in a
  /// zone of its own: with no system bus, or behind a proxy that refuses a
  /// subscription, the plugin's D-Bus client also fails signal streams
  /// nothing handles errors on, before or after its answer, and those
  /// stay out of the app's zone.
  Future<List<ConnectivityResult>> _probe() {
    final answer = Completer<List<ConnectivityResult>>();
    runZonedGuarded(
      () => Future.sync(
        _stock.checkConnectivity,
      ).then(answer.complete, onError: answer.completeError),
      (_, _) {},
    );
    return answer.future;
  }

  /// [stream], listened to in a zone that drops its errors, and its error
  /// events dropped too: the stock stream raises where nothing listens
  /// (its listen rethrows a failed connect, and its signal subscription
  /// has no error handler), and a failure is no change to report.
  Stream<T> _unheard<T>(Stream<T> stream) {
    StreamSubscription<T>? source;
    late final StreamController<T> out;
    out = StreamController<T>(
      onListen: () => runZonedGuarded(
        () => source = stream.listen(
          out.add,
          onError: (Object _) {},
          onDone: out.close,
        ),
        (_, _) {},
      ),
      onPause: () => source?.pause(),
      onResume: () => source?.resume(),
      // Not returned: a future made in that zone cannot carry its error
      // out of it, so a cancel awaiting one could wait forever.
      onCancel: () {
        runZonedGuarded(() => source?.cancel(), (_, _) {});
      },
    );
    return out.stream;
  }
}
