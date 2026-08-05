import 'package:waxdeck_ui/waxdeck_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'entity_play_state_controller.dart';
import 'star_rating_row.dart';

/// Star toggle plus the five-star rating row for a catalog entity (an
/// artist or an album), the twin of the item row on the player screen.
///
/// An entity star is independent of its members': starring an album
/// leaves its tracks alone, and the row says so through [label] rather
/// than reading as a bulk action on the tracks below it.
class EntityStarRatingRow extends ConsumerWidget {
  const EntityStarRatingRow({
    super.key,
    required this.pid,
    required this.label,
  });

  /// The entity's API pid (`ar-...` or `al-...`).
  final String pid;

  /// What the controls act on, for the accessibility labels and
  /// tooltips: "album", "artist".
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A failed mutation rolls the value back and lands here as an error
    // still carrying that previous value; tell the user the tap did not
    // stick while the row keeps rendering the real state.
    ref.listen(entityPlayStateControllerProvider(pid), (previous, next) {
      if (next.hasError && !next.isLoading) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Could not save that change')),
          );
      }
    });
    final playState = ref.watch(entityPlayStateControllerProvider(pid)).value;
    final notifier = ref.read(entityPlayStateControllerProvider(pid).notifier);

    return StarRatingRow(
      starred: playState?.starred ?? false,
      rating: playState?.rating,
      enabled: playState != null,
      onStar: notifier.setStarred,
      onRate: notifier.rate,
      idPrefix: 'entity-',
      starLabel: (starred) =>
          starred ? 'Unstar this $label' : 'Star this $label',
      ratingLabel: (n) => '$n star $label rating',
    );
  }
}
