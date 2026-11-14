import 'dart:async';
import 'dart:convert';

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
    this.onUserCatchUp,
  });

  /// The most frames a socket that came back holds while its session is
  /// read. Past it they all go, and the catch-up reads every topic again
  /// instead: an invalidation or a resync names a topic and carries no
  /// more, and [onConnected] is where the Connect layer registers, watches
  /// and tunes again, which the server answers with the state as it is.
  /// Only a reply to a command sent meanwhile is lost, and it times out as
  /// one sent on a socket that dropped does.
  static const mostHeld = 64;

  final EventsChannelFactory channelFactory;
  final void Function() onCatalog;
  final void Function() onUser;

  /// The user topic after continuity may have been lost (a connect, a
  /// resync), when nothing can say which surfaces moved. Null is
  /// [onUser].
  final void Function()? onUserCatchUp;

  void _userCatchUp() => (onUserCatchUp ?? onUser)();

  /// Player-topic invalidations: endpoint and session lists changed.
  void Function()? onPlayer;

  /// Radio-topic invalidations: artwork for an announced title landed.
  void Function()? onRadio;

  /// Control-plane frames (the player command bus) hand off here.
  void Function(Map<String, Object?> frame)? onControlFrame;

  /// Fires after each successful (re)connect.
  void Function()? onConnected;

  /// Fires whenever the socket comes up or goes down, so the shell can
  /// say it is reconnecting rather than leaving a client that answers
  /// nothing looking healthy. [onConnected] is the "and catch up" hook
  /// and fires only on the way up; this one reports both directions.
  void Function(bool connected)? onConnectionChanged;

  /// Fires when the session this socket rides may no longer be the one
  /// the client holds: the server closed it as ended, an attempt to
  /// reconnect failed (a browser reports an upgrade refused for want of a
  /// session like a dead network), or it came back from a drop, across
  /// which the cookie may have changed hands. A drop alone does not fire
  /// it: a dead link says nothing about the session.
  ///
  /// On a return nothing is caught up until it answers, and what the
  /// socket says meanwhile is held, in order, and heard after the
  /// catch-up. False is an account that left, whose screens go without
  /// being read again for the next one: what was held goes unheard.
  Future<bool> Function()? onSessionInDoubt;

  /// Sends one control frame on the live socket. False when offline.
  bool sendControl(Map<String, Object?> frame) {
    final channel = _channel;
    if (channel == null) return false;
    return channel.send(jsonEncode(frame));
  }

  EventsChannel? _channel;
  Timer? _reconnect;
  bool _running = false;
  final _backoff = Backoff();

  /// Whether the socket has been down since it last came up.
  bool _wasDown = false;

  /// Whether the socket came back and the session has not said it is
  /// still this client's.
  bool _unvouched = false;

  /// What a socket that came back said while its session was read, in
  /// order; null once let go (the account left, or past [mostHeld]).
  List<String>? _held;

  /// Whether more than [mostHeld] frames came while the session was read.
  bool _spilled = false;

  void start() {
    if (_running) return;
    _running = true;
    _connect();
  }

  /// The network came back: a socket waiting out its backoff tries now,
  /// and from the first step again. One up, or on its way, is left be.
  void networkBack() {
    if (!_running || _channel != null) return;
    _reconnect?.cancel();
    _backoff.reset();
    _connect();
  }

  void stop() {
    _running = false;
    _reconnect?.cancel();
    _channel?.close();
    _channel = null;
    _held = null;
    // A start after this is a first connect: nothing held back, and the
    // backoff from the first step.
    _unvouched = false;
    _wasDown = false;
    _backoff.reset();
  }

  void _connect() {
    if (!_running) return;
    final channel = _channel = channelFactory(
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
    channel.connect().then(
      (_) {
        // A connect can resolve after stop(): the listener was told to
        // stand down mid-handshake, and a dead session must not hear
        // "connected" or refresh providers that are being torn down. The
        // socket that came up for nobody goes.
        if (!_running || !identical(_channel, channel)) {
          unawaited(channel.close());
          return;
        }
        _backoff.reset();
        onConnectionChanged?.call(true);
        final asking = onSessionInDoubt;
        if (!_wasDown || asking == null) {
          _wasDown = false;
          _catchUp();
          return;
        }
        _wasDown = false;
        _unvouched = true;
        _held = [];
        _spilled = false;
        asking().then(
          (ours) => _answered(channel, ours: ours),
          onError: (Object _) => _answered(channel, ours: true),
        );
      },
      onError: (Object error) {
        if (identical(_channel, channel)) _onDown(failed: error);
      },
    );
  }

  /// A return's session read answered. Ours, it catches up and hears what
  /// the socket said meanwhile; not this client's, that goes unheard and
  /// so does the socket, until the session that started it stops it.
  void _answered(EventsChannel channel, {required bool ours}) {
    if (!_running || !identical(_channel, channel)) return;
    final held = _held;
    _held = null;
    if (!ours) return;
    _unvouched = false;
    _catchUp(everyTopic: _spilled);
    for (final frame in held ?? const <String>[]) {
      if (!_running || !identical(_channel, channel)) return;
      _hear(frame);
    }
  }

  void _catchUp({bool everyTopic = false}) {
    onConnected?.call();
    // The socket may have been down across changes; refresh once.
    onCatalog();
    _userCatchUp();
    if (everyTopic) {
      onPlayer?.call();
      onRadio?.call();
    }
  }

  void _onDown({Object? failed}) {
    if (!_running) return;
    // A browser reports an upgrade refused for want of a session like a
    // dead network, so every failed attempt is in doubt.
    final inDoubt =
        failed != null || _channel?.closeCode == sessionEndedCloseCode;
    _channel = null;
    _wasDown = true;
    _unvouched = false;
    _held = null;
    onConnectionChanged?.call(false);
    _reconnect?.cancel();
    _reconnect = Timer(_backoff.take(), _connect);
    if (inDoubt) onSessionInDoubt?.call().ignore();
  }

  void _onFrame(String data) {
    // What a socket that came back says waits on its session's answer.
    if (_unvouched) {
      final held = _held;
      if (held == null) return;
      if (held.length < mostHeld) {
        held.add(data);
      } else {
        _held = null;
        _spilled = true;
      }
      return;
    }
    _hear(data);
  }

  void _hear(String data) {
    Map<String, Object?> frame;
    try {
      frame = jsonDecode(data) as Map<String, Object?>;
    } on FormatException {
      return;
    }
    switch (frame['type']) {
      case 'invalidate':
        switch (frame['topic']) {
          case 'catalog':
            onCatalog();
          case 'user':
            onUser();
          case 'player':
            onPlayer?.call();
          case 'radio':
            onRadio?.call();
        }
      case 'resync':
        // Continuity was lost, and refetching is the only catch-up there
        // is here. A topic this build does not know refreshes everything
        // rather than nothing: recovery must not narrow as topics grow.
        switch (frame['topic']) {
          case 'catalog':
            onCatalog();
          case 'user':
            _userCatchUp();
          default:
            onCatalog();
            _userCatchUp();
        }
      default:
        // Command-bus frames route to the Connect layer; anything it
        // does not recognize either is ignored by contract.
        onControlFrame?.call(frame);
    }
  }
}
