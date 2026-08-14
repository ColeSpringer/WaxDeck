import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../home/pin_action.dart';
import '../media_view.dart';
import '../player/now_playing_controller.dart';
import '../providers.dart';
import '../queue/queue_state.dart';
import '../search/search_chrome.dart';
import '../sharing/share_dialog.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../uploads/file_picker_port.dart';
import 'playlist_create.dart';
import 'playlists_controller.dart';
import 'rule_vocabulary.dart';

/// What the playlist overflow can do. The synced-playlist feature adds
/// its settings sheet here, beside the cover verbs.
enum _PlaylistAction {
  pin,
  rename,
  visibility,
  shareLink,
  setCover,
  resetCover,
  exportM3u,
  exportPortable,
  delete,
}

/// One playlist: what it is, what is in it, and what its owner may do
/// to it. Manual lists reorder and remove; smart lists show their rules
/// and a membership nobody edits by hand.
class PlaylistScreen extends ConsumerStatefulWidget {
  const PlaylistScreen({required this.pid, super.key});

  final String pid;

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  /// What the server said when it refused a replace, or null.
  ///
  /// Its sentence, not ours: `conflict` covers three different refusals
  /// and only the server knows which. Widget state because it is about
  /// the drag this screen just made.
  String? _conflict;

  String get pid => widget.pid;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(playlistDetailProvider(pid));
    final view = detail.value;

    return WaxScaffold(
      title: view?.playlist.name ?? 'Playlist',
      largeTitle: false,
      // Pops where something pushed this, goes to the listing where
      // nothing did.
      onBack: () => context.leave(fallback: WaxRoute.playlists),
      actions: <Widget>[
        if (view != null) _Overflow(view: view),
        const SearchAction(),
      ],
      slivers: <Widget>[
        // A permanent slot: a sliver appearing at the head of the list
        // shifts every one after it, rebuilding the add row and losing
        // whatever was typed in it.
        SliverToBoxAdapter(
          child: _conflict == null
              ? const SizedBox.shrink()
              : WaxBanner(
                  message:
                      '$_conflict Nothing was changed; this is the list '
                      'as it stands.',
                  tone: WaxBannerTone.caution,
                  semanticsId: SemanticsIds.playlistConflict,
                  onDismiss: () => setState(() => _conflict = null),
                ),
        ),
        switch (detail) {
          AsyncData(:final value) => SliverMainAxisGroup(
            slivers: _body(context, value),
          ),
          AsyncError(:final error) => SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(
              title: 'Could not load this playlist',
              message: error is WaxDeckApiException
                  ? error.message
                  : 'The server did not answer.',
              onRetry: () => ref.invalidate(playlistDetailProvider(pid)),
            ),
          ),
          _ => const SliverFillRemaining(
            hasScrollBody: false,
            child: SkeletonShapes(shape: SkeletonShape.detail),
          ),
        },
        const SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s32)),
      ],
    );
  }

  List<Widget> _body(BuildContext context, PlaylistView view) {
    final playlist = view.playlist;
    final entries = view.entries;
    return <Widget>[
      SliverToBoxAdapter(child: _Header(view: view)),
      SliverToBoxAdapter(child: _StatusChips(view: view)),
      if (view.isEditable) SliverToBoxAdapter(child: _AddRow(pid: pid)),
      if (entries.isEmpty)
        SliverToBoxAdapter(
          child: EmptyState(
            title: playlist.isSmart ? 'Nothing matches yet' : 'Nothing in here',
            message: playlist.isSmart
                ? 'No item in the library answers these rules. Loosen one '
                      'and the list fills itself.'
                : view.isEditable
                ? 'Search above to add the first track, or use "Add to '
                      'playlist" from anywhere something is playing.'
                : 'The owner has not put anything in this list yet.',
            glyph: WaxIcons.playlists,
          ),
        )
      else if (view.isEditable)
        _ReorderableEntries(
          pid: pid,
          view: view,
          onConflict: (message) => setState(() => _conflict = message),
        )
      else
        _FixedEntries(view: view),
    ];
  }
}

/// Cover, what the list is, and the verbs.
class _Header extends ConsumerWidget {
  const _Header({required this.view});

  final PlaylistView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = view.playlist;
    final entries = view.entries;
    void play({bool shuffle = false}) {
      if (entries.isEmpty) return;
      ref
          .read(nowPlayingProvider.notifier)
          .play(
            <ItemSummary>[for (final entry in entries) entry.item],
            shuffle: shuffle,
            source: QueueSource(
              kind: QueueSourceKind.playlist,
              label: playlist.name,
              pid: playlist.pid,
            ),
          );
      context.push(WaxRoute.nowPlaying);
    }

    return EntityHeader(
      title: playlist.name,
      subtitle: playlistOwnerLine(playlist),
      metadata: _facts(context.waxL10n, view),
      artwork: waxArtwork(ref.watch(artworkStoreProvider), playlist.artUrl),
      actions: <Widget>[
        WaxButton(
          label: 'Play',
          icon: WaxIcons.play,
          onPressed: entries.isEmpty ? null : play,
          semanticsId: SemanticsIds.entityPlay,
        ),
        WaxButton(
          label: 'Shuffle',
          kind: WaxButtonKind.tonal,
          icon: WaxIcons.shuffle,
          onPressed: entries.isEmpty ? null : () => play(shuffle: true),
          semanticsId: SemanticsIds.entityShuffle,
        ),
      ],
    );
  }

  /// "Smart playlist · 42 items · 2 hr 41 min".
  static String _facts(WaxLocalizations l10n, PlaylistView view) {
    final entries = view.entries;
    final parts = <String>[
      view.playlist.isSmart ? 'Smart playlist' : 'Manual playlist',
      entries.length == 1 ? '1 item' : '${entries.length} items',
      if (view.duration > Duration.zero) l10n.formatSpan(view.duration),
    ];
    return parts.join(' · ');
  }
}

/// Whose list this is, as the header's second line.
String? playlistOwnerLine(Playlist playlist) {
  if (!playlist.isOwner) return 'Shared by ${playlist.ownerName}';
  return playlist.isShared ? 'Shared with everyone' : null;
}

/// How this list is kept: a smart list's rules, and nothing for a
/// manual one. A synced list's status chip lands here too.
class _StatusChips extends ConsumerWidget {
  const _StatusChips({required this.view});

  final PlaylistView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rule = view.playlist.rule;
    if (rule == null) return const SizedBox.shrink();
    final colors = WaxColors.of(context);
    final sizeClass = WaxSizeClass.of(context);
    // A rule naming another playlist reads as that list's name; the
    // provider is already loaded here, and a pid the caller cannot
    // resolve falls back to itself.
    final known = ref.watch(playlistsProvider).value ?? const <Playlist>[];
    final chips = describeRule(
      rule,
      playlistName: (pid) {
        for (final pl in known) {
          if (pl.pid == pid) return pl.name;
        }
        return null;
      },
    );
    final editable = view.playlist.isOwner;
    final summary = Wrap(
      spacing: WaxSpace.s8,
      runSpacing: WaxSpace.s8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (final chip in chips) CodecChip(chip),
        if (editable)
          WaxButton(
            label: 'Edit rules',
            kind: WaxButtonKind.text,
            icon: WaxIcons.edit,
            semanticsId: SemanticsIds.playlistEditRule,
            onPressed: () => unawaited(_editRule(context, view)),
          ),
      ],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        sizeClass.gutter.horizontal / 2,
        WaxSpace.s16,
        sizeClass.gutter.horizontal / 2,
        WaxSpace.s8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            identifier: SemanticsIds.playlistRuleSummary,
            container: true,
            explicitChildNodes: true,
            label: 'Rules: ${chips.join(', ')}',
            child: summary,
          ),
          const SizedBox(height: WaxSpace.s8),
          Text(
            'Evaluated live, every time this list is opened.',
            style: WaxType.caption.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// Opens the rule editor on this playlist.
Future<void> _editRule(BuildContext context, PlaylistView view) async {
  final router = GoRouter.of(context);
  await router.push<Playlist>(
    WaxRoute.playlistEdit(view.playlist.pid),
    extra: view.playlist,
  );
}

/// Search the library, tap a hit, it lands at the end of the list.
/// Its own search because leaving and coming back is the trip this row
/// exists to avoid.
class _AddRow extends ConsumerStatefulWidget {
  const _AddRow({required this.pid});

  final String pid;

  @override
  ConsumerState<_AddRow> createState() => _AddRowState();
}

class _AddRowState extends ConsumerState<_AddRow> {
  final _controller = TextEditingController();
  Timer? _debounce;
  var _generation = 0;
  List<SearchHit> _hits = const <SearchHit>[];
  var _busy = false;

  /// The query [_hits] answers, or null while one is being typed or
  /// waited for. An empty list means two things and only "asked and
  /// found nothing" is worth reporting.
  String? _answered;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    // Bumped on every keystroke, not just when one is scheduled: a
    // request already in flight would otherwise land and put its
    // results back under a field that has since been cleared.
    _generation++;
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      setState(() {
        _hits = const <SearchHit>[];
        _answered = null;
      });
      return;
    }
    setState(() => _answered = null);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final generation = _generation;
      try {
        final results = await ref
            .read(repositoryProvider)
            .search(trimmed, limit: 8);
        if (!mounted || generation != _generation) return;
        // Tracks, books, and episodes: an artist or an album is a
        // heading, not a member the endpoint would accept.
        setState(() {
          _hits = <SearchHit>[
            ...results.tracks,
            ...results.books,
            ...results.episodes,
          ];
          _answered = trimmed;
        });
      } on WaxDeckApiException {
        // A failed search is not an empty library, so it says nothing
        // rather than reporting no matches.
        if (mounted && generation == _generation) {
          setState(() {
            _hits = const <SearchHit>[];
            _answered = null;
          });
        }
      }
    });
  }

  Future<void> _add(SearchHit hit) async {
    if (_busy) return;
    _debounce?.cancel();
    _generation++;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(playlistDetailProvider(widget.pid).notifier).append(
        <String>[hit.pid],
      );
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _hits = const <SearchHit>[];
        _answered = null;
      });
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Added "${hit.title}"')));
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final sizeClass = WaxSizeClass.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        sizeClass.gutter.horizontal / 2,
        WaxSpace.s16,
        sizeClass.gutter.horizontal / 2,
        WaxSpace.s8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          WaxTextField(
            label: 'Add to this playlist',
            hint: 'Search the library',
            glyph: WaxIcons.add,
            controller: _controller,
            onChanged: _onChanged,
            semanticsId: SemanticsIds.playlistAddField,
          ),
          // Says so rather than looking like it is still thinking. A
          // query matching only an artist or album lands here too.
          if (_answered != null && _hits.isEmpty)
            Padding(
              padding: const EdgeInsets.only(
                left: WaxSpace.s12,
                top: WaxSpace.s8,
              ),
              child: Text(
                'Nothing here to add. Artists and albums are not members '
                'of a playlist; their tracks are.',
                style: WaxType.caption.copyWith(color: colors.textTertiary),
              ),
            ),
          for (var i = 0; i < _hits.length; i++)
            WaxOptionRow(
              title: _hits[i].title,
              subtitle: _hits[i].subtitle,
              glyph: WaxIcons.music,
              semanticsId: SemanticsIds.playlistAddResult(i),
              onTap: _busy ? null : () => unawaited(_add(_hits[i])),
            ),
        ],
      ),
    );
  }
}

/// A manual list: drag to reorder, swipe or tap to remove.
class _ReorderableEntries extends ConsumerWidget {
  const _ReorderableEntries({
    required this.pid,
    required this.view,
    required this.onConflict,
  });

  final String pid;
  final PlaylistView view;

  /// Called with the server's refusal, so the screen can say it.
  final ValueChanged<String> onConflict;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final entries = view.entries;
    return SliverLayoutBuilder(
      builder: (context, constraints) => SliverReorderableList(
        itemCount: entries.length,
        // The proxy is built into an overlay: unbounded cross-axis and
        // no Material, so an Expanded row would stretch to infinity.
        proxyDecorator: (child, index, animation) => Material(
          color: colors.surface2,
          child: SizedBox(width: constraints.crossAxisExtent, child: child),
        ),
        // onReorderItem hands over the destination already adjusted for
        // the removal, unlike the retired onReorder.
        onReorderItem: (from, to) =>
            unawaited(_move(context, ref, from: from, to: to)),
        itemBuilder: (context, index) => _Dismissable(
          // The stored position rather than the row index, and the pid
          // beside it: a playlist may hold the same track twice, so
          // neither is unique on its own.
          key: ValueKey<String>(_rowId(entries[index], index)),
          rowId: _rowId(entries[index], index),
          onRemove: () => unawaited(_remove(context, ref, index)),
          child: Semantics(
            // SliverReorderableList carries none of the move actions
            // ReorderableListView adds itself, so the row declares them:
            // a drag is not a path for everyone.
            customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
              if (index > 0)
                const CustomSemanticsAction(label: 'Move up'): () =>
                    unawaited(_move(context, ref, from: index, to: index - 1)),
              if (index < entries.length - 1)
                const CustomSemanticsAction(label: 'Move down'): () =>
                    unawaited(_move(context, ref, from: index, to: index + 1)),
            },
            child: _EntryRow(
              view: view,
              index: index,
              onTap: () => _openEntry(context, ref, view, index),
              onRemove: () => unawaited(_remove(context, ref, index)),
              handle: ReorderableDragStartListener(
                index: index,
                child: Semantics(
                  identifier: SemanticsIds.playlistEntryDrag(index),
                  label: 'Drag to reorder',
                  child: Padding(
                    padding: const EdgeInsets.all(WaxSpace.s8),
                    child: WaxIcon(
                      WaxIcons.sort,
                      size: 16,
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// This row's identity, for the keys the reorder and the swipe need.
  static String _rowId(PlaylistEntry entry, int index) =>
      '${entry.position ?? index}-${entry.item.pid}';

  Future<void> _move(
    BuildContext context,
    WidgetRef ref, {
    required int from,
    required int to,
  }) async {
    final pids = <String>[for (final e in view.entries) e.item.pid];
    if (from < 0 || from >= pids.length || to < 0 || to >= pids.length) return;
    final moved = pids.removeAt(from);
    pids.insert(to, moved);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(playlistDetailProvider(pid).notifier).reorder(pids);
    } on WaxDeckApiException catch (e) {
      // The list already animated, so it goes back either way. A lost
      // race gets the banner; anything else is a one-off failure.
      ref.invalidate(playlistDetailProvider(pid));
      if (e.code == 'conflict') {
        onConflict(e.message);
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, int index) async {
    // The stored position, never the row index: visibility filtering
    // leaves a viewer's rows non-contiguous.
    final position = view.entries[index].position;
    if (position == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(playlistDetailProvider(pid).notifier).removeAt(position);
    } on WaxDeckApiException catch (e) {
      ref.invalidate(playlistDetailProvider(pid));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// A smart list, or somebody else's: the members, and nothing to drag.
class _FixedEntries extends ConsumerWidget {
  const _FixedEntries({required this.view});

  final PlaylistView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SliverList.builder(
    itemCount: view.entries.length,
    itemBuilder: (context, index) => _EntryRow(
      view: view,
      index: index,
      onTap: () => _openEntry(context, ref, view, index),
    ),
  );
}

/// One member, however the list draws it.
class _EntryRow extends ConsumerWidget {
  const _EntryRow({
    required this.view,
    required this.index,
    required this.onTap,
    this.onRemove,
    this.handle,
  });

  final PlaylistView view;
  final int index;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  /// The drag affordance, on the lists that can be reordered.
  final Widget? handle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final item = view.entries[index].item;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: sizeClass.gutter.horizontal / 2,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: MediaListRow(
              data: MediaTileData(
                title: item.title,
                subtitle: item.artist,
                artwork: waxArtwork(
                  ref.watch(artworkStoreProvider),
                  item.artUrl,
                ),
                domain: waxDomainOf(item.mediaType),
                shape: waxShapeOf(item.mediaType),
                trailingText: item.durationMs > 0
                    ? formatTimecode(Duration(milliseconds: item.durationMs))
                    : null,
                semanticsId: SemanticsIds.playlistEntry(index),
              ),
              onTap: onTap,
            ),
          ),
          if (onRemove != null)
            WaxIconButton(
              glyph: WaxIcons.close,
              label: 'Remove from playlist',
              size: 16,
              onPressed: onRemove,
              semanticsId: SemanticsIds.playlistEntryRemove(index),
            ),
          ?handle,
        ],
      ),
    );
  }
}

/// Swipe to drop a member; the row's remove button does the same, which
/// is what keeps the list usable by keyboard and by screen reader.
class _Dismissable extends StatelessWidget {
  const _Dismissable({
    required this.rowId,
    required this.onRemove,
    required this.child,
    super.key,
  });

  /// The row's identity. Keyed separately from this widget: the
  /// reorderable list reads the outer key.
  final String rowId;

  final VoidCallback onRemove;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Dismissible(
      key: ValueKey<String>('dismiss-$rowId'),
      onDismissed: (_) => onRemove(),
      background: ColoredBox(
        color: colors.surface2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s16),
          child: Row(
            children: <Widget>[
              WaxIcon(WaxIcons.close, size: 16, color: colors.textTertiary),
              const Spacer(),
              WaxIcon(WaxIcons.close, size: 16, color: colors.textTertiary),
            ],
          ),
        ),
      ),
      child: child,
    );
  }
}

/// Opens what a row points at.
void _openEntry(
  BuildContext context,
  WidgetRef ref,
  PlaylistView view,
  int index,
) {
  final entries = view.entries;
  final item = entries[index].item;
  if (item.mediaType == MediaType.audiobook) {
    // Pushed: a book's declared parent is its own hub, so going there
    // would drop this playlist off the stack.
    context.push(WaxRoute.book(item.pid));
    return;
  }
  // Tapping a row plays from there and the rest of the list follows.
  ref
      .read(nowPlayingProvider.notifier)
      .play(
        <ItemSummary>[for (final entry in entries) entry.item],
        source: QueueSource(
          kind: QueueSourceKind.playlist,
          label: view.playlist.name,
          pid: view.playlist.pid,
        ),
        startIndex: index,
      );
  context.push(WaxRoute.nowPlaying);
}

/// Rename, visibility, covers, exports, and delete.
class _Overflow extends ConsumerWidget {
  const _Overflow({required this.view});

  final PlaylistView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = view.playlist;
    final isOwner = playlist.isOwner;
    final hasPicker = ref.watch(filePickerProvider) != null;
    return WaxMenuButton<_PlaylistAction>(
      glyph: WaxIcons.more,
      label: 'More',
      semanticsId: SemanticsIds.playlistOverflow,
      items: <WaxMenuItem<_PlaylistAction>>[
        pinMenuItem<_PlaylistAction>(
          ref,
          playlist.pid,
          value: _PlaylistAction.pin,
          semanticsId: SemanticsIds.playlistPin,
        ),
        if (isOwner) ...<WaxMenuItem<_PlaylistAction>>[
          WaxMenuItem<_PlaylistAction>(
            value: _PlaylistAction.rename,
            label: 'Rename',
            glyph: WaxIcons.edit,
            semanticsId: SemanticsIds.playlistRename,
          ),
          WaxMenuItem<_PlaylistAction>(
            value: _PlaylistAction.visibility,
            label: playlist.isShared ? 'Make private' : 'Share with everyone',
            glyph: WaxIcons.share,
            semanticsId: SemanticsIds.playlistVisibility,
          ),
        ],
        WaxMenuItem<_PlaylistAction>(
          value: _PlaylistAction.shareLink,
          label: 'Share link',
          glyph: WaxIcons.share,
          semanticsId: SemanticsIds.playlistShareLink,
        ),
        // Hidden where the platform has no picker, which is the port
        // answering null.
        if (isOwner && hasPicker)
          WaxMenuItem<_PlaylistAction>(
            value: _PlaylistAction.setCover,
            label: 'Set cover',
            glyph: WaxIcons.albums,
            semanticsId: SemanticsIds.playlistSetCover,
          ),
        // Offered whenever a cover shows: the wire does not say whether
        // it was uploaded, and resetting a generated one rebuilds it.
        if (isOwner && playlist.artUrl != null)
          WaxMenuItem<_PlaylistAction>(
            value: _PlaylistAction.resetCover,
            label: 'Reset cover',
            glyph: WaxIcons.refresh,
            semanticsId: SemanticsIds.playlistResetCover,
          ),
        WaxMenuItem<_PlaylistAction>(
          value: _PlaylistAction.exportM3u,
          label: 'Export M3U',
          glyph: WaxIcons.downloads,
          semanticsId: SemanticsIds.playlistExportM3u,
        ),
        WaxMenuItem<_PlaylistAction>(
          value: _PlaylistAction.exportPortable,
          label: 'Export portable',
          glyph: WaxIcons.share,
          semanticsId: SemanticsIds.playlistExportPortable,
        ),
        if (isOwner)
          WaxMenuItem<_PlaylistAction>(
            value: _PlaylistAction.delete,
            label: 'Delete',
            glyph: WaxIcons.delete,
            destructive: true,
            semanticsId: SemanticsIds.playlistDelete,
          ),
      ],
      onSelected: (action) => unawaited(_run(context, ref, action)),
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    _PlaylistAction action,
  ) async {
    final pid = view.playlist.pid;
    switch (action) {
      case _PlaylistAction.pin:
        await togglePin(context, ref, pid, label: view.playlist.name);
      case _PlaylistAction.rename:
        await _rename(context, ref);
      case _PlaylistAction.visibility:
        await _setVisibility(context, ref);
      case _PlaylistAction.shareLink:
        await showShareLinkDialog(context, pid: pid);
      case _PlaylistAction.setCover:
        await _setCover(context, ref);
      case _PlaylistAction.resetCover:
        await _resetCover(context, ref);
      case _PlaylistAction.exportM3u:
        await _exportM3u(context, ref);
      case _PlaylistAction.exportPortable:
        await _exportPortable(context, ref);
      case _PlaylistAction.delete:
        await _delete(context, ref);
    }
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    // Captured before the prompt: reading one off this context after it
    // is a use across the gap.
    final messenger = ScaffoldMessenger.of(context);
    final name = await promptPlaylistName(
      context,
      title: 'Rename playlist',
      confirmLabel: 'Rename',
      initial: view.playlist.name,
    );
    if (name == null || name.isEmpty || name == view.playlist.name) return;
    await _guard(
      messenger,
      () => ref
          .read(playlistDetailProvider(view.playlist.pid).notifier)
          .edit(name: name),
    );
  }

  Future<void> _setVisibility(BuildContext context, WidgetRef ref) => _guard(
    ScaffoldMessenger.of(context),
    () => ref
        .read(playlistDetailProvider(view.playlist.pid).notifier)
        .edit(visibility: view.playlist.isShared ? 'private' : 'shared'),
  );

  /// Offers the playlist as M3U for copying: the web build has no
  /// file-save surface and the clipboard reaches every M3U player.
  Future<void> _exportM3u(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final String content;
    try {
      content = await ref
          .read(repositoryProvider)
          .exportPlaylistM3u(view.playlist.pid);
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export M3U'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: SelectableText(
              content,
              style: WaxType.monoData.copyWith(
                color: WaxColors.of(context).textPrimary,
              ),
            ),
          ),
        ),
        actions: <Widget>[
          WaxButton(
            label: 'Close',
            kind: WaxButtonKind.text,
            onPressed: () => Navigator.of(context).pop(),
          ),
          WaxButton(
            label: 'Copy',
            semanticsId: SemanticsIds.playlistExportCopy,
            onPressed: () async {
              final navigator = Navigator.of(context);
              await Clipboard.setData(ClipboardData(text: content));
              // Closes first: a snackbar renders on the scaffold behind
              // the modal, where nobody would see the confirmation.
              if (navigator.mounted) navigator.pop();
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(content: Text('Playlist copied as M3U')),
                );
            },
          ),
        ],
      ),
    );
  }

  /// Copies the portable refs, for importing on another server.
  Future<void> _exportPortable(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final PortablePlaylist portable;
    try {
      portable = await ref
          .read(repositoryProvider)
          .exportPlaylistPortable(view.playlist.pid);
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    await Clipboard.setData(ClipboardData(text: portableJson(portable)));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Portable playlist copied')));
  }

  /// What the picker offers; the server decides what it accepts.
  static const _coverExtensions = <String>{'jpg', 'jpeg', 'png', 'webp', 'gif'};

  /// Uploads a picked image as the cover. Read whole rather than
  /// streamed: covers are small and the server caps the body.
  Future<void> _setCover(BuildContext context, WidgetRef ref) async {
    final picker = ref.read(filePickerProvider);
    if (picker == null) return;
    final pid = view.playlist.pid;
    final messenger = ScaffoldMessenger.of(context);
    // Picking and reading are inside the guard: a permission error or a
    // file that vanished throws from the platform, not from the API.
    try {
      final file = await picker.pickFile(
        extensions: _coverExtensions,
        label: 'Cover image',
      );
      final openRead = file?.openRead;
      if (file == null || openRead == null) return;
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in openRead()) {
        bytes.add(chunk);
      }
      await ref
          .read(playlistDetailProvider(pid).notifier)
          .setCover(bytes.takeBytes());
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } on Exception catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Could not read that image: $e')),
        );
    }
  }

  /// Drops an uploaded cover. The playlist does not go bare: the server
  /// rebuilds the one it makes from the member covers.
  Future<void> _resetCover(BuildContext context, WidgetRef ref) async {
    final pid = view.playlist.pid;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(playlistDetailProvider(pid).notifier).resetCover();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Back to the cover made from members')),
        );
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this playlist?'),
        content: const Text(
          'It goes for everyone it is shared with. The items in it are '
          'never touched.',
        ),
        actions: <Widget>[
          WaxButton(
            label: 'Cancel',
            kind: WaxButtonKind.text,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          WaxButton(
            label: 'Delete',
            semanticsId: SemanticsIds.playlistDeleteConfirm,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;
    await ref.read(playlistDetailProvider(view.playlist.pid).notifier).delete();
    // Left only from the screen that asked; a back gesture during the
    // delete would otherwise take the one it landed on.
    if (context.mounted) router.leave(fallback: WaxRoute.playlists);
  }

  /// Runs an edit and says what the server said when it refused.
  static Future<void> _guard(
    ScaffoldMessengerState messenger,
    Future<void> Function() edit,
  ) async {
    try {
      await edit();
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// The portable export, as the JSON the importer on another server reads.
String portableJson(PortablePlaylist portable) => jsonEncode(<String, Object?>{
  'name': portable.name,
  'refs': <Object?>[
    for (final ref in portable.refs)
      <String, Object?>{
        'kind': ref.kind,
        if (ref.essence != null) 'essence': ref.essence,
        if (ref.fingerprint != null) 'fingerprint': ref.fingerprint,
        if (ref.fingerprintAlgo != null) 'fingerprintAlgo': ref.fingerprintAlgo,
        if (ref.mbid != null) 'mbid': ref.mbid,
        if (ref.asin != null) 'asin': ref.asin,
        if (ref.isbn != null) 'isbn': ref.isbn,
        if (ref.isrc != null) 'isrc': ref.isrc,
        if (ref.artist != null) 'artist': ref.artist,
        'title': ref.title,
        if (ref.album != null) 'album': ref.album,
        if (ref.durationMs != null) 'durationMs': ref.durationMs,
      },
  ],
});
