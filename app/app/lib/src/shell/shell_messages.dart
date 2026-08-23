import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';

/// One transient message the shell raises for code with no
/// `BuildContext` - playback's verbs converge in a notifier, and the
/// shell is the one widget that outlives every screen.
/// `lifecycle_banners.dart` is the same shape for standing state.
class ShellMessage {
  ShellMessage({
    required String text,
    this.actionLabel,
    this.onAction,
    this.actionSemanticsId,
    String? channel,
  }) : build = ((_) => text),
       channel = channel ?? actionSemanticsId;

  /// A message whose words are chosen where they are drawn rather than
  /// where they are raised.
  ///
  /// Most callers have a `BuildContext` and read `context.l10n` at the
  /// leaf, which is the rule. A notifier has neither, and the two ways
  /// around that - holding a context or reading a locale from a
  /// provider - are both the thing the rule forbids. So the caller
  /// hands over what to say and the shell says it, in the locale the
  /// shell is being built in.
  ShellMessage.localized(
    this.build, {
    this.actionLabel,
    this.onAction,
    this.actionSemanticsId,
    String? channel,
  }) : channel = channel ?? actionSemanticsId;

  /// The words, as a function of the locale drawing them. A message
  /// whose text was fixed where it was raised is one of these too, over
  /// a locale it ignores.
  final String Function(AppLocalizations l10n) build;

  final String? actionLabel;
  final VoidCallback? onAction;
  final String? actionSemanticsId;

  /// What this message replaces, when it is one of a run.
  ///
  /// Two messages sharing a channel are the same message said again -
  /// three skipped tracks, then the count that gave up on them - and
  /// the shell drops the standing one rather than stacking a second bar
  /// over it. Null is the ordinary case: a message with no channel
  /// supersedes nothing and is superseded by nothing.
  ///
  /// Defaults to the action's identifier, which is the ordinary case:
  /// the same offer raised twice ("Added to queue", "Open") is the same
  /// message, and the button is what says so. Named separately because
  /// a run with nothing to press has no button - and inventing a fake
  /// identifier to be coalesced by is a hand-typed semantics string,
  /// which is exactly what [SemanticsIds] exists to stop.
  final String? channel;

  /// The words to draw, in the locale the shell has.
  String resolve(AppLocalizations l10n) => build(l10n);
}

/// The shell's transient-message channel.
class ShellMessenger extends Notifier<ShellMessage?> {
  @override
  ShellMessage? build() => null;

  void show(
    String text, {
    String? actionLabel,
    VoidCallback? onAction,
    String? actionSemanticsId,
    String? channel,
  }) {
    state = ShellMessage(
      text: text,
      actionLabel: actionLabel,
      onAction: onAction,
      actionSemanticsId: actionSemanticsId,
      channel: channel,
    );
  }

  /// Raises a message whose sentence is picked where it is drawn, for a
  /// caller with no `BuildContext` to read one from.
  void showLocalized(
    String Function(AppLocalizations l10n) build, {
    String? actionLabel,
    VoidCallback? onAction,
    String? actionSemanticsId,
    String? channel,
  }) {
    state = ShellMessage.localized(
      build,
      actionLabel: actionLabel,
      onAction: onAction,
      actionSemanticsId: actionSemanticsId,
      channel: channel,
    );
  }

  /// Drops the delivered message, so its action closure is not held for
  /// the session on a notifier nothing disposes.
  void clear() => state = null;
}

final shellMessengerProvider = NotifierProvider<ShellMessenger, ShellMessage?>(
  ShellMessenger.new,
);
