import '../models.dart';

/// Enrichment sources, runs and status.
abstract interface class EnrichmentApi {
  /// `GET /library/enrichment`: provider roster and coverage.
  Future<EnrichmentStatus> getEnrichmentStatus();

  /// `POST /library/enrichment/run`: starts a library-wide enrichment
  /// pass, returning the job pid. [force] re-asks everything,
  /// [forcePhases] the named phases alone, and [phases] walks only those.
  Future<String> runEnrichment({
    bool force = false,
    List<String> forcePhases = const [],
    List<String> phases = const [],
  });

  /// `PUT /library/enrichment/sources`: the order this server's own
  /// providers are asked in, and which are asked at all.
  Future<EnrichmentStatus> putEnrichmentSources(List<EnrichmentSource> sources);
}
