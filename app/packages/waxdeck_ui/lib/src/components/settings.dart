import 'package:flutter/material.dart';

import '../icons/wax_icon.dart';
import '../theme/wax_layout.dart';
import '../tokens/colors.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'controls.dart';

/// A settings row: what the setting is, one line saying what it does, and
/// the control that changes it.
///
/// The help line is required rather than optional, which is the whole
/// design of the settings surface: every leaf setting carries one
/// sentence of inline help, so nobody has to guess what "Prepare the next
/// track" means from four words and a switch.
///
/// The row is not itself tappable. Its control is the control, and a row
/// that also handled taps would give a switch two ways to be flipped and
/// a screen reader two nodes claiming the same job.
class WaxSettingRow extends StatelessWidget {
  const WaxSettingRow({
    required this.title,
    required this.help,
    required this.control,
    this.glyph,
    super.key,
  });

  final String title;

  /// The one line of inline help. Sentence case, no full stop, says what
  /// changing it does rather than restating the title.
  final String help;

  /// The switch, picker, or button that changes it.
  final Widget control;

  final WaxGlyph? glyph;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final layout = WaxLayout.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: WaxSpace.s4,
        vertical: layout.density.vertical(WaxSpace.s12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (glyph != null) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(top: WaxSpace.s4),
              child: WaxIcon(glyph!, size: 20, color: colors.textSecondary),
            ),
            const SizedBox(width: WaxSpace.s12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: WaxType.body.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: WaxSpace.s4),
                Text(
                  help,
                  style: WaxType.bodySmall.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: WaxSpace.s16),
          // Centred against the title line rather than against the whole
          // row, so a control does not drift downward as the help line
          // wraps at large text scales.
          Padding(
            padding: const EdgeInsets.only(top: WaxSpace.s4),
            child: control,
          ),
        ],
      ),
    );
  }
}

/// The house switch.
///
/// Material's [Switch] underneath, painted by the theme, with the three
/// things every WaxDeck control needs bolted on the way the rest of the
/// design system does them: one semantics node carrying the setting's
/// name, a handle the suite can steer by, and the focus ring.
///
/// It announces as a switch rather than as a button, because a switch's
/// state is the whole point and `toggled` is what a screen reader reads
/// out. That is why this does not simply wrap [WaxTappable], which
/// announces buttons.
class WaxSwitch extends StatefulWidget {
  const WaxSwitch({
    required this.value,
    required this.onChanged,
    required this.label,
    this.semanticsId,
    super.key,
  });

  final bool value;

  /// Null disables the control, reported as well as drawn.
  final ValueChanged<bool>? onChanged;

  /// The accessible name: the setting, not the state. "Prepare the next
  /// track on wifi only", never "On".
  final String label;

  final String? semanticsId;

  @override
  State<WaxSwitch> createState() => _WaxSwitchState();
}

class _WaxSwitchState extends State<WaxSwitch> {
  bool _focused = false;
  final FocusNode _focus = FocusNode(debugLabel: 'wax-switch');

  /// The Material switch's own node, held rather than built inline: a
  /// node minted in `build` is a new one every frame and none of them is
  /// ever disposed.
  final FocusNode _inner = FocusNode(
    debugLabel: 'wax-switch-inner',
    canRequestFocus: false,
    skipTraversal: true,
  );

  @override
  void dispose() {
    _focus.dispose();
    _inner.dispose();
    super.dispose();
  }

  void _toggle() => widget.onChanged?.call(!widget.value);

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final enabled = widget.onChanged != null;
    return Semantics(
      identifier: widget.semanticsId,
      toggled: widget.value,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: enabled ? _toggle : null,
      focusable: enabled,
      focused: _focused,
      // See WaxTappable: a focus action makes a node focusable whatever
      // the flag says, so a disabled switch would still be a tab stop.
      onFocus: enabled ? _focus.requestFocus : null,
      child: FocusableActionDetector(
        enabled: enabled,
        focusNode: _focus,
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _toggle();
              return null;
            },
          ),
        },
        child: WaxFocusRing(
          focused: _focused,
          borderRadius: WaxRadius.pill,
          surface: colors.canvas,
          child: Switch(
            value: widget.value,
            onChanged: widget.onChanged,
            // The node above speaks for this control; the switch's own
            // would put a second stop in the tab order for it.
            focusNode: _inner,
          ),
        ),
      ),
    );
  }
}

/// A value chosen from a short list, drawn as its current value.
///
/// Distinct from [WaxMenuButton], which hides behind an icon and is for
/// verbs. A setting's control has to say what the setting currently is
/// without being opened, because that is what somebody scrolling a
/// settings section is reading.
class WaxChoice<T> extends StatelessWidget {
  const WaxChoice({
    required this.value,
    required this.options,
    required this.labelFor,
    required this.onChanged,
    required this.label,
    this.semanticsId,
    super.key,
  });

  final T value;
  final List<T> options;

  /// How each option reads, both on the closed control and in the menu.
  final String Function(T value) labelFor;

  /// Null disables the control, reported as well as drawn - for a
  /// setting whose value has not loaded yet. A live-looking control that
  /// silently drops the choice is the worse answer.
  final ValueChanged<T>? onChanged;

  /// The accessible name of the setting. The current value is announced
  /// after it, so a screen reader hears the pair rather than a bare "30
  /// seconds" with nothing to attach it to.
  final String label;

  final String? semanticsId;

  Future<void> _open(BuildContext context) async {
    final colors = WaxColors.of(context);
    final trigger = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final origin = trigger.localToGlobal(Offset.zero, ancestor: overlay);
    final chosen = await showMenu<T>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy + trigger.size.height,
        overlay.size.width - origin.dx - trigger.size.width,
        overlay.size.height - origin.dy,
      ),
      items: <PopupMenuEntry<T>>[
        for (final option in options)
          PopupMenuItem<T>(
            value: option,
            child: Semantics(
              selected: option == value,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      labelFor(option),
                      style: WaxType.body.copyWith(color: colors.textPrimary),
                    ),
                  ),
                  if (option == value)
                    WaxIcon(WaxIcons.check, size: 16, color: colors.accent),
                ],
              ),
            ),
          ),
      ],
    );
    if (chosen != null) onChanged?.call(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final enabled = onChanged != null && options.isNotEmpty;
    return Builder(
      // Its own context, so the menu opens against this control rather
      // than against whatever laid the section out.
      builder: (context) => WaxTappable(
        label: '$label, ${labelFor(value)}',
        semanticsId: semanticsId,
        borderRadius: WaxRadius.thumb,
        onPressed: enabled ? () => _open(context) : null,
        // The pointer handler is the child's, per WaxTappable's contract:
        // it contributes the semantics, the focus flag, and the ring, and
        // adds no gesture, so a control that leaves this out is focusable
        // and keyboard-operable while ignoring taps.
        child: Material(
          color: colors.surface2,
          borderRadius: WaxRadius.thumb,
          child: InkWell(
            onTap: enabled ? () => _open(context) : null,
            borderRadius: WaxRadius.thumb,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WaxSpace.s12,
                vertical: WaxSpace.s8,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // Flexible so a narrow column (a table cell, a
                  // cramped settings row) makes the value ellipsize
                  // rather than overflowing its box. The chevron beside
                  // it is what says the control is a control, so it
                  // keeps its width and the text yields.
                  Flexible(
                    child: Text(
                      labelFor(value),
                      style: WaxType.body.copyWith(
                        color: enabled
                            ? colors.textPrimary
                            : colors.textDisabled,
                      ),
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                  const SizedBox(width: WaxSpace.s4),
                  WaxIcon(
                    WaxIcons.collapse,
                    size: 16,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
