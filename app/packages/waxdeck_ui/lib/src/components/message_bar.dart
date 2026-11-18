import 'package:material_ui/material_ui.dart';

import '../icons/wax_icon.dart';
import '../l10n/wax_l10n.dart';
import '../tokens/colors.dart';
import '../tokens/radii.dart';
import '../tokens/typography.dart';
import 'controls.dart';

/// A short message along the bottom of a screen, with at most one action:
/// a floating snack bar, drawn by the design system so that where it
/// rests is the caller's to say.
///
/// The caller lays this box along the bottom of the area a message rests
/// in, and the bar floats [inset] inside it. To a screen reader the bar
/// is one node, the bar's own rect: a live region, announced as it
/// appears, which a dismiss takes away, with the action a button inside
/// it. A press anywhere in the box but on the bar reaches what is under
/// it.
class WaxMessageBar extends StatefulWidget {
  const WaxMessageBar({
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionSemanticsId,
    this.onClose,
    this.onDismiss,
    this.animation,
    super.key,
  }) : assert(
         (actionLabel == null) == (onAction == null),
         'an action is a label and what it does',
       );

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? actionSemanticsId;

  /// Draws a close control at the bar's end, for a bar that waits for its
  /// action rather than leaving on its own.
  final VoidCallback? onClose;

  /// A swipe down, or a screen reader's dismiss. Null, the bar stays put.
  final VoidCallback? onDismiss;

  /// The entrance, from 0 to 1, and the exit, back to 0. Null draws the
  /// bar at rest.
  final Animation<double>? animation;

  /// The room the bar keeps inside its box: Material's floating inset.
  static const EdgeInsets inset = EdgeInsets.fromLTRB(15, 5, 15, 10);

  @override
  State<WaxMessageBar> createState() => _WaxMessageBarState();
}

class _WaxMessageBarState extends State<WaxMessageBar> {
  final Key _dismissible = UniqueKey();

  /// Material 3's floating entrance: the bar rises into view from its foot
  /// as it fades in, and leaves by fading where it stands.
  CurvedAnimation? _fade;
  CurvedAnimation? _rise;

  @override
  void initState() {
    super.initState();
    _curve();
  }

  @override
  void didUpdateWidget(WaxMessageBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      _uncurve();
      _curve();
    }
  }

  @override
  void dispose() {
    _uncurve();
    super.dispose();
  }

  void _curve() {
    final animation = widget.animation;
    if (animation == null) return;
    _fade = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.4, 0.6, curve: Curves.easeInCirc),
    );
    _rise = CurvedAnimation(
      parent: animation,
      curve: Curves.easeInOutQuart,
      reverseCurve: const Threshold(0),
    );
  }

  void _uncurve() {
    _fade?.dispose();
    _rise?.dispose();
    _fade = null;
    _rise = null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final onAction = widget.onAction;
    final onClose = widget.onClose;
    final onDismiss = widget.onDismiss;

    // Material's floating content: 16 to the text, 14 above and below
    // it, nothing after it where a control ends the row.
    Widget bar = Padding(
      padding: EdgeInsetsDirectional.only(
        start: _gutter,
        end: onClose == null ? _gutter : 0,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: DefaultTextStyle(
                style: WaxType.body.copyWith(color: colors.textPrimary),
                child: Row(
                  children: <Widget>[
                    Expanded(child: Text(widget.message)),
                    if (onAction != null)
                      _apart(
                        WaxButton(
                          label: widget.actionLabel!,
                          kind: WaxButtonKind.text,
                          semanticsId: widget.actionSemanticsId,
                          onPressed: onAction,
                        ),
                        named: widget.actionSemanticsId != null,
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (onClose != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _gutter / 12),
              child: SizedBox.square(
                dimension: 48,
                child: Center(
                  child: _apart(
                    WaxIconButton(
                      glyph: WaxIcons.close,
                      label: context.waxL10n.messageClose,
                      size: 24,
                      color: colors.textSecondary,
                      onPressed: onClose,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    bar = Material(
      color: colors.surface3,
      elevation: 6,
      shape: const RoundedRectangleBorder(borderRadius: WaxRadius.card),
      clipBehavior: Clip.hardEdge,
      animationDuration: Duration.zero,
      child: bar,
    );
    // The node and the swipe are the bar's alone, inside the inset, so
    // neither reaches over what the inset leaves showing.
    bar = Semantics(
      container: true,
      liveRegion: true,
      onDismiss: onDismiss,
      child: Dismissible(
        key: _dismissible,
        direction: onDismiss == null
            ? DismissDirection.none
            : DismissDirection.down,
        resizeDuration: null,
        behavior: HitTestBehavior.deferToChild,
        onDismissed: (_) => onDismiss?.call(),
        child: bar,
      ),
    );
    bar = Padding(padding: WaxMessageBar.inset, child: bar);

    final fade = _fade;
    final rise = _rise;
    if (fade != null && rise != null) {
      // Read aloud, it is there at once and gone at once. Held whole
      // rather than unwrapped: a reader starting or stopping turns that on
      // or off, and must find the nodes it listed still there.
      final whole = MediaQuery.accessibleNavigationOf(context);
      bar = FadeTransition(
        opacity: whole ? kAlwaysCompleteAnimation : fade,
        child: ValueListenableBuilder<double>(
          valueListenable: whole ? kAlwaysCompleteAnimation : rise,
          builder: (context, value, child) => Align(
            alignment: Alignment.bottomLeft,
            heightFactor: value,
            child: child,
          ),
          child: bar,
        ),
      );
    }
    return ClipRect(child: bar);
  }

  static const double _gutter = 16;

  /// [control] as a node of its own inside the bar's: merged into it, its
  /// name and its tap would be the whole bar's. One with an identifier is
  /// a node of its own already.
  static Widget _apart(Widget control, {bool named = false}) =>
      named ? control : Semantics(container: true, child: control);
}
