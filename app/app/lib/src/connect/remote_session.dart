import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import 'connect_bus.dart';
import 'connect_providers.dart';

/// One playback session on another endpoint, as this client controls it.
@immutable
class RemoteSession {
  const RemoteSession({
    required this.session,
    required this.entries,
    this.volumeControl = false,
    this.rateControl = false,
    this.sentVolume,
  });

  final PlaybackSessionInfo session;

  /// The queue as last seen.
  ///
  /// Held apart from [session] because a watch frame omits a queue that
  /// has not changed, which is every frame but the first: reading the
  /// entries off the latest frame would empty the title line at the first
  /// position update.
  final List<PlaybackSessionEntry> entries;

  /// What the endpoint says it can be told, read from the endpoint list
  /// rather than guessed. The server refuses `set-volume` on an endpoint
  /// that reports none, so a slider drawn without this is a control whose
  /// every use is an error toast.
  final bool volumeControl;
  final bool rateControl;

  /// The level this client last sent and has not yet seen come back in a
  /// frame. Without it a released drag snapped to the previous frame's
  /// level for the whole round trip; the controller drops it once its
  /// sends have settled and a fresh frame carries the endpoint's own
  /// answer.
  final double? sentVolume;

  /// The level the surfaces draw: the optimistic beat while a send is
  /// out, the endpoint's own report otherwise.
  double? get volume => sentVolume ?? session.volume;

  String get id => session.id;

  /// What the bar and the screen call the place playback is happening.
  /// The server names an endpoint whenever it knows one; the fallback
  /// says the true thing rather than printing an id at a listener.
  String get endpointName => session.endpointName ?? 'another device';

  PlaybackSessionEntry? get currentEntry =>
      session.index >= 0 && session.index < entries.length
      ? entries[session.index]
      : null;

  Duration get duration =>
      Duration(milliseconds: currentEntry?.durationMs ?? 0);

  RemoteSession copyWith({
    PlaybackSessionInfo? session,
    List<PlaybackSessionEntry>? entries,
    bool? volumeControl,
    bool? rateControl,
    double? sentVolume,
  }) => RemoteSession(
    session: session ?? this.session,
    entries: entries ?? this.entries,
    volumeControl: volumeControl ?? this.volumeControl,
    rateControl: rateControl ?? this.rateControl,
    sentVolume: sentVolume ?? this.sentVolume,
  );
}

/// Which session on another endpoint this client is driving, for
/// everything that has to know: the deck bar's remote face, the remote
/// screen, and the picker deciding what selecting "This device" means.
///
/// It exists because the alternative was a screen holding it. P7 shipped
/// the deck bar reading local playback alone, and the remote control was
/// a pushed screen with its own watch subscription, so handing a session
/// to another endpoint emptied the bar rather than saying where playback
/// had gone - and walking away from the screen stopped watching the
/// session the bar would have needed. This is the same move P4 made for
/// local playback: the controller owns the session and the screen is a
/// viewer of it.
///
/// Null means this client is driving nothing elsewhere, which is the
/// ordinary state.
class RemoteSessionController extends Notifier<RemoteSession?> {
  StreamSubscription<PlaybackSessionInfo>? _frames;
  Timer? _ticker;

  /// The pacing for routed volume. The slider reports a value per step
  /// crossed, and each one here is a round trip another device has to
  /// apply, so sends are throttled leading-plus-trailing: the first
  /// change goes now - that first response is the moment the user judges
  /// whether the control works - then at most one per gap, always ending
  /// on the final value.
  static const Duration _volumeGapLength = Duration(milliseconds: 150);
  Timer? _volumeGap;
  double? _volumeTrailing;

  /// Whether a set-volume is still waiting on its ack. The trailing send
  /// waits on this as well as the gap: the gap bounds the rate, and the
  /// ack bounds the backlog to one command in flight, so a link slower
  /// than the gap queues one level instead of stacking un-acked
  /// commands against their ten-second timeouts.
  bool _volumeSending = false;

  /// Which session's pacing the in-flight completions belong to. A
  /// command can outlive the session it was sent for - release, then
  /// adopt, with the old ack still out - and its completion must not
  /// clear the new session's in-flight flag or flush a level meant for
  /// the old device.
  int _volumeEpoch = 0;

  /// Forgets everything the pacing knows. The queued level was a slider
  /// position on the session being left, meaningless to the next one.
  void _resetVolumePacing() {
    _volumeEpoch++;
    _volumeGap?.cancel();
    _volumeGap = null;
    _volumeTrailing = null;
    _volumeSending = false;
  }

  /// The extrapolated position, ticking while the remote plays.
  ///
  /// Its own listenable for the reason local playback's is: the deck bar
  /// is on screen for the whole session, and a position that moved the
  /// bar's own state several times a second would be the most repeated
  /// frame work in the app. The bar and the screen both read this leaf.
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);

  ConnectBus get _bus => ref.read(connectBusProvider);

  /// The endpoint-list subscription, held only while a session is.
  ProviderSubscription<AsyncValue<List<PlayerEndpoint>>>? _endpoints;

  @override
  RemoteSession? build() {
    ref.onDispose(() {
      _frames?.cancel();
      _ticker?.cancel();
      // The epoch bump keeps a still-outstanding ack from flushing a
      // level - or reading state - on a disposed notifier.
      _resetVolumePacing();
      _endpoints?.close();
      position.dispose();
    });
    return null;
  }

  /// Follows the endpoint list while a session is in hand.
  ///
  /// Not from [build]: the deck bar watches this provider so it is never
  /// disposed, and `playerEndpointsProvider` is auto-dispose. A listen held
  /// for the life of the app pins it, so every idle client fetches and
  /// refetches a list only a driven session reads.
  void _followEndpoints() {
    _endpoints ??= ref.listen(playerEndpointsProvider, (_, next) {
      final endpoints = next.value;
      if (endpoints == null) return;
      _adoptCapabilities(endpoints);
    });
  }

  /// Starts controlling [session]: the bar takes its remote face, the
  /// screen has something to render, and the bus follows the session's
  /// live state.
  void adopt(PlaybackSessionInfo session) {
    if (session.ended) return;
    _frames?.cancel();
    _frames = _bus.watchFrames.listen(_onFrame);
    _followEndpoints();
    _resetVolumePacing();
    _bus.watch(session.id);
    final endpoints =
        ref.read(playerEndpointsProvider).value ?? const <PlayerEndpoint>[];
    final endpoint = endpoints
        .where((e) => e.id == session.endpointId)
        .firstOrNull;
    state = RemoteSession(
      session: session,
      entries: session.entries,
      volumeControl: endpoint?.volumeControl ?? false,
      rateControl: endpoint?.rateControl ?? false,
    );
    position.value = _extrapolate();
    _tick();
  }

  /// Stops controlling, leaving playback where it is.
  ///
  /// "Leave it playing" from the disconnect triad, and what a session
  /// ending on its own comes to. Deliberately not a stop: stepping away
  /// from a cast must not silence the room.
  void release() {
    if (state == null) return;
    _frames?.cancel();
    _frames = null;
    _ticker?.cancel();
    _ticker = null;
    // A level still queued for a session no longer driven is a command
    // to a device this client has let go of.
    _resetVolumePacing();
    // Let the endpoint list go with the session; see _followEndpoints.
    _endpoints?.close();
    _endpoints = null;
    // Harmless when the socket has already dropped, and necessary when it
    // has not: the server keeps sending frames for a watched session.
    _bus.watch(null);
    position.value = Duration.zero;
    state = null;
  }

  /// Ends the session on the other endpoint and stops controlling it.
  /// Errors propagate so the caller can say why nothing happened.
  Future<void> stopThere() async {
    final current = state;
    if (current == null) return;
    await ref.read(repositoryProvider).deletePlaybackSession(current.id);
    release();
  }

  /// Pulls the session onto this device, keeping its queue and position.
  ///
  /// The transfer answers with the session bound to this endpoint, and
  /// the load it routes here is what starts local playback; this only has
  /// to stop treating the session as somewhere else. Throws when this
  /// client has no endpoint id yet, because a transfer needs a target.
  Future<void> transferHere() async {
    final current = state;
    if (current == null) return;
    final own = ref.read(connectControllerProvider).endpointId.value;
    if (own == null) {
      // A diagnostic, not copy: the surface renders this through
      // `explainError`, which answers on the code.
      throw const WaxDeckApiException(
        code: 'local-unregistered',
        message: 'this device is not registered as a player yet',
      );
    }
    await ref.read(repositoryProvider).transferPlaybackSession(current.id, own);
    release();
  }

  /// Pauses or resumes the remote.
  Future<void> toggle() =>
      _send(state?.session.playing ?? false ? 'pause' : 'play');

  Future<void> next() => _send('next');

  Future<void> previous() => _send('previous');

  Future<void> seek(Duration position) =>
      _send('seek', positionMs: position.inMilliseconds.clamp(0, 1 << 40));

  /// Sets the endpoint's own output level. Refused server-side on an
  /// endpoint with no volume control, which is why [RemoteSession] carries
  /// the capability and the surfaces draw no slider without it.
  ///
  /// Optimistic and throttled, on the local controller's contract. The
  /// state's [RemoteSession.sentVolume] moves now, so the knob holds the
  /// level through the round trip instead of snapping to the previous
  /// frame; sends go leading-plus-trailing per [_volumeGapLength], with
  /// a call landing inside a gap - or while the previous send is still
  /// un-acked - queued as the trailing level. Failures are not raised:
  /// the slider fires once per step crossed, and a refusing endpoint
  /// would turn a drag into a snackbar per step. Dropping the optimistic
  /// level and letting the next frame carry the endpoint's own answer is
  /// the report.
  Future<void> setVolume(double volume) async {
    final level = volume.clamp(0.0, 1.0);
    final current = state;
    if (current == null) return;
    state = current.copyWith(sentVolume: level);
    if (_volumeGap != null || _volumeSending) {
      _volumeTrailing = level;
      return;
    }
    _volumeGap = Timer(_volumeGapLength, _volumeGapClosed);
    _volumeSending = true;
    final epoch = _volumeEpoch;
    try {
      await _send('set-volume', volume: level);
    } on Object catch (failure) {
      debugPrint('the endpoint would not take the level: $failure');
      _dropSentVolume(epoch);
    } finally {
      if (epoch == _volumeEpoch) {
        _volumeSending = false;
        _flushTrailingVolume();
      }
    }
  }

  void _volumeGapClosed() {
    _volumeGap = null;
    _flushTrailingVolume();
  }

  /// Sends the queued trailing level once both brakes are off: the gap
  /// has closed and the previous command has its answer.
  void _flushTrailingVolume() {
    if (_volumeGap != null || _volumeSending) return;
    final trailing = _volumeTrailing;
    if (trailing == null) return;
    _volumeTrailing = null;
    _volumeGap = Timer(_volumeGapLength, _volumeGapClosed);
    _volumeSending = true;
    final epoch = _volumeEpoch;
    unawaited(
      _send('set-volume', volume: trailing)
          .catchError((Object failure) {
            debugPrint('the endpoint would not take the level: $failure');
            _dropSentVolume(epoch);
          })
          .whenComplete(() {
            if (epoch != _volumeEpoch) return;
            _volumeSending = false;
            _flushTrailingVolume();
          }),
    );
  }

  /// Lets go of the optimistic level after a refused send, so the next
  /// paint reads the endpoint's own report rather than a loudness it
  /// never took.
  void _dropSentVolume(int epoch) {
    if (epoch != _volumeEpoch) return;
    final current = state;
    if (current == null || current.sentVolume == null) return;
    state = RemoteSession(
      session: current.session,
      entries: current.entries,
      volumeControl: current.volumeControl,
      rateControl: current.rateControl,
    );
  }

  Future<void> _send(String verb, {int? positionMs, double? volume}) async {
    final current = state;
    if (current == null) return;
    await _bus.sendCmd(
      current.id,
      verb,
      positionMs: positionMs,
      volume: volume,
    );
  }

  void _onFrame(PlaybackSessionInfo session) {
    final current = state;
    if (current == null || session.id != current.id) return;
    if (session.ended) {
      release();
      return;
    }
    // The optimistic beat ends where truth resumes: while a send is out
    // a frame may still predate it, so the sent level holds; once every
    // send has settled, the frame is the endpoint's own answer and the
    // override is dropped rather than left to shadow somebody else's
    // change forever.
    final settled = !_volumeSending && _volumeTrailing == null;
    state = RemoteSession(
      session: session,
      // A frame carrying no queue is a frame saying the queue did not
      // change, per the mirror contract.
      entries: session.entries.isEmpty ? current.entries : session.entries,
      volumeControl: current.volumeControl,
      rateControl: current.rateControl,
      sentVolume: settled ? null : current.sentVolume,
    );
    position.value = _extrapolate();
    _tick();
  }

  /// Re-reads the capabilities of the endpoint the session is on.
  void _adoptCapabilities(List<PlayerEndpoint> endpoints) {
    final current = state;
    if (current == null) return;
    final endpoint = endpoints
        .where((e) => e.id == current.session.endpointId)
        .firstOrNull;
    final volume = endpoint?.volumeControl ?? false;
    final rate = endpoint?.rateControl ?? false;
    if (volume == current.volumeControl && rate == current.rateControl) return;
    state = current.copyWith(volumeControl: volume, rateControl: rate);
  }

  /// Runs the position feed while the remote plays, and stops it when it
  /// does not: a paused remote's position does not move, and a timer
  /// firing twice a second to write the same value back is a rebuild of
  /// the deck bar's ticking leaf for nothing.
  void _tick() {
    final playing = state?.session.playing ?? false;
    if (!playing) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (state == null) return;
      position.value = _extrapolate();
    });
  }

  /// Where the remote stands right now: its last reported position plus
  /// the wall time since, scaled by its rate, against the clock offset
  /// the bus keeps. Without the offset a phone a few seconds off the
  /// server would draw a playhead that visibly disagrees with the room.
  Duration _extrapolate() {
    final current = state;
    if (current == null) return Duration.zero;
    final session = current.session;
    var ms = session.positionMs;
    if (session.playing) {
      final serverNow = DateTime.now().toUtc().add(_bus.serverClockOffset);
      final elapsed = serverNow.difference(session.positionAt).inMilliseconds;
      if (elapsed > 0) ms += (elapsed * session.rate).round();
    }
    final duration = current.duration.inMilliseconds;
    if (duration > 0 && ms > duration) ms = duration;
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }
}

final remoteSessionProvider =
    NotifierProvider<RemoteSessionController, RemoteSession?>(
      RemoteSessionController.new,
    );

/// Stops controlling another endpoint when the session ends.
///
/// Never throws: a watch left standing is not a reason to leave a dead
/// credential in place, and the socket it was on is going away anyway.
void releaseRemoteOnSignOut(Ref ref) =>
    ref.read(remoteSessionProvider.notifier).release();
