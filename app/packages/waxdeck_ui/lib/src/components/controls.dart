import 'dart:math' as math;

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
    if (!focused) return child;
    final colors = WaxColors.of(context);
    final layout = WaxLayout.of(context);
    final inner = surface ?? colors.surface1;
    return CustomPaint(
      foregroundPainter: _FocusRingPainter(
        radius: borderRadius,
        inner: inner,
        outer: colors.accent,
        innerWidth: layout.focusRingInnerWidth,
        outerWidth: layout.focusRingWidth,
        offset: layout.focusRingOffset,
      ),
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

    return Semantics(
      identifier: semanticsId,
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
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

class _WaxSeekBarState extends State<WaxSeekBar> {
  double? _dragFraction;

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
    final enabled = widget.onSeek != null;

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
            void update(Offset local) {
              final fraction = (local.dx / constraints.maxWidth).clamp(
                0.0,
                1.0,
              );
              setState(() => _dragFraction = fraction);
            }

            void commit() {
              widget.onSeek!(_at(_fraction));
              setState(() => _dragFraction = null);
            }

            void abandon() => setState(() => _dragFraction = null);

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: enabled ? (d) => update(d.localPosition) : null,
              onTapUp: enabled ? (_) => commit() : null,
              // A press that loses the arena to a scroll never ends, and
              // a scrub position left behind would pin the playhead
              // there for good.
              onTapCancel: enabled ? abandon : null,
              onHorizontalDragUpdate: enabled
                  ? (d) => update(d.localPosition)
                  : null,
              onHorizontalDragEnd: enabled ? (_) => commit() : null,
              onHorizontalDragCancel: enabled ? abandon : null,
              child: SizedBox(
                // Width has to be claimed explicitly: inside a centred
                // Column the constraints are loose, and a CustomPaint
                // with no size collapses to nothing.
                width: double.infinity,
                height: widget.peaks == null ? 24 : 44,
                child: CustomPaint(
                  painter: _SeekPainter(
                    fraction: _fraction,
                    buffered: widget.duration.inMilliseconds <= 0
                        ? 0
                        : ((widget.buffered ?? Duration.zero).inMilliseconds /
                                  widget.duration.inMilliseconds)
                              .clamp(0, 1),
                    peaks: widget.peaks,
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

class _SeekPainter extends CustomPainter {
  _SeekPainter({
    required this.fraction,
    required this.buffered,
    required this.peaks,
    required this.track,
    required this.bufferTint,
    required this.fill,
    required this.knob,
  });

  final double fraction;
  final double buffered;
  final List<double>? peaks;
  final Color track;
  final Color bufferTint;
  final Color fill;
  final Color knob;

  @override
  void paint(Canvas canvas, Size size) {
    final peaks = this.peaks;
    if (peaks != null && peaks.isNotEmpty) {
      final barWidth = size.width / peaks.length;
      final mid = size.height / 2;
      for (var i = 0; i < peaks.length; i++) {
        final played = (i + 0.5) / peaks.length <= fraction;
        final height = math.max(2.0, peaks[i].clamp(0, 1) * size.height * 0.92);
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
          Paint()..color = played ? fill : track,
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
      old.peaks != peaks ||
      old.fill != fill;
}
