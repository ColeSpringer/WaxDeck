import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../connect/device_picker.dart';
import '../artwork/artwork_providers.dart';
import '../media_view.dart';
import '../playlists/add_to_playlist_dialog.dart';
import '../providers.dart';
import '../queue/queue_controller.dart';
import '../queue/queue_panel.dart';
import '../queue/queue_persistence.dart';
import '../queue/queue_state.dart';
import '../radio/radio_controller.dart';
import '../sharing/share_dialog.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/side_panel.dart';
import 'autoplay_gate.dart';
import 'now_playing_controller.dart';
import 'play_state_controller.dart';
import 'playback_session.dart';

/// How far the spoken-word skips jump. Configurable per listener when
/// the settings store lands; these are the defaults every client ships.
const Duration kSkipBack = Duration(seconds: 15);
const Duration kSkipForward = Duration(seconds: 30);

/// The e2e handles this bar's controls carry. One place, because the
/// design system emits no identifier strings of its own (ADR-0016).
const _ids = DeckBarIds(
  bar: SemanticsIds.deckBar,
  play: SemanticsIds.deckPlay,
  next: SemanticsIds.deckNext,
  previous: SemanticsIds.deckPrevious,
  skipBack: SemanticsIds.deckSkipBack,
  skipForward: SemanticsIds.deckSkipForward,
  shuffle: SemanticsIds.deckShuffle,
  repeat: SemanticsIds.deckRepeat,
  star: SemanticsIds.deckStar,
  seek: SemanticsIds.deckSeek,
  queue: SemanticsIds.deckQueue,
  cast: SemanticsIds.deckCast,
  more: SemanticsIds.deckMore,
);

/// The deck bar, bound to what this app is playing.
///
/// It lives in the shell's own slot, outside every branch navigator, so
/// playback survives navigation and has one home on every screen. What
/// it shows, in order: the station when live radio has the engine, the
/// queue's current entry when there is one, the queue a launch found
/// when there is one to offer back, and otherwise nothing at all —
/// a bar with no item is a stripe of surface, and the first-run library
/// should not have one.
class DeckBarHost extends ConsumerWidget {
  const DeckBarHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final station = ref.watch(radioPlaybackProvider);
    if (station.station != null) return _RadioDeckBar(playback: station);

    final now = ref.watch(nowPlayingProvider);
    if (now.entry != null) return _PlayingDeckBar(now: now);

    final offer = ref.watch(queueRestoreProvider).value;
    if (offer != null) return _OfferDeckBar(offer: offer);
    return const SizedBox.shrink();
  }
}

/// The bar while an item is playing, loading, or standing where a
/// failure left it.
class _PlayingDeckBar extends ConsumerStatefulWidget {
  const _PlayingDeckBar({required this.now});

  final NowPlaying now;

  @override
  ConsumerState<_PlayingDeckBar> createState() => _PlayingDeckBarState();
}

class _PlayingDeckBarState extends ConsumerState<_PlayingDeckBar> {
  /// The live position, fed straight into the bar's ticking leaf. The
  /// bar itself never rebuilds for it: it is on screen for the whole
  /// session, and a full rebuild several times a second is the most
  /// repeated frame work the app would do.
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  StreamSubscription<Duration>? _feed;

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(covariant _PlayingDeckBar old) {
    super.didUpdateWidget(old);
    if (!identical(old.now.session, widget.now.session)) _follow();
  }

  void _follow() {
    unawaited(_feed?.cancel());
    final session = widget.now.session;
    _position.value = session?.displayPosition ?? Duration.zero;
    _feed = session?.displayPositionStream.listen((position) {
      _position.value = position;
    });
  }

  @override
  void dispose() {
    unawaited(_feed?.cancel());
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now;
    final item = now.item;
    final session = now.session;
    final playback = ref.read(nowPlayingProvider.notifier);
    // The two standing modes and nothing else about the queue: watching
    // the whole of it would rebuild the bar on every edit, and a drag
    // reorder emits one per frame.
    final modes = ref.watch(
      queueControllerProvider.select((q) => (q.shuffled, q.repeat)),
    );
    final blocked = ref.watch(autoplayBlockedProvider);
    // The star is drawn on the three-zone bar only, so only that bar
    // asks the server for a play state: the compact bar would otherwise
    // fetch one per track for a control it does not show.
    final wide = WaxSizeClass.of(context).hasSidebar;
    final starred = wide && item != null
        ? ref.watch(playStateControllerProvider(item.pid)).value?.starred ??
              false
        : false;

    final spokenWord = item != null && item.mediaType != MediaType.music;

    return _EngineTransport(
      builder: (context, playing) => DeckBar(
        now: NowPlayingData(
          // An entry that has not resolved yet is still what is
          // playing: the bar names it as soon as it can and never
          // disappears in between.
          title: item?.title ?? 'Loading…',
          subtitle: item?.artist,
          artwork: waxArtwork(ref.watch(artworkStoreProvider), item?.artUrl),
          domain: waxDomainOf(item?.mediaType ?? MediaType.music),
          shape: waxShapeOf(item?.mediaType ?? MediaType.music),
          // The seed the ticking leaf starts from; the live value
          // arrives through positionTicker.
          position: _position.value,
          duration:
              session?.mediaDuration ??
              Duration(milliseconds: item?.durationMs ?? 0),
          playing: playing,
          starred: starred,
          shuffled: modes.$1,
          repeat: switch (modes.$2) {
            QueueRepeat.off => WaxRepeat.off,
            QueueRepeat.all => WaxRepeat.all,
            QueueRepeat.one => WaxRepeat.one,
          },
          speed: spokenWord ? session?.speed : null,
        ),
        ids: _ids,
        positionTicker: _position,
        autoplayBlocked: blocked,
        actions: DeckBarActions(
          // With no session there is nothing to toggle, and two ways to
          // get there keep the entry on the bar: a start that failed,
          // and an item that let the engine go to live radio. The bar's
          // own play button is what takes it back in both.
          onPlayPause: session != null ? session.toggle : playback.resume,
          onNext: () => unawaited(playback.next()),
          onPrevious: () => unawaited(playback.previous()),
          onSkipBack: spokenWord && session != null
              ? () => unawaited(_seekBy(session, -kSkipBack))
              : null,
          onSkipForward: spokenWord && session != null
              ? () => unawaited(_seekBy(session, kSkipForward))
              : null,
          // The same two durations the seeks use, so the controls
          // announce the distance they actually travel.
          skipBackBy: kSkipBack,
          skipForwardBy: kSkipForward,
          onShuffle: () =>
              ref.read(queueControllerProvider.notifier).setShuffle(!modes.$1),
          onRepeat: () => ref
              .read(queueControllerProvider.notifier)
              .setRepeat(nextQueueRepeat(modes.$2)),
          onSeek: session == null ? null : (at) => unawaited(session.seek(at)),
          onStar: item == null || !wide
              ? null
              : (value) => unawaited(
                  ref
                      .read(playStateControllerProvider(item.pid).notifier)
                      .setStarred(value),
                ),
          onExpand: () => context.push(WaxRoute.nowPlaying),
          onLongPress: item == null
              ? null
              : () => unawaited(_showActions(context, ref, item, session)),
          onMore: item == null
              ? null
              : () => unawaited(_showActions(context, ref, item, session)),
          // Only where a panel can open: the queue's own screen is the
          // compact answer and does not exist yet, and a control that
          // opens nothing is worse than one that is not there.
          onQueue: wide
              ? () =>
                    ref.read(sidePanelProvider.notifier).toggle(WaxPanel.queue)
              : null,
          onCast: item == null
              ? null
              : () => unawaited(
                  showDevicePicker(
                    context,
                    ref,
                    currentPid: item.pid,
                    positionMs: session?.displayPosition.inMilliseconds ?? 0,
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _seekBy(PlaybackSession session, Duration delta) {
    final target = session.displayPosition + delta;
    return session.seek(target < Duration.zero ? Duration.zero : target);
  }
}

/// The bar while live radio owns the engine.
///
/// Radio never enters the queue, so nothing here reads the queue: a
/// station has no position, no next, and no pause that means anything,
/// and the bar says so rather than drawing controls that would lie.
class _RadioDeckBar extends ConsumerWidget {
  const _RadioDeckBar({required this.playback});

  final RadioPlayback playback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final station = playback.station!;
    // The gate is the engine's, and a station is started through the
    // same engine: a refused start leaves this bar as the only surface
    // that could say so, and its one control would otherwise read
    // "Play" and stop the station when it was pressed.
    final blocked = ref.watch(autoplayBlockedProvider);
    return _EngineTransport(
      builder: (context, playing) => DeckBar(
        ids: _ids,
        now: NowPlayingData(
          title: station.name,
          subtitle: playback.nowPlaying,
          artwork: waxArtwork(ref.watch(artworkStoreProvider), station.logoUrl),
          domain: WaxDomain.radio,
          shape: ArtworkShape.circle,
          position: Duration.zero,
          duration: Duration.zero,
          live: true,
          // A station still buffering is a station that is on, and the
          // one control here turns it off: reading the engine alone
          // would offer "Play" during the wait and stop the stream when
          // it was pressed.
          playing: (playing || playback.starting) && !blocked,
        ),
        autoplayBlocked: blocked,
        actions: DeckBarActions(
          // Stop, not pause: a paused live stream resumes at the live
          // edge anyway, and the transport should not pretend otherwise.
          // Unless the platform refused the start, where the one thing
          // to do is ask again with a gesture behind it.
          onPlayPause: () => unawaited(
            blocked
                ? ref.read(radioPlaybackProvider.notifier).resume()
                : ref.read(radioPlaybackProvider.notifier).stop(),
          ),
          onExpand: () => context.go(WaxRoute.radio),
        ),
      ),
    );
  }
}

/// The bar as an offer: a queue this launch found, named so accepting it
/// is a decision.
class _OfferDeckBar extends ConsumerWidget {
  const _OfferDeckBar({required this.offer});

  final RestorableQueue offer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = offer.currentItem;
    final restore = ref.read(queueRestoreProvider.notifier);
    return DeckBarOffer(
      // Offline, or for a queue the mirror never learned about, the
      // count is all there is to say — and it is enough to decide on.
      title: item?.title ?? '${offer.length} queued items',
      subtitle: item?.artist ?? 'Pick up where you left off',
      artwork: waxArtwork(ref.watch(artworkStoreProvider), item?.artUrl),
      domain: waxDomainOf(item?.mediaType ?? MediaType.music),
      shape: waxShapeOf(item?.mediaType ?? MediaType.music),
      onResume: restore.accept,
      onDismiss: () => unawaited(restore.dismiss()),
      semanticsId: SemanticsIds.deckOffer,
      resumeSemanticsId: SemanticsIds.deckOfferResume,
      dismissSemanticsId: SemanticsIds.deckOfferDismiss,
    );
  }
}

/// Rebuilds its child when playback starts or stops.
///
/// The engine rather than the session: radio drives the engine directly,
/// and both faces of the bar want the same answer to "is sound coming
/// out". A pause is a rebuild of the bar and nothing above it, which is
/// the budget the deck bar is held to.
class _EngineTransport extends ConsumerWidget {
  const _EngineTransport({required this.builder});

  final Widget Function(BuildContext context, bool playing) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(audioEngineProvider);
    return StreamBuilder<bool>(
      stream: engine.playingStream,
      initialData: engine.playing,
      builder: (context, snapshot) =>
          builder(context, snapshot.data ?? engine.playing),
    );
  }
}

/// The item's context menu: what the bar's overflow opens, and what a
/// long press on it opens too.
Future<void> _showActions(
  BuildContext context,
  WidgetRef ref,
  ItemSummary item,
  PlaybackSession? session,
) {
  // Read at open time, not at tap time: the sheet is a snapshot of where
  // the item stood when it was asked about.
  final positionMs = session?.displayPosition.inMilliseconds ?? 0;
  // Captured for the same reason, and this one is load-bearing. A sheet
  // outlives the surface that opened it, and this one is opened from a
  // bar that comes and goes on its own: clearing the queue, a routed
  // Connect command, or a station taking the engine all replace it while
  // the sheet is still up. Reaching back through the bar's own context
  // then lands on an element that is no longer in the tree. The root
  // navigator and the router outlive both, so what was tapped still
  // happens.
  final rootContext = Navigator.of(context, rootNavigator: true).context;
  final router = GoRouter.of(context);
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: const WaxIcon(WaxIcons.playlists),
            title: const Text('Add to playlist'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              unawaited(
                showDialog<void>(
                  context: rootContext,
                  builder: (_) => AddToPlaylistDialog(item: item),
                ),
              );
            },
          ),
          ListTile(
            leading: const WaxIcon(WaxIcons.share),
            title: const Text('Share link'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              unawaited(
                showShareLinkDialog(
                  rootContext,
                  pid: item.pid,
                  // Episodes offer the current position as the share's
                  // start point; other media share from the top.
                  positionMs: item.mediaType == MediaType.podcast
                      ? positionMs
                      : null,
                ),
              );
            },
          ),
          ListTile(
            leading: const WaxIcon(WaxIcons.expand),
            title: const Text('Open the player'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              router.push<void>(WaxRoute.nowPlaying);
            },
          ),
        ],
      ),
    ),
  );
}
