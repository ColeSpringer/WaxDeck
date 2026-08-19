import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../l10n/wax_l10n.dart';
import '../tokens/colors.dart';
import '../tokens/motion.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';

/// The seam between two panes, and the grip that moves it.
///
/// A hairline like the divider it replaces, drawn inside a hit area wide
/// enough to grab: a one-pixel target is a target only in theory, and
/// widening the line itself would put a bar between two panes that are
/// meant to read as one surface. It thickens and takes the accent under
/// the pointer or the focus, which is the whole of the invitation.
///
/// Stateless about where it sits. [position] and its bounds come from the
/// caller, which is the half that knows what the two panes need and is
/// the half that persists the answer; this reports where the seam was
/// dragged to, already clamped, and paints the affordance.
///
/// Below the width at which two panes are drawn at all there is nothing
/// to split, so the caller draws no seam - which is also the answer on a
/// phone, where there is no pointer to drag one with.
class WaxSplitter extends StatefulWidget {
  const WaxSplitter({
    required this.position,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onSettled,
    this.onReset,
    this.step = WaxSpace.s32,
    this.label,
    this.semanticsId,
    super.key,
  }) : assert(
         min <= max,
         'a seam with no travel is a divider; draw one of those instead',
       ),
       assert(step > 0, 'step is the keyboard and screen-reader increment');

  /// The pane before the seam, in logical pixels.
  final double position;

  /// The travel, which is what the two panes can each give up. Callers
  /// derive it from what the pane on the far side needs, so dragging can
  /// never squeeze either one below the point where it stops working.
  final double min;
  final double max;

  /// Fired live as the seam moves, already clamped to [min] and [max] -
  /// so a caller that persists this never stores a width it would have
  /// to correct on the way back out. Once per pointer frame while a
  /// drag is in flight, which is what makes it the wrong place to write
  /// anything down.
  final ValueChanged<double> onChanged;

  /// Fired once where a gesture ends: the release of a drag, and each
  /// discrete keyboard step. Where a caller that persists the width
  /// does it.
  ///
  /// Separate from [onChanged] because the two answer different
  /// questions. A pane follows the pointer, so it wants every frame; a
  /// preference is what somebody settled on, and writing one per frame
  /// is a disk write per frame - on the web a synchronous storage
  /// write in the same frames laying the panes out, and a queue of
  /// unordered writes whose last landing is not where the pointer was
  /// let go.
  final ValueChanged<double>? onSettled;

  /// Back to the layout's own answer, on a double tap or a double click.
  /// Null leaves the seam with no reset and no double-tap handler, which
  /// is right for a caller whose default is wherever it was last put.
  final VoidCallback? onReset;

  /// What one arrow key or one screen-reader step moves.
  final double step;

  /// What the seam is called. Null takes the design system's own.
  final String? label;

  final String? semanticsId;

  /// The grabbable width. The line inside it stays a hairline; this is
  /// the pointer's business, and it is the same slop the panes lose
  /// between them either way.
  static const double hitWidth = WaxSpace.s12;

  @override
  State<WaxSplitter> createState() => _WaxSplitterState();
}

/// Widen the pane before the seam.
class _GrowIntent extends Intent {
  const _GrowIntent();
}

/// Narrow it.
class _ShrinkIntent extends Intent {
  const _ShrinkIntent();
}

class _WaxSplitterState extends State<WaxSplitter> {
  final FocusNode _focus = FocusNode(debugLabel: 'wax-splitter');
  bool _hovered = false;
  bool _focused = false;
  bool _dragging = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Where the seam was when this drag started, and how far the pointer
  /// has come since. Accumulated rather than integrated from the live
  /// position, because the caller may clamp or round what it stores: a
  /// drag that ran past [WaxSplitter.max] would otherwise have to be
  /// dragged all the way back before the seam moved again.
  double _grabbedAt = 0;
  double _travelled = 0;

  double _clamp(double value) => value.clamp(widget.min, widget.max);

  /// Which way is "wider". The pane before the seam is the leading one,
  /// so in a right-to-left layout it grows as the pointer moves left -
  /// and the arrow keys go with it, because the key that widens is the
  /// one pointing away from the pane.
  double get _towardsWider =>
      Directionality.of(context) == TextDirection.rtl ? -1 : 1;

  /// How far along its travel the seam sits, which is what a screen
  /// reader can act on - a pixel width says nothing about how much is
  /// left on either side.
  String _announce(double position) {
    final travel = widget.max - widget.min;
    return context.waxL10n.spellPercent(
      travel <= 0 ? 1 : (position - widget.min) / travel,
    );
  }

  void _nudge(double delta) {
    final moved = _clamp(widget.position + delta);
    if (moved == widget.position) return;
    widget.onChanged(moved);
    // A step is its own gesture: there is no release to wait for.
    widget.onSettled?.call(moved);
  }

  void _startDrag(DragStartDetails details) {
    setState(() {
      _dragging = true;
      _grabbedAt = widget.position;
      _travelled = 0;
    });
  }

  void _drag(DragUpdateDetails details) {
    _travelled += details.delta.dx * _towardsWider;
    final moved = _clamp(_grabbedAt + _travelled);
    if (moved != widget.position) widget.onChanged(moved);
  }

  void _endDrag() {
    if (!_dragging) return;
    setState(() => _dragging = false);
    widget.onSettled?.call(_clamp(_grabbedAt + _travelled));
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final motion = WaxMotion.of(context);
    final live = _dragging || _hovered || _focused;
    return Semantics(
      identifier: widget.semanticsId,
      slider: true,
      label: widget.label ?? context.waxL10n.splitterLabel,
      value: _announce(widget.position),
      // A slider offering increase without saying where increasing lands
      // is a half-built control, and an assertion failure besides.
      increasedValue: _announce(_clamp(widget.position + widget.step)),
      decreasedValue: _announce(_clamp(widget.position - widget.step)),
      onIncrease: widget.position < widget.max
          ? () => _nudge(widget.step)
          : null,
      onDecrease: widget.position > widget.min
          ? () => _nudge(-widget.step)
          : null,
      // Declared here rather than left to the detector below, which
      // `excludeSemantics` covers over: the arrow keys are half of what
      // this control is, and on the web a node that does not publish
      // itself as focusable gets no tab stop at all. Same shape as
      // `WaxIconButton`, for the same reason.
      excludeSemantics: true,
      focusable: true,
      focused: _focused,
      onFocus: _focus.requestFocus,
      child: FocusableActionDetector(
        focusNode: _focus,
        mouseCursor: SystemMouseCursors.resizeColumn,
        onShowHoverHighlight: (on) => setState(() => _hovered = on),
        onShowFocusHighlight: (on) => setState(() => _focused = on),
        shortcuts: const <ShortcutActivator, Intent>{
          // Named for the key rather than for the effect: which one
          // widens is [_towardsWider]'s business.
          SingleActivator(LogicalKeyboardKey.arrowLeft): _ShrinkIntent(),
          SingleActivator(LogicalKeyboardKey.arrowRight): _GrowIntent(),
        },
        actions: <Type, Action<Intent>>{
          _GrowIntent: CallbackAction<_GrowIntent>(
            onInvoke: (_) => _nudge(widget.step * _towardsWider),
          ),
          _ShrinkIntent: CallbackAction<_ShrinkIntent>(
            onInvoke: (_) => _nudge(-widget.step * _towardsWider),
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _startDrag,
          onHorizontalDragUpdate: _drag,
          onHorizontalDragEnd: (_) => _endDrag(),
          onHorizontalDragCancel: _endDrag,
          onDoubleTap: widget.onReset,
          child: SizedBox(
            width: WaxSplitter.hitWidth,
            height: double.infinity,
            child: Center(
              child: AnimatedContainer(
                duration: motion.quick,
                curve: WaxMotion.emphasized,
                width: live ? 3 : 1,
                decoration: BoxDecoration(
                  color: live ? colors.accent : colors.hairline,
                  borderRadius: WaxRadius.pill,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
