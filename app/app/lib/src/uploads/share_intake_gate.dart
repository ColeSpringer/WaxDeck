import 'package:waxdeck_ui/waxdeck_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import 'add_to_library.dart';
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
    final messenger = ScaffoldMessenger.of(context);
    // A multi-file share groups through a batch with auto-detection -
    // no dialog: the share sheet is a fire-and-forget gesture, and
    // auto clustering does the right thing for an album share while
    // leaving unrelated files separate.
    String? batchId;
    if (files.length > 1) {
      try {
        final batch = await ref
            .read(repositoryProvider)
            .createUploadBatch(
              grouping: UploadGrouping.auto,
              mediaType: MediaType.music.wireName,
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
        // Path-backed: the platform side already staged the share to
        // an app-private file, and the upload streams it from disk so
        // an audiobook-sized share never sits whole in memory.
        await ref
            .read(uploadsProvider.notifier)
            .uploadFromPath(
              fileName: file.name,
              path: file.path,
              mediaType: MediaType.music.wireName,
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
        await ref.read(repositoryProvider).completeUploadBatch(batchId);
      } on WaxDeckApiException catch (e) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
      ref.invalidate(uploadsProvider);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
