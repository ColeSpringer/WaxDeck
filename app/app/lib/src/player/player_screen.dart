import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../media_icons.dart';
import '../providers.dart';
import 'play_state_controller.dart';
import 'playback_session.dart';

/// Full-screen player for one item: artwork, transport controls, and a seek
/// bar, with resume and listen accounting handled by [PlaybackSession].
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.item});

  final ItemSummary item;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final PlaybackSession _session;
  late final Future<void> _starting;

  @override
  void initState() {
    super.initState();
    _session = PlaybackSession(
      repository: ref.read(repositoryProvider),
      engine: ref.read(audioEngineProvider),
      item: widget.item,
      clientId: listenClientId,
    );
    _starting = _session.start();
  }

  @override
  void dispose() {
    // Fire and forget: the final checkpoint and listen report run out of
    // band while the route animates away.
    unawaited(_session.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Scaffold(
      appBar: AppBar(title: Text(item.title)),
      body: FutureBuilder<void>(
        future: _starting,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final error = snapshot.error;
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

class _PlayerBody extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
          _StarRatingRow(pid: item.pid),
          const SizedBox(height: 8),
          StreamBuilder<Duration>(
            stream: engine.positionStream,
            initialData: engine.position,
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
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Star toggle plus the five-star rating row, backed by the item's play
/// state. Ratings map star N to N times 20 on the 0 to 100 wire scale;
/// tapping the current rating again clears it.
class _StarRatingRow extends ConsumerWidget {
  const _StarRatingRow({required this.pid});

  final String pid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
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
    final starred = playState?.starred ?? false;
    final rating = playState?.rating;
    final stars = rating == null ? 0 : (rating / 20).round().clamp(0, 5);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Semantics(
          identifier: 'star-button',
          label: starred ? 'Unstar' : 'Star',
          button: true,
          child: IconButton(
            key: const Key('star-button'),
            tooltip: starred ? 'Unstar' : 'Star',
            color: starred ? colorScheme.primary : null,
            onPressed: playState == null
                ? null
                : () => notifier.setStarred(!starred),
            icon: Icon(starred ? Icons.favorite : Icons.favorite_border),
          ),
        ),
        const SizedBox(width: 8),
        for (var n = 1; n <= 5; n++)
          Semantics(
            identifier: 'rating-$n',
            label: '$n star rating',
            button: true,
            child: IconButton(
              key: Key('rating-$n'),
              visualDensity: VisualDensity.compact,
              color: n <= stars ? colorScheme.primary : null,
              onPressed: playState == null
                  ? null
                  : () => notifier.rate(n == stars ? null : n * 20),
              icon: Icon(n <= stars ? Icons.star : Icons.star_border),
            ),
          ),
      ],
    );
  }
}
