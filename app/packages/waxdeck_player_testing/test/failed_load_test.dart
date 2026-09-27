import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

// just_audio 0.10.6 raises a failed activation twice: to the call, and
// uncaught from a completer nothing listens to yet, which on web reached the
// page. The engine answers the first and drops the second.

/// A platform whose loads all fail the way the web's does on a file the
/// browser cannot decode.
class _RefusingPlatform extends JustAudioPlatform {
  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async =>
      _RefusingPlayer(request.id);

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async => DisposePlayerResponse();

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async => DisposeAllPlayersResponse();
}

class _RefusingPlayer extends AudioPlayerPlatform {
  _RefusingPlayer(super.id);

  final _events = StreamController<PlaybackEventMessage>.broadcast();
  final _data = StreamController<PlayerDataMessage>.broadcast();

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => _data.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async =>
      throw PlatformException(code: '4', message: 'Failed to load URL');

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
  Future<PauseResponse> pause(PauseRequest request) async => PauseResponse();

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    await _events.close();
    await _data.close();
    return DisposeResponse();
  }
}

/// A player whose activations leave [echo] uncaught, as wasm's microtask
/// order always does; the VM's never shows it with the real player.
class _EchoingPlayer implements AudioPlayer {
  _EchoingPlayer(this.echo);

  /// What the activation leaves uncaught.
  final Object echo;

  final _index = StreamController<int?>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();

  @override
  Stream<int?> get currentIndexStream => _index.stream;

  @override
  Stream<Duration?> get durationStream => _duration.stream;

  @override
  ProcessingState get processingState => ProcessingState.idle;

  @override
  List<IndexedAudioSource> get sequence => const <IndexedAudioSource>[];

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> sources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) {
    Completer<Duration?>().completeError(echo);
    return Future<Duration?>.error(PlayerException(4, 'Failed to load URL', 0));
  }

  @override
  Future<void> seek(Duration? position, {int? index}) {
    Completer<void>().completeError(echo);
    return Future<void>.value();
  }

  @override
  Future<void> dispose() async {
    await _index.close();
    await _duration.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// Runs [action] on an engine over [player] inside a guarded zone,
/// answering what reached the zone uncaught and what the action threw.
Future<({List<Object> uncaught, Object? thrown})> _through(
  AudioPlayer Function() player, [
  Future<void> Function(JustAudioEngine engine)? action,
]) async {
  final uncaught = <Object>[];
  Object? thrown;
  await runZonedGuarded(() async {
    final engine = JustAudioEngine.withPlayer(
      player(),
      probe: (_) async => StreamProbe.answered,
    );
    try {
      await (action ?? (e) => e.load('http://x/queued.ape'))(engine);
    } on Object catch (e) {
      thrown = e;
    }
    // Past the microtasks the activation left behind.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await engine.dispose();
  }, (error, _) => uncaught.add(error));
  return (uncaught: uncaught, thrown: thrown);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => JustAudioPlatform.instance = _RefusingPlatform());

  test('a refused load is reported to its caller and nowhere else', () async {
    final result = await _through(
      () => AudioPlayer(handleAudioSessionActivation: false),
    );
    expect(result.thrown, isA<MediaLoadException>());
    expect(result.uncaught, isEmpty);
  });

  test("the activation's echo of a refused load is dropped", () async {
    final result = await _through(
      () => _EchoingPlayer(PlayerException(4, 'Failed to load URL', 0)),
    );
    expect(result.thrown, isA<MediaLoadException>());
    expect(result.uncaught, isEmpty);
  });

  test('an interrupted activation is dropped the same way', () async {
    final result = await _through(
      () => _EchoingPlayer(PlayerInterruptedException('Loading interrupted')),
    );
    expect(result.thrown, isA<MediaLoadException>());
    expect(result.uncaught, isEmpty);
  });

  test('a seek that restarts the platform leaves no echo either', () async {
    final result = await _through(
      () => _EchoingPlayer(PlayerException(2, 'Network error', 0)),
      (engine) => engine.seek(const Duration(seconds: 30)),
    );
    expect(result.thrown, isNull);
    expect(result.uncaught, isEmpty);
  });

  test('anything else left uncaught still reaches the zone', () async {
    final result = await _through(
      () => _EchoingPlayer(StateError('a defect, not a refusal')),
    );
    expect(result.thrown, isA<MediaLoadException>());
    expect(result.uncaught, <Matcher>[isA<StateError>()]);
  });
}
