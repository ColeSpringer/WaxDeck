import 'dart:async';

import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [HealthApi] for `FakeRepository`.
mixin FakeHealth on FakeRepositoryState implements HealthApi {
  /// Health state served by the health endpoints.
  HealthSummary healthSummary = const HealthSummary(
    score: 100,
    totalItems: 0,
    evaluatedItems: 0,
  );
  List<HealthIssue> healthIssues = [];

  /// Thrown by the health endpoints when set.
  WaxDeckApiException? healthError;

  int sweepCalls = 0;
  final List<({String rule, List<String>? itemPids})> fixHealthCalls = [];

  /// Where a started fix answers it runs; null starts it on `jb-fix`.
  HealthFixStart? fixHealthStart;

  /// Holds a fix's answer until completed, for the in-flight state.
  Completer<void>? fixHealthGate;

  /// Thrown by the fix when set; [healthError] fails the reads alone.
  WaxDeckApiException? fixHealthError;

  List<DuplicateGroup> duplicateGroups = const [];
  final List<({String entityType, String survivorPid, List<String> loserPids})>
  mergeDuplicatesCalls = [];

  /// The folded names, which a merge adds to as the server does.
  List<EntityFold> entityFolds = const [];

  /// Thrown by [listEntityFolds] when set; [listEntityFoldsCalls] counts
  /// the asks.
  WaxDeckApiException? foldsError;
  int listEntityFoldsCalls = 0;

  /// Each unfold asked for, and what it refuses with when set.
  final List<({String entityType, List<String> keys})> unfoldCalls = [];
  WaxDeckApiException? unfoldError;

  List<UpgradeGroup> upgradeGroups = const [];
  final List<
    ({
      String keepItemPid,
      List<String> removeItemPids,
      String? keepFilePid,
      List<String> removeFilePids,
    })
  >
  resolveUpgradeCalls = [];

  /// Thrown by [listUpgrades] when set; [listUpgradesCalls] counts the
  /// asks.
  WaxDeckApiException? upgradesError;
  int listUpgradesCalls = 0;

  /// Thrown by [resolveUpgrade] after it trashed what it was named, as
  /// the server refuses a move the trash could not make once the others
  /// went.
  WaxDeckApiException? resolveUpgradeRefusal;
  final List<FileDiagnostic> fileDiagnostics = [];

  /// The cursor every diagnostics page answers, so the screen offers more.
  String? fileDiagnosticsNextCursor;
  final List<DiagnosticCount> diagnosticCounts = [];

  @override
  Future<HealthSummary> getLibraryHealth() async {
    await healthGate?.future;
    final error = healthError;
    if (error != null) throw error;
    return healthSummary;
  }

  /// Holds a health read until completed, for the moment between a
  /// request and the summary that answers it.
  Completer<void>? healthGate;

  /// When set, a later page of [listHealthIssues] waits for it.
  Completer<void>? listHealthIssuesMoreGate;

  @override
  Future<HealthIssuePage> listHealthIssues({
    String? rule,
    String? cursor,
    int? limit,
  }) async {
    if (cursor != null) await listHealthIssuesMoreGate?.future;
    final error = healthError;
    if (error != null) throw error;
    final filtered = rule == null
        ? healthIssues
        : healthIssues.where((i) => i.rules.contains(rule)).toList();
    final start = cursor == null ? 0 : int.parse(cursor);
    final pageSize = limit ?? 100;
    final end = (start + pageSize).clamp(0, filtered.length);
    return HealthIssuePage(
      items: filtered.sublist(start.clamp(0, filtered.length), end),
      nextCursor: end < filtered.length ? '$end' : null,
    );
  }

  /// Held open, [listFileDiagnostics] waits on it.
  Completer<void>? listFileDiagnosticsGate;

  @override
  Future<FileDiagnosticPage> listFileDiagnostics({
    String? origin,
    String? code,
    String? severity,
    String? library,
    String? cursor,
    int? limit,
  }) async {
    await listFileDiagnosticsGate?.future;
    final filtered = fileDiagnostics
        .where((d) => origin == null || d.origin == origin)
        .where((d) => code == null || d.code == code)
        .where((d) => severity == null || d.severity == severity)
        .toList();
    return FileDiagnosticPage(
      diagnostics: filtered,
      nextCursor: fileDiagnosticsNextCursor,
    );
  }

  @override
  Future<List<DiagnosticCount>> getDiagnosticSummary({
    String? origin,
    String? code,
    String? severity,
    String? library,
  }) async => List.unmodifiable(diagnosticCounts);

  @override
  Future<void> sweepLibraryHealth() async {
    sweepCalls++;
  }

  @override
  Future<HealthFixStart> fixHealthIssues({
    required String rule,
    List<String>? itemPids,
  }) async {
    fixHealthCalls.add((rule: rule, itemPids: itemPids));
    await fixHealthGate?.future;
    final error = fixHealthError;
    if (error != null) throw error;
    return fixHealthStart ??
        HealthFixStart(
          queued:
              itemPids?.length ??
              healthIssues.where((i) => i.rules.contains(rule)).length,
          jobPid: 'jb-fix',
        );
  }

  @override
  Future<List<DuplicateGroup>> listDuplicates() async =>
      List.of(duplicateGroups);

  @override
  Future<MergeOutcome> mergeDuplicates({
    required String entityType,
    required String survivorPid,
    required List<String> loserPids,
  }) async {
    final error = healthError;
    if (error != null) throw error;
    mergeDuplicatesCalls.add((
      entityType: entityType,
      survivorPid: survivorPid,
      loserPids: List.of(loserPids),
    ));
    final group = duplicateGroups
        .where((g) => g.survivor.pid == survivorPid)
        .firstOrNull;
    final folded = [
      for (final loser in group?.losers ?? const <DuplicateEntity>[])
        if (loserPids.contains(loser.pid))
          EntityFold(
            entityType: entityType,
            key: loser.name.toLowerCase(),
            spelling: loser.name.toLowerCase(),
            entityPid: survivorPid,
            entityName: group!.survivor.name,
            createdAt: DateTime.utc(2026, 10, 1),
          ),
    ];
    entityFolds = [...entityFolds, ...folded];
    duplicateGroups = [
      for (final g in duplicateGroups)
        if (g.survivor.pid != survivorPid) g,
    ];
    return MergeOutcome(
      merged: loserPids.length,
      childrenMoved: 0,
      folds: [for (final f in folded) f.key],
    );
  }

  /// Held open, [listEntityFolds] waits on it.
  Completer<void>? listEntityFoldsGate;

  /// A page after the cursor's type and key, as the server's keyset
  /// pages: an unfold before the cursor shifts nothing after it.
  @override
  Future<EntityFoldPage> listEntityFolds({String? cursor, int? limit}) async {
    listEntityFoldsCalls++;
    await listEntityFoldsGate?.future;
    final error = foldsError;
    if (error != null) throw error;
    String at(EntityFold f) => '${f.entityType}|${f.key}';
    final after = cursor == null
        ? 0
        : entityFolds.indexWhere((f) => at(f).compareTo(cursor) > 0);
    final start = after < 0 ? entityFolds.length : after;
    final end = (start + (limit ?? 100)).clamp(0, entityFolds.length);
    final page = entityFolds.sublist(start, end);
    return EntityFoldPage(
      folds: page,
      nextCursor: end < entityFolds.length ? at(page.last) : null,
    );
  }

  /// Forgets the folds named, all or none, as the server does.
  @override
  Future<void> unfoldEntities({
    required String entityType,
    required List<String> keys,
  }) async {
    unfoldCalls.add((entityType: entityType, keys: List.of(keys)));
    if (unfoldError case final error?) throw error;
    bool named(EntityFold f) =>
        f.entityType == entityType && keys.contains(f.key);
    final missing = keys.where(
      (k) => !entityFolds.any((f) => f.entityType == entityType && f.key == k),
    );
    if (missing.isNotEmpty) {
      throw WaxDeckApiException(
        code: 'not-found',
        message: 'no $entityType fold of ${missing.join(', ')}',
        statusCode: 404,
      );
    }
    entityFolds = [
      for (final f in entityFolds)
        if (!named(f)) f,
    ];
  }

  @override
  Future<List<UpgradeGroup>> listUpgrades() async {
    listUpgradesCalls++;
    final error = upgradesError;
    if (error != null) throw error;
    return List.of(upgradeGroups);
  }

  @override
  Future<int> resolveUpgrade({
    required String keepItemPid,
    List<String> removeItemPids = const [],
    String? keepFilePid,
    List<String> removeFilePids = const [],
  }) async {
    final error = healthError;
    if (error != null) throw error;
    resolveUpgradeCalls.add((
      keepItemPid: keepItemPid,
      removeItemPids: List.of(removeItemPids),
      keepFilePid: keepFilePid,
      removeFilePids: List.of(removeFilePids),
    ));
    upgradeGroups = [
      for (final g in upgradeGroups)
        if (!g.members.any((m) => m.itemPid == keepItemPid)) g,
    ];
    final refusal = resolveUpgradeRefusal;
    if (refusal != null) throw refusal;
    return removeItemPids.length + removeFilePids.length;
  }
}
