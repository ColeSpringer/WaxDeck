import 'dart:async';

import 'package:waxdeck_ui/waxdeck_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../player/now_playing_controller.dart';
import '../providers.dart';
import '../queue/queue_state.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';

/// How large an instant mix is asked to be.
const instantMixSize = 50;

/// Remembers the last chosen mix adventurousness for the session.
class MixAdventurousnessController extends Notifier<double> {
  @override
  double build() => 0.5;

  void set(double value) => state = value;
}

final mixAdventurousnessProvider =
    NotifierProvider<MixAdventurousnessController, double>(
      MixAdventurousnessController.new,
    );

/// Opens the instant-mix sheet for a seed track. Confirming builds the
/// mix and starts playing it.
Future<void> showInstantMixSheet(BuildContext context, ItemSummary seed) =>
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => InstantMixSheet(seed: seed),
    );

/// Adventurousness slider plus the Mix confirm. The chosen value is
/// remembered for the next launch.
class InstantMixSheet extends ConsumerStatefulWidget {
  const InstantMixSheet({super.key, required this.seed});

  final ItemSummary seed;

  @override
  ConsumerState<InstantMixSheet> createState() => _InstantMixSheetState();
}

class _InstantMixSheetState extends ConsumerState<InstantMixSheet> {
  late double _adventurousness = ref.read(mixAdventurousnessProvider);
  var _busy = false;

  Future<void> _mix() async {
    if (_busy) return;
    setState(() => _busy = true);
    ref.read(mixAdventurousnessProvider.notifier).set(_adventurousness);
    // The sheet's own navigator closes the sheet; pushes go through
    // the router, whose stack outlives it. Playback likewise: the
    // controller belongs to the container, and reaching for it through
    // ref after the await would throw if the sheet were dismissed while
    // the mix was building.
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final playback = ref.read(nowPlayingProvider.notifier);
    try {
      final mix = await ref
          .read(repositoryProvider)
          .createInstantMix(
            seedPid: widget.seed.pid,
            adventurousness: _adventurousness,
            size: instantMixSize,
          );
      // Dismissed while the mix was building: that is a cancel, and
      // popping again from here would take the screen underneath with
      // it.
      if (!mounted) return;
      navigator.pop();
      if (mix.items.isEmpty) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('No mix available for this track')),
          );
        return;
      }
      // Mirror how playlists start playback: the mix list stands in
      // for the playlist screen, and the player opens on the first
      // track so the mix starts immediately. Popping the player lands
      // on the list to keep going. Route futures resolve on pop, so
      // neither push is awaited.
      unawaited(
        router.push<void>(
          WaxRoute.tracks,
          extra: TrackListArgs(
            title: 'Instant mix',
            basis: mix.basis,
            items: mix.items,
            idPrefix: 'mix',
          ),
        ),
      );
      playback.play(
        mix.items,
        source: QueueSource(kind: QueueSourceKind.mix, label: 'Instant mix'),
      );
      unawaited(router.push<void>(WaxRoute.nowPlaying));
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
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Instant mix', style: textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'From "${widget.seed.title}"',
              style: textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Familiar'),
                Expanded(
                  child: Semantics(
                    identifier: SemanticsIds.mixAdventurousness,
                    label: 'Adventurousness',
                    child: Slider(
                      key: const Key(SemanticsIds.mixAdventurousness),
                      value: _adventurousness,
                      onChanged: (v) => setState(() => _adventurousness = v),
                    ),
                  ),
                ),
                const Text('Adventurous'),
              ],
            ),
            const SizedBox(height: 8),
            Semantics(
              identifier: SemanticsIds.instantMixRun,
              label: 'Mix',
              button: true,
              child: FilledButton(
                key: const Key(SemanticsIds.instantMixRun),
                onPressed: _busy ? null : _mix,
                child: const Text('Mix'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fetches similar tracks for a seed and pushes the result list.
Future<void> openSimilarTracks(
  BuildContext context,
  WidgetRef ref,
  ItemSummary seed,
) async {
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final similar = await ref
        .read(repositoryProvider)
        .getSimilarTracks(seed.pid, limit: instantMixSize);
    await router.push<void>(
      WaxRoute.tracks,
      extra: TrackListArgs(
        title: 'Similar to ${seed.title}',
        basis: similar.basis,
        items: similar.items,
        idPrefix: 'similar',
      ),
    );
  } on WaxDeckApiException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(e.message)));
  }
}
