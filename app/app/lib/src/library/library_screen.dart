import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../media_icons.dart';
import '../player/player_screen.dart';
import '../settings/settings_screen.dart';
import 'library_controller.dart';

/// Artwork grid over the whole library with a media-type filter, cursor
/// paged with infinite scroll, plus a continue-listening banner.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  void _openPlayer(BuildContext context, ItemSummary item) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => PlayerScreen(item: item)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryControllerProvider);
    final filter = ref.watch(libraryFilterProvider);
    final resume = ref.watch(continueListeningProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('WaxDeck'),
        actions: [
          Semantics(
            identifier: 'settings-open',
            child: IconButton(
              key: const Key('settings-open'),
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<LibraryFilter>(
                segments: [
                  for (final f in LibraryFilter.values)
                    ButtonSegment(value: f, label: Text(f.label)),
                ],
                selected: {filter},
                onSelectionChanged: (selection) => ref
                    .read(libraryFilterProvider.notifier)
                    .select(selection.first),
              ),
            ),
          ),
          if (resume != null)
            _ResumeBanner(
              item: resume,
              onTap: () => _openPlayer(context, resume),
            ),
          Expanded(
            child: switch (library) {
              AsyncData(:final value) => _grid(context, ref, value),
              AsyncError(:final error) => _errorView(context, ref, error),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }

  Widget _errorView(BuildContext context, WidgetRef ref, Object error) {
    final message = error is WaxDeckApiException
        ? error.message
        : 'Could not load the library';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => ref.invalidate(libraryControllerProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _grid(BuildContext context, WidgetRef ref, LibraryState state) {
    if (state.items.isEmpty) {
      return const Center(child: Text('Nothing here yet'));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.pixels >= metrics.maxScrollExtent - 400) {
          ref.read(libraryControllerProvider.notifier).loadMore();
        }
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.78,
        ),
        itemCount: state.items.length + (state.loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.items.length) {
            return const Center(child: CircularProgressIndicator());
          }
          final item = state.items[index];
          return _ItemCard(item: item, onTap: () => _openPlayer(context, item));
        },
      ),
    );
  }
}

class _ResumeBanner extends StatelessWidget {
  const _ResumeBanner({required this.item, required this.onTap});

  final ItemSummary item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Semantics(
        identifier: 'resume-banner',
        label: 'Continue listening to ${item.title}',
        button: true,
        child: Card(
          key: const Key('resume-banner'),
          color: colorScheme.secondaryContainer,
          child: ListTile(
            onTap: onTap,
            leading: Icon(Icons.play_circle, color: colorScheme.primary),
            title: const Text('Continue listening'),
            subtitle: Text(
              item.artist == null
                  ? item.title
                  : '${item.title} by ${item.artist}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
          ),
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, required this.onTap});

  final ItemSummary item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final artUrl = item.artUrl;
    final placeholder = ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          mediaFallbackIcon(item.mediaType),
          size: 48,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
    return Semantics(
      identifier: 'item-${item.pid}',
      label: item.artist == null
          ? item.title
          : '${item.title} by ${item.artist}',
      button: true,
      child: Card(
        key: ValueKey('item-${item.pid}'),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: artUrl == null
                    ? placeholder
                    : Image.network(
                        artUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => placeholder,
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.artist != null)
                      Text(
                        item.artist!,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
