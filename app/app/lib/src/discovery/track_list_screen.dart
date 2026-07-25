import 'package:flutter/material.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../media_icons.dart';
import '../player/player_screen.dart';
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
                      item: items[index],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.idPrefix,
    required this.index,
    required this.item,
  });

  final String idPrefix;
  final int index;
  final ItemSummary item;

  @override
  Widget build(BuildContext context) {
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
            child: artUrl == null
                ? placeholder
                : Image.network(
                    artUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => placeholder,
                  ),
          ),
        ),
        title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: item.artist == null
            ? null
            : Text(item.artist!, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => PlayerScreen(item: item)),
        ),
      ),
    );
  }
}
