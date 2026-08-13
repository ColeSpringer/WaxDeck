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
/// Help is required, not optional: every leaf setting carries a sentence
/// so nobody guesses what four words and a switch mean. The row is not
/// itself tappable, or a switch would have two ways to be flipped and a
/// screen reader two nodes claiming the same job.
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

/// One choice in a [WaxRadioGroup].
@immutable
class WaxRadioOption<T> {
  const WaxRadioOption({
    required this.value,
    required this.label,
    this.help,
    this.semanticsId,
  });

  final T value;

  final String label;

  /// The one line under the label, where a choice has a consequence
  /// worth spelling out - "Restorable from the trash screen" against
  /// "Gone for good".
  final String? help;

  final String? semanticsId;
}

/// A short list of choices with every one of them, and its consequence,
/// on screen at once.
///
/// The counterpart to [WaxChoice], not a duplicate: the line is whether
/// the options have to be read to be chosen between. Speeds can wait
/// behind a tap; "trash or permanent" hidden behind one is how somebody
/// deletes a library by mistake.
///
/// One semantics node per option, announcing with
/// `inMutuallyExclusiveGroup` and `checked` so a screen reader knows
/// choosing one un-chooses the rest.
class WaxRadioGroup<T> extends StatelessWidget {
  const WaxRadioGroup({
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
  });

  final T value;
  final List<WaxRadioOption<T>> options;

  /// Null disables every option, reported as well as drawn.
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      for (final option in options)
        _WaxRadioRow<T>(
          option: option,
          selected: option.value == value,
          onSelect: onChanged == null ? null : () => onChanged!(option.value),
        ),
    ],
  );
}

class _WaxRadioRow<T> extends StatefulWidget {
  const _WaxRadioRow({
    required this.option,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final WaxRadioOption<T> option;
  final bool selected;
  final VoidCallback? onSelect;

  @override
  State<_WaxRadioRow<T>> createState() => _WaxRadioRowState<T>();
}

class _WaxRadioRowState<T> extends State<_WaxRadioRow<T>> {
  bool _focused = false;
  final FocusNode _focus = FocusNode(debugLabel: 'wax-radio');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final layout = WaxLayout.of(context);
    final option = widget.option;
    final enabled = widget.onSelect != null;
    final mark = !enabled
        ? colors.textDisabled
        : (widget.selected ? colors.accent : colors.outline);

    return Semantics(
      identifier: option.semanticsId,
      // The pair that makes a radio a radio: in a group, and checked or
      // not. A button that happened to look round would announce as a
      // button and say nothing about what choosing it un-chooses.
      inMutuallyExclusiveGroup: true,
      checked: widget.selected,
      enabled: enabled,
      label: <String?>[option.label, option.help].nonNulls.join(', '),
      excludeSemantics: true,
      onTap: widget.onSelect,
      focusable: enabled,
      focused: _focused,
      // See WaxTappable: a focus action makes a node focusable whatever
      // the flag says, so a disabled option would still be a tab stop.
      onFocus: enabled ? _focus.requestFocus : null,
      child: FocusableActionDetector(
        enabled: enabled,
        focusNode: _focus,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onSelect?.call();
              return null;
            },
          ),
        },
        child: WaxFocusRing(
          focused: _focused,
          surface: colors.canvas,
          child: GestureDetector(
            onTap: widget.onSelect,
            behavior: HitTestBehavior.opaque,
            child: ConstrainedBox(
              // The whole row is the target, not the mark on the end of
              // it: a 20-pixel circle is not something to aim at.
              constraints: BoxConstraints(minHeight: layout.rowHeightDense),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: WaxSpace.s12),
                    child: _Mark(selected: widget.selected, color: mark),
                  ),
                  const SizedBox(width: WaxSpace.s12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: WaxSpace.s8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            option.label,
                            style: WaxType.body.copyWith(
                              color: enabled
                                  ? colors.textPrimary
                                  : colors.textDisabled,
                            ),
                          ),
                          if (option.help != null)
                            Text(
                              option.help!,
                              style: WaxType.bodySmall.copyWith(
                                color: enabled
                                    ? colors.textTertiary
                                    : colors.textDisabled,
                              ),
                            ),
                        ],
                      ),
                    ),
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

/// The ring, and the dot inside it when this is the one chosen.
class _Mark extends StatelessWidget {
  const _Mark({required this.selected, required this.color});

  final bool selected;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 20,
    height: 20,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: color, width: 2),
    ),
    child: selected
        ? Center(
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          )
        : null,
  );
}

/// The house switch: Material's [Switch] painted by the theme, with one
/// semantics node carrying the setting's name, a handle the suite can
/// steer by, and the focus ring.
///
/// Announces as a switch, not a button, because `toggled` is what a
/// screen reader reads out - which is why it does not wrap
/// [WaxTappable].
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
    this.optionSemanticsIdFor,
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

  /// The identifier each option row publishes. Keyed on the value, not
  /// the label: a label is copy, and it translates.
  final String Function(T value)? optionSemanticsIdFor;

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
              identifier: optionSemanticsIdFor?.call(option),
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
                  // Flexible so a narrow column ellipsizes the value
                  // rather than overflowing. The chevron keeps its width
                  // because it is what says this is a control.
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
