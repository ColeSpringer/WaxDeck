import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../music/album_detail.dart';
import '../music/entity_facts.dart';
import '../music/music_controllers.dart';
import '../settings/client_prefs.dart';
import '../settings/settings_registry.dart';
import '../shell/forbidden_page.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shortcuts.dart';
import 'album_pane.dart';
import 'bulk_pane.dart';
import 'metadata_screen.dart';

/// Where the workbench put its seam, in whole pixels; zero is "wherever
/// the layout puts it". Per device, beside the review queue's own, for
/// the same reason: a seam is a fact about the window it was dragged in.
class MetadataListWidth extends IntSetting {
  @override
  String get settingKey => ClientSettingKeys.metadataListWidth;

  @override
  int get defaultValue => 0;

  @override
  int get minValue => 0;

  /// A sanity ceiling rather than a layout bound; the screen clamps
  /// against the room it actually has, every frame.
  @override
  int get maxValue => 32000;
}

final metadataListWidthProvider = NotifierProvider<MetadataListWidth, int>(
  MetadataListWidth.new,
);

/// The release workbench, served at `/metadata/<al-...>`: the album
/// entity row and its member tracks on the left, the editor for
/// whatever is selected on the right. One track selected mounts the
/// item editor's own pane; checked tracks mount the bulk form; the
/// album row mounts the entity editor that used to be a screen of its
/// own.
///
/// Below the width that holds two panes it is the list alone: a track
/// pushes its own editor location, and the album and bulk forms open as
/// sheets.
///
/// Administrators only, refused before it loads: the entity edit and
/// the bulk edit are both admin endpoints, and this location is
/// shareable, so the rule is stated where it cannot be walked around.
/// An uploader keeps the per-track editor through the track's own
/// location.
class ReleaseWorkbench extends ConsumerStatefulWidget {
  const ReleaseWorkbench({super.key, required this.pid});

  final String pid;

  /// The narrowest the list may be squeezed to and still read as a
  /// track list, and the widest it grows to on its own.
  static const listMin = 280.0;
  static const listMax = 400.0;

  /// What the editor pane beside it needs, asked of the pane rather
  /// than guessed: below its own floor the surface is the list alone.
  static const paneMin = MetadataPane.minWidth;

  /// The narrowest content pane that holds both. Measured against the
  /// room this screen actually gets, not the window's size class: the
  /// shell sidebar takes its share before this screen starts.
  static const twoPaneMinWidth = listMin + WaxSplitter.hitWidth + paneMin;

  @override
  ConsumerState<ReleaseWorkbench> createState() => _ReleaseWorkbenchState();
}

class _ReleaseWorkbenchState extends ConsumerState<ReleaseWorkbench> {
  final _scroll = ScrollController();

  /// Keyboard cursor over the rows: 0 is the album row, 1..N the
  /// tracks; -1 before the first j/k.
  var _cursor = -1;

  /// The track the pane edits, or null for the album row. Only ever
  /// set where there is a pane to draw it in - on compact a track tap
  /// pushes its own location instead.
  String? _open;

  /// Multi-select mode with the checked track pids.
  var _selecting = false;
  final _checked = <String>{};

  /// Whether the last layout pass had room for two panes. A plain
  /// field, written during layout and read by the keyboard handlers,
  /// which run outside any build.
  var _twoPane = false;

  /// The row pitch the last build measured, for the keyboard scroll
  /// arithmetic. Asked of the row component so it tracks the text
  /// scale; a fixed number clips the rows the moment the OS setting
  /// moves.
  var _rowExtent = 64.0;

  /// Whether the mounted pane reported unsaved edits. A plain field:
  /// it is only read at the moment a swap would discard the pane.
  var _paneDirty = false;

  /// Where a drag in flight has the seam; null outside a gesture.
  double? _dragging;

  MusicListing get _listing =>
      (dimension: MusicDimension.albums, segment: widget.pid);

  List<ItemSummary> get _tracks => albumOrder(
    ref.read(musicItemsProvider(_listing)).value?.items ?? const [],
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double _listMax(double available) =>
      (available - WaxSplitter.hitWidth - ReleaseWorkbench.paneMin).clamp(
        ReleaseWorkbench.listMin,
        double.infinity,
      );

  /// The list's width beside the pane: a third of the room, bounded,
  /// unless a dragged seam said otherwise - a drag is not a guess and
  /// is allowed past [ReleaseWorkbench.listMax], as far as the pane's
  /// own floor.
  double _listWidth(double available, int stored) {
    final room = available - WaxSplitter.hitWidth;
    final wanted =
        _dragging ??
        (stored > 0
            ? stored.toDouble()
            : (room / 3).clamp(
                ReleaseWorkbench.listMin,
                ReleaseWorkbench.listMax,
              ));
    return wanted.clamp(ReleaseWorkbench.listMin, _listMax(available));
  }

  void _paneDirtyChanged(bool dirty) => _paneDirty = dirty;

  /// Whether a swap that replaces the pane may go ahead. True straight
  /// away when nothing is at stake; otherwise the person decides -
  /// every selection change re-keys the pane, and the State under it
  /// owns the draft.
  Future<bool> _confirmDiscard() async {
    if (!_twoPane || !_paneDirty) return true;
    final l10n = context.l10n;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.metadataDiscardTitle),
        content: Text(l10n.metadataDiscardBody),
        actions: <Widget>[
          WaxButton(
            label: l10n.commonCancel,
            kind: WaxButtonKind.text,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          WaxButton(
            label: l10n.metadataDiscardConfirm,
            semanticsId: SemanticsIds.workbenchDiscardConfirm,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (!(discard ?? false)) return false;
    _paneDirty = false;
    return true;
  }

  void _move(int delta) {
    final tracks = _tracks;
    setState(() {
      _cursor = (_cursor + delta).clamp(0, tracks.length);
    });
    _ensureVisible(_cursor);
    if (_cursor >= tracks.length - 2) {
      ref.read(musicItemsProvider(_listing).notifier).loadMore();
    }
  }

  void _ensureVisible(int index) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final target = index * _rowExtent;
    final top = position.pixels;
    final bottom = top + position.viewportDimension - _rowExtent;
    final double? to = target < top
        ? target
        : target > bottom
        ? target - position.viewportDimension + _rowExtent
        : null;
    if (to == null) return;
    _scroll.animateTo(
      to.clamp(0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  /// Space on a track checks it, entering selection the way a
  /// long-press does; on the album row it has nothing to check.
  void _toggleAtCursor() {
    final tracks = _tracks;
    if (_cursor < 1 || _cursor > tracks.length) return;
    unawaited(_toggleChecked(tracks[_cursor - 1]));
  }

  Future<void> _toggleChecked(ItemSummary track) async {
    // Entering selection replaces the pane, and changing the checked
    // set re-keys the bulk form; either would drop a dirty draft.
    if (!await _confirmDiscard()) return;
    if (!mounted) return;
    setState(() {
      _selecting = true;
      if (!_checked.add(track.pid)) _checked.remove(track.pid);
    });
  }

  void _openAtCursor() {
    if (_cursor < 0) return;
    final tracks = _tracks;
    if (_cursor == 0) {
      unawaited(_openAlbum());
    } else if (_cursor <= tracks.length) {
      unawaited(_openTrack(tracks[_cursor - 1]));
    }
  }

  Future<void> _openAlbum() async {
    if (!_twoPane) {
      await _albumSheet();
      return;
    }
    if (_open == null && !_selecting) return;
    if (!await _confirmDiscard()) return;
    if (!mounted) return;
    setState(() {
      _open = null;
      _selecting = false;
      _checked.clear();
    });
  }

  Future<void> _openTrack(ItemSummary track) async {
    if (_selecting) {
      await _toggleChecked(track);
      return;
    }
    if (!_twoPane) {
      // The item editor is a canonical location of its own; the
      // workbench only hosts it where there is a pane to hold it.
      unawaited(context.push(WaxRoute.metadata(track.pid)));
      return;
    }
    if (_open == track.pid) return;
    if (!await _confirmDiscard()) return;
    if (!mounted) return;
    setState(() => _open = track.pid);
  }

  Future<void> _escape() async {
    if (_selecting) {
      if (!await _confirmDiscard()) return;
      if (!mounted) return;
      setState(() {
        _selecting = false;
        _checked.clear();
      });
      return;
    }
    if (_open == null) return;
    if (!await _confirmDiscard()) return;
    if (!mounted) return;
    setState(() => _open = null);
  }

  Future<void> _toggleSelecting() async {
    if (!await _confirmDiscard()) return;
    if (!mounted) return;
    setState(() {
      _selecting = !_selecting;
      if (!_selecting) _checked.clear();
    });
  }

  /// Where a regroup takes the workbench: the same location under the
  /// album pid the tracks landed on. Replaced rather than gone to, so
  /// a workbench that was pushed from an album's overflow keeps its
  /// way back.
  void _goTo(String albumPid) {
    if (mounted) context.replace(WaxRoute.metadata(albumPid));
  }

  /// A member saved in the pane: the pane's controller refetches only
  /// itself, and the list beside it holds the same item.
  void _memberSaved() {
    ref
      ..invalidate(musicItemsProvider(_listing))
      ..invalidate(albumDetailProvider(widget.pid));
  }

  Future<void> _albumSheet() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.95,
      child: AlbumPane(
        pid: widget.pid,
        onRegrouped: (newPid) {
          // The regroup can arrive from a snackbar action after the
          // sheet was swiped away; a dead context must not be walked.
          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
          _goTo(newPid);
        },
      ),
    ),
  );

  Future<void> _bulkSheet() async {
    final ordered = _orderedChecked();
    // Checks can outlive their rows - a regroup moves tracks off the
    // release - and a form over nothing has nothing to fetch.
    if (ordered.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.95,
        child: WorkbenchBulkPane(
          pids: ordered,
          albumPid: widget.pid,
          onRegrouped: (newPid) {
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            _goTo(newPid);
          },
        ),
      ),
    );
  }

  /// The checked pids in list order, which is the order the batch
  /// reports its outcomes back in. Filtered against the live rows, so
  /// a check whose track left the release stops counting.
  List<String> _orderedChecked() => [
    for (final track in _tracks)
      if (_checked.contains(track.pid)) track.pid,
  ];

  /// Keeps the cursor on a row that exists once the list shortens
  /// under it - a bulk edit that regrouped part of the release does
  /// exactly that.
  void _clampCursor(int trackCount) {
    if (_cursor > trackCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _cursor = trackCount);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // On the screen, not only on the doors that open it: this location
    // is shareable and the web build puts it in the path, so a member
    // following a pasted link would otherwise get a form whose every
    // Save answers 403.
    if (!ref.watch(isAdminProvider)) {
      return ForbiddenPage(
        pageTitle: l10n.musicAlbumTitle,
        heading: l10n.musicAlbumEditorForbiddenTitle,
        message: l10n.musicAlbumEditorForbiddenMessage,
        glyph: WaxIcons.edit,
        fallback: WaxRoute.music,
      );
    }
    final album = ref.watch(albumDetailProvider(widget.pid));
    final members = ref.watch(musicItemsProvider(_listing));
    final seamAt = ref.watch(metadataListWidthProvider);
    _rowExtent = MediaListRow.heightFor(context);
    _clampCursor(members.value?.items.length ?? 0);
    return AppShortcuts(
      // No Enter binding, deliberately: a focused Save is activated by
      // Enter, and a screen-level binding would swallow it and swap
      // the pane instead. `e` opens, like the review queue.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyJ): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.keyK): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.space): _toggleAtCursor,
        const SingleActivator(LogicalKeyboardKey.keyE): _openAtCursor,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            unawaited(_escape()),
      },
      child: WaxScaffold(
        title: album.value?.title ?? l10n.musicAlbumTitle,
        largeTitle: false,
        semanticsId: SemanticsIds.metadataWorkbench,
        onBack: () => context.leave(fallback: WaxRoute.music),
        // A filling sliver, not a body: the list needs a bounded height
        // and a scroll position of its own for j/k to move by
        // arithmetic, and the pane keeps its save bar under its own
        // scroll.
        slivers: <Widget>[
          SliverFillRemaining(
            hasScrollBody: true,
            child: LayoutBuilder(
              builder: (context, constraints) {
                _twoPane =
                    constraints.maxWidth >= ReleaseWorkbench.twoPaneMinWidth;
                // No pane, nothing at stake: a resize below the
                // threshold disposes the pane, and a dirtiness it
                // reported before that must not outlive it into a
                // spurious question later.
                if (!_twoPane) _paneDirty = false;
                final width = _twoPane
                    ? _listWidth(constraints.maxWidth, seamAt)
                    : constraints.maxWidth;
                // One position in the tree whether or not there is a
                // pane: moving the list between shapes rebuilds its
                // Scrollable, and a fresh scroll position starts at
                // the top - the rule the review surface states.
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          SizedBox(
                            width: width,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                _selectHeader(),
                                Expanded(child: _list(members, album.value)),
                              ],
                            ),
                          ),
                          if (_twoPane) ...<Widget>[
                            WaxSplitter(
                              position: width,
                              min: ReleaseWorkbench.listMin,
                              max: _listMax(constraints.maxWidth),
                              semanticsId: SemanticsIds.workbenchSplitter,
                              onChanged: (w) => setState(() => _dragging = w),
                              onSettled: (w) {
                                setState(() => _dragging = null);
                                ref
                                    .read(metadataListWidthProvider.notifier)
                                    .set(w.round());
                              },
                              onReset: () {
                                setState(() => _dragging = null);
                                ref
                                    .read(metadataListWidthProvider.notifier)
                                    .set(0);
                              },
                            ),
                            Expanded(child: _pane()),
                          ],
                        ],
                      ),
                    ),
                    if (!_twoPane && _selecting) _bulkBar(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _pane() {
    final l10n = context.l10n;
    final Widget pane;
    if (_selecting) {
      final ordered = _orderedChecked();
      pane = ordered.isEmpty
          ? Center(
              child: EmptyState(
                glyph: WaxIcons.check,
                title: l10n.metadataWorkbenchSelectEmptyTitle,
                message: l10n.metadataWorkbenchSelectEmptyMessage,
              ),
            )
          // Keyed by the selection: a different set of tracks is a
          // different set of common values, so the form reseeds.
          : WorkbenchBulkPane(
              key: ValueKey(ordered.join(' ')),
              pids: ordered,
              albumPid: widget.pid,
              onRegrouped: _goTo,
              onDirtyChanged: _paneDirtyChanged,
            );
    } else if (_open case final pid?) {
      // The item editor itself, one member at a time. Keyed by pid so
      // a move to the next track starts a fresh draft rather than
      // carrying the last one's staged edits onto it.
      pane = MetadataPane(
        key: ValueKey(pid),
        pid: pid,
        embedded: true,
        onSaved: _memberSaved,
        onDirtyChanged: _paneDirtyChanged,
      );
    } else {
      pane = AlbumPane(
        pid: widget.pid,
        onRegrouped: _goTo,
        onDirtyChanged: _paneDirtyChanged,
      );
    }
    return Semantics(
      container: true,
      identifier: SemanticsIds.workbenchPane,
      child: pane,
    );
  }

  Widget _list(AsyncValue<MusicItemsState> members, AlbumDetail? album) {
    // Rows first, whatever the load state: every save invalidates the
    // members, and flashing the list to a skeleton would lose the
    // scroll position and the checks.
    final state = members.value;
    if (state == null) {
      // The album row stays above the failure: on compact it is the
      // only door to the entity form, and a member listing that will
      // not load is no reason to lose the release's own fields.
      return Semantics(
        container: true,
        explicitChildNodes: true,
        identifier: SemanticsIds.workbenchList,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _albumRow(album, trackCount: 0),
            Expanded(
              child: switch (members) {
                AsyncValue(hasError: true, error: final Object error) =>
                  Padding(
                    padding: const EdgeInsets.all(WaxSpace.s16),
                    child: ErrorState(
                      title: context.l10n.musicAlbumLoadError,
                      message: context.explain(error),
                      onRetry: () =>
                          ref.invalidate(musicItemsProvider(_listing)),
                    ),
                  ),
                _ => const SkeletonShapes(shape: SkeletonShape.list),
              },
            ),
          ],
        ),
      );
    }
    final tracks = albumOrder(state.items);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: SemanticsIds.workbenchList,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          final metrics = notification.metrics;
          if (metrics.pixels >= metrics.maxScrollExtent - 400) {
            ref.read(musicItemsProvider(_listing).notifier).loadMore();
          }
          return false;
        },
        child: ListView.builder(
          controller: _scroll,
          itemExtent: _rowExtent,
          itemCount: 1 + tracks.length + (state.loadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _albumRow(album, trackCount: tracks.length);
            }
            if (index > tracks.length) {
              return const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            return _trackRow(index, tracks[index - 1]);
          },
        ),
      ),
    );
  }

  /// The selection toggle, in a slim header pinned over the list -
  /// beside the rows it selects, not in the app bar away from them,
  /// and outside the builder so scrolling a long release can never
  /// virtualise the only pointer affordance for leaving the mode away.
  Widget _selectHeader() {
    final l10n = context.l10n;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s8),
        child: WaxIconButton(
          glyph: _selecting ? WaxIcons.close : WaxIcons.check,
          label: _selecting
              ? l10n.metadataWorkbenchSelectLeave
              : l10n.metadataWorkbenchSelectEnter,
          active: _selecting,
          semanticsId: SemanticsIds.workbenchSelectToggle,
          onPressed: () => unawaited(_toggleSelecting()),
        ),
      ),
    );
  }

  /// The release itself, as the list's first row: what the workbench
  /// is open on, and the door to its entity fields.
  Widget _albumRow(AlbumDetail? album, {required int trackCount}) {
    final l10n = context.l10n;
    return _cursorTint(
      cursor: _cursor == 0,
      child: MediaListRow(
        data: MediaTileData(
          title: album?.title ?? l10n.musicAlbumTitle,
          subtitle: <String>[
            if (album?.year case final year?) '$year',
            l10n.musicTrackCount(album?.itemCount ?? trackCount),
          ].join(' · '),
          semanticsId: SemanticsIds.workbenchAlbumRow,
        ),
        selected: _twoPane && !_selecting && _open == null,
        onTap: () => unawaited(_openAlbum()),
      ),
    );
  }

  Widget _trackRow(int index, ItemSummary track) {
    return _cursorTint(
      cursor: index == _cursor,
      child: MediaListRow(
        data: MediaTileData(
          title: track.title,
          trailingText: formatTimecode(
            Duration(milliseconds: track.durationMs),
          ),
          semanticsId: SemanticsIds.workbenchRow(track.pid),
        ),
        leadingIndex: track.trackNumber ?? index,
        selected: _selecting
            ? _checked.contains(track.pid)
            : _twoPane && track.pid == _open,
        onSelect: _selecting ? (_) => unawaited(_toggleChecked(track)) : null,
        onTap: () => unawaited(_openTrack(track)),
        onLongPress: () => unawaited(_toggleChecked(track)),
      ),
    );
  }

  /// The keyboard cursor's highlight, under the row's own surface: the
  /// row paints itself transparent unless selected, so the tint shows
  /// through exactly where the cursor sits.
  Widget _cursorTint({required bool cursor, required Widget child}) {
    final colors = WaxColors.of(context);
    return ColoredBox(
      color: cursor ? colors.accentContainer : colors.canvas,
      child: child,
    );
  }

  /// The compact bulk bar: the count, and the door to the bulk form as
  /// a sheet. On two panes the form is already beside the list, so the
  /// bar only exists where it is the way in. Counted over the checks
  /// that still have rows, not the raw set: a regroup can move a
  /// checked track off the release.
  Widget _bulkBar() {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final ordered = _orderedChecked();
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: SemanticsIds.workbenchBulkBar,
      child: Container(
        color: colors.surface2,
        padding: const EdgeInsets.symmetric(
          horizontal: WaxSpace.s16,
          vertical: WaxSpace.s8,
        ),
        child: Row(
          children: <Widget>[
            Text(
              l10n.metadataWorkbenchSelectedCount(ordered.length),
              style: WaxType.label.copyWith(color: colors.textSecondary),
            ),
            const Spacer(),
            WaxButton(
              label: l10n.metadataWorkbenchEditSelection,
              kind: WaxButtonKind.text,
              semanticsId: SemanticsIds.workbenchBulkEdit,
              onPressed: ordered.isEmpty ? null : () => unawaited(_bulkSheet()),
            ),
          ],
        ),
      ),
    );
  }
}
