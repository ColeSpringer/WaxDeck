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
import '../tools/tool_tasks_provider.dart';
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

/// The media types a file or a link can be added as. Podcasts are added
/// by subscribing to a feed, so they are not among them.
const uploadableMediaTypes = <MediaType>[MediaType.music, MediaType.audiobook];

/// [type] where it can be added, music otherwise: what the dialogs open
/// on for a caller in a section (podcasts) that has no medium of its own
/// here.
MediaType uploadableMediaType(MediaType? type) =>
    type != null && uploadableMediaTypes.contains(type)
    ? type
    : MediaType.music;

bool _isM4b(String name) => name.toLowerCase().endsWith('.m4b');

/// The media type a pick of audio files named [names] opens the medium
/// choice on: an audiobook when any is an `.m4b`, music for one file or
/// loose files, and null for several files from a folder ([foldered]),
/// which could as well be an album as a book and so are asked rather than
/// guessed. The person's choice, where they are asked, wins over it.
MediaType? detectUploadMediaType(List<String> names, {required bool foldered}) {
  if (names.any(_isM4b)) return MediaType.audiobook;
  if (names.length > 1 && foldered) return null;
  return MediaType.music;
}

// The server folds the same names (server/internal/match/cluster.go,
// bookDirPattern). The separators are spelled out (space, tab, no-break
// space, _ . -) because Dart's \s and Go's differ beyond ASCII.
final _discFolder = RegExp(
  r'^(disc|disk|cd|part)[ \t\u00A0_.-]*\d+$',
  caseSensitive: false,
);

/// The grouping a pick of [files] opens on. An audiobook whose files sit
/// in one folder (or in disc-named subfolders of one) is one book in
/// parts; loose files, a folder of book folders and several `.m4b` (each
/// normally a whole book) are left to the server, as is all music.
UploadGrouping defaultUploadGrouping(
  MediaType type,
  List<PickedAudioFile> files,
) {
  if (type != MediaType.audiobook) return UploadGrouping.auto;
  if (files.where((f) => _isM4b(f.name)).length > 1) return UploadGrouping.auto;
  final dirs = {for (final f in files) f.relativeDir};
  if (dirs.contains('')) return UploadGrouping.auto;
  if (dirs.length == 1) return UploadGrouping.album;
  // A disc subfolder belongs to its parent: one book where every
  // directory resolves to the same one.
  String bookDir(String dir) {
    final cut = dir.lastIndexOf('/');
    final leaf = dir.substring(cut + 1);
    return cut > 0 && _discFolder.hasMatch(leaf) ? dir.substring(0, cut) : dir;
  }

  return dirs.map(bookDir).toSet().length == 1
      ? UploadGrouping.album
      : UploadGrouping.auto;
}

/// Opens the add sheet. [fixed] is the kind of the section the caller is
/// in (music, audiobook): the dialogs then take it instead of asking.
/// With none, a pick of files is asked what it is and preselected from
/// its names and folders (see [detectUploadMediaType]), and a link is
/// asked with music preselected.
Future<void> showAddToLibrarySheet(
  BuildContext context,
  WidgetRef ref, {
  MediaType? fixed,
}) async {
  final picker = ref.read(filePickerProvider);
  final defaultType = uploadableMediaType(fixed);
  final colors = WaxColors.of(context);
  final choice = await showWaxSheet<String>(
    context: context,
    backgroundColor: colors.surface2,
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
              SectionHeader(title: sheetContext.l10n.uploadsAddTitle),
              WaxOptionRow(
                title: sheetContext.l10n.uploadsFromUrl,
                glyph: WaxIcons.downloads,
                semanticsId: SemanticsIds.addFromUrl,
                onTap: () => Navigator.of(sheetContext).pop('url'),
              ),
              if (picker != null)
                WaxOptionRow(
                  title: sheetContext.l10n.uploadsPick,
                  glyph: WaxIcons.add,
                  semanticsId: SemanticsIds.addUploadFile,
                  onTap: () => Navigator.of(sheetContext).pop('file'),
                ),
              if (picker != null && picker.canPickFolders)
                WaxOptionRow(
                  title: sheetContext.l10n.uploadsPickFolder,
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
      await acquireFromUrl(
        context,
        ref,
        initial: defaultType,
        kindFixed: fixed != null && uploadableMediaTypes.contains(fixed),
      );
    case 'file':
      if (picker != null) {
        await pickAndUpload(context, ref, picker, fixed: fixed);
      }
    case 'folder':
      if (picker != null) {
        await pickFolderAndUpload(context, ref, picker, fixed: fixed);
      }
    case 'sessions':
      // Gone to: the list has a place of its own, and a push would file
      // it inside whichever tab the sheet was opened on.
      context.go(WaxRoute.uploads);
  }
}

/// Queues a server-side download of a source URL; the result flows
/// through uploads and the review queue. [initialUrl] prefills the
/// dialog (a share-sheet handoff); [kindFixed] takes [initial] as the
/// section's own kind and leaves the question out.
Future<void> acquireFromUrl(
  BuildContext context,
  WidgetRef ref, {
  MediaType initial = MediaType.music,
  bool kindFixed = false,
  String? initialUrl,
}) async {
  final messenger = ref.read(shellMessengerProvider);
  final router = GoRouter.of(context);
  final l10n = context.l10n;
  // Past the first await, the container rather than `ref`: the request
  // outlives the surface that made it, and `ref` dies with its widget.
  final container = ProviderScope.containerOf(context, listen: false);
  // Joined, not awaited in turn: both are pre-dialog seeds and paying
  // their round trips end to end doubles the wait before the sheet.
  final (seed, targets, remembered) = await _dialogSeeds(ref);
  if (!context.mounted) return;
  Future<ToolTask> send(AcquireRequest request) async {
    _rememberUploadTarget(container, request.libraryPid);
    final task = await container
        .read(repositoryProvider)
        .createAcquisition(
          url: request.url,
          mediaType: request.mediaType,
          playlist: request.playlist,
          format: request.format,
          identify: request.identify,
          acceptBestMatch: request.acceptBestMatch,
          libraryPid: request.libraryPid.isEmpty ? null : request.libraryPid,
        );
    container
      ..invalidate(uploadsProvider)
      ..invalidate(toolTasksProvider);
    return task;
  }

  void queued(ToolTask task) => messenger.show(
    // It runs in the background and lands in review rather than the
    // library, so the message says where to look.
    _queuedMessage(l10n, task),
    actionLabel: l10n.uploadsAcquireTasks,
    actionSemanticsId: SemanticsIds.acquireTasks,
    onAction: () => router.go(WaxRoute.tasks),
  );

  final task = await showDialog<ToolTask>(
    context: context,
    builder: (_) => AcquireDialog(
      initial: initial,
      kindFixed: kindFixed,
      initialUrl: initialUrl,
      initialIdentify: seed.identify,
      initialAcceptBest: seed.acceptBest,
      targets: targets,
      rememberedTarget: remembered,
      send: send,
      // The dialog closed before the answer: the message is the only
      // place left to say it.
      onUnseen: (outcome) => switch (outcome) {
        final ToolTask task => queued(task),
        final WaxDeckApiException error => messenger.show(
          explainRefusal(l10n, error),
        ),
        _ => null,
      },
    ),
  );
  if (task != null) queued(task);
}

/// What was queued, by name when the answer carries one.
String _queuedMessage(AppLocalizations l10n, ToolTask task) {
  final title = task.itemTitle?.trim() ?? '';
  if (title.isEmpty) return l10n.uploadsAcquireQueued;
  final source = task.summary?['source'];
  return l10n.uploadsAcquireQueuedTitled(source is String ? source : '', title);
}

/// Picks files and hands them to the shared upload flow.
Future<void> pickAndUpload(
  BuildContext context,
  WidgetRef ref,
  FilePickerPort picker, {
  MediaType? fixed,
}) async {
  // Held across the picker, which can outlive the widget that opened it.
  final messenger = ref.read(shellMessengerProvider);
  final l10n = context.l10n;
  final formats = await resolveUploadFormats(ref);
  final picked = await picker.pickAudioFiles(
    audioLabel: l10n.uploadsFileTypeAudio,
    anyLabel: l10n.uploadsFileTypeAny,
    formats: formats,
  );
  // The "any file" filter lets a DRM container through; it is dropped
  // and named here, as the folder and drop walks do, rather than asked
  // its media type and refused one by one.
  final files = [
    for (final f in picked)
      if (!formats.refuses(f.name)) f,
  ];
  if (files.isNotEmpty && context.mounted) {
    await uploadPickedFiles(context, ref, files, fixed: fixed);
  }
  // After the flow, for the reason pickFolderAndUpload gives: a toast
  // raised under the media-type dialog is hidden and can expire there.
  reportSkippedFiles(
    messenger,
    l10n,
    unsupported: 0,
    drm: picked.length - files.length,
    nothingKept: files.isEmpty,
  );
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

/// Why a file was not uploaded, worded the same whichever way it came
/// in.
///
/// `quota-exceeded` is two refusals the code does not tell apart: an
/// allowance already full of staged sessions, which clearing Past
/// uploads makes room in, and a file larger than the whole allowance,
/// which nothing anybody clears admits. The allowance as the session
/// list last read it ([quota]) tells them apart against [sizeBytes];
/// without both, the table's sentence is the one true of either.
/// Anything else refused the file this person chose, in the server's
/// words where it has some.
String explainUploadRefusal(
  AppLocalizations l10n,
  Object error, {
  required int? sizeBytes,
  required UploadQuota? quota,
}) {
  final limit = quota?.quotaBytes;
  if (error is WaxDeckApiException &&
      error.code == 'quota-exceeded' &&
      limit != null &&
      sizeBytes != null) {
    return sizeBytes > limit
        ? l10n.uploadsFileOverQuota(l10n.formatBytes(limit))
        : l10n.uploadsQuotaFull;
  }
  return explainRefusal(l10n, error);
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
  MediaType? fixed,
}) async {
  final messenger = ref.read(shellMessengerProvider);
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
  // The upload asks its question where the pick was made; with that
  // gone, nothing is sent, and the report below still is said.
  if (context.mounted) {
    await uploadPickedFiles(context, ref, pick.files, fixed: fixed);
  }
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
  MediaType? fixed,
}) async {
  final messenger = ref.read(shellMessengerProvider);
  final router = GoRouter.of(context);
  // Held across the awaits below, which outlive the dialog: everything
  // this loop reports is worded from a code, and there is no context to
  // read a table through once the last upload settles.
  final l10n = context.l10n;
  // Past the first await, the container rather than `ref`: the
  // transfers outlive the surface that started them, and a refusal, the
  // files after it and the batch's finalize must not die with it.
  final container = ProviderScope.containerOf(context, listen: false);
  // An empty file is named rather than sent; when nothing else was
  // picked there is no question to ask about it.
  final nonEmpty = files.where((f) => f.size > 0).toList();
  final sending = nonEmpty.length;
  if (sending == 0) {
    for (final file in files) {
      messenger.show(l10n.uploadsFileFailed(file.name, l10n.uploadsFileEmpty));
    }
    return;
  }
  final (seed, targets, remembered) = await _dialogSeeds(ref);
  if (!context.mounted) return;
  final fixedKind = fixed != null && uploadableMediaTypes.contains(fixed)
      ? fixed
      : null;
  // What is uploaded is what is asked about: an empty file is only named.
  final kind =
      fixedKind ??
      detectUploadMediaType([
        for (final f in nonEmpty) f.name,
      ], foldered: nonEmpty.any((f) => f.relativeDir.isNotEmpty));
  final choice =
      await showDialog<
        ({
          MediaType mediaType,
          UploadGrouping grouping,
          bool? identify,
          bool? acceptBestMatch,
          String libraryPid,
        })
      >(
        context: context,
        builder: (_) => MediaTypeDialog(
          initial: kind,
          kindFixed: fixedKind != null,
          fileCount: sending,
          audiobookGrouping: fixedKind == MediaType.music
              ? null
              : defaultUploadGrouping(MediaType.audiobook, files),
          initialIdentify: seed.identify,
          initialAcceptBest: seed.acceptBest,
          targets: targets,
          rememberedTarget: remembered,
        ),
      );
  if (choice == null) return;
  _rememberUploadTarget(container, choice.libraryPid);
  final libraryPid = choice.libraryPid.isEmpty ? null : choice.libraryPid;
  final repository = container.read(repositoryProvider);
  String? batchId;
  if (sending > 1) {
    try {
      final batch = await repository.createUploadBatch(
        grouping: choice.grouping,
        mediaType: choice.mediaType.wireName,
        libraryPid: libraryPid,
        identify: choice.identify,
        acceptBestMatch: choice.acceptBestMatch,
      );
      batchId = batch.id;
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
      return;
    }
  }
  await untilUploadsListed(container.read(uploadsProvider.future));
  var uploaded = 0;
  for (final file in files) {
    if (file.size == 0) {
      messenger.show(l10n.uploadsFileFailed(file.name, l10n.uploadsFileEmpty));
      continue;
    }
    try {
      // A file discarded on its way is neither counted nor reported.
      final accepted = await container
          .read(uploadsProvider.notifier)
          .uploadPicked(
            file,
            mediaType: choice.mediaType.wireName,
            libraryPid: libraryPid,
            batchId: batchId,
            identify: choice.identify,
            acceptBestMatch: choice.acceptBestMatch,
            // The account that picked them: a swap stops the run.
            through: repository,
          );
      if (accepted) uploaded++;
    } on WaxDeckApiException catch (e) {
      messenger.show(
        l10n.uploadsFileFailed(
          file.name,
          explainUploadRefusal(
            l10n,
            e,
            sizeBytes: file.size,
            quota: container.read(uploadsProvider).value?.quota,
          ),
        ),
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
    container.invalidate(uploadsProvider);
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
void _rememberUploadTarget(ProviderContainer container, String pid) {
  if (pid.isEmpty) return;
  final store = container.read(clientSettingsStoreProvider);
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

/// The values a dialog opens on, gathered together so their waits
/// overlap rather than stack.
Future<(_PrefsSeed, List<UploadTarget>, String)> _dialogSeeds(
  WidgetRef ref,
) async {
  final seed = _prefsSeed(ref);
  final targets = _uploadTargets(ref);
  final remembered = _rememberedTarget(ref);
  return (await seed, await targets, await remembered);
}

/// What the two switches open on; see [_prefsSeed].
typedef _PrefsSeed = ({bool? identify, bool? acceptBest});

/// What the identification and accept-best switches open on. Awaited,
/// not sampled: the provider is lazy, so a synchronous read answers the
/// default for anybody who has not opened Settings. Null where it cannot
/// be read: Identify then goes absent rather than overriding an opt-out
/// with a guess, while accept-best draws and sends off.
///
/// Bounded, because the app's Dio carries no timeouts: a server that
/// takes the socket and never answers would otherwise hold the sheet
/// shut for good, dropping picked files and eating a shared URL the
/// gate has already dequeued.
Future<_PrefsSeed> _prefsSeed(WidgetRef ref) async {
  const unread = (identify: null, acceptBest: null);
  _PrefsSeed read(Prefs? prefs) => (
    identify: !(prefs?.identifyOptOut ?? false),
    acceptBest: prefs?.acceptBestMatch ?? false,
  );
  final loaded = ref.read(prefsControllerProvider);
  if (loaded.hasValue) return read(loaded.value);
  return ref
      .read(prefsControllerProvider.future)
      .then<_PrefsSeed>(read, onError: (Object _, StackTrace _) => unread)
      .timeout(_prefsSeedWait, onTimeout: () => unread);
}

/// How long a sheet waits on the account preference before opening
/// without it.
const _prefsSeedWait = Duration(seconds: 5);

/// What a submitted dialog asks the server to acquire.
typedef AcquireRequest = ({
  String url,
  MediaType mediaType,
  bool? playlist,
  String format,
  bool? identify,
  bool? acceptBestMatch,
  String libraryPid,
});

/// The URL entry dialog.
///
/// It sends the request itself and stays open while the server checks
/// the link, so a refusal is worded under the field for the person to
/// correct; it pops the queued task on success.
class AcquireDialog extends StatefulWidget {
  const AcquireDialog({
    super.key,
    this.initial = MediaType.music,
    this.kindFixed = false,
    this.initialUrl,
    required this.initialIdentify,
    required this.initialAcceptBest,
    required this.send,
    required this.onUnseen,
    this.targets = const [],
    this.rememberedTarget = '',
  });

  final MediaType initial;

  /// Whether [initial] is the section's own kind: the selector is then
  /// left out.
  final bool kindFixed;

  /// Prefills the URL field (a share-sheet handoff).
  final String? initialUrl;

  /// What the switch opens on; null is sent absent. Required, not
  /// defaulted: a caller that forgot it would ignore the preference.
  final bool? initialIdentify;

  /// What the accept-best switch opens on, under the same rule.
  final bool? initialAcceptBest;

  /// Sends the request; throws [WaxDeckApiException] for a refusal.
  final Future<ToolTask> Function(AcquireRequest request) send;

  /// Takes the outcome (a [ToolTask] or a [WaxDeckApiException]) when the
  /// dialog is no longer there to show it.
  final void Function(Object outcome) onUnseen;

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
  late var _mediaType = uploadableMediaType(widget.initial);
  // Null is "nobody has said": drawn as on, sent absent.
  late bool? _identify = widget.initialIdentify;
  late bool? _acceptBest = widget.initialAcceptBest;
  var _format = 'best';

  /// The pid last chosen here, or the remembered one until somebody
  /// chooses. What is sent is [resolveUploadTarget] of it against the
  /// candidates for the chosen medium, resolved per build: switching
  /// the medium moves the choice onto one that medium offers, without
  /// this having to follow the move.
  late String _target = widget.rememberedTarget;

  /// The text a submit found not to be a web address, while the field
  /// still holds it: the next edit clears it, so the error never runs
  /// ahead of the typing, and a caret moving is not an edit.
  String? _refused;

  /// Whether a request is out: the server is checking the link.
  var _busy = false;

  /// What the source said about [_refusalFor], worded for the field.
  String? _refusal;
  String? _refusalFor;

  /// What went wrong that is not about the link (a full disk, a timeout):
  /// said above the form rather than under the field, until the next send
  /// or an edit of the link it was said about.
  String? _failure;
  String? _failureFor;

  /// The playlist switch; only ever true while the link names both a
  /// video and a playlist.
  var _playlist = false;

  @override
  void initState() {
    super.initState();
    _urlController.addListener(
      () => setState(() {
        if (_urlController.text != _refused) _refused = null;
        if (_urlController.text.trim() != _refusalFor) _refusal = null;
        if (_urlController.text.trim() != _failureFor) _failure = null;
        if (!namesVideoAndPlaylist(_urlController.text)) _playlist = false;
      }),
    );
  }

  Future<void> _send(AcquireRequest request) async {
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    final l10n = context.l10n;
    // Whether this dialog is still on screen to take an answer: closing
    // it keeps it mounted through its exit transition, and a pop then
    // would take the page beneath it.
    bool showing() => mounted && (route?.isActive ?? false);
    setState(() {
      _busy = true;
      _refusal = null;
      _failure = null;
    });
    final Object outcome;
    try {
      outcome = await widget.send(request);
    } on WaxDeckApiException catch (error) {
      if (!showing()) {
        if (mounted) setState(() => _busy = false);
        widget.onUnseen(error);
        return;
      }
      if (!_aboutLink(error)) {
        setState(() {
          _busy = false;
          _failure = explainRefusal(l10n, error);
          _failureFor = request.url;
        });
        return;
      }
      // A link edited while the check ran has moved on from the answer;
      // it is said as a message rather than lost.
      if (_urlController.text.trim() != request.url) {
        setState(() => _busy = false);
        widget.onUnseen(error);
        return;
      }
      setState(() {
        _busy = false;
        _refusalFor = request.url;
        _refusal = explainRefusal(l10n, error);
      });
      return;
    } catch (error, stack) {
      // Not the server's answer: a defect for the log, and the dialog is
      // not left silent and stuck behind it.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'waxdeck uploads',
        ),
      );
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = explainError(l10n, error);
          _failureFor = request.url;
        });
      }
      return;
    }
    if (showing()) {
      navigator.pop(outcome);
    } else {
      widget.onUnseen(outcome);
    }
  }

  /// Whether a refusal is the source's or the server's word on the link
  /// itself, which belongs under the field: the source's refusal, and an
  /// `invalid-request` whose params name the address. The server sends
  /// that code for a library, media type or format it refuses too, and
  /// anything else, a bridge that is not running included, says nothing
  /// about the link: the dialog's general line takes it.
  static bool _aboutLink(WaxDeckApiException error) =>
      error.code == 'source-refused' || refusesAddress(error);

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
      title: Text(
        !widget.kindFixed
            ? l10n.uploadsFromUrl
            : _mediaType == MediaType.audiobook
            ? l10n.uploadsFromUrlBook
            : l10n.uploadsFromUrlMusic,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (_failure case final failure?) ...<Widget>[
              Semantics(
                liveRegion: true,
                child: Text(
                  failure,
                  style: WaxType.caption.copyWith(color: colors.error),
                ),
              ),
              const SizedBox(height: WaxSpace.s12),
            ],
            WaxTextField(
              label: l10n.uploadsSourceUrl,
              hint: l10n.uploadsSourceUrlHint,
              controller: _urlController,
              autofocus: true,
              semanticsId: SemanticsIds.acquireUrl,
              errorText: _refused != null
                  ? l10n.uploadsSourceUrlInvalid
                  : _refusal,
            ),
            if (namesVideoAndPlaylist(url))
              AcquirePlaylistSwitch(
                value: _playlist,
                onChanged: (value) => setState(() {
                  _playlist = value;
                  _refusal = null;
                }),
              ),
            const SizedBox(height: WaxSpace.s12),
            if (!widget.kindFixed)
              MediaTypeSelector(
                value: _mediaType,
                onChanged: (value) => setState(() => _mediaType = value),
              ),
            UploadTargetSelector(
              candidates: candidates,
              value: target,
              onChanged: (value) => setState(() => _target = value),
            ),
            const SizedBox(height: WaxSpace.s12),
            AcquireFormatSelector(
              value: _format,
              onChanged: (value) => setState(() => _format = value),
            ),
            const SizedBox(height: WaxSpace.s12),
            IdentifySwitch(
              value: _identify,
              mediaType: _mediaType,
              semanticsId: SemanticsIds.acquireIdentify,
              onChanged: (value) => setState(() => _identify = value),
            ),
            if (_mediaType == MediaType.music)
              AcceptBestSwitch(
                value: _acceptBest,
                identify: _identify ?? true,
                semanticsId: SemanticsIds.acquireAcceptBest,
                onChanged: (value) => setState(() => _acceptBest = value),
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
          label: _busy ? l10n.uploadsAcquireChecking : l10n.uploadsDownload,
          semanticsId: SemanticsIds.acquireSubmit,
          busy: _busy,
          onPressed: url.isEmpty || _busy
              ? null
              : !isWebLink(url)
              ? () => setState(() => _refused = _urlController.text)
              : () => _send((
                  url: url,
                  mediaType: _mediaType,
                  // Only while the switch is drawn, and only when on.
                  playlist: _playlist && namesVideoAndPlaylist(url)
                      ? true
                      : null,
                  format: _format,
                  identify: _identify,
                  acceptBestMatch: _sendsAcceptBest(
                    _mediaType,
                    _identify,
                    _acceptBest,
                  ),
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

/// Whether [text] is an http or https address with a host: the only
/// links an acquisition takes.
bool isWebLink(String text) {
  final uri = Uri.tryParse(text);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

/// Whether [text] is a link that names a video and the playlist it sits
/// in: a `v` and a `list` together, or a `youtu.be/<id>` with a `list`.
/// Such a link downloads the video unless the person asks for the list.
bool namesVideoAndPlaylist(String text) {
  final trimmed = text.trim();
  if (!isWebLink(trimmed)) return false;
  final uri = Uri.parse(trimmed);
  final Map<String, String> query;
  try {
    query = uri.queryParameters;
  } on FormatException {
    return false;
  }
  if ((query['list'] ?? '').isEmpty) return false;
  if ((query['v'] ?? '').isNotEmpty) return true;
  return uri.host.toLowerCase() == 'youtu.be' &&
      uri.pathSegments.any((s) => s.isNotEmpty);
}

/// The media-type prompt, plus the grouping intent for several files:
/// an album must not arrive as one entry per track, and a grab of
/// singles must not merge into one album. A [kindFixed] dialog (opened
/// from the music or audiobook section) says the kind instead of asking.
class MediaTypeDialog extends StatefulWidget {
  const MediaTypeDialog({
    super.key,
    this.initial = MediaType.music,
    this.kindFixed = false,
    this.fileCount = 1,
    this.audiobookGrouping,
    required this.initialIdentify,
    required this.initialAcceptBest,
    this.targets = const [],
    this.rememberedTarget = '',
  });

  /// What the selector opens on; null opens it with nothing chosen, and
  /// the confirm waits for a choice.
  final MediaType? initial;

  /// Whether [initial] is the section's own kind: the selector is then
  /// left out and the title names the kind.
  final bool kindFixed;

  /// How many files are about to upload; above one, the grouping
  /// question appears.
  final int fileCount;

  /// The grouping an audiobook of these files opens on (see
  /// [defaultUploadGrouping]); music always opens on auto-detection.
  /// Until the person picks one, a change of kind moves the grouping to
  /// that kind's default.
  final UploadGrouping? audiobookGrouping;

  /// What the identification switch opens on; see
  /// [AcquireDialog.initialIdentify].
  final bool? initialIdentify;

  /// See [AcquireDialog.initialAcceptBest].
  final bool? initialAcceptBest;

  /// See [AcquireDialog.targets].
  final List<UploadTarget> targets;

  /// See [AcquireDialog.rememberedTarget].
  final String rememberedTarget;

  @override
  State<MediaTypeDialog> createState() => _MediaTypeDialogState();
}

class _MediaTypeDialogState extends State<MediaTypeDialog> {
  late MediaType? _mediaType = widget.initial == null
      ? null
      : uploadableMediaType(widget.initial);
  late bool? _identify = widget.initialIdentify;
  late bool? _acceptBest = widget.initialAcceptBest;
  late var _grouping = _defaultGrouping(_mediaType);
  var _groupingTouched = false;

  /// See [_AcquireDialogState._target].
  late String _target = widget.rememberedTarget;

  UploadGrouping _defaultGrouping(MediaType? kind) =>
      kind == MediaType.audiobook
      ? widget.audiobookGrouping ?? UploadGrouping.auto
      : UploadGrouping.auto;

  String _title(AppLocalizations l10n) {
    final several = widget.fileCount > 1;
    if (!widget.kindFixed) {
      return several
          ? l10n.uploadsWhatMany(widget.fileCount)
          : l10n.uploadsWhatOne;
    }
    final book = _mediaType == MediaType.audiobook;
    return several
        ? (book
              ? l10n.uploadsWhatManyBook(widget.fileCount)
              : l10n.uploadsWhatManyMusic(widget.fileCount))
        : (book ? l10n.uploadsWhatOneBook : l10n.uploadsWhatOneMusic);
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final several = widget.fileCount > 1;
    final chosen = _mediaType;
    final candidates = chosen == null
        ? const <UploadTarget>[]
        : uploadTargetsFor(widget.targets, chosen);
    final target = resolveUploadTarget(candidates, _target);
    return AlertDialog(
      backgroundColor: colors.surface2,
      title: Text(_title(l10n)),
      // Scrollable: with the grouping selector the content outgrows a
      // short viewport (a phone in landscape) and an AlertDialog does
      // not scroll on its own.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (!widget.kindFixed)
              MediaTypeSelector(
                value: _mediaType,
                onChanged: (value) => setState(() {
                  _mediaType = value;
                  if (!_groupingTouched) _grouping = _defaultGrouping(value);
                }),
              ),
            // Everything below words itself for the medium, so it waits
            // for the choice.
            if (chosen != null) ...<Widget>[
              UploadTargetSelector(
                candidates: candidates,
                value: target,
                onChanged: (value) => setState(() => _target = value),
              ),
              if (several) ...<Widget>[
                const SizedBox(height: WaxSpace.s16),
                UploadGroupingSelector(
                  value: _grouping,
                  mediaType: chosen,
                  fileCount: widget.fileCount,
                  onChanged: (value) => setState(() {
                    _grouping = value;
                    _groupingTouched = true;
                  }),
                ),
              ],
              const SizedBox(height: WaxSpace.s16),
              IdentifySwitch(
                value: _identify,
                mediaType: chosen,
                semanticsId: SemanticsIds.uploadIdentify,
                onChanged: (value) => setState(() => _identify = value),
              ),
              if (chosen == MediaType.music)
                AcceptBestSwitch(
                  value: _acceptBest,
                  identify: _identify ?? true,
                  semanticsId: SemanticsIds.uploadAcceptBest,
                  onChanged: (value) => setState(() => _acceptBest = value),
                ),
            ],
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
          onPressed: chosen == null
              ? null
              : () => Navigator.of(context).pop((
                  mediaType: chosen,
                  grouping: _grouping,
                  identify: _identify,
                  acceptBestMatch: _sendsAcceptBest(
                    chosen,
                    _identify,
                    _acceptBest,
                  ),
                  libraryPid: candidates.length > 1 ? target : '',
                )),
        ),
      ],
    );
  }
}

/// The grouping-intent selector for a multi-file upload, worded for
/// [mediaType]: albums for music, books in parts for an audiobook.
class UploadGroupingSelector extends StatelessWidget {
  const UploadGroupingSelector({
    super.key,
    required this.value,
    required this.mediaType,
    required this.fileCount,
    required this.onChanged,
  });

  final UploadGrouping value;
  final MediaType mediaType;

  /// How many files the pick holds, for "One book in {count} parts".
  final int fileCount;
  final ValueChanged<UploadGrouping> onChanged;

  List<(UploadGrouping, String, String?)> _options(AppLocalizations l10n) =>
      mediaType == MediaType.audiobook
      ? <(UploadGrouping, String, String?)>[
          (
            UploadGrouping.auto,
            l10n.uploadsGroupingAuto,
            l10n.uploadsGroupingBookAutoHelp,
          ),
          (UploadGrouping.album, l10n.uploadsGroupingBookOne(fileCount), null),
          (UploadGrouping.tracks, l10n.uploadsGroupingBookEach, null),
        ]
      : <(UploadGrouping, String, String?)>[
          (
            UploadGrouping.auto,
            l10n.uploadsGroupingAuto,
            l10n.uploadsGroupingAutoHelp,
          ),
          (UploadGrouping.album, l10n.uploadsGroupingAlbum, null),
          (UploadGrouping.tracks, l10n.uploadsGroupingTracks, null),
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
/// URL-acquisition dialogs; only one of them is ever open at a time. It
/// offers [uploadableMediaTypes], so [value] is one of them, or null
/// while nothing is chosen yet.
class MediaTypeSelector extends StatelessWidget {
  const MediaTypeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  }) : assert(
         value != MediaType.podcast,
         'podcasts are added by subscribing to a feed',
       );

  final MediaType? value;
  final ValueChanged<MediaType> onChanged;

  /// Podcasts are not offered, so they are not worded: the wire name keeps
  /// a stray one legible.
  static String label(AppLocalizations l10n, MediaType type) => switch (type) {
    MediaType.music => l10n.uploadsMediaMusic,
    MediaType.audiobook => l10n.uploadsMediaBook,
    MediaType.podcast => type.wireName,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return WaxChoice<MediaType?>(
      label: l10n.uploadsWhatThisIs,
      value: value,
      semanticsId: SemanticsIds.uploadMediaType,
      optionSemanticsIdFor: (type) =>
          SemanticsIds.uploadMediaTypeOption(type?.wireName ?? ''),
      options: uploadableMediaTypes,
      labelFor: (type) =>
          type == null ? l10n.uploadsChooseMedium : label(l10n, type),
      onChanged: (type) {
        if (type != null) onChanged(type);
      },
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
    final l10n = context.l10n;
    final names = {for (final t in candidates) t.pid: t.name};
    return Padding(
      padding: const EdgeInsets.only(top: WaxSpace.s16),
      // The tip beside the picker, not inside it: the picker is one merged
      // node, and a tip under one never opens. "Library" reads as where
      // the files go, which the server decides.
      child: titleWithInfo(
        WaxChoice<String>(
          label: l10n.uploadsLibrary,
          value: value,
          semanticsId: SemanticsIds.uploadLibrary,
          optionSemanticsIdFor: SemanticsIds.uploadLibraryOption,
          options: candidates.map((t) => t.pid).toList(),
          labelFor: (pid) => names[pid] ?? pid,
          onChanged: onChanged,
        ),
        l10n.uploadsLibraryHelp,
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

  String _info(AppLocalizations l10n) => mediaType == MediaType.music
      ? l10n.uploadsIdentifyMusicHelp
      : l10n.uploadsIdentifyOtherHelp;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return WaxSettingRow(
      title: _title(l10n),
      info: _info(l10n),
      control: WaxSwitch(
        value: value ?? true,
        label: _title(l10n),
        semanticsId: semanticsId,
        onChanged: onChanged,
      ),
    );
  }
}

/// Whether a link naming both a video and a playlist takes the whole
/// playlist; off takes the video alone.
class AcquirePlaylistSwitch extends StatelessWidget {
  const AcquirePlaylistSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return WaxSettingRow(
      title: l10n.uploadsAcquirePlaylist,
      info: l10n.uploadsAcquirePlaylistHelp,
      control: WaxSwitch(
        value: value,
        label: l10n.uploadsAcquirePlaylist,
        semanticsId: SemanticsIds.acquirePlaylist,
        onChanged: onChanged,
      ),
    );
  }
}

/// The accept-best choice a submission carries: only for music with
/// identification on, where it can act, and always what the switch shows
/// (unread preferences draw off, so off is sent). Left out otherwise, so the
/// account preference (inert there) decides.
bool? _sendsAcceptBest(
  MediaType? mediaType,
  bool? identify,
  bool? acceptBest,
) => mediaType == MediaType.music && (identify ?? true)
    ? acceptBest ?? false
    : null;

/// Whether a clear best match is taken without waiting for review. Drawn
/// under [IdentifySwitch] for music, and disabled while [identify] is off.
class AcceptBestSwitch extends StatelessWidget {
  const AcceptBestSwitch({
    super.key,
    required this.value,
    required this.identify,
    required this.semanticsId,
    required this.onChanged,
  });

  /// Null is "nobody has said", drawn as off.
  final bool? value;

  /// Whether Identify is on; the switch cannot act without it.
  final bool identify;

  final String semanticsId;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return WaxSettingRow(
      title: l10n.uploadsAcceptBestTitle,
      info: l10n.uploadsAcceptBestHelp,
      control: WaxSwitch(
        value: value ?? false,
        label: l10n.uploadsAcceptBestTitle,
        semanticsId: semanticsId,
        onChanged: identify ? onChanged : null,
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
