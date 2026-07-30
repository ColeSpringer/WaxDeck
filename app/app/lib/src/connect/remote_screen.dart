import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'device_picker.dart';
import 'remote_session.dart';

/// The full surface for one session playing somewhere else.
///
/// A viewer, like the player screen: [RemoteSessionController] owns which
/// session this client drives, follows its live state, and extrapolates
/// the position, so this screen holds nothing of its own and walking away
/// from it does not stop the deck bar following the session. Before that
/// controller existed this screen *was* the state, which is why leaving it
/// left the bar with nothing to say.
class RemoteControlScreen extends ConsumerWidget {
  const RemoteControlScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = ref.watch(remoteSessionProvider);
    if (remote == null) {
      // Reached by a session ending while this was open, and by a cold
      // open of the location. Either way there is nothing to control, and
      // saying so beats an empty transport.
      return WaxScaffold(
        title: 'Remote playback',
        largeTitle: false,
        onBack: () => context.leave(),
        slivers: const <Widget>[
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: 'Nothing playing elsewhere',
              message:
                  'Pick a device from the now-playing bar to send playback '
                  'somewhere else.',
              glyph: WaxIcons.cast,
            ),
          ),
        ],
      );
    }
    return _Remote(remote: remote);
  }
}

class _Remote extends ConsumerWidget {
  const _Remote({required this.remote});

  final RemoteSession remote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(remoteSessionProvider.notifier);
    final colors = WaxColors.of(context);
    final entry = remote.currentEntry;
    final session = remote.session;

    return WaxScaffold(
      title: remote.endpointName,
      largeTitle: false,
      onBack: () => context.leave(),
      actions: <Widget>[
        WaxIconButton(
          glyph: WaxIcons.cast,
          label: 'Play on another device',
          active: true,
          semanticsId: SemanticsIds.deckCast,
          onPressed: () =>
              unawaited(showDevicePicker(context, from: CastSource.elsewhere)),
        ),
      ],
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: WaxSizeClass.of(context).gutter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const SizedBox(height: WaxSpace.s16),
                // Circular, and centred, because this is a place rather
                // than a thing: what a listener is looking at is a room
                // with a speaker in it.
                Center(
                  child: WaxIcon(
                    WaxIcons.cast,
                    size: 56,
                    active: true,
                    color: colors.accent,
                  ),
                ),
                const SizedBox(height: WaxSpace.s16),
                Text(
                  entry?.title ?? 'Playing',
                  textAlign: TextAlign.center,
                  style: WaxType.titleEntity.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                if (entry?.artist != null)
                  Text(
                    entry!.artist!,
                    textAlign: TextAlign.center,
                    style: WaxType.body.copyWith(color: colors.textSecondary),
                  ),
                Text(
                  <String?>[
                    'on ${remote.endpointName}',
                    if (session.ownerName != null)
                      'started by ${session.ownerName}',
                  ].nonNulls.join(', '),
                  textAlign: TextAlign.center,
                  style: WaxType.caption.copyWith(color: colors.textTertiary),
                ),
                const SizedBox(height: WaxSpace.s20),
                _Seek(remote: remote, controller: controller),
                const SizedBox(height: WaxSpace.s8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    WaxIconButton(
                      glyph: WaxIcons.previous,
                      label: 'Previous',
                      size: 24,
                      semanticsId: SemanticsIds.remotePrevious,
                      onPressed: () =>
                          unawaited(_report(context, controller.previous())),
                    ),
                    WaxIconButton(
                      glyph: session.playing ? WaxIcons.pause : WaxIcons.play,
                      label: session.playing ? 'Pause' : 'Play',
                      size: 40,
                      active: true,
                      semanticsId: SemanticsIds.remoteToggle,
                      onPressed: () =>
                          unawaited(_report(context, controller.toggle())),
                    ),
                    WaxIconButton(
                      glyph: WaxIcons.next,
                      label: 'Next',
                      size: 24,
                      semanticsId: SemanticsIds.remoteNext,
                      onPressed: () =>
                          unawaited(_report(context, controller.next())),
                    ),
                  ],
                ),
                // The endpoint's own level, and the surface a phone gets it
                // on: the compact deck bar draws no right cluster, so this
                // is where 5.2's mobile condition lands.
                if (remote.volumeControl) ...<Widget>[
                  const SizedBox(height: WaxSpace.s8),
                  Center(
                    child: WaxSlider(
                      value: session.volume ?? 1.0,
                      label: 'Volume on ${remote.endpointName}',
                      glyph: WaxIcons.volume,
                      mutedGlyph: WaxIcons.volumeMuted,
                      trackWidth: 200,
                      semanticsId: SemanticsIds.remoteVolume,
                      onChanged: (level) => unawaited(
                        _report(context, controller.setVolume(level)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: WaxSpace.s20),
                // The triad, spelled out on the screen as well as in the
                // picker: this is where somebody standing over a remote
                // session decides what happens to it, and hiding two of
                // the three behind a device list would make "stop the
                // music in the kitchen" a scavenger hunt.
                WaxButton(
                  label: 'Transfer here',
                  kind: WaxButtonKind.filled,
                  icon: WaxIcons.home,
                  semanticsId: SemanticsIds.remotePlayHere,
                  onPressed: () =>
                      unawaited(_transferHere(context, controller)),
                ),
                const SizedBox(height: WaxSpace.s8),
                WaxButton(
                  label: 'Leave it playing',
                  kind: WaxButtonKind.tonal,
                  semanticsId: SemanticsIds.remoteLeave,
                  onPressed: () {
                    controller.release();
                    context.leave();
                  },
                ),
                const SizedBox(height: WaxSpace.s8),
                WaxButton(
                  label: 'Stop playback on ${remote.endpointName}',
                  kind: WaxButtonKind.destructive,
                  icon: WaxIcons.stop,
                  semanticsId: SemanticsIds.remoteStopThere,
                  onPressed: () => unawaited(_stopThere(context, controller)),
                ),
                const SizedBox(height: WaxSpace.s32),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _transferHere(
    BuildContext context,
    RemoteSessionController controller,
  ) async {
    final router = GoRouter.of(context);
    if (await _report(context, controller.transferHere())) router.leave();
  }

  Future<void> _stopThere(
    BuildContext context,
    RemoteSessionController controller,
  ) async {
    final router = GoRouter.of(context);
    if (await _report(context, controller.stopThere())) router.leave();
  }

  /// Runs [work], saying why it did nothing when it fails. True when it
  /// succeeded, so a caller can leave the screen only if there is nothing
  /// left to say on it.
  Future<bool> _report(BuildContext context, Future<void> work) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await work;
      return true;
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
      return false;
    }
  }
}

/// The seek bar, in its own leaf so the extrapolated position does not
/// rebuild the screen twice a second.
class _Seek extends StatelessWidget {
  const _Seek({required this.remote, required this.controller});

  final RemoteSession remote;
  final RemoteSessionController controller;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final duration = remote.duration;
    return ValueListenableBuilder<Duration>(
      valueListenable: controller.position,
      builder: (context, position, _) => Column(
        children: <Widget>[
          WaxSeekBar(
            position: position,
            duration: duration,
            semanticsId: SemanticsIds.remoteSeek,
            // A session frame carries no duration for an entry the server
            // could not measure, and scrubbing a bar with no length seeks
            // to zero: better no control than one that throws playback to
            // the start.
            onSeek: duration > Duration.zero
                ? (at) => unawaited(controller.seek(at))
                : null,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              ExcludeSemantics(
                child: Text(
                  formatTimecode(position),
                  style: WaxType.monoTime.copyWith(color: colors.textTertiary),
                ),
              ),
              ExcludeSemantics(
                child: Text(
                  formatTimecode(duration),
                  style: WaxType.monoTime.copyWith(color: colors.textTertiary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
