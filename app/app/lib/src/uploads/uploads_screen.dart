import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../media_view.dart';
import '../providers.dart';
import '../shell/async_box_face.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'add_to_library.dart';
import 'audio_drop_area.dart';
import 'file_picker_port.dart';
import 'upload_phase.dart';
import 'uploads_controller.dart';

/// The caller's upload sessions, the quota header, and drag-and-drop.
/// Pick affordances need a [FilePickerPort] and upload rights; without
/// either this is a read-only session list.
class UploadsScreen extends ConsumerWidget {
  const UploadsScreen({super.key});

  Future<void> _retry(AppLocalizations l10n, WidgetRef ref, String id) async {
    try {
      await ref.read(uploadsProvider.notifier).retry(id);
    } on WaxDeckApiException catch (e) {
      ref.read(shellMessengerProvider.notifier).show(explainError(l10n, e));
    }
  }

  Future<void> _discard(
    BuildContext context,
    WidgetRef ref,
    UploadSession upload,
  ) async {
    final l10n = context.l10n;
    final confirmed = await showTypedConfirm(
      context,
      title: l10n.uploadsDiscardTitle,
      message: l10n.uploadsDiscardBody(upload.fileName),
      confirmWord: l10n.uploadsDiscardWord,
      confirmLabel: l10n.uploadsDiscardConfirm,
      fieldSemanticsId: SemanticsIds.confirmField,
      confirmSemanticsId: SemanticsIds.confirmAccept,
      cancelSemanticsId: SemanticsIds.confirmCancel,
    );
    if (!confirmed) return;
    try {
      await ref.read(uploadsProvider.notifier).discard(upload.id);
    } on WaxDeckApiException catch (e) {
      ref.read(shellMessengerProvider.notifier).show(explainError(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final uploads = ref.watch(uploadsProvider);
    final picker = ref.watch(filePickerProvider);
    final canUpload =
        ref.watch(authControllerProvider).value?.user?.uploadEnabled ?? false;
    final l10n = context.l10n;
    // Around the whole screen: the copy says anywhere on this page, and
    // a zone inside the scroll would refuse a drop over the bar.
    return AudioDropArea(
      enabled: canUpload,
      formats: dropFormats(ref),
      hint: l10n.uploadsDropHint,
      onDropped: (files) => uploadPickedFiles(context, ref, files),
      onSkipped: ({required unsupported, required drm, required nothingKept}) =>
          reportSkippedFiles(
            ref.read(shellMessengerProvider.notifier),
            l10n,
            unsupported: unsupported,
            drm: drm,
            nothingKept: nothingKept,
          ),
      child: WaxScaffold(
        title: l10n.uploadsTitle,
        largeTitle: false,
        semanticsId: SemanticsIds.uploadsScreen,
        // A way out, which a destination does not need and this is not
        // one any more: it is opened from the add sheet, from a
        // notification, and from a review entry's origin line, and it
        // lights no row for a visitor to press again. Popping where
        // something pushed it, home where a link did.
        onBack: () => context.leave(),
        actions: <Widget>[
          if (picker != null && canUpload)
            WaxIconButton(
              glyph: WaxIcons.add,
              label: l10n.uploadsPick,
              semanticsId: SemanticsIds.uploadPick,
              onPressed: () => pickAndUpload(context, ref, picker),
            ),
          if (canUpload)
            WaxIconButton(
              glyph: WaxIcons.downloads,
              label: l10n.uploadsFromUrl,
              semanticsId: SemanticsIds.uploadFromUrl,
              onPressed: () => acquireFromUrl(context, ref),
            ),
        ],
        body: Padding(
          padding: sizeClass.gutter.add(
            const EdgeInsets.only(bottom: WaxSpace.s32),
          ),
          child: AsyncBoxFace<UploadsState>(
            state: uploads,
            errorTitle: l10n.uploadsLoadError,
            onRetry: () => ref.invalidate(uploadsProvider),
            builder: (context, value) => _body(context, ref, value, canUpload),
          ),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    UploadsState state,
    bool canUpload,
  ) {
    final quota = state.quota;
    final l10n = context.l10n;
    final live = ref.watch(liveTransfersProvider);
    final creates = ref.watch(uploadCreatesProvider);
    UploadPhase phaseOf(UploadSession upload) => uploadPhaseOf(
      upload,
      live[upload.id],
      creating: creates.mayHaveOpened(upload.id),
    );
    // When each row sent from elsewhere would have gone a whole window
    // without the server taking a byte, if nothing more arrived: that row
    // is read again then, alone, so one nobody is sending any more is
    // offered for discard only once a read says so.
    final clock = ref.read(monotonicClockProvider);
    final quiet = <String, Duration>{
      for (final upload in state.uploads)
        if (phaseOf(upload) is UploadElsewhere)
          if (state.readAt[upload.id] case final read?)
            upload.id: read + uploadIdleWindow - upload.idle,
    };
    return _ReadAgainAt(
      at: quiet.isEmpty ? null : quiet.values.reduce((a, b) => a < b ? a : b),
      clock: clock,
      onDue: (due) {
        unawaited(
          ref.read(uploadsProvider.notifier).readAgain([
            for (final MapEntry(key: id, value: at) in quiet.entries)
              if (at <= due) id,
          ]),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (quota != null) _QuotaHeader(quota: quota),
          const SizedBox(height: WaxSpace.s24),
          if (state.uploads.isEmpty)
            EmptyState(
              glyph: WaxIcons.add,
              title: l10n.uploadsEmptyTitle,
              message: canUpload ? null : l10n.uploadsNoPermissionEmptyMessage,
            )
          else ...<Widget>[
            for (final group in _grouped(state))
              _BatchGroup(
                key: group.key,
                group: group,
                phaseOf: phaseOf,
                onRetry: (id) => _retry(l10n, ref, id),
                onDiscard: (upload) => _discard(context, ref, upload),
              ),
            if (state.hasMore)
              LoadMoreFooter(
                label: l10n.uploadsLoadMore,
                loading: state.loadingMore,
                semanticsId: SemanticsIds.uploadsMore,
                padding: const EdgeInsets.only(top: WaxSpace.s16),
                onLoadMore: () => ref.read(uploadsProvider.notifier).loadMore(),
              ),
          ],
        ],
      ),
    );
  }

  /// Buckets each batch under one header at its newest member, because
  /// a concurrent solo upload can interleave the listing. Client-side
  /// only, so a batch across a page boundary still splits.
  static List<_Batch> _grouped(UploadsState state) {
    final byBatch = <String, List<UploadSession>>{};
    for (final upload in state.uploads) {
      final batchId = upload.batchId;
      if (batchId != null) byBatch.putIfAbsent(batchId, () => []).add(upload);
    }
    final out = <_Batch>[];
    final emitted = <String>{};
    for (final upload in state.uploads) {
      final batchId = upload.batchId;
      if (batchId == null) {
        out.add(_Batch(id: null, uploads: [upload]));
        continue;
      }
      if (!emitted.add(batchId)) continue;
      out.add(_Batch(id: batchId, uploads: byBatch[batchId]!));
    }
    return out;
  }
}

/// Calls [onDue] at [at] on [clock], a monotonic span, for as long as it
/// stands: whether a session another device was sending is still being
/// sent is a question only a fresh read answers. A read that changes
/// nothing (it failed) is asked for again every [_again]. [onDue] gets the
/// span on [clock] that counts as due, [_early] past now.
class _ReadAgainAt extends StatefulWidget {
  const _ReadAgainAt({
    required this.at,
    required this.clock,
    required this.onDue,
    required this.child,
  });

  final Duration? at;
  final Duration Function() clock;
  final void Function(Duration due) onDue;
  final Widget child;

  static const _again = Duration(seconds: 30);

  /// How far short of [at] a fire can land on [clock]: the VM rounds a
  /// timer's delay down to a whole millisecond, and a browser's clock is
  /// coarser still.
  static const _early = Duration(milliseconds: 50);

  @override
  State<_ReadAgainAt> createState() => _ReadAgainAtState();
}

class _ReadAgainAtState extends State<_ReadAgainAt> {
  Timer? _due;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(_ReadAgainAt old) {
    super.didUpdateWidget(old);
    if (old.at != widget.at) _arm();
  }

  void _arm() {
    _due?.cancel();
    final at = widget.at;
    _due = at == null ? null : Timer(at - widget.clock(), _fire);
  }

  void _fire() {
    if (!mounted) return;
    widget.onDue(widget.clock() + _ReadAgainAt._early);
    _due = Timer(_ReadAgainAt._again, _fire);
  }

  @override
  void dispose() {
    _due?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// One upload batch, or a solo session standing alone.
class _Batch {
  const _Batch({required this.id, required this.uploads});

  /// Null for a session that was uploaded on its own.
  final String? id;

  final List<UploadSession> uploads;

  /// The group's key, so its rows move with it when another lands above:
  /// Flutter resends a semantics node only when something besides its
  /// identifier changed, and every header and discard button reads alike.
  Key get key => ValueKey(
    id == null
        ? SemanticsIds.uploadRow(uploads.single.id)
        : SemanticsIds.uploadBatch(id!),
  );
}

class _BatchGroup extends StatelessWidget {
  const _BatchGroup({
    super.key,
    required this.group,
    required this.phaseOf,
    required this.onRetry,
    required this.onDiscard,
  });

  final _Batch group;
  final UploadPhase Function(UploadSession upload) phaseOf;
  final void Function(String id) onRetry;
  final void Function(UploadSession upload) onDiscard;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final batchId = group.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: WaxSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (batchId != null)
            Semantics(
              identifier: SemanticsIds.uploadBatch(batchId),
              container: true,
              child: Padding(
                padding: const EdgeInsets.only(bottom: WaxSpace.s8),
                child: Row(
                  children: <Widget>[
                    WaxIcon(
                      WaxIcons.albums,
                      size: 14,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: WaxSpace.s8),
                    Text(
                      context.l10n.uploadsBatch(group.uploads.length),
                      style: WaxType.overline.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          for (final upload in group.uploads)
            _UploadRow(
              key: ValueKey(SemanticsIds.uploadRow(upload.id)),
              upload: upload,
              phase: phaseOf(upload),
              onRetry: () => onRetry(upload.id),
              onDiscard: () => onDiscard(upload),
            ),
        ],
      ),
    );
  }
}

/// What is staged now against the cap. A pending-upload limit rather
/// than a storage cap.
class _QuotaHeader extends StatelessWidget {
  const _QuotaHeader({required this.quota});

  final UploadQuota quota;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final cap = quota.quotaBytes;
    final fraction = cap == null || cap <= 0
        ? null
        : (quota.bytesInUse / cap).clamp(0.0, 1.0);
    return Semantics(
      identifier: SemanticsIds.uploadQuota,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(WaxSpace.s16),
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: WaxRadius.card,
          border: Border.all(color: colors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.uploadsQuotaOverline,
              style: WaxType.overline.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: WaxSpace.s8),
            Text(
              cap == null
                  ? l10n.formatBytes(quota.bytesInUse)
                  : l10n.uploadsQuotaOf(
                      l10n.formatBytes(quota.bytesInUse),
                      l10n.formatBytes(cap),
                    ),
              style: WaxType.titleEntity.copyWith(
                color: fraction != null && fraction >= 1
                    ? colors.error
                    : colors.textPrimary,
              ),
            ),
            if (fraction != null) ...<Widget>[
              const SizedBox(height: WaxSpace.s8),
              WaxProgressBar(
                value: fraction,
                tone: fraction >= 1 ? colors.error : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UploadRow extends StatelessWidget {
  const _UploadRow({
    super.key,
    required this.upload,
    required this.phase,
    required this.onRetry,
    required this.onDiscard,
  });

  final UploadSession upload;
  final UploadPhase phase;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  /// What a duplicate matched: the item by title and artist where the
  /// uploader can see it, a sentence where they cannot. Once imported,
  /// a file whose audio the library held says the item kept its
  /// details, since it joined that item rather than becoming one.
  static String _duplicateMessage(
    AppLocalizations l10n,
    UploadSession upload,
    DuplicateWarning duplicate,
  ) {
    final what = duplicateWhat(l10n, duplicate);
    if (upload.state == 'imported' && duplicate.kind == 'content') {
      return l10n.uploadsDuplicateJoined(what);
    }
    return l10n.uploadsDuplicate(
      duplicateKindLabel(l10n, duplicate.kind),
      what,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final duplicate = upload.duplicate;
    final reviewEntryId = upload.reviewEntryId;
    final phase = this.phase;
    final discardable = switch (phase) {
      // Discarding one sent from elsewhere would fail that upload.
      UploadSealing() || UploadStarting() || UploadElsewhere() => false,
      UploadSettled(:final state) => state == 'staged',
      UploadSending() || UploadStalled() || UploadInterrupted() => true,
    };
    Widget status(Widget child) => Semantics(
      identifier: SemanticsIds.uploadPhase(upload.id),
      container: true,
      child: child,
    );
    final caption = WaxType.caption.copyWith(color: colors.textSecondary);
    return Semantics(
      identifier: SemanticsIds.uploadRow(upload.id),
      container: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: WaxSpace.s8),
        padding: const EdgeInsets.all(WaxSpace.s12),
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: WaxRadius.card,
          border: Border.all(color: colors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                DomainBadge(waxDomainOf(upload.mediaType), compact: true),
                const SizedBox(width: WaxSpace.s12),
                Expanded(
                  child: Text(
                    upload.fileName,
                    style: WaxType.titleItem.copyWith(
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: WaxSpace.s8),
                switch (phase) {
                  UploadStalled() => status(
                    Text(
                      l10n.uploadsTransferFailed,
                      style: WaxType.label.copyWith(color: colors.error),
                    ),
                  ),
                  UploadSettled(:final state) => status(CodecChip(state)),
                  UploadInterrupted() => const SizedBox.shrink(),
                  UploadSending() ||
                  UploadStarting() ||
                  UploadElsewhere() ||
                  UploadSealing() => CodecChip(upload.state),
                },
                if (phase is UploadStalled)
                  WaxIconButton(
                    glyph: WaxIcons.refresh,
                    label: l10n.uploadsRetry,
                    size: 16,
                    semanticsId: SemanticsIds.uploadRetry(upload.id),
                    onPressed: onRetry,
                  ),
                if (discardable)
                  WaxIconButton(
                    glyph: WaxIcons.delete,
                    label: l10n.uploadsDiscardRow,
                    size: 16,
                    semanticsId: SemanticsIds.uploadDelete(upload.id),
                    onPressed: onDiscard,
                  ),
              ],
            ),
            if (switch (phase) {
                  UploadSending(:final sent, :final total, :final retrying) => (
                    sent,
                    total,
                    retrying,
                  ),
                  UploadStarting(:final total) => (0, total, false),
                  UploadElsewhere(:final received, :final total) => (
                    received,
                    total,
                    false,
                  ),
                  _ => null,
                }
                case (final sent, final total, final retrying)) ...<Widget>[
              const SizedBox(height: WaxSpace.s8),
              WaxProgressBar(value: total == 0 ? null : sent / total),
              const SizedBox(height: WaxSpace.s4),
              status(
                Text(switch ((retrying, total)) {
                  (true, _) => l10n.uploadsReconnecting,
                  (false, 0) => l10n.uploadsReceiving,
                  (false, _) => l10n.uploadsReceivedOf(
                    sent * 100 ~/ total,
                    l10n.formatBytes(total),
                  ),
                }, style: caption),
              ),
            ],
            if (phase case UploadSealing(:final unreachable)) ...<Widget>[
              const SizedBox(height: WaxSpace.s8),
              const WaxProgressBar(value: 1),
              const SizedBox(height: WaxSpace.s4),
              status(
                Text(
                  unreachable
                      ? l10n.uploadsFinishingUnreachable
                      : l10n.uploadsFinishing,
                  style: caption,
                ),
              ),
            ],
            if (phase is UploadInterrupted) ...<Widget>[
              const SizedBox(height: WaxSpace.s4),
              status(Text(l10n.uploadsInterrupted, style: caption)),
            ],
            if (duplicate != null) ...<Widget>[
              const SizedBox(height: WaxSpace.s8),
              Semantics(
                identifier: SemanticsIds.uploadDuplicate(upload.id),
                container: true,
                child: WaxBanner(
                  tone: WaxBannerTone.caution,
                  message: _duplicateMessage(l10n, upload, duplicate),
                ),
              ),
            ],
            if (reviewEntryId != null) ...<Widget>[
              const SizedBox(height: WaxSpace.s8),
              Align(
                alignment: Alignment.centerRight,
                child: WaxButton(
                  label: l10n.uploadsOpenReview,
                  kind: WaxButtonKind.text,
                  semanticsId: SemanticsIds.uploadReview(upload.id),
                  // Pushed: an entry is declared under the review queue,
                  // not under this list, so `go` would leave the uploads
                  // behind.
                  onPressed: () =>
                      context.push(WaxRoute.reviewEntry(reviewEntryId)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// How a duplicate matched, as the uploads row and the review pane word
/// it.
String duplicateKindLabel(AppLocalizations l10n, String kind) => switch (kind) {
  'content' => l10n.uploadsDuplicateContent,
  'id' => l10n.uploadsDuplicateId,
  'fingerprint' => l10n.uploadsDuplicateFingerprint,
  _ => l10n.uploadsDuplicateName,
};

/// What a duplicate matched, by title and artist where the reader may
/// see it. The artist names it even where the title is missing, which is
/// when the alternative is a bare pid; an item the reader cannot see is
/// not named at all.
String duplicateWhat(AppLocalizations l10n, DuplicateWarning duplicate) =>
    switch ((duplicate.title ?? duplicate.itemPid, duplicate.artist)) {
      (final name?, final artist?) => l10n.uploadsDuplicateBy(name, artist),
      (final name?, null) => name,
      (null, _) => l10n.uploadsDuplicateUnseen,
    };
