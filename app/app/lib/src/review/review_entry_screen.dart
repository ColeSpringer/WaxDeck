import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'review_controller.dart';

/// One review entry as a page of its own, below the width that can hold
/// the queue beside it.
class ReviewEntryScreen extends StatelessWidget {
  const ReviewEntryScreen({super.key, required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context) {
    return WaxScaffold(
      title: 'Review entry',
      largeTitle: false,
      semanticsId: SemanticsIds.adminReviewEntry,
      onBack: () => context.leave(fallback: WaxRoute.review),
      // A filling sliver, not a body: the view pins its decision bar
      // under a scroll of its own, which needs a bounded height.
      slivers: <Widget>[
        SliverFillRemaining(
          hasScrollBody: true,
          child: ReviewEntryView(entryId: entryId),
        ),
      ],
    );
  }
}

/// One review entry: ranked candidates, the file-by-file diff, and the
/// decision bar. A view rather than a screen because it is both the
/// pane beside the queue and the page that replaces it.
class ReviewEntryView extends ConsumerStatefulWidget {
  const ReviewEntryView({super.key, required this.entryId, this.onClose});

  final String entryId;

  /// Drawn as a close control when the view is a pane. The page has the
  /// scaffold's own back control and passes null.
  final VoidCallback? onClose;

  @override
  ConsumerState<ReviewEntryView> createState() => _ReviewEntryViewState();
}

class _ReviewEntryViewState extends ConsumerState<ReviewEntryView> {
  ReviewCandidate? _selectedCandidate(ReviewEntryDetail detail) {
    if (detail.candidates.isEmpty) return null;
    final chosen = ref.watch(selectedCandidateProvider(widget.entryId));
    return detail.candidates.where((c) => c.mbid == chosen).firstOrNull ??
        detail.candidates.first;
  }

  Future<void> _decide(String action, {String? candidateMbid}) async {
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      final warnings = await ref
          .read(reviewEntryProvider(widget.entryId).notifier)
          .decide(action, candidateMbid: candidateMbid);
      if (warnings.isNotEmpty) messenger.show(warnings.join('\n'));
    } on WaxDeckApiException catch (e) {
      messenger.show(e.message);
    }
  }

  Future<void> _revert() async {
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await ref.read(reviewEntryProvider(widget.entryId).notifier).revert();
    } on WaxDeckApiException catch (e) {
      messenger.show(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(reviewEntryProvider(widget.entryId));
    return switch (detail) {
      AsyncData(:final value) => Column(
        children: <Widget>[
          Expanded(child: _body(context, value)),
          _ActionBar(
            detail: value,
            candidate: _selectedCandidate(value),
            onDecide: _decide,
            onRevert: _revert,
          ),
        ],
      ),
      AsyncError(:final error) => Padding(
        padding: const EdgeInsets.all(WaxSpace.s16),
        child: ErrorState(
          title: 'Could not load the entry',
          message: error is WaxDeckApiException
              ? error.message
              : 'Something went wrong reading it.',
          onRetry: () => ref.invalidate(reviewEntryProvider(widget.entryId)),
        ),
      ),
      _ => const SkeletonShapes(shape: SkeletonShape.detail),
    };
  }

  Widget _body(BuildContext context, ReviewEntryDetail detail) {
    final colors = WaxColors.of(context);
    final candidate = _selectedCandidate(detail);
    return ListView(
      padding: const EdgeInsets.all(WaxSpace.s16),
      children: <Widget>[
        _Header(detail: detail, onClose: widget.onClose),
        if (detail.identifying) ...<Widget>[
          const SizedBox(height: WaxSpace.s16),
          Row(
            children: <Widget>[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: WaxSpace.s8),
              Text(
                'Identifying: candidate lookup is still running',
                style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ],
        const SizedBox(height: WaxSpace.s20),
        const SectionHeader(title: 'Candidates'),
        if (detail.candidates.isEmpty)
          const EmptyState(
            glyph: WaxIcons.search,
            title: 'No candidates found',
            message:
                'Nothing in the sources matched what these files claim. '
                'Keep them as they are, or skip and try again later.',
          )
        else
          for (final c in detail.candidates)
            _CandidateTile(
              candidate: c,
              selected: c.mbid == candidate?.mbid,
              onTap: () => ref
                  .read(selectedCandidateProvider(widget.entryId).notifier)
                  .select(c.mbid),
            ),
        const SizedBox(height: WaxSpace.s20),
        const SectionHeader(title: 'Tracks'),
        _DiffTable(detail: detail, candidate: candidate),
      ],
    );
  }
}

/// The decision bar. Pinned under the scroll rather than in it: it is
/// what somebody came here to press, and a bar that scrolls away is a
/// bar that has to be hunted for on every entry.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.detail,
    required this.candidate,
    required this.onDecide,
    required this.onRevert,
  });

  final ReviewEntryDetail detail;
  final ReviewCandidate? candidate;
  final void Function(String action, {String? candidateMbid}) onDecide;
  final VoidCallback onRevert;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final decided = detail.status != 'pending';
    final revertible =
        detail.status == 'applied' || detail.status == 'auto-applied';
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        border: Border(top: BorderSide(color: colors.hairline)),
      ),
      padding: const EdgeInsets.all(WaxSpace.s12),
      child: SafeArea(
        top: false,
        child: decided
            ? Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Decided: ${detail.status}',
                      style: WaxType.label.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  if (revertible)
                    WaxButton(
                      label: 'Revert',
                      kind: WaxButtonKind.tonal,
                      semanticsId: SemanticsIds.reviewRevert,
                      onPressed: onRevert,
                    ),
                ],
              )
            : Wrap(
                spacing: WaxSpace.s8,
                runSpacing: WaxSpace.s8,
                children: <Widget>[
                  WaxButton(
                    label: 'Approve',
                    semanticsId: SemanticsIds.reviewApprove,
                    onPressed: candidate == null
                        ? null
                        : () => onDecide(
                            'approve',
                            candidateMbid: candidate!.mbid,
                          ),
                  ),
                  WaxButton(
                    label: 'Keep as is',
                    kind: WaxButtonKind.tonal,
                    semanticsId: SemanticsIds.reviewAsIs,
                    onPressed: () => onDecide('as-is'),
                  ),
                  WaxButton(
                    label: 'Mark unofficial',
                    kind: WaxButtonKind.tonal,
                    semanticsId: SemanticsIds.reviewUnofficial,
                    onPressed: () => onDecide('unofficial'),
                  ),
                  WaxButton(
                    label: 'Skip',
                    kind: WaxButtonKind.text,
                    semanticsId: SemanticsIds.reviewSkip,
                    onPressed: () => onDecide('skip'),
                  ),
                  if (detail.origin == 'upload')
                    WaxButton(
                      label: 'Discard',
                      kind: WaxButtonKind.destructive,
                      semanticsId: SemanticsIds.reviewDiscard,
                      onPressed: () => onDecide('discard'),
                    ),
                ],
              ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.detail, this.onClose});

  final ReviewEntryDetail detail;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final uploadedBy = detail.uploadedBy;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                detail.title ?? 'Untitled',
                style: WaxType.titleEntity.copyWith(color: colors.textPrimary),
              ),
              if (detail.artist != null)
                Text(
                  detail.artist!,
                  style: WaxType.body.copyWith(color: colors.textSecondary),
                ),
              const SizedBox(height: WaxSpace.s4),
              Text(
                '${detail.trackCount} tracks, ${detail.origin}'
                '${uploadedBy == null ? '' : ' by $uploadedBy'}',
                style: WaxType.caption.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ),
        if (onClose != null)
          WaxIconButton(
            glyph: WaxIcons.close,
            label: 'Close the entry',
            semanticsId: SemanticsIds.reviewPaneClose,
            onPressed: onClose,
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
    final colors = WaxColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: WaxSpace.s8),
      child: WaxTappable(
        label: '${candidate.title} by ${candidate.artist}',
        semanticsId: SemanticsIds.candidate(candidate.mbid),
        selected: selected,
        borderRadius: WaxRadius.card,
        onPressed: onTap,
        // WaxTappable adds no gesture by design, so the ink is ours or
        // the tile announces as a button and answers no pointer.
        child: Material(
          color: selected ? colors.accentContainer : colors.surface1,
          borderRadius: WaxRadius.card,
          child: InkWell(
            onTap: onTap,
            borderRadius: WaxRadius.card,
            child: Container(
              padding: const EdgeInsets.all(WaxSpace.s12),
              decoration: BoxDecoration(
                borderRadius: WaxRadius.card,
                border: Border.all(
                  color: selected ? colors.accent : colors.hairline,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        '${candidate.similarityPct.round()}%',
                        style: WaxType.monoData.copyWith(
                          color: selected
                              ? colors.onAccentContainer
                              : colors.accent,
                        ),
                      ),
                      const SizedBox(width: WaxSpace.s12),
                      Expanded(
                        child: Text(
                          '${candidate.title}, ${candidate.artist}',
                          style: WaxType.titleItem.copyWith(
                            color: selected
                                ? colors.onAccentContainer
                                : colors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (selected)
                        WaxIcon(
                          WaxIcons.check,
                          size: 16,
                          color: colors.onAccentContainer,
                        ),
                    ],
                  ),
                  if (_subtitle.isNotEmpty)
                    Text(
                      _subtitle,
                      style: WaxType.caption.copyWith(
                        color: selected
                            ? colors.onAccentContainer
                            : colors.textTertiary,
                      ),
                    ),
                  if (candidate.components.isNotEmpty) ...<Widget>[
                    const SizedBox(height: WaxSpace.s8),
                    Wrap(
                      spacing: WaxSpace.s16,
                      runSpacing: WaxSpace.s4,
                      children: <Widget>[
                        for (final component in candidate.components)
                          _ComponentBar(
                            component: component,
                            selected: selected,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
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
  const _ComponentBar({required this.component, required this.selected});

  final CandidateComponent component;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final closeness = (1 - component.distance).clamp(0.0, 1.0);
    final tint = selected ? colors.onAccentContainer : colors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(component.name, style: WaxType.caption.copyWith(color: tint)),
        const SizedBox(width: WaxSpace.s4),
        SizedBox(
          width: 48,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(WaxRadius.r6),
            child: LinearProgressIndicator(
              value: closeness,
              minHeight: 4,
              backgroundColor: colors.surface3,
              valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
            ),
          ),
        ),
        const SizedBox(width: WaxSpace.s4),
        Text(
          '${(closeness * 100).round()}%',
          style: WaxType.monoData.copyWith(color: tint),
        ),
      ],
    );
  }
}

/// The side-by-side diff: one row per local file, then the candidate
/// tracks missing locally. Columns at every width rather than a
/// [WaxTable]: which line faces which is the whole content.
class _DiffTable extends StatelessWidget {
  const _DiffTable({required this.detail, required this.candidate});

  final ReviewEntryDetail detail;
  final ReviewCandidate? candidate;

  static const _minWidth = 420.0;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final pairings = <int, CandidatePairing>{
      for (final p in candidate?.pairings ?? const <CandidatePairing>[])
        p.trackIndex: p,
    };
    final extra = (candidate?.extraTrackIndexes ?? const <int>[]).toSet();
    return Container(
      decoration: BoxDecoration(
        borderRadius: WaxRadius.card,
        border: Border.all(color: colors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      // Measured outside the scroll view, where the width is still
      // bounded: sizing to the window would lay the diff out at 1600
      // inside a 700-pixel pane and push Proposed off the edge.
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: _minWidth,
              maxWidth: constraints.maxWidth < _minWidth
                  ? _minWidth
                  : constraints.maxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _headerRow(colors),
                for (var i = 0; i < detail.tracks.length; i++)
                  _TrackDiffRow(
                    index: i,
                    track: detail.tracks[i],
                    pairing: pairings[i],
                    extra: extra.contains(i),
                    striped: i.isOdd,
                  ),
                for (var i = 0; i < (candidate?.missingTitles.length ?? 0); i++)
                  _MissingRow(index: i, title: candidate!.missingTitles[i]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerRow(WaxColors colors) {
    final style = WaxType.overline.copyWith(color: colors.textSecondary);
    return Container(
      color: colors.surface2,
      padding: const EdgeInsets.symmetric(
        horizontal: WaxSpace.s12,
        vertical: WaxSpace.s8,
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: Text('Current', style: style)),
          const SizedBox(width: WaxSpace.s8),
          Expanded(child: Text('Proposed', style: style)),
          const SizedBox(width: WaxSpace.s40),
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
    required this.striped,
  });

  final int index;
  final ReviewTrack track;
  final CandidatePairing? pairing;
  final bool extra;
  final bool striped;

  static String _numbered(int? number, String title, String? artist) {
    final prefix = number == null ? '' : '$number. ';
    final suffix = artist == null ? '' : ' ($artist)';
    return '$prefix$title$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final paired = pairing;
    final pid = track.pid;
    return Semantics(
      identifier: SemanticsIds.diffRow(index),
      container: true,
      child: Container(
        color: striped ? colors.surface1 : Colors.transparent,
        padding: const EdgeInsets.symmetric(
          horizontal: WaxSpace.s12,
          vertical: WaxSpace.s4,
        ),
        constraints: const BoxConstraints(minHeight: 36),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _numbered(track.trackNo, track.title, track.artist),
                style: WaxType.bodySmall.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(width: WaxSpace.s8),
            Expanded(
              child: extra
                  ? Text(
                      'Extra file, no counterpart',
                      style: WaxType.bodySmall.copyWith(color: colors.error),
                    )
                  : paired == null
                  ? Text(
                      'Unmatched',
                      style: WaxType.bodySmall.copyWith(
                        color: colors.textTertiary,
                      ),
                    )
                  : Text(
                      _numbered(paired.position, paired.title, paired.artist),
                      style: WaxType.bodySmall.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
            ),
            SizedBox(
              width: 40,
              child: pid == null
                  ? null
                  : WaxMenuButton<String>(
                      glyph: WaxIcons.moreVertical,
                      label: 'Track actions',
                      size: 16,
                      semanticsId: SemanticsIds.trackMenu(pid),
                      items: <WaxMenuItem<String>>[
                        WaxMenuItem<String>(
                          value: 'edit',
                          label: 'Edit metadata',
                          glyph: WaxIcons.edit,
                          semanticsId: SemanticsIds.editMetadata(pid),
                        ),
                      ],
                      // An editor opened on one row, pushed so closing
                      // it returns to the entry being reviewed. The
                      // location still resolves for anyone who types it.
                      onSelected: (_) => context.push(WaxRoute.metadata(pid)),
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
    final colors = WaxColors.of(context);
    return Semantics(
      identifier: SemanticsIds.diffMissing(index),
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: WaxSpace.s12,
          vertical: WaxSpace.s4,
        ),
        constraints: const BoxConstraints(minHeight: 36),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Missing locally',
                style: WaxType.bodySmall.copyWith(color: colors.error),
              ),
            ),
            const SizedBox(width: WaxSpace.s8),
            Expanded(
              child: Text(
                title,
                style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
              ),
            ),
            const SizedBox(width: WaxSpace.s40),
          ],
        ),
      ),
    );
  }
}
