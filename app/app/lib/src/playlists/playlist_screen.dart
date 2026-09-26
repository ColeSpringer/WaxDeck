import 'dart:async';

import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
import '../library/item_menu.dart';
import '../media_view.dart';
import '../player/now_playing_controller.dart';
import '../providers.dart';
import '../queue/queue_state.dart';
import '../search/search_chrome.dart';
import '../shell/async_sliver_face.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'playlist_actions.dart';
import 'playlist_play.dart';
import 'playlist_sync_controller.dart';
import 'playlists_controller.dart';
import 'rule_vocabulary.dart';

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
    final l10n = context.l10n;

    return WaxScaffold(
      title: view?.playlist.name ?? l10n.playlistFallbackTitle,
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
                  message: l10n.playlistConflictBanner(_conflict!),
                  tone: WaxBannerTone.caution,
                  semanticsId: SemanticsIds.playlistConflict,
                  onDismiss: () => setState(() => _conflict = null),
                ),
        ),
        AsyncSliverFace<PlaylistView>(
          state: detail,
          skeleton: SkeletonShape.detail,
          skeletonFills: true,
          errorTitle: l10n.playlistLoadError,
          onRetry: () => ref.invalidate(playlistDetailProvider(pid)),
          builder: (context, value) =>
              SliverMainAxisGroup(slivers: _body(context, value)),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s32)),
      ],
    );
  }

  List<Widget> _body(BuildContext context, PlaylistView view) {
    final playlist = view.playlist;
    final entries = view.entries;
    final l10n = context.l10n;
    return <Widget>[
      SliverToBoxAdapter(child: _Header(view: view)),
      SliverToBoxAdapter(child: _StatusChips(view: view)),
      if (view.isEditable) SliverToBoxAdapter(child: _AddRow(pid: pid)),
      if (entries.isEmpty)
        SliverToBoxAdapter(
          child: EmptyState(
            title: playlist.isSmart
                ? l10n.playlistSmartEmptyTitle
                : l10n.playlistEmptyTitle,
            message: playlist.isSmart
                ? l10n.playlistSmartEmptyMessage
                : view.isEditable
                ? l10n.playlistEditableEmptyMessage
                : l10n.playlistForeignEmptyMessage,
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
    void play({bool shuffle = false}) =>
        playPlaylist(ref, view, shuffle: shuffle);

    final l10n = context.l10n;
    return EntityHeader(
      title: playlist.name,
      subtitle: playlistOwnerLine(l10n, playlist),
      metadata: _facts(l10n, context.waxL10n, view),
      artwork: waxArtwork(ref.watch(artworkStoreProvider), playlist.artUrl),
      actions: <Widget>[
        WaxButton(
          label: l10n.playlistPlay,
          icon: WaxIcons.play,
          onPressed: entries.isEmpty ? null : play,
          semanticsId: SemanticsIds.entityPlay,
        ),
        WaxButton(
          label: l10n.playlistShuffle,
          kind: WaxButtonKind.tonal,
          icon: WaxIcons.shuffle,
          onPressed: entries.isEmpty ? null : () => play(shuffle: true),
          semanticsId: SemanticsIds.entityShuffle,
        ),
      ],
    );
  }

  /// "Smart playlist · 42 items · 2 hr 41 min". Two tables: the app's
  /// for its own words, the design system's for the span.
  static String _facts(
    AppLocalizations l10n,
    WaxLocalizations wax,
    PlaylistView view,
  ) {
    final entries = view.entries;
    final parts = <String>[
      view.playlist.isSmart
          ? l10n.playlistFactsSmart
          : l10n.playlistFactsManual,
      l10n.playlistItemCount(entries.length),
      if (view.duration > Duration.zero) wax.formatSpan(view.duration),
    ];
    return parts.join(' · ');
  }
}

/// Whose list this is, as the header's second line.
String? playlistOwnerLine(AppLocalizations l10n, Playlist playlist) {
  if (!playlist.isOwner) return l10n.playlistSharedBy(playlist.ownerName);
  return playlist.isShared ? l10n.playlistSharedWithEveryone : null;
}

/// How this list is kept: a smart list's rules, and nothing for a
/// manual one. A synced list's status chip lands here too.
class _StatusChips extends ConsumerWidget {
  const _StatusChips({required this.view});

  final PlaylistView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rule = view.playlist.rule;
    // Owner-only, like the endpoint behind it: only the owner has sync
    // settings to be told about, and nobody else may read the binding.
    final ownedManual = view.playlist.isOwner && !view.playlist.isSmart;
    final binding = ownedManual
        ? ref.watch(playlistSyncProvider(view.playlist.pid)).value
        : null;
    if (rule == null && binding == null) return const SizedBox.shrink();
    final colors = WaxColors.of(context);
    final sizeClass = WaxSizeClass.of(context);
    final l10n = context.l10n;
    final syncChip = binding == null
        ? null
        : Semantics(
            identifier: SemanticsIds.playlistSyncChip,
            container: true,
            child: CodecChip(
              binding.disabled
                  ? l10n.playlistSyncChipOff
                  : (binding.lastError ?? '').isNotEmpty
                  ? l10n.playlistSyncChipFailing
                  // "Synced" is a claim about the past, so a binding
                  // that has never completed a run does not make it.
                  // What it says instead depends on what it is: a live
                  // source has a schedule to wait for, a matched export
                  // has none by construction and re-matches on demand,
                  // so telling somebody a sync is scheduled would be
                  // waiting for something that is never coming.
                  : binding.lastSyncedAt != null
                  ? l10n.playlistSyncChipSynced
                  : binding.live
                  ? l10n.playlistSyncChipPending
                  : l10n.playlistSyncChipMatched,
              emphasis:
                  binding.disabled || (binding.lastError ?? '').isNotEmpty,
            ),
          );
    if (rule == null) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          sizeClass.gutter.horizontal / 2,
          WaxSpace.s16,
          sizeClass.gutter.horizontal / 2,
          WaxSpace.s8,
        ),
        child: Wrap(
          spacing: WaxSpace.s8,
          runSpacing: WaxSpace.s8,
          children: <Widget>[syncChip!],
        ),
      );
    }
    // A rule naming another playlist reads as that list's name; the
    // provider is already loaded here, and a pid the caller cannot
    // resolve falls back to itself.
    final known = ref.watch(playlistsProvider).value ?? const <Playlist>[];
    final chips = describeRule(
      l10n,
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
            label: l10n.playlistEditRules,
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
            label: l10n.playlistRulesSpoken(chips.join(', ')),
            child: summary,
          ),
          const SizedBox(height: WaxSpace.s8),
          Text(
            l10n.playlistRulesLive,
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
    final l10n = context.l10n;
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
        ..showSnackBar(SnackBar(content: Text(l10n.playlistAdded(hit.title))));
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final sizeClass = WaxSizeClass.of(context);
    final l10n = context.l10n;
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
            label: l10n.playlistAddLabel,
            hint: l10n.playlistAddHint,
            glyph: WaxIcons.add,
            // Its own name is the header this sits under, and its hint
            // says what to type: drawn as a caption too, "Add to this
            // playlist" is the third statement of the same thing.
            showLabel: false,
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
                l10n.playlistAddNothing,
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
    final l10n = context.l10n;
    // Hoisted: the labels do not vary by row, and a reorderable list
    // rebuilds every visible one on every drag frame.
    final moveUp = CustomSemanticsAction(label: l10n.playlistMoveUp);
    final moveDown = CustomSemanticsAction(label: l10n.playlistMoveDown);
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
                moveUp: () =>
                    unawaited(_move(context, ref, from: index, to: index - 1)),
              if (index < entries.length - 1)
                moveDown: () =>
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
                  label: l10n.playlistDragToReorder,
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
    final l10n = context.l10n;
    try {
      await ref.read(playlistDetailProvider(pid).notifier).reorder(pids);
    } on WaxDeckApiException catch (e) {
      // The list already animated, so it goes back either way. A lost
      // race gets the banner; anything else is a one-off failure.
      ref.invalidate(playlistDetailProvider(pid));
      if (e.code == 'conflict') {
        onConflict(explainRefusal(l10n, e));
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, int index) async {
    // The stored position, never the row index: visibility filtering
    // leaves a viewer's rows non-contiguous.
    final position = view.entries[index].position;
    if (position == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await ref.read(playlistDetailProvider(pid).notifier).removeAt(position);
    } on WaxDeckApiException catch (e) {
      ref.invalidate(playlistDetailProvider(pid));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
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
              onMore: () => showItemMenuForSummary(context, ref, item),
              moreSemanticsId: SemanticsIds.playlistEntryMore(index),
            ),
          ),
          if (onRemove != null)
            WaxIconButton(
              glyph: WaxIcons.close,
              label: context.l10n.playlistEntryRemove,
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
}

/// Every playlist action but play and shuffle, which are the header's.
class _Overflow extends ConsumerWidget {
  const _Overflow({required this.view});

  final PlaylistView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = GoRouter.of(context);
    return WaxMenuButton<PlaylistAction>(
      glyph: WaxIcons.more,
      label: context.l10n.playlistMore,
      semanticsId: SemanticsIds.playlistOverflow,
      items: playlistMenuItems(context, ref, view.playlist),
      onSelected: (action) => unawaited(
        runPlaylistAction(
          context,
          ref,
          view.playlist,
          action,
          onDeleted: () => router.leave(fallback: WaxRoute.playlists),
        ),
      ),
    );
  }
}
