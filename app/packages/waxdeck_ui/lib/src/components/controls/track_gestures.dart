part of 'track_controls.dart';

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
    this.onHover,
  });

  final bool enabled;

  /// Whether a pointer is over the track, for a caller that wants to
  /// draw the difference. Only a device that hovers reports one, so
  /// touch never sees it.
  final ValueChanged<bool>? onHover;

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
        // Both halves of "this is a control", in the one place every
        // track already goes through: the cursor says so before the
        // click, and the flag lets the painter say so too. A dead
        // track claims neither - a pointing hand over something that
        // does nothing is a worse lie than no cursor at all.
        child: MouseRegion(
          cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: widget.enabled ? (_) => widget.onHover?.call(true) : null,
          onExit: (_) => widget.onHover?.call(false),
          child: widget.child,
        ),
      ),
    );
  }
}
