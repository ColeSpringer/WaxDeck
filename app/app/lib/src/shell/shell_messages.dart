import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// One transient message the shell raises for code with no
/// `BuildContext` - playback's verbs converge in a notifier, and the
/// shell is the one widget that outlives every screen.
/// `lifecycle_banners.dart` is the same shape for standing state.
class ShellMessage {
  const ShellMessage({
    required this.text,
    this.actionLabel,
    this.onAction,
    this.actionSemanticsId,
  });

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? actionSemanticsId;
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
  }) {
    state = ShellMessage(
      text: text,
      actionLabel: actionLabel,
      onAction: onAction,
      actionSemanticsId: actionSemanticsId,
    );
  }

  /// Drops the delivered message, so its action closure is not held for
  /// the session on a notifier nothing disposes.
  void clear() => state = null;
}

final shellMessengerProvider = NotifierProvider<ShellMessenger, ShellMessage?>(
  ShellMessenger.new,
);
