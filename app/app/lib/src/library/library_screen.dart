import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../artwork/artwork_box.dart';
import '../artwork/artwork_precache.dart';
import '../auth/auth_controller.dart';
import '../media_icons.dart';
import '../player/now_playing_controller.dart';
import '../queue/queue_state.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../sync/sync_providers.dart';
import '../uploads/add_to_library.dart';
import '../uploads/audio_drop_area.dart';
import 'library_controller.dart';

/// Artwork grid over the whole library with a media-type filter, cursor
/// paged with infinite scroll, plus a continue-listening banner.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  void _openPlayer(BuildContext context, WidgetRef ref, ItemSummary item) {
    // Audiobooks route through their detail screen (resume, chapters,
    // settings); music and downloaded podcast episodes play directly.
    if (item.mediaType == MediaType.audiobook) {
      context.go(WaxRoute.book(item.pid));
      return;
    }
    // One item: this grid mixes media types and pages as it scrolls, so
    // there is no list here worth calling a queue. The indexes that
    // replace it queue their own.
    ref.read(nowPlayingProvider.notifier).play(
      [item],
      source: QueueSource(
        kind: QueueSourceKind.single,
        label: item.title,
        pid: item.pid,
      ),
    );
    context.push(WaxRoute.nowPlaying);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryControllerProvider);
    final filter = ref.watch(libraryFilterProvider);
    final resume = ref.watch(continueListeningProvider).value;
    final canUpload =
        ref.watch(authControllerProvider).value?.user?.uploadEnabled ?? false;

    return Scaffold(
      // Adding audio is a primary action, so it gets a button here
      // rather than living inside the curation menu. Podcasts are added
      // by subscribing to a feed (their own screen), so the button is
      // hidden on that filter — and everywhere for accounts without
      // upload rights, which every path behind it needs (URL
      // acquisition included).
      floatingActionButton: filter == LibraryFilter.podcasts || !canUpload
          ? null
          : Semantics(
              identifier: SemanticsIds.addToLibrary,
              label: 'Add music',
              button: true,
              child: FloatingActionButton(
                key: const Key(SemanticsIds.addToLibrary),
                tooltip: 'Add to library',
                onPressed: () => showAddToLibrarySheet(
                  context,
                  ref,
                  initial: filter.mediaType,
                ),
                child: const Icon(Icons.add),
              ),
            ),
      // No navigation of its own: the shell's chrome owns where a visitor
      // can go at every width, and this row was the stand-in that held
      // the compact case until the account menu existed.
      appBar: AppBar(title: const Text('WaxDeck')),
      body: AudioDropArea(
        enabled: canUpload,
        onDropped: (files) =>
            uploadPickedFiles(context, ref, files, initial: filter.mediaType),
        child: Column(
          children: [
            if (ref.watch(offlineProvider))
              Semantics(
                identifier: SemanticsIds.offlineBanner,
                child: Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Offline: showing the local library',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
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
                onTap: () => _openPlayer(context, ref, resume),
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
    final precacher = ref.watch(artworkPrecacherProvider);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // The delegate's own arithmetic, including its clamp: a pane too
        // narrow for one column still lays out one, and dividing by the
        // zero column count a naive ceil gives would make every number
        // after it infinite.
        final pane = constraints.hasBoundedWidth
            ? math.max(0.0, constraints.maxWidth - 32)
            : _gridExtent;
        final columns = math.max(
          1,
          (pane / (_gridExtent + _gridSpacing)).ceil(),
        );
        final cell = math.max(
          1.0,
          (pane - _gridSpacing * (columns - 1)) / columns,
        );
        final rowHeight = cell / _gridRatio + _gridSpacing;
        final ratio = MediaQuery.devicePixelRatioOf(context);
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            final metrics = notification.metrics;
            if (metrics.pixels >= metrics.maxScrollExtent - 400) {
              ref.read(libraryControllerProvider.notifier).loadMore();
            }
            if (notification is ScrollEndNotification) {
              // Where the viewport ends, from the same geometry the grid
              // lays out with: the first row below the fold, and two
              // screenfuls of it. A scroll fraction would have named a
              // row inside the viewport, spending half the window on
              // covers that are already painted.
              final visibleRows = (metrics.viewportDimension / rowHeight)
                  .ceil();
              final firstBelow =
                  ((metrics.pixels / rowHeight).floor() + visibleRows) *
                  columns;
              precacher.warmAhead(
                urls: <String?>[
                  for (final item
                      in state.items
                          .skip(firstBelow)
                          .take(visibleRows * columns * 2))
                    item.artUrl,
                ],
                // The cell's width: the card gives its artwork the full
                // width and less than the full height, so the width is
                // the edge [ArtworkBox] measures itself by.
                px: (cell * ratio).ceil(),
              );
            }
            return false;
          },
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: _gridExtent,
              mainAxisSpacing: _gridSpacing,
              crossAxisSpacing: _gridSpacing,
              childAspectRatio: _gridRatio,
            ),
            // A grid cell holds no state worth keeping alive off screen,
            // and keeping them alive holds their decoded artwork with
            // them: the image cache is what remembers a scrolled-past
            // cover, and it has bounds.
            addAutomaticKeepAlives: false,
            itemCount: state.items.length + (state.loadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= state.items.length) {
                return const Center(child: CircularProgressIndicator());
              }
              final item = state.items[index];
              return _ItemCard(
                item: item,
                onTap: () => _openPlayer(context, ref, item),
              );
            },
          ),
        );
      },
    );
  }
}

const double _gridExtent = 200;
const double _gridSpacing = 12;
const double _gridRatio = 0.78;

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
        identifier: SemanticsIds.resumeBanner,
        label: 'Continue listening to ${item.title}',
        button: true,
        child: Card(
          key: const Key(SemanticsIds.resumeBanner),
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
      identifier: SemanticsIds.item(item.pid),
      label: item.artist == null
          ? item.title
          : '${item.title} by ${item.artist}',
      button: true,
      child: Card(
        key: ValueKey(SemanticsIds.item(item.pid)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ArtworkBox(artUrl: artUrl, placeholder: placeholder),
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
