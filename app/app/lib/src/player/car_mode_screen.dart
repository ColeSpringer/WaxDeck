import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../media_view.dart';
import '../shell/semantics_ids.dart';
import 'now_playing_controller.dart';
import 'now_playing_view.dart';
import 'player_screen.dart';
import 'wake_port.dart';

/// The player at arm's length.
///
/// One surface for a driver: what is playing, and the three verbs worth
/// reaching for. Everything about it is the design system's, held at car
/// size by `CarModeScaffold` - the theme it forces, the control extents,
/// the swipe. What this screen adds is the wiring: which session, which
/// transport verbs, and the lock that stops the screen going dark
/// halfway down a motorway.
///
/// The wake lock is held by mounting and let go by leaving, whichever
/// way somebody leaves: the exit button, a system back gesture, the
/// queue running out.
class CarModeScreen extends ConsumerWidget {
  const CarModeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Around both branches, not only the scaffold's own: the idle state
    // is text and a button on a hard-coded black, and on the light theme
    // that was primary text at under 3:1 on the one control that leaves.
    return CarModeTheme(
      child: KeepAwake(
        child: NowPlayingView(
          idle: (context) => Scaffold(
            body: SafeArea(
              child: EmptyState(
                glyph: WaxIcons.headphones,
                title: 'Nothing is playing',
                message: 'Start something and it takes the whole screen.',
                actionLabel: 'Leave car mode',
                actionSemanticsId: SemanticsIds.carExit,
                onAction: () => leavePlayer(context),
                semanticsId: SemanticsIds.carSurface,
              ),
            ),
          ),
          builder: (context, session, item, position) => StreamBuilder<bool>(
            stream: session.engine.playingStream,
            initialData: session.engine.playing,
            builder: (context, snapshot) {
              final playback = ref.read(nowPlayingProvider.notifier);
              final music = item.mediaType == MediaType.music;
              return CarModeScaffold(
                now: NowPlayingData(
                  title: item.title,
                  subtitle: item.artist,
                  // `read`, not `watch`: this runs inside two nested
                  // builders, so a watch would register the dependency
                  // outside this widget's own build pass and re-register
                  // on every play/pause tick. The store is one object for
                  // the session's life either way.
                  artwork: waxArtwork(
                    ref.read(artworkStoreProvider),
                    item.artUrl,
                  ),
                  domain: waxDomainOf(item.mediaType),
                  shape: waxShapeOf(item.mediaType),
                  // The car face draws no bar, so the position it is
                  // handed is the one it was built with. Nothing here
                  // ticks: a driver reads a title, not a timecode.
                  position: position.value,
                  duration: session.mediaDuration,
                  playing: snapshot.data ?? false,
                ),
                ids: const PlayerIds(
                  surface: SemanticsIds.carSurface,
                  play: SemanticsIds.carToggle,
                  next: SemanticsIds.carNext,
                  previous: SemanticsIds.carPrevious,
                ),
                exitSemanticsId: SemanticsIds.carExit,
                onPlayPause: () => unawaited(session.toggle()),
                // Spoken word steps by interval rather than by item, and
                // the giant three-button layout has nowhere to put a
                // fourth control: a podcast in the car gets play and stop
                // and the swipe does nothing, which is honest, rather than
                // a next button that walks out of an episode.
                onPrevious: music ? () => unawaited(playback.previous()) : null,
                onNext: music ? () => unawaited(playback.next()) : null,
                onExit: () => leavePlayer(context),
              );
            },
          ),
        ),
      ),
    );
  }
}
