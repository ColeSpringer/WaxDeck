import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
import '../music/music_controllers.dart';
import '../presenters/media_tiles.dart';
import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'item_shelf.dart';
import 'pin_action.dart';
import 'pinned_controller.dart';

/// The shelf of what this listener kept, second on home after Continue
/// listening.
///
/// The one user-curated shelf: every other one is a question the server
/// answers about the library, and this is a list somebody made. It draws
/// all of them rather than a dozen with a "Show all" door, because there
/// is no surface behind it that enumerates the same thing - the shelf is
/// the surface, and a pin that fell off the end would look like a pin
/// that failed.
///
/// Silent when there is nothing pinned, like every other shelf that can
/// be empty: a heading over an empty row is a reproach, and
/// "nothing pinned" is the state most libraries are in.
class PinnedShelf extends ConsumerWidget {
  const PinnedShelf({super.key});

  static const _shelf = 'pinned';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // Short-circuited on the stored list rather than on the resolved one,
    // so an account with nothing pinned costs no round trip and no
    // skeleton: the pids are already in hand.
    if (ref.watch(pinnedEntitiesProvider).isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final async = ref.watch(pinnedCardsProvider);
    if (!async.hasValue) {
      if (async.hasError) {
        return SliverToBoxAdapter(
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            identifier: SemanticsIds.shelf(_shelf),
            child: Padding(
              padding:
                  WaxSizeClass.of(context).gutter +
                  const EdgeInsets.only(bottom: WaxSpace.s24),
              child: SectionHeader(
                title: l10n.homePinnedTitle,
                actionLabel: l10n.homeShelfRetry,
                onAction: () => ref.invalidate(pinnedCardsProvider),
              ),
            ),
          ),
        );
      }
      return SliverToBoxAdapter(
        child: DelayedShelfSkeleton(title: l10n.homePinnedTitle),
      );
    }
    final cards = async.value ?? const <EntityCard>[];
    // Every pin can have departed, which is a resolved answer of nothing
    // rather than an error: the shelf goes quiet exactly as it does when
    // nothing is pinned.
    if (cards.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final store = ref.watch(artworkStoreProvider);
    final repository = ref.watch(repositoryProvider);
    final tiles = <MediaTileData>[
      for (final card in cards)
        pinnedCardTile(
          card,
          l10n: l10n,
          store: store,
          repository: repository,
          semanticsId: SemanticsIds.shelfCard(_shelf, card.pid),
        ),
    ];

    return SliverToBoxAdapter(
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        identifier: SemanticsIds.shelf(_shelf),
        child: Padding(
          padding: const EdgeInsets.only(bottom: WaxSpace.s24),
          child: ShelfRow(
            title: l10n.homePinnedTitle,
            items: tiles,
            // By position, like every other shelf here: a tile carries no
            // value equality and two releases can share a title.
            onTapItem: (tile) {
              final at = tiles.indexOf(tile);
              if (at < 0) return;
              // The card's own title rides along: it is the entity's
              // name, which is the one thing the destination cannot
              // work out from the items it loads.
              unawaited(
                context.push(_locationOf(cards[at]), extra: cards[at].title),
              );
            },
            // The shelf is where somebody will try to unpin, so the card
            // carries the gesture: long press on touch, right-click with
            // a pointer. Without it a pin could only be undone from the
            // screen it was made on, which is the surface a listener
            // pinned precisely so they would not have to find again.
            onMoreItem: (tile) {
              final at = tiles.indexOf(tile);
              if (at < 0) return;
              unawaited(_unpin(context, ref, cards[at]));
            },
          ),
        ),
      ),
    );
  }

  /// A sheet rather than an immediate unpin: the gesture that opens it is
  /// a long press or a right-click, neither of which announces what it is
  /// about to do, and a card that vanished under a slipped press would
  /// leave a listener guessing what they had lost.
  Future<void> _unpin(
    BuildContext context,
    WidgetRef ref,
    EntityCard card,
  ) async {
    final colors = WaxColors.of(context);
    final chosen = await showWaxSheet<bool>(
      context: context,
      backgroundColor: colors.surface2,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            WaxSpace.s16,
            0,
            WaxSpace.s16,
            WaxSpace.s24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SectionHeader(
                title: card.title,
                overline: pinnedCardCaption(sheetContext.l10n, card),
              ),
              WaxOptionRow(
                title: sheetContext.l10n.homeUnpinAction,
                glyph: WaxIcons.home,
                semanticsId: SemanticsIds.entityPin,
                onTap: () => Navigator.of(sheetContext).pop(true),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen != true || !context.mounted) return;
    await togglePin(context, ref, card.pid, label: card.title);
  }

  /// Where a card opens. All pushed: every one of these is declared
  /// under its own domain, so `go` would rebuild that ancestry and throw
  /// home away.
  static String _locationOf(EntityCard card) => switch (card.kind) {
    EntityCardKind.album => WaxRoute.musicBucket(
      MusicDimension.albums,
      card.pid,
    ),
    EntityCardKind.artist => WaxRoute.musicBucket(
      MusicDimension.artists,
      card.pid,
    ),
    EntityCardKind.releaseGroup => WaxRoute.musicBucket(
      MusicDimension.releaseGroups,
      card.pid,
    ),
    EntityCardKind.playlist => WaxRoute.playlist(card.pid),
    EntityCardKind.podcast => WaxRoute.show(card.pid),
    EntityCardKind.book => WaxRoute.book(card.pid),
  };
}
