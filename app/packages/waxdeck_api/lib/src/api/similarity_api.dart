import '../models.dart';

/// Similarity index status.
abstract interface class SimilarityApi {
  /// `GET /similarity/status`: coverage of the sonic-similarity
  /// surface, for deciding whether to show sonic affordances.
  Future<SimilarityStatus> getSimilarityStatus();
}
