import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:waxdeck_data/waxdeck_data.dart';

/// The web build's slice of live sync: follow the event channel and
/// turn invalidation frames into provider refreshes. No mirror, no
/// outbox; the SPA stays server-backed, so "catch up" is simply
/// refetching, and every frame type (invalidate, resync, unknown)
/// reduces to that.
class LiveInvalidations {
  LiveInvalidations({
    required this.channelFactory,
    required this.onCatalog,
    required this.onUser,
  });

  final EventsChannelFactory channelFactory;
  final void Function() onCatalog;
  final void Function() onUser;

  /// Player-topic invalidations: endpoint and session lists changed.
  void Function()? onPlayer;

  /// Control-plane frames (the player command bus) hand off here.
  void Function(Map<String, Object?> frame)? onControlFrame;

  /// Fires after each successful (re)connect.
  void Function()? onConnected;

  /// Fires whenever the socket comes up or goes down, so the shell can
  /// say it is reconnecting rather than leaving a client that answers
  /// nothing looking healthy. [onConnected] is the "and catch up" hook
  /// and fires only on the way up; this one reports both directions.
  void Function(bool connected)? onConnectionChanged;

  /// Sends one control frame on the live socket. False when offline.
  bool sendControl(Map<String, Object?> frame) {
    final channel = _channel;
    if (channel == null) return false;
    return channel.send(jsonEncode(frame));
  }

  EventsChannel? _channel;
  Timer? _reconnect;
  bool _running = false;
  int _backoffSeconds = 1;

  void start() {
    if (_running) return;
    _running = true;
    _connect();
  }

  void stop() {
    _running = false;
    _reconnect?.cancel();
    _channel?.close();
    _channel = null;
  }

  void _connect() {
    if (!_running) return;
    _channel = channelFactory(
      onFrame: _onFrame,
      onDone: _onDown,
      // No mirror means no cursors: subscribe empty and receive live
      // invalidations only.
      subscribe: () async => jsonEncode(const <String, Object?>{}),
    );
    // The error handler rides `then` rather than a chained catchError:
    // chained, it would also catch what the success body throws, and a
    // fan-out bug would then masquerade as a dropped socket - banner
    // flipped, backoff armed, a healthy channel abandoned unclosed.
    // Only the connect itself failing means the link is down; a throw
    // from the body stays an error worth hearing as itself.
    _channel!.connect().then(
      (_) {
        // A connect can resolve after stop(): the listener was told to
        // stand down mid-handshake, and a dead session must not hear
        // "connected" or refresh providers that are being torn down.
        if (!_running) return;
        _backoffSeconds = 1;
        onConnectionChanged?.call(true);
        onConnected?.call();
        // The socket may have been down across changes; refresh once.
        onCatalog();
        onUser();
      },
      onError: (Object _) {
        _onDown();
      },
    );
  }

  void _onDown() {
    if (!_running) return;
    _channel = null;
    onConnectionChanged?.call(false);
    _reconnect?.cancel();
    final delay = Duration(seconds: _backoffSeconds);
    _backoffSeconds = math.min(_backoffSeconds * 2, 60);
    _reconnect = Timer(delay, _connect);
  }

  void _onFrame(String data) {
    Map<String, Object?> frame;
    try {
      frame = jsonDecode(data) as Map<String, Object?>;
    } on FormatException {
      return;
    }
    switch (frame['type']) {
      case 'invalidate' || 'resync':
        switch (frame['topic']) {
          case 'catalog':
            onCatalog();
          case 'user':
            onUser();
          case 'player':
            onPlayer?.call();
          default:
            // A resync with no topic: refresh everything; refetching
            // is the only catch-up there is here.
            onCatalog();
            onUser();
        }
      default:
        // Command-bus frames route to the Connect layer; anything it
        // does not recognize either is ignored by contract.
        onControlFrame?.call(frame);
    }
  }
}
