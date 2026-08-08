import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../library/item_delete.dart';
import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/side_panel.dart';
import 'now_playing_view.dart';
import 'playback_session.dart';

/// One item's words, in the shape the design system draws them.
///
/// The mapping happens here rather than in the widget, and that is not
/// tidiness: [LyricsView] resets a reader's scroll when it is handed a
/// different list, which is how a new track puts the highlight back at
/// the top. A widget that mapped the wire model inline would build a new
/// list on every rebuild, so every parent rebuild would look like a new
/// track and drag a reader who had scrolled away back to the playhead.
/// A provider's resolved value is one instance until the read changes.
@immutable
class TrackLyrics {
  const TrackLyrics({required this.lines, this.text});

  /// Timed lines, ordered.
  final List<LyricLine> lines;

  /// The untimed block, when there are no [lines].
  final String? text;

  /// Whether these can follow the playhead.
  bool get isSynced => lines.isNotEmpty;
}

/// One item's words, or null when it has none.
///
/// Null is the ordinary answer, not a failure: most tracks in most
/// libraries have no lyrics stored, and the repository reports that as an
/// absence rather than as a 404 for every caller to translate. A stored
/// record with nothing in it answers null too - the contract promises at
/// least one of the two is non-empty, and a client that trusted that
/// would draw an empty column under a header instead of saying there is
/// nothing to show.
///
/// Auto-disposing per pid, like the waveform beside it: a listener holds
/// one track's words at a time, and a verse a kilobyte long per track
/// played this session is memory nobody asked to spend.
final lyricsProvider = FutureProvider.autoDispose.family<TrackLyrics?, String>((
  ref,
  pid,
) async {
  final lyrics = await ref.watch(repositoryProvider).getItemLyrics(pid);
  if (lyrics == null) return null;
  final lines = <LyricLine>[
    for (final line in lyrics.synced)
      LyricLine(
        at: Duration(milliseconds: line.timeMs),
        text: line.text,
      ),
  ];
  final text = lyrics.unsynced;
  if (lines.isEmpty && (text == null || text.trim().isEmpty)) return null;
  return TrackLyrics(lines: lines, text: text);
});

/// The words for what is playing, in whatever shape they arrived in.
///
/// A surface rather than a screen: the panel beside the content and the
/// sheet over a phone draw the same thing, because they are the same
/// answer at two widths.
class LyricsSurface extends ConsumerWidget {
  const LyricsSurface({
    required this.session,
    required this.item,
    required this.position,
    super.key,
  });

  final PlaybackSession session;
  final ItemSummary item;
  final ValueListenable<Duration> position;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(lyricsProvider(item.pid));
    return words.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorState(
        title: 'Could not load the lyrics',
        message: error is WaxDeckApiException
            ? error.message
            : 'Something went wrong reading them.',
        onRetry: () => ref.invalidate(lyricsProvider(item.pid)),
        semanticsId: SemanticsIds.lyricsSurface,
      ),
      data: (lyrics) {
        if (lyrics == null) return _Absent(pid: item.pid);
        return LyricsView(
          position: position,
          lines: lyrics.lines,
          text: lyrics.text,
          // Only timed lines can be aimed at. An untimed block is a page
          // of text, and a tap on a paragraph that jumped playback
          // somewhere would be a guess wearing a control's clothes.
          onSeek: lyrics.isSynced ? (at) => unawaited(session.seek(at)) : null,
          semanticsId: SemanticsIds.lyricsSurface,
          lineSemanticsId: SemanticsIds.lyricsLine,
          followSemanticsId: SemanticsIds.lyricsFollow,
        );
      },
    );
  }
}

/// No words for this track.
///
/// A quiet state with a door for the person who can do something about
/// it, and nothing at all for everybody else: the metadata editor is
/// where lyrics are set, and offering it to an account the server would
/// refuse is an invitation to a locked room.
class _Absent extends ConsumerWidget {
  const _Absent({required this.pid});

  final String pid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admin = canDeleteItems(ref);
    return EmptyState(
      glyph: WaxIcons.lyrics,
      title: 'No lyrics for this track',
      message: admin
          ? 'Nothing was found in a sidecar or in the file tags. You can '
                'add them in the metadata editor.'
          : 'Nothing was found in a sidecar or in the file tags.',
      actionLabel: admin ? 'Add lyrics' : null,
      actionSemanticsId: admin ? SemanticsIds.lyricsAdd : null,
      onAction: admin ? () => _openEditor(context, pid) : null,
      semanticsId: SemanticsIds.lyricsSurface,
    );
  }
}

/// Leaves for the editor, taking the sheet with it where there is one.
///
/// A sheet left standing over a pushed screen is what back lands on, and
/// what it lands on is the words for a track the listener has left. Every
/// other sheet in the app pops before it pushes.
void _openEditor(BuildContext context, String pid) {
  final router = GoRouter.of(context);
  // Which navigator this surface sits in decides the verb, and it has to
  // be read before anything is popped.
  //
  // On the root navigator the thing underneath is the player, an overlay
  // there, while `/metadata/:pid` lives inside the shell: pushing one
  // over the other builds a second shell beside the mounted one and
  // trips the navigator's key reservation, losing the navigation and the
  // surface that asked for it. `go` is the way out of that, and the
  // routing rule already wanted it for a location a stranger can open.
  //
  // On the shell's own navigator - the side panel, or a sheet raised
  // over a compact page - `push` both works and is the better answer:
  // it leaves the album underneath for the way back, where `go` would
  // reset the branch and hand the editor's own exit nothing to pop.
  final overRoot =
      Navigator.of(context) == Navigator.of(context, rootNavigator: true);
  // Only when this surface *is* the overlay. The same empty state is
  // drawn in the shell's panel, where the enclosing route is the page
  // underneath and popping it would take a screen the listener is still
  // on. A sheet is a `PopupRoute`; a page is not.
  if (ModalRoute.of(context) is PopupRoute) Navigator.of(context).pop();
  if (overRoot) {
    router.go(WaxRoute.metadata(pid));
  } else {
    router.push(WaxRoute.metadata(pid));
  }
}

/// The lyrics in the shell's right panel.
class LyricsPanel extends ConsumerWidget {
  const LyricsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return WaxSidePanel(
      title: WaxPanel.lyrics.title,
      semanticsId: SemanticsIds.panel,
      closeSemanticsId: SemanticsIds.panelClose,
      onClose: ref.read(sidePanelProvider.notifier).close,
      child: NowPlayingView(
        idle: (context) => const EmptyState(
          glyph: WaxIcons.lyrics,
          title: 'Nothing is playing',
          message: 'Words show up here once something is.',
          semanticsId: SemanticsIds.lyricsSurface,
        ),
        builder: (context, session, item, position) =>
            LyricsSurface(session: session, item: item, position: position),
      ),
    );
  }
}

/// Opens the lyrics wherever this caller keeps them.
///
/// The panel beside the content where there is room for one and
/// something to put it beside, an overlay otherwise (5.6). [overShell]
/// is the second half of that condition and the player is why it exists:
/// `/now-playing` is a route pushed over the shell, so it covers the
/// panel slot, and a control that lit up while the panel opened behind
/// the surface holding it would do nothing anybody could see.
///
/// The sheet finds what is playing for itself rather than being handed
/// it. A queue that advances while the sheet is open keeps the same
/// player State, so a captured session is the previous track's: the
/// words on screen would be one item's and the highlight the next one's,
/// and a tap would seek a session that had already let go.
void openLyrics(BuildContext context, WidgetRef ref, {bool overShell = false}) {
  if (!overShell && WaxSizeClass.of(context).hasSidebar) {
    ref.read(sidePanelProvider.notifier).toggle(WaxPanel.lyrics);
    return;
  }
  unawaited(
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Nearly the whole window: a verse read four lines at a time is
      // a lyric sheet posted through a letterbox.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (_) => const _LyricsSheet(),
    ),
  );
}

class _LyricsSheet extends StatelessWidget {
  const _LyricsSheet();

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WaxSpace.s16,
              WaxSpace.s12,
              WaxSpace.s8,
              WaxSpace.s8,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    WaxPanel.lyrics.title,
                    style: WaxType.headline.copyWith(color: colors.textPrimary),
                  ),
                ),
                WaxIconButton(
                  glyph: WaxIcons.close,
                  label: 'Close lyrics',
                  size: 18,
                  onPressed: () => Navigator.of(context).pop(),
                  semanticsId: SemanticsIds.panelClose,
                ),
              ],
            ),
          ),
          Expanded(
            child: NowPlayingView(
              idle: (context) => const EmptyState(
                glyph: WaxIcons.lyrics,
                title: 'Nothing is playing',
                message: 'Words show up here once something is.',
                semanticsId: SemanticsIds.lyricsSurface,
              ),
              builder: (context, session, item, position) => LyricsSurface(
                session: session,
                item: item,
                position: position,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
