import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

import '../queue/queue_state.dart';
import 'connect_bus.dart';
import 'queue_gateway.dart';

/// This client's half of "every client is a controllable endpoint":
/// registers over the command bus, executes routed commands against
/// the local queue, and mirrors whatever plays locally back to the
/// server as session reports (on state change plus a five second
/// heartbeat while playing).
///
/// It holds no queue of its own. A queue handed here by another device
/// becomes the local queue, so the deck bar, the queue screen, and a
/// head unit are all looking at the same one.
class ConnectEndpointController {
  ConnectEndpointController({
    required this.bus,
    required this.engine,
    required this.queue,
    required this.deviceName,
  });

  final ConnectBus bus;
  final AudioEnginePort engine;

  /// The local queue and the playback following it.
  final QueueGateway queue;

  final String deviceName;

  /// This client's endpoint id once registered; pickers use it to
  /// transfer sessions here and to hide this device from its own list.
  final ValueNotifier<String?> endpointId = ValueNotifier(null);

  /// The server-assigned id of the mirror session this client's local
  /// playback reports under, when one is live. The device picker
  /// transfers this session for a position-keeping handoff.
  String? mirrorSessionId;

  /// The queue as last reported, which is what a change is measured
  /// against: `itemPids` rides only the reports where the queue itself
  /// changed. Null means the next report carries it whatever it says.
  QueueSnapshot? _reported;
  int _queueVersion = 0;
  Timer? _reportTimer;
  Timer? _queueSettle;
  StreamSubscription<bool>? _playingSub;
  bool _lastPlaying = false;
  bool _disposed = false;

  /// How long a queue edit waits before it is reported. A drag emits a
  /// queue per frame and no frame of one is worth a socket write.
  static const Duration _queueSettleDelay = Duration(milliseconds: 400);

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
      _reported = null;
      _report();
    } on Exception {
      // The socket dropped mid-registration; the reconnect hook runs
      // this again.
    }
  }

  /// Playback changed hands: a session took the engine, or the last one
  /// let go of it. Reports follow whatever owns it, so this is where
  /// they start and stop.
  void onPlaybackChanged() {
    if (_disposed) return;
    if (queue.snapshot() == null) {
      _stopReporting(sessionOver: !queue.hasQueue);
      return;
    }
    _watchEngine();
    _report();
  }

  /// The queue moved under playback: a reorder, an add, a removal, a
  /// shuffle. The mirror carries it on the next report, which is
  /// scheduled rather than sent: the edit that matters is where the
  /// gesture leaves the queue, not where each frame of it does.
  void onQueueChanged() {
    if (_disposed) return;
    final snapshot = queue.snapshot();
    if (snapshot == null || _nothingNewToReport(snapshot)) return;
    // Restarted on each edit, not held from the first: a drag that
    // reported on a timer from its first frame would put every
    // intermediate order on the wire and leave the last one to the
    // heartbeat. What the gesture settles on is what the mirror wants.
    _queueSettle?.cancel();
    _queueSettle = Timer(_queueSettleDelay, () {
      _queueSettle = null;
      // Re-read rather than trusted from arming time: a queue edited
      // and put back inside the window has nothing to say.
      final settled = queue.snapshot();
      if (settled == null || _nothingNewToReport(settled)) return;
      _report();
    });
  }

  void _watchEngine() {
    _playingSub ??= engine.playingStream.listen((playing) {
      // The subscription lives for the controller's lifetime, but it
      // only acts while some playback is attached: after a detach the
      // engine may keep flipping (radio, another surface) and neither
      // reports nor the heartbeat should follow it.
      if (queue.snapshot() == null) {
        _stopReporting(sessionOver: !queue.hasQueue);
        return;
      }
      if (playing != _lastPlaying) {
        _lastPlaying = playing;
        _report();
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

  /// Stops the heartbeat.
  ///
  /// [sessionOver] also forgets what was reported, because the next
  /// report then creates a session and the server drops a creating
  /// report that carries no queue: playing the same album twice in a
  /// row must not come back as a queue that looks unchanged. False for
  /// the gap between two items of one queue, where the mirror is the
  /// same session throughout and re-sending its queue would have the
  /// server re-hydrate every entry at every track.
  void _stopReporting({bool sessionOver = true}) {
    _reportTimer?.cancel();
    _reportTimer = null;
    if (sessionOver) _reported = null;
  }

  /// Whether [snapshot] says nothing a report has not already carried,
  /// which is what decides whether one is worth scheduling. Wider than
  /// [_queueChanged] on purpose: the toggles ride every report as
  /// steady fields, while the queue itself rides only the reports where
  /// it changed. The current index is in neither, because what moves it
  /// is playback changing hands, which reports for itself.
  bool _nothingNewToReport(QueueSnapshot snapshot) {
    final reported = _reported;
    return reported != null &&
        reported.repeat == snapshot.repeat &&
        reported.shuffled == snapshot.shuffled &&
        !_queueChanged(snapshot);
  }

  /// Whether the queue itself moved since the last report, which is
  /// what `itemPids` rides.
  bool _queueChanged(QueueSnapshot snapshot) =>
      !listEquals(_reported?.pids, snapshot.pids);

  void _report() {
    if (_disposed) return;
    final snapshot = queue.snapshot();
    if (snapshot == null) return;
    // Everything waiting to settle is in this frame.
    _queueSettle?.cancel();
    _queueSettle = null;
    final withQueue = _queueChanged(snapshot);
    if (withQueue) _queueVersion++;
    _reported = snapshot;
    bus.sessionReport(
      playing: engine.playing,
      positionMs: snapshot.positionMs,
      index: snapshot.index,
      rate: engine.speed,
      volume: engine.volume,
      repeat: snapshot.repeat.wireName,
      shuffle: snapshot.shuffled,
      itemPids: withQueue ? snapshot.pids : null,
      queueVersion: withQueue ? _queueVersion : null,
    );
  }

  void _onSessionAnswer(PlaybackSessionInfo session) {
    // Session frames arrive for anything this connection watches, not
    // only for what it reports under: a controller screen following
    // another device's playback receives that session here too. Taking
    // it would make another endpoint's session this one's, so a later
    // "play on the kitchen speaker" would transfer someone else's
    // playback, and that session ending would stop the reports for
    // playback still running here.
    final own = endpointId.value;
    if (own != null && session.endpointId != own) return;
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
        case 'set-queue':
          await queue.load(
            _pids(frame),
            index: (frame['index'] as num?)?.toInt() ?? 0,
            positionMs: (frame['positionMs'] as num?)?.toInt() ?? 0,
            // A set-queue is the controller replacing what plays here,
            // never a queue parked in silence.
            play: verb == 'set-queue' || (frame['play'] as bool? ?? true),
          );
          // The command names the session this playback now reports
          // under; adopting it here is what makes a later transfer
          // from this device target the right session. Assigned rather
          // than merged: the frame carries one by contract, and a queue
          // loaded without one is not the session the last id named, so
          // holding that id would aim a transfer at playback this
          // client no longer drives. The next report re-establishes it.
          final sessionId = frame['sessionId'] as String?;
          mirrorSessionId = sessionId != null && sessionId.isNotEmpty
              ? sessionId
              : null;
        case 'play':
          await engine.play();
        case 'pause':
          await engine.pause();
        case 'stop':
          queue.stop();
          // The engine is silenced here rather than left to the
          // session's teardown, which flushes a checkpoint and a listen
          // report before it gets there: on a slow link that is two
          // round trips of audio after the sender was told it stopped.
          // The queue verb runs first, because the checkpoint it takes
          // reads the engine's position and a stopped engine has none.
          await engine.stop();
        case 'next':
          if (!await queue.next()) throw _nowhereToGo(forward: true);
        case 'previous':
          if (!await queue.previous()) throw _nowhereToGo(forward: false);
        case 'seek':
          final positionMs = (frame['positionMs'] as num?)?.toInt() ?? 0;
          await _activeSeek(Duration(milliseconds: positionMs));
        case 'set-volume':
          await engine.setVolume(
            ((frame['volume'] as num?)?.toDouble() ?? 1).clamp(0.0, 1.0),
          );
        case 'set-rate':
          final rate = (frame['rate'] as num?)?.toDouble() ?? 1;
          final session = queue.session;
          if (session != null) {
            await session.setSpeed(rate, persist: false);
          } else {
            await engine.setSpeed(rate);
          }
        case 'set-repeat':
          queue.setRepeat(
            QueueRepeat.fromWire(frame['repeat'] as String? ?? 'off'),
          );
        case 'set-shuffle':
          queue.setShuffle(frame['shuffle'] as bool? ?? false);
        default:
          bus.sendCommandResult(id, ok: false, message: 'unknown verb $verb');
          return;
      }
      bus.sendCommandResult(id, ok: true);
      _report();
    } on WaxDeckApiException catch (e) {
      // The message is rendered by whoever sent the command, so it
      // travels as itself rather than as a stringified exception.
      bus.sendCommandResult(id, ok: false, code: e.code, message: e.message);
    } on Exception catch (e) {
      bus.sendCommandResult(id, ok: false, message: e.toString());
    }
  }

  /// Why a skip moved nothing, in the sender's words. A refused skip
  /// has two quite different causes and the message is rendered
  /// verbatim on whoever asked: an end of the queue is one thing, and
  /// no local playback at all (an empty queue, or live radio holding
  /// the engine) is another.
  WaxDeckApiException _nowhereToGo({required bool forward}) {
    if (queue.snapshot() == null) {
      // These go out over the socket to whoever sent the command, so
      // the message is the wire's own and the receiving client is what
      // translates it - by code, the way every other refusal is read.
      return const WaxDeckApiException(
        code: 'invalid-request',
        message: 'nothing is playing on this device',
      );
    }
    return WaxDeckApiException(
      code: 'invalid-request',
      message: forward
          ? 'already at the end of the queue'
          : 'already at the start of the queue',
    );
  }

  List<String> _pids(Map<String, Object?> frame) =>
      (frame['itemPids'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false);

  Future<void> _activeSeek(Duration position) async {
    final session = queue.session;
    if (session == null) {
      await engine.seek(position);
      return;
    }
    if (!await session.seek(position)) {
      // The session announced the failure and is being let go; an ok
      // here would tell the remote its seek worked while this device
      // stands an error pane where the transport was.
      throw const WaxDeckApiException(
        code: 'internal',
        message: 'the seek could not load that part of the item',
      );
    }
  }

  void dispose() {
    _disposed = true;
    _stopReporting();
    _queueSettle?.cancel();
    _playingSub?.cancel();
    endpointId.dispose();
  }
}
