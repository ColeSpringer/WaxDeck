import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../music/album_detail.dart';
import '../music/music_controllers.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';

/// Confirms and performs a per-member detach: the track leaves the
/// release a MusicBrainz id pins it to and lands on the album its own
/// tags imply.
///
/// Write-back is a switch, defaulted on. On it is what makes the detach
/// durable - the file still names the release otherwise, so the next
/// re-resolve adopts the track back - but a read-only library refuses
/// the whole call with it on, and the catalog-only detach the API
/// supports is the only way to fix a mis-scan there. A switch says
/// which one is happening; pinning it hid the choice and the failure.
///
/// Takes no `ref`, like [confirmDeleteItem] beside it: the sheet that
/// offered this is popped before the server answers, so the listings
/// showing the track are told through the container.
Future<void> confirmDetachItem(
  BuildContext context, {
  required String pid,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final container = ProviderScope.containerOf(context, listen: false);
  var writeBack = true;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(l10n.libraryMenuDetachConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.libraryMenuDetachConfirmBody),
            const SizedBox(height: WaxSpace.s12),
            WaxSettingRow(
              title: l10n.metadataWriteBackTitle,
              help: l10n.libraryMenuDetachWriteBackHelp,
              control: WaxSwitch(
                label: l10n.metadataWriteBackTitle,
                value: writeBack,
                semanticsId: SemanticsIds.itemMenuDetachWriteBack,
                onChanged: (v) => setDialogState(() => writeBack = v),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          WaxButton(
            label: l10n.commonCancel,
            kind: WaxButtonKind.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          WaxButton(
            label: l10n.libraryMenuDetach,
            semanticsId: SemanticsIds.itemMenuDetachConfirm,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    ),
  );
  if (!(confirmed ?? false)) return;
  try {
    final result = await container
        .read(repositoryProvider)
        .detachItem(pid, writeBack: writeBack);
    // Both albums: the one the track left and the one it landed on.
    // The catalog invalidation is on its way over the socket too; this
    // is what makes the move show now rather than shortly.
    container
      ..invalidate(musicItemsProvider)
      ..invalidate(albumDetailProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          <String>[
            l10n.libraryMenuDetached,
            if (result.writeBackFailures.isNotEmpty)
              l10n.metadataWriteBackWarning,
          ].join('\n'),
        ),
      ),
    );
  } on WaxDeckApiException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(explainRefusal(l10n, e))));
  }
}
