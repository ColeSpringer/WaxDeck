import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/connectivity/connectivity_linux.dart';
import 'package:waxdeck/src/connectivity/connectivity_port.dart';

/// The platform's transports: [now] when asked, and each change as the
/// plugin's broadcast stream says it, which a late listener does not
/// hear the first answer of.
class _Transports extends ConnectivityPlatform {
  _Transports(this.now);

  List<ConnectivityResult> now;
  final _changes = StreamController<List<ConnectivityResult>>.broadcast();

  void change(List<ConnectivityResult> to) {
    now = to;
    _changes.add(to);
  }

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => now;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _changes.stream;
}

const _none = [ConnectivityResult.none];
const _wifi = [ConnectivityResult.wifi];
const _mobile = [ConnectivityResult.mobile];

/// The port's returns over [platform], counted.
Future<List<void>> _returns(ConnectivityPlatform platform) async {
  final previous = ConnectivityPlatform.instance;
  ConnectivityPlatform.instance = platform;
  addTearDown(() => ConnectivityPlatform.instance = previous);
  final heard = <void>[];
  final sub = PluginConnectivity().returns.listen(heard.add);
  addTearDown(sub.cancel);
  await pumpEventQueue();
  return heard;
}

void main() {
  test('a transport after none is a return', () async {
    final transports = _Transports(_wifi);
    final heard = await _returns(transports);
    transports.change(_none);
    await pumpEventQueue();
    expect(heard, isEmpty);

    transports.change(_wifi);
    await pumpEventQueue();
    expect(heard, hasLength(1));
  });

  test('wifi giving way to cellular is no return', () async {
    final transports = _Transports(_wifi);
    final heard = await _returns(transports);
    transports.change(_mobile);
    await pumpEventQueue();
    transports.change(_wifi);
    await pumpEventQueue();

    expect(heard, isEmpty);
  });

  test('a transport after none, joined while offline, is a return', () async {
    final transports = _Transports(_none);
    final heard = await _returns(transports);
    transports.change(_mobile);
    await pumpEventQueue();

    expect(heard, hasLength(1));
  });

  test('a return reaches the port through the tolerant wrapper', () async {
    final transports = _Transports(_wifi);
    final heard = await _returns(TolerantConnectivity(transports));
    transports.change(_none);
    await pumpEventQueue();
    transports.change(_wifi);
    await pumpEventQueue();

    expect(heard, hasLength(1));
  });
}
