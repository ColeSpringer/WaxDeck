import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens/motion.dart';
import 'edge_fade.dart';

/// One line of text that scrolls itself when it does not fit, and sits
/// still when it does.
///
/// The deck bar's title is the case this exists for: the bar is a strip
/// a few hundred pixels wide holding names nobody chose the length of,
/// and a fade at the edge says "there is more" without ever saying what.
/// A player screen is one tap away and shows the whole thing, which is
/// the argument that kept the fade for years - but the bar is what is on
/// screen, and reading the name of what is playing should not cost a
/// navigation.
///
/// What keeps it from being the marquee everyone regrets:
///
/// - It moves only when the text overflows. A title that fits is a
///   static [Text] with no ticker attached, which is nearly all of them.
/// - It pauses at both ends. Continuous travel is what makes a marquee
///   unreadable; a beat at each end is where the eye actually reads.
/// - It rests between runs rather than for good. A few passes, a long
///   still stretch, then one pass again: motion stays rare, and the
///   line is never permanently parked with half a name under a fade.
/// - The fade follows the travel, so the end the text is parked at is
///   crisp and only the side with more text to come is softened.
/// - It stops entirely under reduced motion
///   ([WaxMotion.animationsEnabled]), where it draws the fade-clipped
///   line the bar drew before.
/// - It animates without rebuilding its parent: the scroll offset is an
///   [Animation] the paint reads, so the bar around it is not rebuilt
///   sixty times a second to move some text.
///
/// The semantics are the whole string either way, so a screen reader
/// hears the name rather than whatever is currently in frame.
class WaxMarqueeText extends StatefulWidget {
  const WaxMarqueeText(
    this.text, {
    this.style,
    this.textAlign = TextAlign.start,
    this.velocity = 30,
    this.pause = const Duration(milliseconds: 1200),
    this.cycles = 3,
    this.rest = const Duration(seconds: 15),
    this.fadeWidth = 16,
    super.key,
  });

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  /// Logical pixels a second. Slow enough to read at a glance and to
  /// stay out of the corner of the eye; a title twice the width of its
  /// slot takes a couple of seconds to pass.
  final double velocity;

  /// How long it holds at each end before travelling back.
  final Duration pause;

  /// How many round trips the line runs before it takes its first
  /// [rest].
  ///
  /// Finite on purpose. A name that never stops moving is the marquee
  /// people mean when they say marquees are bad: it is motion in the
  /// corner of the eye for as long as the track plays, and it is read
  /// in the first pass. Three passes is enough to catch a title that
  /// arrived while you were looking elsewhere; a new title re-arms, so
  /// every track gets its own.
  final int cycles;

  /// How long the line holds still between runs.
  ///
  /// Resting is not stopping. Stopping was the old shape, and on a
  /// station - whose subtitle is a song title that changes once every
  /// few minutes rather than once a track - it meant the line spent
  /// nearly all of its life parked, which reads as a name that is cut
  /// off rather than one that has finished scrolling. Long enough that
  /// the motion is rare, short enough that a name is never unreadable
  /// for the length of a song.
  final Duration rest;

  /// The soft edge at both sides, so text does not appear and vanish at
  /// a hard line. Zero draws no fade.
  final double fadeWidth;

  @override
  State<WaxMarqueeText> createState() => _WaxMarqueeTextState();
}

class _WaxMarqueeTextState extends State<WaxMarqueeText>
    with TickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _offset;

  /// How far the text runs past its slot, which is both the distance to
  /// travel and the test for whether to travel at all.
  double _overflow = 0;

  /// A distance the slot changed to while a run was going, applied at
  /// the next cycle boundary.
  ///
  /// Not applied where it is noticed. The measurement happens inside a
  /// `LayoutBuilder`, so a window being drag-resized delivers a new
  /// distance on every frame of the drag - and re-arming there would
  /// dispose a live controller, register a fresh ticker, and rebuild
  /// the sequence sixty times a second while the title sat frozen at
  /// its start. At a boundary the swap costs nothing and shows as
  /// nothing.
  double? _pendingOverflow;

  /// The still stretch between runs. Cancelled everywhere the
  /// controller is, so a disposed line leaves nothing pending - a timer
  /// outliving its tree is a test failure and, in the app, a `setState`
  /// on a widget that is gone.
  Timer? _resting;

  @override
  void didUpdateWidget(covariant WaxMarqueeText old) {
    super.didUpdateWidget(old);
    // A new title starts at the beginning of itself rather than
    // wherever the last one had got to.
    if (old.text != widget.text || old.style != widget.style) _disarm();
  }

  /// Back to a still line, and back to a state that will arm again.
  ///
  /// One place, because the three that need it are easy to get wrong
  /// apart: stopping the controller without clearing it leaves the
  /// re-arm gate closed, and a title frozen half-scrolled until the
  /// track changes.
  void _disarm() {
    _resting?.cancel();
    _resting = null;
    _controller?.dispose();
    _controller = null;
    _offset = null;
    _overflow = 0;
    _pendingOverflow = null;
  }

  @override
  void dispose() {
    _resting?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  /// Builds (or rebuilds) the loop for a run of [overflow] pixels.
  ///
  /// The shape is hold, travel, hold, travel back, and the two holds are
  /// a fixed wall-clock length while the travel scales with the
  /// distance - so a long title does not whip past at the same duration
  /// a short one ambles through.
  void _arm(double overflow) {
    _resting?.cancel();
    _resting = null;
    _controller?.dispose();
    _overflow = overflow;
    final travelMs = (overflow / widget.velocity * 1000).round().clamp(
      400,
      20000,
    );
    final pauseMs = widget.pause.inMilliseconds;
    final total = travelMs * 2 + pauseMs * 2;
    final controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: total),
    );
    _controller = controller;
    // Counted here rather than with `repeat`, which never reports a
    // cycle ending, so there is nowhere to stop it from.
    var runs = 0;
    controller.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      final pending = _pendingOverflow;
      if (pending != null) {
        _pendingOverflow = null;
        // Out of the notification before re-arming: `_arm` disposes
        // this controller, and this is its own status dispatch.
        scheduleMicrotask(() {
          if (mounted) setState(() => _arm(pending));
        });
        return;
      }
      runs++;
      if (runs < widget.cycles) {
        controller.forward(from: 0);
        return;
      }
      // Rest, then one more round trip, for as long as the line is
      // mounted: the burst is what a new title gets, and after that the
      // line moves often enough that it is never left parked with its
      // own end under a fade.
      _resting?.cancel();
      _resting = Timer(widget.rest, () {
        if (!mounted || _controller != controller) return;
        // A slot that changed while the line was resting is picked up
        // here rather than at the next boundary: nothing completes
        // during a rest, so the pending distance would sit unread for
        // its whole length and then run one pass on the old tween -
        // overshooting a slot that narrowed, stopping short of one that
        // widened, and fading the wrong edge throughout.
        final pending = _pendingOverflow;
        if (pending != null) {
          _pendingOverflow = null;
          setState(() => _arm(pending));
          return;
        }
        controller.forward(from: 0);
      });
    });
    _offset = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(
        tween: ConstantTween<double>(0),
        weight: pauseMs.toDouble(),
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: overflow,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: travelMs.toDouble(),
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(overflow),
        weight: pauseMs.toDouble(),
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: overflow,
          end: 0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: travelMs.toDouble(),
      ),
    ]).animate(controller);
    controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    // The static line, and the one every caller falls back to: it is
    // what a title that fits draws, what reduced motion draws, and what
    // a screen reader is handed in both cases.
    final line = Text(
      widget.text,
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
      textAlign: widget.textAlign,
      style: style,
    );
    if (!WaxMotion.of(context).animationsEnabled) {
      // Disarmed, not paused. A stopped controller still satisfies the
      // re-arm gate below, so turning the preference back off with the
      // same title showing left it frozen wherever the stop caught it,
      // its first characters clipped, until the track changed.
      _disarm();
      return line;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          // The scale the [Text] below will be drawn at, not the
          // unscaled default. Both answers this measurement gives are
          // wrong without it: a title that overflows at 1.3x measures
          // as fitting, so the listener who most needs the line to
          // scroll is the one it never scrolls for - and the height it
          // reports is short by the same factor, which is a clip
          // through the tops and bottoms of the glyphs.
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final overflow = painter.width - constraints.maxWidth;
        // Kept before the painter goes: the moving copy is laid out
        // with an unbounded width, so its height has to come from
        // somewhere that measured the text rather than from the slot,
        // which is free to be unbounded itself (a Column in a Row is,
        // and the deck bar's title block is exactly that).
        final lineHeight = painter.height;
        painter.dispose();
        if (overflow <= 1 || !constraints.hasBoundedWidth) {
          // Fits: no ticker, no clip, no cost. Disposed rather than
          // paused, because a bar that plays a hundred tracks would
          // otherwise accumulate one per title it ever showed.
          _disarm();
          return line;
        }
        // Armed here rather than in a layout callback: this runs during
        // build, and starting a controller from a post-frame callback
        // would cost a frame of stillness on every title change.
        if (_controller == null) {
          _arm(overflow);
        } else if ((overflow - _overflow).abs() > 1) {
          _pendingOverflow = overflow;
        }
        final offset = _offset!;
        return SizedBox(
          height: lineHeight,
          child: ClipRect(
            // The copy that moves is a picture of the text and not a
            // target: it is wider than its slot and slides under the
            // pointer, and the deck bar's title is a tap that opens
            // the player while the desktop window's is a drag handle.
            // Both belong to the slot, which does not move.
            child: IgnorePointer(
              child: Semantics(
                label: widget.text,
                excludeSemantics: true,
                child: AnimatedBuilder(
                  animation: offset,
                  // The fade rides the travel rather than sitting at
                  // both edges: a fixed pair softened the first
                  // characters while the line was parked at its start
                  // and the last ones while it was parked at its end,
                  // which is the name looking clipped at exactly the
                  // moments it is meant to be readable. Each side
                  // fades only as far as there is text still to come
                  // on it.
                  builder: (context, child) => EdgeFade(
                    start: math.min(widget.fadeWidth, offset.value),
                    end: math.min(widget.fadeWidth, _overflow - offset.value),
                    child: Transform.translate(
                      offset: Offset(-offset.value, 0),
                      child: child,
                    ),
                  ),
                  // Built once and slid, rather than laid out per frame.
                  // Wide without bound and exactly one line tall: the
                  // width is what there is to travel across, and an
                  // unbounded height here is what a Column would hand
                  // it.
                  child: OverflowBox(
                    alignment: AlignmentDirectional.centerStart,
                    maxWidth: double.infinity,
                    maxHeight: lineHeight,
                    child: Text(
                      widget.text,
                      maxLines: 1,
                      softWrap: false,
                      style: style,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
