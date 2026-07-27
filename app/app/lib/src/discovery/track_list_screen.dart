import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../artwork/artwork_box.dart';
import '../media_icons.dart';
import '../player/now_playing_controller.dart';
import '../queue/queue_state.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';

/// A computed list of playable tracks (an instant mix or a
/// similar-tracks answer) in play order, with the answering engine
/// shown as a basis chip. Rows play on tap, like library rows.
class TrackListScreen extends StatelessWidget {
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

  /// Prefix for the rows' Semantics identifiers and keys.
  final String idPrefix;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Chip(
              key: const Key('discovery-basis'),
              avatar: Icon(
                basis == MixBasis.sonic
                    ? Icons.graphic_eq
                    : Icons.library_music_outlined,
                size: 18,
              ),
              label: Text(basis.wireName),
              visualDensity: VisualDensity.compact,
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('Nothing found'))
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) => _TrackRow(
                      idPrefix: idPrefix,
                      index: index,
                      items: items,
                      title: title,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TrackRow extends ConsumerWidget {
  const _TrackRow({
    required this.idPrefix,
    required this.index,
    required this.items,
    required this.title,
  });

  final String idPrefix;
  final int index;

  /// The whole answer, in the order it is shown: tapping a row plays it
  /// from there, so the rest of the list is the queue.
  final List<ItemSummary> items;

  /// The list's own name, which is what the queue was built from.
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = items[index];
    final colorScheme = Theme.of(context).colorScheme;
    final artUrl = item.artUrl;
    final placeholder = ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        mediaFallbackIcon(item.mediaType),
        color: colorScheme.onSurfaceVariant,
      ),
    );
    return Semantics(
      identifier: SemanticsIds.scopedItem(idPrefix, index),
      label: item.artist == null
          ? item.title
          : '${item.title} by ${item.artist}',
      button: true,
      child: ListTile(
        key: Key(SemanticsIds.scopedItem(idPrefix, index)),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 48,
            height: 48,
            child: ArtworkBox(artUrl: artUrl, placeholder: placeholder),
          ),
        ),
        title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: item.artist == null
            ? null
            : Text(item.artist!, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () {
          ref
              .read(nowPlayingProvider.notifier)
              .play(
                items,
                source: QueueSource(kind: QueueSourceKind.mix, label: title),
                startIndex: index,
              );
          context.push(WaxRoute.nowPlaying);
        },
      ),
    );
  }
}
