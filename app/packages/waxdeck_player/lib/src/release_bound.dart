import 'dart:async';

import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

/// just_audio's platform with a bound on letting a player go.
///
/// just_audio releases its platform player on any move into idle, an
/// error's included, under a lock every later load waits on.
/// just_audio_web runs that release behind the `<audio>` element's own
/// queue, which a play still waiting for data holds, and a network error
/// never settles that play: the release, and every load after it, waited
/// forever. Past [bound] the player is abandoned instead, and the next
/// load gets a fresh element of its own.
class ReleaseBoundedPlatform extends JustAudioPlatform {
  ReleaseBoundedPlatform(
    this._inner, {
    this.bound = const Duration(seconds: 1),
  });

  final JustAudioPlatform _inner;

  /// How long a release gets. A healthy one on the web is a few element
  /// calls, so this is only ever reached by one that is stuck.
  final Duration bound;

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) => _inner.init(request);

  @override
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) =>
      _inner
          .disposePlayer(request)
          .timeout(bound, onTimeout: DisposePlayerResponse.new);

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) => _inner
      .disposeAllPlayers(request)
      .timeout(bound, onTimeout: DisposeAllPlayersResponse.new);
}
