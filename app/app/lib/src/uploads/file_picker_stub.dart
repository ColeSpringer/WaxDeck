import 'package:file_selector/file_selector.dart';

import 'file_picker_port.dart';

/// No picker wiring on this platform: the provider stays null and
/// every pick affordance hides.
FilePickerPort? createFilePickerPort() => null;

Future<bool> droppedPathIsDirectory(String path) async => false;

Future<FolderPick> expandDroppedDirectory(
  String path,
  Set<String> extensions,
) async => const FolderPick();

Future<PickedAudioFile> pickedFromXFile(
  XFile file, {
  String relativeDir = '',
}) async {
  throw UnsupportedError('no file access on this platform');
}
