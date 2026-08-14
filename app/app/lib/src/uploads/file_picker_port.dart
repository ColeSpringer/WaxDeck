import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'file_picker_impl.dart' as impl;

/// Audio extensions the pickers offer and the drop areas accept
/// (lowercase, no dot): a hardcoded mirror of the server's default
/// accepted-format set (uploadFormatSet in
/// server/internal/service/uploads.go - keep in step). Native dialogs
/// keep an "All files" group so a custom WAXDECK_UPLOAD_FORMATS set
/// stays reachable; the server's session create is the real gate.
const kAcceptedAudioExtensions = {
  'flac', 'mp3', 'm4a', 'm4b', 'aac', 'ogg', 'oga', 'opus', //
  'wav', 'aif', 'aiff', 'mka', 'webm',
};

/// Whether the file name's extension is in the accepted set
/// (case-insensitive; extensionless names never match).
bool hasAcceptedExtension(String name, Set<String> extensions) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return false;
  return extensions.contains(name.substring(dot + 1).toLowerCase());
}

/// One picked or dropped file as a lazy reference: the transfer pulls
/// bytes in windows when it needs them, so a multi-hundred-megabyte
/// album never sits whole in memory. Native picks carry [path] and
/// stream from disk; web picks carry [openRead] over the browser's
/// file handle.
class PickedAudioFile {
  const PickedAudioFile({
    required this.name,
    required this.size,
    this.relativeDir = '',
    this.path,
    this.openRead,
  });

  /// Bare file name.
  final String name;

  /// Size in bytes, known up front for the session declaration.
  final int size;

  /// Directory relative to the picked or dropped folder, forward-slash
  /// separated; empty for a file at the top. Carried to the server as
  /// the batch's clustering hint (`batchPath`).
  final String relativeDir;

  /// Local filesystem path, set for native picks and drops.
  final String? path;

  /// Windowed byte-stream accessor reading `[start, end)` lazily; set
  /// for web picks and drops (and usable everywhere it is set).
  final Stream<List<int>> Function([int? start, int? end])? openRead;
}

/// Platform file picking behind a WaxDeck-owned interface, so screens
/// never touch a picker plugin directly.
abstract interface class FilePickerPort {
  /// Opens the platform picker; empty when the user cancels.
  /// [audioLabel] and [anyLabel] name the dialog's two filter rows: a
  /// port is built off the tree and has no table to word them from.
  Future<List<PickedAudioFile>> pickAudioFiles({
    required String audioLabel,
    required String anyLabel,
  });

  /// Whether [pickAudioFolder] works here (desktop only: Android
  /// folder access means SAF tree URIs, which this port does not
  /// speak, and web has no folder dialog).
  bool get canPickFolders;

  /// Picks a folder and returns its audio files recursively, with
  /// [PickedAudioFile.relativeDir] carrying the in-folder hierarchy
  /// rooted at the folder's own name; empty when the user cancels.
  Future<List<PickedAudioFile>> pickAudioFolder();

  /// Picks one arbitrary file filtered to [extensions] (the backup
  /// archive case); null when the user cancels. [label] and [anyLabel]
  /// name the dialog's two filter rows, as in [pickAudioFiles].
  Future<PickedAudioFile?> pickFile({
    required Set<String> extensions,
    required String label,
    required String anyLabel,
  });
}

/// The platform port. Null on platforms with no picker wiring - and in
/// widget tests overriding it so - which hides every pick affordance;
/// that hide-when-null contract predates the real implementations and
/// stands.
final filePickerProvider = Provider<FilePickerPort?>(
  (ref) => impl.createFilePickerPort(),
);
