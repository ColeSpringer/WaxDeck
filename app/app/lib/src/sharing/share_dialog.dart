import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';
import 'shares_controller.dart';

/// Expiry choices the share dialog offers.
enum ShareExpiry {
  day(24),
  week(168),
  month(720),
  never(null);

  const ShareExpiry(this.hours);

  /// Lifetime in hours; null never expires.
  final int? hours;

  String labelOf(AppLocalizations l10n) => switch (this) {
    ShareExpiry.day => l10n.sharingExpiryDay,
    ShareExpiry.week => l10n.sharingExpiryWeek,
    ShareExpiry.month => l10n.sharingExpiryMonth,
    ShareExpiry.never => l10n.sharingExpiryNever,
  };
}

/// The full URL a share link is copied as. The server resolves share
/// URLs against the client base, which is empty on web builds (the URL
/// stays origin-relative there); the page origin completes those.
String shareAbsoluteUrl(WidgetRef ref, String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  final base = ref.read(serverBaseUrlProvider);
  if (base.isEmpty) return Uri.base.resolve(url).toString();
  return '$base$url';
}

/// Opens the share-link dialog for one target. [positionMs] offers a
/// start-at-current-position checkbox; pass it only for podcast
/// episodes launched from the player.
Future<void> showShareLinkDialog(
  BuildContext context, {
  required String pid,
  int? positionMs,
}) => showDialog<void>(
  context: context,
  builder: (_) => ShareLinkDialog(pid: pid, positionMs: positionMs),
);

/// Mints a public share link: expiry choice, allow-download switch, and
/// for episodes a start-at-position checkbox. On success the absolute
/// URL lands on the clipboard.
///
/// The allow-download switch stays enabled regardless of the account's
/// download permission: the caller's own permissions are not visible
/// client-side, so the server is the one to refuse.
///
/// Minting and copying are one step, which is 6.18's own wording and is
/// what a share is for: a link nobody copied is a capability handed to
/// nobody, still valid, still counting against the list.
class ShareLinkDialog extends ConsumerStatefulWidget {
  const ShareLinkDialog({super.key, required this.pid, this.positionMs});

  final String pid;

  /// Current playback position, offered as the share's start point.
  final int? positionMs;

  @override
  ConsumerState<ShareLinkDialog> createState() => _ShareLinkDialogState();
}

class _ShareLinkDialogState extends ConsumerState<ShareLinkDialog> {
  var _expiry = ShareExpiry.never;
  var _allowDownload = false;
  var _startAtPosition = false;
  var _busy = false;

  Future<void> _create() async {
    if (_busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    // The container rather than `ref`: the link is minted whether or not
    // this dialog is still on screen when the server answers, and the
    // list it joined has to hear about it either way. `ref` is dead the
    // moment this State is disposed; the container is not.
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final share = await container
          .read(repositoryProvider)
          .createShare(
            pid: widget.pid,
            expiresInHours: _expiry.hours,
            allowDownload: _allowDownload,
            positionMs: _startAtPosition ? widget.positionMs : null,
          );
      await Clipboard.setData(
        ClipboardData(text: shareAbsoluteUrl(ref, share.url)),
      );
      // The lists this link just joined, so a shares screen left open
      // behind the dialog is not a list missing its newest row - and
      // the console's oversight listing, which holds this row too.
      invalidateShareListings(container);
      // Dismissed while the link was being minted: the link exists and
      // is on the clipboard, but popping again would take the screen
      // underneath with it.
      if (!mounted) return;
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.sharingLinkCopied)));
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final positionMs = widget.positionMs;
    return AlertDialog(
      backgroundColor: colors.surface1,
      title: Text(
        l10n.sharingDialogTitle,
        style: WaxType.headline.copyWith(color: colors.textPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l10n.sharingDialogBody,
            style: WaxType.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: WaxSpace.s16),
          WaxSettingRow(
            title: l10n.sharingExpires,
            help: l10n.sharingExpiresHelp,
            control: WaxChoice<ShareExpiry>(
              value: _expiry,
              options: ShareExpiry.values,
              labelFor: (choice) => choice.labelOf(l10n),
              label: l10n.sharingExpires,
              semanticsId: SemanticsIds.shareExpiry,
              onChanged: (choice) => setState(() => _expiry = choice),
            ),
          ),
          WaxSettingRow(
            title: l10n.sharingAllowDownload,
            help: l10n.sharingAllowDownloadHelp,
            control: WaxSwitch(
              value: _allowDownload,
              label: l10n.sharingAllowDownload,
              semanticsId: SemanticsIds.shareAllowDownload,
              onChanged: (value) => setState(() => _allowDownload = value),
            ),
          ),
          if (positionMs != null && positionMs > 0)
            WaxSettingRow(
              title: l10n.sharingStartAt(
                formatTimecode(Duration(milliseconds: positionMs)),
              ),
              help: l10n.sharingStartAtHelp,
              control: WaxSwitch(
                value: _startAtPosition,
                label: l10n.sharingStartAtLabel,
                semanticsId: SemanticsIds.shareStartAt,
                onChanged: (value) => setState(() => _startAtPosition = value),
              ),
            ),
        ],
      ),
      actions: <Widget>[
        WaxButton(
          label: l10n.commonCancel,
          kind: WaxButtonKind.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        WaxButton(
          label: l10n.sharingCreate,
          semanticsId: SemanticsIds.shareCreate,
          onPressed: _busy ? null : _create,
        ),
      ],
    );
  }
}
