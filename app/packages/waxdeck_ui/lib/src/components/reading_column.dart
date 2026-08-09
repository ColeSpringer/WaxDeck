import 'package:flutter/widgets.dart';

import '../tokens/spacing.dart';

/// Caps a single-column reading context at [WaxSpace.readingWidth] and
/// keeps it against the leading edge.
///
/// The alignment is the whole point, and it is why this exists as a
/// widget rather than as a `ConstrainedBox` typed out at each site. A
/// sliver hands its child a *tight* cross-axis width - both
/// `SliverToBoxAdapter` and `SliverList` do, through
/// `SliverConstraints.asBoxConstraints` - and `ConstrainedBox` enforces
/// its own constraints against the incoming ones rather than over them,
/// so under a tight width it resolves back to that width and caps
/// nothing at all. Every page that reached for one directly got a cap
/// that did nothing on the wide windows it was written for. An [Align]
/// passes loose constraints down, which is what makes the cap bite.
///
/// [AlignmentDirectional.topStart] rather than centred: a settings page
/// whose rows slide to the middle of a wide window reads as a dialog
/// that lost its frame, and every page that already caps its column
/// sits against the leading edge. Directional on purpose - the column
/// follows the reading direction, so it is on the right under RTL, and
/// a "fix" to [Alignment.topLeft] would pin it to the wrong side of
/// half the world's scripts.
///
/// The loose width is the one thing to know about the child. A child
/// that sizes to its content now measures its content rather than the
/// window: a `Column(crossAxisAlignment: start)` of nothing but short
/// `Text` collapses to the widest line instead of filling the column.
/// Rows built from this package fill on their own, which is why the
/// screens read the same; a column of bare text does not, and wants
/// `CrossAxisAlignment.stretch`. The height is untouched - [Align]
/// loosens the minimum and keeps the maximum, so a `Spacer` or an
/// `Expanded` works exactly where it worked before and fails exactly
/// where it failed before, which is under a sliver with no bounded
/// height.
class ReadingColumn extends StatelessWidget {
  const ReadingColumn({required this.child, this.maxWidth, super.key});

  final Widget child;

  /// Overrides [WaxSpace.readingWidth] for a column that is narrower by
  /// nature - a form of short fields rather than a column of prose.
  final double? maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.topStart,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth ?? WaxSpace.readingWidth),
      child: child,
    ),
  );
}
