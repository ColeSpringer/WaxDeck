import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../connect/device_picker.dart';
import '../connect/remote_session.dart';
import '../desktop/mini_window.dart';
import '../artwork/artwork_providers.dart';
import '../media_view.dart';
import '../playlists/add_to_playlist_sheet.dart';
import '../providers.dart';
import '../queue/queue_controller.dart';
import '../queue/queue_view.dart';
import '../queue/queue_persistence.dart';
import '../queue/queue_state.dart';
import '../radio/radio_controller.dart';
import '../settings/client_prefs.dart';
import '../sharing/share_dialog.dart';
import '../shell/commands.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'autoplay_gate.dart';
import 'lyrics.dart';
import 'now_playing_controller.dart';
import 'output_volume.dart';
import 'play_state_controller.dart';
import 'playback_session.dart';

/// How far the spoken-word skips jump, per this device's Playback
/// settings. Both are read here rather than in the transports, so the
/// control's label and the seek it performs cannot disagree.
final skipIntervalsProvider = Provider<({Duration back, Duration forward})>(
  (ref) => (
    back: Duration(seconds: ref.watch(skipBackSecondsProvider)),
    forward: Duration(seconds: ref.watch(skipForwardSecondsProvider)),
  ),
);

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
  lyrics: SemanticsIds.deckLyrics,
  cast: SemanticsIds.deckCast,
  volume: SemanticsIds.deckVolume,
  mute: SemanticsIds.deckMute,
  more: SemanticsIds.deckMore,
);

/// The deck bar, bound to what this app is playing.
///
/// It lives in the shell's own slot, outside every branch navigator, so
/// playback survives navigation and has one home on every screen. What
/// it shows, in order: the station when live radio has the engine, the
/// queue's current entry when there is one, a session this client is
/// driving on another endpoint, the queue a launch found when there is
/// one to offer back, and otherwise nothing at all - a bar with no item
/// is a stripe of surface, and the first-run library should not have one.
///
/// The remote session sits *below* local playback in that order, which is
/// the one ordering decision here worth its own paragraph. The bar's
/// promise is "this is what you are listening to", and local playback is
/// what is coming out of this device. Handing a session away stops local
/// playback - the server routes a stop to the source client - so the
/// remote face is what fills the silence, which is the case the entry
/// scheduling this named. Opening someone else's session to skip a track
/// while an album plays here does not take the bar away from the album;
/// the remote screen that opened is where that session is driven.
class DeckBarHost extends ConsumerWidget {
  const DeckBarHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final station = ref.watch(radioPlaybackProvider);
    if (station.station != null) return _RadioDeckBar(playback: station);

    final now = ref.watch(nowPlayingProvider);
    if (now.entry != null) return _PlayingDeckBar(now: now);

    final remote = ref.watch(remoteSessionProvider);
    if (remote != null) return _RemoteDeckBar(remote: remote);

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
    // Same reasoning for the level: the compact bar draws no right
    // cluster, so it does not follow the engine's gain either. Both
    // conditions have to hold - the platform gives local output a slider,
    // and this width has somewhere to put one.
    final localVolume = wide && ref.watch(localVolumeAvailableProvider);
    final volume = localVolume ? ref.watch(outputVolumeProvider) : null;
    final starred = wide && item != null
        ? ref.watch(playStateControllerProvider(item.pid)).value?.starred ??
              false
        : false;

    final spokenWord = item != null && item.mediaType != MediaType.music;
    // Read whatever the bar is showing, so the two controls do not
    // appear at one distance and jump another after a settings change.
    final skips = ref.watch(skipIntervalsProvider);

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
          volume: volume,
        ),
        ids: _ids,
        positionTicker: _position,
        autoplayBlocked: blocked,
        actions: DeckBarActions(
          // The command, not a copy: the key and the button are one verb.
          onPlayPause: () => togglePlayback(ref),
          onNext: () => unawaited(playback.next()),
          onPrevious: () => unawaited(playback.previous()),
          onSkipBack: spokenWord && session != null
              ? () => seekBy(ref, -skips.back)
              : null,
          onSkipForward: spokenWord && session != null
              ? () => seekBy(ref, skips.forward)
              : null,
          // The same two durations the seeks use, so the controls
          // announce the distance they actually travel.
          skipBackBy: skips.back,
          skipForwardBy: skips.forward,
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
          onQueue: () => openQueue(context, ref),
          // Music only, and only where the bar has a right cluster to
          // put it in: a track has words and a station, an episode, and
          // a chapter do not, and 5.2's lyrics toggle is one of the
          // controls the compact bar drops.
          onLyrics: wide && session != null && item != null && !spokenWord
              ? () => openLyrics(context, ref)
              : null,
          onVolume: localVolume
              ? (level) => unawaited(
                  ref.read(outputVolumeProvider.notifier).set(level),
                )
              : null,
          onMute: localVolume
              ? () => unawaited(
                  ref.read(outputVolumeProvider.notifier).toggleMute(),
                )
              : null,
          onCast: item == null
              ? null
              : () => unawaited(
                  showDevicePicker(
                    context,
                    from: CastSource.here,
                    currentPid: item.pid,
                    positionMs: session?.displayPosition.inMilliseconds ?? 0,
                  ),
                ),
        ),
      ),
    );
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
    // The same two conditions the item bar reads: this platform hands
    // local output a slider, and this width has a right cluster to put
    // one in. A station is the engine's output like anything else, so
    // leaving this off was a bar with a level on every screen except the
    // one live radio was playing on.
    final localVolume =
        WaxSizeClass.of(context).hasSidebar &&
        ref.watch(localVolumeAvailableProvider);
    final volume = localVolume ? ref.watch(outputVolumeProvider) : null;
    return _EngineTransport(
      builder: (context, playing) => DeckBar(
        ids: _ids,
        now: NowPlayingData(
          title: station.name,
          subtitle: playback.nowPlaying,
          // Through the proxy, like the hub's tiles: the station host's own
          // URL is the direct fetch the logo endpoint exists to replace,
          // and on web most of them would not draw at all.
          artwork: waxStationLogo(
            ref.watch(artworkStoreProvider),
            ref.watch(repositoryProvider),
            station,
          ),
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
          volume: volume,
        ),
        autoplayBlocked: blocked,
        actions: DeckBarActions(
          // Stop, not pause: a paused live stream resumes at the live
          // edge anyway, and the transport should not pretend otherwise.
          // Which of stop and start it is belongs to the controller,
          // which is the one thing that can see why a station is
          // silent - a refused start, or a stream that ended on its
          // own. Through the same command the play key runs.
          onPlayPause: () => togglePlayback(ref),
          onVolume: localVolume
              ? (level) => unawaited(
                  ref.read(outputVolumeProvider.notifier).set(level),
                )
              : null,
          onMute: localVolume
              ? () => unawaited(
                  ref.read(outputVolumeProvider.notifier).toggleMute(),
                )
              : null,
          // The player, like every other face of this bar: expanding
          // means "show me what is playing", and since P19 that is a
          // station's own face rather than the hub it was tuned from.
          // The hub is still one row away, in the face's overflow.
          onExpand: () => context.push(WaxRoute.nowPlaying),
        ),
      ),
    );
  }
}

/// The bar while playback is happening on another endpoint.
///
/// Everything on it is routed rather than local: the transport goes over
/// the command bus, the position is extrapolated against the server clock,
/// and the level - when the endpoint says it has one - is the endpoint's
/// own. What makes it the *remote* face is `remoteEndpoint`, which the bar
/// draws as a cast glyph on the artwork and an "on [name]" caption, so a
/// glance says where the sound is rather than leaving a silent device
/// looking broken.
///
/// No artwork: a session frame carries a title, an artist, and a duration
/// per entry and no cover, so the bar draws a monogram from the title.
/// Asking the catalog for one would be a request per crossing for a
/// 48-pixel square, and the pid a frame carries is the item's, which the
/// player screen is the surface for.
class _RemoteDeckBar extends ConsumerWidget {
  const _RemoteDeckBar({required this.remote});

  final RemoteSession remote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(remoteSessionProvider.notifier);
    final entry = remote.currentEntry;
    final session = remote.session;
    // The endpoint's level, not this device's, and only where the endpoint
    // says it can be told: the server refuses `set-volume` on one that
    // reports none, so a slider without this check is a control whose
    // every use is an error.
    //
    // Not width-gated the way the local one is, because this is not a
    // decision this widget gets to make: the bar draws a right cluster
    // only in its three-zone layout, so a level handed to a compact bar
    // is simply not drawn. Below sidebar width the endpoint's slider is on
    // the remote screen, one tap away through the bar - a 64 px bar
    // holding 48 px of artwork, a title block, and a transport has no
    // room for a track, and squeezing one in is how that bar stops being
    // one line.
    final volume = remote.volumeControl ? (remote.volume ?? 1.0) : null;

    return DeckBar(
      ids: _ids,
      now: NowPlayingData(
        title: entry?.title ?? 'Playing',
        subtitle: entry?.artist,
        remoteEndpoint: remote.endpointName,
        position: controller.position.value,
        duration: remote.duration,
        playing: session.playing,
        volume: volume,
      ),
      positionTicker: controller.position,
      actions: DeckBarActions(
        onPlayPause: () => unawaited(_report(context, controller.toggle())),
        onNext: () => unawaited(_report(context, controller.next())),
        onPrevious: () => unawaited(_report(context, controller.previous())),
        onSeek: (at) => unawaited(_report(context, controller.seek(at))),
        // No _report: the level fires per step crossed and the
        // controller swallows refusals - the knob following the frames
        // is the report.
        onVolume: volume == null
            ? null
            : (level) => unawaited(controller.setVolume(level)),
        // No mute: the level lives on the other endpoint and this client
        // has nowhere to remember what it silenced, so the glyph stays a
        // label rather than becoming a control that cannot undo itself.
        // The slider reaches zero on its own.
        onExpand: () => context.push(WaxRoute.remote),
        // The cast control is how you get back: the picker is where
        // leaving a remote session is spelled out as a choice.
        onCast: () =>
            unawaited(showDevicePicker(context, from: CastSource.elsewhere)),
      ),
    );
  }

  /// Says why a routed command did nothing.
  ///
  /// Every verb here crosses a network and a second device, so a refusal
  /// is ordinary rather than exceptional - an endpoint that has gone
  /// offline, a command that timed out, a device in the middle of
  /// something. The bus keeps the server's own code and message, and that
  /// message is what a listener reads.
  Future<void> _report(BuildContext context, Future<void> work) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await work;
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
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
      // count is all there is to say - and it is enough to decide on.
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
              unawaited(showAddToPlaylistSheet(rootContext, item: item));
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
          // Desktop, and only where the window layer answered: the
          // sheet's other rows are true everywhere, and a row that
          // opened nothing on a phone would be the one exception.
          if (ref.read(miniWindowProvider).available)
            Semantics(
              // A registered id that never reaches the tree is a spec
              // that matches nothing (rule 8).
              identifier: SemanticsIds.deckMiniWindow,
              button: true,
              child: ListTile(
                key: const ValueKey(SemanticsIds.deckMiniWindow),
                leading: const WaxIcon(WaxIcons.collapse),
                title: const Text('Mini player window'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(ref.read(miniWindowProvider.notifier).enter());
                },
              ),
            ),
        ],
      ),
    ),
  );
}
