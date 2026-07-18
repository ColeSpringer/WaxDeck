import 'package:web/web.dart' as web;
import 'package:web_socket_channel/web_socket_channel.dart';

/// Web connector: the browser attaches the session cookie to the
/// same-origin upgrade; there is no header to send. A relative URL
/// resolves against the page origin.
Future<WebSocketChannel> connectWebSocket(
  String url, {
  String? authToken,
}) async {
  var resolved = url;
  if (url.startsWith('/')) {
    final loc = web.window.location;
    final scheme = loc.protocol == 'https:' ? 'wss' : 'ws';
    resolved = '$scheme://${loc.host}$url';
  }
  final channel = WebSocketChannel.connect(Uri.parse(resolved));
  await channel.ready;
  return channel;
}
