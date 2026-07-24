import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../discovery/discovery_actions.dart';
import '../library/item_delete.dart';
import '../media_icons.dart';
import '../playlists/add_to_playlist_dialog.dart';
import '../providers.dart';
import '../sharing/share_dialog.dart';
import '../radio/radio_controller.dart';
import '../sync/sync_providers.dart';
import 'play_state_controller.dart';
import '../connect/connect_controller.dart';
import '../connect/connect_providers.dart';
import '../connect/device_picker.dart';
import 'playback_session.dart';
import 'session_registry.dart';
import 'sleep_timer.dart';
import 'star_rating_row.dart';

/// Speed presets the player button cycles through.
const playerSpeedSteps = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];

/// The next speed after [current] in the preset cycle.
double nextPlayerSpeed(double current) {
  for (final step in playerSpeedSteps) {
    if (step > current + 0.001) return step;
  }
  return playerSpeedSteps.first;
}

String formatPlayerSpeed(double speed) {
  var text = speed.toStringAsFixed(2);
  while (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return '${text}x';
}

/// Full-screen player for one item: artwork, transport controls, and a seek
/// bar, with resume and listen accounting handled by [PlaybackSession].
/// Spoken-word items add speed, silence trimming, a sleep timer, and (for
/// books) chapter navigation.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.item, this.initialPositionMs});

  final ItemSummary item;

  /// Overrides the saved resume position (book resume, chapter start).
  final int? initialPositionMs;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final PlaybackSession _session;
  late final ConnectEndpointController _connect;
  late final Future<void> _starting;
  // Captured in initState: ref is not usable inside dispose.
  late final CurrentSessionRegistry _registry;
  StreamSubscription<Duration>? _sleepFeed;

  @override
  void initState() {
    super.initState();
    // Live radio bypasses sessions; loading an item takes the engine
    // back, so the radio surface must stop claiming it.
    ref.read(radioPlaybackProvider.notifier).markInterrupted();
    _session = PlaybackSession(
      repository: ref.read(repositoryProvider),
      engine: ref.read(audioEngineProvider),
      item: widget.item,
      clientId: listenClientId,
      sync: ref.read(syncEngineProvider),
      downloads: ref.read(downloadManagerProvider),
      initialPositionMs: widget.initialPositionMs,
    );
    _registry = ref.read(currentSessionRegistryProvider);
    _registry.register(_session);
    _connect = ref.read(connectControllerProvider);
    _connect.attachLocal(_session, widget.item.pid);
    _starting = _session.start();
    // End-of-chapter sleep mode watches the display timeline.
    final sleepTimer = ref.read(sleepTimerProvider.notifier);
    _sleepFeed = _session.displayPositionStream.listen(sleepTimer.onPosition);
  }

  @override
  void dispose() {
    unawaited(_sleepFeed?.cancel());
    _connect.detachLocal(_session);
    _registry.unregister(_session);
    // Fire and forget: the final checkpoint and listen report run out of
    // band while the route animates away.
    unawaited(_session.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Scaffold(
      appBar: AppBar(
        title: Text(item.title),
        actions: [
          Semantics(
            identifier: 'player-devices',
            label: 'Play on',
            button: true,
            excludeSemantics: true,
            onTap: () => showDevicePicker(
              context,
              ref,
              currentPid: item.pid,
              positionMs: _session.displayPosition.inMilliseconds,
            ),
            child: IconButton(
              key: const Key('player-devices'),
              tooltip: 'Play on',
              icon: const Icon(Icons.cast),
              onPressed: () => showDevicePicker(
                context,
                ref,
                currentPid: item.pid,
                positionMs: _session.displayPosition.inMilliseconds,
              ),
            ),
          ),
          Semantics(
            identifier: 'add-to-playlist',
            label: 'Add to playlist',
            button: true,
            child: IconButton(
              key: const Key('add-to-playlist'),
              tooltip: 'Add to playlist',
              icon: const Icon(Icons.playlist_add),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AddToPlaylistDialog(item: item),
              ),
            ),
          ),
          Semantics(
            identifier: 'share-link',
            label: 'Share link',
            button: true,
            child: IconButton(
              key: const Key('share-link'),
              tooltip: 'Share link',
              icon: const Icon(Icons.share_outlined),
              // Episodes offer the current position as the share's
              // start point; other media share from the top.
              onPressed: () => showShareLinkDialog(
                context,
                pid: item.pid,
                positionMs: item.mediaType == MediaType.podcast
                    ? _session.displayPosition.inMilliseconds
                    : null,
              ),
            ),
          ),
          if (item.mediaType == MediaType.music)
            Semantics(
              identifier: 'player-discover',
              label: 'Discover',
              button: true,
              child: PopupMenuButton<String>(
                key: const Key('player-discover'),
                tooltip: 'Discover',
                icon: const Icon(Icons.auto_awesome_outlined),
                onSelected: (choice) => switch (choice) {
                  'mix' => showInstantMixSheet(context, item),
                  'similar' => openSimilarTracks(context, ref, item),
                  _ => Future<void>.value(),
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'mix',
                    child: Semantics(
                      identifier: 'instant-mix',
                      child: const Text('Instant mix', key: Key('instant-mix')),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'similar',
                    child: Semantics(
                      identifier: 'similar-tracks',
                      child: const Text(
                        'Similar tracks',
                        key: Key('similar-tracks'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _DownloadButton(pid: item.pid),
          ItemDeleteAction(
            pid: item.pid,
            onDeleted: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _starting,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final error = snapshot.error;
            // The pane stays terse; the console carries the real
            // failure so field reports and browser tests can see it.
            debugPrint('playback start failed: $error');
            return Center(
              child: Text(
                error is WaxDeckApiException
                    ? error.message
                    : 'Playback failed to start',
                key: const Key('player-error'),
                textAlign: TextAlign.center,
              ),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return _PlayerBody(session: _session, item: item);
        },
      ),
    );
  }
}

class _PlayerBody extends ConsumerWidget {
  const _PlayerBody({required this.session, required this.item});

  final PlaybackSession session;
  final ItemSummary item;

  String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '${d.inMinutes.remainder(60)}:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = session.engine;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final artUrl = item.artUrl;
    final placeholder = ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          mediaFallbackIcon(item.mediaType),
          size: 96,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 360,
                  maxHeight: 360,
                ),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: artUrl == null
                        ? placeholder
                        : Image.network(
                            artUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => placeholder,
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            item.title,
            style: textTheme.titleLarge,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (item.artist != null)
            Text(
              item.artist!,
              style: textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (item.mediaType == MediaType.audiobook)
            _ChapterIndicator(session: session),
          _StarRatingRow(pid: item.pid),
          const SizedBox(height: 8),
          StreamBuilder<Duration>(
            stream: session.displayPositionStream,
            initialData: session.displayPosition,
            builder: (context, positionSnapshot) {
              final duration = session.mediaDuration;
              final position = positionSnapshot.data ?? Duration.zero;
              final maxMs = duration.inMilliseconds;
              final valueMs = position.inMilliseconds.clamp(
                0,
                maxMs > 0 ? maxMs : 1,
              );
              return Column(
                children: [
                  Semantics(
                    identifier: 'player-seek',
                    label: 'Seek bar',
                    child: Slider(
                      key: const Key('player-seek'),
                      value: valueMs.toDouble(),
                      max: (maxMs > 0 ? maxMs : 1).toDouble(),
                      onChanged: (value) =>
                          session.seek(Duration(milliseconds: value.round())),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_format(position), style: textTheme.labelMedium),
                      Text(_format(duration), style: textTheme.labelMedium),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SpeedButton(session: session),
              const SizedBox(width: 8),
              StreamBuilder<bool>(
                stream: engine.playingStream,
                initialData: engine.playing,
                builder: (context, playingSnapshot) {
                  final playing = playingSnapshot.data ?? false;
                  return Semantics(
                    identifier: 'player-toggle',
                    label: playing ? 'Pause' : 'Play',
                    button: true,
                    child: IconButton.filled(
                      key: const Key('player-toggle'),
                      iconSize: 48,
                      onPressed: session.toggle,
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              _SleepTimerButton(session: session),
            ],
          ),
          if (session.isSpokenWord) ...[
            const SizedBox(height: 8),
            _TrimChip(session: session),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Cycles the playback speed through the presets, persisting the choice
/// per show or book (music stays at whatever it is set to for the
/// session and never persists).
class _SpeedButton extends StatelessWidget {
  const _SpeedButton({required this.session});

  final PlaybackSession session;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: session.engine.speedStream,
      initialData: session.engine.speed,
      builder: (context, snapshot) {
        final speed = snapshot.data ?? 1.0;
        return Semantics(
          identifier: 'player-speed',
          label: 'Playback speed ${formatPlayerSpeed(speed)}',
          button: true,
          excludeSemantics: true,
          onTap: () => session.setSpeed(nextPlayerSpeed(speed)),
          child: TextButton(
            key: const Key('player-speed'),
            onPressed: () => session.setSpeed(nextPlayerSpeed(speed)),
            child: Text(formatPlayerSpeed(speed)),
          ),
        );
      },
    );
  }
}

/// Silence-trimming toggle with the hours-saved badge.
class _TrimChip extends StatelessWidget {
  const _TrimChip({required this.session});

  final PlaybackSession session;

  static String savedLabel(int savedMs) {
    final d = Duration(milliseconds: savedMs);
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    if (m > 0) return 'saved ${m}m ${s}s';
    return 'saved ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: session.trimEnabled,
      builder: (context, enabled, _) {
        return ValueListenableBuilder<int>(
          valueListenable: session.hoursSavedMs,
          builder: (context, savedMs, _) {
            final label = savedMs > 0
                ? 'Trim silence (${savedLabel(savedMs)})'
                : 'Trim silence';
            // excludeSemantics with a mirrored tap: without it the
            // wrapper mints a second node beside the chip's own and
            // the label rides an attribute assertions cannot read.
            return Semantics(
              identifier: 'player-trim',
              label: label,
              button: true,
              excludeSemantics: true,
              onTap: () => session.setTrimEnabled(!enabled),
              child: FilterChip(
                key: const Key('player-trim'),
                selected: enabled,
                label: Text(label),
                onSelected: session.setTrimEnabled,
              ),
            );
          },
        );
      },
    );
  }
}

/// Sleep timer button plus its options sheet. When a timer runs, the
/// remaining time shows as a badge on the button.
class _SleepTimerButton extends ConsumerWidget {
  const _SleepTimerButton({required this.session});

  final PlaybackSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(sleepTimerProvider);
    final button = IconButton(
      key: const Key('sleep-timer-open'),
      tooltip: timer.active ? 'Sleep timer (${timer.label})' : 'Sleep timer',
      icon: Icon(timer.active ? Icons.bedtime : Icons.bedtime_outlined),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        builder: (_) => _SleepTimerSheet(session: session),
      ),
    );
    return Semantics(
      identifier: 'sleep-timer-open',
      label: timer.active ? 'Sleep timer, ${timer.label} left' : 'Sleep timer',
      button: true,
      child: timer.active
          ? Badge(label: Text(timer.label), child: button)
          : button,
    );
  }
}

class _SleepTimerSheet extends ConsumerStatefulWidget {
  const _SleepTimerSheet({required this.session});

  final PlaybackSession session;

  @override
  ConsumerState<_SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends ConsumerState<_SleepTimerSheet> {
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  /// Where the current chapter ends on the book timeline, for
  /// end-of-chapter mode; null when the book has no chapters.
  int? _currentChapterEndMs() {
    final book = widget.session.book;
    if (book == null || book.chapters.isEmpty) return null;
    final positionMs = widget.session.displayPosition.inMilliseconds;
    ChapterMark current = book.chapters.first;
    ChapterMark? next;
    for (var i = 0; i < book.chapters.length; i++) {
      if (book.chapters[i].startMs <= positionMs) {
        current = book.chapters[i];
        next = i + 1 < book.chapters.length ? book.chapters[i + 1] : null;
      }
    }
    return current.endMs ?? next?.startMs ?? book.durationMs;
  }

  void _startMinutes(int minutes) {
    ref.read(sleepTimerProvider.notifier).startMinutes(minutes);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(sleepTimerProvider).active;
    final chapterEndMs = widget.session.item.mediaType == MediaType.audiobook
        ? _currentChapterEndMs()
        : null;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final minutes in const [5, 15, 30, 60])
              Semantics(
                identifier: 'sleep-timer-$minutes',
                button: true,
                child: ListTile(
                  key: ValueKey('sleep-timer-$minutes'),
                  leading: const Icon(Icons.timer_outlined),
                  title: Text('$minutes minutes'),
                  onTap: () => _startMinutes(minutes),
                ),
              ),
            if (chapterEndMs != null)
              Semantics(
                identifier: 'sleep-timer-chapter',
                button: true,
                child: ListTile(
                  key: const Key('sleep-timer-chapter'),
                  leading: const Icon(Icons.auto_stories_outlined),
                  title: const Text('End of chapter'),
                  onTap: () {
                    ref
                        .read(sleepTimerProvider.notifier)
                        .startEndOfChapter(chapterEndMs);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      identifier: 'sleep-timer-custom-field',
                      textField: true,
                      child: TextField(
                        key: const Key('sleep-timer-custom-field'),
                        controller: _custom,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Custom minutes',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    identifier: 'sleep-timer-custom-start',
                    label: 'Start custom timer',
                    button: true,
                    child: TextButton(
                      key: const Key('sleep-timer-custom-start'),
                      onPressed: () {
                        final minutes = int.tryParse(_custom.text.trim());
                        if (minutes != null && minutes > 0) {
                          _startMinutes(minutes);
                        }
                      },
                      child: const Text('Start'),
                    ),
                  ),
                ],
              ),
            ),
            if (active)
              Semantics(
                identifier: 'sleep-timer-cancel',
                button: true,
                child: ListTile(
                  key: const Key('sleep-timer-cancel'),
                  leading: const Icon(Icons.close),
                  title: const Text('Cancel timer'),
                  onTap: () {
                    ref.read(sleepTimerProvider.notifier).cancel();
                    Navigator.of(context).pop();
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Current chapter title for books; tapping opens the chapter sheet for
/// direct seeks.
class _ChapterIndicator extends StatelessWidget {
  const _ChapterIndicator({required this.session});

  final PlaybackSession session;

  static ChapterMark? chapterAt(BookDetail book, Duration position) {
    final positionMs = position.inMilliseconds;
    ChapterMark? current;
    for (final chapter in book.chapters) {
      if (chapter.startMs <= positionMs) current = chapter;
    }
    return current ?? (book.chapters.isEmpty ? null : book.chapters.first);
  }

  @override
  Widget build(BuildContext context) {
    final book = session.book;
    if (book == null || book.chapters.isEmpty) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<Duration>(
      stream: session.displayPositionStream,
      initialData: session.displayPosition,
      builder: (context, snapshot) {
        final chapter = chapterAt(book, snapshot.data ?? Duration.zero);
        final title =
            chapter?.title ??
            (chapter == null ? '' : 'Chapter ${chapter.index + 1}');
        return Semantics(
          identifier: 'player-chapters',
          label: 'Chapters, current: $title',
          button: true,
          child: TextButton.icon(
            key: const Key('player-chapters'),
            icon: const Icon(Icons.list, size: 18),
            label: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => _ChapterSheet(session: session, book: book),
            ),
          ),
        );
      },
    );
  }
}

class _ChapterSheet extends StatelessWidget {
  const _ChapterSheet({required this.session, required this.book});

  final PlaybackSession session;
  final BookDetail book;

  @override
  Widget build(BuildContext context) {
    String stamp(int ms) {
      final d = Duration(milliseconds: ms);
      final h = d.inHours;
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return h > 0 ? '$h:$m:$s' : '$m:$s';
    }

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final chapter in book.chapters)
            Semantics(
              identifier: 'player-chapter-${chapter.index}',
              button: true,
              child: ListTile(
                key: ValueKey('player-chapter-${chapter.index}'),
                dense: true,
                leading: Text(stamp(chapter.startMs)),
                title: Text(chapter.title ?? 'Chapter ${chapter.index + 1}'),
                onTap: () {
                  session.seek(Duration(milliseconds: chapter.startMs));
                  Navigator.of(context).pop();
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// The item's star toggle and rating row, backed by its play state.
class _StarRatingRow extends ConsumerWidget {
  const _StarRatingRow({required this.pid});

  final String pid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A failed mutation rolls the value back and lands here as an error
    // still carrying that previous value; tell the user the tap did not
    // stick while the row keeps rendering the real state.
    ref.listen(playStateControllerProvider(pid), (previous, next) {
      if (next.hasError && !next.isLoading) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Could not save that change')),
          );
      }
    });
    final playState = ref.watch(playStateControllerProvider(pid)).value;
    final notifier = ref.read(playStateControllerProvider(pid).notifier);

    return StarRatingRow(
      starred: playState?.starred ?? false,
      rating: playState?.rating,
      enabled: playState != null,
      onStar: notifier.setStarred,
      onRate: notifier.rate,
      idPrefix: '',
      starLabel: (starred) => starred ? 'Unstar' : 'Star',
      ratingLabel: (n) => '$n star rating',
    );
  }
}

/// Downloads the item's original for offline playback. Hidden on
/// platforms without a download manager (web). Three states: not
/// downloaded, transferring, on disk.
class _DownloadButton extends ConsumerStatefulWidget {
  const _DownloadButton({required this.pid});

  final String pid;

  @override
  ConsumerState<_DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends ConsumerState<_DownloadButton> {
  bool? _complete;
  bool _inFlight = false;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    final port = ref.read(downloadManagerProvider);
    if (port == null) return;
    final complete = await port.isComplete(widget.pid);
    if (mounted) setState(() => _complete = complete);
  }

  Future<void> _download() async {
    final port = ref.read(downloadManagerProvider);
    if (port == null) return;
    setState(() => _inFlight = true);
    try {
      // Listen before enqueuing so a fast completion cannot slip past,
      // and stop on failure too; waiting on the complete event alone
      // would spin forever when a file fails.
      final done = Completer<void>();
      final sub = port.progress.listen((p) {
        if (p.pid == widget.pid &&
            (p.complete || p.failed) &&
            !done.isCompleted) {
          done.complete();
        }
      });
      try {
        await port.download(widget.pid);
        // Everything may already be on disk (an early tap before the
        // probe landed, or a server-side retag): nothing was enqueued,
        // so no event will ever come.
        if (!await port.isComplete(widget.pid)) {
          await done.future;
        }
      } finally {
        await sub.cancel();
      }
    } finally {
      if (mounted) {
        setState(() => _inFlight = false);
      }
      await _probe();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(downloadManagerProvider) == null) {
      return const SizedBox.shrink();
    }
    final complete = _complete ?? false;
    return Semantics(
      identifier: 'download-button',
      label: complete ? 'Downloaded' : 'Download',
      button: true,
      excludeSemantics: true,
      onTap: complete || _inFlight ? null : _download,
      child: IconButton(
        key: const Key('download-button'),
        tooltip: complete ? 'Downloaded' : 'Download for offline playback',
        onPressed: complete || _inFlight ? null : _download,
        icon: _inFlight
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(complete ? Icons.download_done : Icons.download_outlined),
      ),
    );
  }
}
