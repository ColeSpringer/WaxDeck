import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../books/book_screen.dart';
import '../media_icons.dart';
import '../player/player_screen.dart';
import '../shell/semantics_ids.dart';
import 'browse_controller.dart';

/// Browse the library by dimension: a tab per dimension listing its
/// buckets with counts, each opening the items in it. Genre labels are
/// the server's canonical spelling, so the tab shows one "Hip Hop"
/// rather than the several spellings the files carry.
class BrowseScreen extends StatelessWidget {
  const BrowseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const dimensions = BrowseDimension.values;
    return DefaultTabController(
      length: dimensions.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Browse'),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              for (final d in dimensions)
                Semantics(
                  identifier: SemanticsIds.browseTab(d.wireName),
                  child: Tab(
                    key: Key(SemanticsIds.browseTab(d.wireName)),
                    text: d.label,
                  ),
                ),
            ],
          ),
        ),
        body: TabBarView(
          children: [for (final d in dimensions) _BucketList(dimension: d)],
        ),
      ),
    );
  }
}

class _BucketList extends ConsumerWidget {
  const _BucketList({required this.dimension});

  final BrowseDimension dimension;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(browseControllerProvider(dimension));
    return switch (state) {
      AsyncData(:final value) => _list(context, ref, value),
      AsyncError(:final error) => _error(context, ref, error),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Widget _error(BuildContext context, WidgetRef ref, Object error) {
    final message = error is WaxDeckApiException
        ? error.message
        : 'Could not load ${dimension.label.toLowerCase()}';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () =>
                ref.invalidate(browseControllerProvider(dimension)),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, WidgetRef ref, BrowseState state) {
    if (state.buckets.isEmpty) {
      return Center(child: Text('No ${dimension.label.toLowerCase()} yet'));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.pixels >= metrics.maxScrollExtent - 400) {
          ref.read(browseControllerProvider(dimension).notifier).loadMore();
        }
        return false;
      },
      child: ListView.builder(
        itemCount: state.buckets.length + (state.loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.buckets.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final bucket = state.buckets[index];
          final id = SemanticsIds.browseBucket(dimension.wireName, index);
          return Semantics(
            identifier: id,
            label: '${bucket.label}, ${bucket.count} items',
            button: true,
            child: ListTile(
              key: Key(id),
              title: Text(
                bucket.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: bucket.unknown
                    ? TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      )
                    : null,
              ),
              trailing: Text(
                '${bucket.count}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      BrowseItemsScreen(dimension: dimension, bucket: bucket),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The items in one bucket of one dimension, paged.
class BrowseItemsScreen extends ConsumerWidget {
  const BrowseItemsScreen({
    super.key,
    required this.dimension,
    required this.bucket,
  });

  final BrowseDimension dimension;
  final FacetBucket bucket;

  void _open(BuildContext context, ItemSummary item) {
    if (item.mediaType == MediaType.audiobook) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => BookScreen(pid: item.pid)),
      );
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => PlayerScreen(item: item)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drill = (dimension: dimension, key: bucket.key);
    final state = ref.watch(browseItemsControllerProvider(drill));
    return Scaffold(
      appBar: AppBar(title: Text(bucket.label)),
      body: switch (state) {
        AsyncData(:final value) => _list(context, ref, drill, value),
        AsyncError(:final error) => Center(
          child: Text(
            error is WaxDeckApiException
                ? error.message
                : 'Could not load this ${dimension.singular}',
            textAlign: TextAlign.center,
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _list(
    BuildContext context,
    WidgetRef ref,
    BrowseDrill drill,
    BrowseItemsState state,
  ) {
    if (state.items.isEmpty) {
      return Center(child: Text('Nothing in this ${dimension.singular}'));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.pixels >= metrics.maxScrollExtent - 400) {
          ref.read(browseItemsControllerProvider(drill).notifier).loadMore();
        }
        return false;
      },
      child: ListView.builder(
        itemCount: state.items.length + (state.loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final item = state.items[index];
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
            identifier: SemanticsIds.browseItem(index),
            label: item.artist == null
                ? item.title
                : '${item.title} by ${item.artist}',
            button: true,
            child: ListTile(
              key: Key(SemanticsIds.browseItem(index)),
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
              title: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: item.artist == null
                  ? null
                  : Text(
                      item.artist!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              onTap: () => _open(context, item),
            ),
          );
        },
      ),
    );
  }
}
