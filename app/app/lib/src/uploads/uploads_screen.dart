import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../media_icons.dart';
import '../review/review_entry_screen.dart';
import 'add_to_library.dart';
import 'file_picker_port.dart';
import 'uploads_controller.dart';

/// The caller's upload sessions with the pick-and-transfer flow.
///
/// The pick button only appears when a [FilePickerPort] is wired; the
/// default provider is null until the platform pickers (native file
/// dialogs, web drag-and-drop) land with a later wiring pass, so the
/// screen stays a read-only session list until then.
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Uploads'),
        actions: [
          if (picker != null)
            Semantics(
              identifier: 'upload-pick',
              label: 'Upload files',
              button: true,
              child: IconButton(
                key: const Key('upload-pick'),
                tooltip: 'Upload files',
                icon: const Icon(Icons.upload_file),
                onPressed: () => pickAndUpload(context, ref, picker),
              ),
            ),
          Semantics(
            identifier: 'upload-from-url',
            label: 'Add from URL',
            button: true,
            child: IconButton(
              key: const Key('upload-from-url'),
              tooltip: 'Add from URL',
              icon: const Icon(Icons.add_link),
              onPressed: () => acquireFromUrl(context, ref),
            ),
          ),
        ],
      ),
      body: switch (uploads) {
        AsyncData(:final value) => _list(context, ref, value),
        AsyncError(:final error) => _errorView(context, ref, error),
        _ => const Center(child: CircularProgressIndicator()),
      },
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
    if (state.uploads.isEmpty) {
      return const Center(child: Text('No uploads yet'));
    }
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
        itemCount: state.uploads.length + (state.loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.uploads.length) {
            return const Center(child: CircularProgressIndicator());
          }
          final upload = state.uploads[index];
          return _UploadRow(
            upload: upload,
            failed: state.failed.contains(upload.id),
            onRetry: () => _retry(context, ref, upload.id),
            onDiscard: () => _discard(context, ref, upload),
          );
        },
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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final duplicate = upload.duplicate;
    final reviewEntryId = upload.reviewEntryId;
    final receiving = upload.state == 'receiving';
    final discardable = receiving || upload.state == 'staged';
    return Semantics(
      identifier: 'upload-row-${upload.id}',
      label: upload.fileName,
      child: Card(
        key: ValueKey('upload-row-${upload.id}'),
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
                      identifier: 'upload-retry-${upload.id}',
                      label: 'Retry upload',
                      button: true,
                      child: IconButton(
                        key: ValueKey('upload-retry-${upload.id}'),
                        tooltip: 'Retry upload',
                        icon: const Icon(Icons.refresh),
                        onPressed: onRetry,
                      ),
                    ),
                  if (discardable)
                    Semantics(
                      identifier: 'upload-delete-${upload.id}',
                      label: 'Discard upload',
                      button: true,
                      child: IconButton(
                        key: ValueKey('upload-delete-${upload.id}'),
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
                  identifier: 'upload-duplicate-${upload.id}',
                  child: Container(
                    key: ValueKey('upload-duplicate-${upload.id}'),
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
                    identifier: 'upload-review-${upload.id}',
                    label: 'Open review entry',
                    button: true,
                    child: TextButton(
                      key: ValueKey('upload-review-${upload.id}'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ReviewEntryScreen(entryId: reviewEntryId),
                        ),
                      ),
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
