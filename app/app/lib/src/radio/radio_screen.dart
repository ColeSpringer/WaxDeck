import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../media_view.dart';
import '../player/output_volume.dart';
import '../providers.dart';
import '../search/search_chrome.dart';
import '../shell/account_chrome.dart';
import '../settings/client_prefs.dart';
import '../shell/semantics_ids.dart';
import 'add_station.dart';
import 'radio_controller.dart';

/// The dial: what is pinned, and everything there is to tune.
///
/// The favourites strip is a visual shortcut over the grid, which is the
/// primary surface and the one that carries the semantics - every station
/// on the dial is a row below it, so nothing is only reachable by flicking
/// a carousel.
class RadioScreen extends ConsumerWidget {
  const RadioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stations = ref.watch(radioStationsProvider);
    final playback = ref.watch(radioPlaybackProvider);
    final dial = ref.watch(radioDialProvider);

    return WaxScaffold(
      title: 'Radio',
      semanticsId: SemanticsIds.radioHub,
      actions: <Widget>[
        WaxIconButton(
          glyph: WaxIcons.add,
          label: 'Add station',
          semanticsId: SemanticsIds.radioAdd,
          onPressed: () => unawaited(showAddStationDialog(context)),
        ),
        const SearchAction(),
        const AccountAction(),
      ],
      slivers: <Widget>[
        if (dial.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(
                top: WaxSpace.s8,
                bottom: WaxSpace.s16,
              ),
              child: _Dial(dial: dial, playback: playback),
            ),
          ),
        if (playback.station != null)
          const SliverToBoxAdapter(child: _StationVolume()),
        switch (stations) {
          AsyncData(:final value) when value.isEmpty =>
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                title: 'No stations yet',
                message:
                    'Search the directory to add your first, or paste a stream '
                    'URL if you already have one.',
                glyph: WaxIcons.radio,
              ),
            ),
          AsyncData(:final value) => _StationGrid(
            stations: value,
            playback: playback,
          ),
          AsyncError(:final error) => SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(
              title: 'Could not load stations',
              message: error is WaxDeckApiException
                  ? error.message
                  : 'The server did not answer.',
              onRetry: () => ref.invalidate(radioStationsProvider),
            ),
          ),
          _ => const SliverToBoxAdapter(
            child: SkeletonShapes(shape: SkeletonShape.grid),
          ),
        },
        const SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s32)),
      ],
    );
  }
}

/// The favourites strip, fed from the pinned stations.
class _Dial extends ConsumerWidget {
  const _Dial({required this.dial, required this.playback});

  final List<RadioStation> dial;
  final RadioPlayback playback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(artworkStoreProvider);
    final repository = ref.watch(repositoryProvider);
    final playingAt = dial.indexWhere(
      (station) => station.pid == playback.station?.pid,
    );
    return StationDial(
      // Opens on what is playing when the dial holds it, so a listener
      // coming back to the screen finds the needle where they left it.
      initialIndex: playingAt < 0 ? 0 : playingAt,
      stations: <DialStation>[
        for (final station in dial)
          DialStation(
            name: station.name,
            artwork: waxStationLogo(store, repository, station),
            playing: station.pid == playback.station?.pid,
            nowPlaying: playback.nowPlaying,
          ),
      ],
      semanticsId: SemanticsIds.radioDial,
      tuneSemanticsId: SemanticsIds.radioTune,
      nowPlayingSemanticsId: SemanticsIds.radioNowPlaying,
      onTune: (index) => unawaited(_tune(context, ref, dial[index], playback)),
      onStop: playback.station == null
          ? null
          : () => unawaited(ref.read(radioPlaybackProvider.notifier).stop()),
    );
  }
}

/// How loud the station that is on comes out of this device.
///
/// Here because the deck bar's compact layout has no right cluster to
/// hold a track, and this hub is what that bar expands to: the level a
/// wide window reads on the bar is one tap away on every narrower one,
/// which is the arrangement the remote session already uses for its own
/// endpoint. Above sidebar width both are drawn, over the same engine
/// gain, so neither can show a loudness the other does not.
///
/// Absent on a phone and a tablet, where the hardware buttons own local
/// volume and a software slider would fight the OS volume stack.
class _StationVolume extends ConsumerWidget {
  const _StationVolume();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(localVolumeAvailableProvider)) {
      return const SizedBox.shrink();
    }
    final volume = ref.read(outputVolumeProvider.notifier);
    return Padding(
      padding: const EdgeInsets.only(bottom: WaxSpace.s16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: WaxSlider(
          value: ref.watch(outputVolumeProvider),
          onChanged: (level) => unawaited(volume.set(level)),
          onMute: () => unawaited(volume.toggleMute()),
          label: 'Volume',
          glyph: WaxIcons.volume,
          mutedGlyph: WaxIcons.volumeMuted,
          trackWidth: 160,
          semanticsId: SemanticsIds.radioVolume,
          muteSemanticsId: SemanticsIds.radioMute,
        ),
      ),
    );
  }
}

/// Every station, as logos.
class _StationGrid extends ConsumerWidget {
  const _StationGrid({required this.stations, required this.playback});

  final List<RadioStation> stations;
  final RadioPlayback playback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final store = ref.watch(artworkStoreProvider);
    final repository = ref.watch(repositoryProvider);
    final favorites = ref.watch(radioFavoritesProvider);
    return SliverPadding(
      padding: sizeClass.gutter,
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final grid = MediaCard.gridFor(
            constraints.crossAxisExtent,
            extent: _tileExtent * ref.watch(gridScaleProvider),
          );
          return SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: grid.columns,
              mainAxisSpacing: WaxShellMetrics.gridGap,
              crossAxisSpacing: WaxShellMetrics.gridGap,
              mainAxisExtent: MediaCard.heightFor(context, width: grid.width),
            ),
            itemCount: stations.length,
            itemBuilder: (context, index) {
              final station = stations[index];
              final playing = station.pid == playback.station?.pid;
              return _StationTile(
                station: station,
                width: grid.width,
                playing: playing,
                starting: playing && playback.starting,
                pinned: favorites.contains(station.pid),
                nowPlaying: playing ? playback.nowPlaying : null,
                artwork: waxStationLogo(store, repository, station),
                playback: playback,
              );
            },
          );
        },
      ),
    );
  }
}

/// One station: its logo, its name, the pin, and its menu.
class _StationTile extends ConsumerWidget {
  const _StationTile({
    required this.station,
    required this.width,
    required this.playing,
    required this.starting,
    required this.pinned,
    required this.nowPlaying,
    required this.artwork,
    required this.playback,
  });

  final RadioStation station;
  final double width;
  final bool playing;
  final bool starting;
  final bool pinned;
  final String? nowPlaying;
  final WaxArtwork? artwork;
  final RadioPlayback playback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: <Widget>[
        MediaCard(
          data: MediaTileData(
            title: station.name,
            // What is on, when this is the station that is on: the ICY
            // line is the reason to look at a station tile at all.
            subtitle: starting
                ? 'Tuning in'
                : (playing ? (nowPlaying ?? 'Playing') : null),
            artwork: artwork,
            domain: WaxDomain.radio,
            shape: ArtworkShape.circle,
            semanticsId: SemanticsIds.radio(station.pid),
          ),
          width: width,
          playing: playing,
          onTap: () => unawaited(_tune(context, ref, station, playback)),
        ),
        // Beside the card rather than inside it: both are controls, and a
        // card that swallowed them would announce one node for three
        // things (the trap MediaListRow shipped once).
        Positioned(
          top: 0,
          right: 0,
          child: Row(
            children: <Widget>[
              WaxIconButton(
                glyph: WaxIcons.star,
                label: pinned
                    ? 'Unpin ${station.name} from the dial'
                    : 'Pin ${station.name} to the dial',
                size: 16,
                active: pinned,
                semanticsId: SemanticsIds.radioFavorite(station.pid),
                onPressed: () => unawaited(_pin(context, ref)),
              ),
              WaxMenuButton<String>(
                glyph: WaxIcons.more,
                label: 'More for ${station.name}',
                semanticsId: SemanticsIds.radioMenu(station.pid),
                items: <WaxMenuItem<String>>[
                  WaxMenuItem<String>(
                    value: 'edit',
                    label: 'Edit station',
                    semanticsId: SemanticsIds.radioEdit(station.pid),
                  ),
                  if (station.homepageUrl != null)
                    const WaxMenuItem<String>(
                      value: 'homepage',
                      label: 'Station website',
                    ),
                  WaxMenuItem<String>(
                    value: 'delete',
                    label: 'Remove station',
                    semanticsId: SemanticsIds.radioDelete(station.pid),
                  ),
                ],
                onSelected: (choice) => unawaited(_menu(context, ref, choice)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Pins or unpins, saying so when the write did not land. The star has no
  /// room to report anything, so the refusal goes where the screen's others
  /// go: a full dial is actionable, and a refused write would otherwise be
  /// a star that silently springs back.
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

  Future<void> _menu(BuildContext context, WidgetRef ref, String choice) async {
    switch (choice) {
      case 'edit':
        await showAddStationDialog(context, editing: station);
      case 'homepage':
        await openStationHomepage(context, station);
      case 'delete':
        await _remove(context, ref);
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final favorites = ref.read(radioFavoritesProvider.notifier);
    final playbackController = ref.read(radioPlaybackProvider.notifier);
    final wasPlaying = playing;
    try {
      await ref.read(radioStationsProvider.notifier).remove(station.pid);
      if (wasPlaying) await playbackController.stop();
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    // A pin outlives the station it names: the dial draws nothing, but the
    // stored list keeps a dead pid and a slot of the cap. Awaited rather
    // than fired off, since an unawaited toggle escapes the block above.
    if (!favorites.contains(station.pid)) return;
    final refusal = await favorites.toggle(station.pid);
    if (refusal == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(refusal)));
  }
}

/// Tunes a station in, or stops it when it is the one playing.
///
/// Every failure is reported, not only the server's: the play-info call is
/// one of two things that can go wrong, and the other is the stream itself
/// refusing to open, which throws from the engine. Catching the API alone
/// left a dead station as a tap that did nothing and said nothing.
///
/// Exceptions, not everything: a platform refusing a stream raises one, and
/// an assertion or a type error is this app being wrong rather than the
/// station being unreachable. Those belong in the console, not behind a
/// message telling a listener their station is down.
Future<void> _tune(
  BuildContext context,
  WidgetRef ref,
  RadioStation station,
  RadioPlayback playback,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final controller = ref.read(radioPlaybackProvider.notifier);
  // Which of the two ran, so the failure is named after it: a stop that
  // threw used to report that the station could not be tuned, while it
  // carried on playing.
  final tuning = station.pid != playback.station?.pid;
  try {
    if (tuning) {
      await controller.play(station);
    } else {
      await controller.stop();
    }
  } on Exception catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            e is WaxDeckApiException
                ? e.message
                : tuning
                ? 'Could not tune ${station.name}'
                : 'Could not stop ${station.name}',
          ),
        ),
      );
  }
}

/// The widest a station logo is allowed to be. Circular art reads smaller
/// than a square of the same width, and a station has one line of text
/// under it rather than two.
const double _tileExtent = 148;
