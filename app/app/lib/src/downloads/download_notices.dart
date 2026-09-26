import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../sync/sync_providers.dart';
import 'downloads_controller.dart';

/// The download notices' words, from the app's copy.
DownloadCopy downloadCopy(AppLocalizations l10n) => DownloadCopy(
  downloading: l10n.downloadsNoticeRunning,
  downloaded: l10n.downloadsNoticeDone,
  failed: l10n.downloadsNoticeFailed,
  part: l10n.downloadsNoticePart,
);

/// Says why downloads want notifications before Android asks a second
/// time, which it allows once somebody has refused.
class DownloadNoticeRationale extends ConsumerStatefulWidget {
  const DownloadNoticeRationale({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<DownloadNoticeRationale> createState() =>
      _DownloadNoticeRationaleState();
}

class _DownloadNoticeRationaleState
    extends ConsumerState<DownloadNoticeRationale> {
  StreamSubscription<void>? _asks;

  @override
  void initState() {
    super.initState();
    _asks = ref
        .read(downloadManagerProvider)
        ?.notificationRationale
        .listen((_) => unawaited(_explain()));
  }

  @override
  void dispose() {
    unawaited(_asks?.cancel());
    super.dispose();
  }

  Future<void> _explain() async {
    final l10n = context.l10n;
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.downloadsNoticeAskTitle),
        content: Text(l10n.downloadsNoticeAskBody),
        actions: <Widget>[
          WaxButton(
            label: l10n.downloadsNoticeAskLater,
            kind: WaxButtonKind.text,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          WaxButton(
            label: l10n.downloadsNoticeAskAllow,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (allow != true || !mounted) return;
    await ref.read(downloadsProvider.notifier).askForNotifications();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
