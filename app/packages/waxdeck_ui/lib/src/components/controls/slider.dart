part of 'track_controls.dart';

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
/// which is what a level is, unless [valueLabel] spells it another way.
///
/// It is one Tab stop with the focus ring, and Left or Down and Right or Up
/// step it by [step], as increase and decrease do for a reader.
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
    this.balanced = false,
    this.valueLabel,
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

  /// The leading glyph, drawn at one size whether it is a control or a
  /// label. Named because [balanced] and a caller sizing the row by its
  /// track measure against it.
  static const double glyphSize = 18;

  /// Reserves a trailing gap as wide as the leading glyph, so the drawn
  /// track sits on the row's own centre line.
  ///
  /// For a caller that centres this row under something else centred.
  /// The row is a glyph box and a track laid out from the left, so its
  /// midpoint is half a glyph box right of the track's - which put the
  /// full-screen player's level a touch-target's half-width off the
  /// transport it sits under. A deck bar's level is packed into a
  /// cluster and wants no such gap, which is why this is a caller's
  /// answer rather than the component's.
  final bool balanced;

  /// Spells a level for a screen reader where a percentage is the wrong
  /// unit, such as a speed whose 0 to 1 is a span of rates. Null reads
  /// the share.
  final String Function(double value)? valueLabel;

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

  final FocusNode _focus = FocusNode(debugLabel: 'wax-slider');
  bool _focused = false;

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

  /// A pointer is over the track, so the knob draws a size up. Only a
  /// device that hovers ever sets it, so touch never sees the state.
  ///
  /// A notifier the painter repaints from, rather than state the slider
  /// rebuilds for: the whole of what it decides is two pixels of knob.
  final ValueNotifier<bool> _hovered = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _hovered.dispose();
    _focus.dispose();
    super.dispose();
  }

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

  String _announce(double value) =>
      widget.valueLabel?.call(value) ?? context.waxL10n.spellPercent(value);

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
      focusable: enabled,
      focused: enabled ? _focused : null,
      onFocus: enabled ? _focus.requestFocus : null,
      child: FocusableActionDetector(
        enabled: enabled,
        focusNode: _focus,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowLeft): _SliderStepIntent(-1),
          SingleActivator(LogicalKeyboardKey.arrowDown): _SliderStepIntent(-1),
          SingleActivator(LogicalKeyboardKey.arrowRight): _SliderStepIntent(1),
          SingleActivator(LogicalKeyboardKey.arrowUp): _SliderStepIntent(1),
        },
        actions: <Type, Action<Intent>>{
          _SliderStepIntent: CallbackAction<_SliderStepIntent>(
            onInvoke: (intent) {
              _nudge(intent.direction * widget.step);
              return null;
            },
          ),
        },
        child: WaxFocusRing(
          focused: _focused,
          borderRadius: WaxRadius.pill,
          surface: colors.canvas,
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
              onHover: (over) {
                _hovered.value = over;
              },
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
                    hovered: _hovered,
                  ),
                ),
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
              label: _muted
                  ? context.waxL10n.controlsUnmute
                  : context.waxL10n.controlsMute,
              size: WaxSlider.glyphSize,
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
                size: WaxSlider.glyphSize,
                color: enabled ? colors.textSecondary : colors.textDisabled,
              ),
            ),
        SizedBox(width: widget.trackWidth + 2 * widget.endSlop, child: track),
        // The counterweight, and nothing else: as wide as whichever
        // leading box was drawn, so the track's centre and the row's
        // centre are one point.
        if (widget.balanced && glyph != null)
          SizedBox(
            width: widget.onMute != null
                ? WaxSpace.touchTarget
                : WaxSlider.glyphSize,
          ),
      ],
    );
  }
}

/// One arrow-key step on a [WaxSlider]: [direction] is -1 or 1.
class _SliderStepIntent extends Intent {
  const _SliderStepIntent(this.direction);

  final double direction;
}

class _LevelPainter extends CustomPainter {
  _LevelPainter({
    required this.fraction,
    required this.inset,
    required this.track,
    required this.fill,
    required this.knob,
    required this.hovered,
  }) : super(repaint: hovered);

  final double fraction;

  /// The end slop: the drawn track starts and ends this far inside the
  /// box, and the gesture surface maps the same rectangle back to the
  /// level, so a press past either end clamps instead of missing.
  final double inset;

  final Color track;
  final Color fill;
  final Color knob;

  /// A pointer is over the track. Drawn as a slightly larger knob
  /// rather than a colour change: the accent is already the fill, so a
  /// brighter one would read as a different value.
  ///
  /// A listenable rather than a value, passed to `repaint`: this feeds
  /// two pixels of knob radius and nothing else, and a `setState` for it
  /// would re-run the whole slider - its duration strings, its
  /// `LayoutBuilder`, and the gesture map's factories and closures -
  /// every time a cursor crossed a bar that sits inches from the
  /// transport buttons.
  final ValueListenable<bool> hovered;

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
      hovered.value ? 7 : 5,
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
  // `hovered` is deliberately absent: it repaints through `repaint`
  // rather than through a rebuild, so what there is to compare here is
  // a notifier identity rather than a drawn state - and two bars drawn
  // the same way hold two different notifiers.
}
