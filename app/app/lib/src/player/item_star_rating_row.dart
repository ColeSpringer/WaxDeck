import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'play_state_controller.dart';
import 'star_rating_row.dart';

/// One item's star toggle and rating row, backed by its play state.
///
/// The twin of [EntityStarRatingRow] for items rather than entities: the
/// player wears it under the title, and a book's header wears it beside
/// Resume. Both edit the same state through the same optimistic
/// controller.
class ItemStarRatingRow extends ConsumerWidget {
  const ItemStarRatingRow({required this.pid, this.idPrefix = '', super.key});

  final String pid;

  /// Prefix on the keys and identifiers, so two rows on one screen stay
  /// separately addressable. Empty is the player's, which the e2e suite
  /// already drives by the bare handles.
  final String idPrefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A failed mutation rolls the value back and lands here as an error
    // still carrying that previous value; tell the user the tap did not
    // stick while the row keeps rendering the real state.
    ref.listen(playStateControllerProvider(pid), (previous, next) {
      if (next.hasError && !next.isLoading) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Could not save that change')),
          );
      }
    });
    final playState = ref.watch(playStateControllerProvider(pid)).value;
    final notifier = ref.read(playStateControllerProvider(pid).notifier);

    return StarRatingRow(
      starred: playState?.starred ?? false,
      rating: playState?.rating,
      enabled: playState != null,
      onStar: notifier.setStarred,
      onRate: notifier.rate,
      idPrefix: idPrefix,
      starLabel: (starred) => starred ? 'Unstar' : 'Star',
      ratingLabel: (n) => '$n star rating',
    );
  }
}
