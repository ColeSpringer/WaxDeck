import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../providers.dart';
import '../settings/client_settings_providers.dart';
import '../settings/prefs_controller.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import '../sync/sync_providers.dart';
import '../tools/tasks_screen.dart';
import 'file_picker_port.dart';
import 'uploads_controller.dart';

/// The one place new audio enters the library: a URL to acquire or a
/// file to upload, both landing in the review queue. Shared by the add
/// button and the uploads screen so there is one flow.

/// Whether this session can be offered a way in at all: the upload right,
/// which every path behind the sheet needs, and a server to hand the
/// files to.
///
/// One reading for the four surfaces that draw an add - home, the music
/// and audiobook hubs, and the music hub's own first-run invitation -
/// because a control that appears on three of them and not the fourth is
/// how the music hub came to have none.
bool canAddToLibrary(WidgetRef ref) {
  final canUpload =
      ref.watch(authControllerProvider).value?.user?.uploadEnabled ?? false;
  return canUpload && !ref.watch(offlineProvider);
}

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
      // Scrollable, because the sheet is capped at a fraction of the
      // window and four rows plus a header do not fit a phone held
      // sideways. It still sizes to its content wherever they do.
      child: SingleChildScrollView(
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
              SectionHeader(
                title: sheetContext.l10n.uploadsAddTitle,
                overline: sheetContext.l10n.uploadsAddOverline,
              ),
              WaxOptionRow(
                title: sheetContext.l10n.uploadsFromUrl,
                subtitle: sheetContext.l10n.uploadsFromUrlSubtitle,
                glyph: WaxIcons.downloads,
                semanticsId: SemanticsIds.addFromUrl,
                onTap: () => Navigator.of(sheetContext).pop('url'),
              ),
              if (picker != null)
                WaxOptionRow(
                  title: sheetContext.l10n.uploadsPick,
                  subtitle: sheetContext.l10n.uploadsPickSubtitle,
                  glyph: WaxIcons.add,
                  semanticsId: SemanticsIds.addUploadFile,
                  onTap: () => Navigator.of(sheetContext).pop('file'),
                ),
              if (picker != null && picker.canPickFolders)
                WaxOptionRow(
                  title: sheetContext.l10n.uploadsPickFolder,
                  subtitle: sheetContext.l10n.uploadsPickFolderSubtitle,
                  glyph: WaxIcons.albums,
                  semanticsId: SemanticsIds.addUploadFolder,
                  onTap: () => Navigator.of(sheetContext).pop('folder'),
                ),
              // What was added before, and the quota it is spending. This
              // sheet is the + control the uploads list stopped being a
              // navigation destination in favour of, so it is where the
              // lasting door to that list belongs: the other two ways in -
              // a notification about an upload, a review entry's origin
              // line - are news, and news is gone by the next launch.
              WaxOptionRow(
                title: sheetContext.l10n.uploadsSessionsTitle,
                subtitle: sheetContext.l10n.uploadsSessionsSubtitle,
                glyph: WaxIcons.recent,
                semanticsId: SemanticsIds.addUploadSessions,
                onTap: () => Navigator.of(sheetContext).pop('sessions'),
              ),
            ],
          ),
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
    case 'sessions':
      // Pushed, so back returns to the screen the sheet was opened over:
      // the list is not declared under any of them, and `go` would
      // strand a visitor who only wanted to check a quota.
      context.pushOnce(WaxRoute.uploads);
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
  final l10n = context.l10n;
  // Joined, not awaited in turn: both are pre-dialog seeds and paying
  // their round trips end to end doubles the wait before the sheet.
  final (identifyDefault, targets, remembered) = await _dialogSeeds(ref);
  if (!context.mounted) return;
  final request =
      await showDialog<
        ({
          String url,
          MediaType mediaType,
          String format,
          bool? identify,
          String libraryPid,
        })
      >(
        context: context,
        builder: (_) => AcquireDialog(
          initial: initial,
          initialUrl: initialUrl,
          initialIdentify: identifyDefault,
          targets: targets,
          rememberedTarget: remembered,
        ),
      );
  if (request == null) return;
  _rememberUploadTarget(ref, request.libraryPid);
  try {
    await ref
        .read(repositoryProvider)
        .createAcquisition(
          url: request.url,
          mediaType: request.mediaType,
          format: request.format,
          identify: request.identify,
          libraryPid: request.libraryPid.isEmpty ? null : request.libraryPid,
        );
    ref
      ..invalidate(uploadsProvider)
      ..invalidate(toolTasksProvider);
    // It runs in the background and lands in review rather than the
    // library, so the message says where to look.
    messenger.show(
      l10n.uploadsAcquireQueued,
      actionLabel: l10n.uploadsAcquireTasks,
      actionSemanticsId: SemanticsIds.acquireTasks,
      onAction: () => router.push<void>(WaxRoute.tasks),
    );
  } on WaxDeckApiException catch (e) {
    // A refusal of the URL somebody just pasted keeps the server's own
    // words: only it can say what was wrong with that address.
    messenger.show(explainRefusal(l10n, e));
  }
}

/// Picks files and hands them to the shared upload flow.
Future<void> pickAndUpload(
  BuildContext context,
  WidgetRef ref,
  FilePickerPort picker, {
  MediaType? initial,
}) async {
  final l10n = context.l10n;
  final files = await picker.pickAudioFiles(
    audioLabel: l10n.uploadsFileTypeAudio,
    anyLabel: l10n.uploadsFileTypeAny,
    formats: await resolveUploadFormats(ref),
  );
  if (files.isEmpty || !context.mounted) return;
  await uploadPickedFiles(context, ref, files, initial: initial);
}

/// What a walk's extension filter dropped, said where it is news and
/// quiet where it is not. Two cases speak: files on the DRM deny-list,
/// which look like audio and can never play, and a pick that kept
/// nothing at all, which otherwise just looks broken. Ordinary album
/// cruft - the cover image, the rip log, the cue sheet - is expected to
/// be left behind, and announcing it on every folder would teach people
/// to ignore the report that matters.
void reportSkippedFiles(
  ShellMessenger messenger,
  AppLocalizations l10n, {
  required int unsupported,
  required int drm,
  required bool nothingKept,
}) {
  if (drm > 0) {
    messenger.show(l10n.uploadsSkippedDrm(drm));
  } else if (nothingKept && unsupported > 0) {
    messenger.show(l10n.uploadsSkippedUnsupported(unsupported));
  }
}

/// Picks a folder and hands its audio files to the shared upload
/// flow, their in-folder hierarchy riding along as the clustering
/// hint. What the filter dropped is reported per [reportSkippedFiles]:
/// a folder of Audible files used to pick "nothing" with no word
/// about why.
Future<void> pickFolderAndUpload(
  BuildContext context,
  WidgetRef ref,
  FilePickerPort picker, {
  MediaType? initial,
}) async {
  final messenger = ref.read(shellMessengerProvider.notifier);
  final l10n = context.l10n;
  final FolderPick pick;
  try {
    pick = await picker.pickAudioFolder(
      formats: await resolveUploadFormats(ref),
    );
  } on PlatformException {
    // The pick itself failed - a ROM without a documents picker, a
    // provider that errored mid-walk. Said out loud: swallowed, the
    // folder tile just does nothing, and this caller is the surface's
    // only chance to word it.
    messenger.show(l10n.uploadsPickFolderFailed);
    return;
  }
  if (pick.files.isEmpty) {
    reportSkippedFiles(
      messenger,
      l10n,
      unsupported: pick.skippedUnsupported,
      drm: pick.skippedDrm,
      nothingKept: true,
    );
    return;
  }
  if (!context.mounted) return;
  await uploadPickedFiles(context, ref, pick.files, initial: initial);
  // After the flow rather than before it: the media-type dialog is
  // modal, and a toast raised under a modal is hidden from the
  // semantics tree and can expire before the dialog closes. The
  // messenger queues, so this shows after the identify announcement
  // rather than eating it. It also fires when the dialog was
  // cancelled, on purpose: the fact is about the pick, and "these
  // files can never play" holds whether or not an upload followed.
  reportSkippedFiles(
    messenger,
    l10n,
    unsupported: pick.skippedUnsupported,
    drm: pick.skippedDrm,
    nothingKept: false,
  );
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
  final router = GoRouter.of(context);
  // Held across the awaits below, which outlive the dialog: everything
  // this loop reports is worded from a code, and there is no context to
  // read a table through once the last upload settles.
  final l10n = context.l10n;
  final (identifyDefault, targets, remembered) = await _dialogSeeds(ref);
  if (!context.mounted) return;
  final choice =
      await showDialog<
        ({
          MediaType mediaType,
          UploadGrouping grouping,
          bool? identify,
          String libraryPid,
        })
      >(
        context: context,
        builder: (_) => MediaTypeDialog(
          initial: initial ?? MediaType.music,
          fileCount: files.length,
          initialIdentify: identifyDefault,
          targets: targets,
          rememberedTarget: remembered,
        ),
      );
  if (choice == null) return;
  _rememberUploadTarget(ref, choice.libraryPid);
  final libraryPid = choice.libraryPid.isEmpty ? null : choice.libraryPid;
  final repository = ref.read(repositoryProvider);
  String? batchId;
  if (files.length > 1) {
    try {
      final batch = await repository.createUploadBatch(
        grouping: choice.grouping,
        mediaType: choice.mediaType.wireName,
        libraryPid: libraryPid,
        identify: choice.identify,
      );
      batchId = batch.id;
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
      return;
    }
  }
  var uploaded = 0;
  for (final file in files) {
    try {
      await ref
          .read(uploadsProvider.notifier)
          .uploadPicked(
            file,
            mediaType: choice.mediaType.wireName,
            libraryPid: libraryPid,
            batchId: batchId,
            identify: choice.identify,
          );
      uploaded++;
    } on WaxDeckApiException catch (e) {
      // explainRefusal, not explainError: a size or a format the server
      // will not take is a refusal of the file this person just picked,
      // and its sentence names which limit and by how much. The table's
      // own words would say "over the storage limit" for a file no
      // allowance can ever admit.
      messenger.show(
        l10n.uploadsFileFailed(file.name, explainRefusal(l10n, e)),
      );
    } catch (_) {
      // The source stopped answering (a file moved or shrank between
      // pick and transfer). Named per file and the loop continues:
      // this failure sinking the siblings and the finalize would keep
      // everything that did arrive out of review.
      messenger.show(
        l10n.uploadsFileFailed(file.name, l10n.uploadsFileUnreadable),
      );
    }
  }
  var finalized = true;
  if (batchId != null) {
    try {
      await repository.completeUploadBatch(batchId);
    } on WaxDeckApiException catch (e) {
      // The error stands alone: a success announcement over a failed
      // finalize would send somebody to a review queue holding none of
      // their files.
      finalized = false;
      messenger.show(explainError(l10n, e));
    }
    // Finalization filled the members' review entries; refresh the
    // rows.
    ref.invalidate(uploadsProvider);
  }
  // With identification on, what arrived is in review rather than on
  // the shelves, and nothing on screen would otherwise say so - the
  // report of "added music and home never refreshed" was this window.
  // Only when the choice is known on: the switch's value is null only
  // when the account preference could not be read, and the server then
  // resolves the default itself - announcing review on a guess would
  // tell an opted-out account its files are waiting where the server
  // already shelved them.
  if (finalized && uploaded > 0 && (choice.identify ?? false)) {
    messenger.show(
      l10n.uploadsIdentifying(uploaded),
      actionLabel: l10n.commonOpenReview,
      actionSemanticsId: SemanticsIds.uploadIdentifyingReview,
      onAction: () => router.go(WaxRoute.review),
    );
  }
}

/// The libraries this account may file under, or none.
///
/// Read here rather than watched in the dialog because the dialog is
/// built once and a list arriving mid-tap would grow a row under a
/// pointer already moving; and because a server without the route, one
/// that refused the read, and one that never answers all degrade to the
/// same empty list - no picker, and the server routing as it always
/// did.
///
/// Time-boxed like its two neighbours and for the same reason: the
/// app's Dio carries no timeouts, so a server that takes the socket and
/// never answers would otherwise hold the dialog shut for good,
/// dropping picked files and eating a shared URL the gate has already
/// dequeued. try/catch bounds errors, not time.
Future<List<UploadTarget>> _uploadTargets(WidgetRef ref) => ref
    .read(uploadTargetsProvider.future)
    .catchError((Object _, StackTrace _) => const <UploadTarget>[])
    .timeout(_targetsWait, onTimeout: () => const <UploadTarget>[]);

/// How long a dialog waits on the target list before opening without a
/// picker.
const _targetsWait = Duration(seconds: 2);

/// The library the last submission was filed under, or empty.
///
/// Read straight from the store rather than through a [StoredSetting]:
/// that mixin answers its default synchronously and hydrates in the
/// background, and nothing else in the app reads this key, so every
/// read here would be the first one and would answer empty - the cold
/// start being exactly the launch this is for. Bounded like the reads
/// beside it, though this one is local.
Future<String> _rememberedTarget(WidgetRef ref) async {
  try {
    final store = ref.read(clientSettingsStoreProvider);
    final raw = await store
        .read(ClientSettingKeys.uploadTarget)
        .timeout(_targetsWait, onTimeout: () => null);
    return raw ?? '';
  } on Exception {
    return '';
  }
}

/// Remembers the library that was chosen, so the next submission opens
/// on it. An empty pid is the picker not having been a choice at all,
/// which must not overwrite a real answer from a server with several.
void _rememberUploadTarget(WidgetRef ref, String pid) {
  if (pid.isEmpty) return;
  final store = ref.read(clientSettingsStoreProvider);
  unawaited(
    store.write(ClientSettingKeys.uploadTarget, pid).catchError((Object _) {}),
  );
}

/// The remembered library and the candidate list, for the one intake
/// that opens no dialog. Public because the share gate is a sibling
/// file rather than a caller of the dialogs.
Future<(String, List<UploadTarget>)> sharedUploadTarget(WidgetRef ref) async {
  final remembered = _rememberedTarget(ref);
  final targets = _uploadTargets(ref);
  return (await remembered, await targets);
}

/// The three values a dialog opens on, gathered together so their
/// waits overlap rather than stack.
Future<(bool?, List<UploadTarget>, String)> _dialogSeeds(WidgetRef ref) async {
  final identify = _identifyDefault(ref);
  final targets = _uploadTargets(ref);
  final remembered = _rememberedTarget(ref);
  return (await identify, await targets, await remembered);
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
    this.targets = const [],
    this.rememberedTarget = '',
  });

  final MediaType initial;

  /// Prefills the URL field (a share-sheet handoff).
  final String? initialUrl;

  /// What the switch opens on; null is sent absent. Required, not
  /// defaulted: a caller that forgot it would ignore the preference.
  final bool? initialIdentify;

  /// Every library this account may file under, unfiltered: the medium
  /// is chosen inside the dialog, so the narrowing is too.
  final List<UploadTarget> targets;

  /// The library the last submission went to, honoured where it is
  /// still on offer for the chosen medium.
  final String rememberedTarget;

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

  /// The pid last chosen here, or the remembered one until somebody
  /// chooses. What is sent is [resolveUploadTarget] of it against the
  /// candidates for the chosen medium, resolved per build: switching
  /// the medium moves the choice onto one that medium offers, without
  /// this having to follow the move.
  late String _target = widget.rememberedTarget;

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
    final l10n = context.l10n;
    final url = _urlController.text.trim();
    final candidates = uploadTargetsFor(widget.targets, _mediaType);
    final target = resolveUploadTarget(candidates, _target);
    return AlertDialog(
      backgroundColor: colors.surface2,
      title: Text(l10n.uploadsFromUrl),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            WaxTextField(
              label: l10n.uploadsSourceUrl,
              hint: l10n.uploadsSourceUrlHint,
              controller: _urlController,
              autofocus: true,
              semanticsId: SemanticsIds.acquireUrl,
            ),
            const SizedBox(height: WaxSpace.s12),
            MediaTypeSelector(
              value: _mediaType,
              onChanged: (value) => setState(() => _mediaType = value),
            ),
            UploadTargetSelector(
              candidates: candidates,
              value: target,
              onChanged: (value) => setState(() => _target = value),
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
          label: l10n.commonCancel,
          kind: WaxButtonKind.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        WaxButton(
          label: l10n.uploadsDownload,
          semanticsId: SemanticsIds.acquireSubmit,
          onPressed: url.isEmpty
              ? null
              : () => Navigator.of(context).pop((
                  url: url,
                  mediaType: _mediaType,
                  format: _mediaType == MediaType.podcast ? 'best' : _format,
                  identify: _identify,
                  // Only where the picker was a real choice: one
                  // candidate is the routing the server would have done
                  // anyway, and naming it would pin a policy nobody
                  // asked for.
                  libraryPid: candidates.length > 1 ? target : '',
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
    this.targets = const [],
    this.rememberedTarget = '',
  });

  final MediaType initial;

  /// How many files are about to upload; above one, the grouping
  /// question appears.
  final int fileCount;

  /// What the identification switch opens on; see
  /// [AcquireDialog.initialIdentify].
  final bool? initialIdentify;

  /// See [AcquireDialog.targets].
  final List<UploadTarget> targets;

  /// See [AcquireDialog.rememberedTarget].
  final String rememberedTarget;

  @override
  State<MediaTypeDialog> createState() => _MediaTypeDialogState();
}

class _MediaTypeDialogState extends State<MediaTypeDialog> {
  late var _mediaType = widget.initial;
  late bool? _identify = widget.initialIdentify;
  var _grouping = UploadGrouping.auto;

  /// See [_AcquireDialogState._target].
  late String _target = widget.rememberedTarget;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final several = widget.fileCount > 1;
    final candidates = uploadTargetsFor(widget.targets, _mediaType);
    final target = resolveUploadTarget(candidates, _target);
    return AlertDialog(
      backgroundColor: colors.surface2,
      title: Text(
        several ? l10n.uploadsWhatMany(widget.fileCount) : l10n.uploadsWhatOne,
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
            UploadTargetSelector(
              candidates: candidates,
              value: target,
              onChanged: (value) => setState(() => _target = value),
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
          label: l10n.commonCancel,
          kind: WaxButtonKind.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        WaxButton(
          label: l10n.uploadsUpload,
          semanticsId: SemanticsIds.uploadMediaConfirm,
          onPressed: () => Navigator.of(context).pop((
            mediaType: _mediaType,
            grouping: _grouping,
            identify: _identify,
            libraryPid: candidates.length > 1 ? target : '',
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

  static List<(UploadGrouping, String, String)> _options(
    AppLocalizations l10n,
  ) => <(UploadGrouping, String, String)>[
    (
      UploadGrouping.auto,
      l10n.uploadsGroupingAuto,
      l10n.uploadsGroupingAutoHelp,
    ),
    (
      UploadGrouping.album,
      l10n.uploadsGroupingAlbum,
      l10n.uploadsGroupingAlbumHelp,
    ),
    (
      UploadGrouping.tracks,
      l10n.uploadsGroupingTracks,
      l10n.uploadsGroupingTracksHelp,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return Semantics(
      identifier: SemanticsIds.uploadGrouping,
      container: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.uploadsGroupingTitle,
            style: WaxType.overline.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: WaxSpace.s4),
          for (final (grouping, label, help) in _options(l10n))
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

  static String label(AppLocalizations l10n, MediaType type) => switch (type) {
    MediaType.music => l10n.uploadsMediaMusic,
    MediaType.podcast => l10n.uploadsMediaPodcast,
    MediaType.audiobook => l10n.uploadsMediaBook,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return WaxChoice<MediaType>(
      label: l10n.uploadsWhatThisIs,
      value: value,
      semanticsId: SemanticsIds.uploadMediaType,
      options: MediaType.values,
      labelFor: (type) => label(l10n, type),
      onChanged: onChanged,
    );
  }
}

/// Which library the submission is filed under, when the server offers
/// more than one candidate for the chosen medium.
///
/// Hidden below two candidates on purpose: a question with one answer
/// is not a question, and the server routes exactly as it always did
/// when nothing is named. It is also hidden while the read is in
/// flight, so the dialog never grows a row under a pointer already
/// moving to Upload.
///
/// The help line is there because the choice is narrower than the word
/// "library" suggests: it selects whose settings govern the import, not
/// the folder the bytes land in, which is the catalog's own routing.
class UploadTargetSelector extends StatelessWidget {
  const UploadTargetSelector({
    super.key,
    required this.candidates,
    required this.value,
    required this.onChanged,
  });

  final List<UploadTarget> candidates;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (candidates.length < 2) return const SizedBox.shrink();
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final names = {for (final t in candidates) t.pid: t.name};
    return Padding(
      padding: const EdgeInsets.only(top: WaxSpace.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          WaxChoice<String>(
            label: l10n.uploadsLibrary,
            value: value,
            semanticsId: SemanticsIds.uploadLibrary,
            optionSemanticsIdFor: SemanticsIds.uploadLibraryOption,
            options: candidates.map((t) => t.pid).toList(),
            labelFor: (pid) => names[pid] ?? pid,
            onChanged: onChanged,
          ),
          const SizedBox(height: WaxSpace.s4),
          Text(
            l10n.uploadsLibraryHelp,
            style: WaxType.caption.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// The candidate this dialog opens on: the remembered choice where it
/// is still on offer, and the first candidate otherwise. A pid from
/// another server, or one whose library stopped accepting this medium,
/// is not sent.
String resolveUploadTarget(List<UploadTarget> candidates, String remembered) {
  if (candidates.isEmpty) return '';
  if (candidates.any((t) => t.pid == remembered)) return remembered;
  return candidates.first.pid;
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

  String _title(AppLocalizations l10n) => mediaType == MediaType.music
      ? l10n.uploadsIdentifyMusic
      : l10n.uploadsIdentifyOther;

  String _help(AppLocalizations l10n) => mediaType == MediaType.music
      ? l10n.uploadsIdentifyMusicHelp
      : l10n.uploadsIdentifyOtherHelp;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return WaxSettingRow(
      title: _title(l10n),
      help: _help(l10n),
      control: WaxSwitch(
        value: value ?? true,
        label: _title(l10n),
        semanticsId: semanticsId,
        onChanged: onChanged,
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

  /// The formats offered, in order. The codec names are written out
  /// rather than derived from the wire token, because Opus is a name
  /// and MP3 is an acronym.
  static const _formats = ['best', 'opus', 'm4a', 'mp3', 'flac'];

  static String _label(AppLocalizations l10n, String format) =>
      switch (format) {
        'best' => l10n.uploadsFormatBest,
        'opus' => 'Opus',
        'm4a' => 'M4A (AAC)',
        'mp3' => 'MP3',
        'flac' => 'FLAC',
        _ => format,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return WaxChoice<String>(
      label: l10n.uploadsFormat,
      value: value,
      semanticsId: SemanticsIds.acquireFormat,
      options: _formats,
      labelFor: (format) => _label(l10n, format),
      onChanged: onChanged,
    );
  }
}
