import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';

/// The library health scoreboard, with the fix and sweep actions.
class HealthController extends AsyncNotifier<HealthSummary> {
  @override
  Future<HealthSummary> build() =>
      ref.watch(repositoryProvider).getLibraryHealth();

  /// Queues automatic repairs for every failing item of one rule;
  /// returns the queued count.
  Future<int> fix(String rule) async {
    final queued = await ref
        .read(repositoryProvider)
        .fixHealthIssues(rule: rule);
    if (ref.mounted) ref.invalidateSelf();
    return queued;
  }

  /// Queues a full re-evaluation; the score refreshes as it lands.
  Future<void> sweep() => ref.read(repositoryProvider).sweepLibraryHealth();
}

final healthProvider = AsyncNotifierProvider<HealthController, HealthSummary>(
  HealthController.new,
);

/// Accumulated pages of one rule's failing items.
class HealthIssuesState {
  const HealthIssuesState({
    required this.items,
    this.nextCursor,
    this.loadingMore = false,
    this.loadError = false,
  });

  final List<HealthIssue> items;
  final String? nextCursor;
  final bool loadingMore;

  /// True when the last page fetch failed; reset when the next fetch starts,
  /// so a listener reads each fresh failure as an edge.
  final bool loadError;

  bool get hasMore => nextCursor != null;

  HealthIssuesState copyWith({bool? loadingMore, bool? loadError}) =>
      HealthIssuesState(
        items: items,
        nextCursor: nextCursor,
        loadingMore: loadingMore ?? this.loadingMore,
        loadError: loadError ?? this.loadError,
      );
}

/// Pages the failing items of one rule with keyset cursors.
class HealthIssuesController extends AsyncNotifier<HealthIssuesState> {
  HealthIssuesController(this.rule);

  static const pageSize = 60;

  final String rule;

  var _generation = 0;

  @override
  Future<HealthIssuesState> build() async {
    _generation++;
    final page = await ref
        .watch(repositoryProvider)
        .listHealthIssues(rule: rule, limit: pageSize);
    return HealthIssuesState(items: page.items, nextCursor: page.nextCursor);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true, loadError: false));
    try {
      final page = await ref
          .read(repositoryProvider)
          .listHealthIssues(
            rule: rule,
            cursor: current.nextCursor,
            limit: pageSize,
          );
      if (generation != _generation) return;
      state = AsyncData(
        HealthIssuesState(
          items: [...current.items, ...page.items],
          nextCursor: page.nextCursor,
        ),
      );
    } on WaxDeckApiException {
      // An expected transport or server error. Keep what we have;
      // scrolling near the end again retries.
      if (generation != _generation) return;
      state = AsyncData(current.copyWith(loadingMore: false, loadError: true));
    } catch (_) {
      // Anything else is a defect, not a hiccup: a decode failure,
      // a bad cast. Release the paging guard first - loadingMore is
      // what keeps two fetches from racing, so leaving it set would
      // wedge paging permanently and silently - then let the error
      // reach the zone's handler instead of vanishing here.
      if (generation == _generation) {
        state = AsyncData(
          current.copyWith(loadingMore: false, loadError: true),
        );
      }
      rethrow;
    }
  }
}

final healthIssuesProvider =
    AsyncNotifierProvider.family<
      HealthIssuesController,
      HealthIssuesState,
      String
    >(HealthIssuesController.new);

/// Detected duplicate clusters, with the merge action.
class DuplicatesController extends AsyncNotifier<List<DuplicateGroup>> {
  @override
  Future<List<DuplicateGroup>> build() =>
      ref.watch(repositoryProvider).listDuplicates();

  Future<MergeOutcome> merge(DuplicateGroup group) async {
    final outcome = await ref
        .read(repositoryProvider)
        .mergeDuplicates(
          entityType: group.entityType,
          survivorPid: group.survivor.pid,
          loserPids: [for (final loser in group.losers) loser.pid],
        );
    if (ref.mounted) ref.invalidateSelf();
    return outcome;
  }
}

final duplicatesProvider =
    AsyncNotifierProvider<DuplicatesController, List<DuplicateGroup>>(
      DuplicatesController.new,
    );

/// Recordings held in more than one quality, with the resolve action
/// (keep the best member, trash the rest).
class UpgradesController extends AsyncNotifier<List<UpgradeGroup>> {
  @override
  Future<List<UpgradeGroup>> build() =>
      ref.watch(repositoryProvider).listUpgrades();

  /// Returns the trashed count.
  Future<int> resolve(UpgradeGroup group) async {
    final keep =
        group.members.where((m) => m.best).firstOrNull ?? group.members.first;
    final removed = await ref
        .read(repositoryProvider)
        .resolveUpgrade(
          keepItemPid: keep.itemPid,
          removeItemPids: [
            for (final member in group.members)
              if (member.itemPid != keep.itemPid) member.itemPid,
          ],
        );
    if (ref.mounted) ref.invalidateSelf();
    return removed;
  }
}

final upgradesProvider =
    AsyncNotifierProvider<UpgradesController, List<UpgradeGroup>>(
      UpgradesController.new,
    );
