import 'dart:async';

import 'package:waxdeck_api/waxdeck_api.dart';

/// Sends one control frame on the live event socket; false when the
/// socket is down (the caller retries after the next reconnect).
typedef ControlSender = bool Function(Map<String, Object?> frame);

/// The client half of the player command bus (api/events.md): commands
/// with correlation ids resolved by ack or error frames, endpoint
/// registration, session watching, state reports, and the NTP style
/// clock probe that makes remote position extrapolation skew immune.
class ConnectBus {
  ConnectBus({required this.send, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final ControlSender send;
  final DateTime Function() _now;

  /// Routed endpoint commands (load, play, seek and so on) hand off
  /// to the endpoint controller; the handler must answer each exactly
  /// once through [sendCommandResult].
  void Function(Map<String, Object?> frame)? onEndpointCommand;

  /// Session frames answering reports (assigned ids, ended markers).
  void Function(PlaybackSessionInfo session)? onSessionAnswer;

  final _watchFrames = StreamController<PlaybackSessionInfo>.broadcast();
  final _pending = <String, Completer<Map<String, Object?>>>{};
  String? _watched;
  int _seq = 0;
  DateTime? _pingSent;

  /// Server clock minus local clock, from the last ping round trip.
  Duration serverClockOffset = Duration.zero;

  /// Live state frames for the currently watched session.
  Stream<PlaybackSessionInfo> get watchFrames => _watchFrames.stream;

  String _nextId() => 'c${++_seq}';

  /// Routes one inbound control frame. Unknown types are ignored by
  /// contract.
  void handleFrame(Map<String, Object?> frame) {
    switch (frame['type']) {
      case 'ack':
        _pending.remove(frame['id'])?.complete(frame);
      case 'error':
        final id = frame['id'];
        final completer = id is String ? _pending.remove(id) : null;
        completer?.completeError(
          WaxDeckApiException(
            code: frame['code'] as String? ?? 'internal',
            message: frame['message'] as String? ?? 'command failed',
          ),
        );
      case 'endpoint-cmd':
        onEndpointCommand?.call(frame);
      case 'session':
        final payload = frame['session'];
        if (payload is Map<String, Object?>) {
          final session = PlaybackSessionInfo.fromWire(payload);
          if (session.id == _watched) _watchFrames.add(session);
          onSessionAnswer?.call(session);
        }
      case 'pong':
        final sent = _pingSent;
        if (sent != null) {
          final at = (frame['at'] as num?)?.toInt();
          if (at != null) {
            final received = _now();
            final midpoint = sent.add(received.difference(sent) ~/ 2);
            serverClockOffset = DateTime.fromMillisecondsSinceEpoch(
              at,
              isUtc: true,
            ).difference(midpoint.toUtc());
          }
          _pingSent = null;
        }
    }
  }

  Future<Map<String, Object?>> _request(Map<String, Object?> frame) {
    final id = _nextId();
    frame['id'] = id;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    if (!send(frame)) {
      _pending.remove(id);
      completer.completeError(
        const WaxDeckApiException(
          code: 'local-channel-offline',
          message: 'the event channel is offline',
        ),
      );
      return completer.future;
    }
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _pending.remove(id);
        throw const WaxDeckApiException(
          code: 'local-command-timeout',
          message: 'the server did not answer the command',
        );
      },
    );
  }

  /// Declares this connection a controllable endpoint; resolves to
  /// the endpoint id.
  Future<String> registerEndpoint({
    required String name,
    bool volumeControl = true,
    bool rateControl = true,
  }) async {
    final ack = await _request({
      'type': 'register-endpoint',
      'name': name,
      'volumeControl': volumeControl,
      'rateControl': rateControl,
    });
    final id = ack['endpointId'];
    if (id is! String || id.isEmpty) {
      throw const WaxDeckApiException(
        code: 'local-protocol',
        message: 'registration ack carried no endpoint id',
      );
    }
    return id;
  }

  /// Sends one session command and resolves on its ack.
  Future<void> sendCmd(
    String sessionId,
    String verb, {
    int? positionMs,
    double? volume,
    double? rate,
    List<String>? itemPids,
    int? index,
    String? repeat,
    bool? shuffle,
  }) async {
    await _request({
      'type': 'cmd',
      'sessionId': sessionId,
      'verb': verb,
      'positionMs': ?positionMs,
      'volume': ?volume,
      'rate': ?rate,
      'itemPids': ?itemPids,
      'index': ?index,
      'repeat': ?repeat,
      'shuffle': ?shuffle,
    });
  }

  /// Answers one routed endpoint command. A refusal carries its own
  /// code and message: the server hands both back to whoever sent the
  /// command, and that is what they read.
  void sendCommandResult(
    String id, {
    required bool ok,
    String? code,
    String? message,
  }) {
    send({
      'type': 'cmd-result',
      'id': id,
      'ok': ok,
      if (!ok) 'code': code ?? 'invalid-request',
      if (!ok && message != null) 'message': message,
    });
  }

  /// Follows one session's live state; a new watch replaces the old.
  void watch(String? sessionId) {
    _watched = sessionId;
    send({'type': 'watch', 'sessionId': ?sessionId});
  }

  /// The session this connection is watching, for re-watch after a
  /// reconnect.
  String? get watched => _watched;

  /// Reports local playback state (the mirror contract: steady fields
  /// every report, the queue only when it changed).
  void sessionReport({
    required bool playing,
    required int positionMs,
    required int index,
    double? rate,
    double? volume,
    String? repeat,
    bool? shuffle,
    List<String>? itemPids,
    int? queueVersion,
  }) {
    send({
      'type': 'session-report',
      'playing': playing,
      'positionMs': positionMs,
      'index': index,
      'rate': ?rate,
      'volume': ?volume,
      'repeat': ?repeat,
      'shuffle': ?shuffle,
      'itemPids': ?itemPids,
      'queueVersion': ?queueVersion,
    });
  }

  /// Sends one clock probe; the pong updates [serverClockOffset].
  void ping() {
    final sent = _now();
    _pingSent = sent;
    send({'type': 'ping', 't': sent.millisecondsSinceEpoch});
  }

  void dispose() {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const WaxDeckApiException(
            code: 'local-channel-offline',
            message: 'the event channel closed',
          ),
        );
      }
    }
    _pending.clear();
    _watchFrames.close();
  }
}
