import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
import '../library/item_menu.dart';
import '../player/now_playing_controller.dart';
import '../player/play_progress.dart';
import '../presenters/media_tiles.dart';
import '../providers.dart';
import '../queue/queue_state.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';

/// A computed list's rows: the answer as it was handed over, then the
/// same items as the catalog has them each time a sweep reads it again.
/// Keyed on the answer itself, so one per list pushed.
final trackListRowsProvider = AsyncNotifierProvider.autoDispose
    .family<TrackListRows, List<ItemSummary>, List<ItemSummary>>(
      TrackListRows.new,
    );

class TrackListRows extends AsyncNotifier<List<ItemSummary>> {
  TrackListRows(this.answer);

  final List<ItemSummary> answer;

  late List<ItemSummary> _held = answer;

  @override
  Future<List<ItemSummary>> build() async {
    // The answer was read a moment ago: opening the list asks nothing.
    if (ref.isFirstBuild) return _held;
    final repository = ref.read(repositoryProvider);
    final pids = {for (final row in _held) row.pid}.toList();
    final now = <String, ItemSummary>{};
    try {
      for (var at = 0; at < pids.length; at += itemLookupCap) {
        final resolved = await repository.resolveItems(
          pids.sublist(at, math.min(at + itemLookupCap, pids.length)),
        );
        for (final item in resolved.items) {
          now[ulidOf(item.pid)] = item;
        }
      }
    } on WaxDeckApiException {
      // Says nothing of the rows: they stand until the next sweep.
      return _held;
    }
    // In the answer's order; one the lookup does not name stays as held.
    return _held = [for (final row in _held) now[ulidOf(row.pid)] ?? row];
  }
}

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
    this.sourceLabel = '',
  });

  final String title;
  final MixBasis basis;
  final List<ItemSummary> items;

  /// The mix's own name, which the queue stores, and empty for a seeded
  /// one, whose provenance the queue words from the kind. Never a
  /// translated frame; see [TrackListArgs].
  final String sourceLabel;

  /// Scope for this screen's Semantics identifiers - the rows and the
  /// basis readout alike. A mix and a similar-tracks answer are both
  /// this screen, so an unscoped handle would let a spec that opened
  /// the wrong one pass anyway.
  final String idPrefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(artworkStoreProvider);
    final l10n = context.l10n;
    final items =
        ref.watch(trackListRowsProvider(this.items)).value ?? this.items;
    final windows = PlayWindows.ofItems(items);
    return WaxScaffold(
      title: title,
      largeTitle: false,
      // An answer has no location of its own (it rides an in-memory
      // payload), so there is nothing under it on a cold open: home is
      // where a dropped stack lands.
      onBack: () => context.back(fallback: WaxRoute.home),
      backSemanticsId: SemanticsIds.navBack,
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
                label: l10n.discoveryBasisSpoken(basis.wireName),
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
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              glyph: WaxIcons.music,
              title: l10n.discoveryEmptyTitle,
              message: l10n.discoveryEmptyMessage,
            ),
          )
        else
          SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return PlayCountBuilder(
                windows: windows,
                index: index,
                pid: item.pid,
                builder: (context, plays) => MediaListRow(
                  data: itemRowTile(
                    item,
                    l10n: l10n,
                    store: store,
                    // Addressed by position: this is a running order, and
                    // the same item can answer more than one mix.
                    semanticsId: SemanticsIds.scopedItem(idPrefix, index),
                    playCount: plays,
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
                            label: sourceLabel,
                          ),
                          startIndex: index,
                        );
                  },
                  onMore: () =>
                      unawaited(showItemMenuForSummary(context, ref, item)),
                ),
              );
            },
          ),
      ],
    );
  }
}
