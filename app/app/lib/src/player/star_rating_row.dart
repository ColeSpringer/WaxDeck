import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../shell/semantics_ids.dart';

/// Star toggle plus the five-star rating row, shared by the item
/// controls and their artist/album twin. Ratings map star N to N times
/// 20 on the 0 to 100 wire scale; tapping the current rating again
/// clears it, which [onRate] receives as null.
///
/// Presentation only: it holds no state and knows no controller, so the
/// two surfaces share one set of interaction rules (the clear-on-repeat
/// gesture, the disabled-while-loading pass, the single accessibility
/// node per control) instead of two drifting copies.
///
/// The toggle is a heart and the rating is stars, on purpose: they are
/// different verbs ("keep this" against "grade this"), and one mark for
/// both would read as a six-star row.
class StarRatingRow extends StatelessWidget {
  const StarRatingRow({
    super.key,
    required this.starred,
    required this.rating,
    required this.enabled,
    required this.onStar,
    required this.onRate,
    required this.idPrefix,
    required this.starLabel,
    required this.ratingLabel,
  });

  final bool starred;

  /// The stored rating, 0 to 100; null when unrated.
  final int? rating;

  /// False while the backing state is still loading, which disables
  /// every control rather than letting a tap race the first fetch.
  final bool enabled;

  final ValueChanged<bool> onStar;
  final ValueChanged<int?> onRate;

  /// Prefix on the widget keys and Semantics identifiers
  /// (`{prefix}star-button`, `{prefix}rating-N`), so the two rows stay
  /// separately addressable in tests.
  final String idPrefix;

  /// Accessibility label for the star control, given the current state.
  final String Function(bool starred) starLabel;

  /// Accessibility label for the Nth rating star.
  final String Function(int n) ratingLabel;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final stars = rating == null ? 0 : (rating! / 20).round().clamp(0, 5);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        WaxIconButton(
          key: Key(SemanticsIds.starButton(idPrefix)),
          glyph: WaxIcons.heart,
          active: starred,
          label: starLabel(starred),
          semanticsId: SemanticsIds.starButton(idPrefix),
          color: starred ? colors.accent : colors.textSecondary,
          onPressed: enabled ? () => onStar(!starred) : null,
        ),
        const SizedBox(width: WaxSpace.s8),
        for (var n = 1; n <= 5; n++)
          WaxIconButton(
            key: Key(SemanticsIds.rating(idPrefix, n)),
            glyph: WaxIcons.star,
            active: n <= stars,
            label: ratingLabel(n),
            semanticsId: SemanticsIds.rating(idPrefix, n),
            color: n <= stars ? colors.accent : colors.textSecondary,
            onPressed: enabled
                ? () => onRate(n == stars ? null : n * 20)
                : null,
          ),
      ],
    );
  }
}
