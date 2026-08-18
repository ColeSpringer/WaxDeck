import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
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
      title: context.l10n.reviewEntryTitle,
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
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      final warnings = await ref
          .read(reviewEntryProvider(widget.entryId).notifier)
          .decide(action, candidateMbid: candidateMbid);
      // The server's own words: a warning names the file or the field it
      // is about, which no table sentence can.
      if (warnings.isNotEmpty) messenger.show(warnings.join('\n'));
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
    }
  }

  Future<void> _revert() async {
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await ref.read(reviewEntryProvider(widget.entryId).notifier).revert();
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
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
          title: context.l10n.reviewEntryLoadError,
          message: context.explain(error),
          onRetry: () => ref.invalidate(reviewEntryProvider(widget.entryId)),
        ),
      ),
      _ => const SkeletonShapes(shape: SkeletonShape.detail),
    };
  }

  Widget _body(BuildContext context, ReviewEntryDetail detail) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
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
                l10n.reviewIdentifyingLong,
                style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ],
        // Ungated on poor results: a right-looking guess can still be
        // the wrong release. Music only, because the identify worker
        // returns immediately for anything else.
        if (detail.status == 'pending' &&
            detail.mediaType == MediaType.music) ...<Widget>[
          const SizedBox(height: WaxSpace.s16),
          _IdentifySearch(
            key: ValueKey<String>(widget.entryId),
            entryId: widget.entryId,
            stored: detail.identifyOverride,
            suggested: detail.suggested,
            busy: detail.identifying,
            // A track title names one track, so the server ignores it
            // on a unit of several. Not drawn where it would do
            // nothing.
            oneTrack: detail.trackCount == 1,
          ),
        ],
        const SizedBox(height: WaxSpace.s20),
        SectionHeader(title: l10n.reviewCandidatesTitle),
        // Two different empty lists: one searched and found nothing, one
        // never searched at all. Saying so is the difference between a
        // dead end and an answer.
        if (detail.candidates.isEmpty)
          if (detail.identifyDeclined)
            Semantics(
              identifier: SemanticsIds.reviewIdentifySkipped,
              container: true,
              // The usual one is already filed; a pending one is an
              // import that refused, and needs telling what to do.
              child: EmptyState(
                glyph: WaxIcons.search,
                title: l10n.reviewSkippedTitle,
                message: detail.status == 'pending'
                    ? l10n.reviewSkippedPending
                    : l10n.reviewSkippedDecided,
              ),
            )
          else
            EmptyState(
              glyph: WaxIcons.search,
              title: l10n.reviewNoCandidatesTitle,
              message: l10n.reviewNoCandidatesMessage,
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
        SectionHeader(title: l10n.reviewTracksTitle),
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
    final l10n = context.l10n;
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
                      // Worded, because the filter chips one screen back
                      // are, and a raw token here would disagree with
                      // them. The row's monospace chip keeps the token.
                      l10n.reviewDecidedStatus(
                        reviewStatusLabel(l10n, detail.status),
                      ),
                      style: WaxType.label.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  if (revertible)
                    WaxButton(
                      label: l10n.reviewActionRevert,
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
                    label: l10n.reviewActionApprove,
                    semanticsId: SemanticsIds.reviewApprove,
                    onPressed: candidate == null
                        ? null
                        : () => onDecide(
                            'approve',
                            candidateMbid: candidate!.mbid,
                          ),
                  ),
                  WaxButton(
                    label: l10n.reviewActionAsIs,
                    kind: WaxButtonKind.tonal,
                    semanticsId: SemanticsIds.reviewAsIs,
                    onPressed: () => onDecide('as-is'),
                  ),
                  WaxButton(
                    label: l10n.reviewActionUnofficial,
                    kind: WaxButtonKind.tonal,
                    semanticsId: SemanticsIds.reviewUnofficial,
                    onPressed: () => onDecide('unofficial'),
                  ),
                  WaxButton(
                    label: l10n.reviewActionSkip,
                    kind: WaxButtonKind.text,
                    semanticsId: SemanticsIds.reviewSkip,
                    onPressed: () => onDecide('skip'),
                  ),
                  if (detail.origin == 'upload')
                    WaxButton(
                      label: l10n.reviewActionDiscard,
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

/// Type what to search for when the files' tags are not what the
/// release is called. Open from the start when something is stored,
/// which is the only way to see and undo it.
class _IdentifySearch extends ConsumerStatefulWidget {
  const _IdentifySearch({
    super.key,
    required this.entryId,
    required this.stored,
    required this.suggested,
    required this.busy,
    required this.oneTrack,
  });

  final String entryId;

  /// What the last re-identify searched for; the fields open on it.
  final ReviewOverride? stored;

  /// What the matching parse read out of the source title. Fills the
  /// fields [stored] leaves empty, and says so above them: a guess
  /// offered as a starting point, not something anybody asserted.
  final ReviewOverride? suggested;

  /// Identification is running, so a second Search again would queue
  /// behind the first for no benefit.
  final bool busy;

  /// The unit is a single file, so a track title is worth asking for.
  final bool oneTrack;

  @override
  ConsumerState<_IdentifySearch> createState() => _IdentifySearchState();
}

class _IdentifySearchState extends ConsumerState<_IdentifySearch> {
  late final _artist = TextEditingController(text: _seedOf(widget, _artistOf));
  late final _album = TextEditingController(text: _seedOf(widget, _albumOf));
  late final _title = TextEditingController(text: _seedOf(widget, _titleOf));
  late bool _open = widget.stored != null || widget.suggested != null;

  static String? _artistOf(ReviewOverride? o) => o?.artist;
  static String? _albumOf(ReviewOverride? o) => o?.album;
  static String? _titleOf(ReviewOverride? o) => o?.title;

  /// What one field opens on: the stored override wherever it has a
  /// value, the suggestion where it does not.
  static String _seedOf(
    _IdentifySearch w,
    String? Function(ReviewOverride?) of,
  ) {
    final stored = of(w.stored);
    if (stored != null && stored.isNotEmpty) return stored;
    return of(w.suggested) ?? '';
  }

  @override
  void didUpdateWidget(covariant _IdentifySearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    _adopt(_artist, oldWidget, _artistOf);
    _adopt(_album, oldWidget, _albumOf);
    _adopt(_title, oldWidget, _titleOf);
  }

  /// Takes a value the server changed, into a field nobody has
  /// touched - read strictly as "still reads what it was last handed",
  /// because a refetch must never delete what somebody is typing.
  void _adopt(
    TextEditingController c,
    _IdentifySearch old,
    String? Function(ReviewOverride?) of,
  ) {
    final was = _seedOf(old, of);
    final now = _seedOf(widget, of);
    if (was == now || c.text != was) return;
    c.text = now;
  }

  @override
  void dispose() {
    _artist.dispose();
    _album.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    // The same gate the button carries: Enter is the keyboard's version
    // of pressing it, not a way around it.
    if (widget.busy) return;
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await ref
          .read(reviewEntryProvider(widget.entryId).notifier)
          .reidentify(
            artist: _artist.text,
            album: _album.text,
            title: widget.oneTrack ? _title.text : '',
          );
    } on WaxDeckApiException catch (e) {
      // Names it typed, so the server's own refusal is what says which
      // of them it could not act on.
      messenger.show(explainRefusal(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return Semantics(
      identifier: SemanticsIds.reviewIdentifyGroup,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          WaxButton(
            label: l10n.reviewSearchToggle,
            kind: WaxButtonKind.text,
            icon: _open ? WaxIcons.collapse : WaxIcons.expand,
            semanticsId: SemanticsIds.reviewIdentifyToggle,
            onPressed: () => setState(() => _open = !_open),
          ),
          if (_open) ...<Widget>[
            const SizedBox(height: WaxSpace.s8),
            Text(
              widget.stored == null && widget.suggested != null
                  ? l10n.reviewSearchSuggested
                  : l10n.reviewSearchStored,
              style: WaxType.caption.copyWith(color: colors.textTertiary),
            ),
            const SizedBox(height: WaxSpace.s12),
            WaxTextField(
              label: l10n.reviewFieldArtist,
              controller: _artist,
              semanticsId: SemanticsIds.reviewIdentifyField('artist'),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: WaxSpace.s8),
            WaxTextField(
              label: l10n.reviewFieldAlbum,
              controller: _album,
              semanticsId: SemanticsIds.reviewIdentifyField('album'),
              onSubmitted: (_) => _search(),
            ),
            if (widget.oneTrack) ...<Widget>[
              const SizedBox(height: WaxSpace.s8),
              WaxTextField(
                label: l10n.reviewFieldTitle,
                controller: _title,
                semanticsId: SemanticsIds.reviewIdentifyField('title'),
                onSubmitted: (_) => _search(),
              ),
            ],
            const SizedBox(height: WaxSpace.s12),
            WaxButton(
              label: l10n.reviewSearchAgain,
              kind: WaxButtonKind.tonal,
              semanticsId: SemanticsIds.reviewIdentifySubmit,
              // Empty fields are a Search again too: that is how a
              // stored override is cleared and the plain derivation run.
              onPressed: widget.busy ? null : _search,
            ),
          ],
        ],
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
    final l10n = context.l10n;
    final uploadedBy = detail.uploadedBy;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                detail.title ?? l10n.reviewUntitled,
                style: WaxType.titleEntity.copyWith(color: colors.textPrimary),
              ),
              if (detail.artist != null)
                Text(
                  detail.artist!,
                  style: WaxType.body.copyWith(color: colors.textSecondary),
                ),
              const SizedBox(height: WaxSpace.s4),
              Text(
                uploadedBy == null
                    ? l10n.reviewHeaderFacts(
                        detail.trackCount,
                        reviewOriginLabel(l10n, detail.origin),
                      )
                    : l10n.reviewHeaderFactsBy(
                        detail.trackCount,
                        reviewOriginLabel(l10n, detail.origin),
                        uploadedBy,
                      ),
                style: WaxType.caption.copyWith(color: colors.textTertiary),
              ),
              // The way back to where the files came from. The origin
              // line named the upload and stopped there, and the uploads
              // screen has linked forward to its entry all along - so
              // this was the one direction a curator had to navigate by
              // hand, from the surface they are actually standing on.
              // The sessions list rather than one session: the entry
              // carries no upload id, and the list is where a batch's
              // several sessions are together anyway.
              //
              // Pushed, which is the mirror of the link pointing this
              // way: the sessions list is not declared under the queue,
              // so `go` would drop whatever the entry was opened from
              // and leave back with nothing to answer.
              if (detail.origin == 'upload')
                Padding(
                  padding: const EdgeInsets.only(top: WaxSpace.s4),
                  child: WaxButton(
                    label: l10n.reviewOpenUploads,
                    kind: WaxButtonKind.text,
                    semanticsId: SemanticsIds.reviewOpenUploads,
                    onPressed: () => context.pushOnce(WaxRoute.uploads),
                  ),
                ),
            ],
          ),
        ),
        if (onClose != null)
          WaxIconButton(
            glyph: WaxIcons.close,
            label: l10n.reviewPaneClose,
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
        label: context.l10n.reviewCandidateSpoken(
          candidate.title,
          candidate.artist,
        ),
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
                          context.l10n.reviewCandidateTitleLine(
                            candidate.title,
                            candidate.artist,
                          ),
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
    final l10n = context.l10n;
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
                _headerRow(l10n, colors),
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

  Widget _headerRow(AppLocalizations l10n, WaxColors colors) {
    final style = WaxType.overline.copyWith(color: colors.textSecondary);
    return Container(
      color: colors.surface2,
      padding: const EdgeInsets.symmetric(
        horizontal: WaxSpace.s12,
        vertical: WaxSpace.s8,
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(l10n.reviewDiffCurrent, style: style)),
          const SizedBox(width: WaxSpace.s8),
          Expanded(child: Text(l10n.reviewDiffProposed, style: style)),
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

  static String _numbered(
    AppLocalizations l10n,
    int? number,
    String title,
    String? artist,
  ) {
    final numbered = number == null
        ? title
        : l10n.reviewTrackNumbered('$number', title);
    return artist == null
        ? numbered
        : l10n.reviewTrackWithArtist(numbered, artist);
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
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
                _numbered(l10n, track.trackNo, track.title, track.artist),
                style: WaxType.bodySmall.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(width: WaxSpace.s8),
            Expanded(
              child: extra
                  ? Text(
                      l10n.reviewDiffExtra,
                      style: WaxType.bodySmall.copyWith(color: colors.error),
                    )
                  : paired == null
                  ? Text(
                      l10n.reviewDiffUnmatched,
                      style: WaxType.bodySmall.copyWith(
                        color: colors.textTertiary,
                      ),
                    )
                  : Text(
                      _numbered(
                        l10n,
                        paired.position,
                        paired.title,
                        paired.artist,
                      ),
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
                      label: l10n.reviewTrackMenu,
                      size: 16,
                      semanticsId: SemanticsIds.trackMenu(pid),
                      items: <WaxMenuItem<String>>[
                        WaxMenuItem<String>(
                          value: 'edit',
                          label: l10n.reviewEditMetadata,
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
                context.l10n.reviewDiffMissing,
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
