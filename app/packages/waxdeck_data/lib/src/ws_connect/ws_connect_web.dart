import 'dart:async';

import 'package:web/web.dart' as web;
import 'package:web_socket_channel/web_socket_channel.dart';

/// How long an upgrade may take before it is called a failure.
const _connectDeadline = Duration(seconds: 10);

/// Web connector: the browser attaches the session cookie to the
/// same-origin upgrade; there is no header to send. A relative URL
/// resolves against the page origin.
Future<WebSocketChannel> connectWebSocket(
  String url, {
  String? authToken,
  Duration connectDeadline = _connectDeadline,
}) async {
  var resolved = url;
  if (url.startsWith('/')) {
    final loc = web.window.location;
    final scheme = loc.protocol == 'https:' ? 'wss' : 'ws';
    resolved = '$scheme://${loc.host}$url';
  }
  final channel = WebSocketChannel.connect(Uri.parse(resolved));
  // The same half-open guard the native connector has. There is no ping
  // to pair with it: a browser socket's keepalive is the browser's, not
  // this app's, so a peer that vanishes silently is found when the next
  // send fails rather than on a missed pong.
  try {
    await channel.ready.timeout(connectDeadline);
  } on TimeoutException {
    // Abandoned, not awaited: on a handshake that never finished, the
    // close future settles with the connection's own failure, and that
    // error must not replace the timeout the caller is owed.
    unawaited(channel.sink.close().catchError((_) {}));
    rethrow;
  }
  return channel;
}
