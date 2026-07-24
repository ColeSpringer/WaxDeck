import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../admin/audit_screen.dart';
import '../admin/backups_screen.dart';
import '../admin/migrate_screen.dart';
import '../admin/trash_screen.dart';
import '../admin/users_screen.dart';
import '../auth/auth_controller.dart';
import '../books/book_screen.dart';
import '../health/diagnostics_screen.dart';
import '../health/health_screen.dart';
import '../media_icons.dart';
import '../organize/organize_screen.dart';
import '../player/player_screen.dart';
import '../playlists/playlists_screen.dart';
import '../podcasts/podcasts_screen.dart';
import '../radio/radio_screen.dart';
import '../review/review_screen.dart';
import '../settings/settings_screen.dart';
import '../stats/stats_screen.dart';
import '../sync/sync_providers.dart';
import '../tools/tasks_screen.dart';
import '../uploads/add_to_library.dart';
import '../uploads/audio_drop_area.dart';
import '../uploads/uploads_screen.dart';
import 'library_controller.dart';

/// Curation surfaces reachable from the app bar menu. Administrators
/// see all of them; everyone else only their own uploads — and only
/// while they hold upload rights, without which the uploads screen is
/// an empty list they can do nothing on.
enum _CurationDestination {
  review('curation-review', 'Review queue', adminOnly: true),
  uploads('curation-uploads', 'Uploads', adminOnly: false, needsUpload: true),
  health('curation-health', 'Health', adminOnly: true),
  diagnostics('curation-diagnostics', 'Diagnostics', adminOnly: true),
  organize('curation-organize', 'Organize', adminOnly: true),
  tasks('curation-tasks', 'Tasks', adminOnly: true),
  users('curation-users', 'Users', adminOnly: true),
  audit('curation-audit', 'Audit log', adminOnly: true),
  backups('curation-backups', 'Backups', adminOnly: true),
  trash('curation-trash', 'Trash', adminOnly: true),
  migrate('curation-migrate', 'Import from another server', adminOnly: true);

  const _CurationDestination(
    this.id,
    this.label, {
    required this.adminOnly,
    this.needsUpload = false,
  });

  final String id;
  final String label;
  final bool adminOnly;

  /// Hidden without effective upload rights (admins always hold
  /// them).
  final bool needsUpload;

  Widget screen() => switch (this) {
    review => const ReviewScreen(),
    uploads => const UploadsScreen(),
    health => const HealthScreen(),
    diagnostics => const DiagnosticsScreen(),
    organize => const OrganizeScreen(),
    tasks => const TasksScreen(),
    users => const UsersScreen(),
    audit => const AuditScreen(),
    backups => const BackupsScreen(),
    trash => const TrashScreen(),
    migrate => const MigrateScreen(),
  };
}

/// Artwork grid over the whole library with a media-type filter, cursor
/// paged with infinite scroll, plus a continue-listening banner.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  void _openPlayer(BuildContext context, ItemSummary item) {
    // Audiobooks route through their detail screen (resume, chapters,
    // settings); music and downloaded podcast episodes play directly.
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
              identifier: 'add-to-library',
              label: 'Add music',
              button: true,
              child: FloatingActionButton(
                key: const Key('add-to-library'),
                tooltip: 'Add to library',
                onPressed: () => showAddToLibrarySheet(
                  context,
                  ref,
                  initial: filter.mediaType,
                ),
                child: const Icon(Icons.add),
              ),
            ),
      appBar: AppBar(
        title: const Text('WaxDeck'),
        actions: [
          Semantics(
            identifier: 'curation-menu',
            label: 'Curation',
            child: PopupMenuButton<_CurationDestination>(
              key: const Key('curation-menu'),
              tooltip: 'Curation',
              icon: const Icon(Icons.build_outlined),
              onSelected: (destination) => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => destination.screen()),
              ),
              itemBuilder: (context) {
                final user = ref.read(authControllerProvider).value?.user;
                final isAdmin = user?.roles.contains('admin') ?? false;
                final uploads = user?.uploadEnabled ?? false;
                return [
                  for (final destination in _CurationDestination.values)
                    if ((isAdmin || !destination.adminOnly) &&
                        (uploads || !destination.needsUpload))
                      PopupMenuItem(
                        value: destination,
                        child: Semantics(
                          identifier: destination.id,
                          child: Text(
                            destination.label,
                            key: ValueKey(destination.id),
                          ),
                        ),
                      ),
                ];
              },
            ),
          ),
          Semantics(
            identifier: 'open-stats',
            child: IconButton(
              key: const Key('open-stats'),
              tooltip: 'Listening stats',
              icon: const Icon(Icons.insights),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const StatsScreen()),
              ),
            ),
          ),
          Semantics(
            identifier: 'playlists-open',
            child: IconButton(
              key: const Key('playlists-open'),
              tooltip: 'Playlists',
              icon: const Icon(Icons.queue_music),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PlaylistsScreen(),
                ),
              ),
            ),
          ),
          Semantics(
            identifier: 'radio-open',
            child: IconButton(
              key: const Key('radio-open'),
              tooltip: 'Radio',
              icon: const Icon(Icons.radio),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const RadioScreen()),
              ),
            ),
          ),
          Semantics(
            identifier: 'podcasts-open',
            child: IconButton(
              key: const Key('podcasts-open'),
              tooltip: 'Podcasts',
              icon: const Icon(Icons.podcasts),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PodcastsScreen()),
              ),
            ),
          ),
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
      body: AudioDropArea(
        enabled: canUpload,
        onDropped: (files) =>
            uploadPickedFiles(context, ref, files, initial: filter.mediaType),
        child: Column(
          children: [
            if (ref.watch(offlineProvider))
              Semantics(
                identifier: 'offline-banner',
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
