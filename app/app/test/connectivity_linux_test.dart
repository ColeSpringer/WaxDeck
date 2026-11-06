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

/// Fails a stream nothing handles errors on, as the stock plugin's D-Bus
/// client opens its signal subscriptions: the error raises where nobody
/// listens.
void _raiseUnheard(String why) {
  final signals = StreamController<void>();
  signals.stream.listen((_) {});
  signals.addError(StateError(why));
}

/// The stock plugin with such an error around its answer, [before] it or
/// after it: before a failed answer with no system bus at all, before a
/// good one behind a proxy that refuses only the signal subscription.
class _Unheard extends _Stock {
  _Unheard({super.fails, required this.before});

  final bool before;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    if (before) {
      _raiseUnheard('no /var/run/dbus/system_bus_socket');
      await pumpEventQueue();
      return super.checkConnectivity();
    }
    try {
      return await super.checkConnectivity();
    } finally {
      Timer.run(() => _raiseUnheard('the signal subscription, refused late'));
    }
  }
}

/// The stock plugin answering only after [late], or never, as through a
/// system bus whose socket takes the connection while its daemon is
/// wedged.
class _Slow extends _Stock {
  _Slow({this.late});

  final Duration? late;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() {
    final after = late;
    if (after == null) return Completer<List<ConnectivityResult>>().future;
    return Future.delayed(after, super.checkConnectivity);
  }
}

/// The stock plugin whose change stream breaks after a good probe, the way
/// the real one does when its own D-Bus session fails: it raises where
/// nothing listens, and its listen rethrows, having sent one change.
class _BreakingChanges extends _Stock {
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged {
    listens++;
    late final StreamController<List<ConnectivityResult>> out;
    out = StreamController.broadcast(
      onListen: () async {
        out.add(const [ConnectivityResult.wifi]);
        _raiseUnheard('NetworkManager left the bus');
        await pumpEventQueue();
        throw StateError('org.freedesktop.DBus.Error.ServiceUnknown');
      },
    );
    return out.stream;
  }
}

/// Until the tolerant stream has subscribed to [stock]'s changes, which a
/// probe that takes its time puts off.
Future<void> _subscribed(_Stock stock) async {
  for (var i = 0; i < 100 && !stock.changes.hasListener; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  // Short, for the cases about patience; the rest keep the default, which
  // an answer due at once never comes near.
  const patience = Duration(milliseconds: 50);

  test(
    'a platform with no system bus reads as ethernet, raising nothing',
    () async {
      final tolerant = TolerantConnectivity(
        _Unheard(fails: true, before: true),
      );

      expect(await tolerant.checkConnectivity(), [ConnectivityResult.ethernet]);
      expect(await tolerant.onConnectivityChanged.toList(), [
        [ConnectivityResult.ethernet],
      ]);
    },
  );

  test(
    'an error raised where nothing listens never decides the answer',
    () async {
      final stock = _Unheard(before: true);
      final tolerant = TolerantConnectivity(stock);

      expect(await tolerant.checkConnectivity(), [ConnectivityResult.wifi]);
      final seen = <List<ConnectivityResult>>[];
      final sub = tolerant.onConnectivityChanged.listen(seen.add);
      addTearDown(sub.cancel);
      await _subscribed(stock);
      stock.changes.add(const [ConnectivityResult.mobile]);
      await pumpEventQueue();

      expect(seen, [
        [ConnectivityResult.mobile],
      ]);
      expect(stock.listens, 1);
    },
  );

  test('one raised after the answer is kept from the app too', () async {
    final tolerant = TolerantConnectivity(_Unheard(before: false));

    expect(await tolerant.checkConnectivity(), [ConnectivityResult.wifi]);
    await pumpEventQueue();
  });

  test('a platform that never answers reads as ethernet in time', () async {
    final stock = _Slow();
    final tolerant = TolerantConnectivity(stock, patience: patience);

    expect(await tolerant.checkConnectivity(), [ConnectivityResult.ethernet]);
    expect(await tolerant.onConnectivityChanged.first, [
      ConnectivityResult.ethernet,
    ]);
    expect(stock.listens, 0);
  });

  test('an answer past the patience still brings the changes', () async {
    final stock = _Slow(late: patience * 4);
    final tolerant = TolerantConnectivity(stock, patience: patience);
    final seen = <List<ConnectivityResult>>[];
    final sub = tolerant.onConnectivityChanged.listen(seen.add);
    addTearDown(sub.cancel);

    await Future<void>.delayed(patience * 2);
    expect(seen, [
      [ConnectivityResult.ethernet],
    ]);
    await _subscribed(stock);
    stock.changes.add(const [ConnectivityResult.mobile]);
    await pumpEventQueue();

    expect(seen, [
      [ConnectivityResult.ethernet],
      [ConnectivityResult.mobile],
    ]);
    expect(stock.listens, 1);
  });

  test('a change stream that breaks raises nothing', () async {
    final tolerant = TolerantConnectivity(_BreakingChanges());
    final seen = <List<ConnectivityResult>>[];
    final sub = tolerant.onConnectivityChanged.listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();

    expect(seen, [
      [ConnectivityResult.wifi],
    ]);
  });

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
    await _subscribed(stock);

    stock.changes.add(const [ConnectivityResult.mobile]);
    await pumpEventQueue();

    expect(seen, [
      [ConnectivityResult.mobile],
    ]);
    expect(stock.listens, 1);
  });
}
