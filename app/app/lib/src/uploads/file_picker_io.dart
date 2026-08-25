import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import 'file_picker_port.dart';
import 'saf_folder_picker.dart';

/// Android resolves at the factory, like the share-intake port: no
/// port method carries an OS branch, and the platform read is the
/// overridable [defaultTargetPlatform] so a host test can exercise the
/// dispatch.
FilePickerPort? createFilePickerPort() =>
    defaultTargetPlatform == TargetPlatform.android
    ? _AndroidFilePickerPort()
    : _IoFilePickerPort();

/// Whether a dropped path is a directory on disk (Linux and Windows
/// deliver folder drops as plain path items).
Future<bool> droppedPathIsDirectory(String path) =>
    FileSystemEntity.isDirectory(path);

/// Recursively lists a dropped or picked directory's files matching
/// [formats] as path-backed references, relativeDir rooted at the
/// directory's own name, with what the filter dropped counted. A path
/// that vanished between drop and expansion reads as empty rather than
/// blowing up the drop handler.
Future<FolderPick> expandDroppedDirectory(
  String path,
  UploadFormatSets formats,
) async {
  final dir = Directory(path);
  if (!await dir.exists()) return const FolderPick();
  return _filesUnder(dir, formats);
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
  static XTypeGroup _audioGroup(String label, Set<String> accepted) =>
      XTypeGroup(label: label, extensions: accepted.toList());

  // Keeps files outside the accepted set reachable (a set the health
  // read has not landed yet, or a server older than the field). Named,
  // because the Linux and Windows plugins hand a missing label to the
  // toolkit as an empty string rather than substituting one.
  static XTypeGroup _anyGroup(String label) => XTypeGroup(label: label);

  @override
  bool get canPickFolders => Platform.isLinux || Platform.isWindows;

  @override
  Future<List<PickedAudioFile>> pickAudioFiles({
    required String audioLabel,
    required String anyLabel,
    required UploadFormatSets formats,
  }) async {
    final files = await openFiles(
      acceptedTypeGroups: [
        _audioGroup(audioLabel, formats.accepted),
        _anyGroup(anyLabel),
      ],
    );
    return [for (final f in files) await pickedFromXFile(f)];
  }

  @override
  Future<FolderPick> pickAudioFolder({
    required UploadFormatSets formats,
  }) async {
    if (!canPickFolders) return const FolderPick();
    final dir = await getDirectoryPath();
    if (dir == null) return const FolderPick();
    return expandDroppedDirectory(dir, formats);
  }

  @override
  Future<PickedAudioFile?> pickFile({
    required Set<String> extensions,
    required String label,
    required String anyLabel,
  }) async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: label, extensions: extensions.toList()),
        _anyGroup(anyLabel),
      ],
    );
    if (file == null) return null;
    return pickedFromXFile(file);
  }
}

// The Android arm: file picks stay with the shared dialogs, folder
// access means SAF tree URIs and goes over the platform channel.
class _AndroidFilePickerPort extends _IoFilePickerPort {
  @override
  bool get canPickFolders => true;

  @override
  Future<FolderPick> pickAudioFolder({required UploadFormatSets formats}) =>
      pickSafAudioFolder(formats);
}

Future<FolderPick> _filesUnder(Directory root, UploadFormatSets formats) async {
  final rootPath = root.path;
  final rootName = _baseName(rootPath);
  final builder = FolderPickBuilder(formats);
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final name = _baseName(entity.path);
    if (!builder.keep(name)) continue;
    builder.files.add(
      PickedAudioFile(
        name: name,
        size: await entity.length(),
        relativeDir: _joinDir(rootName, _relativeDirOf(entity.path, rootPath)),
        path: entity.path,
        openRead: ([int? start, int? end]) => entity.openRead(start, end),
      ),
    );
  }
  return builder.build();
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
