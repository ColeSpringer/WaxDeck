import 'package:flutter/material.dart';
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
    final colorScheme = Theme.of(context).colorScheme;
    final stars = rating == null ? 0 : (rating! / 20).round().clamp(0, 5);
    final label = starLabel(starred);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // excludeSemantics collapses the control to one accessibility
        // node: the wrapper's label plus the button's own (tooltip-fed)
        // node would otherwise announce twice.
        Semantics(
          identifier: SemanticsIds.starButton(idPrefix),
          label: label,
          button: true,
          excludeSemantics: true,
          onTap: enabled ? () => onStar(!starred) : null,
          child: IconButton(
            key: Key(SemanticsIds.starButton(idPrefix)),
            tooltip: label,
            color: starred ? colorScheme.primary : null,
            onPressed: enabled ? () => onStar(!starred) : null,
            icon: Icon(starred ? Icons.favorite : Icons.favorite_border),
          ),
        ),
        const SizedBox(width: 8),
        for (var n = 1; n <= 5; n++)
          Semantics(
            identifier: SemanticsIds.rating(idPrefix, n),
            label: ratingLabel(n),
            button: true,
            excludeSemantics: true,
            onTap: enabled ? () => onRate(n == stars ? null : n * 20) : null,
            child: IconButton(
              key: Key(SemanticsIds.rating(idPrefix, n)),
              visualDensity: VisualDensity.compact,
              color: n <= stars ? colorScheme.primary : null,
              onPressed: enabled
                  ? () => onRate(n == stars ? null : n * 20)
                  : null,
              icon: Icon(n <= stars ? Icons.star : Icons.star_border),
            ),
          ),
      ],
    );
  }
}
