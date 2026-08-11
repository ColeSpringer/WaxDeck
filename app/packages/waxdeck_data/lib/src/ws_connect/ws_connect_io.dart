import 'dart:async';
import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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
/// Authorization header.
/// [connectDeadline] is a test hook: the suite proves the half-open case
/// against a socket that accepts and never upgrades, and waiting the real
/// budget out would make that a ten-second test.
Future<WebSocketChannel> connectWebSocket(
  String url, {
  String? authToken,
  Duration connectDeadline = _connectDeadline,
}) async {
  final pending = WebSocket.connect(
    url,
    headers: {if (authToken != null) 'Authorization': 'Bearer $authToken'},
  );
  final socket = await pending.timeout(
    connectDeadline,
    onTimeout: () {
      // The future is abandoned, not cancelled - there is no cancelling
      // it - so the socket it may still produce is closed rather than
      // left open with nobody reading it.
      unawaited(pending.then((late) => late.close()).catchError((_) {}));
      throw TimeoutException('the sync channel did not finish connecting');
    },
  );
  socket.pingInterval = _pingInterval;
  return IOWebSocketChannel(socket);
}
