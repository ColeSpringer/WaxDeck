import 'dart:async';

import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [DiscoveryApi] for `FakeRepository`.
mixin FakeDiscovery on FakeRepositoryState implements DiscoveryApi {
  /// Thrown by the discovery endpoints (similar tracks, instant mix,
  /// sonic path) when set.
  WaxDeckApiException? discoveryError;

  /// Held open, a similar-tracks read waits on it.
  Completer<void>? similarTracksGate;

  /// Canned results served by the discovery endpoints.
  SimilarTracks similarTracksResult = const SimilarTracks(
    basis: MixBasis.metadata,
  );
  InstantMix instantMixResult = const InstantMix(basis: MixBasis.metadata);

  /// Holds [createInstantMix] open until the test completes it.
  Completer<void>? instantMixGate;
  SonicPath sonicPathResult = const SonicPath(complete: false);

  final List<({String pid, int? limit})> similarTracksCalls = [];
  final List<
    ({
      String? seedPid,
      String? genre,
      double? adventurousness,
      int? size,
      List<String> excludePids,
    })
  >
  instantMixCalls = [];
  final List<({String from, String to, int? length})> sonicPathCalls = [];

  @override
  Future<SimilarTracks> getSimilarTracks(String pid, {int? limit}) async {
    similarTracksCalls.add((pid: pid, limit: limit));
    final gate = similarTracksGate;
    if (gate != null) await gate.future;
    final error = discoveryError;
    if (error != null) throw error;
    return similarTracksResult;
  }

  @override
  Future<InstantMix> createInstantMix({
    String? seedPid,
    String? genre,
    double? adventurousness,
    int? size,
    List<String> excludePids = const [],
  }) async {
    instantMixCalls.add((
      seedPid: seedPid,
      genre: genre,
      adventurousness: adventurousness,
      size: size,
      excludePids: List.of(excludePids),
    ));
    await instantMixGate?.future;
    final error = discoveryError;
    if (error != null) throw error;
    return instantMixResult;
  }

  @override
  Future<SonicPath> getSonicPath({
    required String from,
    required String to,
    int? length,
  }) async {
    sonicPathCalls.add((from: from, to: to, length: length));
    final error = discoveryError;
    if (error != null) throw error;
    return sonicPathResult;
  }
}
