import 'dart:async';

import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [SimilarityApi] for `FakeRepository`.
mixin FakeSimilarity on FakeRepositoryState implements SimilarityApi {
  /// Similarity coverage served by [getSimilarityStatus].
  SimilarityStatus similarityStatus = const SimilarityStatus(
    enabled: false,
    embeddedTracks: 0,
    totalTracks: 0,
    coveragePct: 0,
    queueDepth: 0,
  );

  /// Held open, [getSimilarityStatus] waits on it.
  Completer<void>? similarityStatusGate;

  @override
  Future<SimilarityStatus> getSimilarityStatus() async {
    await similarityStatusGate?.future;
    return similarityStatus;
  }
}
