import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';

import '../icons/wax_icon.dart';
import '../tokens/colors.dart';
import '../tokens/elevation.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'anchor.dart';
import 'controls.dart';
import 'tooltip.dart';

/// An info glyph that holds a sentence the screen does not print.
///
/// A pointer resting on it, or keyboard focus, shows the text as a
/// [WaxTooltip]; a press opens it in a small popover under the glyph
/// instead. A key's press takes focus into the popover, and Escape hands
/// it back to the glyph; a tap, which is how touch asks, leaves focus
/// where it was, so a field beside the glyph keeps its keyboard. The
/// popover closes on a tap anywhere else, on Escape, when focus moves
/// anywhere but onto the tip, when an enclosing scrollable moves, and when
/// a resize moves the glyph. The two are never up together. The glyph is a
/// button named by [message] itself, so it is read without a press.
class WaxInfoTip extends StatefulWidget {
  const WaxInfoTip({required this.message, this.semanticsId, super.key});

  /// The text the tip holds.
  final String message;
  final String? semanticsId;

  @override
  State<WaxInfoTip> createState() => _WaxInfoTipState();
}

class _WaxInfoTipState extends State<WaxInfoTip> with WidgetsBindingObserver {
  final OverlayPortalController _portal = OverlayPortalController();

  /// Ties the glyph and the popover into one tap region, so a tap on the
  /// glyph toggles rather than closing and reopening.
  final Object _region = Object();

  /// Holds focus while it is on the glyph or the popover, whose elements
  /// both sit under it: losing it is leaving the tip.
  final FocusNode _group = FocusNode(
    debugLabel: 'wax-info-tip-group',
    canRequestFocus: false,
    skipTraversal: true,
  );

  /// The popover's own, so Escape has somewhere to be heard after a key
  /// opened it. Never a tab stop: only that key puts focus here.
  final FocusNode _focus = FocusNode(
    debugLabel: 'wax-info-tip',
    skipTraversal: true,
  );

  final List<ScrollPosition> _scrolls = <ScrollPosition>[];

  /// Where focus was when a key opened the popover, to hand back on
  /// Escape. Null after a tap, which moved no focus.
  FocusNode? _previousFocus;

  bool _open = false;

  /// Whether a popover a tap opened, which holds no focus of its own, is
  /// watching the keyboard: Escape ahead of the focus tree, and focus
  /// moving on.
  bool _watching = false;

  /// What held focus when a tap opened the popover.
  FocusNode? _focusAtTap;

  /// Set when the popover closes and focus goes back to the glyph it was
  /// opened from, whose focus label would otherwise reappear for the very
  /// focus that asked for the popover. Only a close that has a glyph
  /// focus to return to sets it, so it never outlives that focus; cleared
  /// when focus leaves the tip.
  bool _hushed = false;

  ({Offset target, double halfHeight}) _anchor = (
    target: Offset.zero,
    halfHeight: 0,
  );

  void _toggle({bool byKey = false}) {
    if (_open) {
      _close();
      return;
    }
    final anchor = measureAnchor(context);
    if (anchor == null) return;
    _anchor = anchor;
    _previousFocus = byKey ? FocusManager.instance.primaryFocus : null;
    // The popover is placed once, so anything that moves its glyph ends
    // it rather than leaving it behind.
    var scrollable = Scrollable.maybeOf(context);
    while (scrollable != null) {
      scrollable.position.addListener(_close);
      _scrolls.add(scrollable.position);
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
    WidgetsBinding.instance.addObserver(this);
    _portal.show();
    setState(() {
      _open = true;
      _hushed = false;
    });
    if (!byKey) {
      _focusAtTap = FocusManager.instance.primaryFocus;
      FocusManager.instance
        ..addEarlyKeyEventHandler(_escapeFirst)
        ..addListener(_focusMoved);
      _watching = true;
      return;
    }
    // Not `autofocus`, which stands down while anything already holds
    // focus, and a keyboard press on the glyph is exactly that.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _open) _focus.requestFocus();
    });
  }

  void _stopWatching() {
    if (!_watching) return;
    _watching = false;
    _focusAtTap = null;
    FocusManager.instance
      ..removeEarlyKeyEventHandler(_escapeFirst)
      ..removeListener(_focusMoved);
  }

  /// Focus moving on from where it was when a tap opened the popover, to
  /// anywhere but the tip, ends it as a tap elsewhere does: so it never
  /// sits over the control focus went to, nor keeps the first Escape of a
  /// dialog opened from there. Focus dropped back to its own page is left
  /// to the taps, as a mouse press drops a field's focus before it lands.
  void _focusMoved() {
    final now = FocusManager.instance.primaryFocus;
    final held = _focusAtTap;
    if (now == held || now == held?.enclosingScope || now == _group) return;
    if (now != null && now.ancestors.contains(_group)) return;
    _close();
  }

  /// Escape for a popover a tap opened, ahead of whatever holds focus: it
  /// takes that one press and leaves every other key alone.
  KeyEventResult _escapeFirst(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !_open) {
      return KeyEventResult.ignored;
    }
    _close();
    return KeyEventResult.handled;
  }

  void _close({bool? hush}) {
    if (!_open || !mounted) return;
    // A scroll can end it mid-layout, where neither the portal nor
    // setState may be touched.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close(hush: hush));
      return;
    }
    for (final position in _scrolls) {
      position.removeListener(_close);
    }
    _scrolls.clear();
    WidgetsBinding.instance.removeObserver(this);
    _stopWatching();
    if (_portal.isShowing) _portal.hide();
    setState(() {
      _open = false;
      _hushed = hush ?? (_previousFocus?.ancestors.contains(_group) ?? false);
    });
  }

  /// A resize that leaves the glyph where it was, such as a keyboard
  /// hiding, keeps the popover; one that moves it ends it. Judged a frame
  /// on, once the page has laid out again.
  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_open) return;
      final now = measureAnchor(context);
      if (now == null || now.target != _anchor.target) _close();
    });
  }

  void _groupFocus(bool focused) {
    if (focused) return;
    _close();
    if (_hushed && mounted) setState(() => _hushed = false);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final tab = event.logicalKey == LogicalKeyboardKey.tab;
    if (!tab && event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    final back = _previousFocus;
    // Only a node still in the tree can take focus back; one that has
    // been disposed has no scope.
    final usable =
        back != null && back.canRequestFocus && back.enclosingScope != null;
    _close(hush: tab ? false : null);
    if (usable) {
      back.requestFocus();
      // Tab then steps on from the glyph rather than back onto it.
      if (tab) FocusManager.instance.applyFocusChangesIfNeeded();
    }
    return tab ? KeyEventResult.ignored : KeyEventResult.handled;
  }

  Widget _popover(BuildContext context) {
    final colors = WaxColors.of(context);
    return CustomSingleChildLayout(
      delegate: AnchorLayout(
        target: _anchor.target,
        verticalOffset: _anchor.halfHeight,
      ),
      child: TapRegion(
        groupId: _region,
        onTapOutside: (_) => _close(),
        child: Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: Semantics(
            container: true,
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.all(WaxSpace.s12),
              constraints: const BoxConstraints(maxWidth: 280),
              decoration: BoxDecoration(
                color: colors.surface3,
                borderRadius: WaxRadius.thumb,
                border: Border.all(color: colors.hairline),
                boxShadow: WaxElevation.overlay(Theme.of(context).brightness),
              ),
              child: Text(
                widget.message,
                style: WaxType.bodySmall.copyWith(color: colors.textPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _open = false;
    for (final position in _scrolls) {
      position.removeListener(_close);
    }
    WidgetsBinding.instance.removeObserver(this);
    _stopWatching();
    _focus.dispose();
    _group.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // One tear-off for the node and its ink: two would be equal but not
    // the same callback, which the semantics audit holds every control to.
    final toggle = _toggle;
    return Focus(
      focusNode: _group,
      onFocusChange: _groupFocus,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _popover,
        child: TapRegion(
          groupId: _region,
          // The one label, for hover, focus and a long press alike, so the
          // glyph has none of its own; it stands down whenever the popover
          // has the words on screen, or Escape has just taken them away.
          child: WaxTooltip(
            message: widget.message,
            excludeFromSemantics: true,
            showOnFocus: true,
            suppressed: _open
                ? WaxTooltipSuppression.all
                : _hushed
                ? WaxTooltipSuppression.focus
                : WaxTooltipSuppression.none,
            child: WaxTappable(
              label: widget.message,
              semanticsId: widget.semanticsId,
              borderRadius: WaxRadius.pill,
              onPressed: toggle,
              onKeyPress: () => _toggle(byKey: true),
              child: InkResponse(
                onTap: toggle,
                radius: WaxSpace.touchTarget / 2,
                child: SizedBox.square(
                  dimension: WaxSpace.touchTarget,
                  child: Center(
                    child: WaxIcon(
                      WaxIcons.info,
                      size: 16,
                      color: WaxColors.of(context).textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
