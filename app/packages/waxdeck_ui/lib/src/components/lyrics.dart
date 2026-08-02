import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/motion.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'controls.dart';

/// One line of words with the moment it is sung.
///
/// Plain data, like every other view-data struct here: `waxdeck_ui`
/// never imports the API package, so a screen maps the wire model into
/// this at the call site.
@immutable
class LyricLine {
  const LyricLine({required this.at, required this.text});

  final Duration at;
  final String text;
}

/// The words, following playback where they can.
///
/// Two shapes behind one component, decided by what the source carried.
/// Timed lines scroll as a karaoke list: the line being sung is in
/// primary text with an amber tick beside it, everything else is
/// secondary, a tap on any line seeks to it, and the list follows the
/// playhead until somebody scrolls. Untimed words are a block of
/// readable text at a measure that can actually be read, and nothing
/// about them moves.
///
/// The position arrives as a listenable rather than as a value: the
/// playhead moves several times a second and the highlight moves once a
/// line, so this listens and rebuilds on the line boundary. A caller
/// rebuilding it per tick would repaint a screen of text to move a tick
/// mark once every few seconds.
class LyricsView extends StatefulWidget {
  const LyricsView({
    required this.position,
    this.lines = const <LyricLine>[],
    this.text,
    this.onSeek,
    this.semanticsId,
    this.lineSemanticsId,
    this.followSemanticsId,
    super.key,
  });

  /// The live position. Only read while [lines] is non-empty; untimed
  /// words have nothing to follow.
  final ValueListenable<Duration> position;

  /// Timed lines, ordered by [LyricLine.at].
  final List<LyricLine> lines;

  /// The untimed block, drawn when there are no [lines].
  final String? text;

  /// Null makes the lines read-only, which is what a surface with no
  /// transport behind it wants.
  final ValueChanged<Duration>? onSeek;

  final String? semanticsId;

  /// The handle for one line, by index.
  final String Function(int index)? lineSemanticsId;

  final String? followSemanticsId;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  /// Two lines of body text, which is what a row holds at most.
  static const double _textExtent = 40;

  /// The gutter above and below the words, which does not scale: it is
  /// the space between rows rather than part of them.
  static const double _rowPadding = WaxSpace.s8 * 2;

  /// Every row is one height, so following is arithmetic rather than a
  /// measurement pass over a list that can be hundreds long - but the
  /// height is the text's, so it follows the text scale with it. Fixed
  /// at 56, the row fit two lines of body text at exactly one hundred
  /// percent and clipped them at every notch above it, which is the
  /// setting the layout system promises to honour to two hundred.
  double _rowExtent(BuildContext context) =>
      _rowPadding + MediaQuery.textScalerOf(context).scale(_textExtent);

  final ScrollController _scroll = ScrollController();

  /// Which line is being sung, or -1 before the first one.
  int _current = -1;

  /// Whether the list still moves itself. A manual scroll turns it off;
  /// the button that appears turns it back on.
  bool _following = true;

  @override
  void initState() {
    super.initState();
    widget.position.addListener(_onPosition);
    _current = _lineAt(widget.position.value);
    // Opened three minutes into a track, the line being sung is three
    // minutes down the list. Without this the view starts at the top and
    // stays there until the playhead crosses into the next line - and
    // for a paused track, forever.
    _anchor();
  }

  @override
  void didUpdateWidget(covariant LyricsView old) {
    super.didUpdateWidget(old);
    if (!identical(old.position, widget.position)) {
      old.position.removeListener(_onPosition);
      widget.position.addListener(_onPosition);
    }
    // A new track's words arrive with the old track's highlight, and its
    // position is somewhere else entirely.
    //
    // By identity, which puts a requirement on the caller: hand this the
    // same list while it is the same words. A caller mapping a wire
    // model inline builds a new list every rebuild, and every one of
    // them would read as a new track here - dragging a reader who had
    // scrolled away back to the playhead and taking the button that
    // undoes it with them.
    if (!identical(old.lines, widget.lines)) {
      _current = _lineAt(widget.position.value);
      _following = true;
      _anchor();
    }
  }

  /// Puts the list where the playhead is, after the frame that lays it
  /// out: there is no scroll extent to move within until then.
  void _anchor() {
    if (_current < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _following) _follow(_current);
    });
  }

  @override
  void dispose() {
    widget.position.removeListener(_onPosition);
    _scroll.dispose();
    super.dispose();
  }

  /// The latest line at or before [at], by comparison rather than by
  /// walking to the end: the list is promised ordered and is built from
  /// a sidecar somebody else wrote, so a helper that reads the same
  /// either way costs nothing to write.
  int _lineAt(Duration at) {
    final ms = at.inMilliseconds;
    var found = -1;
    for (var i = 0; i < widget.lines.length; i++) {
      if (widget.lines[i].at.inMilliseconds <= ms) found = i;
    }
    return found;
  }

  /// Whether the line already showing is still the one being sung.
  ///
  /// A line lasts seconds and the position moves several times a second,
  /// so nearly every tick lands inside the answer already held: two
  /// comparisons rather than a walk of the whole verse. The scan above
  /// is what runs when it does not, which is once a line.
  bool _stillOn(int ms) {
    if (_current < 0 || _current >= widget.lines.length) return false;
    if (widget.lines[_current].at.inMilliseconds > ms) return false;
    final next = _current + 1;
    return next >= widget.lines.length ||
        widget.lines[next].at.inMilliseconds > ms;
  }

  void _onPosition() {
    if (!mounted || widget.lines.isEmpty) return;
    final ms = widget.position.value.inMilliseconds;
    if (_stillOn(ms)) return;
    final next = _lineAt(widget.position.value);
    if (next == _current) return;
    setState(() => _current = next);
    if (!_following || next < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _following) _follow(next);
    });
  }

  /// Told apart by who moved it: a programmatic jump arrives with no
  /// user scroll behind it, so only a drag or a wheel counts as somebody
  /// taking over.
  bool _onScrollNotification(Notification note) {
    if (note is UserScrollNotification && _following) {
      setState(() => _following = false);
    }
    return false;
  }

  void _follow(int index) {
    if (!_scroll.hasClients) return;
    // A third of the viewport above the current line rather than the top
    // of it: the words coming next are the ones being read ahead.
    final lead = _scroll.position.viewportDimension / 3;
    final target = (index * _rowExtent(context) - lead).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    final motion = WaxMotion.of(context);
    if (!motion.animationsEnabled) {
      _scroll.jumpTo(target);
      return;
    }
    unawaited(
      _scroll.animateTo(
        target,
        duration: motion.standard,
        curve: WaxMotion.emphasized,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    if (widget.lines.isEmpty) return _block(colors);

    return Semantics(
      identifier: widget.semanticsId,
      container: true,
      explicitChildNodes: true,
      label: 'Lyrics',
      child: Stack(
        children: <Widget>[
          NotificationListener<Notification>(
            onNotification: _onScrollNotification,
            child: ListView.builder(
              controller: _scroll,
              itemExtent: _rowExtent(context),
              padding: const EdgeInsets.symmetric(vertical: WaxSpace.s8),
              itemCount: widget.lines.length,
              itemBuilder: (context, index) => _line(colors, index),
            ),
          ),
          if (!_following)
            Positioned(
              right: WaxSpace.s12,
              bottom: WaxSpace.s12,
              child: WaxButton(
                label: 'Follow along',
                kind: WaxButtonKind.tonal,
                semanticsId: widget.followSemanticsId,
                onPressed: () {
                  setState(() => _following = true);
                  _follow(_current);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _line(WaxColors colors, int index) {
    final line = widget.lines[index];
    final singing = index == _current;
    final seek = widget.onSeek;
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WaxSpace.s16,
        vertical: WaxSpace.s8,
      ),
      child: Row(
        children: <Widget>[
          // The tick holds its column whether or not it is drawn, so the
          // words do not step sideways as the highlight passes them.
          SizedBox(
            width: WaxSpace.s12,
            child: singing
                ? Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: WaxRadius.pill,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: WaxSpace.s8),
          Expanded(
            child: Text(
              line.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: WaxType.body.copyWith(
                color: singing ? colors.textPrimary : colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
    if (seek == null) {
      // Still a node of its own, so a screen reader reads the words a
      // line at a time rather than as one paragraph, and still says
      // which line is being sung.
      return Semantics(
        identifier: widget.lineSemanticsId?.call(index),
        selected: singing,
        label: line.text,
        excludeSemantics: true,
        child: row,
      );
    }
    return WaxTappable(
      semanticsId: widget.lineSemanticsId?.call(index),
      label: line.text,
      selected: singing,
      onPressed: () => seek(line.at),
      child: InkWell(onTap: () => seek(line.at), child: row),
    );
  }

  /// Words with no timings: a column of readable text rather than a list
  /// that pretends to follow anything.
  Widget _block(WaxColors colors) {
    return Semantics(
      identifier: widget.semanticsId,
      container: true,
      label: 'Lyrics',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(WaxSpace.s16),
        child: Center(
          child: ConstrainedBox(
            // A measure rather than the window: a wide desktop panel
            // would otherwise set a verse as one line each.
            constraints: const BoxConstraints(maxWidth: 720),
            child: Text(
              widget.text ?? '',
              style: WaxType.body.copyWith(
                color: colors.textPrimary,
                height: 1.6,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
