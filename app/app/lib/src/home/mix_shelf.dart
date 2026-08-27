import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../discovery/discovery_actions.dart';
import '../l10n/l10n.dart';
import '../media_view.dart';
import '../player/now_playing_controller.dart';
import '../providers.dart';
import '../queue/queue_state.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'home_shelves.dart';
import 'item_shelf.dart';

/// The "Made for you" shelf: one card per mix seed the caller's own
/// listening suggests. Shared by home and the music hub - the cards are
/// music by construction (top genres and top artists are music stats),
/// so the hub mounts the same shelf rather than growing a scoped twin.
class MixShelf extends ConsumerWidget {
  const MixShelf({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(mixCardsProvider);
    if (!state.hasValue) {
      // The same rule ItemShelf follows: loading shows the shelf's
      // ghost after the shared delay rather than collapsing. A failed
      // read hides, though - mixes are an extra, and a listener with no
      // history is indistinguishable from one on purpose.
      if (state.hasError) {
        return const SliverToBoxAdapter(child: SizedBox.shrink());
      }
      return SliverToBoxAdapter(
        child: DelayedShelfSkeleton(title: l10n.homeMixesTitle),
      );
    }
    final cards = state.value ?? const <MixCard>[];
    if (cards.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final store = ref.watch(artworkStoreProvider);
    final tiles = <MediaTileData>[
      for (var i = 0; i < cards.length; i++)
        MediaTileData(
          title: cards[i].titleOf(l10n),
          subtitle: l10n.discoveryInstantMixTitle,
          // The card clamps every line, so the full name lives on the
          // hover tooltip, as on every other home shelf.
          tooltip: cards[i].titleOf(l10n),
          artwork: waxArtwork(store, cards[i].artUrl),
          domain: WaxDomain.music,
          semanticsId: SemanticsIds.homeMix(i),
        ),
    ];
    return SliverToBoxAdapter(
      child: Semantics(
        // A region rather than a node that swallows its subtree; see
        // `ItemShelf` for why.
        container: true,
        explicitChildNodes: true,
        identifier: SemanticsIds.shelf('mixes'),
        child: Padding(
          padding: const EdgeInsets.only(bottom: WaxSpace.s24),
          child: ShelfRow(
            title: l10n.homeMixesTitle,
            items: tiles,
            onTapItem: (tile) {
              final at = tiles.indexOf(tile);
              if (at < 0) return;
              unawaited(playMixCard(context, ref, cards[at]));
            },
          ),
        ),
      ),
    );
  }
}

/// Mints a mix from a card's seed and plays it.
///
/// The same landing the instant-mix sheet uses: the track list is pushed
/// so the running order is on screen, and playback starts in the dock.
/// The mix's own `basis` rides the list, which is what tells the truth
/// about whether this was sonic or metadata - no copy here may imply
/// otherwise.
Future<void> playMixCard(
  BuildContext context,
  WidgetRef ref,
  MixCard card,
) async {
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final title = card.titleOf(l10n);
  final playback = ref.read(nowPlayingProvider.notifier);
  try {
    final mix = await ref
        .read(repositoryProvider)
        .createInstantMix(
          seedPid: card.seedPid,
          genre: card.genre,
          adventurousness: ref.read(mixAdventurousnessProvider),
          size: instantMixSize,
        );
    if (mix.items.isEmpty) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.homeMixEmpty(title))));
      return;
    }
    // A mix takes a moment to build, and the tap that asked for it is a
    // play command: it is honoured whether or not the card is still on
    // screen, and the deck bar is where it shows up. What is conditional
    // is the navigation - the router outlives this widget, so pushing
    // unguarded would slam a track list over whichever destination the
    // visitor walked to meanwhile.
    playback.play(
      mix.items,
      // A stored name or none at all, never the card's sentence: the
      // label is stored with the queue and outlives the language it was
      // built in, and a seeded mix has no name to store.
      source: QueueSource(kind: QueueSourceKind.mix, label: card.queueLabel),
    );
    if (!context.mounted) return;
    unawaited(
      router.push<void>(
        WaxRoute.tracks,
        extra: TrackListArgs(
          title: title,
          sourceLabel: card.queueLabel,
          basis: mix.basis,
          items: mix.items,
          idPrefix: 'mix',
        ),
      ),
    );
  } on WaxDeckApiException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
  }
}
