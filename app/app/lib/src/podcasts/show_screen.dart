import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'credits.dart';
import 'explicit_badge.dart';
import 'podcasts_controller.dart';
import 'show_notes.dart';

String formatEpisodeDate(DateTime when) {
  final local = when.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

String formatEpisodeDuration(int durationMs) {
  final d = Duration(milliseconds: durationMs);
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}

/// One podcast show: header with subscribe and settings, then the paged
/// episode list.
class ShowScreen extends ConsumerWidget {
  const ShowScreen({super.key, required this.pid});

  final String pid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(podcastDetailProvider(pid));
    final episodes = ref.watch(episodesProvider(pid));
    return Scaffold(
      appBar: AppBar(
        title: Text(detail.value?.show.title ?? 'Show'),
        actions: [
          if (detail.value?.subscribed ?? false)
            Semantics(
              identifier: SemanticsIds.podcastSettingsOpen,
              label: 'Subscription settings',
              button: true,
              child: IconButton(
                key: const Key(SemanticsIds.podcastSettingsOpen),
                tooltip: 'Subscription settings',
                icon: const Icon(Icons.tune),
                onPressed: () => _openSettings(context, ref),
              ),
            ),
        ],
      ),
      body: switch (detail) {
        AsyncData(:final value) => _body(context, ref, value, episodes),
        AsyncError(:final error) => Center(
          child: Text(
            error is WaxDeckApiException
                ? error.message
                : 'Could not load the show',
            textAlign: TextAlign.center,
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  void _openSettings(BuildContext context, WidgetRef ref) {
    final settings =
        ref.read(podcastDetailProvider(pid)).value?.settings ??
        const SubscriptionSettings();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SubscriptionSettingsSheet(pid: pid, initial: settings),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    PodcastDetail detail,
    AsyncValue<EpisodeListState> episodes,
  ) {
    final list = episodes.value;
    final items = list?.items ?? const <EpisodeSummary>[];
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.pixels >= metrics.maxScrollExtent - 400) {
          ref.read(episodesProvider(pid).notifier).loadMore();
        }
        return false;
      },
      child: ListView.builder(
        itemCount: 1 + items.length + ((list?.loadingMore ?? false) ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == 0) return _ShowHeader(pid: pid, detail: detail);
          if (index > items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _EpisodeRow(showPid: pid, episode: items[index - 1]);
        },
      ),
    );
  }
}

class _ShowHeader extends ConsumerWidget {
  const _ShowHeader({required this.pid, required this.detail});

  final String pid;
  final PodcastDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(podcastDetailProvider(pid).notifier);

    Future<void> guarded(Future<void> Function() action) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await action();
      } on WaxDeckApiException catch (e) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
    }

    return _buildHeader(context, ref, notifier, guarded);
  }

  // The unsubscribe itself never destroys anything, so it needs no
  // confirmation; the question only appears when server downloads are
  // at stake, and it is about the files, not the subscription.
  Future<void> _unsubscribe(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(Future<void> Function()) guarded,
  ) async {
    final episodes =
        ref.read(episodesProvider(pid)).value?.items ??
        const <EpisodeSummary>[];
    final hasDownloads = episodes.any((e) => e.downloaded);
    final notifier = ref.read(podcastDetailProvider(pid).notifier);
    if (!hasDownloads) {
      await guarded(notifier.unsubscribe);
      return;
    }
    final removeFiles = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unsubscribe'),
        content: const Text(
          'Some episodes are downloaded on the server. Remove those '
          'files too? Removed files go to the trash, and your listening '
          'progress is kept either way. If someone else subscribes to '
          'this show, the files stay regardless.',
        ),
        actions: [
          Semantics(
            identifier: SemanticsIds.unsubscribeKeepFiles,
            label: 'Keep files',
            button: true,
            child: TextButton(
              key: const Key(SemanticsIds.unsubscribeKeepFiles),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep files'),
            ),
          ),
          Semantics(
            identifier: SemanticsIds.unsubscribeRemoveFiles,
            label: 'Remove files',
            button: true,
            child: TextButton(
              key: const Key(SemanticsIds.unsubscribeRemoveFiles),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove files'),
            ),
          ),
        ],
      ),
    );
    if (removeFiles == null) return;
    await guarded(() => notifier.unsubscribe(removeDownloads: removeFiles));
  }

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    PodcastDetailController notifier,
    Future<void> Function(Future<void> Function()) guarded,
  ) {
    final show = detail.show;
    final artUrl = show.artUrl;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final descriptionHtml = show.descriptionHtml;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: artUrl == null
                      ? ColoredBox(
                          color: colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.podcasts, size: 40),
                        )
                      : Image.network(
                          artUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => ColoredBox(
                            color: colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.podcasts, size: 40),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (show.explicit)
                          ExplicitBadge(key: ValueKey('show-explicit-$pid')),
                        Expanded(
                          child: Text(show.title, style: textTheme.titleLarge),
                        ),
                      ],
                    ),
                    if (show.author != null)
                      Text(
                        show.author!,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (detail.subscribed)
                      Semantics(
                        identifier: SemanticsIds.podcastUnsubscribe,
                        label: 'Unsubscribe',
                        button: true,
                        child: OutlinedButton(
                          key: const Key(SemanticsIds.podcastUnsubscribe),
                          onPressed: () => _unsubscribe(context, ref, guarded),
                          child: const Text('Unsubscribe'),
                        ),
                      )
                    else
                      Semantics(
                        identifier: SemanticsIds.podcastSubscribe,
                        label: 'Subscribe',
                        button: true,
                        child: FilledButton(
                          key: const Key(SemanticsIds.podcastSubscribe),
                          onPressed: () => guarded(notifier.subscribe),
                          child: const Text('Subscribe'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (show.funding != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () =>
                    ref.read(urlOpenerProvider).open(show.funding!.url),
                icon: const Icon(Icons.favorite_outline, size: 18),
                label: Text(
                  show.funding!.message?.isNotEmpty ?? false
                      ? show.funding!.message!
                      : 'Support this show',
                ),
              ),
            ),
          ],
          if (descriptionHtml != null && descriptionHtml.isNotEmpty) ...[
            const SizedBox(height: 16),
            ShowNotesView(
              html: descriptionHtml,
              onOpenLink: ref.read(urlOpenerProvider).open,
            ),
          ],
          if (show.persons.isNotEmpty) ...[
            const SizedBox(height: 16),
            PodcastCredits(
              persons: show.persons,
              onOpenLink: ref.read(urlOpenerProvider).open,
            ),
          ],
        ],
      ),
    );
  }
}

class _EpisodeRow extends ConsumerWidget {
  const _EpisodeRow({required this.showPid, required this.episode});

  final String showPid;
  final EpisodeSummary episode;

  Future<void> _fetch(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(episodesProvider(showPid).notifier)
          .fetchEpisode(episode.pid);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Fetching to server')));
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _removeDownload(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(episodesProvider(showPid).notifier)
          .removeEpisodeDownload(episode.pid);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Removed from server; your progress is kept'),
          ),
        );
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitleParts = [
      formatEpisodeDate(episode.publishedAt),
      if (episode.durationMs > 0) formatEpisodeDuration(episode.durationMs),
    ];
    final chip = episode.downloaded
        ? const Chip(
            label: Text('Downloaded'),
            visualDensity: VisualDensity.compact,
          )
        : switch (episode.fetchState) {
            'failed' => const Chip(
              label: Text('Failed'),
              visualDensity: VisualDensity.compact,
            ),
            null => null,
            // Open set: anything pending-ish reads as queued.
            _ => const Chip(
              label: Text('Queued'),
              visualDensity: VisualDensity.compact,
            ),
          };
    final showFetchButton =
        !episode.downloaded &&
        (episode.fetchState == null || episode.fetchState == 'failed');

    return Semantics(
      identifier: SemanticsIds.episode(episode.pid),
      label: episode.title,
      button: true,
      child: ListTile(
        key: ValueKey(SemanticsIds.episode(episode.pid)),
        title: Row(
          children: [
            if (episode.explicit)
              ExplicitBadge(key: ValueKey('episode-explicit-${episode.pid}')),
            Expanded(
              child: Text(
                episode.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Text(subtitleParts.join(' | ')),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?chip,
            if (showFetchButton)
              Semantics(
                identifier: SemanticsIds.episodeFetch(episode.pid),
                label: 'Fetch episode',
                button: true,
                excludeSemantics: true,
                onTap: () => _fetch(context, ref),
                child: IconButton(
                  key: ValueKey(SemanticsIds.episodeFetch(episode.pid)),
                  tooltip: 'Fetch to server',
                  icon: const Icon(Icons.cloud_download_outlined),
                  onPressed: () => _fetch(context, ref),
                ),
              ),
            if (episode.downloaded)
              Semantics(
                identifier: SemanticsIds.episodeRemove(episode.pid),
                label: 'Remove download',
                button: true,
                excludeSemantics: true,
                onTap: () => _removeDownload(context, ref),
                child: IconButton(
                  key: ValueKey(SemanticsIds.episodeRemove(episode.pid)),
                  tooltip: 'Remove from server',
                  icon: const Icon(Icons.cloud_off_outlined),
                  onPressed: () => _removeDownload(context, ref),
                ),
              ),
            Semantics(
              identifier: SemanticsIds.episodeInfo(episode.pid),
              label: 'Episode details',
              button: true,
              excludeSemantics: true,
              onTap: () => _openInfo(context),
              child: IconButton(
                key: ValueKey(SemanticsIds.episodeInfo(episode.pid)),
                tooltip: 'Episode details',
                icon: const Icon(Icons.info_outline),
                onPressed: () => _openInfo(context),
              ),
            ),
          ],
        ),
        onTap: () {
          if (episode.downloaded) {
            context.push(
              WaxRoute.nowPlaying,
              extra: NowPlayingArgs(item: episode),
            );
          } else {
            _fetch(context, ref);
          }
        },
      ),
    );
  }

  void _openInfo(BuildContext context) {
    context.push(WaxRoute.episode(episode.pid));
  }
}

/// Per-subscription settings editor; Save PUTs the complete object.
class _SubscriptionSettingsSheet extends ConsumerStatefulWidget {
  const _SubscriptionSettingsSheet({required this.pid, required this.initial});

  final String pid;
  final SubscriptionSettings initial;

  @override
  ConsumerState<_SubscriptionSettingsSheet> createState() =>
      _SubscriptionSettingsSheetState();
}

class _SubscriptionSettingsSheetState
    extends ConsumerState<_SubscriptionSettingsSheet> {
  late double _speed;
  late bool _trimSilence;
  late bool _voiceBoost;
  late bool _autoDownload;
  late final TextEditingController _retention;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _speed = widget.initial.speed ?? 1.0;
    _trimSilence = widget.initial.trimSilence ?? false;
    _voiceBoost = widget.initial.voiceBoost ?? false;
    _autoDownload = widget.initial.autoDownload;
    _retention = TextEditingController(
      text: widget.initial.retentionKeep?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _retention.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final retentionText = _retention.text.trim();
    final settings = SubscriptionSettings(
      retentionKeep: retentionText.isEmpty ? null : int.tryParse(retentionText),
      autoDownload: _autoDownload,
      folder: widget.initial.folder,
      private: widget.initial.private,
      speed: _speed,
      trimSilence: _trimSilence,
      voiceBoost: _voiceBoost,
      skipIntroSeconds: widget.initial.skipIntroSeconds,
      skipOutroSeconds: widget.initial.skipOutroSeconds,
    );
    try {
      await ref
          .read(podcastDetailProvider(widget.pid).notifier)
          .saveSettings(settings);
      navigator.pop();
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Subscription settings',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text('Speed ${_speed.toStringAsFixed(2)}x'),
          Semantics(
            identifier: SemanticsIds.podcastSettingsSpeed,
            label: 'Playback speed',
            child: Slider(
              key: const Key(SemanticsIds.podcastSettingsSpeed),
              value: _speed,
              min: 0.5,
              max: 3.5,
              divisions: 60,
              label: _speed.toStringAsFixed(2),
              onChanged: (v) => setState(() => _speed = v),
            ),
          ),
          SwitchListTile(
            key: const Key('podcast-settings-trim'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Trim silence'),
            value: _trimSilence,
            onChanged: (v) => setState(() => _trimSilence = v),
          ),
          SwitchListTile(
            key: const Key('podcast-settings-boost'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Voice boost'),
            value: _voiceBoost,
            onChanged: (v) => setState(() => _voiceBoost = v),
          ),
          SwitchListTile(
            key: const Key('podcast-settings-autodownload'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-download new episodes'),
            value: _autoDownload,
            onChanged: (v) => setState(() => _autoDownload = v),
          ),
          Semantics(
            identifier: SemanticsIds.podcastSettingsRetention,
            textField: true,
            child: TextField(
              key: const Key(SemanticsIds.podcastSettingsRetention),
              controller: _retention,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Episodes to keep',
                helperText: 'Empty uses the server default; 0 keeps all',
              ),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: Semantics(
              identifier: SemanticsIds.podcastSettingsSave,
              label: 'Save settings',
              button: true,
              child: FilledButton(
                key: const Key(SemanticsIds.podcastSettingsSave),
                onPressed: _busy ? null : _save,
                child: const Text('Save'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
