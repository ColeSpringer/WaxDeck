import 'package:file_selector/file_selector.dart';

import 'file_picker_port.dart';

FilePickerPort? createFilePickerPort() => _WebFilePickerPort();

/// Web drop items are never filesystem paths.
Future<bool> droppedPathIsDirectory(String path) async => false;

/// Web directory drops arrive as recursive drop items, never as bare
/// paths; nothing to expand here.
Future<List<PickedAudioFile>> expandDroppedDirectory(
  String path,
  Set<String> extensions,
) async => const [];

/// Converts one picker or drop XFile: a lazy browser-file reference
/// whose ranged openRead slices the underlying Blob, so only the
/// window in flight ever materializes in memory.
Future<PickedAudioFile> pickedFromXFile(
  XFile file, {
  String relativeDir = '',
}) async {
  return PickedAudioFile(
    name: file.name,
    size: await file.length(),
    relativeDir: relativeDir,
    openRead: file.openRead,
  );
}

class _WebFilePickerPort implements FilePickerPort {
  static final _audioGroup = XTypeGroup(
    label: 'Audio',
    extensions: kAcceptedAudioExtensions.toList(),
  );

  @override
  bool get canPickFolders => false;

  @override
  Future<List<PickedAudioFile>> pickAudioFiles() async {
    final files = await openFiles(acceptedTypeGroups: [_audioGroup]);
    return [for (final f in files) await pickedFromXFile(f)];
  }

  @override
  Future<List<PickedAudioFile>> pickAudioFolder() async => const [];

  @override
  Future<PickedAudioFile?> pickFile({
    required Set<String> extensions,
    required String label,
  }) async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: label, extensions: extensions.toList()),
      ],
    );
    if (file == null) return null;
    return pickedFromXFile(file);
  }
}
