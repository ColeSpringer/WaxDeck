import 'package:waxdeck_ui/waxdeck_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/shell_messages.dart';
import 'add_to_library.dart';
import 'local_file_reader.dart';
import 'share_intake.dart';
import 'uploads_controller.dart';

/// Sits above the signed-in shell and routes share-sheet payloads:
/// polls the intake port on start and every resume (the two moments a
/// share can have arrived), then opens the add-from-URL dialog for a
/// shared link or uploads shared audio files directly.
class ShareIntakeGate extends ConsumerStatefulWidget {
  const ShareIntakeGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ShareIntakeGate> createState() => _ShareIntakeGateState();
}

class _ShareIntakeGateState extends ConsumerState<ShareIntakeGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A cold start from the share sheet queued its payload before the
    // first frame; drain once the tree is up.
    WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _drain();
  }

  Future<void> _drain() async {
    final port = ref.read(shareIntakeProvider);
    final intake = await port.consumeShared();
    if (intake == null || !mounted) return;
    switch (intake) {
      case SharedUrlIntake(:final url):
        await acquireFromUrl(context, ref, initialUrl: url);
      case SharedFilesIntake(:final files):
        await _uploadShared(port, files);
    }
  }

  Future<void> _uploadShared(
    ShareIntakePort port,
    List<SharedFile> files,
  ) async {
    // The container rather than `ref` past the first await: this gate
    // lives in the signed-in scope, so a sign-out mid-share takes it,
    // and its `ref`, away. The messenger keeps the session that shared.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = container.read(shellMessengerProvider);
    // The sharing account's, for every file: a swap stops the run.
    final repository = container.read(repositoryProvider);
    // Held beside the messenger and for the same reason: the loop below
    // outlives this frame.
    final l10n = context.l10n;
    // A multi-file share groups through a batch with auto-detection -
    // no dialog: the share sheet is a fire-and-forget gesture, and
    // auto clustering does the right thing for an album share while
    // leaving unrelated files separate.
    //
    // The library follows the same rule: no dialog means no choice, so
    // the last one this device filed under is used where the server
    // still offers it, and nothing is named otherwise. A share must not
    // grow a prompt, and inheriting the last answer is closer to what
    // the person meant than sending none is on a server with several.
    // The kind is the one the files would be offered in a dialog: an
    // .m4b among them makes the share an audiobook.
    // A share carries no folders, so detection only ever seeds music or
    // audiobook; the fallback is for the type's sake.
    final kind =
        detectUploadMediaType([
          for (final f in files) f.name,
        ], foldered: false) ??
        MediaType.music;
    final libraryPid = await _sharedTarget(ref, kind);
    String? batchId;
    if (files.length > 1) {
      try {
        final batch = await repository.createUploadBatch(
          grouping: UploadGrouping.auto,
          mediaType: kind.wireName,
          libraryPid: libraryPid,
        );
        batchId = batch.id;
      } on WaxDeckApiException catch (e) {
        messenger.show(explainError(l10n, e), channel: ShellChannel.uploads);
        return;
      }
    }
    await untilUploadsListed(container.read(uploadsProvider.future));
    for (final file in files) {
      // Measured here rather than inside the upload, so a refusal can
      // be told against the allowance as a picked file's is.
      int? size;
      try {
        size = await localFileLength(file.path);
        // Path-backed: the platform side already staged the share to
        // an app-private file, and the upload streams it from disk so
        // an audiobook-sized share never sits whole in memory.
        await container
            .read(uploadsProvider.notifier)
            .uploadFromPath(
              fileName: file.name,
              path: file.path,
              mediaType: kind.wireName,
              libraryPid: libraryPid,
              batchId: batchId,
              sizeBytes: size,
              through: repository,
            );
      } on WaxDeckApiException catch (e) {
        messenger.show(
          l10n.uploadsFileFailed(
            file.name,
            explainUploadRefusal(
              l10n,
              e,
              sizeBytes: size,
              quota: container.read(uploadsProvider).value?.quota,
            ),
          ),
          channel: ShellChannel.uploads,
        );
      }
    }
    if (batchId != null) {
      try {
        await repository.completeUploadBatch(batchId);
      } on WaxDeckApiException catch (e) {
        messenger.show(explainError(l10n, e), channel: ShellChannel.uploads);
      }
      container.invalidate(uploadsProvider);
    }
  }

  /// The library a dialogless share is filed under: the remembered one
  /// where it is still a candidate for [kind], and null otherwise. Null
  /// is the server routing exactly as it did before this existed.
  Future<String?> _sharedTarget(WidgetRef ref, MediaType kind) async {
    final (remembered, targets) = await sharedUploadTarget(ref);
    if (remembered.isEmpty) return null;
    final candidates = uploadTargetsFor(targets, kind);
    if (candidates.length < 2) return null;
    return candidates.any((t) => t.pid == remembered) ? remembered : null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
