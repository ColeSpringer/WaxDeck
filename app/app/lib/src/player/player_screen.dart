import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_palette.dart';
import '../artwork/artwork_providers.dart';
import '../connect/device_picker.dart';
import '../discovery/discovery_actions.dart';
import '../library/item_delete.dart';
import '../media_view.dart';
import '../playlists/add_to_playlist_sheet.dart';
import '../player/play_progress.dart';
import '../podcasts/episode_actions.dart';
import '../podcasts/podcasts_controller.dart';
import '../providers.dart';
import '../queue/queue_controller.dart';
import '../queue/queue_item.dart';
import '../queue/queue_state.dart';
import '../queue/queue_view.dart';
import '../radio/radio_controller.dart';
import '../settings/client_prefs.dart';
import '../sharing/share_dialog.dart';
import '../shell/commands.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'deck_bar_host.dart';
import 'download_action.dart';
import 'item_star_rating_row.dart';
import 'lyrics.dart';
import 'now_playing_controller.dart';
import 'output_volume.dart';
import 'playback_session.dart';
import 'radio_face.dart';
import 'sleep_timer.dart';
import 'spoken_face.dart';
import 'waveform.dart';

/// The verbs behind the player's one overflow menu.
enum _PlayerMenuAction {
  addToPlaylist,
  share,
  delete,
  goToShow,
  markPlayed,
  funding,
  visualizer,
  carMode,
}

/// The e2e handles the player's own controls carry. One place, because
/// the design system emits no identifier strings of its own (ADR-0016),
/// and because the scaffold and the transport each take their own copy:
/// two literals would be two chances to disagree.
const _ids = PlayerIds(
  surface: SemanticsIds.playerSurface,
  collapse: SemanticsIds.playerBack,
  play: SemanticsIds.playerToggle,
  next: SemanticsIds.playerNext,
  previous: SemanticsIds.playerPrevious,
  skipBack: SemanticsIds.playerSkipBack,
  skipForward: SemanticsIds.playerSkipForward,
  shuffle: SemanticsIds.playerShuffle,
  repeat: SemanticsIds.playerRepeat,
  seek: SemanticsIds.playerSeek,
);

/// The full player: one scaffold, four faces.
///
/// A viewer, deliberately: nothing here starts, stops, or outlives
/// playback, so leaving this screen keeps the music on. The session and
/// the queue own the state; this draws it and sends verbs back.
///
/// Which face is decided by what holds the engine: a station when live
/// radio has taken it, otherwise the medium of the item the queue is
/// standing on. The scaffold is the same in every case; what differs is
/// which of its slots are filled, and with what.
class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CommandScope(
      // The keyboard's way out, and the third one overall beside the
      // collapse button and the pull-down. Scoped rather than global so
      // Escape belongs to whoever is on top: `CommandScope` withdraws
      // itself when its route stops being current, so a sheet or the
      // palette over the player answers Escape first and hands it back
      // on the way out.
      commands: <WaxCommand>[
        WaxCommand(
          id: 'player-collapse',
          label: 'Collapse the player',
          section: WaxCommandSection.view,
          glyph: WaxIcons.collapse,
          // Not on repeats. The binding map fires on every key event the
          // activator accepts, and a held Escape repeats about every
          // 33 ms while the scope withdraws itself only on a post-frame
          // callback - so the second firing runs `leavePlayer` with the
          // player already gone and pops whatever was underneath it, or
          // at the root sends the listener home.
          activators: const <ShortcutActivator>[
            SingleActivator(LogicalKeyboardKey.escape, includeRepeats: false),
          ],
          run: (context, ref) => leavePlayer(context),
        ),
      ],
      // A Scaffold with nothing in it but the body, for the thing a
      // Scaffold does that no other widget does: it is what
      // `ScaffoldMessenger` presents into. The player is a route of its
      // own over the shell, so the chrome's Scaffold is not an ancestor,
      // and every refusal raised from here - a star that would not
      // stick, a routed command an endpoint declined, a delete the
      // server refused - asserts without one. The backdrop underneath
      // paints the canvas, hence transparent.
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: _body(context, ref),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref) {
    // Radio first, and for the same reason the deck bar reads it first:
    // a station has taken the engine, so whatever the queue still names
    // is not what is coming out of the speakers.
    final radio = ref.watch(radioPlaybackProvider);
    if (radio.station != null) {
      return ArtworkAccent(
        artUrl: null,
        domain: WaxDomain.radio,
        child: RadioFace(playback: radio),
      );
    }

    final nowPlaying = ref.watch(nowPlayingProvider);
    // The queue is what decides whether anything is playing. An item
    // still resolving, or one whose start failed before it could be
    // named, is not nothing: saying so would hide the failure and the
    // button that retries it.
    if (nowPlaying.entry == null) {
      return _PlayerShell(
        child: EmptyState(
          key: const Key('player-idle'),
          glyph: WaxIcons.headphones,
          title: 'Nothing is playing',
          message: 'Pick something from your library and it shows up here.',
          semanticsId: SemanticsIds.playerSurface,
        ),
      );
    }

    final item = nowPlaying.item;
    return switch (nowPlaying) {
      NowPlaying(:final Object error) => _PlayerShell(
        artUrl: item?.artUrl,
        domain: waxDomainOf(item?.mediaType ?? MediaType.music),
        child: ErrorState(
          key: const Key('player-error'),
          title: 'Playback stopped',
          message: error is WaxDeckApiException
              ? error.message
              : 'Playback failed to start',
          // The queue still holds the entry, and nothing else will try
          // it again: without this the failure is where playback stops
          // until something rebuilds the queue.
          onRetry: ref.read(nowPlayingProvider.notifier).resume,
          semanticsId: SemanticsIds.playerSurface,
          retrySemanticsId: SemanticsIds.playerRetry,
        ),
      ),
      // Both, always: the state publishes a session and the item it is
      // for together.
      NowPlaying(:final PlaybackSession session, :final ItemSummary item) =>
        ArtworkAccent(
          artUrl: item.artUrl,
          domain: waxDomainOf(item.mediaType),
          child: PlayerFace(session: session, item: item),
        ),
      _ => _PlayerShell(
        artUrl: item?.artUrl,
        domain: waxDomainOf(item?.mediaType ?? MediaType.music),
        child: const Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

/// The backdrop and the way out, for the states with no item to draw.
///
/// The scaffold proper needs a session; these do not, and they still
/// have to be leaveable and still have to look like the player rather
/// than like a blank route.
class _PlayerShell extends ConsumerWidget {
  const _PlayerShell({
    required this.child,
    this.artUrl,
    this.domain = WaxDomain.music,
  });

  final Widget child;
  final String? artUrl;
  final WaxDomain domain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ArtworkAccent(
      artUrl: artUrl,
      domain: domain,
      child: WaxBackdrop(
        domain: domain,
        // The scaffold's dismissal, on the surfaces that have no
        // scaffold. Unlike the player proper this has no content card to
        // hold a tap back from: these states are a glyph, two lines, and
        // at most one button, and the button is the deeper hit target so
        // it still gets its own taps. Everything else here is backdrop,
        // and a tap on backdrop leaves.
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Same reason as the scaffold's: a published tap action here
            // would be an unnamed control the size of the window, and
            // the collapse button beside it already says what it does.
            excludeFromSemantics: true,
            onTap: () => leavePlayer(context),
            child: SafeArea(
              child: Column(
                children: <Widget>[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: WaxSpace.s8,
                      ),
                      child: WaxIconButton(
                        glyph: WaxIcons.collapse,
                        label: 'Collapse player',
                        onPressed: () => leavePlayer(context),
                        semanticsId: SemanticsIds.playerBack,
                      ),
                    ),
                  ),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Leaves the player, however it was opened.
///
/// The player is pushed over whatever was underneath, so popping is
/// right nearly always; a cold arrival on `/now-playing` has nothing
/// under it, and there the way out is home rather than a dead control.
/// `maybeOf`, matching what the overflow's delete does with the router it
/// captures: one policy for a player mounted outside a router, rather
/// than a menu row that shrugs and a collapse button that throws.
void leavePlayer(BuildContext context) => leaveWith(GoRouter.maybeOf(context));

/// The same, for a caller that has to leave after work it awaited.
///
/// The router outlives this screen and a `BuildContext` does not:
/// deleting the playing item finishes whenever the server answers, and
/// by then the surface that asked may be gone. Null where the player is
/// mounted outside a router at all, which is a test host rather than a
/// running app, and where there is nowhere to leave to.
void leaveWith(GoRouter? router) {
  if (router == null) return;
  if (router.canPop()) {
    router.pop();
    return;
  }
  router.go(WaxRoute.home);
}

/// One item playing, drawn through the scaffold.
class PlayerFace extends ConsumerStatefulWidget {
  const PlayerFace({required this.session, required this.item, super.key});

  final PlaybackSession session;
  final ItemSummary item;

  @override
  ConsumerState<PlayerFace> createState() => _PlayerFaceState();
}

class _PlayerFaceState extends ConsumerState<PlayerFace> {
  /// The live position, fed into the one leaf that draws it. The face
  /// itself never rebuilds for it: it holds the artwork hero, and
  /// rebuilding that several times a second would re-ask the artwork
  /// store for a cover per frame.
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  StreamSubscription<Duration>? _feed;

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(covariant PlayerFace old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, widget.session)) _follow();
  }

  void _follow() {
    unawaited(_feed?.cancel());
    _position.value = widget.session.displayPosition;
    _feed = widget.session.displayPositionStream.listen((position) {
      _position.value = position;
    });
  }

  @override
  void dispose() {
    unawaited(_feed?.cancel());
    _position.dispose();
    super.dispose();
  }

  ItemSummary get _item => widget.item;
  PlaybackSession get _session => widget.session;
  bool get _music => _item.mediaType == MediaType.music;
  bool get _book => _item.mediaType == MediaType.audiobook;

  /// The episode being played, when the layer above resolved one. The
  /// show pid hangs off it, and the per-show controls hang off that.
  EpisodeSummary? get _episode {
    final item = _item;
    return item is EpisodeSummary ? item : null;
  }

  /// Read at tap time, never at build time: this rebuilds when what is
  /// playing changes, not as it plays, so a captured position would be
  /// where the item stood when it started.
  int get _positionMs => _session.displayPosition.inMilliseconds;

  /// What the scaffold draws from: the identity half of the item.
  ///
  /// The scaffold reads the title, the subtitle, the provenance, the
  /// artwork, its shape, and the domain. The playback half is filled
  /// truthfully because the struct asks for it, and only [position] is a
  /// snapshot rather than a stream - the clusters that tick take the
  /// notifier directly, so anything added here that wants a live
  /// position has to take it the same way rather than reading this.
  NowPlayingData _now({
    required bool playing,
    required bool shuffled,
    required QueueRepeat repeat,
    required QueueSource source,
  }) {
    return NowPlayingData(
      title: _item.title,
      subtitle: _item.artist,
      provenance: queueProvenance(source),
      artwork: waxArtwork(ref.read(artworkStoreProvider), _item.artUrl),
      domain: waxDomainOf(_item.mediaType),
      shape: waxShapeOf(_item.mediaType),
      position: _position.value,
      duration: _session.mediaDuration,
      playing: playing,
      shuffled: shuffled,
      repeat: switch (repeat) {
        QueueRepeat.off => WaxRepeat.off,
        QueueRepeat.all => WaxRepeat.all,
        QueueRepeat.one => WaxRepeat.one,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // The two standing modes plus where the queue came from, and nothing
    // else about it: watching the whole queue rebuilds this face on
    // every edit, and a drag reorder in the panel beside it emits one
    // per frame.
    final modes = ref.watch(
      queueControllerProvider.select((q) => (q.shuffled, q.repeat, q.source)),
    );
    final skips = ref.watch(skipIntervalsProvider);
    // Read here rather than inside the transport's builder: everything
    // below runs when the engine's playing stream ticks, which is a
    // build of that leaf and not of this widget, and a `watch` from
    // there would be registering a dependency out of phase.
    final canDelete = canDeleteItems(ref);
    // Same reason, and it decides two things at once: whether the action
    // row carries car mode, and whether the overflow still offers it.
    final carMode = ref.watch(carModeButtonProvider);
    final playback = ref.read(nowPlayingProvider.notifier);
    final queue = ref.read(queueControllerProvider.notifier);

    return StreamBuilder<bool>(
      stream: _session.engine.playingStream,
      initialData: _session.engine.playing,
      builder: (context, snapshot) {
        final playing = snapshot.data ?? false;
        return PlayerScaffold(
          now: _now(
            playing: playing,
            shuffled: modes.$1,
            repeat: modes.$2,
            source: modes.$3,
          ),
          ids: _ids,
          onCollapse: () => leavePlayer(context),
          trailingHeaderActions: _headerActions(
            context,
            canDelete: canDelete,
            carMode: carMode,
          ),
          // The show an episode is from, above its title and tappable
          // (5.3). Books and tracks name their maker under the title
          // instead, which is what the subtitle already is.
          titleOverline: _episode == null
              ? null
              : ShowOverline(episode: _episode!),
          subtitleOverride:
              _book && (_session.book?.chapters.isNotEmpty ?? false)
              ? BookSubtitle(
                  chapters: _session.book!.chapters,
                  position: _position,
                )
              : null,
          titleTrailing: ItemStarRatingRow(pid: _item.pid),
          seek: _book
              ? BookSeek(
                  session: _session,
                  position: _position,
                  chapters: _session.book?.chapters ?? const <ChapterMark>[],
                )
              : _Seek(
                  session: _session,
                  item: _item,
                  position: _position,
                  playing: playing,
                ),
          transport: TransportCluster(
            ids: _ids,
            playing: playing,
            shuffled: modes.$1,
            repeat: modes.$2 != QueueRepeat.off,
            onPlayPause: _session.toggle,
            onPrevious: _music ? () => unawaited(playback.previous()) : null,
            onNext: _music ? () => unawaited(playback.next()) : null,
            onSkipBack: _music ? null : () => unawaited(_seekBy(-skips.back)),
            onSkipForward: _music
                ? null
                : () => unawaited(_seekBy(skips.forward)),
            onShuffle: _music ? () => queue.setShuffle(!modes.$1) : null,
            onRepeat: _music
                ? () => queue.setRepeat(nextQueueRepeat(modes.$2))
                : null,
            skipBackSeconds: skips.back.inSeconds,
            skipForwardSeconds: skips.forward.inSeconds,
          ),
          volume: const _VolumeRow(),
          actionRow: _actionRow(context, carMode: carMode),
          bottomRegion: _music
              ? const _UpNextPeek()
              : SpokenBottomRegion(session: _session, position: _position),
        );
      },
    );
  }

  Future<void> _seekBy(Duration delta) {
    final target = _session.displayPosition + delta;
    return _session.seek(target < Duration.zero ? Duration.zero : target);
  }

  /// Cast and the one overflow. Everything else that acts on the item
  /// lives inside that menu: 5.3 gives the header two controls, and a
  /// player whose chrome is a row of glyphs is a toolbar with artwork.
  List<Widget> _headerActions(
    BuildContext context, {
    required bool canDelete,
    required bool carMode,
  }) {
    // Captured while the surface is still standing: a delete finishes
    // when the server answers, and what it leaves behind is a player
    // whose item no longer exists. `maybeOf` because this runs during
    // build, where a widget test mounting the player on its own has no
    // router to find and no reason to need one.
    final router = GoRouter.maybeOf(context);
    return <Widget>[
      WaxIconButton(
        glyph: WaxIcons.cast,
        label: 'Play on',
        semanticsId: SemanticsIds.playerDevices,
        onPressed: () => unawaited(
          showDevicePicker(
            context,
            from: CastSource.here,
            currentPid: _item.pid,
            positionMs: _positionMs,
          ),
        ),
      ),
      DownloadAction(
        pid: _item.pid,
        artUrl: _item.artUrl,
        semanticsId: SemanticsIds.downloadButton,
      ),
      WaxMenuButton<_PlayerMenuAction>(
        semanticsId: SemanticsIds.playerMore,
        items: <WaxMenuItem<_PlayerMenuAction>>[
          // The episode rows first: they are what a listener reaches
          // this menu for on a podcast, and 5.3 names them.
          if (_episode != null) ...<WaxMenuItem<_PlayerMenuAction>>[
            const WaxMenuItem(
              value: _PlayerMenuAction.markPlayed,
              label: 'Mark as played',
              glyph: WaxIcons.check,
              semanticsId: SemanticsIds.playerMarkPlayed,
            ),
            const WaxMenuItem(
              value: _PlayerMenuAction.goToShow,
              label: 'Go to show',
              glyph: WaxIcons.podcasts,
              // Not the overline's handle: the show name above the
              // title is a second control that does the same thing, and
              // both stand in the tree while this menu is open.
              semanticsId: SemanticsIds.playerGoToShow,
            ),
            if (_funding != null)
              WaxMenuItem(
                value: _PlayerMenuAction.funding,
                label: _funding!.message ?? 'Support the show',
                glyph: WaxIcons.star,
                semanticsId: SemanticsIds.playerFunding,
              ),
          ],
          const WaxMenuItem(
            value: _PlayerMenuAction.addToPlaylist,
            label: 'Add to playlist',
            glyph: WaxIcons.playlists,
            semanticsId: SemanticsIds.addToPlaylist,
          ),
          const WaxMenuItem(
            value: _PlayerMenuAction.share,
            label: 'Share link',
            glyph: WaxIcons.share,
            semanticsId: SemanticsIds.shareLink,
          ),
          // Music only: what it draws is the peak envelope, and the
          // three populations that never have one are the three other
          // faces. A row that opened an empty state would be a menu
          // entry that exists to disappoint.
          if (_music)
            const WaxMenuItem(
              value: _PlayerMenuAction.visualizer,
              // The record, not the waveform: the waveform glyph is the
              // discovery control two rows up, and one page should not
              // wear it twice.
              glyph: WaxIcons.albums,
              label: 'Visualizer',
              semanticsId: SemanticsIds.playerVisualizer,
            ),
          // Gone from the menu once the row above carries it: the verb
          // is the same one and so is its handle, and the same
          // identifier twice in one tree is what a menu row and a
          // button both claiming it would be.
          if (!carMode)
            const WaxMenuItem(
              value: _PlayerMenuAction.carMode,
              glyph: WaxIcons.car,
              label: 'Car mode',
              semanticsId: SemanticsIds.playerCarMode,
            ),
          if (canDelete)
            const WaxMenuItem(
              value: _PlayerMenuAction.delete,
              label: 'Delete files...',
              glyph: WaxIcons.delete,
              destructive: true,
              semanticsId: SemanticsIds.itemDelete,
            ),
        ],
        onSelected: (action) => unawaited(switch (action) {
          _PlayerMenuAction.addToPlaylist => showAddToPlaylistSheet(
            context,
            item: _item,
          ),
          // Episodes offer the current position as the share's start
          // point; other media share from the top.
          _PlayerMenuAction.share => showShareLinkDialog(
            context,
            pid: _item.pid,
            positionMs: _item.mediaType == MediaType.podcast
                ? _positionMs
                : null,
          ),
          _PlayerMenuAction.delete => confirmDeleteItem(
            context,
            pid: _item.pid,
            onDeleted: () => leaveWith(router),
          ),
          _PlayerMenuAction.markPlayed => EpisodeActions(
            ref: ref,
          ).markPlayed(context, _episode!, playPidsKey(<String>[_item.pid])),
          _PlayerMenuAction.goToShow => Future<void>.sync(
            () => context.go(WaxRoute.show(_episode!.showPid)),
          ),
          // Pushed over the player rather than replacing it: both are
          // views of the same playback, and leaving either lands back on
          // the face somebody opened it from.
          _PlayerMenuAction.visualizer => Future<void>.sync(
            () => context.push(WaxRoute.visualizer),
          ),
          _PlayerMenuAction.carMode => Future<void>.sync(
            () => context.push(WaxRoute.carMode),
          ),
          _PlayerMenuAction.funding =>
            ref.read(urlOpenerProvider).open(_funding!.url),
        }),
      ),
    ];
  }

  /// The show's support pointer, when its feed declares one.
  PodcastFunding? get _funding {
    final episode = _episode;
    if (episode == null) return null;
    return ref
        .watch(podcastDetailProvider(episode.showPid))
        .value
        ?.show
        .funding;
  }

  /// The per-medium verbs.
  ///
  /// Music gets the queue and the discovery menu 5.3 calls "More like
  /// this"; spoken word gets rate, the two effects, and a book's
  /// bookmarks. The chapter list is no longer a button here: it is the
  /// bottom region, where 5.3 puts it.
  Widget _actionRow(BuildContext context, {required bool carMode}) {
    // A wrap rather than a row: the spoken-word faces carry four
    // labelled chips, which do not fit a phone in one line, and a Row
    // answers that by overflowing. The hero above gives up the height a
    // second line takes.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: WaxSpace.s8,
      runSpacing: WaxSpace.s8,
      children: <Widget>[
        if (_music) ...<Widget>[
          // First in the row, where 5.3 puts it: the words are what a
          // listener reaches the music face for while a track plays,
          // and the queue is what they reach it for between tracks.
          WaxIconButton(
            glyph: WaxIcons.lyrics,
            label: 'Lyrics',
            semanticsId: SemanticsIds.playerLyrics,
            // Always the overlay, whatever the width: this screen is a
            // route pushed over the shell, so the panel it would
            // otherwise open opens behind it.
            onPressed: () => openLyrics(context, ref, overShell: true),
          ),
          WaxIconButton(
            glyph: WaxIcons.queue,
            label: 'Queue',
            semanticsId: SemanticsIds.playerQueue,
            onPressed: () => openQueue(context, ref, overShell: true),
          ),
          WaxMenuButton<String>(
            glyph: WaxIcons.waveform,
            label: 'More like this',
            semanticsId: SemanticsIds.playerDiscover,
            items: const <WaxMenuItem<String>>[
              WaxMenuItem(
                value: 'mix',
                label: 'Instant mix',
                semanticsId: SemanticsIds.instantMix,
              ),
              WaxMenuItem(
                value: 'similar',
                label: 'Similar tracks',
                semanticsId: SemanticsIds.similarTracks,
              ),
            ],
            onSelected: (choice) => unawaited(switch (choice) {
              'mix' => showInstantMixSheet(context, _item),
              _ => openSimilarTracks(context, ref, _item),
            }),
          ),
        ] else
          ...spokenActionChips(_session),
        // Every face, not only the spoken-word ones 5.3 lists it under:
        // falling asleep to a record is what the control is for, and it
        // is about the device rather than the medium.
        SleepTimerButton(session: _session),
        // Only where somebody asked for it (5.6). The verb is in the
        // overflow for everybody; this is the row for the listener who
        // takes the same phone to the same car every morning.
        if (carMode)
          WaxIconButton(
            glyph: WaxIcons.car,
            label: 'Car mode',
            semanticsId: SemanticsIds.playerCarMode,
            onPressed: () => context.push(WaxRoute.carMode),
          ),
      ],
    );
  }
}

/// The seek cluster and nothing else, rebuilt as the item plays.
///
/// Its own widget so the position ticks here rather than through the
/// face: the artwork hero, the title block, and the transport are
/// unchanged between one second and the next.
class _Seek extends ConsumerWidget {
  const _Seek({
    required this.session,
    required this.item,
    required this.position,
    required this.playing,
  });

  final PlaybackSession session;
  final ItemSummary item;
  final ValueListenable<Duration> position;

  /// The seek cluster draws from the position, the duration, and the
  /// live flag, and reads this one not at all. Passed through anyway
  /// because it is cheap and true, where a hardcoded `true` would be
  /// neither - but nothing here depends on it today.
  final bool playing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Music only, and the caller rather than the provider decides that:
    // a podcast episode is never analyzed, and a book's bar is a
    // chapter's rather than the file's, so both would be a request that
    // answers "no" at best.
    final peaks = item.mediaType == MediaType.music
        ? ref.watch(waveformProvider(item.pid)).value
        : null;
    return ValueListenableBuilder<Duration>(
      valueListenable: position,
      builder: (context, at, _) => SeekCluster(
        now: NowPlayingData(
          title: item.title,
          position: at,
          duration: session.mediaDuration,
          playing: playing,
        ),
        peaks: peaks,
        onSeek: (to) => unawaited(session.seek(to)),
        semanticsId: SemanticsIds.playerSeek,
      ),
    );
  }
}

/// What is next in the queue, as the drag-up handle for the queue
/// itself.
///
/// A peek rather than a list: the queue has a surface of its own on both
/// sides of the sidebar breakpoint, and this is the line that says
/// whether it is worth opening.
class _UpNextPeek extends ConsumerWidget {
  const _UpNextPeek();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final queue = ref.watch(queueControllerProvider);
    // The queue's own answer, not a second reading of it. Repeat-one
    // plays this item again and has no next; repeat-all on the last
    // entry wraps to the first. Deriving it from the index here named
    // the following track under repeat-one and showed nothing at the end
    // of a repeating queue - both wrong, and both already decided by the
    // state the engine preloads from.
    final next = queue.nextEntry;
    if (next == null) return const SizedBox.shrink();
    final item = ref.watch(queueItemProvider(next.pid)).value;
    // Zero where the next entry is a wrap rather than a step forward:
    // "0 left" beside a named track is a count of what has not played,
    // and on a repeating queue that is the honest number.
    final remaining = queue.unplayed;
    final left = remaining > 0 ? ', $remaining left' : '';

    return WaxTappable(
      semanticsId: SemanticsIds.playerUpNext,
      label: item == null ? 'Up next$left' : 'Up next, ${item.title}$left',
      borderRadius: WaxRadius.sheetTop,
      onPressed: () => openQueue(context, ref, overShell: true),
      // Ink outside, InkWell in: the scaffold's only Material is
      // transparent, so a splash under an opaquely decorated Container
      // paints beneath it and never appears. Ink puts the decoration
      // into the Material instead, which is what the splash draws on.
      child: Ink(
        decoration: BoxDecoration(
          color: colors.surface1.withValues(alpha: 0.92),
          borderRadius: WaxRadius.sheetTop,
          border: Border(top: BorderSide(color: colors.hairline)),
        ),
        child: InkWell(
          onTap: () => openQueue(context, ref, overShell: true),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              WaxSpace.s16,
              WaxSpace.s8,
              WaxSpace.s16,
              WaxSpace.s16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: WaxSpace.s8),
                  decoration: BoxDecoration(
                    color: colors.textTertiary,
                    borderRadius: WaxRadius.pill,
                  ),
                ),
                Row(
                  children: <Widget>[
                    Text(
                      'UP NEXT',
                      style: WaxType.overline.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                    const Spacer(),
                    if (remaining > 0)
                      Text(
                        '$remaining left',
                        style: WaxType.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: WaxSpace.s4),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        item?.title ?? 'Loading...',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WaxType.body.copyWith(color: colors.textPrimary),
                      ),
                    ),
                    if (item?.artist != null) ...<Widget>[
                      const SizedBox(width: WaxSpace.s8),
                      Text(
                        item!.artist!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WaxType.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// This device's own output level.
///
/// Drawn where the platform gives the app a level to set, which is
/// desktop and web; a phone and a tablet get nothing, because the
/// hardware buttons own local volume there and a software slider fights
/// the OS volume stack rather than driving it. The deck bar answers the
/// same question and adds a width condition of its own - a 64 px bar has
/// nowhere to put a track - and this screen is the surface that has the
/// room, so a narrow window reaches its level here.
///
/// Nothing is stored: the level follows the engine, which is written from
/// three places no widget hears about (a routed set-volume, the sleep
/// timer's fade, this slider), so a control holding its own copy would
/// draw a loudness the output no longer has.
class _VolumeRow extends ConsumerWidget {
  const _VolumeRow();

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
      semanticsId: SemanticsIds.playerVolume,
      muteSemanticsId: SemanticsIds.playerMute,
      onChanged: (value) => unawaited(volume.set(value)),
      onMute: () => unawaited(volume.toggleMute()),
    );
  }
}

/// Sleep timer button plus its options sheet. When a timer runs, the
/// remaining time shows as a badge on the button.
///
/// [session] is null on the radio face, which has no item and therefore
/// no chapter to end on. Everything else about the control is the same
/// there: the timer is about the device, not about what it is playing.
class SleepTimerButton extends ConsumerWidget {
  const SleepTimerButton({required this.session, super.key});

  final PlaybackSession? session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(sleepTimerProvider);
    return WaxIconButton(
      glyph: WaxIcons.sleepTimer,
      label: timer.active ? 'Sleep timer, ${timer.label} left' : 'Sleep timer',
      active: timer.active,
      badge: timer.active ? timer.label : null,
      semanticsId: SemanticsIds.sleepTimerOpen,
      onPressed: () => unawaited(
        showModalBottomSheet<void>(
          context: context,
          builder: (_) => _SleepTimerSheet(session: session),
        ),
      ),
    );
  }
}

class _SleepTimerSheet extends ConsumerStatefulWidget {
  const _SleepTimerSheet({required this.session});

  final PlaybackSession? session;

  @override
  ConsumerState<_SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends ConsumerState<_SleepTimerSheet> {
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  /// Where the current chapter ends on the book timeline, for
  /// end-of-chapter mode; null when the book has no chapters.
  int? _currentChapterEndMs() {
    final session = widget.session;
    final book = session?.book;
    if (session == null || book == null || book.chapters.isEmpty) return null;
    final current = chapterAt(book.chapters, session.displayPosition);
    if (current == null) return null;
    return chapterEndMs(book.chapters, current, book.durationMs);
  }

  void _startMinutes(int minutes) {
    ref.read(sleepTimerProvider.notifier).startMinutes(minutes);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final timer = ref.watch(sleepTimerProvider);
    final chapterEndMs = widget.session?.item.mediaType == MediaType.audiobook
        ? _currentChapterEndMs()
        : null;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Both of the running timer's own verbs first, and together:
            // a listener who opened this sheet with a timer on came to
            // change that timer, not to set a new one, and the presets
            // below are long enough to push a row at the bottom out of
            // a half-height sheet.
            if (timer.active) ...[
              Semantics(
                identifier: SemanticsIds.sleepTimerExtend,
                button: true,
                child: ListTile(
                  key: const Key(SemanticsIds.sleepTimerExtend),
                  leading: const WaxIcon(WaxIcons.add),
                  title: const Text('Extend 10 minutes'),
                  subtitle: Text('${timer.label} left'),
                  onTap: () {
                    ref.read(sleepTimerProvider.notifier).extend();
                    Navigator.of(context).pop();
                  },
                ),
              ),
              Semantics(
                identifier: SemanticsIds.sleepTimerCancel,
                button: true,
                child: ListTile(
                  key: const Key(SemanticsIds.sleepTimerCancel),
                  leading: const WaxIcon(WaxIcons.close),
                  title: const Text('Cancel timer'),
                  onTap: () {
                    ref.read(sleepTimerProvider.notifier).cancel();
                    Navigator.of(context).pop();
                  },
                ),
              ),
              const Divider(height: WaxSpace.s16),
            ],
            for (final minutes in const [5, 15, 30, 60])
              Semantics(
                identifier: SemanticsIds.sleepTimer(minutes),
                button: true,
                child: ListTile(
                  key: ValueKey(SemanticsIds.sleepTimer(minutes)),
                  leading: const WaxIcon(WaxIcons.sleepTimer),
                  title: Text('$minutes minutes'),
                  onTap: () => _startMinutes(minutes),
                ),
              ),
            if (chapterEndMs != null)
              Semantics(
                identifier: SemanticsIds.sleepTimerChapter,
                button: true,
                child: ListTile(
                  key: const Key(SemanticsIds.sleepTimerChapter),
                  leading: const WaxIcon(WaxIcons.audiobooks),
                  title: const Text('End of chapter'),
                  onTap: () {
                    ref
                        .read(sleepTimerProvider.notifier)
                        .startEndOfChapter(chapterEndMs);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      identifier: SemanticsIds.sleepTimerCustomField,
                      textField: true,
                      child: TextField(
                        key: const Key(SemanticsIds.sleepTimerCustomField),
                        controller: _custom,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Custom minutes',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    identifier: SemanticsIds.sleepTimerCustomStart,
                    label: 'Start custom timer',
                    button: true,
                    child: TextButton(
                      key: const Key(SemanticsIds.sleepTimerCustomStart),
                      onPressed: () {
                        final minutes = int.tryParse(_custom.text.trim());
                        if (minutes != null && minutes > 0) {
                          _startMinutes(minutes);
                        }
                      },
                      child: const Text('Start'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
