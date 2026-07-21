import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'ws_connect/ws_connect.dart';

/// Builds one connection attempt to the server's event channel. The
/// engine calls it for every (re)connect so each attempt gets a fresh
/// socket and a fresh subscribe frame.
typedef EventsChannelFactory =
    EventsChannel Function({
      required void Function(String frame) onFrame,
      required void Function() onDone,
      required Future<String> Function() subscribe,
    });

/// One WebSocket connection to `GET /api/v1/ws`. Native builds
/// authenticate with the bearer token header; web builds ride the
/// session cookie the browser attaches to same-origin upgrades.
class EventsChannel {
  EventsChannel({
    required this.url,
    required this.authToken,
    required this.onFrame,
    required this.onDone,
    required this.subscribe,
  });

  /// Absolute ws(s) URL of the event channel.
  final String url;
  final String? authToken;
  final void Function(String frame) onFrame;
  final void Function() onDone;
  final Future<String> Function() subscribe;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;

  /// Opens the socket, sends the subscribe frame, and starts relaying
  /// frames. Completes when the connection is established.
  Future<void> connect() async {
    final channel = await connectWebSocket(url, authToken: authToken);
    _channel = channel;
    channel.sink.add(await subscribe());
    _sub = channel.stream.listen(
      (message) {
        if (message is String) onFrame(message);
      },
      onDone: onDone,
      onError: (Object _) => onDone(),
      cancelOnError: true,
    );
  }

  /// Sends one JSON text frame on the live socket. False when no
  /// connection is up (the caller retries after the next connect).
  bool send(String frame) {
    final channel = _channel;
    if (channel == null) return false;
    channel.sink.add(frame);
    return true;
  }

  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
  }
}

/// The default factory over a server base URL and a token supplier
/// (native builds pass the live bearer; web passes null).
EventsChannelFactory eventsChannelFactory({
  required String baseUrl,
  required String? Function() token,
}) {
  final wsBase = _wsBase(baseUrl);
  return ({required onFrame, required onDone, required subscribe}) {
    return EventsChannel(
      url: '$wsBase/api/v1/ws',
      authToken: token(),
      onFrame: onFrame,
      onDone: onDone,
      subscribe: subscribe,
    );
  };
}

String _wsBase(String baseUrl) {
  final trimmed = baseUrl.replaceAll(RegExp(r'/+$'), '');
  if (trimmed.startsWith('https://')) {
    return 'wss://${trimmed.substring(8)}';
  }
  if (trimmed.startsWith('http://')) {
    return 'ws://${trimmed.substring(7)}';
  }
  return trimmed;
}
