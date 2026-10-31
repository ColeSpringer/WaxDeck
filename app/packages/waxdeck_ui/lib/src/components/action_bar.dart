import 'package:material_ui/material_ui.dart';

import '../icons/wax_icon.dart';
import '../tokens/spacing.dart';
import 'controls.dart';

/// How much weight an action in a [WaxActionBar] carries.
enum WaxActionEmphasis {
  /// The thing the screen is for, drawn filled. At most one per bar.
  primary,

  /// Everything else, drawn tonal.
  secondary,
}

/// Where an action stands. Every state is a state of the one pill.
sealed class WaxActionState {
  const WaxActionState();

  /// Pressable, in its own emphasis.
  const factory WaxActionState.ready() = WaxActionReady;

  /// Work it started is in flight, with no share to report.
  const factory WaxActionState.busy() = WaxActionBusy;

  /// Work it started has got [WaxActionProgress.progress] of the way.
  const factory WaxActionState.progress(double progress) = WaxActionProgress;

  /// Finished. Pressable only when there is something left to do, such
  /// as removing what it fetched; otherwise a state to read.
  const factory WaxActionState.done() = WaxActionDone;

  /// A state to read, such as queued: no press, and no button to a
  /// screen reader.
  const factory WaxActionState.status() = WaxActionStatus;

  /// It went wrong. Pressable when it can be tried again; otherwise a
  /// state to read, like [WaxActionState.done] with no press.
  const factory WaxActionState.failed() = WaxActionFailed;
}

final class WaxActionReady extends WaxActionState {
  const WaxActionReady();
}

final class WaxActionBusy extends WaxActionState {
  const WaxActionBusy();
}

final class WaxActionProgress extends WaxActionState {
  const WaxActionProgress(this.progress);

  /// From 0 to 1; values outside are clamped when drawn, and one that is
  /// not finite (0 of 0) draws the busy pill.
  final double progress;
}

final class WaxActionDone extends WaxActionState {
  const WaxActionDone();
}

final class WaxActionStatus extends WaxActionState {
  const WaxActionStatus();
}

final class WaxActionFailed extends WaxActionState {
  const WaxActionFailed();
}

/// One action in a [WaxActionBar], as plain data.
@immutable
class WaxAction {
  const WaxAction({
    required this.label,
    required this.semanticsId,
    this.slot,
    this.glyph,
    this.onPressed,
    this.emphasis = WaxActionEmphasis.secondary,
    this.state = const WaxActionState.ready(),
    this.spokenLabel,
    this.detail,
  });

  final String label;

  /// The pill's handle, and its identity in the row unless [slot] names
  /// another.
  final String semanticsId;

  /// The pill's identity in the row, for an action whose [semanticsId]
  /// changes with its state (Download and Remove download): a pill that
  /// keeps its slot keeps its place and its focus. Null is [semanticsId].
  final Object? slot;

  /// Drawn before the label. A done or failed state draws its own glyph
  /// in place of this one.
  final WaxGlyph? glyph;

  final VoidCallback? onPressed;
  final WaxActionEmphasis emphasis;
  final WaxActionState state;

  /// What a screen reader hears in place of [label].
  final String? spokenLabel;

  /// The failure reason or status sentence: a tooltip, and read after
  /// the name. Never drawn as a second chip.
  final String? detail;
}

/// An entity's row of actions: every action a [WaxButton] pill, then
/// the [trailing] icon clusters, then the [overflow] menu.
///
/// The actions are data rather than widgets, so every state of every
/// action is drawn by the one pill and no action can be a chip.
class WaxActionBar extends StatelessWidget {
  WaxActionBar({
    required this.actions,
    this.trailing = const <Widget>[],
    this.overflow,
    this.alignment = WrapAlignment.start,
    super.key,
  }) : assert(
         actions.skip(1).every((a) => a.emphasis != WaxActionEmphasis.primary),
         'at most one primary action, and it is first',
       );

  final List<WaxAction> actions;

  /// Icon clusters after the pills, such as a star and a rating.
  final List<Widget> trailing;

  /// The overflow menu, always last.
  final Widget? overflow;

  final WrapAlignment alignment;

  static Widget _pill(WaxAction action) {
    final ownKind = action.emphasis == WaxActionEmphasis.primary
        ? WaxButtonKind.filled
        : WaxButtonKind.tonal;
    final key = ValueKey<Object>(action.slot ?? action.semanticsId);
    WaxButton pill({
      WaxButtonKind kind = WaxButtonKind.tonal,
      WaxGlyph? glyph,
      VoidCallback? onPressed,
      bool busy = false,
      double? progress,
      bool status = false,
    }) => WaxButton(
      key: key,
      label: action.label,
      spokenLabel: action.spokenLabel,
      semanticsId: action.semanticsId,
      detail: action.detail,
      kind: kind,
      icon: glyph,
      onPressed: onPressed,
      busy: busy,
      progress: progress,
      status: status,
    );
    return switch (action.state) {
      WaxActionReady() => pill(
        kind: ownKind,
        glyph: action.glyph,
        onPressed: action.onPressed,
      ),
      WaxActionBusy() => pill(
        kind: ownKind,
        glyph: action.glyph,
        onPressed: action.onPressed,
        busy: true,
      ),
      WaxActionProgress(:final progress) => pill(
        kind: ownKind,
        glyph: action.glyph,
        onPressed: action.onPressed,
        progress: progress,
      ),
      WaxActionStatus() => pill(glyph: action.glyph, status: true),
      // Finished or failed is not unavailable: with no verb left it is a
      // state to read, never the disabled tint.
      WaxActionDone() => pill(
        glyph: WaxIcons.success,
        onPressed: action.onPressed,
        status: action.onPressed == null,
      ),
      WaxActionFailed() => pill(
        glyph: WaxIcons.warning,
        onPressed: action.onPressed,
        status: action.onPressed == null,
      ),
    };
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: WaxSpace.s8,
    runSpacing: WaxSpace.s8,
    alignment: alignment,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: <Widget>[
      for (final action in actions) _pill(action),
      ...trailing,
      ?overflow,
    ],
  );
}
