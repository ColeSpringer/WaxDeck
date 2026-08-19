import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../admin/admin_providers.dart';
import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../media_view.dart';
import '../settings/client_prefs.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import '../shell/shortcuts.dart';
import 'review_controller.dart';
import 'review_entry_screen.dart';

/// The review surface: the queue, with one entry beside it where there
/// is room and in place of it where there is not. Both `/review`
/// locations land here, so an entry keeps its own URL either way.
class ReviewSurface extends StatelessWidget {
  const ReviewSurface({super.key, this.openEntryId});

  final String? openEntryId;

  /// The narrowest the list may be squeezed to and still read as a
  /// queue, and the widest it grows to on its own.
  static const listMin = 280.0;
  static const listMax = 380.0;

  /// What the entry beside it needs, asked of the entry rather than
  /// guessed: the diff table's own minimum plus the chrome between it
  /// and the pane's edge. Below this the table's horizontal scroller
  /// takes over, which is the crowding this threshold exists to keep
  /// the reviewer out of.
  static const paneMin = ReviewEntryView.minWidth;

  /// The narrowest content pane that holds both.
  ///
  /// Derived from what the *entry* needs rather than from what the list
  /// wants, which is the change: the old threshold added 340 to a fixed
  /// 380 list, so the first window wide enough to split gave the
  /// submission 340 - well inside the table's own minimum, and a
  /// horizontal scrollbar under the thing being read. Every window that
  /// gets two panes can now hold the table without one.
  static const _twoPaneMinWidth = listMin + WaxSplitter.hitWidth + paneMin;

  @override
  Widget build(BuildContext context) {
    // Measured, not the window's size class: the shell sidebar and the
    // console list take ~500px before this screen starts.
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoPane = constraints.maxWidth >= _twoPaneMinWidth;
        if (openEntryId != null && !twoPane) {
          return ReviewEntryScreen(entryId: openEntryId!);
        }
        return ReviewScreen(openEntryId: twoPane ? openEntryId : null);
      },
    );
  }
}

/// Where the reviewer put the seam, in whole pixels; zero is "wherever
/// the layout puts it", which is what a fresh device reads and what the
/// double-tap reset writes back.
///
/// Per device, stored beside the sidebar's own fold rather than on the
/// account: a seam is a fact about the window it was dragged in, and the
/// screen clamps whatever comes back against the room it actually has.
class ReviewListWidth extends IntSetting {
  @override
  String get settingKey => ClientSettingKeys.reviewListWidth;

  @override
  int get defaultValue => 0;

  @override
  int get minValue => 0;

  /// A sanity ceiling rather than a layout bound, and deliberately past
  /// any panel a seam could be dragged across: [IntSetting.set] clamps
  /// writes as well as reads, so a bound near a real width would freeze
  /// the seam under a still-moving pointer on a wide enough screen. The
  /// screen bounds this against the room it actually has, every frame.
  @override
  int get maxValue => 32000;
}

final reviewListWidthProvider = NotifierProvider<ReviewListWidth, int>(
  ReviewListWidth.new,
);

/// The metadata review queue: filterable, cursor paged, keyboard-first.
/// j/k move, a/s/u decide, e opens, Escape leaves. Long-press a row or
/// use the select button for bulk decisions.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, this.openEntryId});

  /// The entry drawn in the pane beside the list. Only ever set above
  /// sidebar width, where there is a pane to draw it in.
  final String? openEntryId;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  /// Fixed row height so keyboard selection can scroll by arithmetic
  /// instead of hunting for offscreen render objects.
  static const _rowExtent = 76.0;

  /// The list's own width once the pane is beside it.
  ///
  /// A third of the room, bounded, rather than a fixed 380: the pane is
  /// where the reading happens, so the majority goes to the submission
  /// somebody opened - which at the width this was reported at meant a
  /// queue of one-line rows holding 380 while the files under review
  /// had 343.
  ///
  /// A seam dragged by hand outranks that and is allowed past [listMax],
  /// as far as the entry's own floor: the default is a guess about what
  /// somebody wants, and a drag is not.
  ///
  /// [stored] is read in `build` and passed down rather than watched
  /// here: this runs from a `LayoutBuilder`, which builds during layout
  /// rather than during the build that owns this ref.
  double _listWidth(double available, int stored) {
    final room = available - WaxSplitter.hitWidth;
    final wanted =
        _dragging ??
        (stored > 0
            ? stored.toDouble()
            : (room / 3).clamp(ReviewSurface.listMin, ReviewSurface.listMax));
    return wanted.clamp(ReviewSurface.listMin, _listMax(available));
  }

  /// Where a drag in flight has the seam, so the panes follow the
  /// pointer without a preference being written down per frame. Null
  /// outside a gesture, when the stored width is the answer again.
  double? _dragging;

  /// The widest the list may be drawn at this size, which is whatever
  /// leaves the entry its floor. Never below [ReviewSurface.listMin]:
  /// the surface only draws two panes above the threshold, and clamping
  /// to a smaller maximum than minimum throws.
  double _listMax(double available) =>
      (available - WaxSplitter.hitWidth - ReviewSurface.paneMin).clamp(
        ReviewSurface.listMin,
        double.infinity,
      );

  final _scroll = ScrollController();

  /// Index of the keyboard-selected row; -1 before the first j/k.
  var _selected = -1;

  /// Multi-select mode with the checked entry ids.
  var _selecting = false;
  final _checked = <String>{};

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<ReviewEntry> get _entries =>
      ref.read(reviewQueueProvider).value?.entries ?? const [];

  void _move(int delta) {
    final entries = _entries;
    if (entries.isEmpty) return;
    setState(() {
      _selected = (_selected + delta).clamp(0, entries.length - 1);
    });
    _ensureVisible(_selected);
    if (_selected >= entries.length - 3) {
      ref.read(reviewQueueProvider.notifier).loadMore();
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

  Future<void> _decideSelected(String action) async {
    final entries = _entries;
    if (_selected < 0 || _selected >= entries.length) return;
    final entry = entries[_selected];
    if (entry.status != 'pending' || entry.identifying) return;
    // `a` on the row the pane is showing approves what the pane has
    // selected, or the two controls decide different releases.
    await _decide(
      entry.id,
      action,
      candidateMbid: action == 'approve'
          ? ref.read(selectedCandidateProvider(entry.id))
          : null,
    );
  }

  Future<void> _decide(
    String entryId,
    String action, {
    String? candidateMbid,
  }) async {
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      final warnings = await ref
          .read(reviewQueueProvider.notifier)
          .decide(entryId, action, candidateMbid: candidateMbid);
      // The server's own words: a warning names the file or the field it
      // is about, which no table sentence can.
      if (warnings.isNotEmpty) messenger.show(warnings.join('\n'));
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
    }
  }

  Future<void> _decideBulk(String action) async {
    final ids = _checked.toList();
    if (ids.isEmpty) return;
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      final outcomes = await ref
          .read(reviewQueueProvider.notifier)
          .decideBulk(ids, action);
      final failed = outcomes.where((o) => !o.ok).length;
      messenger.show(
        failed == 0
            ? l10n.reviewDecidedCount(outcomes.length)
            : l10n.reviewDecidedSomeFailed(outcomes.length - failed, failed),
      );
      setState(() {
        _selecting = false;
        _checked.clear();
      });
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
    }
  }

  void _openSelected() {
    final entries = _entries;
    if (_selected < 0 || _selected >= entries.length) return;
    _open(entries[_selected]);
  }

  void _open(ReviewEntry entry) {
    context.go(WaxRoute.reviewEntry(entry.id));
  }

  void _escape() {
    if (_selecting) {
      setState(() {
        _selecting = false;
        _checked.clear();
      });
      return;
    }
    // One page spans both locations, so leaving the entry is a move
    // rather than a pop.
    if (widget.openEntryId != null) context.go(WaxRoute.review);
  }

  void _toggleChecked(ReviewEntry entry) {
    setState(() {
      if (!_checked.add(entry.id)) _checked.remove(entry.id);
    });
  }

  /// Keeps the cursor on a row that exists, and on the entry the pane
  /// is showing. Deciding the last row shortens the queue under it, and
  /// a tap has to move it or the next j resumes from somewhere else.
  void _syncSelection(List<ReviewEntry> entries) {
    final open = widget.openEntryId;
    if (open != null) {
      if (_selected >= 0 &&
          _selected < entries.length &&
          entries[_selected].id == open) {
        return;
      }
      final index = entries.indexWhere((entry) => entry.id == open);
      if (index >= 0 && index != _selected) {
        _later(() => _selected = index);
        return;
      }
    }
    if (_selected >= entries.length) {
      // Onto the last row rather than off the end: the reviewer was
      // working down the queue and the next thing they press should
      // decide something.
      _later(() => _selected = entries.length - 1);
    }
  }

  /// Called from `build`, where `setState` is not allowed.
  void _later(VoidCallback move) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(move);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sizeClass = WaxSizeClass.of(context);
    final queue = ref.watch(reviewQueueProvider);
    final seamAt = ref.watch(reviewListWidthProvider);
    final l10n = context.l10n;
    _syncSelection(queue.value?.entries ?? const []);
    // Surface a failed "load more": the queue keeps its rows, so the
    // failure is otherwise invisible. Firing on the flag's rising edge
    // shows one notice per failure, and scrolling again retries.
    ref.listen(reviewQueueProvider, (prev, next) {
      final failedNow = next.value?.loadError ?? false;
      final failedBefore = prev?.value?.loadError ?? false;
      if (failedNow && !failedBefore) {
        ref
            .read(shellMessengerProvider.notifier)
            .show(l10n.reviewLoadMoreFailed);
      }
    });
    return AppShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyJ): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.keyK): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.keyA): () =>
            _decideSelected('approve'),
        const SingleActivator(LogicalKeyboardKey.keyS): () =>
            _decideSelected('skip'),
        const SingleActivator(LogicalKeyboardKey.keyU): () =>
            _decideSelected('unofficial'),
        const SingleActivator(LogicalKeyboardKey.keyE): _openSelected,
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
      },
      child: WaxScaffold(
        title: l10n.reviewTitle,
        largeTitle: false,
        semanticsId: SemanticsIds.adminReview,
        actions: <Widget>[
          const _MatchingModeMenu(),
          WaxIconButton(
            glyph: _selecting ? WaxIcons.close : WaxIcons.check,
            label: _selecting ? l10n.reviewSelectLeave : l10n.reviewSelectEnter,
            active: _selecting,
            semanticsId: SemanticsIds.reviewSelectToggle,
            onPressed: () => setState(() {
              _selecting = !_selecting;
              if (!_selecting) _checked.clear();
            }),
          ),
        ],
        // A filling sliver, not a body: the list needs a bounded height
        // and a scroll position of its own for j/k to move by arithmetic.
        slivers: <Widget>[
          SliverFillRemaining(
            hasScrollBody: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: sizeClass.gutter.left,
                    vertical: WaxSpace.s8,
                  ),
                  child: const _FilterChips(),
                ),
                Expanded(
                  // One position in the tree either way: moving the
                  // list rebuilds its Scrollable, and a fresh scroll
                  // position starts at the top.
                  child: LayoutBuilder(
                    builder: (context, constraints) => Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        SizedBox(
                          width: widget.openEntryId == null
                              ? constraints.maxWidth
                              : _listWidth(constraints.maxWidth, seamAt),
                          child: _queue(sizeClass),
                        ),
                        if (widget.openEntryId case final open?) ...<Widget>[
                          // The seam only exists where there are two
                          // panes, which is also why there is none on a
                          // phone: below the threshold the entry takes
                          // the screen and there is nothing to divide.
                          WaxSplitter(
                            position: _listWidth(constraints.maxWidth, seamAt),
                            min: ReviewSurface.listMin,
                            max: _listMax(constraints.maxWidth),
                            semanticsId: SemanticsIds.reviewSplitter,
                            onChanged: (width) =>
                                setState(() => _dragging = width),
                            onSettled: (width) {
                              setState(() => _dragging = null);
                              ref
                                  .read(reviewListWidthProvider.notifier)
                                  .set(width.round());
                            },
                            onReset: () {
                              setState(() => _dragging = null);
                              ref.read(reviewListWidthProvider.notifier).set(0);
                            },
                          ),
                          Expanded(child: _pane(open)),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_selecting)
                  _BulkBar(count: _checked.length, onDecide: _decideBulk),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pane(String entryId) {
    return Semantics(
      identifier: SemanticsIds.reviewPane,
      container: true,
      child: ReviewEntryView(
        key: ValueKey(entryId),
        entryId: entryId,
        onClose: () => context.go(WaxRoute.review),
      ),
    );
  }

  Widget _queue(WaxSizeClass sizeClass) {
    final queue = ref.watch(reviewQueueProvider);
    // Rows first, whatever the load state: every decision invalidates
    // the queue, and flashing 200 rows to a skeleton would lose the
    // scroll position the pane exists to preserve.
    final rows = queue.value;
    if (rows != null) return _list(rows, sizeClass);
    return switch (queue) {
      AsyncError(:final error) => Padding(
        padding: sizeClass.gutter,
        child: ErrorState(
          title: context.l10n.reviewLoadError,
          message: context.explain(error),
          onRetry: () => ref.invalidate(reviewQueueProvider),
        ),
      ),
      _ => const SkeletonShapes(shape: SkeletonShape.list),
    };
  }

  Widget _list(ReviewQueueState state, WaxSizeClass sizeClass) {
    if (state.entries.isEmpty) {
      return Padding(
        padding: sizeClass.gutter,
        child: EmptyState(
          glyph: WaxIcons.check,
          title: context.l10n.reviewEmptyTitle,
          message: context.l10n.reviewEmptyMessage,
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.pixels >= metrics.maxScrollExtent - 400) {
          ref.read(reviewQueueProvider.notifier).loadMore();
        }
        return false;
      },
      child: ListView.builder(
        controller: _scroll,
        itemExtent: _rowExtent,
        itemCount: state.entries.length + (state.loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.entries.length) {
            return const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final entry = state.entries[index];
          return _ReviewRow(
            entry: entry,
            selected: index == _selected,
            open: entry.id == widget.openEntryId,
            selecting: _selecting,
            checked: _checked.contains(entry.id),
            onTap: () => _selecting ? _toggleChecked(entry) : _open(entry),
            onLongPress: () => setState(() {
              _selecting = true;
              _checked.add(entry.id);
            }),
          );
        },
      ),
    );
  }
}

/// The bulk decision bar, over the list rather than under the whole
/// page: the pane beside it keeps its own decision bar, and two bars
/// across the bottom of one screen read as one control with four verbs.
class _BulkBar extends StatelessWidget {
  const _BulkBar({required this.count, required this.onDecide});

  final int count;
  final void Function(String action) onDecide;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Container(
      color: colors.surface2,
      padding: const EdgeInsets.symmetric(
        horizontal: WaxSpace.s16,
        vertical: WaxSpace.s8,
      ),
      child: Row(
        children: <Widget>[
          Text(
            context.l10n.reviewSelectedCount(count),
            style: WaxType.label.copyWith(color: colors.textSecondary),
          ),
          const Spacer(),
          WaxButton(
            label: context.l10n.reviewActionApprove,
            kind: WaxButtonKind.text,
            semanticsId: SemanticsIds.reviewBulkApprove,
            onPressed: () => onDecide('approve'),
          ),
          WaxButton(
            label: context.l10n.reviewActionAsIs,
            kind: WaxButtonKind.text,
            semanticsId: SemanticsIds.reviewBulkAsIs,
            onPressed: () => onDecide('as-is'),
          ),
          WaxButton(
            label: context.l10n.reviewActionSkip,
            kind: WaxButtonKind.text,
            semanticsId: SemanticsIds.reviewBulkSkip,
            onPressed: () => onDecide('skip'),
          ),
        ],
      ),
    );
  }
}

/// The per-library matching mode, admin only. It stays here as well as
/// on the libraries table: this is where somebody notices a library is
/// asking too much, and another page would lose the thought.
class _MatchingModeMenu extends ConsumerWidget {
  const _MatchingModeMenu();

  static const _modes = ['auto', 'review', 'off'];

  /// The client's word for a mode, with the wire value as the last
  /// resort - the shape every other open vocabulary here keeps, so a
  /// mode a newer server invents draws as itself.
  static String _modeLabel(AppLocalizations l10n, String mode) =>
      switch (mode) {
        'auto' => l10n.reviewMatchingAuto,
        'review' => l10n.reviewMatchingReview,
        'off' => l10n.reviewMatchingOff,
        _ => mode,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin =
        ref
            .watch(authControllerProvider)
            .value
            ?.user
            ?.roles
            .contains('admin') ??
        false;
    if (!isAdmin) return const SizedBox.shrink();
    final libraries = ref.watch(librariesProvider).value ?? const [];
    if (libraries.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    return WaxMenuButton<(String, String)>(
      glyph: WaxIcons.filter,
      label: l10n.reviewMatchingMenu,
      semanticsId: SemanticsIds.matchingMenu,
      items: <WaxMenuItem<(String, String)>>[
        for (final library in libraries)
          for (final mode in _modes)
            WaxMenuItem<(String, String)>(
              value: (library.pid, mode),
              label: l10n.reviewMatchingRow(
                library.name,
                _modeLabel(l10n, mode),
              ),
              semanticsId: SemanticsIds.matchingOption(library.pid, mode),
              selected:
                  ref.watch(libraryMatchingProvider(library.pid)).value == mode,
            ),
      ],
      onSelected: (choice) => _set(l10n, ref, choice.$1, choice.$2),
    );
  }

  Future<void> _set(
    AppLocalizations l10n,
    WidgetRef ref,
    String libraryPid,
    String mode,
  ) async {
    try {
      await ref.read(libraryMatchingProvider(libraryPid).notifier).set(mode);
    } on WaxDeckApiException catch (e) {
      ref.read(shellMessengerProvider.notifier).show(explainError(l10n, e));
    }
  }
}

class _FilterChips extends ConsumerWidget {
  const _FilterChips();

  static int _decidedCount(ReviewStats stats) =>
      stats.applied +
      stats.autoApplied +
      stats.asIs +
      stats.unofficial +
      stats.skipped;

  static String _label(
    AppLocalizations l10n,
    ReviewFilter filter,
    ReviewStats? stats,
  ) {
    if (stats == null) return filter.labelOf(l10n);
    final count = switch (filter) {
      ReviewFilter.pending => stats.pending,
      ReviewFilter.autoApplied => stats.autoApplied,
      ReviewFilter.decided => _decidedCount(stats),
    };
    return l10n.reviewFilterCount(filter.labelOf(l10n), count);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(reviewFilterProvider);
    final stats = ref.watch(reviewStatsProvider).value;
    return FilterChipRow(
      padding: EdgeInsets.zero,
      selected: selected.name,
      chips: <WaxFilterChip>[
        for (final filter in ReviewFilter.values)
          WaxFilterChip(
            name: filter.name,
            label: _label(context.l10n, filter, stats),
            semanticsId: SemanticsIds.reviewFilter(filter.name),
          ),
      ],
      onSelect: (name) => ref
          .read(reviewFilterProvider.notifier)
          .select(ReviewFilter.values.byName(name)),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.entry,
    required this.selected,
    required this.open,
    required this.selecting,
    required this.checked,
    required this.onTap,
    required this.onLongPress,
  });

  final ReviewEntry entry;

  /// Where the keyboard cursor is. Distinct from [open], which is the
  /// entry the pane holds: they are the same row almost always, and are
  /// two different facts the moment the pane is closed.
  final bool selected;
  final bool open;
  final bool selecting;
  final bool checked;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  static String bestLine(AppLocalizations l10n, CandidateSummary best) {
    final percent = '${best.similarityPct.round()}';
    final year = best.year;
    return year == null
        ? l10n.reviewCandidateLine(percent, best.title, best.artist)
        : l10n.reviewCandidateLineYear(
            percent,
            best.title,
            best.artist,
            '$year',
          );
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final best = entry.best;
    final name = entry.title ?? l10n.reviewUntitled;
    final title = entry.artist == null
        ? name
        : l10n.reviewEntryLine(name, entry.artist!);
    final surface = selected || open ? colors.accentContainer : colors.canvas;
    return WaxTappable(
      label: title,
      semanticsId: SemanticsIds.reviewRow(entry.id),
      // The tick is inside this control and reports nothing of its own,
      // so the row carries the checked state for a screen reader.
      selected: selecting ? checked : open,
      surface: surface,
      borderRadius: BorderRadius.zero,
      onPressed: onTap,
      child: Material(
        color: surface,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WaxSpace.s16,
              vertical: WaxSpace.s8,
            ),
            child: Row(
              children: <Widget>[
                if (selecting) ...<Widget>[
                  WaxIcon(
                    checked ? WaxIcons.success : WaxIcons.check,
                    size: 18,
                    color: checked ? colors.accent : colors.textTertiary,
                    active: checked,
                  ),
                  const SizedBox(width: WaxSpace.s12),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: WaxType.titleItem.copyWith(
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: WaxSpace.s4),
                      if (entry.identifying)
                        Row(
                          children: <Widget>[
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: WaxSpace.s8),
                            Text(
                              l10n.reviewIdentifying,
                              style: WaxType.caption.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          best == null
                              ? l10n.reviewRowNoCandidates(entry.trackCount)
                              : l10n.reviewRowBest(
                                  entry.trackCount,
                                  bestLine(l10n, best),
                                ),
                          style: WaxType.caption.copyWith(
                            color: best == null
                                ? colors.textTertiary
                                : colors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: WaxSpace.s8),
                DomainBadge(
                  waxDomainOf(entry.mediaType),
                  label: _originLabel(l10n, context.waxL10n, entry),
                  compact: true,
                ),
                if (entry.status != 'pending') ...<Widget>[
                  const SizedBox(width: WaxSpace.s4),
                  CodecChip(entry.status),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Where the unit came from, in the badge that would otherwise say
  /// the media type twice: the queue is one domain deep at a time and
  /// "Upload" is the fact a reviewer is actually sorting by.
  static String _originLabel(
    AppLocalizations l10n,
    WaxLocalizations wax,
    ReviewEntry entry,
  ) => switch (entry.origin) {
    'upload' || 'acquisition' => reviewOriginLabel(l10n, entry.origin),
    _ => DomainBadge.defaultLabel(wax, waxDomainOf(entry.mediaType)),
  };
}
