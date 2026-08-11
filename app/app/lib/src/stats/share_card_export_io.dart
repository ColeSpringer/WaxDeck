import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'share_card_export.dart';

/// Android hands the card to the share sheet; the desktops write a file.
ShareCardExporter createShareCardExporter() =>
    defaultTargetPlatform == TargetPlatform.android
    ? const _AndroidShareCardExporter()
    : const _DesktopShareCardExporter();

/// Out through the share sheet, over the channel this app already owns
/// for intake. Nothing else on the phone can open app-private storage,
/// so a saved path here would do nothing.
class _AndroidShareCardExporter implements ShareCardExporter {
  const _AndroidShareCardExporter();

  static const _channel = MethodChannel('waxdeck/share');

  @override
  bool get canExport => true;

  @override
  Future<ShareCardOutcome> export({
    required List<int> png,
    required String fileName,
    required String subject,
  }) async {
    try {
      await _channel.invokeMethod<void>('shareImage', <String, Object?>{
        'bytes': Uint8List.fromList(png),
        'fileName': fileName,
        'subject': subject,
      });
      return const ShareCardShared();
    } on PlatformException catch (e) {
      return ShareCardFailed(e.message ?? 'The share sheet refused the image');
    } on MissingPluginException {
      // An older platform side than this Dart side: real on a partial
      // upgrade, and not something to crash a share button over.
      return const ShareCardFailed('This build cannot share images');
    }
  }
}

/// Onto disk, in the directory the desktop already means by "where
/// downloads go", and the outcome says where.
class _DesktopShareCardExporter implements ShareCardExporter {
  const _DesktopShareCardExporter();

  @override
  bool get canExport => true;

  @override
  Future<ShareCardOutcome> export({
    required List<int> png,
    required String fileName,
    required String subject,
  }) async {
    try {
      final directory =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      final file = File(_freePath(directory, fileName));
      await _writeAtomically(file, Uint8List.fromList(png));
      return ShareCardSaved(file.path);
    } on FileSystemException catch (e) {
      return ShareCardFailed(e.message);
    } on MissingPlatformDirectoryException {
      return const ShareCardFailed('There is nowhere to save images here');
    }
  }

  /// The first name in the directory that is not taken, so exporting the
  /// same card twice keeps both rather than overwriting last year's.
  static String _freePath(Directory directory, String fileName) {
    final stem = p.basenameWithoutExtension(fileName);
    final extension = p.extension(fileName);
    var candidate = p.join(directory.path, fileName);
    var n = 2;
    while (File(candidate).existsSync()) {
      candidate = p.join(directory.path, '$stem-$n$extension');
      n++;
    }
    return candidate;
  }
}

/// Keeps two concurrent writes from sharing a temp file.
int _writes = 0;

/// Temp in the target directory, fsync, verify, atomic rename (the
/// file-write durability rule). `_freePath` picks an unused name, so
/// the rename replaces nothing - and would replace silently if it did.
Future<void> _writeAtomically(File file, Uint8List bytes) async {
  final temp = File('${file.path}.${_writes++}.tmp');
  try {
    final handle = await temp.open(mode: FileMode.writeOnly);
    try {
      await handle.writeFrom(bytes);
      await handle.flush();
    } finally {
      await handle.close();
    }
    // The rule's verify step: a short write is a full disk, and
    // renaming one publishes a truncated image as a whole one.
    if (await temp.length() != bytes.length) {
      throw FileSystemException('short write', temp.path);
    }
    await temp.rename(file.path);
  } on Object {
    try {
      await temp.delete();
    } on FileSystemException {
      // Already gone, or a filesystem that will not say.
    }
    rethrow;
  }
}
