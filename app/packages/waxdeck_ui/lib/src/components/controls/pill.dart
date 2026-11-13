import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../tokens/colors.dart';
import '../../tokens/radii.dart';
import '../../tokens/spacing.dart';
import '../../tokens/typography.dart';
import '../indicators.dart';
import '../reserved_size.dart';
import 'button.dart';
import 'icon_button.dart';
import 'tappable.dart';

/// A labelled pill that can be on or off.
///
/// The player's effects and rates are all this shape: a word or a
/// number in a rounded outline that fills when it is on. It is a
/// control rather than a filter, so it is not [WaxFilterChip] - the
/// chips in a filter row are one choice among several and this is a
/// switch or a preset - and it carries text rather than a glyph, so it
/// is not [WaxIconButton].
///
/// Ink outside, InkWell in, once and here: the surfaces these sit on
/// are transparent Materials (the player draws its own backdrop), so a
/// splash under an opaquely decorated Container paints beneath it and
/// never appears. Every caller had to know that; now none of them do.
class WaxPill extends StatelessWidget {
  const WaxPill({
    required this.label,
    required this.onPressed,
    this.text,
    this.reserve,
    this.selected = false,
    this.mono = false,
    this.surface,
    this.semanticsId,
    this.busy = false,
    super.key,
  });

  /// The accessible name, which is the whole sentence a screen reader
  /// hears: "Trim silence (saved 2m 4s)", not "Trim silence".
  final String label;

  /// What is drawn, when it is shorter than the name. Defaults to
  /// [label].
  final String? text;

  /// The widest text a changing readout can show: the pill keeps room
  /// for it, so its width does not follow the value.
  final String? reserve;

  /// Null disables it.
  final VoidCallback? onPressed;

  /// Work this pill started is in flight, as [WaxButton.busy]: it takes
  /// no press, keeps the live colours and its focus, is announced as
  /// working, and draws a [WaxSpinner] in its word's room.
  final bool busy;

  final bool selected;

  /// Numbers set in the mono face: a rate that changes under a thumb
  /// should not move the pill's width with it.
  final bool mono;

  /// The pill's own unselected fill. Defaults to [WaxColors.surface2],
  /// which lifts off the canvas the player draws over; a caller on a
  /// raised surface passes the step above its own.
  final Color? surface;

  final String? semanticsId;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final drawn = text ?? label;
    // Busy keeps the live colours: working, not unavailable.
    final live = onPressed != null || busy;
    final foreground = selected
        ? colors.onAccentContainer
        : (live ? colors.textSecondary : colors.textDisabled);
    final style = (mono ? WaxType.monoData : WaxType.caption).copyWith(
      color: foreground,
    );
    final word = switch (reserve) {
      final room? => ReservedSize(
        reserve: Text(room, style: style),
        child: Text(drawn, style: style),
      ),
      null => Text(drawn, style: style),
    };
    return WaxTappable(
      semanticsId: semanticsId,
      label: label,
      selected: selected,
      busy: busy,
      borderRadius: WaxRadius.pill,
      onPressed: onPressed,
      child: Ink(
        decoration: BoxDecoration(
          color: selected
              ? colors.accentContainer
              : (surface ?? colors.surface2),
          borderRadius: WaxRadius.pill,
          border: Border.all(color: selected ? colors.accent : colors.hairline),
        ),
        child: InkWell(
          borderRadius: WaxRadius.pill,
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WaxSpace.s12,
              vertical: WaxSpace.s8,
            ),
            // The spinner at a glyph's size, held to the word's line so
            // a pill going busy keeps its height as well as its width.
            child: busy
                ? ReservedSize(
                    reserve: word,
                    child: WaxSpinner(
                      color: foreground,
                      size: math.min(
                        16,
                        MediaQuery.textScalerOf(
                              context,
                            ).scale(style.fontSize ?? 16) *
                            (style.height ?? 1),
                      ),
                    ),
                  )
                : word,
          ),
        ),
      ),
    );
  }
}
