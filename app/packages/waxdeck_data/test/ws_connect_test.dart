import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_data/src/ws_connect/ws_connect.dart';

void main() {
  test('a socket that accepts and never upgrades times out', () async {
    // The half-open case, which is the one a deadline exists for: the TCP
    // connection completes, so nothing fails, and without a budget the
    // future never settles and the reconnect ladder above never learns
    // the channel is down.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final held = <Socket>[];
    server.listen(held.add);
    addTearDown(() {
      for (final s in held) {
        s.destroy();
      }
    });

    await expectLater(
      connectWebSocket(
        'ws://127.0.0.1:${server.port}/api/v1/sync/live',
        connectDeadline: const Duration(milliseconds: 300),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('a refused connection fails rather than hanging', () async {
    // Nothing is listening: the platform refuses immediately, and the
    // deadline is not what reports it.
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();

    await expectLater(
      connectWebSocket(
        'ws://127.0.0.1:$port/api/v1/sync/live',
        connectDeadline: const Duration(seconds: 5),
      ),
      throwsA(isA<Exception>()),
    );
  });
}
