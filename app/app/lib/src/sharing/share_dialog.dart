import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';

/// Expiry choices the share dialog offers.
enum ShareExpiry {
  never(null, 'Never'),
  day(24, '1 day'),
  week(168, '1 week'),
  month(720, '30 days');

  const ShareExpiry(this.hours, this.label);

  /// Lifetime in hours; null never expires.
  final int? hours;

  final String label;
}

/// The full URL a share link is copied as. The server resolves share
/// URLs against the client base, which is empty on web builds (the URL
/// stays origin-relative there); the page origin completes those.
String shareAbsoluteUrl(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  final base = waxDeckBaseUrl;
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

  static String _stamp(int ms) {
    final d = Duration(milliseconds: ms);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      return '${d.inHours}:$m:$s';
    }
    return '${d.inMinutes}:$s';
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final share = await ref
          .read(repositoryProvider)
          .createShare(
            pid: widget.pid,
            expiresInHours: _expiry.hours,
            allowDownload: _allowDownload,
            positionMs: _startAtPosition ? widget.positionMs : null,
          );
      await Clipboard.setData(ClipboardData(text: shareAbsoluteUrl(share.url)));
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Link copied')));
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final positionMs = widget.positionMs;
    return AlertDialog(
      title: const Text('Share link'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Expires'),
            trailing: Semantics(
              identifier: 'share-expiry',
              child: DropdownButton<ShareExpiry>(
                key: const Key('share-expiry'),
                value: _expiry,
                onChanged: (choice) {
                  if (choice != null) setState(() => _expiry = choice);
                },
                items: [
                  for (final choice in ShareExpiry.values)
                    DropdownMenuItem(value: choice, child: Text(choice.label)),
                ],
              ),
            ),
          ),
          SwitchListTile(
            key: const Key('share-allow-download'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow download'),
            value: _allowDownload,
            onChanged: (v) => setState(() => _allowDownload = v),
          ),
          if (positionMs != null && positionMs > 0)
            CheckboxListTile(
              key: const Key('share-start-at'),
              contentPadding: EdgeInsets.zero,
              title: Text('Start at ${_stamp(positionMs)}'),
              value: _startAtPosition,
              onChanged: (v) => setState(() => _startAtPosition = v ?? false),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        Semantics(
          identifier: 'share-create',
          label: 'Create link',
          button: true,
          child: FilledButton(
            key: const Key('share-create'),
            onPressed: _busy ? null : _create,
            child: const Text('Create link'),
          ),
        ),
      ],
    );
  }
}
