import '../models.dart';

/// Library health, diagnostics, duplicates and upgrades.
abstract interface class HealthApi {
  /// `GET /library/health`: the library health scoreboard.
  Future<HealthSummary> getLibraryHealth();

  /// `GET /library/health/issues`: keyset-paginated failing items,
  /// optionally filtered to one [rule].
  Future<HealthIssuePage> listHealthIssues({
    String? rule,
    String? cursor,
    int? limit,
  });

  /// `GET /library/diagnostics`: per-file diagnostics across the library,
  /// optionally narrowed by [origin], [code], [severity], or [library], and
  /// keyset-paginated. Administrators only.
  Future<FileDiagnosticPage> listFileDiagnostics({
    String? origin,
    String? code,
    String? severity,
    String? library,
    String? cursor,
    int? limit,
  });

  /// `GET /library/diagnostics/summary`: diagnostic counts grouped by
  /// writer, code, and severity, most severe first. Administrators only.
  Future<List<DiagnosticCount>> getDiagnosticSummary({
    String? origin,
    String? code,
    String? severity,
    String? library,
  });

  /// `POST /library/health/sweep`: queues a full health re-evaluation.
  Future<void> sweepLibraryHealth();

  /// `POST /library/health/fix`: starts the fix for one [rule], on
  /// [itemPids] or on every failing item, answering where it runs.
  Future<HealthFixStart> fixHealthIssues({
    required String rule,
    List<String>? itemPids,
  });

  /// `GET /library/duplicates`: detected duplicate entity clusters.
  Future<List<DuplicateGroup>> listDuplicates();

  /// `POST /library/duplicates/merge`: merges [loserPids] into
  /// [survivorPid]. [entityType] is `album`, `artist`,
  /// `release-group`, `genre`, or `series`.
  Future<MergeOutcome> mergeDuplicates({
    required String entityType,
    required String survivorPid,
    required List<String> loserPids,
  });

  /// `GET /library/folds`: one page of the names merges folded into an
  /// entity, by type and then key.
  Future<EntityFoldPage> listEntityFolds({String? cursor, int? limit});

  /// `POST /library/folds/unfold`: forgets the folds of [keys], all of
  /// them or none, so the files still spelled that way file under their
  /// own name at the next scan.
  Future<void> unfoldEntities({
    required String entityType,
    required List<String> keys,
  });

  /// `GET /library/upgrades`: recordings present in more than one
  /// quality.
  Future<List<UpgradeGroup>> listUpgrades();

  /// `POST /library/upgrades/resolve`: keeps one member and trashes
  /// the rest, returning the trashed file count: whole items across
  /// items ([removeItemPids]), or files of [keepItemPid] within one
  /// ([keepFilePid] and [removeFilePids]).
  Future<int> resolveUpgrade({
    required String keepItemPid,
    List<String> removeItemPids = const [],
    String? keepFilePid,
    List<String> removeFilePids = const [],
  });
}
