import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'share_card_export.dart';

/// The browser keeps the card the way it keeps everything else: as a
/// download.
ShareCardExporter createShareCardExporter() => const _WebShareCardExporter();

class _WebShareCardExporter implements ShareCardExporter {
  const _WebShareCardExporter();

  @override
  bool get canExport => true;

  @override
  Future<ShareCardOutcome> export({
    required List<int> png,
    required String fileName,
    required String subject,
  }) async {
    // A blob, not a data: URI - a 1080x1920 PNG base64s past the URL
    // length Safari accepts.
    final blob = web.Blob(
      <JSUint8Array>[Uint8List.fromList(png).toJS].toJS,
      web.BlobPropertyBag(type: 'image/png'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = fileName
      ..style.display = 'none';
    // Firefox ignores a click on an anchor that is not in the tree.
    web.document.body!.appendChild(anchor);
    anchor.click();
    anchor.remove();
    // Withdrawing the URL in the same turn cancels the download it
    // had only just started.
    unawaited(
      Future<void>.delayed(
        const Duration(seconds: 30),
        () => web.URL.revokeObjectURL(url),
      ),
    );
    return ShareCardSaved(fileName);
  }
}
