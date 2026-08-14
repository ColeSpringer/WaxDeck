import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
import '../search/search_chrome.dart';
import '../shell/semantics_ids.dart';
import 'downloads_controller.dart';

/// What this overflow can do.
enum _DownloadsAction { removeFinished, refreshStale }

/// The surface over the download engine: what this device holds, what it
/// is fetching, and how to get the space back.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(downloadsProvider);
    // Watched here rather than in the rows: one subscription for the
    // screen, and the rows read the map out of it.
    final fractions =
        ref.watch(downloadProgressProvider).value ?? const <String, double>{};
    final downloads = state.value ?? DownloadsState.empty;

    return WaxScaffold(
      title: context.l10n.downloadsTitle,
      semanticsId: SemanticsIds.downloadsScreen,
      actions: <Widget>[
        if (downloads.entries.isNotEmpty) const _Overflow(),
        const SearchAction(),
      ],
      slivers: <Widget>[
        if (downloads.entries.isNotEmpty)
          SliverToBoxAdapter(child: _StorageHeader(downloads: downloads)),
        if (downloads.inFlight.isNotEmpty)
          SliverToBoxAdapter(
            child: _Transfers(
              entries: downloads.inFlight.toList(),
              fractions: fractions,
            ),
          ),
        switch (state) {
          AsyncData() when downloads.entries.isEmpty => SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: context.l10n.downloadsEmptyTitle,
              message: context.l10n.downloadsEmptyMessage,
              glyph: WaxIcons.downloads,
            ),
          ),
          AsyncData() => _Groups(downloads: downloads),
          AsyncError(:final error) => SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(
              title: context.l10n.downloadsLoadError,
              message: context.explain(error),
              onRetry: () => ref.invalidate(downloadsProvider),
            ),
          ),
          _ => const SliverToBoxAdapter(
            child: SkeletonShapes(shape: SkeletonShape.list),
          ),
        },
        const SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s32)),
      ],
    );
  }
}

/// What is used, by medium, and the way to reclaim all of it.
///
/// No device free space beside it: nothing in Dart answers how much room
/// a volume has left, and pinning a plugin for one number is a decision
/// of its own. What WaxDeck holds is the half it can be honest about and
/// the half a listener can act on.
class _StorageHeader extends ConsumerWidget {
  const _StorageHeader({required this.downloads});

  final DownloadsState downloads;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final sizeClass = WaxSizeClass.of(context);
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        sizeClass.gutter.horizontal / 2,
        WaxSpace.s8,
        sizeClass.gutter.horizontal / 2,
        WaxSpace.s16,
      ),
      child: Semantics(
        identifier: SemanticsIds.downloadsStorage,
        container: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: Text(
                    l10n.formatBytes(downloads.usedBytes),
                    style: WaxType.titleEntity.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                WaxButton(
                  label: l10n.downloadsClearAll,
                  kind: WaxButtonKind.text,
                  semanticsId: SemanticsIds.downloadsClearAll,
                  onPressed: () => unawaited(_confirmClear(context, ref)),
                ),
              ],
            ),
            const SizedBox(height: WaxSpace.s4),
            Wrap(
              spacing: WaxSpace.s8,
              runSpacing: WaxSpace.s8,
              children: <Widget>[
                for (final domain in downloads.byDomain)
                  CodecChip(
                    l10n.downloadsChip(
                      _mediumLabel(l10n, domain.mediaType),
                      l10n.formatBytes(domain.bytes),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    // Read before the dialog: this runs unawaited, so `ref` may be dead
    // by the time the answer comes back.
    final notifier = ref.read(downloadsProvider.notifier);
    final l10n = context.l10n;
    final freed = l10n.formatBytes(downloads.usedBytes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.downloadsClearTitle),
        content: Text(l10n.downloadsClearBody(freed)),
        actions: <Widget>[
          WaxButton(
            label: l10n.downloadsClearKeep,
            kind: WaxButtonKind.text,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          WaxButton(
            label: l10n.downloadsClearConfirm,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await notifier.removeAll();
  }
}

/// The two sweeps a manager offers, in the overflow because they act on
/// everything and a bar button that does is too easy to hit.
class _Overflow extends ConsumerWidget {
  const _Overflow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return WaxMenuButton<_DownloadsAction>(
      glyph: WaxIcons.more,
      label: l10n.downloadsOverflow,
      semanticsId: SemanticsIds.downloadsOverflow,
      items: <WaxMenuItem<_DownloadsAction>>[
        WaxMenuItem<_DownloadsAction>(
          value: _DownloadsAction.removeFinished,
          label: l10n.downloadsRemoveFinished,
          glyph: WaxIcons.check,
          semanticsId: SemanticsIds.downloadsRemoveFinished,
        ),
        WaxMenuItem<_DownloadsAction>(
          value: _DownloadsAction.refreshStale,
          label: l10n.downloadsRefreshStale,
          glyph: WaxIcons.refresh,
          semanticsId: SemanticsIds.downloadsRefresh,
        ),
      ],
      onSelected: (action) => unawaited(_run(context, ref, action)),
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    _DownloadsAction action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final notifier = ref.read(downloadsProvider.notifier);
    switch (action) {
      case _DownloadsAction.removeFinished:
        final removed = await notifier.removeFinishedEpisodes();
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                removed == 0
                    ? l10n.downloadsNoneFinished
                    : l10n.downloadsRemovedEpisodes(removed),
              ),
            ),
          );
      case _DownloadsAction.refreshStale:
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l10n.downloadsChecking)));
        await notifier.refreshStale();
    }
  }
}

/// The transfers running now, with the controls that stop them.
class _Transfers extends ConsumerWidget {
  const _Transfers({required this.entries, required this.fractions});

  final List<DownloadEntry> entries;
  final Map<String, double> fractions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final store = ref.watch(artworkStoreProvider);
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: sizeClass.gutter.horizontal / 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            title: l10n.downloadsTransferring,
            overline: l10n.downloadsInFlight(entries.length),
          ),
          for (final entry in entries)
            MediaListRow(
              data: MediaTileData(
                title: entry.title,
                subtitle: entry.subtitle,
                artwork: store.source(entry.item?.artUrl),
                domain: _domainOf(entry.mediaType),
                shape: _shapeOf(entry.mediaType),
                // The progress bar under the row, which is the sliver
                // MediaListRow already draws for a resume position.
                progress: fractions[entry.pid] ?? 0,
                trailingText: l10n.formatBytes(entry.record.sizeBytes),
                semanticsId: SemanticsIds.downloadRow(entry.pid),
              ),
              actions: <Widget>[
                // Keyed: it holds whether this transfer is parked, and
                // unkeyed state follows position, not pid.
                _PauseButton(key: ValueKey(entry.pid), entry: entry),
                WaxIconButton(
                  glyph: WaxIcons.close,
                  label: l10n.downloadsCancel(entry.title),
                  size: 18,
                  semanticsId: SemanticsIds.downloadCancel(entry.pid),
                  onPressed: () => unawaited(
                    ref.read(downloadsProvider.notifier).cancel(entry.pid),
                  ),
                ),
              ],
            ),
          const SizedBox(height: WaxSpace.s16),
        ],
      ),
    );
  }
}

/// Pause, and resume once paused.
///
/// Its own state because the port answers whether a pause took: a
/// transfer the plugin will not pause (a server with no range support)
/// stays running rather than being canceled behind the listener's back,
/// and the control has to say so rather than flipping to Resume.
class _PauseButton extends ConsumerStatefulWidget {
  const _PauseButton({required this.entry, super.key});

  final DownloadEntry entry;

  @override
  ConsumerState<_PauseButton> createState() => _PauseButtonState();
}

class _PauseButtonState extends ConsumerState<_PauseButton> {
  var _paused = false;

  @override
  Widget build(BuildContext context) {
    final pid = widget.entry.pid;
    final l10n = context.l10n;
    return WaxIconButton(
      glyph: _paused ? WaxIcons.play : WaxIcons.pause,
      label: _paused
          ? l10n.downloadsResume(widget.entry.title)
          : l10n.downloadsPause(widget.entry.title),
      size: 18,
      semanticsId: _paused
          ? SemanticsIds.downloadResume(pid)
          : SemanticsIds.downloadPause(pid),
      onPressed: () => unawaited(_toggle(pid)),
    );
  }

  Future<void> _toggle(String pid) async {
    final notifier = ref.read(downloadsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final cannotPause = context.l10n.downloadsCannotPause;
    if (_paused) {
      await notifier.resume(pid);
      if (mounted) setState(() => _paused = false);
      return;
    }
    final paused = await notifier.pause(pid);
    if (!mounted) return;
    if (paused) {
      setState(() => _paused = true);
    } else {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(cannotPause)));
    }
  }
}

/// Everything on disk, grouped by medium.
class _Groups extends ConsumerWidget {
  const _Groups({required this.downloads});

  final DownloadsState downloads;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final store = ref.watch(artworkStoreProvider);
    final l10n = context.l10n;
    final groups = downloads.groups;
    return SliverPadding(
      padding: EdgeInsets.symmetric(
        horizontal: sizeClass.gutter.horizontal / 2,
      ),
      sliver: SliverList.list(
        children: <Widget>[
          for (final group in groups) ...<Widget>[
            SectionHeader(
              title: _mediumLabel(l10n, group.mediaType),
              overline: l10n.downloadsGroupItems(group.entries.length),
            ),
            for (final entry in group.entries)
              MediaListRow(
                data: MediaTileData(
                  title: entry.title,
                  subtitle: entry.subtitle,
                  artwork: store.source(entry.item?.artUrl),
                  domain: _domainOf(entry.mediaType),
                  shape: _shapeOf(entry.mediaType),
                  downloaded: true,
                  // Played state as the row already draws it: a dot for
                  // never-heard, a sliver for part way through.
                  unplayed: (entry.progress?.positionMs ?? 0) == 0,
                  progress: entry.finished
                      ? null
                      : _fraction(entry.progress, entry.item?.durationMs),
                  trailingText: l10n.formatBytes(entry.record.sizeBytes),
                  semanticsId: SemanticsIds.downloadRow(entry.pid),
                ),
                actions: <Widget>[
                  WaxIconButton(
                    glyph: WaxIcons.delete,
                    label: l10n.downloadsRemove(entry.title),
                    size: 18,
                    semanticsId: SemanticsIds.downloadRemove(entry.pid),
                    onPressed: () => unawaited(
                      ref.read(downloadsProvider.notifier).remove(entry.pid),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: WaxSpace.s16),
          ],
        ],
      ),
    );
  }

  static double? _fraction(PlayState? progress, int? durationMs) {
    final position = progress?.positionMs ?? 0;
    if (position <= 0 || durationMs == null || durationMs <= 0) return null;
    return (position / durationMs).clamp(0.0, 1.0);
  }
}

String _mediumLabel(AppLocalizations l10n, MediaType type) => switch (type) {
  MediaType.music => l10n.downloadsMediumMusic,
  MediaType.podcast => l10n.downloadsMediumPodcasts,
  MediaType.audiobook => l10n.downloadsMediumBooks,
};

WaxDomain _domainOf(MediaType type) => switch (type) {
  MediaType.music => WaxDomain.music,
  MediaType.podcast => WaxDomain.podcasts,
  MediaType.audiobook => WaxDomain.audiobooks,
};

ArtworkShape _shapeOf(MediaType type) =>
    type == MediaType.audiobook ? ArtworkShape.portrait : ArtworkShape.square;
