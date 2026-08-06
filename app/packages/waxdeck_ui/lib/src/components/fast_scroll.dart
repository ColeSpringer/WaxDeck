import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// The alphabet strip beside a long A-to-Z index.
///
/// Every letter owns an equal slice of the rail's height, so a tap and a
/// drag resolve to the same letter and every letter is its own semantics
/// node. When the rail is too short to letter every slice legibly it
/// draws a dot for the ones it skips rather than dropping them: the
/// slices stay where they were, so dragging still reaches every letter
/// and a screen reader still finds one.
///
/// It is a supplementary affordance, never the only way to reach a
/// bucket. Its slices are deliberately smaller than a touch target - a
/// 27-target strip could not be otherwise - and scrolling reaches
/// everything it does, which is why it hides itself entirely rather than
/// shrink below legibility.
class FastScrollRail extends StatefulWidget {
  const FastScrollRail({
    required this.letters,
    required this.onLetter,
    this.available = const <String>{},
    this.selected,
    this.semanticsId,
    this.letterSemanticsId,
    super.key,
  });

  /// The index letters, in order. Conventionally `#` then A to Z, since
  /// digits and symbols sort ahead of letters.
  final List<String> letters;

  /// Fired with the letter under a tap or a drag.
  final ValueChanged<String> onLetter;

  /// The letters that actually have buckets. The rest are drawn dimmed
  /// and still report, because a rail that silently ignores half its
  /// letters reads as broken; the caller answers by landing on the
  /// nearest bucket after it.
  final Set<String> available;

  /// The letter the list is currently showing.
  final String? selected;

  final String? semanticsId;

  /// Builds the per-letter handle. Letters are e2e touchpoints, so the
  /// caller supplies the naming rather than the component inventing one.
  final String Function(String letter)? letterSemanticsId;

  /// Below this, a slice cannot carry a legible glyph and the rail hides.
  static const double minSlice = 9;

  @override
  State<FastScrollRail> createState() => _FastScrollRailState();
}

class _FastScrollRailState extends State<FastScrollRail> {
  /// The letter the pointer is on mid-drag, so the rail can show where a
  /// finger is before it lifts.
  String? _dragging;

  void _reportAt(double dy, double height) {
    if (widget.letters.isEmpty || height <= 0) return;
    final slice = height / widget.letters.length;
    final index = (dy / slice).floor().clamp(0, widget.letters.length - 1);
    final letter = widget.letters[index];
    if (letter == _dragging) return;
    setState(() => _dragging = letter);
    widget.onLetter(letter);
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final glyphHeight = scaler.scale(WaxType.caption.fontSize ?? 11.5) + 2;

    // The width is fixed outside the LayoutBuilder on purpose: a
    // LayoutBuilder cannot answer an intrinsic dimension, and anything
    // that measures its children before laying them out (a Table, an
    // IntrinsicWidth) asks. A tight width short-circuits that question
    // without ever reaching the builder.
    return SizedBox(
      width: WaxSpace.s24,
      child: LayoutBuilder(
        builder: (context, constraints) {
          assert(
            constraints.hasBoundedHeight,
            'FastScrollRail measures its slices from its height: give it a '
            'bounded one (an Expanded, a SizedBox)',
          );
          final height = constraints.maxHeight;
          final slice = widget.letters.isEmpty
              ? 0.0
              : height / widget.letters.length;
          if (slice < FastScrollRail.minSlice) return const SizedBox.shrink();

          // How many slices one legible glyph needs. Everything in between
          // draws a dot, so the alphabet still reads as a ruler.
          final stride = (glyphHeight / slice).ceil().clamp(1, 4);

          return Semantics(
            identifier: widget.semanticsId,
            container: true,
            // Same boundary as the chip row: each letter is its own
            // button, and merged they become one rail-sized tap target
            // that jumps to whichever letter merged last.
            explicitChildNodes: true,
            label: 'Jump to a letter',
            child: GestureDetector(
              // Drag only: a tap belongs to the letter it lands on, and a
              // detector claiming both would take it from them.
              onVerticalDragStart: (details) =>
                  _reportAt(details.localPosition.dy, height),
              onVerticalDragUpdate: (details) =>
                  _reportAt(details.localPosition.dy, height),
              onVerticalDragEnd: (_) => setState(() => _dragging = null),
              onVerticalDragCancel: () => setState(() => _dragging = null),
              child: Column(
                children: <Widget>[
                  for (var i = 0; i < widget.letters.length; i++)
                    Expanded(
                      child: _RailLetter(
                        letter: widget.letters[i],
                        // The first and last always draw: a rail whose
                        // ends are dots names nothing.
                        drawn:
                            i % stride == 0 || i == widget.letters.length - 1,
                        active:
                            widget.letters[i] == (_dragging ?? widget.selected),
                        enabled:
                            widget.available.isEmpty ||
                            widget.available.contains(widget.letters[i]),
                        colors: colors,
                        semanticsId: widget.letterSemanticsId?.call(
                          widget.letters[i],
                        ),
                        onTap: () => widget.onLetter(widget.letters[i]),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RailLetter extends StatelessWidget {
  const _RailLetter({
    required this.letter,
    required this.drawn,
    required this.active,
    required this.enabled,
    required this.colors,
    required this.onTap,
    this.semanticsId,
  });

  final String letter;
  final bool drawn;
  final bool active;
  final bool enabled;
  final WaxColors colors;
  final VoidCallback onTap;
  final String? semanticsId;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? colors.accent
        : enabled
        ? colors.textSecondary
        : colors.textDisabled;
    return Semantics(
      identifier: semanticsId,
      button: true,
      label: 'Jump to $letter',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: drawn
              ? Text(
                  letter,
                  style: WaxType.caption.copyWith(
                    color: color,
                    fontWeight: active ? FontWeight.w700 : null,
                  ),
                )
              : Container(
                  width: 3,
                  height: 3,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: WaxRadius.pill,
                  ),
                ),
        ),
      ),
    );
  }
}

/// The rail letter a label belongs under: its first character upper-cased
/// for A to Z, and `#` for everything else (digits, brackets, scripts the
/// Latin alphabet has no row for).
///
/// This is the client half of the server's A-to-Z order, which folds case
/// the same way. Labels the Latin alphabet has no row for still sort and
/// still scroll; they simply read as `#`. Digits and brackets land there
/// and sort ahead of A, which is where the rail puts `#`; scripts beyond
/// ASCII read as `#` too but sort after Z, so a jump to `#` finds the
/// first of them rather than all of them. Naming a row per script is a
/// collation problem, not an index-screen one.
String fastScrollLetter(String label) {
  final trimmed = label.trimLeft();
  if (trimmed.isEmpty) return '#';
  final first = trimmed[0].toUpperCase();
  return first.codeUnitAt(0) >= 0x41 && first.codeUnitAt(0) <= 0x5A
      ? first
      : '#';
}

/// The conventional rail: `#` for everything that is not a letter, then A
/// to Z, matching the order the server's label sort produces.
const List<String> fastScrollLetters = <String>[
  '#',
  'A',
  'B',
  'C',
  'D',
  'E',
  'F',
  'G',
  'H',
  'I',
  'J',
  'K',
  'L',
  'M',
  'N',
  'O',
  'P',
  'Q',
  'R',
  'S',
  'T',
  'U',
  'V',
  'W',
  'X',
  'Y',
  'Z',
];
