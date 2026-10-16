import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

/// A just_audio platform the test drives: loads answer or refuse, and the
/// test emits the playback events a real backend would. No audio device
/// is ever opened.
class ScriptedPlatform extends JustAudioPlatform {
  ScriptedPlatform({this.refuseLoads = false});

  /// Every load fails the way the web's does on a file the browser cannot
  /// decode: the element's error event first, then the thrown failure.
  bool refuseLoads;

  /// Holds the next player's start until the test completes it, as a slow
  /// native start does. One-shot.
  Completer<void>? initGate;

  /// Fails the next player's start outright. One-shot.
  bool refuseNextInit = false;

  /// Holds the next load open until the test completes it, whichever
  /// player makes it (a replacing load starts on a fresh one). One-shot.
  Completer<void>? loadGate;

  /// Holds every player release open until the test completes it, as
  /// just_audio_web's is behind an `<audio>` play still waiting for data.
  Completer<void>? releaseGate;

  final List<ScriptedPlayer> players = <ScriptedPlayer>[];

  /// The player the engine is talking to now.
  ScriptedPlayer get player => players.last;

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final gate = initGate;
    initGate = null;
    await gate?.future;
    if (refuseNextInit) {
      refuseNextInit = false;
      throw PlatformException(code: 'init');
    }
    final player = ScriptedPlayer(request.id, this);
    players.add(player);
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async {
    await releaseGate?.future;
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async => DisposeAllPlayersResponse();
}

class ScriptedPlayer extends AudioPlayerPlatform {
  ScriptedPlayer(super.id, this._platform);

  final ScriptedPlatform _platform;
  final _events = StreamController<PlaybackEventMessage>.broadcast();
  final _data = StreamController<PlayerDataMessage>.broadcast();

  /// The source each load asked this player for, in order, which says how
  /// the backend was asked to read it (progressive or HLS).
  final List<UriAudioSourceMessage> loadedSources = <UriAudioSourceMessage>[];

  /// Where each load asked to start, and where each seek asked to go.
  final List<Duration?> loadStarts = <Duration?>[];
  final List<Duration?> seeks = <Duration?>[];

  int get loads => loadStarts.length;

  /// Every URL a load asked this player for, in order.
  Iterable<String> get loadedUris => loadedSources.map((source) => source.uri);

  /// Where the last event put playback, which a failure reports again:
  /// a backend's error event carries the position it failed at.
  Duration _position = Duration.zero;
  Duration _buffered = Duration.zero;

  /// Publishes a playback event, as the backend reporting its state.
  /// An [errorCode] is how a backend reports media failing: just_audio
  /// turns it into its `errorStream`.
  void emit({
    ProcessingStateMessage state = ProcessingStateMessage.ready,
    Duration position = Duration.zero,
    Duration buffered = Duration.zero,
    int? errorCode,
    String? errorMessage,
  }) {
    if (_events.isClosed) return;
    _position = position;
    _buffered = buffered;
    _events.add(
      PlaybackEventMessage(
        processingState: state,
        updateTime: DateTime.now(),
        updatePosition: position,
        bufferedPosition: buffered,
        duration: const Duration(minutes: 3),
        icyMetadata: null,
        currentIndex: 0,
        androidAudioSessionId: null,
        errorCode: errorCode,
        errorMessage: errorMessage,
      ),
    );
  }

  /// The media failing after it loaded: the element's error, which leaves
  /// the backend idle where it stood.
  void fail(int code, [String message = 'media error']) => emit(
    state: ProcessingStateMessage.idle,
    position: _position,
    buffered: _buffered,
    errorCode: code,
    errorMessage: message,
  );

  static Iterable<UriAudioSourceMessage> _leaves(AudioSourceMessage message) =>
      switch (message) {
        UriAudioSourceMessage() => [message],
        ClippingAudioSourceMessage(:final child) => [child],
        ConcatenatingAudioSourceMessage(:final children) => children.expand(
          _leaves,
        ),
        _ => const <UriAudioSourceMessage>[],
      };

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => _data.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    loadedSources.addAll(_leaves(request.audioSourceMessage));
    loadStarts.add(request.initialPosition);
    final gate = _platform.loadGate;
    _platform.loadGate = null;
    if (gate != null) await gate.future;
    if (_platform.refuseLoads) {
      fail(4, 'Failed to load URL');
      throw PlatformException(code: '4', message: 'Failed to load URL');
    }
    emit();
    return LoadResponse(duration: const Duration(minutes: 3));
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async => PlayResponse();

  @override
  Future<PauseResponse> pause(PauseRequest request) async => PauseResponse();

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    seeks.add(request.position);
    return SeekResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async => SetShuffleModeResponse();

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    await _events.close();
    await _data.close();
    return DisposeResponse();
  }
}

/// Long enough for what a test just caused to reach every listener.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

/// A probe that answers [answer] whatever it is asked.
StreamAsk answering(ProbeAnswer answer) =>
    (_, {segmentAt}) async => answer;

/// An engine over a real [AudioPlayer] on whatever platform the test put
/// in place, let go when the test ends. Its probe reaches nothing unless
/// [ask] says otherwise.
JustAudioEngine scriptedEngine({StreamAsk? ask, bool isWeb = false}) {
  final engine = JustAudioEngine.withPlayer(
    AudioPlayer(handleAudioSessionActivation: false),
    ask: ask ?? answering(ProbeAnswer.unreachable),
    isWeb: isWeb,
  );
  addTearDown(engine.dispose);
  return engine;
}
