import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../auth/auth_controller.dart';
import '../format_bytes.dart';
import '../media_icons.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'add_to_library.dart';
import 'audio_drop_area.dart';
import 'file_picker_port.dart';
import 'uploads_controller.dart';

/// The caller's upload sessions with the pick-and-transfer flow, the
/// quota header, and drag-and-drop. Pick affordances appear when a
/// [FilePickerPort] is wired and the caller holds upload rights;
/// without either, the screen stays a read-only session list.
class UploadsScreen extends ConsumerWidget {
  const UploadsScreen({super.key});

  Future<void> _retry(BuildContext context, WidgetRef ref, String id) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(uploadsProvider.notifier).retry(id);
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _discard(
    BuildContext context,
    WidgetRef ref,
    UploadSession upload,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard upload?'),
        content: Text(
          '"${upload.fileName}" and its staged bytes will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('upload-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(uploadsProvider.notifier).discard(upload.id);
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uploads = ref.watch(uploadsProvider);
    final picker = ref.watch(filePickerProvider);
    final canUpload =
        ref.watch(authControllerProvider).value?.user?.uploadEnabled ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Uploads'),
        actions: [
          if (picker != null && canUpload)
            Semantics(
              identifier: SemanticsIds.uploadPick,
              label: 'Upload files',
              button: true,
              child: IconButton(
                key: const Key(SemanticsIds.uploadPick),
                tooltip: 'Upload files',
                icon: const Icon(Icons.upload_file),
                onPressed: () => pickAndUpload(context, ref, picker),
              ),
            ),
          if (canUpload)
            Semantics(
              identifier: SemanticsIds.uploadFromUrl,
              label: 'Add from URL',
              button: true,
              child: IconButton(
                key: const Key(SemanticsIds.uploadFromUrl),
                tooltip: 'Add from URL',
                icon: const Icon(Icons.add_link),
                onPressed: () => acquireFromUrl(context, ref),
              ),
            ),
        ],
      ),
      body: AudioDropArea(
        enabled: canUpload,
        onDropped: (files) => uploadPickedFiles(context, ref, files),
        child: switch (uploads) {
          AsyncData(:final value) => _list(context, ref, value),
          AsyncError(:final error) => _errorView(context, ref, error),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Widget _errorView(BuildContext context, WidgetRef ref, Object error) {
    final message = error is WaxDeckApiException
        ? error.message
        : 'Could not load uploads';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => ref.invalidate(uploadsProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, WidgetRef ref, UploadsState state) {
    final quota = state.quota;
    if (state.uploads.isEmpty) {
      return Column(
        children: [
          if (quota != null)
            _QuotaHeader(
              key: const Key(SemanticsIds.uploadQuota),
              quota: quota,
            ),
          const Expanded(child: Center(child: Text('No uploads yet'))),
        ],
      );
    }
    final rows = _groupedRows(state);
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.pixels >= metrics.maxScrollExtent - 400) {
          ref.read(uploadsProvider.notifier).loadMore();
        }
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount:
            rows.length + (quota == null ? 0 : 1) + (state.loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (quota != null) {
            if (index == 0) {
              return _QuotaHeader(
                key: const Key(SemanticsIds.uploadQuota),
                quota: quota,
              );
            }
            index--;
          }
          if (index >= rows.length) {
            return const Center(child: CircularProgressIndicator());
          }
          // Keys ride the top-level items so the list's element
          // reconciliation tracks rows across inserts and removals,
          // not just the finders inside them.
          return switch (rows[index]) {
            _BatchHeaderRow(:final batchId, :final count) => _BatchHeader(
              key: ValueKey(SemanticsIds.uploadBatch(batchId)),
              batchId: batchId,
              count: count,
            ),
            _SessionRow(:final upload) => _UploadRow(
              key: ValueKey(SemanticsIds.uploadRow(upload.id)),
              upload: upload,
              failed: state.failed.contains(upload.id),
              onRetry: () => _retry(context, ref, upload.id),
              onDiscard: () => _discard(context, ref, upload),
            ),
          };
        },
      ),
    );
  }

  /// Renders the listing with each batch's members bucketed under one
  /// header at the batch's first (newest) appearance. Members usually
  /// arrive adjacent in the creation-ordered listing, but a concurrent
  /// solo upload (another tab, a share) can interleave them; bucketing
  /// keeps one header per batch either way. Grouping is purely visual
  /// and client-side (there is no batch listing endpoint), and a batch
  /// spanning a page boundary still splits across pages.
  static List<_ListRow> _groupedRows(UploadsState state) {
    final byBatch = <String, List<UploadSession>>{};
    for (final upload in state.uploads) {
      final batchId = upload.batchId;
      if (batchId != null) {
        byBatch.putIfAbsent(batchId, () => []).add(upload);
      }
    }
    final rows = <_ListRow>[];
    final emitted = <String>{};
    for (final upload in state.uploads) {
      final batchId = upload.batchId;
      if (batchId == null) {
        rows.add(_SessionRow(upload));
        continue;
      }
      if (!emitted.add(batchId)) continue;
      final members = byBatch[batchId]!;
      rows.add(_BatchHeaderRow(batchId: batchId, count: members.length));
      rows.addAll(members.map(_SessionRow.new));
    }
    return rows;
  }
}

sealed class _ListRow {
  const _ListRow();
}

class _SessionRow extends _ListRow {
  const _SessionRow(this.upload);

  final UploadSession upload;
}

class _BatchHeaderRow extends _ListRow {
  const _BatchHeaderRow({required this.batchId, required this.count});

  final String batchId;
  final int count;
}

class _BatchHeader extends StatelessWidget {
  const _BatchHeader({super.key, required this.batchId, required this.count});

  final String batchId;
  final int count;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      identifier: SemanticsIds.uploadBatch(batchId),
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Row(
          children: [
            Icon(
              Icons.library_add,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              'Uploaded together · $count ${count == 1 ? 'file' : 'files'}',
              style: textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The caller's allowance: usage, and the cap with a fill bar when one
/// is set.
class _QuotaHeader extends StatelessWidget {
  const _QuotaHeader({super.key, required this.quota});

  final UploadQuota quota;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cap = quota.quotaBytes;
    return Semantics(
      identifier: SemanticsIds.uploadQuota,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cap == null
                  ? '${formatBytes(quota.bytesInUse)} of uploads in use'
                  : '${formatBytes(quota.bytesInUse)} of '
                        '${formatBytes(cap)} used',
              style: textTheme.bodySmall,
            ),
            if (cap != null && cap > 0) ...[
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: (quota.bytesInUse / cap).clamp(0.0, 1.0),
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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final duplicate = upload.duplicate;
    final reviewEntryId = upload.reviewEntryId;
    final receiving = upload.state == 'receiving';
    final discardable = receiving || upload.state == 'staged';
    return Semantics(
      identifier: SemanticsIds.uploadRow(upload.id),
      label: upload.fileName,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    mediaFallbackIcon(upload.mediaType),
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      upload.fileName,
                      style: textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (failed)
                    Chip(
                      label: const Text('Transfer failed'),
                      labelStyle: TextStyle(
                        color: colorScheme.onErrorContainer,
                      ),
                      backgroundColor: colorScheme.errorContainer,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    )
                  else
                    Chip(
                      label: Text(upload.state),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (failed)
                    Semantics(
                      identifier: SemanticsIds.uploadRetry(upload.id),
                      label: 'Retry upload',
                      button: true,
                      child: IconButton(
                        key: ValueKey(SemanticsIds.uploadRetry(upload.id)),
                        tooltip: 'Retry upload',
                        icon: const Icon(Icons.refresh),
                        onPressed: onRetry,
                      ),
                    ),
                  if (discardable)
                    Semantics(
                      identifier: SemanticsIds.uploadDelete(upload.id),
                      label: 'Discard upload',
                      button: true,
                      child: IconButton(
                        key: ValueKey(SemanticsIds.uploadDelete(upload.id)),
                        tooltip: 'Discard upload',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: onDiscard,
                      ),
                    ),
                ],
              ),
              if (receiving && !failed) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: upload.sizeBytes == 0
                      ? null
                      : upload.receivedBytes / upload.sizeBytes,
                ),
                const SizedBox(height: 4),
                Text(
                  upload.sizeBytes == 0
                      ? 'Receiving'
                      : '${(upload.receivedBytes * 100 ~/ upload.sizeBytes)}% received',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (duplicate != null) ...[
                const SizedBox(height: 8),
                Semantics(
                  identifier: SemanticsIds.uploadDuplicate(upload.id),
                  child: Container(
                    key: ValueKey(SemanticsIds.uploadDuplicate(upload.id)),
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber,
                          size: 16,
                          color: colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Duplicate (${_duplicateKind(duplicate.kind)}): '
                            '${duplicate.title ?? duplicate.itemPid}'
                            '${duplicate.artist == null ? '' : ' by ${duplicate.artist}'}',
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (reviewEntryId != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: Semantics(
                    identifier: SemanticsIds.uploadReview(upload.id),
                    label: 'Open review entry',
                    button: true,
                    child: TextButton(
                      key: ValueKey(SemanticsIds.uploadReview(upload.id)),
                      onPressed: () =>
                          // Pushed: an entry is declared under the review
                          // queue, not under this list, so `go` would
                          // leave the uploads behind.
                          context.push(WaxRoute.reviewEntry(reviewEntryId)),
                      child: const Text('Open review entry'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
