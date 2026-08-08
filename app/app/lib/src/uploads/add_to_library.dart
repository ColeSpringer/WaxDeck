import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../providers.dart';
import '../settings/prefs_controller.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import '../tools/tasks_screen.dart';
import 'file_picker_port.dart';
import 'uploads_controller.dart';

/// The one place new audio enters the library: a URL to acquire or a
/// file to upload, both landing in the review queue. Shared by the add
/// button and the uploads screen so there is one flow.

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
  final colors = WaxColors.of(context);
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: colors.surface2,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          WaxSpace.s16,
          0,
          WaxSpace.s16,
          WaxSpace.s24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SectionHeader(
              title: 'Add to the library',
              overline: 'Both routes land in the review queue',
            ),
            WaxOptionRow(
              title: 'Add from URL',
              subtitle: 'A video, a playlist, or a channel',
              glyph: WaxIcons.downloads,
              semanticsId: SemanticsIds.addFromUrl,
              onTap: () => Navigator.of(sheetContext).pop('url'),
            ),
            if (picker != null)
              WaxOptionRow(
                title: 'Upload files',
                subtitle: 'One track, or a set you pick yourself',
                glyph: WaxIcons.add,
                semanticsId: SemanticsIds.addUploadFile,
                onTap: () => Navigator.of(sheetContext).pop('file'),
              ),
            if (picker != null && picker.canPickFolders)
              WaxOptionRow(
                title: 'Upload a folder',
                subtitle: 'An album or a collection, hierarchy and all',
                glyph: WaxIcons.albums,
                semanticsId: SemanticsIds.addUploadFolder,
                onTap: () => Navigator.of(sheetContext).pop('folder'),
              ),
          ],
        ),
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
  final messenger = ref.read(shellMessengerProvider.notifier);
  final router = GoRouter.of(context);
  final identifyDefault = await _identifyDefault(ref);
  if (!context.mounted) return;
  final request =
      await showDialog<
        ({String url, MediaType mediaType, String format, bool identify})
      >(
        context: context,
        builder: (_) => AcquireDialog(
          initial: initial,
          initialUrl: initialUrl,
          initialIdentify: identifyDefault,
        ),
      );
  if (request == null) return;
  try {
    await ref
        .read(repositoryProvider)
        .createAcquisition(
          url: request.url,
          mediaType: request.mediaType,
          format: request.format,
          identify: request.identify,
        );
    ref
      ..invalidate(uploadsProvider)
      ..invalidate(toolTasksProvider);
    // It runs in the background and lands in review rather than the
    // library, so the message says where to look.
    messenger.show(
      'Downloading. It will appear in the review queue when ready.',
      actionLabel: 'Tasks',
      actionSemanticsId: SemanticsIds.acquireTasks,
      onAction: () => router.push<void>(WaxRoute.tasks),
    );
  } on WaxDeckApiException catch (e) {
    messenger.show(e.message);
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

/// The one upload flow behind picker, folder, and drop. A per-file
/// failure surfaces and the loop continues, and the finalize runs
/// regardless so what did arrive reaches review.
Future<void> uploadPickedFiles(
  BuildContext context,
  WidgetRef ref,
  List<PickedAudioFile> files, {
  MediaType? initial,
}) async {
  final messenger = ref.read(shellMessengerProvider.notifier);
  final identifyDefault = await _identifyDefault(ref);
  if (!context.mounted) return;
  final choice =
      await showDialog<
        ({MediaType mediaType, UploadGrouping grouping, bool identify})
      >(
        context: context,
        builder: (_) => MediaTypeDialog(
          initial: initial ?? MediaType.music,
          fileCount: files.length,
          initialIdentify: identifyDefault,
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
        identify: choice.identify,
      );
      batchId = batch.id;
    } on WaxDeckApiException catch (e) {
      messenger.show(e.message);
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
            identify: choice.identify,
          );
    } on WaxDeckApiException catch (e) {
      messenger.show('${file.name}: ${e.message}');
    }
  }
  if (batchId != null) {
    try {
      await repository.completeUploadBatch(batchId);
    } on WaxDeckApiException catch (e) {
      messenger.show(e.message);
    }
    // Finalization filled the members' review entries; refresh the
    // rows.
    ref.invalidate(uploadsProvider);
  }
}

/// What the identification switch opens on. Awaited, not sampled: the
/// provider is lazy, so a synchronous read answers the default for
/// anybody who has not opened Settings. Null where it cannot be read,
/// which is sent absent rather than overriding an opt-out with a guess.
///
/// Bounded, because the app's Dio carries no timeouts: a server that
/// takes the socket and never answers would otherwise hold the sheet
/// shut for good, dropping picked files and eating a shared URL the
/// gate has already dequeued.
Future<bool?> _identifyDefault(WidgetRef ref) async {
  final loaded = ref.read(prefsControllerProvider);
  if (loaded.hasValue) return !(loaded.value?.identifyOptOut ?? false);
  return ref
      .read(prefsControllerProvider.future)
      .then<bool?>(
        (prefs) => !(prefs.identifyOptOut ?? false),
        onError: (Object _, StackTrace _) => null,
      )
      .timeout(_prefsSeedWait, onTimeout: () => null);
}

/// How long a sheet waits on the account preference before opening
/// without it.
const _prefsSeedWait = Duration(seconds: 5);

/// The URL entry dialog, returning the URL, media type, format, and
/// identification choice, or null.
class AcquireDialog extends StatefulWidget {
  const AcquireDialog({
    super.key,
    this.initial = MediaType.music,
    this.initialUrl,
    required this.initialIdentify,
  });

  final MediaType initial;

  /// Prefills the URL field (a share-sheet handoff).
  final String? initialUrl;

  /// What the switch opens on; null is sent absent. Required, not
  /// defaulted: a caller that forgot it would ignore the preference.
  final bool? initialIdentify;

  @override
  State<AcquireDialog> createState() => _AcquireDialogState();
}

class _AcquireDialogState extends State<AcquireDialog> {
  late final _urlController = TextEditingController(
    text: widget.initialUrl ?? '',
  );
  late var _mediaType = widget.initial;
  // Null is "nobody has said": drawn as on, sent absent.
  late bool? _identify = widget.initialIdentify;
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
    final colors = WaxColors.of(context);
    final url = _urlController.text.trim();
    return AlertDialog(
      backgroundColor: colors.surface2,
      title: const Text('Add from URL'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            WaxTextField(
              label: 'Source URL',
              hint: 'A single video, or a playlist or channel',
              controller: _urlController,
              autofocus: true,
              semanticsId: SemanticsIds.acquireUrl,
            ),
            const SizedBox(height: WaxSpace.s12),
            MediaTypeSelector(
              value: _mediaType,
              onChanged: (value) => setState(() => _mediaType = value),
            ),
            // Format is a download choice, so it is hidden for podcasts,
            // which subscribe to a feed rather than transcode a file.
            if (_mediaType != MediaType.podcast) ...<Widget>[
              const SizedBox(height: WaxSpace.s12),
              AcquireFormatSelector(
                value: _format,
                onChanged: (value) => setState(() => _format = value),
              ),
            ],
            // Outside that block: a podcast has no format to pick, but
            // it does open a review entry.
            const SizedBox(height: WaxSpace.s12),
            IdentifySwitch(
              value: _identify,
              mediaType: _mediaType,
              semanticsId: SemanticsIds.acquireIdentify,
              onChanged: (value) => setState(() => _identify = value),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        WaxButton(
          label: 'Cancel',
          kind: WaxButtonKind.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        WaxButton(
          label: 'Download',
          semanticsId: SemanticsIds.acquireSubmit,
          onPressed: url.isEmpty
              ? null
              : () => Navigator.of(context).pop((
                  url: url,
                  mediaType: _mediaType,
                  format: _mediaType == MediaType.podcast ? 'best' : _format,
                  identify: _identify,
                )),
        ),
      ],
    );
  }
}

/// The media-type prompt, plus the grouping intent for several files:
/// an album must not arrive as one entry per track, and a grab of
/// singles must not merge into one album.
class MediaTypeDialog extends StatefulWidget {
  const MediaTypeDialog({
    super.key,
    this.initial = MediaType.music,
    this.fileCount = 1,
    required this.initialIdentify,
  });

  final MediaType initial;

  /// How many files are about to upload; above one, the grouping
  /// question appears.
  final int fileCount;

  /// What the identification switch opens on; see
  /// [AcquireDialog.initialIdentify].
  final bool? initialIdentify;

  @override
  State<MediaTypeDialog> createState() => _MediaTypeDialogState();
}

class _MediaTypeDialogState extends State<MediaTypeDialog> {
  late var _mediaType = widget.initial;
  late bool? _identify = widget.initialIdentify;
  var _grouping = UploadGrouping.auto;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final several = widget.fileCount > 1;
    return AlertDialog(
      backgroundColor: colors.surface2,
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            MediaTypeSelector(
              value: _mediaType,
              onChanged: (value) => setState(() => _mediaType = value),
            ),
            if (several) ...<Widget>[
              const SizedBox(height: WaxSpace.s16),
              UploadGroupingSelector(
                value: _grouping,
                onChanged: (value) => setState(() => _grouping = value),
              ),
            ],
            const SizedBox(height: WaxSpace.s16),
            IdentifySwitch(
              value: _identify,
              mediaType: _mediaType,
              semanticsId: SemanticsIds.uploadIdentify,
              onChanged: (value) => setState(() => _identify = value),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        WaxButton(
          label: 'Cancel',
          kind: WaxButtonKind.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        WaxButton(
          label: 'Upload',
          semanticsId: SemanticsIds.uploadMediaConfirm,
          onPressed: () => Navigator.of(context).pop((
            mediaType: _mediaType,
            grouping: _grouping,
            identify: _identify,
          )),
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
    final colors = WaxColors.of(context);
    return Semantics(
      identifier: SemanticsIds.uploadGrouping,
      container: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'How should these files be grouped?',
            style: WaxType.overline.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: WaxSpace.s4),
          for (final (grouping, label, help) in _options)
            WaxOptionRow(
              title: label,
              subtitle: help,
              glyph: value == grouping ? WaxIcons.check : null,
              selected: value == grouping,
              semanticsId: SemanticsIds.uploadGroupingOption(grouping.wireName),
              onTap: () => onChanged(grouping),
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

  static String label(MediaType type) => switch (type) {
    MediaType.music => 'Music',
    MediaType.podcast => 'Podcast',
    MediaType.audiobook => 'Audiobook',
  };

  @override
  Widget build(BuildContext context) {
    return WaxChoice<MediaType>(
      label: 'What this is',
      value: value,
      semanticsId: SemanticsIds.uploadMediaType,
      options: MediaType.values,
      labelFor: label,
      onChanged: onChanged,
    );
  }
}

/// Does this stop for you, or go straight in as delivered? Named for
/// whichever truth applies: matching is a music question, so elsewhere
/// this only decides whether the submission waits.
class IdentifySwitch extends StatelessWidget {
  const IdentifySwitch({
    super.key,
    required this.value,
    required this.mediaType,
    required this.semanticsId,
    required this.onChanged,
  });

  /// Null is "nobody has said", drawn as on.
  final bool? value;

  /// What is being added, which decides what this control is called.
  final MediaType mediaType;

  final String semanticsId;
  final ValueChanged<bool> onChanged;

  String get _title => mediaType == MediaType.music
      ? 'Identify against MusicBrainz'
      : 'Review before adding';

  String get _help => mediaType == MediaType.music
      ? 'Matches it, then waits for your decision. Off adds it with the '
            'tags it has'
      : 'Waits for your decision. Off adds it with the tags it has';

  @override
  Widget build(BuildContext context) => WaxSettingRow(
    title: _title,
    help: _help,
    control: WaxSwitch(
      value: value ?? true,
      label: _title,
      semanticsId: semanticsId,
      onChanged: onChanged,
    ),
  );
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

  static const _labels = {
    'best': 'Best quality (recommended)',
    'opus': 'Opus',
    'm4a': 'M4A (AAC)',
    'mp3': 'MP3',
    'flac': 'FLAC',
  };

  @override
  Widget build(BuildContext context) {
    return WaxChoice<String>(
      label: 'Download format',
      value: value,
      semanticsId: SemanticsIds.acquireFormat,
      options: _labels.keys.toList(),
      labelFor: (format) => _labels[format] ?? format,
      onChanged: onChanged,
    );
  }
}
