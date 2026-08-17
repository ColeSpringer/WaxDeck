import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_palette.dart';
import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
import '../media_view.dart';
import '../queue/queue_controller.dart';
import '../shell/semantics_ids.dart';
import 'now_playing_controller.dart';
import 'now_playing_view.dart';
import 'playback_session.dart';
import 'player_screen.dart';
import 'wake_port.dart';
import 'waveform.dart';

/// The track, drawn large.
///
/// Everything here comes off the analyze pass: the peaks the seek bar
/// already reads, and the position. Nothing is synthesised, which is the
/// decision the whole surface rests on - a spectrum this app cannot
/// measure would be an animation pretending to be a measurement, and the
/// people who run their own music server can tell the difference.
///
/// A track with no peaks has no picture, and says so. That is most
/// tracks on a server whose analyze pass has never run, so the empty
/// state names the pass rather than shrugging.
class VisualizerScreen extends ConsumerWidget {
  const VisualizerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return KeepAwake(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: NowPlayingView(
          idle: (context) => _Frame(
            domain: WaxDomain.music,
            child: EmptyState(
              glyph: WaxIcons.waveform,
              title: context.l10n.playerNothingPlaying,
              message: context.l10n.playerVisualizerIdleMessage,
              semanticsId: SemanticsIds.visualizerSurface,
            ),
          ),
          builder: (context, session, item, position) =>
              _Visualizer(session: session, item: item, position: position),
        ),
      ),
    );
  }
}

/// The backdrop and the way out, which every state needs.
class _Frame extends StatelessWidget {
  const _Frame({required this.child, required this.domain, this.artUrl});

  final Widget child;
  final WaxDomain domain;
  final String? artUrl;

  @override
  Widget build(BuildContext context) {
    return ArtworkAccent(
      artUrl: artUrl,
      domain: domain,
      child: WaxBackdrop(
        domain: domain,
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s8),
                  child: WaxIconButton(
                    glyph: WaxIcons.collapse,
                    label: context.l10n.playerLeaveVisualizer,
                    onPressed: () => leavePlayer(context),
                    semanticsId: SemanticsIds.visualizerClose,
                  ),
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _Visualizer extends ConsumerStatefulWidget {
  const _Visualizer({
    required this.session,
    required this.item,
    required this.position,
  });

  final PlaybackSession session;
  final ItemSummary item;
  final ValueListenable<Duration> position;

  @override
  ConsumerState<_Visualizer> createState() => _VisualizerState();
}

class _VisualizerState extends ConsumerState<_Visualizer> {
  /// How long the chrome stays after the last input (5.6).
  static const Duration _linger = Duration(seconds: 3);

  WaxVisualizerMode _mode = WaxVisualizerMode.waveform;
  bool _controls = true;
  Timer? _hide;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Here rather than in `initState`, because what decides whether the
    // countdown runs at all is a media query - and because a screen
    // reader switched on while this is open has to put the controls
    // back, which is exactly the rebuild this hook answers.
    _arm();
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  /// Shows the chrome and starts the countdown that takes it away again.
  /// Any input at all calls this: a tap, a scrub, a mode change, a
  /// transport press.
  ///
  /// The countdown does not run under a screen reader. Chrome faded to
  /// nothing leaves the semantics tree with it, so auto-hiding would put
  /// the transport, the mode switch, and the way out beyond reach with
  /// no node left to touch to bring them back - the reveal is a pointer
  /// event, and a pointer event needs something to land on.
  void _arm() {
    _hide?.cancel();
    _hide = null;
    if (!_controls) setState(() => _controls = true);
    if (MediaQuery.accessibleNavigationOf(context)) return;
    _hide = Timer(_linger, () {
      if (mounted) setState(() => _controls = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    // The whole async value, not its `value`. That reads null while the
    // read is still in flight as well as when there is nothing to draw,
    // and the two want opposite answers here: the seek bar can share one
    // branch because its fallback is a plain bar, but a full-screen
    // instruction to go and run an analyze pass is not a thing to show
    // somebody for the length of a round trip.
    final waveform = ref.watch(waveformProvider(item.pid));
    return _Frame(
      domain: waxDomainOf(item.mediaType),
      artUrl: item.artUrl,
      child: switch (waveform) {
        AsyncData(value: final peaks?) when peaks.isNotEmpty => _stage(peaks),
        AsyncLoading() => const Center(child: CircularProgressIndicator()),
        _ => EmptyState(
          glyph: WaxIcons.waveform,
          title: context.l10n.playerNoShape,
          message: context.l10n.playerNoShapeMessage,
          semanticsId: SemanticsIds.visualizerSurface,
        ),
      },
    );
  }

  Widget _stage(List<double> peaks) {
    return Listener(
      // Every pointer that touches the surface reveals the chrome,
      // including the drags the stage swallows for scrubbing: a listener
      // scrubbing is a listener using the controls, and a surface that
      // hid them mid-drag would be arguing with the hand on it.
      onPointerDown: (_) => _arm(),
      onPointerMove: (_) => _arm(),
      child: StreamBuilder<bool>(
        stream: widget.session.engine.playingStream,
        initialData: widget.session.engine.playing,
        builder: (context, snapshot) {
          final playing = snapshot.data ?? false;
          return Column(
            children: <Widget>[
              Expanded(
                child: VisualizerStage(
                  position: widget.position,
                  duration: widget.session.mediaDuration,
                  peaks: peaks,
                  mode: _mode,
                  playing: playing,
                  artwork: waxArtwork(
                    ref.read(artworkStoreProvider),
                    widget.item.artUrl,
                  ),
                  monogram: widget.item.title,
                  domain: waxDomainOf(widget.item.mediaType),
                  onSeek: (to) => unawaited(widget.session.seek(to)),
                  semanticsId: SemanticsIds.visualizerSurface,
                ),
              ),
              // Held in the tree rather than removed, so the picture does
              // not resize every three seconds: what auto-hides is the
              // chrome's paint, not the room it takes.
              IgnorePointer(
                ignoring: !_controls,
                child: AnimatedOpacity(
                  opacity: _controls ? 1 : 0,
                  duration: WaxMotion.of(context).standard,
                  child: _chrome(playing),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _chrome(bool playing) {
    final playback = ref.read(nowPlayingProvider.notifier);
    final music = widget.item.mediaType == MediaType.music;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WaxSpace.s24,
        WaxSpace.s8,
        WaxSpace.s24,
        WaxSpace.s24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          WaxSegmented(
            label: context.l10n.playerVisualizerMode,
            selected: _mode.name,
            segments: <WaxSegment>[
              for (final mode in WaxVisualizerMode.values)
                WaxSegment(
                  name: mode.name,
                  label: mode.label(context.waxL10n),
                  semanticsId: SemanticsIds.visualizerMode(mode.name),
                ),
            ],
            onSelect: (name) {
              _arm();
              setState(() => _mode = WaxVisualizerMode.values.byName(name));
            },
          ),
          const SizedBox(height: WaxSpace.s12),
          ValueListenableBuilder<Duration>(
            valueListenable: widget.position,
            builder: (context, at, _) => SeekCluster(
              now: NowPlayingData(
                title: widget.item.title,
                position: at,
                duration: widget.session.mediaDuration,
                playing: playing,
              ),
              onSeek: (to) {
                _arm();
                unawaited(widget.session.seek(to));
              },
              semanticsId: SemanticsIds.visualizerSeek,
            ),
          ),
          const SizedBox(height: WaxSpace.s8),
          TransportCluster(
            // Its own handles rather than the player's: the player is
            // still mounted underneath this pushed route, and two nodes
            // answering to one identifier is a spec that steers the
            // wrong one.
            ids: const PlayerIds(
              play: SemanticsIds.visualizerToggle,
              next: SemanticsIds.visualizerNext,
              previous: SemanticsIds.visualizerPrevious,
            ),
            playing: playing,
            onPlayPause: () {
              _arm();
              unawaited(widget.session.toggle());
            },
            // Music alone gets neighbours here: the visualizer is the
            // music face's own surface, and a podcast opened into it by
            // a shortcut has skips rather than tracks.
            onPrevious: music
                ? () {
                    _arm();
                    unawaited(playback.previous());
                  }
                : null,
            onNext: music
                ? () {
                    _arm();
                    unawaited(playback.next());
                  }
                : null,
            canNext: ref.watch(queueCanAdvanceProvider),
          ),
        ],
      ),
    );
  }
}
