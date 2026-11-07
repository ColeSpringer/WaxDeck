import '../models.dart';

/// Similar tracks, instant mixes and sonic paths.
abstract interface class DiscoveryApi {
  /// `GET /items/{pid}/similar`: tracks similar to a seed track, most
  /// similar first. The result names which engine answered (`sonic`
  /// embeddings or the `metadata` fallback).
  Future<SimilarTracks> getSimilarTracks(String pid, {int? limit});

  /// `POST /mixes/instant`: computes an instant mix from a seed track
  /// or artist ([seedPid]) or a [genre]; exactly one must be set.
  /// [adventurousness] (0 to 1) sets how far the mix wanders from the
  /// seed; [excludePids] leaves out already-played tracks.
  Future<InstantMix> createInstantMix({
    String? seedPid,
    String? genre,
    double? adventurousness,
    int? size,
    List<String> excludePids,
  });

  /// `GET /mixes/path`: a sonic path [from] one track [to] another,
  /// starting track first. An incomplete path still drifts toward the
  /// target.
  Future<SonicPath> getSonicPath({
    required String from,
    required String to,
    int? length,
  });
}
