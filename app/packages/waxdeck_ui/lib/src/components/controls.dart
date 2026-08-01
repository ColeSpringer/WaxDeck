import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../icons/wax_icon.dart';
import '../tokens/colors.dart';
import '../tokens/motion.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import '../theme/wax_layout.dart';
import 'view_data.dart';

/// The two-tone focus ring.
///
/// An inner ring in the underlying surface colour and an outer ring in
/// accent, so focus stays visible on every background including an
/// active amber element. A single amber ring disappears exactly where it
/// matters most (a focused active tab), which is a WCAG 2.4.11 failure.
class WaxFocusRing extends StatelessWidget {
  const WaxFocusRing({
    required this.focused,
    required this.child,
    this.borderRadius = WaxRadius.thumb,
    this.surface,
    super.key,
  });

  final bool focused;
  final Widget child;
  final BorderRadius borderRadius;

  /// The colour immediately under the ring. Defaults to the card surface.
  final Color? surface;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final layout = WaxLayout.of(context);
    final inner = surface ?? colors.surface1;
    // The CustomPaint is always here and only its painter comes and goes.
    // Returning the bare child while unfocused would change the shape of
    // the element tree the moment focus arrived, and a child whose parent
    // changes type is rebuilt from scratch - which for a text field means
    // losing its state and its input connection on the way in.
    return CustomPaint(
      foregroundPainter: focused
          ? _FocusRingPainter(
              radius: borderRadius,
              inner: inner,
              outer: colors.accent,
              innerWidth: layout.focusRingInnerWidth,
              outerWidth: layout.focusRingWidth,
              offset: layout.focusRingOffset,
            )
          : null,
      child: child,
    );
  }
}

class _FocusRingPainter extends CustomPainter {
  _FocusRingPainter({
    required this.radius,
    required this.inner,
    required this.outer,
    required this.innerWidth,
    required this.outerWidth,
    required this.offset,
  });

  final BorderRadius radius;
  final Color inner;
  final Color outer;
  final double innerWidth;
  final double outerWidth;
  final double offset;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final innerRect = radius.toRRect(rect.inflate(offset));
    final outerRect = radius.toRRect(rect.inflate(offset + innerWidth));
    canvas.drawRRect(
      innerRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = innerWidth
        ..color = inner,
    );
    canvas.drawRRect(
      outerRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = outerWidth
        ..color = outer,
    );
  }

  @override
  bool shouldRepaint(_FocusRingPainter old) =>
      old.inner != inner || old.outer != outer;
}

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
/// gesture of its own, so nothing fires twice.
class WaxTappable extends StatefulWidget {
  const WaxTappable({
    required this.label,
    required this.onPressed,
    required this.child,
    this.semanticsId,
    this.selected,
    this.borderRadius = WaxRadius.thumb,
    this.surface,
    super.key,
  });

  /// The accessible name. Stateful controls say what they will do.
  final String label;

  /// Null disables the control, which is reported as well as drawn.
  final VoidCallback? onPressed;

  final Widget child;
  final String? semanticsId;

  /// Set on controls that are one of a set, so the state is announced
  /// rather than left to colour.
  final bool? selected;

  final BorderRadius borderRadius;

  /// The colour immediately under the ring, for its inner stroke.
  final Color? surface;

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

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final enabled = widget.onPressed != null;
    return Semantics(
      identifier: widget.semanticsId,
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onPressed,
      focusable: enabled,
      focused: _focused,
      // Gated with the flag beside it. Supplying a focus action marks a
      // node focusable whatever `focusable` says, so a disabled control
      // with one advertises itself as a tab stop that does nothing -
      // which is the opposite of what the line above declares.
      onFocus: enabled ? _focus.requestFocus : null,
      child: FocusableActionDetector(
        enabled: enabled,
        focusNode: _focus,
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: WaxFocusRing(
          focused: _focused,
          borderRadius: widget.borderRadius,
          surface: widget.surface ?? colors.canvas,
          child: widget.child,
        ),
      ),
    );
  }
}

/// How much weight a button carries.
enum WaxButtonKind {
  /// One per screen: the thing you came to do.
  filled,

  /// Secondary actions that still deserve a surface.
  tonal,

  /// Everything else.
  text,

  /// Deletes and revokes. Never the default focus target.
  destructive,
}

/// The button.
///
/// Labels are sentence case and name their verb ("Save changes", "Add to
/// queue"), never "Submit" or a bare "OK".
class WaxButton extends StatelessWidget {
  const WaxButton({
    required this.label,
    required this.onPressed,
    this.kind = WaxButtonKind.filled,
    this.icon,
    this.semanticsId,
    this.expand = false,
    super.key,
  });

  final String label;

  /// Null disables the button. Disabled is never signalled by colour
  /// alone: the control also reports itself disabled to assistive tech.
  final VoidCallback? onPressed;

  final WaxButtonKind kind;
  final WaxGlyph? icon;
  final String? semanticsId;

  /// Fills the available width, for sheets and empty states.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final enabled = onPressed != null;

    final (Color background, Color foreground, Color? border) = switch (kind) {
      WaxButtonKind.filled => (colors.accent, colors.onAccent, null),
      WaxButtonKind.tonal => (
        colors.surface2,
        colors.textPrimary,
        colors.hairline,
      ),
      WaxButtonKind.text => (Colors.transparent, colors.accent, null),
      WaxButtonKind.destructive => (Colors.transparent, colors.error, null),
    };

    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          WaxIcon(
            icon!,
            size: 18,
            color: enabled ? foreground : colors.textDisabled,
          ),
          const SizedBox(width: WaxSpace.s8),
        ],
        Text(
          label,
          style: WaxType.label.copyWith(
            color: enabled ? foreground : colors.textDisabled,
          ),
        ),
      ],
    );

    final button = Material(
      color: enabled ? background : colors.surface2,
      borderRadius: WaxRadius.pill,
      child: InkWell(
        onTap: onPressed,
        borderRadius: WaxRadius.pill,
        child: Container(
          constraints: const BoxConstraints(minHeight: WaxSpace.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s20),
          decoration: BoxDecoration(
            borderRadius: WaxRadius.pill,
            border: border == null ? null : Border.all(color: border),
          ),
          child: Center(widthFactor: expand ? null : 1, child: child),
        ),
      ),
    );

    return Semantics(
      identifier: semanticsId,
      button: true,
      enabled: enabled,
      label: label,
      // The action rides the semantics node: a screen reader's double tap
      // and the e2e suite's click both land here, not on the canvas.
      // excludeSemantics collapses the inner Material's own node so the
      // control is announced once.
      excludeSemantics: true,
      onTap: onPressed,
      child: button,
    );
  }
}

/// An icon-only control. Always has an accessible name, and a tooltip on
/// pointer platforms, because the glyph is the whole meaning.
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
    this.selected = false,
    this.mono = false,
    this.surface,
    this.semanticsId,
    super.key,
  });

  /// The accessible name, which is the whole sentence a screen reader
  /// hears: "Trim silence (saved 2m 4s)", not "Trim silence".
  final String label;

  /// What is drawn, when it is shorter than the name. Defaults to
  /// [label].
  final String? text;

  /// Null disables it, which is what a control with a round trip in
  /// flight is.
  final VoidCallback? onPressed;

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
    final enabled = onPressed != null;
    final foreground = selected
        ? colors.onAccentContainer
        : (enabled ? colors.textSecondary : colors.textDisabled);
    return WaxTappable(
      semanticsId: semanticsId,
      label: label,
      selected: selected,
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
            child: Text(
              drawn,
              style: (mono ? WaxType.monoData : WaxType.caption).copyWith(
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WaxIconButton extends StatelessWidget {
  const WaxIconButton({
    required this.glyph,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.size = 20,
    this.color,
    this.semanticsId,
    this.badge,
    super.key,
  });

  final WaxGlyph glyph;

  /// The accessible name, and the tooltip. Stateful controls say what
  /// they will do: "Play" when paused, "Pause" when playing.
  final String label;

  final VoidCallback? onPressed;
  final bool active;
  final double size;
  final Color? color;
  final String? semanticsId;

  /// A count or a countdown drawn on the glyph, such as the sleep
  /// timer's remaining minutes.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final enabled = onPressed != null;
    final tint = !enabled
        ? colors.textDisabled
        : color ?? (active ? colors.accent : colors.textSecondary);

    Widget icon = WaxIcon(glyph, size: size, color: tint, active: active);
    if (badge != null) {
      icon = Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          icon,
          Positioned(
            right: -6,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: WaxRadius.pill,
              ),
              child: Text(
                badge!,
                style: WaxType.caption.copyWith(
                  color: colors.onAccent,
                  fontSize: 9,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return WaxTappable(
      label: label,
      onPressed: onPressed,
      semanticsId: semanticsId,
      borderRadius: WaxRadius.pill,
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: onPressed,
          radius: WaxSpace.touchTarget / 2,
          child: SizedBox(
            width: WaxSpace.touchTarget,
            height: WaxSpace.touchTarget,
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}

/// The floating primary action: one accented disc over the content.
///
/// A page gets at most one, and only where the action is what the page is
/// for. It sits above the deck bar's slot rather than over it, which the
/// scaffold arranges by handing this to `Scaffold.floatingActionButton`
/// inside its own column.
class WaxFab extends StatelessWidget {
  const WaxFab({
    required this.glyph,
    required this.label,
    required this.onPressed,
    this.semanticsId,
    super.key,
  });

  final WaxGlyph glyph;

  /// The accessible name and the tooltip. A fab draws no text, so this is
  /// the only name it has.
  final String label;

  final VoidCallback? onPressed;
  final String? semanticsId;

  /// The disc's diameter. Larger than a touch target on purpose: it is
  /// the one control on the page that should be hittable without looking.
  static const double size = 56;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final enabled = onPressed != null;
    return WaxTappable(
      label: label,
      onPressed: onPressed,
      semanticsId: semanticsId,
      borderRadius: WaxRadius.pill,
      child: Tooltip(
        message: label,
        child: Material(
          color: enabled ? colors.accent : colors.surface2,
          shape: const CircleBorder(),
          elevation: enabled ? 3 : 0,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: WaxIcon(
                  glyph,
                  size: 24,
                  color: enabled ? colors.onAccent : colors.textDisabled,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A vertical drag claim for mouse pointers only.
///
/// The device set is fixed here rather than left to the caller because
/// the set is the point: a finger dragging vertically over a track is
/// scrolling and must stay a scroll. Mouse alone covers trackpads too -
/// a trackpad click-drag reports itself as a mouse (the trackpad kind
/// exists only on pan-zoom events, which the framework asserts never
/// carry it on ordinary pointer events) - and pan-zoom sequences are
/// refused below, so two-finger scrolling over a slider still scrolls.
class _PreciseVerticalDragRecognizer extends VerticalDragGestureRecognizer {
  _PreciseVerticalDragRecognizer()
    : super(
        supportedDevices: const <PointerDeviceKind>{PointerDeviceKind.mouse},
      );

  @override
  bool isPointerPanZoomAllowed(PointerPanZoomStartEvent event) => false;
}

/// The pointer pipeline the slider and the seek bar share.
///
/// One recogniser set, three rules. A tap previews on press and commits
/// on release, so a press that loses the arena (a touch scroll that
/// started on the track) applies nothing. A horizontal drag is the
/// gesture both controls exist for, on every device. And a vertical drag
/// from a precise pointer belongs to the track too: a mouse click drifts
/// a pixel or two between press and release, which is past the
/// precise-pointer slop, so without a claim here the click loses the
/// arena to whatever scrolls or dismisses behind the control and
/// silently does nothing.
///
/// Disabling this mid-gesture disposes the recognisers during the
/// rebuild, and their cancel callbacks land mid-build where setState
/// must not - so the owning states clear their drag fields in
/// didUpdateWidget first, and their abandons no-op when there is
/// nothing left to let go of.
class _TrackGestures extends StatelessWidget {
  const _TrackGestures({
    required this.enabled,
    required this.width,
    required this.inset,
    required this.onPress,
    required this.onDrag,
    required this.onCommit,
    required this.onAbandon,
    required this.child,
  });

  final bool enabled;

  /// The gesture box's width, which every caller already knows - the
  /// slider sizes its own box and the seek bar has measured its row - so
  /// no LayoutBuilder is spent rediscovering it.
  final double width;

  /// How far the drawn track sits inside each end of the gesture box, so
  /// a press just past either end still lands and clamps.
  final double inset;

  /// A press that may yet be cancelled: paint, but apply nothing.
  final ValueChanged<double> onPress;

  /// Movement after the arena is won: paint and, where the control is
  /// live, apply.
  final ValueChanged<double> onDrag;

  final VoidCallback onCommit;
  final VoidCallback onAbandon;

  final Widget child;

  double _fraction(Offset local) {
    final track = width - 2 * inset;
    if (track <= 0) return 0;
    return ((local.dx - inset) / track).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: !enabled
          ? const <Type, GestureRecognizerFactory>{}
          : <Type, GestureRecognizerFactory>{
              TapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                    TapGestureRecognizer.new,
                    (recognizer) {
                      recognizer.onTapDown = (d) =>
                          onPress(_fraction(d.localPosition));
                      recognizer.onTapUp = (_) => onCommit();
                      recognizer.onTapCancel = onAbandon;
                    },
                  ),
              HorizontalDragGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    HorizontalDragGestureRecognizer
                  >(HorizontalDragGestureRecognizer.new, (recognizer) {
                    recognizer.onStart = (d) =>
                        onDrag(_fraction(d.localPosition));
                    recognizer.onUpdate = (d) =>
                        onDrag(_fraction(d.localPosition));
                    recognizer.onEnd = (_) => onCommit();
                    recognizer.onCancel = onAbandon;
                  }),
              _PreciseVerticalDragRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    _PreciseVerticalDragRecognizer
                  >(_PreciseVerticalDragRecognizer.new, (recognizer) {
                    recognizer.onStart = (d) =>
                        onDrag(_fraction(d.localPosition));
                    recognizer.onUpdate = (d) =>
                        onDrag(_fraction(d.localPosition));
                    recognizer.onEnd = (_) => onCommit();
                    recognizer.onCancel = onAbandon;
                  }),
            },
      child: child,
    );
  }
}

/// A horizontal level control: a glyph that mutes, and a track that sets.
///
/// The house's general-purpose slider, which the deck bar's volume is the
/// first caller of. The seek bar next to it is deliberately not this
/// widget: it draws a buffered band and an optional waveform, announces a
/// spoken time rather than a level, and is the one control on the bar
/// whose value moves several times a second on its own. What they share
/// is the pointer pipeline, and that is [_TrackGestures].
///
/// A semantic slider, so a screen reader can set it: increase and
/// decrease step by [step], and the announced value is a percentage,
/// which is what a level is.
///
/// [onMute] is optional and is what the glyph does. Without it the glyph
/// is decoration and says the level rather than offering to silence it -
/// which is the honest arrangement where nothing can be un-muted, and is
/// why the caller decides.
class WaxSlider extends StatefulWidget {
  const WaxSlider({
    required this.value,
    required this.onChanged,
    required this.label,
    this.glyph,
    this.mutedGlyph,
    this.onMute,
    this.muted = false,
    this.step = 0.05,
    this.trackWidth = 96,
    this.endSlop = defaultEndSlop,
    this.semanticsId,
    this.muteSemanticsId,
    super.key,
  }) : assert(
         step > 0,
         'step is the semantic and live-report increment; zero would '
         'silence both',
       );

  /// The ordinary [endSlop].
  static const double defaultEndSlop = 12;

  /// How far the gesture surface extends past each end of the drawn
  /// track. A level is grabbed at its ends more than anywhere else -
  /// full and silent - and a press a few pixels past the knob's travel
  /// used to fall through to whatever was behind the bar. [trackWidth]
  /// stays the drawn width; the row's footprint is wider by twice this.
  /// A caller on a hard width budget passes a smaller slop rather than
  /// giving the whole default up out of its drawn track.
  final double endSlop;

  /// 0 to 1. Values outside are clamped rather than asserted: this draws
  /// live state, and a platform reporting 1.0000001 is not a bug worth
  /// crashing a bar over.
  final double value;

  /// Fired live while a drag moves, once per [step] boundary crossed,
  /// and once more with the exact value on release. Callers therefore
  /// hear the level as the finger moves it, which is what a level is
  /// for; a caller with a round trip behind each write paces itself.
  /// Null disables the control: the track greys and the semantics say
  /// so.
  final ValueChanged<double>? onChanged;

  /// The accessible name of the level itself ("Volume").
  final String label;

  /// Drawn to the left of the track. Two glyphs rather than one, because
  /// the muted state has to be visible without colour.
  final WaxGlyph? glyph;
  final WaxGlyph? mutedGlyph;

  /// What the glyph does when it is a control rather than a label.
  final VoidCallback? onMute;

  /// Forces the muted glyph and label. A level of zero already counts as
  /// muted - see [_muted] - so this is only for a caller whose output is
  /// silent at a level above zero, and no caller has to remember it to get
  /// a silent slider drawn as silent.
  final bool muted;

  /// How far one keyboard or screen-reader step moves the level.
  final double step;

  /// The track's own width. The bar's right cluster sizes to its
  /// contents, so this is a real number rather than an Expanded: a
  /// slider that took the space it could would push the transport off
  /// centre as the window narrowed.
  final double trackWidth;

  final String? semanticsId;
  final String? muteSemanticsId;

  @override
  State<WaxSlider> createState() => _WaxSliderState();
}

class _WaxSliderState extends State<WaxSlider> {
  /// Where a drag in progress has the knob, so the track follows the
  /// finger rather than the value the caller has got round to writing
  /// back. Cleared when the gesture ends.
  double? _dragValue;

  /// The last step boundary reported while dragging, so the live stream
  /// is one event per step crossed rather than one per frame - the
  /// natural throttle - while the painted knob keeps following the raw
  /// fraction. Null outside a gesture.
  int? _reportedStep;

  @override
  void didUpdateWidget(WaxSlider old) {
    super.didUpdateWidget(old);
    // Disabling mid-gesture disposes the recognisers during the rebuild,
    // and their cancel callbacks land mid-build where setState must not.
    // The flip lets go of the preview here, before the build, so the
    // late cancels find nothing to do.
    if (widget.onChanged == null) {
      _dragValue = null;
      _reportedStep = null;
    }
  }

  double get _value => (_dragValue ?? widget.value).clamp(0.0, 1.0);

  /// A level of zero *is* muted, whatever the caller said.
  ///
  /// Asked here rather than at each call site because forgetting it draws a
  /// speaker over silence, which is the one thing the glyph exists to be
  /// right about - and the remote screen forgot it. A caller that has a
  /// separate mute with a level behind it still sets [WaxSlider.muted].
  bool get _muted => widget.muted || _value == 0;

  String _announce(double value) => '${(value.clamp(0.0, 1.0) * 100).round()}%';

  double _stepped(double delta) => (_value + delta).clamp(0.0, 1.0);

  void _nudge(double delta) => widget.onChanged?.call(_stepped(delta));

  int _stepIndex(double value) =>
      widget.step <= 0 ? 0 : (value / widget.step).round();

  /// A press previews only: it can still lose the arena to a scroll,
  /// and a level applied on press would survive its own cancellation.
  void _press(double fraction) {
    setState(() {
      _dragValue = fraction;
      _reportedStep ??= _stepIndex(widget.value);
    });
  }

  /// Movement with the arena won: the knob follows the raw fraction and
  /// the caller hears one value per step boundary crossed.
  void _drag(double fraction) {
    setState(() => _dragValue = fraction);
    _reportedStep ??= _stepIndex(widget.value);
    final step = _stepIndex(fraction);
    if (step == _reportedStep) return;
    _reportedStep = step;
    widget.onChanged!((step * widget.step).clamp(0.0, 1.0));
  }

  void _commit() {
    // The exact fraction, deliberately not the stepped one: the release
    // lands the level where the finger left it, and the step stays what
    // it is for - the keyboard and screen-reader increment.
    widget.onChanged!(_value);
    setState(() {
      _dragValue = null;
      _reportedStep = null;
    });
  }

  /// A press that loses the arena to a scroll never ends, and a level
  /// left mid-drag would pin the knob where the finger passed. Same
  /// reasoning as the seek bar's own abandon. No-ops when there is
  /// nothing held: a disable's late cancel arrives mid-build, after
  /// didUpdateWidget already let go, where setState must not run.
  void _abandon() {
    if (_dragValue == null && _reportedStep == null) return;
    setState(() {
      _dragValue = null;
      _reportedStep = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final enabled = widget.onChanged != null;
    final glyph = _muted ? widget.mutedGlyph : widget.glyph;

    final track = Semantics(
      identifier: widget.semanticsId,
      slider: true,
      enabled: enabled,
      label: widget.label,
      value: _announce(_value),
      // A slider offering increase without saying where increasing lands
      // is a half-built control, and an assertion failure besides.
      increasedValue: _announce(_stepped(widget.step)),
      decreasedValue: _announce(_stepped(-widget.step)),
      onIncrease: enabled ? () => _nudge(widget.step) : null,
      onDecrease: enabled ? () => _nudge(-widget.step) : null,
      child: ExcludeSemantics(
        child: _TrackGestures(
          enabled: enabled,
          width: widget.trackWidth + 2 * widget.endSlop,
          inset: widget.endSlop,
          onPress: _press,
          onDrag: _drag,
          onCommit: _commit,
          onAbandon: _abandon,
          child: SizedBox(
            width: double.infinity,
            // The touch target, not the drawn track: a 4 px bar is
            // unhittable, and the paint is centred inside this.
            height: WaxSpace.touchTarget,
            child: CustomPaint(
              painter: _LevelPainter(
                fraction: _value,
                inset: widget.endSlop,
                track: colors.hairline,
                fill: enabled ? colors.accent : colors.textDisabled,
                knob: enabled ? colors.accent : colors.textDisabled,
              ),
            ),
          ),
        ),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (glyph != null)
          if (widget.onMute != null)
            WaxIconButton(
              glyph: glyph,
              label: _muted ? 'Unmute' : 'Mute',
              size: 18,
              active: _muted,
              onPressed: widget.onMute,
              semanticsId: widget.muteSemanticsId,
            )
          else
            // Decoration, so it is excluded rather than announced: the
            // track beside it already carries the label and the level,
            // and a second node saying "volume" is one more stop for a
            // screen reader with nothing behind it. The end slop is the
            // gap now, so no padding rides on top of it.
            ExcludeSemantics(
              child: WaxIcon(
                glyph,
                size: 18,
                color: enabled ? colors.textSecondary : colors.textDisabled,
              ),
            ),
        SizedBox(width: widget.trackWidth + 2 * widget.endSlop, child: track),
      ],
    );
  }
}

class _LevelPainter extends CustomPainter {
  _LevelPainter({
    required this.fraction,
    required this.inset,
    required this.track,
    required this.fill,
    required this.knob,
  });

  final double fraction;

  /// The end slop: the drawn track starts and ends this far inside the
  /// box, and the gesture surface maps the same rectangle back to the
  /// level, so a press past either end clamps instead of missing.
  final double inset;

  final Color track;
  final Color fill;
  final Color knob;

  @override
  void paint(Canvas canvas, Size size) {
    const height = 4.0;
    final top = (size.height - height) / 2;
    final width = math.max(0.0, size.width - 2 * inset);
    const radius = Radius.circular(2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(inset, top, width, height), radius),
      Paint()..color = track,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(inset, top, width * fraction, height),
        radius,
      ),
      Paint()..color = fill,
    );
    canvas.drawCircle(
      Offset(inset + width * fraction, size.height / 2),
      5,
      Paint()..color = knob,
    );
  }

  @override
  bool shouldRepaint(_LevelPainter old) =>
      old.fraction != fraction ||
      old.inset != inset ||
      old.fill != fill ||
      old.track != track ||
      // The knob moves on a theme flip that changes no other field here;
      // same reasoning as the seek painter's palette comparisons.
      old.knob != knob;
}

/// One row of a [WaxMenuButton].
@immutable
class WaxMenuItem<T> {
  const WaxMenuItem({
    required this.value,
    required this.label,
    this.glyph,
    this.selected = false,
    this.destructive = false,
    this.enabled = true,
    this.semanticsId,
  });

  /// What the button reports when this row is chosen.
  final T value;

  final String label;
  final WaxGlyph? glyph;

  /// Drawn checked, for the rows that are a standing choice (a sort
  /// order) rather than a verb.
  final bool selected;

  /// Deletes and revokes, in the error colour.
  final bool destructive;

  final bool enabled;

  /// This row's own handle. A menu row is a control, so it gets one of
  /// its own rather than being found by its text.
  final String? semanticsId;
}

/// An overflow menu behind one icon button.
///
/// The trigger is the house icon button rather than a [PopupMenuButton],
/// for the reason the chrome's own overflow already follows: a
/// PopupMenuButton draws a second semantics node for the same control,
/// and the suite steers by one handle per control.
class WaxMenuButton<T> extends StatelessWidget {
  const WaxMenuButton({
    required this.items,
    required this.onSelected,
    this.glyph = WaxIcons.more,
    this.label = 'More',
    this.semanticsId,
    this.size = 20,
    this.badge,
    this.onOpen,
    this.emptyLabel,
    super.key,
  });

  final List<WaxMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final WaxGlyph glyph;
  final String label;
  final String? semanticsId;
  final double size;

  /// A count drawn on the trigger's glyph, for a menu whose whole point
  /// is how much is waiting in it.
  final String? badge;

  /// Run as the menu opens. For a menu that is a list of things to be
  /// read rather than a list of verbs: opening it is the reading.
  final VoidCallback? onOpen;

  /// What an empty menu says. Without one an empty menu disables its
  /// trigger, which is right for an overflow of verbs and wrong for a
  /// list that is legitimately empty and worth saying so.
  final String? emptyLabel;

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
        if (items.isEmpty && emptyLabel != null)
          PopupMenuItem<T>(
            enabled: false,
            child: Text(
              emptyLabel!,
              style: WaxType.body.copyWith(color: colors.textTertiary),
            ),
          ),
        for (final item in items)
          PopupMenuItem<T>(
            value: item.value,
            enabled: item.enabled,
            child: Semantics(
              identifier: item.semanticsId,
              selected: item.selected,
              child: Row(
                children: <Widget>[
                  if (item.glyph != null) ...<Widget>[
                    WaxIcon(
                      item.glyph!,
                      size: 16,
                      color: item.destructive
                          ? colors.error
                          : colors.textSecondary,
                    ),
                    const SizedBox(width: WaxSpace.s12),
                  ],
                  Expanded(
                    child: Text(
                      item.label,
                      style: WaxType.body.copyWith(
                        color: item.destructive
                            ? colors.error
                            : colors.textPrimary,
                      ),
                    ),
                  ),
                  if (item.selected)
                    WaxIcon(WaxIcons.check, size: 16, color: colors.accent),
                ],
              ),
            ),
          ),
      ],
    );
    if (chosen != null) onSelected(chosen);
  }

  @override
  Widget build(BuildContext context) => Builder(
    // Its own context, so the menu positions against this button rather
    // than against whatever laid the bar out.
    builder: (context) => WaxIconButton(
      glyph: glyph,
      label: label,
      size: size,
      badge: badge,
      semanticsId: semanticsId,
      onPressed: items.isEmpty && emptyLabel == null
          ? null
          : () {
              onOpen?.call();
              _open(context);
            },
    ),
  );
}

/// The star toggle, with the pop the design language asks for.
///
/// Optimistic state belongs to the app's controllers; this draws whatever
/// it is given and reports the action it will perform, which is the
/// vocabulary the accessibility audit freezes ("Star" / "Unstar").
class StarButton extends StatelessWidget {
  const StarButton({
    required this.starred,
    required this.onChanged,
    this.size = 20,
    this.semanticsId,
    super.key,
  });

  final bool starred;
  final ValueChanged<bool>? onChanged;
  final double size;
  final String? semanticsId;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final motion = WaxMotion.of(context);
    return AnimatedScale(
      // The star pops on the way in and holds still under reduced
      // motion, which the duration token handles for us.
      scale: starred ? 1.08 : 1,
      duration: motion.standard,
      curve: WaxMotion.emphasized,
      child: WaxIconButton(
        glyph: WaxIcons.star,
        label: starred ? 'Unstar' : 'Star',
        semanticsId: semanticsId,
        active: starred,
        size: size,
        color: starred ? colors.accent : colors.textSecondary,
        onPressed: onChanged == null ? null : () => onChanged!(!starred),
      ),
    );
  }
}

/// The seek bar.
///
/// One component covers every medium: a plain track for music, a buffered
/// track for streams, an optional waveform for tracks with peaks, and a
/// live pill instead of a track for radio (the players hide it there).
/// It is a semantic slider, so a screen reader can scrub it: increase and
/// decrease step by [step], and the announced value is a spoken time
/// rather than a percentage.
class WaxSeekBar extends StatefulWidget {
  const WaxSeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
    this.buffered,
    this.peaks,
    this.step = const Duration(seconds: 5),
    this.semanticsId,
    super.key,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration>? onSeek;
  final Duration? buffered;

  /// Normalised 0 to 1 peak amplitudes. When present the track renders as
  /// a waveform; when absent it is a styled bar. Nothing here invents
  /// data: no peaks, no waveform.
  final List<double>? peaks;

  final Duration step;
  final String? semanticsId;

  @override
  State<WaxSeekBar> createState() => _WaxSeekBarState();
}

/// One waveform bar every this many logical pixels: a 2 px bar and a
/// 1 px gap, which is the coarsest reading that still shows a track's
/// shape and the finest that still reads as bars rather than as a smear.
const double _barPitch = 3;

class _WaxSeekBarState extends State<WaxSeekBar> {
  double? _dragFraction;

  /// The peaks reduced to the number of bars this width draws.
  ///
  /// Held rather than recomputed in `paint`: the playhead moves several
  /// times a second and the peaks do not, so reducing a thousand buckets
  /// per frame would be a thousand comparisons and a fresh list to draw
  /// a shape that has not changed since the track started.
  List<double>? _heights;
  List<double>? _heightsFrom;
  int _heightsBars = 0;

  List<double>? _resolvedHeights(double width) {
    final peaks = widget.peaks;
    if (peaks == null || peaks.isEmpty) return null;
    // An unbounded width has no bar count to derive; a fixed reading is
    // better than none, and the constrained case is every real one.
    final bars = width.isFinite
        ? math.max(1, (width / _barPitch).floor())
        : 120;
    if (!identical(_heightsFrom, peaks) || _heightsBars != bars) {
      _heightsFrom = peaks;
      _heightsBars = bars;
      _heights = downsamplePeaks(peaks, bars);
    }
    return _heights;
  }

  @override
  void didUpdateWidget(WaxSeekBar old) {
    super.didUpdateWidget(old);
    // Disabling mid-scrub disposes the recognisers during the rebuild,
    // and their cancel callbacks land mid-build where setState must not.
    // A frame arriving with no duration lets go of the scrub here,
    // before the build, so the late cancels find nothing to do.
    if (widget.onSeek == null || widget.duration <= Duration.zero) {
      _dragFraction = null;
    }
  }

  double get _fraction {
    if (_dragFraction != null) return _dragFraction!;
    final total = widget.duration.inMilliseconds;
    if (total <= 0) return 0;
    return (widget.position.inMilliseconds / total).clamp(0, 1);
  }

  Duration _at(double fraction) => Duration(
    milliseconds: (widget.duration.inMilliseconds * fraction).round(),
  );

  Duration _offsetBy(Duration delta) {
    final target = widget.position + delta;
    if (target < Duration.zero) return Duration.zero;
    return target > widget.duration ? widget.duration : target;
  }

  void _seekBy(Duration delta) => widget.onSeek?.call(_offsetBy(delta));

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    // Every position here is a fraction of the duration, so at zero a
    // scrub or a keyboard step seeks to the start. Callers reach that
    // without meaning to (an unresolved duration, a session frame carrying
    // none), so the guard is here rather than in each of them.
    final enabled = widget.onSeek != null && widget.duration > Duration.zero;

    return Semantics(
      identifier: widget.semanticsId,
      slider: true,
      enabled: enabled,
      label: 'Position',
      value:
          '${spellDuration(widget.position)} of '
          '${spellDuration(widget.duration)}',
      // Position is announced as a spoken time rather than a percentage,
      // and the step values ride along: a slider that offers increase
      // without saying where increasing lands is a half-built control
      // (and an assertion failure).
      increasedValue: spellDuration(_offsetBy(widget.step)),
      decreasedValue: spellDuration(_offsetBy(-widget.step)),
      onIncrease: enabled ? () => _seekBy(widget.step) : null,
      onDecrease: enabled ? () => _seekBy(-widget.step) : null,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The scrub is a preview until release, deliberately: a live
            // seek per drag frame would spam stream loads, so the drag
            // paints and only the commit seeks.
            void preview(double fraction) =>
                setState(() => _dragFraction = fraction);

            void commit() {
              widget.onSeek!(_at(_fraction));
              setState(() => _dragFraction = null);
            }

            // A press that loses the arena to a scroll never ends, and
            // a scrub position left behind would pin the playhead
            // there for good. No-ops when nothing is held: a disable's
            // late cancel arrives mid-build, after didUpdateWidget
            // already let go, where setState must not run.
            void abandon() {
              if (_dragFraction == null) return;
              setState(() => _dragFraction = null);
            }

            return _TrackGestures(
              enabled: enabled,
              width: constraints.maxWidth,
              inset: 0,
              onPress: preview,
              onDrag: preview,
              onCommit: commit,
              onAbandon: abandon,
              child: SizedBox(
                // Width has to be claimed explicitly: inside a centred
                // Column the constraints are loose, and a CustomPaint
                // with no size collapses to nothing. The height is the
                // touch target whatever is drawn: a 24 px box over a
                // 4 px track demanded the accuracy the bug report
                // named.
                width: double.infinity,
                height: WaxSpace.touchTarget,
                child: CustomPaint(
                  painter: _SeekPainter(
                    fraction: _fraction,
                    buffered: widget.duration.inMilliseconds <= 0
                        ? 0
                        : ((widget.buffered ?? Duration.zero).inMilliseconds /
                                  widget.duration.inMilliseconds)
                              .clamp(0, 1),
                    // Resolved against the width the bar was given
                    // rather than handed over raw: the reduction is a
                    // property of this layout, and it outlives every
                    // frame the playhead moves through.
                    heights: _resolvedHeights(constraints.maxWidth),
                    track: colors.hairline,
                    bufferTint: colors.textTertiary.withValues(alpha: 0.4),
                    fill: colors.accent,
                    knob: enabled ? colors.accent : colors.textDisabled,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// [peaks] reduced to [bars] values, each the loudest of the range it
/// covers.
///
/// The catalog stores a fixed thousand buckets and a seek bar is
/// whatever width it was given, so the two are reconciled at paint time.
/// Loudest rather than mean, because an averaged envelope loses exactly
/// the transients that make a track recognisable: the shape a listener
/// aims a scrub at is its peaks, not its energy. Fewer peaks than bars
/// is fine and repeats values rather than inventing them.
List<double> downsamplePeaks(List<double> peaks, int bars) {
  if (peaks.isEmpty || bars <= 0) return const <double>[];
  return List<double>.generate(bars, (i) {
    final from = (i * peaks.length) ~/ bars;
    final to = math.max(from + 1, ((i + 1) * peaks.length) ~/ bars);
    var peak = 0.0;
    for (var j = from; j < to && j < peaks.length; j++) {
      if (peaks[j] > peak) peak = peaks[j];
    }
    return peak.clamp(0.0, 1.0);
  }, growable: false);
}

class _SeekPainter extends CustomPainter {
  _SeekPainter({
    required this.fraction,
    required this.buffered,
    required this.heights,
    required this.track,
    required this.bufferTint,
    required this.fill,
    required this.knob,
  });

  final double fraction;
  final double buffered;

  /// One value per bar, already reduced to this bar's width by the
  /// state that owns it. Null draws the plain track.
  final List<double>? heights;

  final Color track;
  final Color bufferTint;
  final Color fill;
  final Color knob;

  @override
  void paint(Canvas canvas, Size size) {
    final heights = this.heights;
    if (heights != null && heights.isNotEmpty) {
      final bars = heights.length;
      final barWidth = size.width / bars;
      final mid = size.height / 2;
      for (var i = 0; i < bars; i++) {
        final centre = (i + 0.5) / bars;
        final height = math.max(2.0, heights[i] * size.height * 0.92);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              i * barWidth,
              mid - height / 2,
              math.max(1, barWidth - 1),
              height,
            ),
            const Radius.circular(1),
          ),
          Paint()
            ..color = centre <= fraction
                ? fill
                : (centre <= buffered ? bufferTint : track),
        );
      }
      return;
    }

    const height = 4.0;
    final top = (size.height - height) / 2;
    final radius = const Radius.circular(2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, top, size.width, height),
        radius,
      ),
      Paint()..color = track,
    );
    if (buffered > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, top, size.width * buffered, height),
          radius,
        ),
        Paint()..color = bufferTint,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, top, size.width * fraction, height),
        radius,
      ),
      Paint()..color = fill,
    );
    canvas.drawCircle(
      Offset(size.width * fraction, size.height / 2),
      6,
      Paint()..color = knob,
    );
  }

  @override
  bool shouldRepaint(_SeekPainter old) =>
      old.fraction != fraction ||
      old.buffered != buffered ||
      // Identity, because the state hands back the same list until the
      // peaks or the width change; comparing a few hundred doubles
      // every frame is the cost this reduction exists to avoid.
      !identical(old.heights, heights) ||
      old.fill != fill ||
      // The rest of the palette moves on a theme flip, which changes no
      // other field here: without them the bar keeps the dark set's
      // track and knob on a light canvas.
      old.track != track ||
      old.bufferTint != bufferTint ||
      old.knob != knob;
}
