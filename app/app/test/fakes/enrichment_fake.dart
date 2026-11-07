import 'dart:async';

import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [EnrichmentApi] for `FakeRepository`.
mixin FakeEnrichment on FakeRepositoryState implements EnrichmentApi {
  /// Enrichment status served by [getEnrichmentStatus].
  EnrichmentStatus enrichmentStatus = const EnrichmentStatus(
    coverage: EnrichmentCoverage(
      artists: CoverageCount(enriched: 0, total: 0),
      releaseGroups: CoverageCount(enriched: 0, total: 0),
      books: CoverageCount(enriched: 0, total: 0),
      lyrics: CoverageCount(enriched: 0, total: 0),
    ),
    running: false,
  );

  /// What each [runEnrichment] asked for, in order.
  final List<({bool force, List<String> forcePhases, List<String> phases})>
  runEnrichmentCalls = [];

  /// Each saved source order, in order.
  final List<List<EnrichmentSource>> putEnrichmentSourcesCalls = [];

  /// Holds every status read until completed; the read answers the
  /// status as it stood when asked, as a read already out does.
  Completer<void>? enrichmentStatusGate;

  /// Thrown by every status read while set.
  WaxDeckApiException? enrichmentStatusError;
  int enrichmentStatusReads = 0;

  /// Thrown by [runEnrichment] and [putEnrichmentSources] while set.
  WaxDeckApiException? runEnrichmentError;
  WaxDeckApiException? putEnrichmentSourcesError;

  @override
  Future<EnrichmentStatus> getEnrichmentStatus() async {
    enrichmentStatusReads++;
    final served = enrichmentStatus;
    await enrichmentStatusGate?.future;
    if (enrichmentStatusError case final error?) throw error;
    return served;
  }

  @override
  Future<String> runEnrichment({
    bool force = false,
    List<String> forcePhases = const [],
    List<String> phases = const [],
  }) async {
    runEnrichmentCalls.add((
      force: force,
      forcePhases: forcePhases,
      phases: phases,
    ));
    await runEnrichmentGate?.future;
    if (runEnrichmentError case final error?) throw error;
    return 'jb-FAKEENRICH';
  }

  /// Holds a run's answer until completed, for the in-flight state.
  Completer<void>? runEnrichmentGate;

  /// The catalog's built-ins in its own order, which is where one left
  /// out of a save goes.
  static const _catalogOrder = [
    'coverartarchive',
    'musicbrainz',
    'listenbrainz',
    'lrclib',
  ];

  /// Stores the order the way the server does: every provider that is
  /// not built in named once, a built-in where named and after the rest,
  /// switched on, where not; and the phases their capabilities open
  /// recomputed.
  @override
  Future<EnrichmentStatus> putEnrichmentSources(
    List<EnrichmentSource> sources,
  ) async {
    putEnrichmentSourcesCalls.add(sources);
    if (putEnrichmentSourcesError case final error?) throw error;
    final current = enrichmentStatus;
    final byName = {for (final p in current.providers) p.name: p};
    final named = [for (final s in sources) s.name];
    final own = [
      for (final p in current.providers)
        if (!p.builtin) p.name,
    ];
    if (named.any((n) => !byName.containsKey(n)) ||
        named.toSet().length != named.length ||
        !own.every(named.contains)) {
      throw const WaxDeckApiException(
        code: 'invalid-request',
        message: 'the order must name every provider this server adds once',
        statusCode: 400,
      );
    }
    final providers = <EnrichmentProvider>[
      for (final s in sources)
        EnrichmentProvider(
          name: s.name,
          capabilities: byName[s.name]!.capabilities,
          configured: byName[s.name]!.configured,
          builtin: byName[s.name]!.builtin,
          enabled: s.enabled,
        ),
      for (final name in _catalogOrder)
        if (byName[name] case final p? when !named.contains(name))
          EnrichmentProvider(
            name: p.name,
            capabilities: p.capabilities,
            configured: p.configured,
            builtin: true,
          ),
    ];
    const opens = <String, List<String>>{
      'aux-art': ['group-art', 'album-art'],
      'artist-art': ['artist-art'],
      'artist-front': ['artist-art'],
      'artist-background': ['artist-art'],
      'cover': ['group-art', 'album-art'],
      'lyrics': ['lyrics'],
      'fields': ['track-fields', 'album-fields'],
      'book': ['book-fields'],
    };
    final open = {
      if (current.musicbrainzConfigured) ...['identity', 'releases'],
      for (final p in providers)
        if (p.enabled && (!p.builtin || current.musicbrainzConfigured))
          for (final c in p.capabilities) ...?opens[c],
    };
    final phases = [
      for (final phase in current.phases)
        if (open.contains(phase)) phase,
    ];
    enrichmentStatus = EnrichmentStatus(
      providers: providers,
      coverage: current.coverage,
      running: current.running,
      runningJob: current.runningJob,
      configured: phases.isNotEmpty,
      musicbrainzConfigured: current.musicbrainzConfigured,
      phases: phases,
      lastRun: current.lastRun,
    );
    return enrichmentStatus;
  }
}
