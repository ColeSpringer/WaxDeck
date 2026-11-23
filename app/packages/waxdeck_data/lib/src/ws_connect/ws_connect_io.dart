import 'dart:async';
import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'upgrade_refused.dart';

/// How long an upgrade may take before it is called a failure, and how
/// often the socket proves the peer is still there afterwards.
///
/// The first is the half-open case: a TCP connection that completes to a
/// proxy which never finishes the upgrade leaves a future that never
/// settles, and the reconnect ladder above never learns it is down. The
/// second is the same failure once connected - a peer that vanishes
/// without a FIN - which only a missed pong surfaces.
const _connectDeadline = Duration(seconds: 10);
const _pingInterval = Duration(seconds: 30);

/// Native connector: the bearer token authenticates the upgrade via the
/// Authorization header. An upgrade the server answers with a status
/// throws [UpgradeRefused] naming it.
/// [connectDeadline] is a test hook: the suite proves the half-open case
/// against a socket that accepts and never upgrades, and waiting the real
/// budget out would make that a ten-second test.
Future<WebSocketChannel> connectWebSocket(
  String url, {
  String? authToken,
  Duration connectDeadline = _connectDeadline,
}) async {
  // A client of its own, so closing it aborts this attempt and nothing
  // else: a connect still pending and an upgrade not yet answered. An
  // upgraded socket is detached from it and outlives it.
  final client = HttpClient();
  final WebSocket socket;
  try {
    final pending = WebSocket.connect(
      url,
      headers: {if (authToken != null) 'Authorization': 'Bearer $authToken'},
      customClient: client,
    );
    socket = await pending.timeout(
      connectDeadline,
      onTimeout: () {
        // Closing the client cannot reach a tunnel still opening through
        // a proxy, nor an upgrade answered and mid-detach at the deadline
        // (the client lets go of it before the socket arrives); whichever
        // lands is closed.
        unawaited(pending.then((late) => late.close()).catchError((_) {}));
        throw TimeoutException('the sync channel did not finish connecting');
      },
    );
  } on WebSocketException catch (e) {
    if (e.httpStatusCode case final status?) throw UpgradeRefused(status);
    rethrow;
  } finally {
    client.close(force: true);
  }
  socket.pingInterval = _pingInterval;
  return IOWebSocketChannel(socket);
}
