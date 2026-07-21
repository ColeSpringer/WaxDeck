import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One picked audio file, fully read into memory. Upload sessions chunk
/// straight from these bytes, so the port never hands platform file
/// handles to widget code.
class PickedAudioFile {
  const PickedAudioFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Platform file picking behind a WaxDeck-owned interface, so screens
/// never touch a picker plugin directly.
abstract interface class FilePickerPort {
  /// Opens the platform picker and resolves to the chosen audio files;
  /// empty when the user cancels.
  Future<List<PickedAudioFile>> pickAudioFiles();
}

/// Unavailable by default, like the download manager on web: the real
/// pickers (native file dialogs, web drag-and-drop) land with a later
/// platform wiring pass. The uploads screen hides its pick affordance
/// while this is null.
final filePickerProvider = Provider<FilePickerPort?>((ref) => null);
