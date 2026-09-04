import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/art_source_label.dart';
import '../artwork/artwork_palette.dart';
import '../artwork/artwork_providers.dart';
import '../connect/device_picker.dart';
import '../discovery/discovery_actions.dart';
import '../l10n/l10n.dart';
import '../library/item_delete.dart';
import '../media_view.dart';
import '../metadata/metadata_controller.dart';
import '../player/play_progress.dart';
import '../playlists/add_to_playlist_sheet.dart';
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
  editMetadata,
}

/// The e2e handles the player's own controls carry. One place, because
/// the design system emits no identifier strings of its own,
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
    // A stopped station empties the state under a mounted route, so the
    // face falls to "nothing playing" with no deck bar to minimize to.
    // On the state, not the button: seven paths reach the same stop.
    final route = ModalRoute.of(context);
    ref.listen(radioPlaybackProvider, (previous, next) {
      if (previous?.station == null || next.station != null) return;
      // `interrupt` empties it too when an item takes the engine, but
      // installs its entry first: a face swap, not a stop.
      if (ref.read(nowPlayingProvider).entry != null) return;
      // Or the pop takes a dialog open over the player instead.
      if (!(route?.isCurrent ?? true)) return;
      leavePlayer(context);
    });
    // What the palette can offer here, which is the second half of the
    // overflow row below: a listener who cannot find a menu can type
    // the verb. Scoped rather than standing, because a standing command
    // would need a "current item" concept the registry does not have.
    //
    // Offered on exactly the face that draws the row, which is the one
    // arm of `_body` below holding both a session and an item: a
    // station has taken the engine, a failed start draws a retry, and a
    // resolving entry draws a spinner - all three still name an item,
    // and none of them is a surface to be offered an editor from.
    final nowPlaying = ref.watch(nowPlayingProvider);
    final editing =
        ref.watch(radioPlaybackProvider).station == null &&
            nowPlaying.error == null &&
            nowPlaying.session != null
        ? nowPlaying.item?.pid
        : null;
    final mayCurate =
        editing != null &&
        (ref.watch(mayCurateItemProvider(editing)).value ?? false);
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
          label: context.l10n.playerCollapseCommand,
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
        if (mayCurate)
          WaxCommand(
            id: 'edit-metadata',
            label: context.l10n.reviewEditMetadata,
            section: WaxCommandSection.app,
            glyph: WaxIcons.edit,
            // Read when it runs rather than captured when it is
            // registered. `CommandScope` republishes on a changed
            // *offer* - id, name, place, keys - and this command's offer
            // is the same for every track, so a closure over the pid
            // registered on one track could still be standing on the
            // next. The overflow row below has no such problem: it is
            // rebuilt with the face.
            run: (context, ref) {
              final pid = ref.read(nowPlayingProvider).item?.pid;
              // `go` for the same reason the row above uses it.
              if (pid != null) context.go(WaxRoute.metadata(pid));
            },
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
    final onAir = radio.station != null;
    final nowPlaying = onAir ? null : ref.watch(nowPlayingProvider);
    final item = nowPlaying?.item;
    final domain = onAir
        ? WaxDomain.radio
        : waxDomainOf(item?.mediaType ?? MediaType.music);

    final Widget face;
    // The queue is what decides whether anything is playing. An item
    // still resolving, or one whose start failed before it could be
    // named, is not nothing: saying so would hide the failure and the
    // button that retries it.
    if (nowPlaying == null) {
      face = RadioFace(playback: radio);
    } else if (nowPlaying.entry == null) {
      face = _PlayerShell(
        domain: domain,
        child: EmptyState(
          key: const Key('player-idle'),
          glyph: WaxIcons.headphones,
          title: context.l10n.playerNothingPlaying,
          message: context.l10n.playerIdleMessage,
          semanticsId: SemanticsIds.playerSurface,
        ),
      );
    } else {
      face = switch (nowPlaying) {
        NowPlaying(:final Object error) => _PlayerShell(
          domain: domain,
          child: ErrorState(
            key: const Key('player-error'),
            title: context.l10n.playerStopped,
            // `NowPlaying.error` holds whatever the start threw, and the
            // engine's exceptions are not the contract's: the table has
            // nothing to say about a codec, so those keep the sentence
            // that at least says what failed.
            message: error is WaxDeckApiException
                ? context.explain(error)
                : context.l10n.playerStartFailed,
            // The queue still holds the entry, and nothing else will try
            // it again: without this the failure is where playback stops
            // until something rebuilds the queue.
            onRetry: ref.read(nowPlayingProvider.notifier).resume,
            semanticsId: SemanticsIds.playerSurface,
            retrySemanticsId: SemanticsIds.playerRetry,
          ),
        ),
        // The entry alone, which is what the deck bar branches on and
        // why it does not flash. A start occupies the state with an
        // entry and no session for as long as the resolve and the load
        // take, and reading that window as "not playing yet" swapped
        // this branch for a spinner on every advance - a widget-type
        // change, so the face, its hero, its ticker and its artwork
        // were torn down and rebuilt each time. The face tolerates a
        // session-less state instead, and stays the same element.
        _ => PlayerFace(
          session: nowPlaying.session,
          item: nowPlaying.item,
          domain: domain,
        ),
      };
    }

    // One accent over every state this screen has, rather than one
    // inside each. A track change publishes a session-less state for the
    // frames the resolve takes, and that is a different branch above:
    // an accent per branch is a fresh element each time, which drops the
    // palette it was holding and crossfades through the domain hue and
    // back - the flash the holding is there to stop.
    return ArtworkAccent(
      // Radio draws its own picture and asks for no accent from it: the
      // cover it shows is borrowed and turns over with the songs.
      artUrl: onAir ? null : item?.artUrl,
      // A start publishes its entry before the summary behind it
      // resolves, and a queue handed over from another device arrives
      // with pids this layer has never seen - so a null item here is
      // usually "not yet" rather than "no cover", and the accent holds
      // instead of crossfading through the domain hue and back.
      resolving: !onAir && nowPlaying?.entry != null && item == null,
      domain: domain,
      child: face,
    );
  }
}

/// The backdrop and the way out, for the states with no item to draw.
///
/// The scaffold proper needs a session; these do not, and they still
/// have to be leaveable and still have to look like the player rather
/// than like a blank route.
class _PlayerShell extends ConsumerWidget {
  const _PlayerShell({required this.child, this.domain = WaxDomain.music});

  final Widget child;
  final WaxDomain domain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No accent of its own: the screen puts one over all of its states
    // at once, so that a state passing through here on the way to a
    // playing one does not take the held palette with it.
    return WaxBackdrop(
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
                      label: context.l10n.playerCollapse,
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

/// The player while the queue has an entry: playing, loading, or
/// standing where a start left it.
///
/// Both halves of what it draws are nullable, and for the same reason.
/// A start publishes the entry first and the session only once the load
/// lands, so a face that demanded a session would be replaced by a
/// spinner on every advance - a different widget type, which tears down
/// the hero, the ticker and the artwork it was holding. The summary is
/// normally in hand from the preload's own resolve; when it is not, the
/// last one is held rather than dropped, so the face persists for the
/// frames a fetch takes instead of blinking. A face with no summary yet
/// draws the spinner itself, which is the cold open and the one case
/// where there is genuinely nothing to show.
class PlayerFace extends ConsumerStatefulWidget {
  const PlayerFace({
    required this.session,
    required this.item,
    this.domain = WaxDomain.music,
    super.key,
  });

  /// Null while a start is between its entry and its load. Seeking and
  /// the spoken-word controls are off for that window; the transport
  /// stays, because pressing play during it is a real intent the
  /// controller already answers.
  final PlaybackSession? session;

  /// Null only until the summary resolves. [_shown] is what is drawn.
  final ItemSummary? item;

  /// Drawn by the spinner shell, which has no item to derive one from.
  final WaxDomain domain;

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

  /// The last summary this face was given, which is what it keeps
  /// drawing while the next one resolves.
  ItemSummary? _shown;

  @override
  void initState() {
    super.initState();
    _shown = widget.item;
    _follow();
  }

  @override
  void didUpdateWidget(covariant PlayerFace old) {
    super.didUpdateWidget(old);
    if (widget.item != null) _shown = widget.item;
    if (!identical(old.session, widget.session)) _follow();
  }

  void _follow() {
    unawaited(_feed?.cancel());
    final session = widget.session;
    // Zero rather than the outgoing position: the next track starts at
    // its own beginning, and holding the old number would run the bar
    // backwards from wherever the last one ended.
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

  ItemSummary get _item => _shown!;
  PlaybackSession? get _session => widget.session;
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
  int get _positionMs => _session?.displayPosition.inMilliseconds ?? 0;

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
      // An episode's artist is its show, already drawn above as the
      // tappable overline. Books and tracks name theirs nowhere else.
      subtitle: _episode == null ? _item.artist : null,
      provenance: queueProvenance(context.l10n, source),
      artwork: waxArtwork(ref.read(artworkStoreProvider), _item.artUrl),
      domain: waxDomainOf(_item.mediaType),
      shape: waxShapeOf(_item.mediaType),
      position: _position.value,
      // The summary's own length until the session can answer, so the
      // bar has a scale to draw before the load lands.
      duration:
          _session?.mediaDuration ?? Duration(milliseconds: _item.durationMs),
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
    // Nothing has ever resolved here, which is the cold open. Every
    // other pass has a summary to hold, so this is the only state that
    // draws a spinner - and it is a shell rather than a face, so the
    // hero is never built with nothing in it.
    if (_shown == null) {
      return _PlayerShell(
        domain: widget.domain,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
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
    // Same reason, and the seek cluster below already reads this track's
    // envelope, so the header costs no extra request by asking too: both
    // derive from the one provider.
    final hasShape =
        _music &&
        waveformMayHavePeaks(ref.watch(trackWaveformProvider(_item.pid)));
    // Same reason, and it decides two things at once: whether the action
    // row carries car mode, and whether the overflow still offers it.
    final carMode = ref.watch(carModeButtonProvider);
    // Same reason again. One read for the one item on screen, which is
    // what makes this affordable here and not on a list of rows.
    final mayCurate =
        ref.watch(mayCurateItemProvider(_item.pid)).value ?? false;
    // Where the cover under the hero came from, for the mark under it.
    // Affordable here for the same reason as the read above: one item,
    // the one on screen, and Phase 4's `ArtProvenance` made the server
    // side of it a row lookup rather than an image decode. It is
    // deliberately not on `ItemSummary`, so no list row pays for it.
    final artSource = ref
        .watch(itemArtRolesProvider(_item.pid))
        .value
        ?.artSource;
    final playback = ref.read(nowPlayingProvider.notifier);
    final queue = ref.read(queueControllerProvider.notifier);

    // The engine rather than the session's handle on it: they are the
    // same object, and reading it from the provider is what lets the
    // transport keep ticking through the window where there is no
    // session to reach it through.
    final engine = ref.watch(audioEngineProvider);
    return StreamBuilder<bool>(
      stream: engine.playingStream,
      initialData: engine.playing,
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
            mayCurate: mayCurate,
            hasShape: hasShape,
          ),
          // A cover fetched from a third party says so here too, at the
          // one size in the app where the picture is the whole screen.
          // Nothing gates it: the mark is the same sentence the album
          // header and the artwork manager draw, from the same wording.
          artworkCaption: artSourceLabelWithBorrow(context.l10n, artSource),
          // Held for the session rather than only while the read above is
          // in flight. That read lands after the first frame, and it
          // answers null for a library nothing has enriched and for
          // every track whose picture came from its own file - so a slot
          // reserved by the request alone is a cover drawn small and
          // then grown, which is the resize this is here to stop.
          artworkCaptionReserved: true,
          // The show an episode is from, above its title and tappable
          // (5.3). Books and tracks name their maker under the title
          // instead, which is what the subtitle already is.
          titleOverline: _episode == null
              ? null
              : ShowOverline(episode: _episode!),
          subtitleOverride:
              _book && (_session?.book?.chapters.isNotEmpty ?? false)
              ? BookSubtitle(
                  chapters: _session!.book!.chapters,
                  position: _position,
                )
              : null,
          titleTrailing: ItemStarRatingRow(pid: _item.pid),
          // The chapter bar needs a session to seek within; without
          // one the plain cluster stands in, which is the same bar with
          // its handle inert. Not a spinner and not nothing: the scale
          // is the item's own length and it is honest for the frames
          // this lasts.
          seek: _book && _session != null
              ? BookSeek(
                  session: _session!,
                  position: _position,
                  chapters: _session!.book?.chapters ?? const <ChapterMark>[],
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
            // Through the controller rather than the session: with no
            // session yet this is a resume, which is what the
            // controller answers a play press with.
            onPlayPause: playback.togglePlayback,
            onPrevious: _music ? () => unawaited(playback.previous()) : null,
            onNext: _music ? () => unawaited(playback.next()) : null,
            canNext: ref.watch(queueCanAdvanceProvider),
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
          bottomRegion: _music || _session == null
              ? const _UpNextPeek()
              : SpokenBottomRegion(session: _session!, position: _position),
        );
      },
    );
  }

  Future<void> _seekBy(Duration delta) async {
    final session = _session;
    if (session == null) return;
    final target = session.displayPosition + delta;
    await session.seek(target < Duration.zero ? Duration.zero : target);
  }

  /// Cast and the one overflow. Everything else that acts on the item
  /// lives inside that menu: 5.3 gives the header two controls, and a
  /// player whose chrome is a row of glyphs is a toolbar with artwork.
  List<Widget> _headerActions(
    BuildContext context, {
    required bool canDelete,
    required bool carMode,
    required bool mayCurate,
    required bool hasShape,
  }) {
    // Captured while the surface is still standing: a delete finishes
    // when the server answers, and what it leaves behind is a player
    // whose item no longer exists. `maybeOf` because this runs during
    // build, where a widget test mounting the player on its own has no
    // router to find and no reason to need one.
    final router = GoRouter.maybeOf(context);
    final l10n = context.l10n;
    return <Widget>[
      WaxIconButton(
        glyph: WaxIcons.cast,
        label: context.l10n.devicesPlayOn,
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
        label: l10n.playerDownload,
        semanticsId: SemanticsIds.downloadButton,
      ),
      WaxMenuButton<_PlayerMenuAction>(
        semanticsId: SemanticsIds.playerMore,
        items: <WaxMenuItem<_PlayerMenuAction>>[
          // The episode rows first: they are what a listener reaches
          // this menu for on a podcast, and 5.3 names them.
          if (_episode != null) ...<WaxMenuItem<_PlayerMenuAction>>[
            WaxMenuItem(
              value: _PlayerMenuAction.markPlayed,
              label: l10n.playerMarkPlayed,
              glyph: WaxIcons.check,
              semanticsId: SemanticsIds.playerMarkPlayed,
            ),
            WaxMenuItem(
              value: _PlayerMenuAction.goToShow,
              label: l10n.playerGoToShow,
              glyph: WaxIcons.podcasts,
              // Not the overline's handle: the show name above the
              // title is a second control that does the same thing, and
              // both stand in the tree while this menu is open.
              semanticsId: SemanticsIds.playerGoToShow,
            ),
            if (_funding != null)
              WaxMenuItem(
                value: _PlayerMenuAction.funding,
                label: _funding!.message ?? l10n.playerSupportShow,
                glyph: WaxIcons.star,
                semanticsId: SemanticsIds.playerFunding,
              ),
          ],
          WaxMenuItem(
            value: _PlayerMenuAction.addToPlaylist,
            label: l10n.playerAddToPlaylist,
            glyph: WaxIcons.playlists,
            semanticsId: SemanticsIds.addToPlaylist,
          ),
          WaxMenuItem(
            value: _PlayerMenuAction.share,
            label: l10n.playerShareLink,
            glyph: WaxIcons.share,
            semanticsId: SemanticsIds.shareLink,
          ),
          // Music only: what it draws is the peak envelope, and the
          // three populations that never have one are the three other
          // faces. A row that opened an empty state would be a menu
          // entry that exists to disappoint.
          if (_music)
            WaxMenuItem(
              value: _PlayerMenuAction.visualizer,
              // The record, not the waveform: the waveform glyph is the
              // discovery control two rows up, and one page should not
              // wear it twice.
              glyph: WaxIcons.albums,
              label: l10n.playerVisualizer,
              // Both modes are peak-driven, so a track the analyze pass
              // has not measured has nothing to draw in either. Shown
              // and disabled rather than hidden: the row disappearing
              // says nothing, and the reason is the whole answer.
              enabled: hasShape,
              help: hasShape ? null : l10n.playerVisualizerAnalysisNeeded,
              semanticsId: SemanticsIds.playerVisualizer,
            ),
          // Gone from the menu once the row above carries it: the verb
          // is the same one and so is its handle, and the same
          // identifier twice in one tree is what a menu row and a
          // button both claiming it would be.
          if (!carMode)
            WaxMenuItem(
              value: _PlayerMenuAction.carMode,
              glyph: WaxIcons.car,
              label: l10n.playerCarMode,
              semanticsId: SemanticsIds.playerCarMode,
            ),
          // The way to the editor for an ordinary track. Everywhere else
          // it is reached from a review row, a book, or an empty lyrics
          // panel - none of which a listener passes on the way to a song
          // they want to fix. The permission is the server's own answer
          // for this item rather than an administrator check, which is
          // what lets the person whose upload brought it in keep it.
          if (mayCurate)
            WaxMenuItem(
              value: _PlayerMenuAction.editMetadata,
              glyph: WaxIcons.edit,
              label: l10n.reviewEditMetadata,
              semanticsId: SemanticsIds.editMetadata(_item.pid),
            ),
          // Not for episodes: the podcast tree owns its own files and the
          // server refuses this verb there. "Remove download" is the
          // episode's equivalent, and it lives on the episode's surfaces.
          if (canDelete && _item.mediaType != MediaType.podcast)
            WaxMenuItem(
              value: _PlayerMenuAction.delete,
              label: l10n.playerDeleteFiles,
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
          // `go`, not `push`, and for the reason `lyrics.dart` writes
          // out where it opens the same editor: the player is an
          // overlay on the root navigator and `/metadata/:pid` lives
          // inside the shell, so pushing one over the other builds a
          // second shell beside the mounted one and loses the
          // navigation. Same verb as "Go to show" two rows up.
          _PlayerMenuAction.editMetadata => Future<void>.sync(
            () => context.go(WaxRoute.metadata(_item.pid)),
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
    final l10n = context.l10n;
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
            label: l10n.playerLyrics,
            semanticsId: SemanticsIds.playerLyrics,
            // Always the overlay, whatever the width: this screen is a
            // route pushed over the shell, so the panel it would
            // otherwise open opens behind it.
            onPressed: () => openLyrics(context, ref, overShell: true),
          ),
          WaxIconButton(
            glyph: WaxIcons.queue,
            label: l10n.playerQueue,
            semanticsId: SemanticsIds.playerQueue,
            onPressed: () => openQueue(context, ref, overShell: true),
          ),
          WaxMenuButton<String>(
            glyph: WaxIcons.waveform,
            label: l10n.playerMoreLikeThis,
            semanticsId: SemanticsIds.playerDiscover,
            items: <WaxMenuItem<String>>[
              WaxMenuItem(
                value: 'mix',
                label: l10n.playerInstantMix,
                semanticsId: SemanticsIds.instantMix,
              ),
              WaxMenuItem(
                value: 'similar',
                label: l10n.playerSimilarTracks,
                semanticsId: SemanticsIds.similarTracks,
              ),
            ],
            onSelected: (choice) => unawaited(switch (choice) {
              'mix' => showInstantMixSheet(context, (
                pid: _item.pid,
                title: _item.title,
              )),
              _ => openSimilarTracks(context, ref, _item),
            }),
          ),
        ] else if (_session != null)
          // Gated like the seek cluster and the bottom region above:
          // every chip here drives a live session (its rate, its
          // trim, its bookmarks), so the resolve window has nothing
          // for them to act on. Absent for those frames rather than
          // inert, which is what the rest of the spoken-word face
          // does.
          ...spokenActionChips(_session!),
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
            label: l10n.playerCarMode,
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

  /// Null between a start's entry and its load. The bar still draws -
  /// the scale is the item's own length - and its handle is inert,
  /// because there is nothing yet to seek within.
  final PlaybackSession? session;
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
          duration:
              session?.mediaDuration ?? Duration(milliseconds: item.durationMs),
          playing: playing,
        ),
        peaks: peaks,
        onSeek: session == null ? null : (to) => unawaited(session!.seek(to)),
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
    final l10n = context.l10n;
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
    final spoken = <String>[
      item == null ? l10n.playerUpNextLabel : l10n.playerUpNextItem(item.title),
      if (remaining > 0) l10n.playerLeftCount(remaining),
    ].join(', ');

    return WaxTappable(
      semanticsId: SemanticsIds.playerUpNext,
      label: spoken,
      borderRadius: WaxRadius.sheetTop,
      onPressed: () => openQueue(context, ref, overShell: true),
      // Ink outside, InkWell in: the scaffold's only Material is
      // transparent, so a splash under an opaquely decorated Container
      // paints beneath it and never appears. Ink puts the decoration
      // into the Material instead, which is what the splash draws on.
      child: Ink(
        decoration: BoxDecoration(
          color: colors.veil,
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
              // Left, like the header row above it and like every other
              // block on this screen. Centring was the Column's default
              // rather than a decision, and it put the track's name in
              // the middle of the peek under a heading pinned to the
              // left - two alignments in a strip four lines tall.
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // The one thing that is centred, and now says so: it is
                // a grab handle, and a handle belongs in the middle of
                // what it drags.
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: WaxSpace.s8),
                    decoration: BoxDecoration(
                      color: colors.textTertiary,
                      borderRadius: WaxRadius.pill,
                    ),
                  ),
                ),
                Row(
                  children: <Widget>[
                    // The cover of what is coming leads the strip,
                    // spanning both text lines beside the name it
                    // repeats - where the eye lands first, next to the
                    // words that spell it out. A fixed box whether or
                    // not the item has resolved: skipping the cell
                    // while it loads would shove both text lines
                    // sideways the moment the cover arrives.
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: item == null
                          ? null
                          : ArtworkImage(
                              size: 40,
                              artwork: waxArtwork(
                                ref.watch(artworkStoreProvider),
                                item.artUrl,
                              ),
                              monogram: item.title,
                              shape: waxShapeOf(item.mediaType),
                              domain: waxDomainOf(item.mediaType),
                            ),
                    ),
                    const SizedBox(width: WaxSpace.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              // Expanded, and the count keeps itself
                              // whole: the pair lost the cover's width,
                              // and a letter-spaced overline beside a
                              // localized count has to give somewhere
                              // on a narrow window at a large scale.
                              Expanded(
                                child: Text(
                                  l10n.playerUpNext,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: WaxType.overline.copyWith(
                                    color: colors.textTertiary,
                                  ),
                                ),
                              ),
                              if (remaining > 0)
                                Text(
                                  l10n.playerLeftCount(remaining),
                                  style: WaxType.caption.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: WaxSpace.s4),
                          // Title and artist as one paragraph rather
                          // than a row of two. A row strands the artist
                          // at the far edge if the title is Expanded,
                          // and splits the width down the middle if
                          // both are Flexible - a flex child is capped
                          // at its share and hands nothing back, so a
                          // short artist leaves a hole the title was
                          // truncated to make. One line lays out left
                          // to right and runs out at the end, which is
                          // where an ellipsis belongs.
                          Text.rich(
                            TextSpan(
                              children: <InlineSpan>[
                                TextSpan(
                                  text:
                                      item?.title ??
                                      context.l10n.commonLoadingTitle,
                                  style: WaxType.body.copyWith(
                                    color: colors.textPrimary,
                                  ),
                                ),
                                if (item?.artist != null) ...<InlineSpan>[
                                  const WidgetSpan(
                                    child: SizedBox(width: WaxSpace.s8),
                                  ),
                                  TextSpan(
                                    text: item!.artist!,
                                    style: WaxType.caption.copyWith(
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
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
      label: context.l10n.playerVolume,
      glyph: WaxIcons.volume,
      mutedGlyph: WaxIcons.volumeMuted,
      trackWidth: 220,
      // Centred under a centred transport: without the counterweight
      // the row's midpoint sits half a glyph box right of the track's,
      // which is the level looking shifted on the full-screen face.
      balanced: true,
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
      label: timer.active
          ? context.l10n.playerSleepTimerLeft(timer.label)
          : context.l10n.playerSleepTimer,
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
    final l10n = context.l10n;
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
              WaxOptionRow(
                key: const Key(SemanticsIds.sleepTimerExtend),
                semanticsId: SemanticsIds.sleepTimerExtend,
                glyph: WaxIcons.add,
                title: l10n.playerExtendTimer,
                subtitle: l10n.playerTimerLeft(timer.label),
                onTap: () {
                  ref.read(sleepTimerProvider.notifier).extend();
                  Navigator.of(context).pop();
                },
              ),
              WaxOptionRow(
                key: const Key(SemanticsIds.sleepTimerCancel),
                semanticsId: SemanticsIds.sleepTimerCancel,
                glyph: WaxIcons.close,
                title: l10n.playerCancelTimer,
                onTap: () {
                  ref.read(sleepTimerProvider.notifier).cancel();
                  Navigator.of(context).pop();
                },
              ),
              const Divider(height: WaxSpace.s16),
            ],
            for (final minutes in const [5, 15, 30, 60])
              WaxOptionRow(
                key: ValueKey(SemanticsIds.sleepTimer(minutes)),
                semanticsId: SemanticsIds.sleepTimer(minutes),
                glyph: WaxIcons.sleepTimer,
                title: l10n.playerTimerMinutes(minutes),
                onTap: () => _startMinutes(minutes),
              ),
            if (chapterEndMs != null)
              WaxOptionRow(
                key: const Key(SemanticsIds.sleepTimerChapter),
                semanticsId: SemanticsIds.sleepTimerChapter,
                glyph: WaxIcons.audiobooks,
                title: l10n.playerTimerChapterEnd,
                onTap: () {
                  ref
                      .read(sleepTimerProvider.notifier)
                      .startEndOfChapter(chapterEndMs);
                  Navigator.of(context).pop();
                },
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s16),
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
                        decoration: InputDecoration(
                          labelText: l10n.playerTimerCustom,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: WaxSpace.s8),
                  Semantics(
                    identifier: SemanticsIds.sleepTimerCustomStart,
                    label: l10n.playerTimerCustomStart,
                    button: true,
                    child: TextButton(
                      key: const Key(SemanticsIds.sleepTimerCustomStart),
                      onPressed: () {
                        final minutes = int.tryParse(_custom.text.trim());
                        if (minutes != null && minutes > 0) {
                          _startMinutes(minutes);
                        }
                      },
                      child: Text(l10n.playerStart),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: WaxSpace.s8),
          ],
        ),
      ),
    );
  }
}
