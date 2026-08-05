import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../media_view.dart';
import '../player/now_playing_controller.dart';
import '../queue/queue_state.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';

/// A computed list of playable tracks (an instant mix or a
/// similar-tracks answer) in play order, with the answering engine
/// shown as a basis chip. Rows play on tap, like library rows.
class TrackListScreen extends ConsumerWidget {
  const TrackListScreen({
    super.key,
    required this.title,
    required this.basis,
    required this.items,
    required this.idPrefix,
  });

  final String title;
  final MixBasis basis;
  final List<ItemSummary> items;

  /// Scope for this screen's Semantics identifiers - the rows and the
  /// basis readout alike. A mix and a similar-tracks answer are both
  /// this screen, so an unscoped handle would let a spec that opened
  /// the wrong one pass anyway.
  final String idPrefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(artworkStoreProvider);
    return WaxScaffold(
      title: title,
      largeTitle: false,
      // An answer has no location of its own (it rides an in-memory
      // payload), so there is nothing under it on a cold open: home is
      // where a dropped stack lands.
      onBack: () => context.leave(fallback: WaxRoute.home),
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              WaxSpace.s16,
              WaxSpace.s12,
              WaxSpace.s16,
              WaxSpace.s4,
            ),
            // Which engine answered, in the words the contract uses. A
            // chip rather than a subtitle: it is a property of the
            // answer, not part of its name. The wire word is drawn and
            // the sentence is spoken - "sonic" alone says nothing aloud.
            child: Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                identifier: SemanticsIds.mixBasis(idPrefix),
                label: 'Answered by the ${basis.wireName} engine',
                excludeSemantics: true,
                child: CodecChip(
                  basis.wireName,
                  emphasis: basis == MixBasis.sonic,
                ),
              ),
            ),
          ),
        ),
        if (items.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              glyph: WaxIcons.music,
              title: 'Nothing found',
              message: 'This answer came back empty. Try another track.',
            ),
          )
        else
          SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return MediaListRow(
                data: MediaTileData(
                  title: item.title,
                  subtitle: item.artist,
                  artwork: waxArtwork(store, item.artUrl),
                  domain: waxDomainOf(item.mediaType),
                  shape: waxShapeOf(item.mediaType),
                  trailingText: formatTimecode(
                    Duration(milliseconds: item.durationMs),
                  ),
                  // Addressed by position: this is a running order, and
                  // the same item can answer more than one mix.
                  semanticsId: SemanticsIds.scopedItem(idPrefix, index),
                ),
                // Tapping a row plays the answer from there, so the rest
                // of the list is the queue.
                onTap: () {
                  ref
                      .read(nowPlayingProvider.notifier)
                      .play(
                        items,
                        source: QueueSource(
                          kind: QueueSourceKind.mix,
                          label: title,
                        ),
                        startIndex: index,
                      );
                  context.push(WaxRoute.nowPlaying);
                },
              );
            },
          ),
      ],
    );
  }
}
