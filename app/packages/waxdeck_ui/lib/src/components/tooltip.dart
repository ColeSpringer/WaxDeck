import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';

import '../tokens/motion.dart';
import '../tokens/spacing.dart';
import 'anchor.dart';

/// A hover label that always waits its own delay.
///
/// Material's tooltip is the thing this replaces, and the reason is one
/// behaviour rather than a matter of taste: once any tooltip in the tree
/// has been shown, every other tooltip the pointer touches opens with no
/// delay at all, for as long as one of them is still fading out.
/// Membership of that shared set is what suppresses the wait, so no
/// combination of `waitDuration`, `exitDuration`, and `triggerMode`
/// turns it off. Crossing a row of icon buttons on the way to the one
/// you meant to press therefore trails a label from every button on the
/// way, which is the complaint this answers: a tooltip should be
/// something a pointer asks for by resting, not something it collects.
///
/// So the delay here is per instance and unconditional. Hovering starts
/// this widget's own timer; leaving cancels it; a neighbour's tooltip
/// has no bearing on either. Everything else follows Material closely
/// enough to be a drop-in: the durations and the decoration come from
/// [TooltipThemeData], the label is placed below the target where there
/// is room and above it where there is not, a long press shows it on
/// touch, and a tap or a scroll dismisses it.
///
/// The accessible name is unchanged: a [Semantics] `tooltip` on the
/// child, which is what Flutter web folds into the name that
/// role-and-name locators match on.
class WaxTooltip extends StatefulWidget {
  const WaxTooltip({
    required this.message,
    required this.child,
    this.touchTrigger = true,
    this.excludeFromSemantics = false,
    this.showOnFocus = false,
    this.suppressed = WaxTooltipSuppression.none,
    super.key,
  });

  /// What the label reads, and - unless [excludeFromSemantics] - what a
  /// screen reader hears as the target's description.
  ///
  /// Null is a label with nothing to say: nothing opens, no pointer or
  /// long press is taken from a holder, and the child keeps its place in
  /// the tree, so a label that comes and goes never rebuilds what it wraps.
  final String? message;

  /// Whether a long press opens the label, which is how a touch device
  /// asks for one.
  ///
  /// Off where the target owns that gesture for something else: a media
  /// card's long press is its overflow menu, and a label that claimed
  /// it would shadow the menu.
  final bool touchTrigger;

  /// Drop the semantics description, for a target whose accessible name
  /// already carries the same words.
  final bool excludeFromSemantics;

  /// Whether keyboard focus landing on [child], or inside it, opens the
  /// label as a pointer resting on it would, and focus leaving closes it.
  /// Off by default: it is for a target that is only a hint, where a
  /// keyboard user has no other way to ask.
  final bool showOnFocus;

  /// Which of the label's ways of opening are held back.
  final WaxTooltipSuppression suppressed;

  final Widget child;

  @override
  State<WaxTooltip> createState() => _WaxTooltipState();
}

/// What a [WaxTooltip] holds back.
enum WaxTooltipSuppression {
  /// Nothing: hover, a long press and, with `showOnFocus`, focus.
  none,

  /// Only the label focus would open, for a focus that has already had
  /// its answer; hover and a long press still open one.
  focus,

  /// Every label: none opens, and one that is open closes. For a target
  /// that is showing the same words some other way.
  all,
}

class _WaxTooltipState extends State<WaxTooltip> {
  final OverlayPortalController _portal = OverlayPortalController();

  /// This instance's delay, and nobody else's.
  Timer? _waiting;

  /// The touch path's own life span; a hover has no limit but leaving.
  Timer? _showing;

  /// Whether focus is on the target now, for the frame-late measure.
  bool _focused = false;

  /// The focus listener's own node, so a focus the target already held
  /// when this label arrived around it can be read back: nothing reports
  /// a focus that did not change.
  final FocusNode _focusWatch = FocusNode(debugLabel: 'wax-tooltip-focus');

  Offset _target = Offset.zero;
  double _verticalOffset = WaxSpace.s24;

  /// Whether the global pointer route is installed. It is what dismisses
  /// on a tap or a scroll anywhere, and it is only worth listening to
  /// while this tooltip is waiting or open.
  bool _listening = false;

  Duration get _waitDuration =>
      TooltipTheme.of(context).waitDuration ??
      const Duration(milliseconds: 400);

  Duration get _showDuration =>
      TooltipTheme.of(context).showDuration ??
      const Duration(milliseconds: 1500);

  void _listen() {
    if (_listening) return;
    _listening = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  void _unlisten() {
    if (!_listening) return;
    _listening = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
  }

  /// A press or a scroll anywhere is the pointer doing something else,
  /// which is the end of the label and of any delay running towards one.
  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent ||
        event is PointerScrollEvent ||
        event is PointerPanZoomStartEvent) {
      _dismiss();
    }
  }

  /// Whether no label may show at all.
  bool get _silenced =>
      widget.message == null || widget.suppressed == WaxTooltipSuppression.all;

  @override
  void initState() {
    super.initState();
    if (widget.showOnFocus) _catchUpWithFocus();
  }

  @override
  void didUpdateWidget(WaxTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasSilenced =
        oldWidget.message == null ||
        oldWidget.suppressed == WaxTooltipSuppression.all;
    if (_silenced && !wasSilenced) {
      // The portal cannot be hidden while the tree is building.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _silenced) _dismiss();
      });
    }
    if (widget.showOnFocus && !oldWidget.showOnFocus) _catchUpWithFocus();
    // Words arriving for a focus the keyboard already holds, such as a
    // failure's reason on the button just pressed, open as they would have
    // had the focus arrived with them.
    if (widget.showOnFocus &&
        oldWidget.showOnFocus &&
        oldWidget.message == null &&
        widget.message != null &&
        _focused) {
      _focusChanged(true);
    }
  }

  /// A label that arrives around a target the keyboard already holds, such
  /// as a failure's reason on the button that was just pressed, opens as
  /// one that saw the focus arrive would. Read once its listener is in the
  /// tree.
  void _catchUpWithFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _focused || !_focusWatch.hasFocus) return;
      _focused = true;
      _focusChanged(true);
    });
  }

  void _scheduleShow() {
    if (_silenced) return;
    _waiting?.cancel();
    _listen();
    _waiting = Timer(_waitDuration, _show);
  }

  void _show({Duration? forDuration}) {
    _waiting?.cancel();
    _waiting = null;
    if (_silenced) return;
    final anchor = measureAnchor(context);
    if (anchor == null) return;
    // Measured at the moment of showing rather than tracked: a label
    // that outlives its target's position is dismissed by the scroll
    // that moved it.
    _target = anchor.target;
    _verticalOffset = anchor.halfHeight + WaxSpace.s8;
    _listen();
    _portal.show();
    _showing?.cancel();
    _showing = forDuration == null ? null : Timer(forDuration, _dismiss);
  }

  /// Only a keyboard's focus asks: a tap also focuses, and that is not
  /// a request for a label. Measured a frame on, since focus scrolls its
  /// target into view and the label belongs where that lands.
  void _focusChanged(bool focused) {
    if (!focused) {
      _dismiss();
      return;
    }
    if (FocusManager.instance.highlightMode != FocusHighlightMode.traditional) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _focused &&
          widget.suppressed != WaxTooltipSuppression.focus) {
        _show();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  KeyEventResult _focusKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !_portal.isShowing) {
      return KeyEventResult.ignored;
    }
    _dismiss();
    return KeyEventResult.handled;
  }

  void _dismiss() {
    _waiting?.cancel();
    _waiting = null;
    _showing?.cancel();
    _showing = null;
    _unlisten();
    if (_portal.isShowing) _portal.hide();
  }

  @override
  void dispose() {
    _waiting?.cancel();
    _showing?.cancel();
    _unlisten();
    _focusWatch.dispose();
    super.dispose();
  }

  Widget _label(BuildContext context) {
    // Suppressed in this very frame; the portal itself closes a frame on.
    if (_silenced) return const SizedBox.shrink();
    final theme = TooltipTheme.of(context);
    final motion = WaxMotion.of(context);
    return IgnorePointer(
      child: CustomSingleChildLayout(
        delegate: AnchorLayout(
          target: _target,
          verticalOffset: _verticalOffset,
          preferBelow: theme.preferBelow ?? true,
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: motion.quick,
          curve: WaxMotion.easeOut,
          builder: (context, value, child) =>
              Opacity(opacity: value, child: child),
          child: Container(
            padding:
                theme.padding ??
                const EdgeInsets.symmetric(
                  horizontal: WaxSpace.s8,
                  vertical: WaxSpace.s4,
                ),
            decoration: theme.decoration,
            // Wide enough for a sentence, narrow enough that it reads as
            // a label rather than as a paragraph floating over the page.
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(widget.message!, style: theme.textStyle),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final speaks = widget.message != null;
    final target = _ExclusiveMouseRegion(
      onEnter: speaks ? (_) => _scheduleShow() : null,
      onExit: speaks ? (_) => _dismiss() : null,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        excludeFromSemantics: true,
        onLongPress: speaks && widget.touchTrigger
            ? () => _show(forDuration: _showDuration)
            : null,
        child: widget.showOnFocus
            ? Focus(
                focusNode: _focusWatch,
                canRequestFocus: false,
                skipTraversal: true,
                onFocusChange: (focused) {
                  _focused = focused;
                  _focusChanged(focused);
                },
                onKeyEvent: _focusKey,
                child: widget.child,
              )
            : widget.child,
      ),
    );
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _label,
      child: widget.excludeFromSemantics
          ? target
          : Semantics(tooltip: widget.message, child: target),
    );
  }
}

/// A hover region only the innermost of a nest reacts to.
///
/// Tooltips nest: a media card names itself on hover and the play
/// affordance drawn over its artwork names itself too. Both regions
/// contain the pointer, so both plain [MouseRegion]s would fire and two
/// labels would open a few pixels apart. Material has the same problem
/// and the same answer - the outer regions are told, during the hit
/// test, that something below them already claimed the pointer.
class _ExclusiveMouseRegion extends MouseRegion {
  const _ExclusiveMouseRegion({super.onEnter, super.onExit, super.child});

  @override
  _RenderExclusiveMouseRegion createRenderObject(BuildContext context) =>
      _RenderExclusiveMouseRegion(onEnter: onEnter, onExit: onExit);
}

class _RenderExclusiveMouseRegion extends RenderMouseRegion {
  _RenderExclusiveMouseRegion({super.onEnter, super.onExit});

  /// Whether this hit test has reached one of these yet, and whether one
  /// deeper down has already taken the pointer. Static because the walk
  /// is depth-first and single-threaded: the outermost region of a nest
  /// opens the pair and closes it again on the way out.
  static bool _outermost = true;
  static bool _claimed = false;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final opening = _outermost;
    _outermost = false;
    var hit = false;
    if (size.contains(position) && onEnter == null && onExit == null) {
      // A label with nothing to say: its child answers, and the pointer is
      // left to a region around it.
      hit = hitTestChildren(result, position: position);
    } else if (size.contains(position)) {
      // Children first, so a region deeper in this nest has had its say
      // before this one decides. Adding the entry is the decision:
      // whether the pointer *enters* here is what the result holds, not
      // what this returns.
      hit =
          hitTestChildren(result, position: position) || hitTestSelf(position);
      if (!_claimed && (hit || behavior == HitTestBehavior.translucent)) {
        result.add(BoxHitTestEntry(this, position));
        if (hit) _claimed = true;
      }
    }
    if (opening) {
      _outermost = true;
      _claimed = false;
    }
    return hit;
  }
}
