import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
import '../media_view.dart';
import '../player/now_playing_controller.dart';
import '../player/playback_session.dart';
import '../providers.dart';
import '../queue/queue_controller.dart';
import '../radio/radio_controller.dart';
import '../shell/commands.dart';
import '../shell/semantics_ids.dart';
import 'desktop_ports.dart';
import 'desktop_ports_io.dart'
    if (dart.library.js_interop) 'desktop_ports_stub.dart';

final miniWindowPortProvider = Provider<MiniWindowPort>(
  (ref) => createMiniWindowPort(),
);

/// Whether the app is wearing its mini window, and what this compositor
/// would let that window be.
class MiniWindowState {
  const MiniWindowState({
    this.capabilities = MiniWindowCapabilities.none,
    this.showing = false,
  });

  final MiniWindowCapabilities capabilities;
  final bool showing;

  /// Whether there is a mini window to offer at all. False on web and
  /// both mobiles, where the app does not own a window.
  bool get available => capabilities.available;

  MiniWindowState copyWith({
    MiniWindowCapabilities? capabilities,
    bool? showing,
  }) => MiniWindowState(
    capabilities: capabilities ?? this.capabilities,
    showing: showing ?? this.showing,
  );
}

/// Owns the mini window: what the compositor will allow, and whether the
/// app is currently wearing it.
///
/// The capabilities are probed once and held, rather than asked at the
/// moment of the toggle, because two surfaces read them synchronously -
/// the command's `enabled`, and the deck bar's overflow - and neither
/// gets to await.
class MiniWindowController extends Notifier<MiniWindowState> {
  /// Not `late final`: Riverpod re-runs `build` on the same notifier
  /// instance, and a second assignment would throw.
  late MiniWindowPort _port;

  /// Whether the window is small, held beside the state rather than read
  /// from it on the way out: reading a notifier's state from inside a
  /// disposal callback is forbidden outright, and the window still has
  /// to be put back.
  bool _small = false;

  @override
  MiniWindowState build() {
    _port = ref.read(miniWindowPortProvider);
    unawaited(_probe());
    ref.onDispose(() {
      // A container going away with the window still small would leave a
      // 320 px window behind for the next launch to find.
      if (_small) unawaited(_port.leave());
    });
    return const MiniWindowState();
  }

  Future<void> _probe() async {
    final capabilities = await _port.probe();
    if (!ref.mounted) return;
    state = state.copyWith(capabilities: capabilities);
  }

  Future<void> toggle() => state.showing ? leave() : enter();

  Future<void> enter() async {
    if (!state.available || state.showing) return;
    // The state moves first: the window shrinking and the app swapping
    // to the mini player are one change, and doing the platform half
    // first shows a full shell squeezed into 320 pixels for a frame.
    _small = true;
    state = state.copyWith(showing: true);
    await _port.enter(state.capabilities);
  }

  Future<void> leave() async {
    if (!state.showing) return;
    _small = false;
    state = state.copyWith(showing: false);
    await _port.leave();
  }

  /// A drag begun on the mini player's background.
  void drag() => unawaited(_port.startDragging());
}

final miniWindowProvider =
    NotifierProvider<MiniWindowController, MiniWindowState>(
      MiniWindowController.new,
    );

/// The command that opens and closes it.
///
/// Ctrl/Cmd+Shift+M rather than the bare M the mute key took: this is a
/// window-level verb, and the modifiers are what every other window verb
/// on a desktop wears.
///
/// `offered` rather than `enabled`, so a build with no window to shrink
/// does not bind the chord, list it in the palette, or teach it in the
/// reference sheet. Watched rather than read: the answer arrives from a
/// platform probe a moment after launch.
final WaxCommand miniWindowCommand = WaxCommand(
  id: 'mini-window',
  section: WaxCommandSection.view,
  glyph: WaxIcons.collapse,
  activators: const <ShortcutActivator>[
    SingleActivator(LogicalKeyboardKey.keyM, control: true, shift: true),
    SingleActivator(LogicalKeyboardKey.keyM, meta: true, shift: true),
  ],
  offered: (ref) => ref.watch(miniWindowProvider.select((s) => s.available)),
  run: (context, ref) =>
      unawaited(ref.read(miniWindowProvider.notifier).toggle()),
);

/// Wears the mini player while the window is small.
///
/// The app underneath is kept mounted and stops being drawn, rather than
/// replaced: every provider the signed-in scope owns - the sync engine,
/// playback, the download queue, the media session feed - hangs off that
/// subtree, and swapping it out would tear all of them down every time
/// somebody made the window small.
class MiniWindowGate extends ConsumerWidget {
  const MiniWindowGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(miniWindowProvider.select((s) => s.showing))) return child;
    return Stack(
      children: <Widget>[
        // Not laid out and not ticking: the shell behind a mini window
        // is a whole app's worth of animation nobody can see.
        Offstage(child: TickerMode(enabled: false, child: child)),
        // Filled and centred rather than left at its own size in the
        // corner: the window is still whatever size it was for the frame
        // between the state moving and the compositor answering, and an
        // unpainted three quarters of a window is what that would look
        // like.
        Positioned.fill(
          child: ColoredBox(
            color: WaxColors.of(context).canvas,
            child: const Center(child: _MiniWindowSurface()),
          ),
        ),
      ],
    );
  }
}

class _MiniWindowSurface extends ConsumerStatefulWidget {
  const _MiniWindowSurface();

  @override
  ConsumerState<_MiniWindowSurface> createState() => _MiniWindowSurfaceState();
}

class _MiniWindowSurfaceState extends ConsumerState<_MiniWindowSurface> {
  /// The live position, fed into the hairline alone. Same reasoning as
  /// the deck bar's: a window that rebuilt several times a second would
  /// be the most repeated frame work a minimized app does.
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  StreamSubscription<Duration>? _feed;
  PlaybackSession? _following;

  @override
  void dispose() {
    unawaited(_feed?.cancel());
    _position.dispose();
    super.dispose();
  }

  void _follow(PlaybackSession? session) {
    if (identical(session, _following)) return;
    _following = session;
    unawaited(_feed?.cancel());
    _position.value = session?.displayPosition ?? Duration.zero;
    _feed = session?.displayPositionStream.listen((at) => _position.value = at);
  }

  @override
  Widget build(BuildContext context) {
    final mini = ref.read(miniWindowProvider.notifier);
    final station = ref.watch(radioPlaybackProvider);
    final now = ref.watch(nowPlayingProvider);
    _follow(now.session);
    final engine = ref.watch(audioEngineProvider);
    final item = now.item;

    return StreamBuilder<bool>(
      stream: engine.playingStream,
      initialData: engine.playing,
      builder: (context, snapshot) {
        final playing = snapshot.data ?? engine.playing;
        final live = station.station != null;
        return MiniPlayer(
          now: live
              ? NowPlayingData(
                  title: station.station!.name,
                  subtitle: station.nowPlaying,
                  artwork: waxStationLogo(
                    ref.watch(artworkStoreProvider),
                    ref.watch(repositoryProvider),
                    station.station!,
                  ),
                  domain: WaxDomain.radio,
                  shape: ArtworkShape.circle,
                  position: Duration.zero,
                  duration: Duration.zero,
                  live: true,
                  playing: playing || station.starting,
                )
              : NowPlayingData(
                  title: item?.title ?? context.l10n.playerNothingPlaying,
                  subtitle: item?.artist,
                  artwork: waxArtwork(
                    ref.watch(artworkStoreProvider),
                    item?.artUrl,
                  ),
                  domain: waxDomainOf(item?.mediaType ?? MediaType.music),
                  shape: waxShapeOf(item?.mediaType ?? MediaType.music),
                  position: _position.value,
                  duration:
                      now.session?.mediaDuration ??
                      Duration(milliseconds: item?.durationMs ?? 0),
                  playing: playing,
                ),
          positionTicker: _position,
          ids: const MiniPlayerIds(
            surface: SemanticsIds.miniWindow,
            play: SemanticsIds.miniWindowPlay,
            next: SemanticsIds.miniWindowNext,
            previous: SemanticsIds.miniWindowPrevious,
            restore: SemanticsIds.miniWindowRestore,
          ),
          actions: DeckBarActions(
            // The same commands the keys and the deck bar run: a mini
            // window is a smaller surface onto one playback, not a
            // second transport with rules of its own.
            onPlayPause: () => togglePlayback(ref),
            onNext: live || !ref.watch(queueCanAdvanceProvider)
                ? null
                : () => unawaited(ref.read(nowPlayingProvider.notifier).next()),
            onPrevious: live
                ? null
                : () => unawaited(
                    ref.read(nowPlayingProvider.notifier).previous(),
                  ),
          ),
          onRestore: () => unawaited(mini.leave()),
          onDrag: mini.drag,
        );
      },
    );
  }
}
