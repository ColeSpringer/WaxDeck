import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The requests a person started that are still out, by action: a
/// control reads its own to draw busy, whichever surface started it (the
/// dashboard's scan and the command palette's are one action).
class PendingActions extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  /// Runs [action] under [key], which reads as pending until it settles.
  /// A second run while the first is out is dropped.
  Future<void> run(String key, Future<void> Function() action) async {
    if (state.contains(key)) return;
    state = {...state, key};
    try {
      await action();
    } finally {
      if (ref.mounted) state = {...state}..remove(key);
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
}
