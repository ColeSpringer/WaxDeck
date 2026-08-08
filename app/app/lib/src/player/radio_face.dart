import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../media_view.dart';
import '../providers.dart';
import '../radio/add_station.dart';
import '../radio/radio_controller.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'autoplay_gate.dart';
import 'output_volume.dart';
import 'player_screen.dart';

/// The player's radio face: one station, live, and nothing that implies
/// otherwise.
///
/// Radio never enters the queue, so there is no seek bar, no next, no
/// repeat, and no speed. What it has instead is the station itself - the
/// logo on a platter, what the stream says is playing, and a way into
/// the library for the track it just named.
class RadioFace extends ConsumerWidget {
  const RadioFace({required this.playback, super.key});

  final RadioPlayback playback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final station = playback.station!;
    final blocked = ref.watch(autoplayBlockedProvider);
    final controller = ref.read(radioPlaybackProvider.notifier);
    final engine = ref.watch(audioEngineProvider);

    return StreamBuilder<bool>(
      stream: engine.playingStream,
      initialData: engine.playing,
      builder: (context, snapshot) {
        // A station still buffering is a station that is on, and the one
        // control here turns it off: reading the engine alone would
        // offer "Play" during the wait and stop the stream when it was
        // pressed. The parentheses are load-bearing - `??` binds looser
        // than `||`, so the tuning flag would be consulted only in the
        // case the stream has not emitted yet, which is never.
        final playing =
            ((snapshot.data ?? engine.playing) || playback.starting) &&
            !blocked;
        return PlayerScaffold(
          ids: radioPlayerIds,
          now: NowPlayingData(
            title: station.name,
            subtitle: playback.nowPlaying,
            // The song's own cover when the server recognised what is
            // playing, the station's logo otherwise. Only here: the deck
            // bar keeps the logo, because a bar whose picture changed
            // every few minutes would read as the station changing.
            artwork:
                waxArtwork(
                  ref.watch(artworkStoreProvider),
                  ref.watch(radioNowPlayingArtProvider),
                ) ??
                waxStationLogo(
                  ref.watch(artworkStoreProvider),
                  ref.watch(repositoryProvider),
                  station,
                ),
            domain: WaxDomain.radio,
            shape: ArtworkShape.circle,
            position: Duration.zero,
            duration: Duration.zero,
            live: true,
            playing: playing,
          ),
          onCollapse: () => leavePlayer(context),
          trailingHeaderActions: <Widget>[
            _FavoriteButton(station: station),
            _StationMenu(station: station),
          ],
          // The platter's ring rides over the artwork the scaffold draws;
          // the title block keeps the station name and the ICY line.
          heroOverlay: PlatterRing(playing: playing),
          titleTrailing: playback.nowPlaying == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _SaveSong(saved: playback.nowPlayingSaved),
                    _FindInLibrary(track: playback.nowPlaying!),
                  ],
                ),
          seek: const SeekCluster(
            now: NowPlayingData(
              title: '',
              position: Duration.zero,
              duration: Duration.zero,
              playing: true,
              live: true,
            ),
          ),
          transport: TransportCluster(
            ids: radioPlayerIds,
            playing: playing,
            // Stop, not pause: a paused live stream resumes at the live
            // edge anyway, and the transport should not pretend
            // otherwise. Which of stop and start it is belongs to the
            // controller, which is the one thing that can see why a
            // station is silent.
            live: true,
            onPlayPause: () => unawaited(controller.toggle()),
          ),
          volume: const RadioVolumeRow(),
          actionRow: const Center(child: SleepTimerButton(session: null)),
        );
      },
    );
  }
}

/// The handles the radio face's own controls carry. Its transport is
/// one button and it has no seek, so most of the player's set is absent
/// here rather than pointing at controls that are not drawn.
const radioPlayerIds = PlayerIds(
  surface: SemanticsIds.playerSurface,
  collapse: SemanticsIds.playerBack,
  play: SemanticsIds.playerToggle,
);

/// The thin amber arc that turns while a station plays.
///
/// The one piece of ambient motion in the app, and the only honest one
/// available: a live stream has no position, so nothing here can be
/// derived from playback except whether it is happening. Still under
/// reduced motion, where a rotating ring is exactly what that setting
/// is about.
class PlatterRing extends StatefulWidget {
  const PlatterRing({required this.playing, super.key});

  final bool playing;

  @override
  State<PlatterRing> createState() => _PlatterRingState();
}

class _PlatterRingState extends State<PlatterRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant PlatterRing old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) _sync();
  }

  void _sync() {
    final animate = widget.playing && WaxMotion.of(context).animationsEnabled;
    if (animate && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!animate && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _spin,
        builder: (context, _) => CustomPaint(
          painter: _RingPainter(
            turns: _spin.value,
            color: colors.accent,
            track: colors.hairline,
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.turns,
    required this.color,
    required this.track,
  });

  final double turns;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final extent = math.min(size.width, size.height);
    if (extent <= 0) return;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: extent - 4,
      height: extent - 4,
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(rect.center, rect.width / 2, stroke..color = track);
    // A quarter turn of arc, so the ring reads as moving rather than as
    // a second border.
    canvas.drawArc(
      rect,
      turns * 2 * math.pi,
      math.pi / 2,
      false,
      stroke..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.turns != turns || old.color != color || old.track != track;
}

/// The shortcut into the library for the track a station just named.
class _FindInLibrary extends StatelessWidget {
  const _FindInLibrary({required this.track});

  final String track;

  @override
  Widget build(BuildContext context) {
    return WaxIconButton(
      glyph: WaxIcons.search,
      label: 'Find "$track" in the library',
      size: 18,
      semanticsId: SemanticsIds.playerFindInLibrary,
      // `go`, not `push`. A search is a location a stranger can open, so
      // the routing rule already says which verb it takes - and pushing
      // it from here was not merely untidy but broken: the player is an
      // overlay on the root navigator and `/search` lives inside the
      // shell, so pushing built a second shell whose navigator key was
      // already reserved. The assertion that fired took the navigation
      // and the face's own rebuild with it, which is why the button
      // looked dead and the station's title went blank beside it.
      onPressed: () => context.go(WaxRoute.searchFor(track)),
    );
  }
}

/// The heart that keeps the song a station just named.
///
/// It says *song*, never favourite, and that wording is load-bearing:
/// the star two rows up means "pin this station to the dial", and two
/// affordances on one face that both read as favouriting would blur into
/// each other.
class _SaveSong extends ConsumerWidget {
  const _SaveSong({required this.saved});

  final bool saved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return WaxIconButton(
      glyph: WaxIcons.heart,
      label: saved ? 'Forget this song' : 'Save this song',
      size: 18,
      active: saved,
      semanticsId: SemanticsIds.playerSaveSong,
      onPressed: () => unawaited(saveNowPlayingSong(context, ref)),
    );
  }
}

/// Taps the heart and reports a refusal. The controller flips the state
/// optimistically and reverts on failure, so the only thing left to do
/// here is say what went wrong - a full list being the refusal worth
/// reading, since nothing else on these surfaces explains it.
Future<void> saveNowPlayingSong(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(radioPlaybackProvider.notifier).toggleSaveNowPlaying();
  } on WaxDeckApiException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(e.message)));
  }
}

class _FavoriteButton extends ConsumerWidget {
  const _FavoriteButton({required this.station});

  final RadioStation station;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = ref.watch(radioFavoritesProvider).contains(station.pid);
    return WaxIconButton(
      glyph: WaxIcons.star,
      label: pinned ? 'Unpin from the dial' : 'Pin to the dial',
      active: pinned,
      semanticsId: SemanticsIds.radioFavorite(station.pid),
      onPressed: () => unawaited(_pin(context, ref)),
    );
  }

  /// A full dial is a refusal worth reading; the star has nowhere to
  /// put one, so it goes where the hub's does.
  Future<void> _pin(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final refusal = await ref
        .read(radioFavoritesProvider.notifier)
        .toggle(station.pid);
    if (refusal == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(refusal)));
  }
}

class _StationMenu extends ConsumerWidget {
  const _StationMenu({required this.station});

  final RadioStation station;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return WaxMenuButton<String>(
      semanticsId: SemanticsIds.radioMenu(station.pid),
      label: 'More for ${station.name}',
      items: <WaxMenuItem<String>>[
        const WaxMenuItem<String>(
          value: 'hub',
          label: 'All stations',
          glyph: WaxIcons.radio,
        ),
        if (station.homepageUrl != null)
          const WaxMenuItem<String>(
            value: 'homepage',
            label: 'Station website',
            semanticsId: SemanticsIds.playerStationInfo,
          ),
        WaxMenuItem<String>(
          value: 'edit',
          label: 'Edit station',
          glyph: WaxIcons.edit,
          semanticsId: SemanticsIds.radioEdit(station.pid),
        ),
      ],
      onSelected: (choice) => unawaited(switch (choice) {
        'hub' => Future<void>.sync(() {
          leavePlayer(context);
          context.go(WaxRoute.radio);
        }),
        'homepage' => openStationHomepage(context, station),
        _ => showAddStationDialog(context, editing: station),
      }),
    );
  }
}

/// This device's output level while a station plays.
///
/// The same two conditions the item face reads: the platform gives
/// local output a level to set, which is desktop and web. A station is
/// the engine's output like anything else.
class RadioVolumeRow extends ConsumerWidget {
  const RadioVolumeRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(localVolumeAvailableProvider)) {
      return const SizedBox.shrink();
    }
    final level = ref.watch(outputVolumeProvider).clamp(0.0, 1.0);
    final volume = ref.read(outputVolumeProvider.notifier);
    return WaxSlider(
      value: level,
      label: 'Volume',
      glyph: WaxIcons.volume,
      mutedGlyph: WaxIcons.volumeMuted,
      trackWidth: 220,
      semanticsId: SemanticsIds.radioVolume,
      muteSemanticsId: SemanticsIds.radioMute,
      onChanged: (value) => unawaited(volume.set(value)),
      onMute: () => unawaited(volume.toggleMute()),
    );
  }
}
