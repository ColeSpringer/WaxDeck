import 'package:material_ui/material_ui.dart';

import '../../icons/wax_icon.dart';
import '../../l10n/wax_l10n.dart';
import '../../tokens/colors.dart';
import '../../tokens/radii.dart';
import '../../tokens/spacing.dart';
import '../../tokens/typography.dart';
import '../indicators.dart';
import '../reserved_size.dart';
import 'tappable.dart';

/// How much weight a button carries.
enum WaxButtonKind {
  /// One per screen: the thing you came to do.
  filled,

  /// Secondary actions that still deserve a surface.
  tonal,

  /// Everything else.
  text,

  /// A link in a column of text.
  ///
  /// [text]'s colour and none of its box: no horizontal padding, so the
  /// label's leading edge is the prose's leading edge rather than a
  /// pill's, twenty pixels to the side of it. For anything that has to
  /// line up with the paragraph it belongs to - a link a note refers
  /// to, the control that unfolds the rest of one. The vertical touch
  /// target stays, because a link in a column of text is still
  /// something a thumb has to hit. A label that wraps takes the ambient
  /// [DefaultTextStyle]'s alignment, so it lines up as the column does.
  inline,

  /// Deletes and revokes. Never the default focus target.
  destructive,
}

/// The padding a pill-shaped button keeps around its label. The
/// vertical share sits inside the touch target, so it only shows once a
/// label wraps or large text outgrows it.
const _pillPadding = EdgeInsets.symmetric(
  horizontal: WaxSpace.s20,
  vertical: WaxSpace.s8,
);

/// The button.
///
/// Labels are sentence case and name their verb ("Save changes", "Add to
/// queue"), never "Submit" or a bare "OK". A label too long for the room
/// wraps, so large text grows the pill downwards rather than clipping it.
class WaxButton extends StatelessWidget {
  const WaxButton({
    required this.label,
    required this.onPressed,
    this.kind = WaxButtonKind.filled,
    this.icon,
    this.spokenLabel,
    this.semanticsId,
    this.expand = false,
    this.busy = false,
    this.progress,
    this.status = false,
    this.detail,
    this.maxLines,
    super.key,
  }) : assert(
         progress == null ? !(busy && status) : !busy && !status,
         'busy, progress and status are one state at a time',
       ),
       assert(
         maxLines == null || kind == WaxButtonKind.inline,
         'only a link takes a line cap: a pill label wraps',
       );

  final String label;

  /// What a screen reader hears, where the drawn label is short for the
  /// room it has: "New app password" on a button that reads "New". A
  /// button reached through the rotor arrives with no heading above it
  /// to lend it a subject, so the name has to carry one.
  final String? spokenLabel;

  /// Null disables the button. Disabled is never signalled by colour
  /// alone: the control also reports itself disabled to assistive tech.
  final VoidCallback? onPressed;

  final WaxButtonKind kind;
  final WaxGlyph? icon;
  final String? semanticsId;

  /// Fills the available width, for sheets and empty states.
  final bool expand;

  /// Work this button started is in flight: it takes no press and draws
  /// a [WaxSpinner] for its glyph, or over its label, at the same size.
  final bool busy;

  /// How far that work has got, from 0 to 1, when it can say: the
  /// leading share of the pill is drawn in the filled form, label
  /// included, and the share is its spoken value. In every other way
  /// it is [busy]: live colours, and no press whatever [onPressed] says.
  /// A value that is not finite (NaN from 0 of 0, or infinity) says
  /// nothing of how far, so it draws the busy pill, as the page's
  /// progress bar draws one of unknown length.
  final double? progress;

  /// A state to read, not an action to take: the tonal box in secondary
  /// ink, whatever [kind] and [onPressed] say, and no button to a screen
  /// reader.
  final bool status;

  /// What the label leaves out, such as why the action failed: a
  /// tooltip on hover, keyboard focus or long press, and read after the
  /// name.
  final String? detail;

  /// The most lines an [WaxButtonKind.inline] link draws before it ends
  /// in an ellipsis, for a link that must not outgrow the lines around
  /// it. The touch target stays, and the whole label is still spoken.
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final share = switch (progress) {
      final value? when value.isFinite => value.clamp(0.0, 1.0),
      _ => null,
    };
    final working = busy || (progress != null && share == null);
    // Busy and progress keep the live colours: working, not unavailable.
    final live = onPressed != null || working || share != null;

    // Every per-kind answer in one place. A kind that settled three of
    // them here and the rest in ternaries further down is how `inline`
    // came to need a second dispatch of its own, and how the next change
    // to a ground would quietly skip it.
    //
    // `disabled` is the ground a disabled button takes: the filled kinds
    // fall back to the disabled surface, and a pill radius on a box with
    // no padding is a lozenge as wide as the word, which is not what a
    // link's press looks like. `fill` and `onFill` draw the share of a
    // progress pill that is done. Every pill kind has a border, clear
    // where none shows, because a border is laid out inside the padding
    // and one kind with it would stand taller than its neighbours.
    final (
      Color background,
      Color disabled,
      Color foreground,
      Color? border,
      BorderRadius radius,
      EdgeInsetsGeometry padding,
      Color fill,
      Color onFill,
    ) = switch (status ? WaxButtonKind.tonal : kind) {
      WaxButtonKind.filled => (
        colors.accent,
        colors.surface2,
        colors.onAccent,
        Colors.transparent,
        WaxRadius.pill,
        _pillPadding,
        colors.accent,
        colors.onAccent,
      ),
      WaxButtonKind.tonal => (
        colors.surface2,
        colors.surface2,
        colors.textPrimary,
        colors.hairline,
        WaxRadius.pill,
        _pillPadding,
        colors.accent,
        colors.onAccent,
      ),
      WaxButtonKind.text => (
        Colors.transparent,
        colors.surface2,
        colors.accent,
        Colors.transparent,
        WaxRadius.pill,
        _pillPadding,
        colors.accent,
        colors.onAccent,
      ),
      WaxButtonKind.destructive => (
        Colors.transparent,
        colors.surface2,
        colors.error,
        Colors.transparent,
        WaxRadius.pill,
        _pillPadding,
        colors.error,
        colors.onError,
      ),
      // A disabled link keeps prose's ground under it, and no border, so
      // its leading edge stays the prose's.
      WaxButtonKind.inline => (
        Colors.transparent,
        Colors.transparent,
        colors.accent,
        null,
        WaxRadius.chip,
        const EdgeInsets.symmetric(vertical: WaxSpace.s8),
        colors.accent,
        colors.onAccent,
      ),
    };

    // A link is part of the prose around it, so a wrapped one lines up
    // as that text does. Read here: the Material below resets it.
    final align = kind == WaxButtonKind.inline
        ? DefaultTextStyle.of(context).textAlign
        : null;

    Widget face(Color ink, {Color? ground}) {
      final text = Text(
        label,
        textAlign: align,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        // A wrapped label is as wide as its longest line, so the row
        // can centre it.
        textWidthBasis: TextWidthBasis.longestLine,
        style: WaxType.label.copyWith(color: ink),
      );
      return Container(
        constraints: const BoxConstraints(minHeight: WaxSpace.touchTarget),
        padding: padding,
        decoration: BoxDecoration(
          color: ground,
          borderRadius: radius,
          border: border == null ? null : Border.all(color: border),
        ),
        // Both factors: a loose but bounded host (a centred page, a row in
        // a fixed-height bar) would otherwise stretch the pill to fill it.
        child: Center(
          widthFactor: expand ? null : 1,
          heightFactor: 1,
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                if (working)
                  SizedBox.square(
                    dimension: 18,
                    child: Center(child: WaxSpinner(color: ink)),
                  )
                else
                  WaxIcon(icon!, size: 18, color: ink),
                const SizedBox(width: WaxSpace.s8),
              ],
              Flexible(
                child: working && icon == null
                    ? ReservedSize(
                        reserve: text,
                        child: WaxSpinner(color: ink),
                      )
                    : text,
              ),
            ],
          ),
        ),
      );
    }

    // One labelled thing, not a button. Still a WaxTappable, so a pill
    // that becomes a status under the keyboard keeps its focus.
    if (status) {
      return WaxTappable(
        label: spokenLabel ?? label,
        onPressed: null,
        inert: true,
        hint: detail,
        tooltip: detail,
        tooltipOnLongPress: true,
        semanticsId: semanticsId,
        borderRadius: radius,
        child: face(colors.textSecondary, ground: background),
      );
    }

    var ground = live ? background : disabled;
    var ink = live ? foreground : colors.textDisabled;
    Widget body = face(ink);
    if (share != null) {
      // A filled button's ground is already the fill, so its track
      // steps back to the container.
      if (kind == WaxButtonKind.filled) {
        ground = colors.accentContainer;
        ink = colors.onAccentContainer;
      }
      // The label is drawn twice, each in the ink of the ground under it.
      // Passthrough hands both faces the pill's own constraints, so the
      // two lay out as one.
      body = Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          face(ink),
          ClipRect(
            clipper: _LeadingShare(share, Directionality.of(context)),
            child: face(onFill, ground: fill),
          ),
        ],
      );
    }

    // The semantics, focus, ring and busy state are WaxTappable's, as on
    // every other control; the ink here only draws the press.
    return WaxTappable(
      label: spokenLabel ?? label,
      onPressed: onPressed,
      busy: working || share != null,
      value: share == null ? null : context.waxL10n.spellPercent(share),
      hint: detail,
      tooltip: detail,
      tooltipOnLongPress: true,
      semanticsId: semanticsId,
      borderRadius: radius,
      child: Material(
        color: ground,
        borderRadius: radius,
        child: InkWell(onTap: onPressed, borderRadius: radius, child: body),
      ),
    );
  }
}

/// The leading [share] of a box, in reading order.
class _LeadingShare extends CustomClipper<Rect> {
  const _LeadingShare(this.share, this.direction);

  final double share;
  final TextDirection direction;

  @override
  Rect getClip(Size size) {
    final width = size.width * share;
    return Rect.fromLTWH(
      direction == TextDirection.ltr ? 0 : size.width - width,
      0,
      width,
      size.height,
    );
  }

  @override
  bool shouldReclip(_LeadingShare old) =>
      old.share != share || old.direction != direction;
}
