import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/connectivity/connectivity_linux.dart';

/// The stock plugin: answering, or failing the way a Linux session with
/// no NetworkManager does.
class _Stock extends ConnectivityPlatform {
  _Stock({this.fails = false});

  final bool fails;
  final changes = StreamController<List<ConnectivityResult>>.broadcast();
  var listens = 0;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    if (fails) throw StateError('org.freedesktop.DBus.Error.ServiceUnknown');
    return const [ConnectivityResult.wifi];
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged {
    listens++;
    return changes.stream;
  }
}

void main() {
  test('a platform that cannot answer reads as ethernet', () async {
    final tolerant = TolerantConnectivity(_Stock(fails: true));

    expect(await tolerant.checkConnectivity(), [ConnectivityResult.ethernet]);
  });

  test(
    'its changes say ethernet once and end without the stock stream',
    () async {
      final stock = _Stock(fails: true);

      final seen = await TolerantConnectivity(
        stock,
      ).onConnectivityChanged.toList();

      expect(seen, [
        [ConnectivityResult.ethernet],
      ]);
      expect(stock.listens, 0);
    },
  );

  test('a platform that answers is passed through', () async {
    final stock = _Stock();
    final tolerant = TolerantConnectivity(stock);
    expect(await tolerant.checkConnectivity(), [ConnectivityResult.wifi]);
    final seen = <List<ConnectivityResult>>[];
    final sub = tolerant.onConnectivityChanged.listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();

    stock.changes.add(const [ConnectivityResult.mobile]);
    await pumpEventQueue();

    expect(seen, [
      [ConnectivityResult.mobile],
    ]);
    expect(stock.listens, 1);
  });
}
