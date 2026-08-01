import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
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
import '../queue/queue_controller.dart';
import '../queue/queue_item.dart';
import '../queue/queue_state.dart';
import '../queue/queue_view.dart';
import '../sharing/share_dialog.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'deck_bar_host.dart';
import 'download_action.dart';
import 'item_star_rating_row.dart';
import 'now_playing_controller.dart';
import 'output_volume.dart';
import 'playback_session.dart';
import 'sleep_timer.dart';
import 'waveform.dart';

/// Speed presets the player button cycles through.
const playerSpeedSteps = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];

/// The next speed after [current] in the preset cycle.
double nextPlayerSpeed(double current) {
  for (final step in playerSpeedSteps) {
    if (step > current + 0.001) return step;
  }
  return playerSpeedSteps.first;
}

String formatPlayerSpeed(double speed) {
  var text = speed.toStringAsFixed(2);
  while (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return '${text}x';
}

/// The verbs behind the player's one overflow menu.
enum _PlayerMenuAction { addToPlaylist, share, delete }

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

/// The full player: one scaffold, configured by what is playing.
///
/// A viewer, deliberately: nothing here starts, stops, or outlives
/// playback, so leaving this screen keeps the music on. The session and
/// the queue own the state; this draws it and sends verbs back.
///
/// The music face is whole here. Podcasts, books, and radio get the
/// scaffold and the controls they had before it - speed, silence
/// trimming, the sleep timer, chapters - which is deliberately less than
/// 5.3 asks of them: the speed sheet, smart rewind, bookmarks, and the
/// chapter and transcript regions are P19's, and their controls are
/// hosted through the same slots meanwhile rather than left on a screen
/// of their own.
class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A Scaffold with nothing in it but the body, for the thing a
    // Scaffold does that no other widget does: it is what
    // `ScaffoldMessenger` presents into. The player is a route of its
    // own over the shell, so the chrome's Scaffold is not an ancestor,
    // and every refusal raised from here - a star that would not stick,
    // a routed command an endpoint declined, a delete the server
    // refused - asserts without one. The backdrop underneath paints the
    // canvas, hence transparent.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _body(context, ref),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref) {
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
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s8),
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
          trailingHeaderActions: _headerActions(context, canDelete: canDelete),
          titleTrailing: ItemStarRatingRow(pid: _item.pid),
          seek: _Seek(
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
          actionRow: _actionRow(context),
          bottomRegion: _music ? const _UpNextPeek() : null,
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
  List<Widget> _headerActions(BuildContext context, {required bool canDelete}) {
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
        }),
      ),
    ];
  }

  /// The per-medium verbs.
  ///
  /// Music gets the queue and the discovery menu 5.3 calls "More like
  /// this"; spoken word keeps the speed, silence-trim, sleep-timer, and
  /// chapter controls it has always had, which P19 replaces with the
  /// faces they belong to.
  Widget _actionRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (_music) ...<Widget>[
          WaxIconButton(
            glyph: WaxIcons.queue,
            label: 'Queue',
            semanticsId: SemanticsIds.playerQueue,
            onPressed: () => openQueue(context, ref),
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
        ] else ...<Widget>[
          _SpeedButton(session: _session),
          _TrimChip(session: _session),
          if (_item.mediaType == MediaType.audiobook)
            _ChapterButton(session: _session, position: _position),
        ],
        // Every face, not only the spoken-word ones 5.3 lists it under:
        // falling asleep to a record is what the control is for, and it
        // is about the device rather than the medium.
        _SleepTimerButton(session: _session),
      ],
    );
  }
}

/// Which chapter is playing, and the way to any other one.
///
/// A button and a sheet, which is what the book face had before the
/// scaffold and less than 5.3 asks for: the chapter list belongs in the
/// bottom region beside the book-versus-chapter timeline toggle, and
/// that is the book face P19 builds.
class _ChapterButton extends StatelessWidget {
  const _ChapterButton({required this.session, required this.position});

  final PlaybackSession session;
  final ValueListenable<Duration> position;

  static ChapterMark? chapterAt(BookDetail book, Duration position) {
    final positionMs = position.inMilliseconds;
    ChapterMark? current;
    for (final chapter in book.chapters) {
      if (chapter.startMs <= positionMs) current = chapter;
    }
    return current ?? (book.chapters.isEmpty ? null : book.chapters.first);
  }

  static String chapterTitle(ChapterMark? chapter) =>
      chapter?.title ?? (chapter == null ? '' : 'Chapter ${chapter.index + 1}');

  @override
  Widget build(BuildContext context) {
    final book = session.book;
    if (book == null || book.chapters.isEmpty) return const SizedBox.shrink();
    return ValueListenableBuilder<Duration>(
      valueListenable: position,
      builder: (context, at, _) => WaxIconButton(
        glyph: WaxIcons.audiobooks,
        label: 'Chapters, current: ${chapterTitle(chapterAt(book, at))}',
        semanticsId: SemanticsIds.playerChapters,
        onPressed: () => unawaited(
          showModalBottomSheet<void>(
            context: context,
            builder: (_) => _ChapterSheet(session: session, book: book),
          ),
        ),
      ),
    );
  }
}

class _ChapterSheet extends StatelessWidget {
  const _ChapterSheet({required this.session, required this.book});

  final PlaybackSession session;
  final BookDetail book;

  @override
  Widget build(BuildContext context) {
    String stamp(int ms) {
      final d = Duration(milliseconds: ms);
      final h = d.inHours;
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return h > 0 ? '$h:$m:$s' : '$m:$s';
    }

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final chapter in book.chapters)
            Semantics(
              identifier: SemanticsIds.playerChapter(chapter.index),
              button: true,
              child: ListTile(
                key: ValueKey(SemanticsIds.playerChapter(chapter.index)),
                dense: true,
                leading: Text(stamp(chapter.startMs)),
                title: Text(chapter.title ?? 'Chapter ${chapter.index + 1}'),
                onTap: () {
                  unawaited(
                    session.seek(Duration(milliseconds: chapter.startMs)),
                  );
                  Navigator.of(context).pop();
                },
              ),
            ),
        ],
      ),
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
      onPressed: () => openQueue(context, ref),
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
          onTap: () => openQueue(context, ref),
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

/// Cycles the playback speed through the presets, persisting the choice
/// per show or book (music stays at whatever it is set to for the
/// session and never persists).
///
/// The cycle is what P19 replaces with the speed sheet 5.3 specifies:
/// one tap should reach every speed rather than walking to it.
class _SpeedButton extends StatelessWidget {
  const _SpeedButton({required this.session});

  final PlaybackSession session;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return StreamBuilder<double>(
      stream: session.engine.speedStream,
      initialData: session.engine.speed,
      builder: (context, snapshot) {
        final speed = snapshot.data ?? 1.0;
        return WaxTappable(
          semanticsId: SemanticsIds.playerSpeed,
          label: 'Playback speed ${formatPlayerSpeed(speed)}',
          borderRadius: WaxRadius.pill,
          onPressed: () => session.setSpeed(nextPlayerSpeed(speed)),
          // WaxTappable adds semantics, focus, and a ring, and no
          // gesture of its own, so the chip carries the tap. Ink rather
          // than a decorated Container, or the splash paints under an
          // opaque fill and the press has no feedback at all.
          child: Ink(
            decoration: BoxDecoration(
              color: colors.surface2,
              borderRadius: WaxRadius.pill,
              border: Border.all(color: colors.hairline),
            ),
            child: InkWell(
              borderRadius: WaxRadius.pill,
              onTap: () => session.setSpeed(nextPlayerSpeed(speed)),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WaxSpace.s12,
                  vertical: WaxSpace.s8,
                ),
                child: Text(
                  formatPlayerSpeed(speed),
                  style: WaxType.monoData.copyWith(color: colors.textPrimary),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Silence-trimming toggle with the time-saved badge.
///
/// The label says "silence trimming" and not "time saved" on purpose:
/// the client counts trim jumps only, and the seek-aware accounting that
/// would make the larger claim true is P20's.
class _TrimChip extends StatelessWidget {
  const _TrimChip({required this.session});

  final PlaybackSession session;

  static String savedLabel(int savedMs) {
    final d = Duration(milliseconds: savedMs);
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    if (m > 0) return 'saved ${m}m ${s}s';
    return 'saved ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: session.trimEnabled,
      builder: (context, enabled, _) {
        return ValueListenableBuilder<int>(
          valueListenable: session.hoursSavedMs,
          builder: (context, savedMs, _) {
            final label = savedMs > 0
                ? 'Trim silence (${savedLabel(savedMs)})'
                : 'Trim silence';
            // A chip with its readout drawn rather than an icon with the
            // readout only spoken: what the session has saved is the
            // reason to leave the toggle on, and a glyph says none of it.
            return WaxTappable(
              semanticsId: SemanticsIds.playerTrim,
              label: label,
              selected: enabled,
              borderRadius: WaxRadius.pill,
              onPressed: () => session.setTrimEnabled(!enabled),
              child: Ink(
                decoration: BoxDecoration(
                  color: enabled ? colors.accentContainer : colors.surface2,
                  borderRadius: WaxRadius.pill,
                  border: Border.all(
                    color: enabled ? colors.accent : colors.hairline,
                  ),
                ),
                child: InkWell(
                  borderRadius: WaxRadius.pill,
                  onTap: () => session.setTrimEnabled(!enabled),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: WaxSpace.s12,
                      vertical: WaxSpace.s8,
                    ),
                    child: Text(
                      label,
                      style: WaxType.caption.copyWith(
                        color: enabled
                            ? colors.onAccentContainer
                            : colors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Sleep timer button plus its options sheet. When a timer runs, the
/// remaining time shows as a badge on the button.
class _SleepTimerButton extends ConsumerWidget {
  const _SleepTimerButton({required this.session});

  final PlaybackSession session;

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

  final PlaybackSession session;

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
    final book = widget.session.book;
    if (book == null || book.chapters.isEmpty) return null;
    final positionMs = widget.session.displayPosition.inMilliseconds;
    ChapterMark current = book.chapters.first;
    ChapterMark? next;
    for (var i = 0; i < book.chapters.length; i++) {
      if (book.chapters[i].startMs <= positionMs) {
        current = book.chapters[i];
        next = i + 1 < book.chapters.length ? book.chapters[i + 1] : null;
      }
    }
    return current.endMs ?? next?.startMs ?? book.durationMs;
  }

  void _startMinutes(int minutes) {
    ref.read(sleepTimerProvider.notifier).startMinutes(minutes);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(sleepTimerProvider).active;
    final chapterEndMs = widget.session.item.mediaType == MediaType.audiobook
        ? _currentChapterEndMs()
        : null;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            if (active)
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
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
