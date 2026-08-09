import 'dart:async';
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
    this.spokenLabel,
    this.semanticsId,
    this.expand = false,
    super.key,
  });

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
      label: spokenLabel ?? label,
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
class _TrackGestures extends StatefulWidget {
  const _TrackGestures({
    required this.enabled,
    required this.width,
    required this.inset,
    required this.onPress,
    required this.onGlide,
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

  /// A press that may yet be cancelled, with the device it came from:
  /// the owners decide per pointer kind whether a press only paints or
  /// already applies (a mouse click is a decision; a touch may become
  /// a scroll).
  final void Function(double fraction, PointerDeviceKind? kind) onPress;

  /// Raw movement before any recogniser has claimed the pointer: paint
  /// only, never apply. Inside a scroll view a touch drag has to travel
  /// the platform's disambiguation slop before the track wins the
  /// arena, and a knob that sat still through that stretch read as the
  /// control lagging the finger; this is what lets it follow from the
  /// first event. The owners stop honouring it once the gesture is
  /// abandoned, so a scroll that wins does not drag the knob along.
  final ValueChanged<double> onGlide;

  /// Movement after the arena is won: paint and, where the control is
  /// live, apply.
  final ValueChanged<double> onDrag;

  final VoidCallback onCommit;
  final VoidCallback onAbandon;

  final Widget child;

  @override
  State<_TrackGestures> createState() => _TrackGesturesState();
}

class _TrackGesturesState extends State<_TrackGestures> {
  /// Whether one of this track's own recognisers has claimed the
  /// pointer, after which the raw glide below stands down and the
  /// recogniser's stream drives. A field rather than a build-local:
  /// gliding repaints per event, and closure state minted inside a
  /// build would reset under the gesture it is tracking.
  bool _claimed = false;

  /// Whether the current pointer sequence stopped being this track's:
  /// its vertical excursion says it is a scroll, or a cancel arrived.
  bool _dead = false;

  /// Whether this sequence has already been answered with a commit or
  /// an abandon, so the release fallback below does not answer twice.
  bool _settled = false;

  /// Where the pointer went down, for the excursion test.
  double? _downDy;

  /// The one pointer this track is following. The raw listener hears
  /// every pointer, and a second finger landing on the track mid-drag
  /// must not reset the latches or move the measurements out from
  /// under the first.
  int? _pointer;

  /// Bumped per followed press, so a release's deferred fallback can
  /// tell it still speaks for the sequence it was scheduled by.
  int _sequence = 0;

  @override
  void didUpdateWidget(_TrackGestures old) {
    super.didUpdateWidget(old);
    // Disabling mid-gesture nulls the listener callbacks, so the up
    // that would release the followed pointer never arrives; left
    // held, every press after re-enabling would be refused.
    if (!widget.enabled) {
      _sequence++;
      _pointer = null;
      _claimed = false;
      _dead = false;
      _settled = true;
    }
  }

  double _fraction(Offset local) {
    final track = widget.width - 2 * widget.inset;
    if (track <= 0) return 0;
    return ((local.dx - widget.inset) / track).clamp(0.0, 1.0);
  }

  void _commit() {
    _settled = true;
    _claimed = false;
    widget.onCommit();
  }

  void _abandon() {
    _settled = true;
    _claimed = false;
    _dead = true;
    widget.onAbandon();
  }

  void _down(PointerDownEvent event) {
    if (_pointer != null) return;
    // Primary button only. The recognisers refuse the rest, so nothing
    // would ever commit or cancel the press this painted: a right-click
    // would set a level and pin the knob until the next real gesture.
    if (event.buttons != kPrimaryButton) return;
    _pointer = event.pointer;
    _sequence++;
    _claimed = false;
    _dead = false;
    _settled = false;
    _downDy = event.position.dy;
    widget.onPress(_fraction(event.localPosition), event.kind);
  }

  /// Raw movement. Until a recogniser claims the pointer this is what
  /// keeps the knob under the finger; once the sequence has clearly
  /// gone vertical it is a scroll by the same rule the arena will
  /// apply, and the preview is let go rather than dragged along -
  /// which matters because no recogniser callback reports that loss
  /// reliably (a fast scroll rejects the tap before it ever sent its
  /// down, so its cancel never fires).
  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    if (_claimed || _dead) return;
    final downDy = _downDy;
    if (downDy != null && (event.position.dy - downDy).abs() > kTouchSlop) {
      _abandon();
      return;
    }
    widget.onGlide(_fraction(event.localPosition));
  }

  /// The release. Whether it resolved anything is only knowable after
  /// the event finishes routing - the arena closes on the up, then a
  /// winning tap fires its onTapUp or a won drag its onEnd - so the
  /// question is deferred past both. When it resolved nothing (the tap
  /// was rejected before its deadline and every drag lost, which no
  /// recogniser callback reports), the pressed preview would otherwise
  /// stay latched for good.
  void _up(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    final sequence = _sequence;
    scheduleMicrotask(() {
      if (!mounted || sequence != _sequence) return;
      if (_settled || _claimed) return;
      _abandon();
    });
  }

  /// The platform took the pointer back (a palm rejection, a system
  /// gesture, the browser reclaiming a touch): nothing else reports
  /// the loss when no recogniser had claimed it yet.
  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    if (_settled) return;
    _abandon();
  }

  /// The tap losing to one of this track's own drags is the gesture
  /// carrying on, not ending; only a loss while nothing here holds the
  /// pointer is a real abandonment (a touch scroll that started on the
  /// track and won before the excursion test could see it).
  void _tapCancel() {
    if (_claimed || _settled) return;
    _abandon();
  }

  void _dragStart(DragStartDetails details) {
    _claimed = true;
    widget.onDrag(_fraction(details.localPosition));
  }

  void _dragCancel() {
    // Only a drag that had begun has anything to let go of. A
    // recogniser also fires its cancel when it merely LOSES the arena -
    // and on a deliberate click (press, pause, release) both drags lose
    // at the sweep the release runs, before the winning tap's own
    // callbacks. Un-gated, those cancels wiped the pressed preview and
    // the tap then committed the value the slider already had: the
    // click silently did nothing. The losses this gate swallows are
    // answered by the release fallback and the raw cancel above.
    if (!_claimed) return;
    _abandon();
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: !widget.enabled
          ? const <Type, GestureRecognizerFactory>{}
          : <Type, GestureRecognizerFactory>{
              TapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                    TapGestureRecognizer.new,
                    (recognizer) {
                      // The press itself lands through the raw listener
                      // below, on the down event rather than at the tap
                      // deadline; the recogniser's half is the release
                      // and the arena loss.
                      recognizer.onTapUp = (_) => _commit();
                      recognizer.onTapCancel = _tapCancel;
                    },
                  ),
              HorizontalDragGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    HorizontalDragGestureRecognizer
                  >(HorizontalDragGestureRecognizer.new, (recognizer) {
                    recognizer.onStart = _dragStart;
                    recognizer.onUpdate = (d) =>
                        widget.onDrag(_fraction(d.localPosition));
                    recognizer.onEnd = (_) => _commit();
                    recognizer.onCancel = _dragCancel;
                  }),
              _PreciseVerticalDragRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    _PreciseVerticalDragRecognizer
                  >(_PreciseVerticalDragRecognizer.new, (recognizer) {
                    recognizer.onStart = _dragStart;
                    recognizer.onUpdate = (d) =>
                        widget.onDrag(_fraction(d.localPosition));
                    recognizer.onEnd = (_) => _commit();
                    recognizer.onCancel = _dragCancel;
                  }),
            },
      child: Listener(
        onPointerDown: !widget.enabled ? null : _down,
        onPointerMove: !widget.enabled ? null : _move,
        onPointerUp: !widget.enabled ? null : _up,
        onPointerCancel: !widget.enabled ? null : _cancel,
        child: widget.child,
      ),
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
  /// and once more with the exact value on release when the gesture has
  /// not already delivered exactly it - so a mouse click, which applies
  /// on press, is one event and never two. Callers therefore hear the
  /// level as the finger moves it, which is what a level is for; a
  /// caller with a round trip behind each write paces itself. Null
  /// disables the control: the track greys and the semantics say so.
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

  /// Latched when the gesture is abandoned (a scroll won the arena),
  /// so the raw glide events that keep arriving under the scroll stop
  /// painting the knob along with it. Reset by the next press.
  bool _dead = false;

  /// The last step boundary reported while dragging, so the live stream
  /// is one event per step crossed rather than one per frame - the
  /// natural throttle - while the painted knob keeps following the raw
  /// fraction. Null outside a gesture.
  int? _reportedStep;

  /// The last value actually handed to the caller this gesture, so the
  /// release does not repeat it: a mouse press applies exactly where
  /// the click lands, and un-deduplicated the commit sent the same
  /// click a second time - two writes for a caller with a round trip
  /// behind each one. Null outside a gesture and after touch presses,
  /// which apply nothing until release.
  double? _sent;

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
      _sent = null;
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

  /// A press previews, and from a precise pointer it applies too: a
  /// mouse click is a decision, and a level that only painted until
  /// release read as a dead control under a held button - the click
  /// used to land the moment it was pressed, and going quiet on the
  /// down-stroke was reported as the control getting worse. A touch
  /// press stays preview-only, because it can still lose the arena to
  /// the scroll it may be starting, and a level applied then would
  /// survive its own cancellation.
  void _press(double fraction, PointerDeviceKind? kind) {
    _dead = false;
    _sent = null;
    setState(() {
      _dragValue = fraction;
      _reportedStep ??= _stepIndex(widget.value);
    });
    if (kind == PointerDeviceKind.mouse) {
      // The exact fraction rather than the stepped one: a click is one
      // decision about one place, and the step stays what it is for -
      // the throttle a drag's stream needs and a keyboard's increment.
      _sent = fraction;
      _reportedStep = _stepIndex(fraction);
      widget.onChanged!(fraction);
    }
  }

  /// Raw movement while the arena still arbitrates: the knob follows
  /// the pointer from the first event instead of sitting through the
  /// disambiguation slop a scrollable ancestor imposes, which read as
  /// the drag lagging the finger. Paint only - the level applies once
  /// a recogniser actually wins, or at release.
  void _glide(double fraction) {
    if (_dead || widget.onChanged == null) return;
    setState(() => _dragValue = fraction);
  }

  /// Movement with the arena won: the knob follows the raw fraction and
  /// the caller hears one value per step boundary crossed.
  void _drag(double fraction) {
    _dead = false;
    setState(() => _dragValue = fraction);
    _report(fraction);
  }

  /// One caller-facing event per step boundary crossed.
  void _report(double fraction) {
    _reportedStep ??= _stepIndex(widget.value);
    final step = _stepIndex(fraction);
    if (step == _reportedStep) return;
    _reportedStep = step;
    final value = (step * widget.step).clamp(0.0, 1.0);
    _sent = value;
    widget.onChanged!(value);
  }

  void _commit() {
    // The exact fraction, deliberately not the stepped one: the release
    // lands the level where the finger left it, and the step stays what
    // it is for - the keyboard and screen-reader increment. Skipped
    // when the gesture already delivered exactly this value (a mouse
    // click applies on press), so one click is one event.
    final value = _value;
    if (value != _sent) widget.onChanged!(value);
    _sent = null;
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
    _dead = true;
    _sent = null;
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
          onGlide: _glide,
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
    this.marks,
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

  /// Positions to tick, for a bar that spans something with divisions in
  /// it: a book's chapters across a whole-book envelope.
  ///
  /// Decoration, and deliberately not semantics. The slider already
  /// announces one position and one span; a screen reader hearing
  /// forty tick marks would be told about the shape of a picture it
  /// cannot see, and the chapter list is where a chapter is chosen.
  final List<Duration>? marks;

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

  /// Latched on abandon so the raw glide events a winning scroll keeps
  /// sending stop moving the scrub preview; reset by the next press.
  bool _dead = false;

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

  /// The ticks as fractions of the span.
  ///
  /// Held like the heights are, for the same reason: the playhead moves
  /// several times a second and the divisions do not, and the painter
  /// compares this list by identity.
  List<double>? _markFractions;
  List<Duration>? _marksFrom;
  Duration? _marksSpan;

  List<double>? _resolvedMarks() {
    if (!identical(_marksFrom, widget.marks) || _marksSpan != widget.duration) {
      _marksFrom = widget.marks;
      _marksSpan = widget.duration;
      _markFractions = markFractions(widget.marks, widget.duration);
    }
    return _markFractions;
  }

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
              _dead = true;
              if (_dragFraction == null) return;
              setState(() => _dragFraction = null);
            }

            return _TrackGestures(
              enabled: enabled,
              width: constraints.maxWidth,
              inset: 0,
              // A seek is destructive where a level is not, so a press
              // previews from every device and commits on release.
              onPress: (fraction, _) {
                _dead = false;
                preview(fraction);
              },
              onGlide: (fraction) {
                if (_dead) return;
                preview(fraction);
              },
              onDrag: (fraction) {
                _dead = false;
                preview(fraction);
              },
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
                    marks: _resolvedMarks(),
                    track: colors.hairline,
                    bufferTint: colors.textTertiary.withValues(alpha: 0.4),
                    fill: colors.accent,
                    knob: enabled ? colors.accent : colors.textDisabled,
                    mark: colors.textTertiary.withValues(alpha: 0.5),
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

/// [marks] as fractions of [span], with anything outside it dropped.
///
/// Dropped rather than clamped, and both edges excluded. These come out
/// of file metadata through a third-party reader, so a chapter list and
/// a duration disagreeing is ordinary rather than exceptional - and a
/// tick pinned to the end would sit on the knob's rail claiming a
/// division starts where the bar stops. Null where there is nothing to
/// draw, which is what the painter takes to mean "no ticks".
List<double>? markFractions(List<Duration>? marks, Duration span) {
  final total = span.inMilliseconds;
  if (marks == null || marks.isEmpty || total <= 0) return null;
  final out = <double>[
    for (final at in marks)
      if (at > Duration.zero && at < span) at.inMilliseconds / total,
  ];
  return out.isEmpty ? null : out;
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
    required this.marks,
    required this.track,
    required this.bufferTint,
    required this.fill,
    required this.knob,
    required this.mark,
  });

  final double fraction;
  final double buffered;

  /// One value per bar, already reduced to this bar's width by the
  /// state that owns it. Null draws the plain track.
  final List<double>? heights;

  /// Fractions of the span to tick, already bounded by the state.
  final List<double>? marks;

  final Color track;
  final Color bufferTint;
  final Color fill;
  final Color knob;
  final Color mark;

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
      _paintMarks(canvas, size, size.height * 0.92);
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
    // Between the fill and the knob: a tick under the playhead would be
    // a division the knob is hiding, and one over it would look like
    // part of the control.
    _paintMarks(canvas, size, height * 2.5);
    canvas.drawCircle(
      Offset(size.width * fraction, size.height / 2),
      6,
      Paint()..color = knob,
    );
  }

  /// The division ticks, centred on the bar and one logical pixel wide.
  void _paintMarks(Canvas canvas, Size size, double height) {
    final marks = this.marks;
    if (marks == null || marks.isEmpty) return;
    final mid = size.height / 2;
    final paint = Paint()..color = mark;
    for (final at in marks) {
      canvas.drawRect(
        Rect.fromLTWH(size.width * at, mid - height / 2, 1, height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SeekPainter old) =>
      old.fraction != fraction ||
      old.buffered != buffered ||
      // Identity, because the state hands back the same list until the
      // peaks or the width change; comparing a few hundred doubles
      // every frame is the cost this reduction exists to avoid.
      !identical(old.heights, heights) ||
      !identical(old.marks, marks) ||
      old.fill != fill ||
      // The rest of the palette moves on a theme flip, which changes no
      // other field here: without them the bar keeps the dark set's
      // track and knob on a light canvas.
      old.track != track ||
      old.bufferTint != bufferTint ||
      old.mark != mark ||
      old.knob != knob;
}
