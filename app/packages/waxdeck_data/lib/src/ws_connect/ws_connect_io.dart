import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Native connector: the bearer token authenticates the upgrade via the
/// Authorization header.
Future<WebSocketChannel> connectWebSocket(
  String url, {
  String? authToken,
}) async {
  final socket = await WebSocket.connect(
    url,
    headers: {if (authToken != null) 'Authorization': 'Bearer $authToken'},
  );
  return IOWebSocketChannel(socket);
}
