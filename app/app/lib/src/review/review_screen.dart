import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../auth/auth_controller.dart';
import '../media_icons.dart';
import '../shell/semantics_ids.dart';
import '../shell/shortcuts.dart';
import 'review_controller.dart';
import 'review_entry_screen.dart';

/// The metadata review queue: filterable, cursor paged, keyboard-first.
///
/// j / ArrowDown and k / ArrowUp move the selection, a approves with the
/// best candidate, s skips, u marks unofficial, e opens the entry, and
/// Escape leaves the screen (or clears the multi-select). Long-press a
/// row or use the app bar select button for bulk decisions.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  /// Fixed row height so keyboard selection can scroll by arithmetic
  /// instead of hunting for offscreen render objects.
  static const _rowExtent = 88.0;

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
    await _decide(entry.id, action);
  }

  Future<void> _decide(String entryId, String action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final warnings = await ref
          .read(reviewQueueProvider.notifier)
          .decide(entryId, action);
      if (warnings.isNotEmpty) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(warnings.join('\n'))));
      }
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _decideBulk(String action) async {
    final ids = _checked.toList();
    if (ids.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final outcomes = await ref
          .read(reviewQueueProvider.notifier)
          .decideBulk(ids, action);
      final failed = outcomes.where((o) => !o.ok).length;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              failed == 0
                  ? 'Decided ${outcomes.length} entries'
                  : 'Decided ${outcomes.length - failed} entries, $failed failed',
            ),
          ),
        );
      setState(() {
        _selecting = false;
        _checked.clear();
      });
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _openSelected() {
    final entries = _entries;
    if (_selected < 0 || _selected >= entries.length) return;
    _open(entries[_selected]);
  }

  void _open(ReviewEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReviewEntryScreen(entryId: entry.id),
      ),
    );
  }

  void _escape() {
    if (_selecting) {
      setState(() {
        _selecting = false;
        _checked.clear();
      });
      return;
    }
    Navigator.of(context).maybePop();
  }

  void _toggleChecked(ReviewEntry entry) {
    setState(() {
      if (!_checked.add(entry.id)) _checked.remove(entry.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(reviewQueueProvider);
    // Surface a failed "load more": the queue keeps its rows, so the failure
    // is otherwise invisible. Firing on the flag's rising edge shows one
    // notice per failure, and scrolling again retries.
    ref.listen(reviewQueueProvider, (prev, next) {
      final failedNow = next.value?.loadError ?? false;
      final failedBefore = prev?.value?.loadError ?? false;
      if (failedNow && !failedBefore) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Could not load more; scroll to retry'),
            ),
          );
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
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Review queue'),
          actions: [
            const _MatchingModeMenu(),
            Semantics(
              identifier: SemanticsIds.reviewSelectToggle,
              label: 'Select entries',
              button: true,
              child: IconButton(
                key: const Key(SemanticsIds.reviewSelectToggle),
                tooltip: _selecting ? 'Leave selection' : 'Select entries',
                icon: Icon(_selecting ? Icons.close : Icons.checklist),
                onPressed: () => setState(() {
                  _selecting = !_selecting;
                  if (!_selecting) _checked.clear();
                }),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            _FilterChips(),
            Expanded(
              child: switch (queue) {
                AsyncData(:final value) => _list(context, value),
                AsyncError(:final error) => _errorView(context, error),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
          ],
        ),
        bottomNavigationBar: _selecting ? _bulkBar(context) : null,
      ),
    );
  }

  Widget _errorView(BuildContext context, Object error) {
    final message = error is WaxDeckApiException
        ? error.message
        : 'Could not load the review queue';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => ref.invalidate(reviewQueueProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, ReviewQueueState state) {
    if (state.entries.isEmpty) {
      return const Center(child: Text('Nothing waiting for review'));
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
            return const Center(child: CircularProgressIndicator());
          }
          final entry = state.entries[index];
          return _ReviewRow(
            entry: entry,
            selected: index == _selected,
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

  Widget _bulkBar(BuildContext context) {
    return BottomAppBar(
      child: Row(
        children: [
          Text('${_checked.length} selected'),
          const Spacer(),
          Semantics(
            identifier: SemanticsIds.reviewBulkApprove,
            label: 'Approve selected',
            button: true,
            child: TextButton(
              key: const Key(SemanticsIds.reviewBulkApprove),
              onPressed: () => _decideBulk('approve'),
              child: const Text('Approve'),
            ),
          ),
          Semantics(
            identifier: SemanticsIds.reviewBulkAsIs,
            label: 'Keep selected as is',
            button: true,
            child: TextButton(
              key: const Key(SemanticsIds.reviewBulkAsIs),
              onPressed: () => _decideBulk('as-is'),
              child: const Text('Keep as is'),
            ),
          ),
          Semantics(
            identifier: SemanticsIds.reviewBulkSkip,
            label: 'Skip selected',
            button: true,
            child: TextButton(
              key: const Key(SemanticsIds.reviewBulkSkip),
              onPressed: () => _decideBulk('skip'),
              child: const Text('Skip'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The per-library matching-mode control. Admin only: it is hidden for
/// everyone else, and the endpoints it drives are admin-gated anyway.
/// A library's mode chooses whether confident matches auto-apply
/// (`auto`), everything waits for review (`review`), or the library is
/// never matched (`off`).
class _MatchingModeMenu extends ConsumerWidget {
  const _MatchingModeMenu();

  static const _modes = ['auto', 'review', 'off'];

  static const _labels = {
    'auto': 'Auto-apply confident matches',
    'review': 'Review everything',
    'off': 'Never match this library',
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
    // Captured before the menu's async onTap: setting a mode is a network
    // call that can fail, and the tap must report it rather than throwing
    // into the void.
    final messenger = ScaffoldMessenger.of(context);
    return Semantics(
      identifier: SemanticsIds.matchingMenu,
      label: 'Matching mode',
      button: true,
      child: PopupMenuButton<void>(
        key: const Key(SemanticsIds.matchingMenu),
        tooltip: 'Matching mode',
        icon: const Icon(Icons.auto_fix_high_outlined),
        itemBuilder: (context) => [
          for (final library in libraries) ...[
            PopupMenuItem<void>(
              enabled: false,
              child: Text(
                library.name,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            for (final mode in _modes)
              PopupMenuItem<void>(
                key: Key('matching-${library.pid}-$mode'),
                child: _ModeRow(libraryPid: library.pid, mode: mode),
                onTap: () async {
                  try {
                    await ref
                        .read(libraryMatchingProvider(library.pid).notifier)
                        .setMode(mode);
                  } on WaxDeckApiException catch (e) {
                    messenger
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(content: Text(e.message)));
                  }
                },
              ),
          ],
        ],
      ),
    );
  }
}

/// One mode row inside the menu, showing a check on the library's
/// current mode.
class _ModeRow extends ConsumerWidget {
  const _ModeRow({required this.libraryPid, required this.mode});

  final String libraryPid;
  final String mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(libraryMatchingProvider(libraryPid)).value;
    return Row(
      children: [
        SizedBox(
          width: 24,
          child: current == mode ? const Icon(Icons.check, size: 18) : null,
        ),
        Expanded(child: Text(_MatchingModeMenu._labels[mode] ?? mode)),
      ],
    );
  }
}

class _FilterChips extends ConsumerWidget {
  static int _decidedCount(ReviewStats stats) =>
      stats.applied +
      stats.autoApplied +
      stats.asIs +
      stats.unofficial +
      stats.skipped;

  static String _label(ReviewFilter filter, ReviewStats? stats) {
    if (stats == null) return filter.label;
    final count = switch (filter) {
      ReviewFilter.pending => stats.pending,
      ReviewFilter.autoApplied => stats.autoApplied,
      ReviewFilter.decided => _decidedCount(stats),
    };
    return '${filter.label} ($count)';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(reviewFilterProvider);
    final stats = ref.watch(reviewStatsProvider).value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (final filter in ReviewFilter.values) ...[
            Semantics(
              identifier: SemanticsIds.reviewFilter(filter.name),
              label: filter.label,
              button: true,
              child: ChoiceChip(
                key: Key(SemanticsIds.reviewFilter(filter.name)),
                label: Text(_label(filter, stats)),
                selected: filter == selected,
                onSelected: (_) =>
                    ref.read(reviewFilterProvider.notifier).select(filter),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.entry,
    required this.selected,
    required this.selecting,
    required this.checked,
    required this.onTap,
    required this.onLongPress,
  });

  final ReviewEntry entry;
  final bool selected;
  final bool selecting;
  final bool checked;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  static String bestLine(CandidateSummary best) {
    final year = best.year == null ? '' : ' (${best.year})';
    return '${best.similarityPct.round()}% ${best.title}, ${best.artist}$year';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final best = entry.best;
    final title = entry.artist == null
        ? (entry.title ?? 'Untitled')
        : '${entry.title ?? 'Untitled'} by ${entry.artist}';
    return Semantics(
      identifier: SemanticsIds.reviewRow(entry.id),
      label: title,
      button: true,
      child: Material(
        key: ValueKey(SemanticsIds.reviewRow(entry.id)),
        color: selected ? colorScheme.secondaryContainer : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                if (selecting) ...[
                  Checkbox(
                    key: ValueKey('review-check-${entry.id}'),
                    value: checked,
                    onChanged: (_) => onTap(),
                  ),
                  const SizedBox(width: 4),
                ],
                Icon(
                  mediaFallbackIcon(entry.mediaType),
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${entry.trackCount} tracks',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (entry.identifying)
                        Row(
                          children: [
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Text('Identifying', style: textTheme.bodySmall),
                          ],
                        )
                      else if (best != null)
                        Text(
                          bestLine(best),
                          style: textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      else
                        Text(
                          'No candidates',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (entry.origin == 'upload' ||
                    entry.origin == 'acquisition') ...[
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(
                      entry.origin == 'acquisition' ? 'Acquired' : 'Upload',
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
                if (entry.status != 'pending') ...[
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(entry.status),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
