import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'review_controller.dart';

/// One review entry: the ranked candidate picker, the file-by-file diff
/// against the selected candidate, and the decision bar.
class ReviewEntryScreen extends ConsumerStatefulWidget {
  const ReviewEntryScreen({super.key, required this.entryId});

  final String entryId;

  @override
  ConsumerState<ReviewEntryScreen> createState() => _ReviewEntryScreenState();
}

class _ReviewEntryScreenState extends ConsumerState<ReviewEntryScreen> {
  /// The candidate the diff and Approve act on; null until the detail
  /// loads, then the top-ranked candidate.
  String? _candidateMbid;

  ReviewCandidate? _selectedCandidate(ReviewEntryDetail detail) {
    if (detail.candidates.isEmpty) return null;
    return detail.candidates
            .where((c) => c.mbid == _candidateMbid)
            .firstOrNull ??
        detail.candidates.first;
  }

  Future<void> _decide(String action, {String? candidateMbid}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final warnings = await ref
          .read(reviewEntryProvider(widget.entryId).notifier)
          .decide(action, candidateMbid: candidateMbid);
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

  Future<void> _revert() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(reviewEntryProvider(widget.entryId).notifier).revert();
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(reviewEntryProvider(widget.entryId));
    return Scaffold(
      appBar: AppBar(title: Text(detail.value?.title ?? 'Review entry')),
      body: switch (detail) {
        AsyncData(:final value) => _body(context, value),
        AsyncError(:final error) => _errorView(context, error),
        _ => const Center(child: CircularProgressIndicator()),
      },
      bottomNavigationBar: detail.hasValue
          ? SafeArea(child: _actionBar(context, detail.value!))
          : null,
    );
  }

  Widget _errorView(BuildContext context, Object error) {
    final message = error is WaxDeckApiException
        ? error.message
        : 'Could not load the entry';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () =>
                ref.invalidate(reviewEntryProvider(widget.entryId)),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, ReviewEntryDetail detail) {
    final textTheme = Theme.of(context).textTheme;
    final candidate = _selectedCandidate(detail);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(detail: detail),
          if (detail.identifying) ...[
            const SizedBox(height: 16),
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Identifying: candidate lookup is still running'),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Text('Candidates', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          if (detail.candidates.isEmpty)
            const Text('No candidates found')
          else
            for (final c in detail.candidates)
              _CandidateTile(
                candidate: c,
                selected: c.mbid == candidate?.mbid,
                onTap: () => setState(() => _candidateMbid = c.mbid),
              ),
          const SizedBox(height: 16),
          Text('Tracks', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          _DiffTable(detail: detail, candidate: candidate),
        ],
      ),
    );
  }

  Widget _actionBar(BuildContext context, ReviewEntryDetail detail) {
    final textTheme = Theme.of(context).textTheme;
    if (detail.status != 'pending') {
      final revertible =
          detail.status == 'applied' || detail.status == 'auto-applied';
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Decided: ${detail.status}',
                style: textTheme.titleSmall,
              ),
            ),
            if (revertible)
              Semantics(
                identifier: SemanticsIds.reviewRevert,
                label: 'Revert decision',
                button: true,
                child: OutlinedButton(
                  key: const Key(SemanticsIds.reviewRevert),
                  onPressed: _revert,
                  child: const Text('Revert'),
                ),
              ),
          ],
        ),
      );
    }
    final candidate = _selectedCandidate(detail);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Semantics(
            identifier: SemanticsIds.reviewApprove,
            label: 'Approve with the selected candidate',
            button: true,
            child: FilledButton(
              key: const Key(SemanticsIds.reviewApprove),
              onPressed: candidate == null
                  ? null
                  : () => _decide('approve', candidateMbid: candidate.mbid),
              child: const Text('Approve'),
            ),
          ),
          Semantics(
            identifier: SemanticsIds.reviewAsIs,
            label: 'Keep as is',
            button: true,
            child: OutlinedButton(
              key: const Key(SemanticsIds.reviewAsIs),
              onPressed: () => _decide('as-is'),
              child: const Text('Keep as is'),
            ),
          ),
          Semantics(
            identifier: SemanticsIds.reviewUnofficial,
            label: 'Mark unofficial',
            button: true,
            child: OutlinedButton(
              key: const Key(SemanticsIds.reviewUnofficial),
              onPressed: () => _decide('unofficial'),
              child: const Text('Mark unofficial'),
            ),
          ),
          Semantics(
            identifier: SemanticsIds.reviewSkip,
            label: 'Skip',
            button: true,
            child: TextButton(
              key: const Key(SemanticsIds.reviewSkip),
              onPressed: () => _decide('skip'),
              child: const Text('Skip'),
            ),
          ),
          if (detail.origin == 'upload')
            Semantics(
              identifier: SemanticsIds.reviewDiscard,
              label: 'Discard upload',
              button: true,
              child: TextButton(
                key: const Key(SemanticsIds.reviewDiscard),
                onPressed: () => _decide('discard'),
                child: const Text('Discard'),
              ),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.detail});

  final ReviewEntryDetail detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final uploadedBy = detail.uploadedBy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(detail.title ?? 'Untitled', style: textTheme.titleLarge),
        if (detail.artist != null)
          Text(detail.artist!, style: textTheme.bodyMedium),
        Text(
          '${detail.trackCount} tracks, ${detail.origin}'
          '${uploadedBy == null ? '' : ' by $uploadedBy'}',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.candidate,
    required this.selected,
    required this.onTap,
  });

  final ReviewCandidate candidate;
  final bool selected;
  final VoidCallback onTap;

  String get _subtitle {
    final parts = [
      if (candidate.year != null) '${candidate.year}',
      if (candidate.label != null) candidate.label!,
      if (candidate.country != null) candidate.country!,
    ];
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      identifier: SemanticsIds.candidate(candidate.mbid),
      label: '${candidate.title} by ${candidate.artist}',
      button: true,
      child: Card(
        key: ValueKey(SemanticsIds.candidate(candidate.mbid)),
        color: selected ? colorScheme.secondaryContainer : null,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${candidate.similarityPct.round()}%',
                      style: textTheme.titleMedium,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${candidate.title}, ${candidate.artist}',
                        style: textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_circle, color: colorScheme.primary),
                  ],
                ),
                if (_subtitle.isNotEmpty)
                  Text(
                    _subtitle,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (candidate.components.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      for (final component in candidate.components)
                        _ComponentBar(component: component),
                    ],
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

/// One similarity component as a small labeled bar with its percentage
/// (100% means identical, so the bar shows 1 - distance).
class _ComponentBar extends StatelessWidget {
  const _ComponentBar({required this.component});

  final CandidateComponent component;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final closeness = (1 - component.distance).clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(component.name, style: textTheme.labelSmall),
        const SizedBox(width: 4),
        SizedBox(width: 48, child: LinearProgressIndicator(value: closeness)),
        const SizedBox(width: 4),
        Text('${(closeness * 100).round()}%', style: textTheme.labelSmall),
      ],
    );
  }
}

/// The side-by-side diff: one row per local file against the selected
/// candidate's pairing, then the candidate tracks missing locally.
class _DiffTable extends StatelessWidget {
  const _DiffTable({required this.detail, required this.candidate});

  final ReviewEntryDetail detail;
  final ReviewCandidate? candidate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pairings = <int, CandidatePairing>{
      for (final p in candidate?.pairings ?? const <CandidatePairing>[])
        p.trackIndex: p,
    };
    final extra = (candidate?.extraTrackIndexes ?? const <int>[]).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _headerRow(theme),
        for (var i = 0; i < detail.tracks.length; i++)
          _TrackDiffRow(
            index: i,
            track: detail.tracks[i],
            pairing: pairings[i],
            extra: extra.contains(i),
          ),
        for (var i = 0; i < (candidate?.missingTitles.length ?? 0); i++)
          _MissingRow(index: i, title: candidate!.missingTitles[i]),
      ],
    );
  }

  Widget _headerRow(ThemeData theme) {
    final style = theme.textTheme.labelLarge;
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text('Current', style: style)),
          const SizedBox(width: 8),
          Expanded(child: Text('Proposed', style: style)),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _TrackDiffRow extends StatelessWidget {
  const _TrackDiffRow({
    required this.index,
    required this.track,
    required this.pairing,
    required this.extra,
  });

  final int index;
  final ReviewTrack track;
  final CandidatePairing? pairing;
  final bool extra;

  static String _numbered(int? number, String title, String? artist) {
    final prefix = number == null ? '' : '$number. ';
    final suffix = artist == null ? '' : ' ($artist)';
    return '$prefix$title$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paired = pairing;
    final pid = track.pid;
    return Semantics(
      identifier: SemanticsIds.diffRow(index),
      child: Container(
        key: ValueKey(SemanticsIds.diffRow(index)),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _numbered(track.trackNo, track.title, track.artist),
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: extra
                  ? Text(
                      'Extra file, no counterpart',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    )
                  : paired == null
                  ? Text(
                      'Unmatched',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Text(
                      _numbered(paired.position, paired.title, paired.artist),
                      style: theme.textTheme.bodySmall,
                    ),
            ),
            SizedBox(
              width: 40,
              child: pid == null
                  ? null
                  : Semantics(
                      identifier: SemanticsIds.trackMenu(pid),
                      label: 'Track actions',
                      button: true,
                      child: PopupMenuButton<String>(
                        key: ValueKey(SemanticsIds.trackMenu(pid)),
                        tooltip: 'Track actions',
                        icon: const Icon(Icons.more_vert, size: 18),
                        onSelected: (action) {
                          if (action == 'edit') {
                            context.push(WaxRoute.metadata(pid));
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'edit',
                            child: Semantics(
                              identifier: SemanticsIds.editMetadata(pid),
                              child: Text(
                                'Edit metadata',
                                key: ValueKey(SemanticsIds.editMetadata(pid)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingRow extends StatelessWidget {
  const _MissingRow({required this.index, required this.title});

  final int index;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      identifier: SemanticsIds.diffMissing(index),
      child: Container(
        key: ValueKey(SemanticsIds.diffMissing(index)),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Missing locally',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: theme.textTheme.bodySmall)),
            const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }
}
