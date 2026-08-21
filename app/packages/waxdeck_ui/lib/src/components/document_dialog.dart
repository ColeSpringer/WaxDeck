import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../tokens/colors.dart';
import '../tokens/typography.dart';
import 'controls.dart';

/// A generated document on screen, selectable, with one button that puts
/// it on the clipboard.
///
/// One implementation, because the playlist M3U export, the playlist NSP
/// export and the podcast OPML export had each grown their own and had
/// already drifted: two popped the dialog before confirming the copy and
/// one drew its snackbar behind the still-open modal, where nobody sees
/// it.
///
/// The clipboard rather than a file on purpose, and the same on every
/// platform: the web build has no file-save surface, and a document that
/// pastes into another player's import box needs no download to be
/// useful. Every string is the caller's - this package has no
/// translation table - and [onCopied] is what the caller does once the
/// dialog is gone, which is where a snackbar can actually be read.
Future<void> showDocumentDialog(
  BuildContext context, {
  required String title,
  required String document,
  required String closeLabel,
  required String copyLabel,
  VoidCallback? onCopied,
  String? copySemanticsId,
  Key? documentKey,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: SelectableText(
          document,
          key: documentKey,
          style: WaxType.monoData.copyWith(
            color: WaxColors.of(context).textPrimary,
          ),
        ),
      ),
    ),
    actions: <Widget>[
      WaxButton(
        label: closeLabel,
        kind: WaxButtonKind.text,
        onPressed: () => Navigator.of(context).pop(),
      ),
      WaxButton(
        label: copyLabel,
        semanticsId: copySemanticsId,
        onPressed: () async {
          final navigator = Navigator.of(context);
          await Clipboard.setData(ClipboardData(text: document));
          // Closes first: a snackbar renders on the scaffold behind the
          // modal, where nobody would see the confirmation.
          if (navigator.mounted) navigator.pop();
          onCopied?.call();
        },
      ),
    ],
  ),
);
