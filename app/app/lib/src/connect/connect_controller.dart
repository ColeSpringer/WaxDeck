import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

import '../player/playback_session.dart';
import '../player/session_registry.dart';
import 'connect_bus.dart';

/// This client's half of "every client is a controllable endpoint":
/// registers over the command bus, executes routed commands against
/// the local player, plays queues handed over by loads and transfers,
/// and mirrors whatever plays locally back to the server as session
/// reports (on state change plus a five second heartbeat while
/// playing).
class ConnectEndpointController {
  ConnectEndpointController({
    required this.bus,
    required this.repository,
    required this.engine,
    required this.registry,
    required this.deviceName,
    required this.clientId,
    this.sync,
    this.downloads,
  });

  final ConnectBus bus;
  final WaxDeckRepository repository;
  final AudioEnginePort engine;
  final CurrentSessionRegistry registry;
  final String deviceName;
  final String clientId;
  final SyncEngine? sync;
  final DownloadManagerPort? downloads;

  /// This client's endpoint id once registered; pickers use it to
  /// transfer sessions here and to hide this device from its own list.
  final ValueNotifier<String?> endpointId = ValueNotifier(null);

  /// The server-assigned id of the mirror session this client's local
  /// playback reports under, when one is live. The device picker
  /// transfers this session for a position-keeping handoff.
  String? mirrorSessionId;

  _ConnectQueue? _queue;
  PlaybackSession? _localSession;
  String? _localPid;
  bool _queueDirty = false;
  int _queueVersion = 0;
  Timer? _reportTimer;
  StreamSubscription<bool>? _playingSub;
  bool _lastPlaying = false;
  bool _disposed = false;

  /// Wires the bus callbacks without registering (frames can arrive
  /// the moment the socket lives, before registration resolves).
  void wire() {
    bus.onEndpointCommand = _onEndpointCommand;
    bus.onSessionAnswer = _onSessionAnswer;
  }

  /// Wires the bus callbacks and registers. Safe to call again after
  /// a reconnect; registration replaces itself server-side.
  Future<void> start() async {
    wire();
    await register();
  }

  /// (Re)registers this connection as a controllable endpoint.
  Future<void> register() async {
    try {
      endpointId.value = await bus.registerEndpoint(name: deviceName);
      // A fresh connection means a fresh mirror session server-side;
      // the next report must carry the queue again.
      _queueDirty = true;
      _report(force: true);
    } on Exception {
      // The socket dropped mid-registration; the reconnect hook runs
      // this again.
    }
  }

  /// PlayerScreen attaches its live session so organic local playback
  /// mirrors to the server and stays remotely controllable.
  void attachLocal(PlaybackSession session, String pid) {
    _queue?.stop();
    _queue = null;
    _localSession = session;
    _localPid = pid;
    _queueDirty = true;
    _queueVersion++;
    _watchEngine();
    _report(force: true);
  }

  /// PlayerScreen detaches on dispose. Reports stop; the server ends
  /// the mirror session when the socket drops or another load lands.
  void detachLocal(PlaybackSession session) {
    if (_localSession == session) {
      _localSession = null;
      _localPid = null;
      _stopReporting();
    }
  }

  void _watchEngine() {
    _playingSub ??= engine.playingStream.listen((playing) {
      // The subscription lives for the controller's lifetime, but it
      // only acts while some playback is attached: after a detach the
      // engine may keep flipping (radio, another surface) and neither
      // reports nor the heartbeat should follow it.
      if (_currentState() == null) {
        _stopReporting();
        return;
      }
      if (playing != _lastPlaying) {
        _lastPlaying = playing;
        _report(force: true);
      }
      _scheduleHeartbeat();
    });
    _scheduleHeartbeat();
  }

  void _scheduleHeartbeat() {
    _reportTimer?.cancel();
    _reportTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (engine.playing) _report();
    });
  }

  void _stopReporting() {
    _reportTimer?.cancel();
    _reportTimer = null;
  }

  ({List<String> pids, int index, int positionMs, bool playing})?
  _currentState() {
    final queue = _queue;
    if (queue != null) {
      return (
        pids: queue.pids,
        index: queue.index,
        positionMs: queue.session?.displayPosition.inMilliseconds ?? 0,
        playing: engine.playing,
      );
    }
    final local = _localSession;
    final pid = _localPid;
    if (local != null && pid != null) {
      return (
        pids: [pid],
        index: 0,
        positionMs: local.displayPosition.inMilliseconds,
        playing: engine.playing,
      );
    }
    return null;
  }

  void _report({bool force = false}) {
    if (_disposed) return;
    final state = _currentState();
    if (state == null) return;
    final withQueue = _queueDirty;
    _queueDirty = false;
    bus.sessionReport(
      playing: state.playing,
      positionMs: state.positionMs,
      index: state.index,
      rate: engine.speed,
      volume: engine.volume,
      itemPids: withQueue ? state.pids : null,
      queueVersion: withQueue ? _queueVersion : null,
    );
  }

  void _onSessionAnswer(PlaybackSessionInfo session) {
    if (session.ended) {
      // The server ended what this client was reporting (a transfer
      // moved it, or a delete): stop treating local playback as that
      // session. An explicit stop command arrives separately when
      // playback itself must halt.
      if (mirrorSessionId == session.id) mirrorSessionId = null;
      _stopReporting();
      return;
    }
    mirrorSessionId = session.id;
  }

  Future<void> _onEndpointCommand(Map<String, Object?> frame) async {
    final id = frame['id'] as String? ?? '';
    final verb = frame['verb'] as String? ?? '';
    try {
      switch (verb) {
        case 'load':
          final pids = (frame['itemPids'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList(growable: false);
          final index = (frame['index'] as num?)?.toInt() ?? 0;
          final positionMs = (frame['positionMs'] as num?)?.toInt() ?? 0;
          final play = frame['play'] as bool? ?? true;
          await _load(pids, index, positionMs, play);
          // The load names the session this playback now reports
          // under; adopting it here is what makes a later transfer
          // from this device target the right session.
          final sessionId = frame['sessionId'] as String?;
          if (sessionId != null && sessionId.isNotEmpty) {
            mirrorSessionId = sessionId;
          }
        case 'play':
          await engine.play();
        case 'pause':
          await engine.pause();
        case 'stop':
          _queue?.stop();
          _queue = null;
          await engine.stop();
          _stopReporting();
        case 'seek':
          final positionMs = (frame['positionMs'] as num?)?.toInt() ?? 0;
          await _activeSeek(Duration(milliseconds: positionMs));
        case 'set-volume':
          await engine.setVolume(
            ((frame['volume'] as num?)?.toDouble() ?? 1).clamp(0.0, 1.0),
          );
        case 'set-rate':
          final rate = (frame['rate'] as num?)?.toDouble() ?? 1;
          final session = _queue?.session ?? _localSession;
          if (session != null) {
            await session.setSpeed(rate, persist: false);
          } else {
            await engine.setSpeed(rate);
          }
        default:
          bus.sendCommandResult(id, ok: false, message: 'unknown verb $verb');
          return;
      }
      bus.sendCommandResult(id, ok: true);
      _report(force: true);
    } on Exception catch (e) {
      bus.sendCommandResult(id, ok: false, message: e.toString());
    }
  }

  Future<void> _activeSeek(Duration position) async {
    final session = _queue?.session ?? _localSession;
    if (session != null) {
      await session.seek(position);
    } else {
      await engine.seek(position);
    }
  }

  Future<void> _load(
    List<String> pids,
    int index,
    int positionMs,
    bool play,
  ) async {
    if (pids.isEmpty) {
      throw const WaxDeckApiException(
        code: 'invalid-request',
        message: 'load carried no items',
      );
    }
    _localSession = null;
    _localPid = null;
    _queue?.stop();
    final queue = _ConnectQueue(
      controller: this,
      pids: pids,
      index: index.clamp(0, pids.length - 1),
    );
    _queue = queue;
    _queueDirty = true;
    _queueVersion++;
    await queue.playCurrent(positionMs: positionMs, play: play);
    _watchEngine();
  }

  /// Called by the queue when a track finishes; advances or ends.
  Future<void> _onQueueTrackDone(_ConnectQueue queue) async {
    if (_queue != queue) return;
    if (queue.index + 1 < queue.pids.length) {
      queue.index++;
      await queue.playCurrent(positionMs: 0, play: true);
      _report(force: true);
    } else {
      _report(force: true);
    }
  }

  /// Steps the active queue forward (a head-unit or notification skip).
  /// False when nothing queued or already at the end.
  Future<bool> nextInQueue() async {
    final queue = _queue;
    if (queue == null || queue.index + 1 >= queue.pids.length) return false;
    queue.index++;
    await queue.playCurrent(positionMs: 0, play: true);
    _report(force: true);
    return true;
  }

  /// Steps the active queue back, or restarts the current entry when
  /// already at the front.
  Future<bool> previousInQueue() async {
    final queue = _queue;
    if (queue == null) return false;
    if (queue.index > 0) queue.index--;
    await queue.playCurrent(positionMs: 0, play: true);
    _report(force: true);
    return true;
  }

  void dispose() {
    _disposed = true;
    _stopReporting();
    _playingSub?.cancel();
    _queue?.stop();
    endpointId.dispose();
  }
}

/// A queue handed to this endpoint by a load: plays entries in order
/// through headless playback sessions (checkpoints, listen accounting,
/// and skip maps all ride along), advancing when the engine completes
/// each item.
class _ConnectQueue {
  _ConnectQueue({
    required this.controller,
    required this.pids,
    required this.index,
  });

  final ConnectEndpointController controller;
  final List<String> pids;
  int index;
  PlaybackSession? session;
  StreamSubscription<void>? _completedSub;
  bool _stopped = false;

  Future<void> playCurrent({
    required int positionMs,
    required bool play,
  }) async {
    await _completedSub?.cancel();
    final old = session;
    session = null;
    if (old != null) await old.dispose();
    if (_stopped) return;

    final detail = await controller.repository.getItem(pids[index]);
    final next = PlaybackSession(
      repository: controller.repository,
      engine: controller.engine,
      item: detail,
      clientId: controller.clientId,
      sync: controller.sync,
      downloads: controller.downloads,
      initialPositionMs: positionMs > 0 ? positionMs : null,
    );
    session = next;
    controller.registry.register(next);
    await next.start();
    if (!play) await controller.engine.pause();
    _completedSub = controller.engine.completed.listen((_) {
      controller._onQueueTrackDone(this);
    });
  }

  void stop() {
    _stopped = true;
    _completedSub?.cancel();
    final s = session;
    session = null;
    if (s != null) {
      controller.registry.unregister(s);
      unawaited(s.dispose());
    }
  }
}
