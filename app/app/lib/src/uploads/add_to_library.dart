import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import '../tools/tasks_screen.dart';
import 'file_picker_port.dart';
import 'uploads_controller.dart';

/// The one place new audio enters the library: acquire it from a URL (a
/// video, playlist, or channel) or upload a file. Both land in the
/// review queue. This is shared by the prominent add button on the
/// library and the manage-uploads screen, so there is one flow to
/// maintain.

/// Opens the add sheet, defaulting the media type to [initial] (the
/// section the caller is in). Podcasts are added by subscribing, not
/// here, so the sheet steers a podcast default to music.
Future<void> showAddToLibrarySheet(
  BuildContext context,
  WidgetRef ref, {
  MediaType? initial,
}) async {
  final picker = ref.read(filePickerProvider);
  final defaultType = (initial == null || initial == MediaType.podcast)
      ? MediaType.music
      : initial;
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        key: const Key('add-sheet'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            identifier: 'add-from-url',
            button: true,
            child: ListTile(
              key: const Key('add-from-url'),
              leading: const Icon(Icons.add_link),
              title: const Text('Add from URL'),
              subtitle: const Text('A video, playlist, or channel'),
              onTap: () => Navigator.of(sheetContext).pop('url'),
            ),
          ),
          if (picker != null)
            Semantics(
              identifier: 'add-upload-file',
              button: true,
              child: ListTile(
                key: const Key('add-upload-file'),
                leading: const Icon(Icons.upload_file),
                title: const Text('Upload files'),
                onTap: () => Navigator.of(sheetContext).pop('file'),
              ),
            ),
          if (picker != null && picker.canPickFolders)
            Semantics(
              identifier: 'add-upload-folder',
              button: true,
              child: ListTile(
                key: const Key('add-upload-folder'),
                leading: const Icon(Icons.drive_folder_upload),
                title: const Text('Upload a folder'),
                subtitle: const Text('An album or a collection'),
                onTap: () => Navigator.of(sheetContext).pop('folder'),
              ),
            ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'url':
      await acquireFromUrl(context, ref, initial: defaultType);
    case 'file':
      if (picker != null) {
        await pickAndUpload(context, ref, picker, initial: defaultType);
      }
    case 'folder':
      if (picker != null) {
        await pickFolderAndUpload(context, ref, picker, initial: defaultType);
      }
  }
}

/// Queues a server-side download of a source URL; the result flows
/// through uploads and the review queue. [initialUrl] prefills the
/// dialog (a share-sheet handoff).
Future<void> acquireFromUrl(
  BuildContext context,
  WidgetRef ref, {
  MediaType initial = MediaType.music,
  String? initialUrl,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final request =
      await showDialog<({String url, MediaType mediaType, String format})>(
        context: context,
        builder: (_) => AcquireDialog(initial: initial, initialUrl: initialUrl),
      );
  if (request == null) return;
  try {
    await ref
        .read(repositoryProvider)
        .createAcquisition(
          url: request.url,
          mediaType: request.mediaType,
          format: request.format,
        );
    ref.invalidate(uploadsProvider);
    ref.invalidate(toolTasksProvider);
    // The download runs in the background and its files land in the
    // review queue, not straight in the library, so the message says
    // where to look and offers a jump to the task list to watch
    // progress (or see why it failed).
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text(
            'Downloading. It will appear in the review queue when ready.',
          ),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Tasks',
            onPressed: () => navigator.push(
              MaterialPageRoute<void>(builder: (_) => const TasksScreen()),
            ),
          ),
        ),
      );
  } on WaxDeckApiException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// Picks files and hands them to the shared upload flow.
Future<void> pickAndUpload(
  BuildContext context,
  WidgetRef ref,
  FilePickerPort picker, {
  MediaType? initial,
}) async {
  final files = await picker.pickAudioFiles();
  if (files.isEmpty || !context.mounted) return;
  await uploadPickedFiles(context, ref, files, initial: initial);
}

/// Picks a folder and hands its audio files to the shared upload
/// flow, their in-folder hierarchy riding along as the clustering
/// hint.
Future<void> pickFolderAndUpload(
  BuildContext context,
  WidgetRef ref,
  FilePickerPort picker, {
  MediaType? initial,
}) async {
  final files = await picker.pickAudioFolder();
  if (files.isEmpty || !context.mounted) return;
  await uploadPickedFiles(context, ref, files, initial: initial);
}

/// The one upload flow behind every entry point (picker, folder,
/// drag-and-drop): asks the media type — and, for several files, the
/// grouping intent — opens the batch, uploads every file, and
/// finalizes. Per-file failures surface and the loop continues; the
/// finalize runs regardless so the files that did arrive reach
/// review.
Future<void> uploadPickedFiles(
  BuildContext context,
  WidgetRef ref,
  List<PickedAudioFile> files, {
  MediaType? initial,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final choice =
      await showDialog<({MediaType mediaType, UploadGrouping grouping})>(
        context: context,
        builder: (_) => MediaTypeDialog(
          initial: initial ?? MediaType.music,
          fileCount: files.length,
        ),
      );
  if (choice == null) return;
  final repository = ref.read(repositoryProvider);
  String? batchId;
  if (files.length > 1) {
    try {
      final batch = await repository.createUploadBatch(
        grouping: choice.grouping,
        mediaType: choice.mediaType.wireName,
      );
      batchId = batch.id;
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
  }
  for (final file in files) {
    try {
      await ref
          .read(uploadsProvider.notifier)
          .uploadPicked(
            file,
            mediaType: choice.mediaType.wireName,
            batchId: batchId,
          );
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${file.name}: ${e.message}')));
    }
  }
  if (batchId != null) {
    try {
      await repository.completeUploadBatch(batchId);
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
    // Finalization filled the members' review entries; refresh the
    // rows.
    ref.invalidate(uploadsProvider);
  }
}

/// The URL entry dialog, returning the URL and media type or null.
class AcquireDialog extends StatefulWidget {
  const AcquireDialog({
    super.key,
    this.initial = MediaType.music,
    this.initialUrl,
  });

  final MediaType initial;

  /// Prefills the URL field (a share-sheet handoff).
  final String? initialUrl;

  @override
  State<AcquireDialog> createState() => _AcquireDialogState();
}

class _AcquireDialogState extends State<AcquireDialog> {
  late final _urlController = TextEditingController(
    text: widget.initialUrl ?? '',
  );
  late var _mediaType = widget.initial;
  var _format = 'best';

  @override
  void initState() {
    super.initState();
    _urlController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = _urlController.text.trim();
    return AlertDialog(
      key: const Key('acquire-dialog'),
      title: const Text('Add from URL'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('acquire-url'),
            controller: _urlController,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Source URL',
              helperText: 'A single video, or a playlist or channel',
            ),
          ),
          const SizedBox(height: 8),
          MediaTypeSelector(
            value: _mediaType,
            onChanged: (value) => setState(() => _mediaType = value),
          ),
          // Format is a download choice, so it is hidden for podcasts, which
          // subscribe to a feed rather than transcode a file.
          if (_mediaType != MediaType.podcast) ...[
            const SizedBox(height: 8),
            AcquireFormatSelector(
              value: _format,
              onChanged: (value) => setState(() => _format = value),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        Semantics(
          identifier: 'acquire-submit',
          label: 'Queue download',
          button: true,
          child: FilledButton(
            key: const Key('acquire-submit'),
            onPressed: url.isEmpty
                ? null
                : () => Navigator.of(context).pop((
                    url: url,
                    mediaType: _mediaType,
                    format: _mediaType == MediaType.podcast ? 'best' : _format,
                  )),
            child: const Text('Download'),
          ),
        ),
      ],
    );
  }
}

/// The media-type prompt before an upload; with several files it also
/// asks the grouping intent, so an album folder never floods the
/// review queue with per-file entries by accident — and a mixed grab
/// of singles never merges into one album.
class MediaTypeDialog extends StatefulWidget {
  const MediaTypeDialog({
    super.key,
    this.initial = MediaType.music,
    this.fileCount = 1,
  });

  final MediaType initial;

  /// How many files are about to upload; above one, the grouping
  /// question appears.
  final int fileCount;

  @override
  State<MediaTypeDialog> createState() => _MediaTypeDialogState();
}

class _MediaTypeDialogState extends State<MediaTypeDialog> {
  late var _mediaType = widget.initial;
  var _grouping = UploadGrouping.auto;

  @override
  Widget build(BuildContext context) {
    final several = widget.fileCount > 1;
    return AlertDialog(
      title: Text(
        several
            ? 'What are these ${widget.fileCount} files?'
            : 'What are you uploading?',
      ),
      // Scrollable: with the grouping selector the content outgrows a
      // short viewport (a phone in landscape) and an AlertDialog does
      // not scroll on its own.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MediaTypeSelector(
              value: _mediaType,
              onChanged: (value) => setState(() => _mediaType = value),
            ),
            if (several) ...[
              const SizedBox(height: 12),
              UploadGroupingSelector(
                value: _grouping,
                onChanged: (value) => setState(() => _grouping = value),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        Semantics(
          identifier: 'upload-media-confirm',
          label: 'Start upload',
          button: true,
          child: FilledButton(
            key: const Key('upload-media-confirm'),
            onPressed: () => Navigator.of(
              context,
            ).pop((mediaType: _mediaType, grouping: _grouping)),
            child: const Text('Upload'),
          ),
        ),
      ],
    );
  }
}

/// The grouping-intent selector for a multi-file upload.
class UploadGroupingSelector extends StatelessWidget {
  const UploadGroupingSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final UploadGrouping value;
  final ValueChanged<UploadGrouping> onChanged;

  static const _options = [
    (
      UploadGrouping.auto,
      'Auto-detect',
      'Group into albums by their tags and folders',
    ),
    (UploadGrouping.album, 'One album', 'Review all files as one release'),
    (UploadGrouping.tracks, 'Separate tracks', 'Review every file on its own'),
  ];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'upload-grouping',
      child: Column(
        key: const Key('upload-grouping'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How should these files be grouped?',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final (grouping, label, help) in _options)
            Semantics(
              identifier: 'upload-grouping-${grouping.wireName}',
              button: true,
              child: ListTile(
                key: Key('upload-grouping-${grouping.wireName}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  value == grouping
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: value == grouping
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: Text(label),
                subtitle: Text(help),
                onTap: () => onChanged(grouping),
              ),
            ),
        ],
      ),
    );
  }
}

/// The required media-type selector shared by the file-upload and
/// URL-acquisition dialogs; only one of them is ever open at a time.
class MediaTypeSelector extends StatelessWidget {
  const MediaTypeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final MediaType value;
  final ValueChanged<MediaType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'upload-media-type',
      child: DropdownButton<MediaType>(
        key: const Key('upload-media-type'),
        value: value,
        isExpanded: true,
        onChanged: (selected) {
          if (selected != null) onChanged(selected);
        },
        items: const [
          DropdownMenuItem(value: MediaType.music, child: Text('Music')),
          DropdownMenuItem(value: MediaType.podcast, child: Text('Podcast')),
          DropdownMenuItem(
            value: MediaType.audiobook,
            child: Text('Audiobook'),
          ),
        ],
      ),
    );
  }
}

/// The optional download-format selector for a URL acquisition. "Best"
/// keeps the source's highest-quality audio without re-encoding; the
/// others transcode to a specific container for device compatibility.
class AcquireFormatSelector extends StatelessWidget {
  const AcquireFormatSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'acquire-format',
      child: DropdownButton<String>(
        key: const Key('acquire-format'),
        value: value,
        isExpanded: true,
        onChanged: (selected) {
          if (selected != null) onChanged(selected);
        },
        items: const [
          DropdownMenuItem(
            value: 'best',
            child: Text('Best quality (recommended)'),
          ),
          DropdownMenuItem(value: 'opus', child: Text('Opus')),
          DropdownMenuItem(value: 'm4a', child: Text('M4A (AAC)')),
          DropdownMenuItem(value: 'mp3', child: Text('MP3')),
          DropdownMenuItem(value: 'flac', child: Text('FLAC')),
        ],
      ),
    );
  }
}
