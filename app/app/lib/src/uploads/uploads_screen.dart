import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../media_view.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'add_to_library.dart';
import 'audio_drop_area.dart';
import 'file_picker_port.dart';
import 'uploads_controller.dart';

/// The caller's upload sessions, the quota header, and drag-and-drop.
/// Pick affordances need a [FilePickerPort] and upload rights; without
/// either this is a read-only session list.
class UploadsScreen extends ConsumerWidget {
  const UploadsScreen({super.key});

  Future<void> _retry(WidgetRef ref, String id) async {
    try {
      await ref.read(uploadsProvider.notifier).retry(id);
    } on WaxDeckApiException catch (e) {
      ref.read(shellMessengerProvider.notifier).show(e.message);
    }
  }

  Future<void> _discard(
    BuildContext context,
    WidgetRef ref,
    UploadSession upload,
  ) async {
    final confirmed = await showTypedConfirm(
      context,
      title: 'Discard upload?',
      message:
          '"${upload.fileName}" and its staged bytes are removed, and the '
          'space they hold against your quota is released.',
      confirmWord: 'discard',
      confirmLabel: 'Discard',
      fieldSemanticsId: SemanticsIds.confirmField,
      confirmSemanticsId: SemanticsIds.confirmAccept,
      cancelSemanticsId: SemanticsIds.confirmCancel,
    );
    if (!confirmed) return;
    try {
      await ref.read(uploadsProvider.notifier).discard(upload.id);
    } on WaxDeckApiException catch (e) {
      ref.read(shellMessengerProvider.notifier).show(e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final uploads = ref.watch(uploadsProvider);
    final picker = ref.watch(filePickerProvider);
    final canUpload =
        ref.watch(authControllerProvider).value?.user?.uploadEnabled ?? false;
    // Around the whole screen: the copy says anywhere on this page, and
    // a zone inside the scroll would refuse a drop over the bar.
    return AudioDropArea(
      enabled: canUpload,
      onDropped: (files) => uploadPickedFiles(context, ref, files),
      child: WaxScaffold(
        title: 'Uploads',
        largeTitle: false,
        semanticsId: SemanticsIds.uploadsScreen,
        actions: <Widget>[
          if (picker != null && canUpload)
            WaxIconButton(
              glyph: WaxIcons.add,
              label: 'Upload files',
              semanticsId: SemanticsIds.uploadPick,
              onPressed: () => pickAndUpload(context, ref, picker),
            ),
          if (canUpload)
            WaxIconButton(
              glyph: WaxIcons.downloads,
              label: 'Add from URL',
              semanticsId: SemanticsIds.uploadFromUrl,
              onPressed: () => acquireFromUrl(context, ref),
            ),
        ],
        body: Padding(
          padding: sizeClass.gutter.add(
            const EdgeInsets.only(bottom: WaxSpace.s32),
          ),
          child: switch (uploads) {
            AsyncData(:final value) => _body(context, ref, value, canUpload),
            AsyncError(:final error) => ErrorState(
              title: 'Could not load uploads',
              message: error is WaxDeckApiException
                  ? error.message
                  : 'The server did not answer.',
              onRetry: () => ref.invalidate(uploadsProvider),
            ),
            _ => const SkeletonShapes(shape: SkeletonShape.list),
          },
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (quota != null) _QuotaHeader(quota: quota),
        const SizedBox(height: WaxSpace.s24),
        if (state.uploads.isEmpty)
          EmptyState(
            glyph: WaxIcons.add,
            title: 'No uploads yet',
            message: canUpload
                ? 'Pick files from the bar above, or drop them anywhere on '
                      'this page.'
                : 'This account cannot upload. Ask an administrator for the '
                      'permission.',
          )
        else ...<Widget>[
          for (final group in _grouped(state))
            _BatchGroup(
              group: group,
              failed: state.failed,
              onRetry: (id) => _retry(ref, id),
              onDiscard: (upload) => _discard(context, ref, upload),
            ),
          if (state.hasMore) ...<Widget>[
            const SizedBox(height: WaxSpace.s16),
            WaxButton(
              label: state.loadingMore ? 'Loading' : 'Load more',
              kind: WaxButtonKind.tonal,
              icon: WaxIcons.expand,
              semanticsId: SemanticsIds.uploadsMore,
              onPressed: state.loadingMore
                  ? null
                  : () => ref.read(uploadsProvider.notifier).loadMore(),
            ),
          ],
        ],
      ],
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

/// One upload batch, or a solo session standing alone.
class _Batch {
  const _Batch({required this.id, required this.uploads});

  /// Null for a session that was uploaded on its own.
  final String? id;

  final List<UploadSession> uploads;
}

class _BatchGroup extends StatelessWidget {
  const _BatchGroup({
    required this.group,
    required this.failed,
    required this.onRetry,
    required this.onDiscard,
  });

  final _Batch group;
  final Set<String> failed;
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
                      'Uploaded together, ${group.uploads.length} '
                      '${group.uploads.length == 1 ? 'file' : 'files'}',
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
              upload: upload,
              failed: failed.contains(upload.id),
              onRetry: () => onRetry(upload.id),
              onDiscard: () => onDiscard(upload),
            ),
        ],
      ),
    );
  }
}

/// What is staged now against the cap. A pending-upload limit rather
/// than a storage cap, which is what the caption explains.
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
              'Waiting to be imported',
              style: WaxType.overline.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: WaxSpace.s8),
            Text(
              cap == null
                  ? l10n.formatBytes(quota.bytesInUse)
                  : '${l10n.formatBytes(quota.bytesInUse)} of '
                        '${l10n.formatBytes(cap)}',
              style: WaxType.titleEntity.copyWith(
                color: fraction != null && fraction >= 1
                    ? colors.error
                    : colors.textPrimary,
              ),
            ),
            if (fraction != null) ...<Widget>[
              const SizedBox(height: WaxSpace.s8),
              ClipRRect(
                borderRadius: BorderRadius.circular(WaxRadius.r6),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 6,
                  backgroundColor: colors.surface3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    fraction >= 1 ? colors.error : colors.accent,
                  ),
                ),
              ),
            ],
            const SizedBox(height: WaxSpace.s8),
            Text(
              cap == null
                  ? 'Staged files are held until they are imported or '
                        'discarded.'
                  : 'This is what may sit staged at once, not what you may '
                        'contribute: importing a session frees the space it '
                        'held.',
              style: WaxType.caption.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadRow extends StatelessWidget {
  const _UploadRow({
    required this.upload,
    required this.failed,
    required this.onRetry,
    required this.onDiscard,
  });

  final UploadSession upload;
  final bool failed;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  static String _duplicateKind(String kind) => switch (kind) {
    'content' => 'exact copy',
    'fingerprint' => 'same recording',
    _ => 'name match',
  };

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final duplicate = upload.duplicate;
    final reviewEntryId = upload.reviewEntryId;
    final receiving = upload.state == 'receiving';
    final discardable = receiving || upload.state == 'staged';
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
                if (failed)
                  Text(
                    'Transfer failed',
                    style: WaxType.label.copyWith(color: colors.error),
                  )
                else
                  CodecChip(upload.state),
                if (failed)
                  WaxIconButton(
                    glyph: WaxIcons.refresh,
                    label: 'Retry upload',
                    size: 16,
                    semanticsId: SemanticsIds.uploadRetry(upload.id),
                    onPressed: onRetry,
                  ),
                if (discardable)
                  WaxIconButton(
                    glyph: WaxIcons.delete,
                    label: 'Discard upload',
                    size: 16,
                    semanticsId: SemanticsIds.uploadDelete(upload.id),
                    onPressed: onDiscard,
                  ),
              ],
            ),
            if (receiving && !failed) ...<Widget>[
              const SizedBox(height: WaxSpace.s8),
              ClipRRect(
                borderRadius: BorderRadius.circular(WaxRadius.r6),
                child: LinearProgressIndicator(
                  value: upload.sizeBytes == 0
                      ? null
                      : upload.receivedBytes / upload.sizeBytes,
                  minHeight: 4,
                  backgroundColor: colors.surface3,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
                ),
              ),
              const SizedBox(height: WaxSpace.s4),
              Text(
                upload.sizeBytes == 0
                    ? 'Receiving'
                    : '${upload.receivedBytes * 100 ~/ upload.sizeBytes}% of '
                          '${l10n.formatBytes(upload.sizeBytes)} received',
                style: WaxType.caption.copyWith(color: colors.textSecondary),
              ),
            ],
            if (duplicate != null) ...<Widget>[
              const SizedBox(height: WaxSpace.s8),
              Semantics(
                identifier: SemanticsIds.uploadDuplicate(upload.id),
                container: true,
                child: WaxBanner(
                  tone: WaxBannerTone.caution,
                  message:
                      'Duplicate (${_duplicateKind(duplicate.kind)}): '
                      '${duplicate.title ?? duplicate.itemPid}'
                      '${duplicate.artist == null ? '' : ' by ${duplicate.artist}'}',
                ),
              ),
            ],
            if (reviewEntryId != null) ...<Widget>[
              const SizedBox(height: WaxSpace.s8),
              Align(
                alignment: Alignment.centerRight,
                child: WaxButton(
                  label: 'Open review entry',
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
