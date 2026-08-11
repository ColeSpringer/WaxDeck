import 'dart:io';

import 'package:file_selector/file_selector.dart';

import 'file_picker_port.dart';

FilePickerPort? createFilePickerPort() => _IoFilePickerPort();

/// Whether a dropped path is a directory on disk (Linux and Windows
/// deliver folder drops as plain path items).
Future<bool> droppedPathIsDirectory(String path) =>
    FileSystemEntity.isDirectory(path);

/// Recursively lists a dropped or picked directory's files matching
/// [extensions] as path-backed references, relativeDir rooted at the
/// directory's own name. A path that vanished between drop and
/// expansion reads as empty rather than blowing up the drop handler.
Future<List<PickedAudioFile>> expandDroppedDirectory(
  String path,
  Set<String> extensions,
) async {
  final dir = Directory(path);
  if (!await dir.exists()) return const [];
  return _filesUnder(dir, extensions);
}

/// Converts one picker or drop XFile: path-backed, streaming from
/// disk at transfer time.
Future<PickedAudioFile> pickedFromXFile(
  XFile file, {
  String relativeDir = '',
}) async {
  return PickedAudioFile(
    name: _baseName(file.path),
    size: await file.length(),
    relativeDir: relativeDir,
    path: file.path,
    openRead: file.openRead,
  );
}

class _IoFilePickerPort implements FilePickerPort {
  static final _audioGroup = XTypeGroup(
    label: 'Audio',
    extensions: kAcceptedAudioExtensions.toList(),
  );

  // The unfiltered group keeps files in a custom
  // WAXDECK_UPLOAD_FORMATS set reachable; the server checks the real
  // accepted list at session create.
  static const _anyGroup = XTypeGroup(label: 'All files');

  @override
  bool get canPickFolders => Platform.isLinux || Platform.isWindows;

  @override
  Future<List<PickedAudioFile>> pickAudioFiles() async {
    final files = await openFiles(acceptedTypeGroups: [_audioGroup, _anyGroup]);
    return [for (final f in files) await pickedFromXFile(f)];
  }

  @override
  Future<List<PickedAudioFile>> pickAudioFolder() async {
    if (!canPickFolders) return const [];
    final dir = await getDirectoryPath();
    if (dir == null) return const [];
    return expandDroppedDirectory(dir, kAcceptedAudioExtensions);
  }

  @override
  Future<PickedAudioFile?> pickFile({
    required Set<String> extensions,
    required String label,
  }) async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: label, extensions: extensions.toList()),
        _anyGroup,
      ],
    );
    if (file == null) return null;
    return pickedFromXFile(file);
  }
}

Future<List<PickedAudioFile>> _filesUnder(
  Directory root,
  Set<String> extensions,
) async {
  final rootPath = root.path;
  final rootName = _baseName(rootPath);
  final out = <PickedAudioFile>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final name = _baseName(entity.path);
    if (!hasAcceptedExtension(name, extensions)) continue;
    out.add(
      PickedAudioFile(
        name: name,
        size: await entity.length(),
        relativeDir: _joinDir(rootName, _relativeDirOf(entity.path, rootPath)),
        path: entity.path,
        openRead: ([int? start, int? end]) => entity.openRead(start, end),
      ),
    );
  }
  // Directory.list order is platform-dependent; a stable order keeps
  // transfers and tests deterministic.
  out.sort((a, b) {
    final byDir = a.relativeDir.compareTo(b.relativeDir);
    return byDir != 0 ? byDir : a.name.compareTo(b.name);
  });
  return out;
}

/// The last separator position. On Windows both `\` and `/` count -
/// neither is legal inside a Windows file name, and pickers and drops
/// there hand back either or mixed forms. On POSIX only `/` counts: a
/// backslash is a legal file-name character and must never split.
int _lastSeparator(String path) {
  final slash = path.lastIndexOf('/');
  if (!Platform.isWindows) return slash;
  final back = path.lastIndexOf(r'\');
  return slash > back ? slash : back;
}

/// Forward-slash form for comparisons and the relativeDir contract;
/// the identity everywhere but Windows.
String _slashed(String path) =>
    Platform.isWindows ? path.replaceAll(r'\', '/') : path;

String _baseName(String path) {
  final cut = _lastSeparator(path);
  return cut < 0 ? path : path.substring(cut + 1);
}

/// The entity's directory relative to root, forward-slash separated;
/// empty at the top.
String _relativeDirOf(String path, String rootPath) {
  final cut = _lastSeparator(path);
  if (cut < 0) return '';
  final dir = _slashed(path.substring(0, cut));
  var root = _slashed(rootPath);
  while (root.endsWith('/')) {
    root = root.substring(0, root.length - 1);
  }
  if (dir == root) return '';
  if (!dir.startsWith('$root/')) return '';
  return dir.substring(root.length + 1);
}

String _joinDir(String a, String b) {
  if (a.isEmpty) return b;
  if (b.isEmpty) return a;
  return '$a/$b';
}
