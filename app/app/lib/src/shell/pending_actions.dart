import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The requests a person started that are still out, by action: a
/// control reads its own to draw busy, whichever surface started it (the
/// dashboard's scan and the command palette's are one action).
class PendingActions extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  /// Runs [action] under [key], which reads as pending until it settles.
  /// A second run while the first is out is dropped.
  Future<void> run(String key, Future<void> Function() action) =>
      runAll([key], action);

  /// Runs [action] under every one of [keys], claimed together: dropped
  /// while any of them is out, so a run never holds some of them.
  Future<void> runAll(
    Iterable<String> keys,
    Future<void> Function() action,
  ) async {
    final claimed = {...keys};
    if (claimed.any(state.contains)) return;
    state = {...state, ...claimed};
    try {
      await action();
    } finally {
      if (ref.mounted) state = state.difference(claimed);
    }
  }
}

final pendingActionsProvider = NotifierProvider<PendingActions, Set<String>>(
  PendingActions.new,
);

/// The action names, so a control and its trigger cannot disagree.
abstract final class PendingAction {
  static const scan = 'scan';
  static const backup = 'backup';
  static const backupImport = 'backup-import';
  static const trashEmpty = 'trash-empty';
  static String notifyTest(String pid) => 'notify-test-$pid';
  static String notifyTargetRemove(String pid) => 'notify-target-remove-$pid';
  static String appPasswordRevoke(String id) => 'app-password-revoke-$id';
  static String trashRestore(String id) => 'trash-restore-$id';

  /// One scrobbler slot's connect or disconnect: the slot shows one of
  /// the two at a time.
  static String scrobbler(String service) => 'scrobbler-$service';

  /// Follow and Following share one: they are one control.
  static String follow(String pid) => 'follow-$pid';
  static String markPlayed(String pid) => 'mark-played-$pid';

  /// One review entry's lock: one decision at a time, whichever control
  /// sent it (the pane's buttons, the queue's keys, a bulk decision).
  static String reviewEntry(String id) => 'review-entry-$id';

  /// The decision out on one review entry, which draws its control busy.
  /// Claimed with [reviewEntry].
  static String reviewAction(String id, String action) =>
      'review-action-$id-$action';
}
