import 'package:flutter/material.dart';

import '../icons/wax_icon.dart';
import '../tokens/colors.dart';
import '../tokens/motion.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'controls.dart';

/// A single-line text input.
///
/// It carries its own leading glyph and clear control rather than leaving
/// them to the caller, so every field in the app clears the same way and
/// announces the same thing. The label is the accessible name; a hint is
/// a placeholder and never stands in for one.
class WaxTextField extends StatefulWidget {
  const WaxTextField({
    required this.label,
    this.controller,
    this.focusNode,
    this.hint,
    this.glyph,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.textInputAction,
    this.obscureText = false,
    this.maxLines = 1,
    this.errorText,
    this.semanticsId,
    this.clearSemanticsId,
    super.key,
  }) : assert(maxLines >= 1, 'a field has at least one line');

  /// The accessible name. Fields with a visible label pass the same
  /// string; fields whose meaning is carried by their placement (a search
  /// box in a sidebar header) pass what a screen reader should hear.
  final String label;

  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// Placeholder text. Disappears on the first keystroke, so it never
  /// carries meaning the label does not also carry.
  final String? hint;

  final WaxGlyph? glyph;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final TextInputAction? textInputAction;

  /// Hides what is typed, for passwords and tokens. Also suppresses the
  /// clear button: a secret field's contents are not something to glance
  /// at and decide about, and the button would be a control whose only
  /// effect is invisible.
  final bool obscureText;

  /// How tall the field grows before it scrolls. Above one it takes the
  /// card radius and drops its clear button, which a paragraph should
  /// not have.
  final int maxLines;

  /// What went wrong with this value, drawn under the field in the error
  /// colour. Beneath rather than as a toast, because an error about a
  /// field belongs where the field is.
  final String? errorText;

  final String? semanticsId;

  /// The clear control's own handle. It is a separate control from the
  /// field, so it gets a separate identifier.
  final String? clearSemanticsId;

  @override
  State<WaxTextField> createState() => _WaxTextFieldState();
}

class _WaxTextFieldState extends State<WaxTextField> {
  TextEditingController? _owned;
  FocusNode? _ownedFocus;
  bool _focused = false;

  TextEditingController get _controller =>
      widget.controller ?? (_owned ??= TextEditingController());
  FocusNode get _focus =>
      widget.focusNode ?? (_ownedFocus ??= FocusNode(debugLabel: 'wax-field'));

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(WaxTextField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode?.removeListener(_onFocusChanged);
      _ownedFocus?.removeListener(_onFocusChanged);
      _focus.addListener(_onFocusChanged);
    }
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() => _focused = _focus.hasFocus);
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_onFocusChanged);
    _ownedFocus?.removeListener(_onFocusChanged);
    _ownedFocus?.dispose();
    _owned?.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final motion = WaxMotion.of(context);

    final error = widget.errorText;
    final multiline = widget.maxLines > 1;
    final radius = multiline ? WaxRadius.card : WaxRadius.pill;
    final field = WaxFocusRing(
      focused: _focused,
      borderRadius: radius,
      surface: colors.canvas,
      child: AnimatedContainer(
        duration: motion.quick,
        curve: WaxMotion.emphasized,
        constraints: const BoxConstraints(minHeight: WaxSpace.touchTarget),
        padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s12),
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: radius,
          border: Border.all(
            color: error != null
                ? colors.error
                : (_focused ? colors.accent : colors.hairline),
          ),
        ),
        child: Row(
          crossAxisAlignment: multiline
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: <Widget>[
            if (widget.glyph != null) ...<Widget>[
              WaxIcon(widget.glyph!, size: 18, color: colors.textTertiary),
              const SizedBox(width: WaxSpace.s8),
            ],
            Expanded(
              // Annotating rather than containing, and around the field
              // alone: the identifier and the name land on the input's
              // own node, so there is one node per control - the role,
              // the name, and the e2e handle on the thing that is
              // actually the text box, with the clear button beside it
              // keeping a node of its own.
              child: Semantics(
                identifier: widget.semanticsId,
                label: widget.label,
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: widget.autofocus,
                  textInputAction: widget.textInputAction,
                  obscureText: widget.obscureText,
                  maxLines: widget.maxLines,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  style: WaxType.body.copyWith(color: colors.textPrimary),
                  cursorColor: colors.accent,
                  // This component draws the field's own surface, border,
                  // and focus ring, so Material's are cleared rather than
                  // left to show through: the theme sets an outline and a
                  // fill for the bare TextField, and both would render as
                  // a second box inside this one.
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: WaxSpace.s12,
                    ),
                    hintText: widget.hint,
                    hintStyle: WaxType.body.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
            // Built off the controller so it appears with the first
            // character and leaves with the last, without the field
            // rebuilding its ancestors on every keystroke.
            if (!widget.obscureText && !multiline)
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) => value.text.isEmpty
                    ? const SizedBox.shrink()
                    : WaxIconButton(
                        glyph: WaxIcons.close,
                        label: 'Clear ${widget.label.toLowerCase()}',
                        size: 16,
                        semanticsId: widget.clearSemanticsId,
                        onPressed: _clear,
                      ),
              ),
          ],
        ),
      ),
    );
    if (error == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        field,
        Padding(
          padding: const EdgeInsets.only(top: WaxSpace.s4, left: WaxSpace.s12),
          child: Text(
            error,
            style: WaxType.bodySmall.copyWith(color: colors.error),
          ),
        ),
      ],
    );
  }
}

/// The search input.
///
/// Two shapes, because search has two jobs. Given [onChanged] it is a
/// real field the caller drives; given [onTap] instead it is a launcher
/// a field-shaped control that opens the search screen, which is what
/// the sidebar header holds. A launcher never carries text of its own, so
/// there is no second field to keep in step with the one that owns the
/// query.
class SearchField extends StatelessWidget {
  const SearchField({
    this.controller,
    this.focusNode,
    this.hint = 'Search',
    this.label = 'Search',
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.autofocus = false,
    this.semanticsId,
    this.clearSemanticsId,
    super.key,
  }) : assert(
         onTap == null || (onChanged == null && controller == null),
         'a launcher holds no text: give SearchField onTap or a controller, '
         'not both',
       );

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hint;
  final String label;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Makes this a launcher: tapping it opens the screen that owns search.
  final VoidCallback? onTap;

  final bool autofocus;
  final String? semanticsId;
  final String? clearSemanticsId;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) {
      return WaxTextField(
        label: label,
        hint: hint,
        glyph: WaxIcons.search,
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        semanticsId: semanticsId,
        clearSemanticsId: clearSemanticsId,
      );
    }

    final colors = WaxColors.of(context);
    return WaxTappable(
      label: label,
      onPressed: onTap,
      semanticsId: semanticsId,
      borderRadius: WaxRadius.pill,
      child: Material(
        color: colors.surface2,
        borderRadius: WaxRadius.pill,
        child: InkWell(
          onTap: onTap,
          borderRadius: WaxRadius.pill,
          child: Container(
            constraints: const BoxConstraints(minHeight: WaxSpace.touchTarget),
            padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s12),
            decoration: BoxDecoration(
              borderRadius: WaxRadius.pill,
              border: Border.all(color: colors.hairline),
            ),
            child: Row(
              children: <Widget>[
                WaxIcon(WaxIcons.search, size: 18, color: colors.textTertiary),
                const SizedBox(width: WaxSpace.s8),
                Expanded(
                  child: Text(
                    hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WaxType.body.copyWith(color: colors.textTertiary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One option in a [WaxSegmented].
@immutable
class WaxSegment {
  const WaxSegment({required this.name, required this.label, this.semanticsId});

  /// The value the control reports when this segment is chosen. Stable
  /// across label changes and translations.
  final String name;

  final String label;
  final String? semanticsId;
}

/// A joined, equal-width control for switching between two or three
/// readings of the same thing.
///
/// Not a filter row and not a set of chips: the segments partition one
/// state, so they share a frame, divide the width evenly, and always
/// have exactly one of them chosen. [FilterChipRow] is what a choice
/// becomes when it outgrows this - a scrolling row of independent pills
/// that can also be none of the above.
class WaxSegmented extends StatelessWidget {
  const WaxSegmented({
    required this.segments,
    required this.selected,
    required this.onSelect,
    this.label,
    this.semanticsId,
    super.key,
  });

  final List<WaxSegment> segments;

  /// The chosen segment's [WaxSegment.name].
  final String selected;

  final ValueChanged<String> onSelect;

  /// What the control as a whole is for, spoken before the segment
  /// names. A segmented control reads as a row of nouns otherwise, and
  /// "Chapter" on its own says nothing about what it switches.
  final String? label;

  final String? semanticsId;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Semantics(
      identifier: semanticsId,
      container: true,
      label: label,
      // The frame names the group; the segments inside it are the
      // controls. Without this the labels fold into one node and
      // neither segment can be reached on its own.
      explicitChildNodes: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: WaxRadius.pill,
          border: Border.all(color: colors.hairline),
        ),
        // Equal widths are the component's promise, so they are made
        // here rather than hoped for: the intrinsic pass sizes the row
        // so every flexed segment gets the widest label's width. A
        // min-width floor alone let any label past the floor render
        // wider than its siblings, which is the lopsided pair the add
        // dialogs shipped with.
        child: IntrinsicWidth(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final segment in segments)
                Expanded(
                  child: _Segment(
                    segment: segment,
                    selected: segment.name == selected,
                    onTap: () => onSelect(segment.name),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.segment,
    required this.selected,
    required this.onTap,
  });

  final WaxSegment segment;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final motion = WaxMotion.of(context);
    return WaxTappable(
      label: segment.label,
      selected: selected,
      onPressed: onTap,
      semanticsId: segment.semanticsId,
      borderRadius: WaxRadius.pill,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: motion.quick,
          curve: WaxMotion.emphasized,
          constraints: const BoxConstraints(
            minHeight: WaxSpace.pointerTarget,
            minWidth: WaxSpace.s64,
          ),
          padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? colors.accentContainer : Colors.transparent,
            borderRadius: WaxRadius.pill,
          ),
          child: Text(
            segment.label,
            style: WaxType.label.copyWith(
              color: selected ? colors.onAccentContainer : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// One chip in a [FilterChipRow].
@immutable
class WaxFilterChip {
  const WaxFilterChip({
    required this.name,
    required this.label,
    this.glyph,
    this.semanticsId,
  });

  /// The value the row reports when this chip is chosen. Stable across
  /// label changes and translations.
  final String name;

  final String label;
  final WaxGlyph? glyph;
  final String? semanticsId;
}

/// A single-select row of filter chips: the segmented control for
/// choices that outgrow a segmented control.
///
/// It scrolls horizontally rather than wrapping, because a filter row
/// that reflows to two lines pushes the content it filters off the fold
/// on exactly the narrow screens that can least afford it.
class FilterChipRow extends StatelessWidget {
  const FilterChipRow({
    required this.chips,
    required this.selected,
    required this.onSelect,
    this.padding,
    this.semanticsId,
    super.key,
  });

  final List<WaxFilterChip> chips;

  /// The chosen chip's [WaxFilterChip.name].
  final String selected;

  final ValueChanged<String> onSelect;
  final EdgeInsets? padding;
  final String? semanticsId;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: semanticsId,
      container: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: Row(
          children: <Widget>[
            for (final chip in chips) ...<Widget>[
              _Chip(
                chip: chip,
                selected: chip.name == selected,
                onTap: () => onSelect(chip.name),
              ),
              const SizedBox(width: WaxSpace.s8),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatefulWidget {
  const _Chip({
    required this.chip,
    required this.selected,
    required this.onTap,
  });

  final WaxFilterChip chip;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final motion = WaxMotion.of(context);
    final foreground = widget.selected
        ? colors.onAccentContainer
        : colors.textSecondary;

    return WaxTappable(
      label: widget.chip.label,
      onPressed: widget.onTap,
      semanticsId: widget.chip.semanticsId,
      selected: widget.selected,
      borderRadius: WaxRadius.pill,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: motion.quick,
          curve: WaxMotion.emphasized,
          constraints: const BoxConstraints(minHeight: WaxSpace.pointerTarget),
          padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s16),
          decoration: BoxDecoration(
            color: widget.selected
                ? colors.accentContainer
                : Colors.transparent,
            borderRadius: WaxRadius.pill,
            border: Border.all(
              color: widget.selected ? colors.accent : colors.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (widget.chip.glyph != null) ...<Widget>[
                WaxIcon(
                  widget.chip.glyph!,
                  size: 14,
                  color: foreground,
                  active: widget.selected,
                ),
                const SizedBox(width: WaxSpace.s4),
              ],
              Text(
                widget.chip.label,
                style: WaxType.label.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
