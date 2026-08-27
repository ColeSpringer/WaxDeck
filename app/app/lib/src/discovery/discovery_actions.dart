import 'dart:async';

import 'package:waxdeck_ui/waxdeck_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../l10n/l10n.dart';
import '../player/now_playing_controller.dart';
import '../providers.dart';
import '../queue/queue_controller.dart';
import '../queue/queue_state.dart';
import '../queue/queue_view.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';

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

/// What an instant mix grows from: a track's pid or an album entity's
/// (`POST /mixes/instant` accepts either as its seed), and the name the
/// sheet shows for it. A record rather than an `ItemSummary` because an
/// album row has no summary in hand, and the sheet never needed more
/// than these two.
typedef MixSeed = ({String pid, String title});

/// Opens the instant-mix sheet for a seed. Confirming builds the mix
/// and starts playing it.
Future<void> showInstantMixSheet(BuildContext context, MixSeed seed) =>
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => InstantMixSheet(seed: seed),
    );

/// Adventurousness slider plus the Mix confirm. The chosen value is
/// remembered for the next launch.
class InstantMixSheet extends ConsumerStatefulWidget {
  const InstantMixSheet({super.key, required this.seed});

  final MixSeed seed;

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
    final shell = ref.read(shellMessengerProvider.notifier);
    final l10n = context.l10n;
    final playback = ref.read(nowPlayingProvider.notifier);
    // What the mix must not repeat, as it stands when the mix is asked
    // for: the current entry and what is still coming. Played history is
    // left mixable - on a small library the whole queue was the whole
    // catalog, and the mix came back empty for it. The branch below
    // reads the queue again: a track started while the mix built is a
    // standing queue too, and wiping it because it was empty a moment
    // ago is the destruction this whole branch exists to avoid.
    final queued = ref.read(queueControllerProvider).upcomingPids;
    // Read here for the same reason as the four above: the message's
    // action fires after this sheet has popped. Over the shell, because
    // the sheet's own route is over the player, which is over the shell:
    // a panel opened from here would open behind both.
    final showQueue = queueOpener(context, ref, overShell: true);
    try {
      final mix = await ref
          .read(repositoryProvider)
          .createInstantMix(
            seedPid: widget.seed.pid,
            adventurousness: _adventurousness,
            size: instantMixSize,
            // A mix landing behind a standing queue must not repeat what
            // is already in it. Harmless when there is no queue.
            excludePids: queued,
          );
      // Dismissed while the mix was building: that is a cancel, and
      // popping again from here would take the screen underneath with
      // it.
      if (!mounted) return;
      navigator.pop();
      if (mix.items.isEmpty) {
        // Two different empty answers: candidates that are all already
        // queued, and a seed with no candidates at all. The count is
        // what tells them apart.
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                mix.excluded > 0
                    ? l10n.discoveryMixAllQueued
                    : l10n.discoveryMixEmpty,
              ),
            ),
          );
        return;
      }
      // Read again rather than reusing the snapshot above: `mounted` is
      // checked a few lines up, so the container is still there.
      if (ref.read(queueControllerProvider).isNotEmpty) {
        // Something is already queued, so the mix goes behind it and the
        // song playing keeps playing. No route push either: nothing on
        // screen was asked to change, and the message is the way to what
        // did. Through the shell rather than a bare SnackBarAction,
        // which carries no semantics identifier for the button.
        playback.enqueue(mix.items);
        shell.show(
          mix.items.length == 1
              ? l10n.queueAddedOne(mix.items.first.title)
              : l10n.queueAddedMany(mix.items.length),
          actionLabel: l10n.queueOpenAction,
          onAction: showQueue,
          actionSemanticsId: SemanticsIds.queueOpen,
        );
        return;
      }
      // An empty queue: mirror how playlists start playback. The mix
      // list stands in for the playlist screen, playback starts in the
      // dock, and the deck bar is the way into the full player. Route
      // futures resolve on pop, so the push is not awaited.
      //
      // Reached whenever the sheet rises with nothing playing - a
      // listing row's or a card's Instant mix, not just the player's
      // own menu - and this is the right answer there: enqueueing
      // behind nothing would leave the tracks queued and silent.
      unawaited(
        router.push<void>(
          WaxRoute.tracks,
          extra: TrackListArgs(
            title: l10n.discoveryInstantMixTitle,
            basis: mix.basis,
            items: mix.items,
            idPrefix: 'mix',
          ),
        ),
      );
      playback.play(
        mix.items,
        // No label: a mix seeded by one track has no name of its own,
        // and the label is stored with the queue. The queue's own
        // provenance line words the kind instead.
        source: const QueueSource(kind: QueueSourceKind.mix, label: ''),
      );
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(WaxSpace.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // No gap of its own: SectionHeader owns its bottom s12.
            SectionHeader(title: l10n.discoveryInstantMixTitle),
            Text(
              l10n.discoveryInstantMixFrom(widget.seed.title),
              style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: WaxSpace.s8),
            Row(
              children: [
                Text(l10n.discoveryFamiliar),
                Expanded(
                  child: Semantics(
                    identifier: SemanticsIds.mixAdventurousness,
                    label: l10n.discoveryAdventurousness,
                    child: Slider(
                      key: const Key(SemanticsIds.mixAdventurousness),
                      value: _adventurousness,
                      onChanged: (v) => setState(() => _adventurousness = v),
                    ),
                  ),
                ),
                Text(l10n.discoveryAdventurous),
              ],
            ),
            const SizedBox(height: WaxSpace.s8),
            Semantics(
              identifier: SemanticsIds.instantMixRun,
              label: l10n.discoveryMixAction,
              button: true,
              child: FilledButton(
                key: const Key(SemanticsIds.instantMixRun),
                onPressed: _busy ? null : _mix,
                child: Text(l10n.discoveryMixAction),
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
  final l10n = context.l10n;
  try {
    final similar = await ref
        .read(repositoryProvider)
        .getSimilarTracks(seed.pid, limit: instantMixSize);
    await router.push<void>(
      WaxRoute.tracks,
      extra: TrackListArgs(
        title: l10n.discoverySimilarTitle(seed.title),
        // No source label, the way the instant mix has none: tracks
        // like this one are not this one, so naming the seed would have
        // the queue claim a provenance the list does not have.
        basis: similar.basis,
        items: similar.items,
        idPrefix: 'similar',
      ),
    );
  } on WaxDeckApiException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
  }
}
