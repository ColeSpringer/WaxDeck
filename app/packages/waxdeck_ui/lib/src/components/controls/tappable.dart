import 'package:material_ui/material_ui.dart';

import '../../l10n/wax_l10n.dart';
import '../../tokens/colors.dart';
import '../../tokens/radii.dart';
import '../tooltip.dart';
import 'focus_ring.dart';

/// The semantics, focus, and focus ring every tappable control needs,
/// wrapped once.
///
/// Three things have to happen together and are easy to ship two of. The
/// control announces itself once, which means excluding its subtree -
/// and excluding a subtree drops the `focusable` flag the [Focus] inside
/// would have contributed, which is what web turns into a `tabindex`, so
/// the node has to declare it back or the control is unreachable from a
/// keyboard while looking perfectly fine. Then, being reachable, it needs
/// a visible focus ring, or it is reachable and invisible.
///
/// The chrome shipped without the flag once already and rendered a whole
/// sidebar no keyboard could enter. This is that lesson as a widget, so
/// the next control gets all three by composing rather than by
/// remembering.
///
/// [child] keeps its own ink and its own tap handler; this adds no
/// gesture of its own, so nothing fires twice, save the one that spends a
/// press while [busy] or disabled.
class WaxTappable extends StatefulWidget {
  const WaxTappable({
    required this.label,
    required this.onPressed,
    required this.child,
    this.semanticsId,
    this.selected,
    this.expanded,
    this.borderRadius = WaxRadius.thumb,
    this.surface,
    this.busy = false,
    this.value,
    this.hint,
    this.tooltip,
    this.tooltipOnLongPress = false,
    this.inert = false,
    this.onKeyPress,
    super.key,
  });

  /// The accessible name. Stateful controls say what they will do.
  final String label;

  /// Null disables the control, which is reported as well as drawn, and
  /// spends a press rather than letting it through to what holds it.
  final VoidCallback? onPressed;

  /// Runs in place of [onPressed] when a key presses the focused control,
  /// for one whose answer depends on what pressed it: the info tip takes
  /// the keyboard into its popover only when a key opened it.
  final VoidCallback? onKeyPress;

  final Widget child;
  final String? semanticsId;

  /// Set on controls that are one of a set, so the state is announced
  /// rather than left to colour.
  final bool? selected;

  /// Set on a control that opens and closes what it heads, so whether it
  /// is open is announced.
  final bool? expanded;

  final BorderRadius borderRadius;

  /// The colour immediately under the ring, for its inner stroke.
  final Color? surface;

  /// Reported disabled and deaf to presses, its child's included, but it
  /// keeps the focus a keyboard press gave it.
  final bool busy;

  /// The spoken value, such as how far a download has got. Defaults to
  /// saying the control is working while [busy].
  final String? value;

  /// Read after the name, for what the label leaves out: why an action
  /// failed, what a state is waiting on.
  final String? hint;

  /// A [WaxTooltip], held outside the busy guard so it opens in every
  /// state, and opened by keyboard focus as by a resting pointer, so a
  /// control with one is a tab stop in every state, disabled included. Its
  /// words reach a reader only through [label] or [hint].
  final String? tooltip;

  /// Whether a long press shows [tooltip], which is how touch asks for
  /// one. Off unless the caller asks: this adds no gesture of its own,
  /// and a long press is often its holder's, such as a row's menu.
  final bool tooltipOnLongPress;

  /// A state to read rather than a control: no button and no press. It is
  /// a tab stop only with a [tooltip] to show; without one it keeps only
  /// the focus it held as a control, so a press that turns an action into
  /// a state leaves the keyboard where it was.
  final bool inert;

  @override
  State<WaxTappable> createState() => _WaxTappableState();
}

class _WaxTappableState extends State<WaxTappable> {
  bool _focused = false;

  final FocusNode _focus = FocusNode(debugLabel: 'wax-tappable');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Object? _activate(Intent _) {
    if (widget.busy || widget.inert || widget.onPressed == null) return null;
    (widget.onKeyPress ?? widget.onPressed)!();
    return null;
  }

  /// Once an inert control loses its place to a neighbour it is no stop
  /// at all.
  void _focusChanged(bool focused) {
    if (!focused && widget.inert) setState(() {});
  }

  /// Around the focus detector, so the control's own focus is focus inside
  /// the tooltip. Built with no tooltip too, as one with nothing to say, so
  /// the detector keeps its place, and its focus, as a tooltip comes and
  /// goes.
  Widget _withTooltip(Widget child) => WaxTooltip(
    message: widget.tooltip,
    excludeFromSemantics: true,
    showOnFocus: true,
    touchTrigger: widget.tooltipOnLongPress,
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final inert = widget.inert;
    final enabled = !inert && widget.onPressed != null && !widget.busy;
    // A greyed control is never a way into what is behind it. An inert
    // one is a state, not a control, so its presses pass.
    final spends = widget.busy || (!inert && widget.onPressed == null);
    // A tooltip is read by focusing it, so it makes a stop of any control.
    // An inert control with nothing to show stays focusable while its
    // scope would hand focus back to it (a dialog closing, the window
    // coming back), and drops out once focus moves on to a neighbour.
    final focusable =
        widget.tooltip != null ||
        (inert
            ? _focus.hasFocus || _focus.enclosingScope?.focusedChild == _focus
            : widget.onPressed != null || widget.busy);
    return Semantics(
      identifier: widget.semanticsId,
      container: inert,
      button: !inert,
      enabled: inert ? null : enabled,
      selected: widget.selected,
      expanded: widget.expanded,
      label: widget.label,
      value:
          widget.value ?? (widget.busy ? context.waxL10n.controlsBusy : null),
      hint: widget.hint,
      excludeSemantics: true,
      onTap: enabled ? widget.onPressed : null,
      focusable: focusable,
      // Null off a stop: a false here would report the node focusable
      // whatever the line above says.
      focused: focusable ? _focused : null,
      // Gated with the flag beside it. Supplying a focus action marks a
      // node focusable whatever `focusable` says, so a disabled control
      // with one advertises itself as a tab stop that does nothing -
      // which is the opposite of what the line above declares.
      onFocus: focusable ? _focus.requestFocus : null,
      child: _withTooltip(
        FocusableActionDetector(
          enabled: focusable,
          focusNode: _focus,
          // One stop, as it is one node to a reader: the ink a control
          // draws with is focusable too, and was a second press of Tab.
          descendantsAreTraversable: false,
          mouseCursor: enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          onFocusChange: _focusChanged,
          // Both: the web binds Enter to the button intent, Space to the
          // other.
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: _activate),
            ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
              onInvoke: _activate,
            ),
          },
          child: WaxFocusRing(
            focused: _focused,
            borderRadius: widget.borderRadius,
            surface: widget.surface ?? colors.canvas,
            // Busy or disabled, the press is spent here rather than
            // falling through to whatever holds the control; busy, the
            // child's ink hears nothing either.
            child: GestureDetector(
              behavior: spends
                  ? HitTestBehavior.opaque
                  : HitTestBehavior.deferToChild,
              excludeFromSemantics: true,
              onTap: spends ? () {} : null,
              child: AbsorbPointer(absorbing: widget.busy, child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}

/// A custom row or tile that is one control: [WaxTappable]'s semantics,
/// focus and ring around a [Material] ground and the [InkWell] that takes
/// the press.
///
/// [WaxTappable] adds no gesture, so a row built on it alone answers a key
/// and a screen reader but no pointer; this one answers all three. The
/// node and the ink take the one callback, never two that do the same
/// thing: on web a click on the node is the node's tap, so the two have
/// to be the same press.
class WaxInkTappable extends StatelessWidget {
  const WaxInkTappable({
    required this.label,
    required this.onPressed,
    required this.child,
    this.semanticsId,
    this.selected,
    this.expanded,
    this.value,
    this.color = Colors.transparent,
    this.borderRadius,
    this.surface,
    this.tooltip,
    this.tooltipOnLongPress = false,
    this.onLongPress,
    super.key,
  });

  /// The accessible name: what the row is, said once.
  final String label;

  /// The spoken value, as on [WaxTappable].
  final String? value;

  /// Null disables it, which is reported as well as drawn.
  final VoidCallback? onPressed;

  /// A press held down, for a row whose long press is a second way in,
  /// such as starting a selection. Taken only while [onPressed] is set: a
  /// disabled row takes no long press either.
  final VoidCallback? onLongPress;

  final Widget child;
  final String? semanticsId;

  /// Set on a row that is one of a set, as on [WaxTappable].
  final bool? selected;

  /// Set on a row that opens and closes what it heads, as on
  /// [WaxTappable].
  final bool? expanded;

  /// The ground the ink spreads on.
  final Color color;

  /// The corner the ground, the ink and the focus ring share. Null is
  /// square.
  final BorderRadius? borderRadius;

  /// The colour immediately under the ring, for its inner stroke.
  final Color? surface;

  /// What the row leaves out, as on [WaxTappable]: hover or keyboard
  /// focus shows it, and a long press where [tooltipOnLongPress] asks.
  final String? tooltip;

  /// As on [WaxTappable].
  final bool tooltipOnLongPress;

  @override
  Widget build(BuildContext context) => WaxTappable(
    label: label,
    onPressed: onPressed,
    semanticsId: semanticsId,
    selected: selected,
    expanded: expanded,
    value: value,
    borderRadius: borderRadius ?? BorderRadius.zero,
    surface: surface,
    tooltip: tooltip,
    tooltipOnLongPress: tooltipOnLongPress,
    child: Material(
      color: color,
      borderRadius: borderRadius,
      animationDuration: Duration.zero,
      child: InkWell(
        onTap: onPressed,
        onLongPress: onPressed == null ? null : onLongPress,
        borderRadius: borderRadius,
        child: child,
      ),
    ),
  );
}
