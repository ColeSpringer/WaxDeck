import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
import '../media_view.dart';
import '../player/output_volume.dart';
import '../providers.dart';
import '../search/search_chrome.dart';
import '../shell/async_sliver_face.dart';
import '../shell/account_chrome.dart';
import '../settings/client_prefs.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'add_station.dart';
import 'radio_controller.dart';

/// How many pins the band needs before it is a dial.
///
/// Under this the ticks sweep a width nothing occupies, the needle points
/// through empty space and a lone logo floats past it - a ruler with one
/// mark on it. The star on the fullscreen player makes that first pin easy
/// to reach by accident, so the degenerate case is the common one; it
/// draws as rows instead.
const int _dialMinimum = 3;

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
    final l10n = context.l10n;

    return WaxScaffold(
      title: l10n.radioTitle,
      semanticsId: SemanticsIds.radioHub,
      actions: <Widget>[
        WaxIconButton(
          glyph: WaxIcons.add,
          label: l10n.radioAddStation,
          semanticsId: SemanticsIds.radioAdd,
          onPressed: () => unawaited(showAddStationDialog(context)),
        ),
        const SearchAction(),
        const AccountAction(),
      ],
      slivers: <Widget>[
        if (dial.length >= _dialMinimum)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(
                top: WaxSpace.s8,
                bottom: WaxSpace.s16,
              ),
              child: _Dial(dial: dial, playback: playback),
            ),
          )
        else if (dial.isNotEmpty)
          SliverToBoxAdapter(
            child: _PinnedRows(dial: dial, playback: playback),
          ),
        if (playback.station != null)
          const SliverToBoxAdapter(child: _StationVolume()),
        const SliverToBoxAdapter(child: _SavedSongsDoor()),
        AsyncSliverFace<List<RadioStation>>(
          state: stations,
          skeleton: SkeletonShape.grid,
          errorTitle: l10n.radioLoadError,
          onRetry: () => ref.invalidate(radioStationsProvider),
          isEmpty: (value) => value.isEmpty,
          empty: (context) => SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: l10n.radioEmptyTitle,
              message: l10n.radioEmptyMessage,
              glyph: WaxIcons.radio,
              actionLabel: l10n.radioEmptyAction,
              onAction: () => unawaited(showAddStationDialog(context)),
            ),
          ),
          builder: (context, value) =>
              _StationGrid(stations: value, playback: playback),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s32)),
      ],
    );
  }
}

/// One or two pins, drawn as rows under a heading.
///
/// Not a shrunken dial: the same option row the door below it uses, with
/// the station's logo in the leading slot the component keeps for one.
/// Every row is a station in the grid below as well, so this is a
/// shortcut and never the only path - the same claim the band makes,
/// which is what lets both surfaces be optional.
class _PinnedRows extends ConsumerWidget {
  const _PinnedRows({required this.dial, required this.playback});

  final List<RadioStation> dial;
  final RadioPlayback playback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gutter = WaxSizeClass.of(context).gutter;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: gutter.copyWith(top: WaxSpace.s8),
          child: SectionHeader(title: context.l10n.radioPinnedTitle),
        ),
        for (final station in dial)
          Padding(
            padding: gutter.copyWith(top: WaxSpace.s4, bottom: WaxSpace.s4),
            child: _PinnedRow(station: station, playback: playback),
          ),
        const SizedBox(height: WaxSpace.s8),
      ],
    );
  }
}

/// A station's second line: what is on, while it is on.
///
/// One function, because the pinned row and the grid tile draw the same
/// line from different shapes - the tile is handed a `starting` already
/// masked by `playing`, the row is not - and two spellings of one rule
/// is how a station comes to say "Playing" in the list above "Tuning in"
/// on its own tile.
String? stationLine(
  AppLocalizations l10n, {
  required bool playing,
  required bool starting,
  String? nowPlaying,
}) {
  if (!playing) return null;
  if (starting) return l10n.radioTuningIn;
  // The ICY line is the reason to look at a station at all; its name is
  // the fallback until one arrives.
  return nowPlaying ?? l10n.radioPlaying;
}

class _PinnedRow extends ConsumerWidget {
  const _PinnedRow({required this.station, required this.playback});

  final RadioStation station;
  final RadioPlayback playback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final playing = station.pid == playback.station?.pid;
    return WaxOptionRow(
      leading: ArtworkImage(
        size: 40,
        artwork: waxStationLogo(
          ref.watch(artworkStoreProvider),
          ref.watch(repositoryProvider),
          station,
        ),
        monogram: station.name,
        shape: ArtworkShape.circle,
        domain: WaxDomain.radio,
      ),
      title: station.name,
      subtitle: stationLine(
        l10n,
        playing: playing,
        starting: playback.starting,
        nowPlaying: playback.nowPlaying,
      ),
      active: playing,
      semanticsId: SemanticsIds.radioPinned(station.pid),
      onTap: () => unawaited(_tune(context, ref, station, playback)),
    );
  }
}

/// The way into the songs kept off the air.
///
/// Between the dial and the grid, which is where it belongs: the dial is
/// the stations pinned, the grid is the stations there are, and this is
/// what listening to them produced.
class _SavedSongsDoor extends StatelessWidget {
  const _SavedSongsDoor();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: WaxSizeClass.of(
        context,
      ).gutter.copyWith(top: WaxSpace.s8, bottom: WaxSpace.s8),
      child: WaxOptionRow(
        glyph: WaxIcons.heart,
        title: context.l10n.radioSavedTitle,
        subtitle: context.l10n.radioSavedDoorSubtitle,
        semanticsId: SemanticsIds.radioSavedOpen,
        onTap: () => context.go(WaxRoute.radioSaved),
      ),
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
/// endpoint. Exactly one local control exists per width - the deck bar's
/// cluster wherever the bar has one, this row where it does not - so the
/// gate is the same size-class rule the bar's host reads, and toggling
/// device emulation adds and removes the row with the class it changes.
///
/// Absent on a phone and a tablet, where the hardware buttons own local
/// volume and a software slider would fight the OS volume stack.
class _StationVolume extends ConsumerWidget {
  const _StationVolume();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (WaxSizeClass.of(context).hasSidebar ||
        !ref.watch(localVolumeAvailableProvider)) {
      return const SizedBox.shrink();
    }
    final volume = ref.read(outputVolumeProvider.notifier);
    return Padding(
      padding: WaxSizeClass.of(
        context,
      ).gutter.add(const EdgeInsets.only(bottom: WaxSpace.s16)),
      child: Align(
        // Centred, because the row belongs to the readout cluster above
        // it - station name, tune control, level - and that cluster is a
        // centred stack. Left on the gutter it floated between the
        // cluster and the grid, attached to neither, which is what "the
        // slider is under the radio text" was pointing at.
        alignment: Alignment.center,
        child: WaxSlider(
          value: ref.watch(outputVolumeProvider),
          onChanged: (level) => unawaited(volume.set(level)),
          onMute: () => unawaited(volume.toggleMute()),
          label: context.l10n.radioVolume,
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
    // Watched here rather than read when a menu opens: the scrobbler
    // slots are fetched, so a menu that read them cold would draw its
    // row one open late.
    final scrobbling = ref.watch(radioScrobblingProvider);
    final muted = ref.watch(radioScrobbleMutedProvider);
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
                scrobbling: scrobbling,
                muted: muted.contains(station.pid.toUpperCase()),
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
    required this.scrobbling,
    required this.muted,
    required this.nowPlaying,
    required this.artwork,
    required this.playback,
  });

  final RadioStation station;
  final double width;
  final bool playing;
  final bool starting;
  final bool pinned;

  /// Whether this account has anywhere to scrobble to and has not
  /// silenced the whole dial, which is what the menu's row is gated on.
  final bool scrobbling;

  /// Whether this station is one of the ones it does not report.
  final bool muted;

  final String? nowPlaying;
  final WaxArtwork? artwork;
  final RadioPlayback playback;

  /// The rows behind the overflow button. One declaration rather than
  /// one instance - the button and the card's secondary tap each build
  /// it - so the two cannot drift into offering different menus.
  ///
  /// The scrobble row only when there is something to scrobble to: with
  /// nothing connected, or the whole dial silenced in settings, a
  /// per-station switch would name a setting with no effect.
  List<WaxMenuItem<String>> _menuItems(
    AppLocalizations l10n,
  ) => <WaxMenuItem<String>>[
    WaxMenuItem<String>(
      value: 'edit',
      label: l10n.radioEditStation,
      semanticsId: SemanticsIds.radioEdit(station.pid),
    ),
    if (station.homepageUrl != null)
      WaxMenuItem<String>(value: 'homepage', label: l10n.radioStationWebsite),
    if (scrobbling)
      WaxMenuItem<String>(
        value: 'scrobble',
        label: muted
            ? l10n.radioScrobbleStationResume
            : l10n.radioScrobbleStationMute,
        semanticsId: SemanticsIds.radioScrobbleToggle(station.pid),
      ),
    WaxMenuItem<String>(
      value: 'delete',
      label: l10n.radioRemoveStation,
      semanticsId: SemanticsIds.radioDelete(station.pid),
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // Both controls through the card's own corner. Hand-rolled, they
    // were a 16-pixel star and a menu button stacked at (0, 0) over a
    // circular card that draws its own overflow at (8, 8): two of the
    // same glyph eight pixels apart on a pointer, and neither aligned
    // to anything.
    return MediaCard(
      data: MediaTileData(
        title: station.name,
        subtitle: stationLine(
          l10n,
          playing: playing,
          starting: starting,
          nowPlaying: nowPlaying,
        ),
        artwork: artwork,
        domain: WaxDomain.radio,
        shape: ArtworkShape.circle,
        semanticsId: SemanticsIds.radio(station.pid),
      ),
      width: width,
      playing: playing,
      onTap: () => unawaited(_tune(context, ref, station, playback)),
      action: MediaCardAction(
        glyph: WaxIcons.star,
        label: pinned
            ? l10n.radioUnpin(station.name)
            : l10n.radioPin(station.name),
        active: pinned,
        semanticsId: SemanticsIds.radioFavorite(station.pid),
        onPressed: () => unawaited(_pin(context, ref)),
      ),
      // The same menu the overflow button raises. Right-click on a
      // pointer, long-press on touch: the tile is the surface somebody
      // will try either on, and until now the only way in was a
      // 16-pixel button in its corner.
      onMore: () => unawaited(_openMenu(context, ref, l10n)),
    );
  }

  /// Raises the station's menu from the card itself, anchored on
  /// whatever the gesture landed on.
  Future<void> _openMenu(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final choice = await showWaxMenu<String>(context, _menuItems(l10n));
    if (choice == null || !context.mounted) return;
    await _menu(context, ref, choice);
  }

  /// Pins or unpins, saying so when the write did not land. The star has no
  /// room to report anything, so the refusal goes where the screen's others
  /// go: a full dial is actionable, and a refused write would otherwise be
  /// a star that silently springs back.
  Future<void> _pin(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final refusal = await ref
        .read(radioFavoritesProvider.notifier)
        .toggle(station.pid);
    if (refusal == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(radioPinRefusalMessage(l10n, refusal))),
      );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, String choice) async {
    switch (choice) {
      case 'edit':
        await showAddStationDialog(context, editing: station);
      case 'homepage':
        await openStationHomepage(context, station);
      case 'scrobble':
        await toggleStationScrobble(context, ref, station);
      case 'delete':
        await _remove(context, ref);
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final favorites = ref.read(radioFavoritesProvider.notifier);
    final playbackController = ref.read(radioPlaybackProvider.notifier);
    final wasPlaying = playing;
    try {
      await ref.read(radioStationsProvider.notifier).remove(station.pid);
      if (wasPlaying) await playbackController.stop();
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
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
      ..showSnackBar(
        SnackBar(content: Text(radioPinRefusalMessage(l10n, refusal))),
      );
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
  // Which of the two, so the failure is named after it: a stop that threw
  // used to report that the station could not be tuned, while it carried
  // on playing.
  if (station.pid != playback.station?.pid) {
    return tuneStation(context, ref, station);
  }
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    await ref.read(radioPlaybackProvider.notifier).stop();
  } on Exception catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            e is WaxDeckApiException
                ? explainError(l10n, e)
                : l10n.radioCouldNotStop(station.name),
          ),
        ),
      );
  }
}

/// Puts [station] on the air, saying so where it cannot. The palette
/// tunes through this too, so a dead stream fails the same way there.
Future<void> tuneStation(
  BuildContext context,
  WidgetRef ref,
  RadioStation station,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    await ref.read(radioPlaybackProvider.notifier).play(station);
  } on Exception catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            e is WaxDeckApiException
                ? explainError(l10n, e)
                : l10n.radioCouldNotTune(station.name),
          ),
        ),
      );
  }
}

/// The widest a station logo is allowed to be. Circular art reads smaller
/// than a square of the same width, and a station has one line of text
/// under it rather than two.
const double _tileExtent = 148;
