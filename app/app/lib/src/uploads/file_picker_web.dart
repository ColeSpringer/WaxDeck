import 'dart:async';
import 'dart:js_interop';

import 'package:file_selector/file_selector.dart';
import 'package:web/web.dart' as web;

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
  static XTypeGroup _audioGroup(String label) =>
      XTypeGroup(label: label, extensions: kAcceptedAudioExtensions.toList());

  @override
  bool get canPickFolders => true;

  // The browser's own picker draws no group names and offers its own
  // "all files" row, so [anyLabel] has nowhere to go here and no group
  // is added for it.
  @override
  Future<List<PickedAudioFile>> pickAudioFiles({
    required String audioLabel,
    required String anyLabel,
  }) async {
    final files = await openFiles(
      acceptedTypeGroups: [_audioGroup(audioLabel)],
    );
    return [for (final f in files) await pickedFromXFile(f)];
  }

  @override
  Future<List<PickedAudioFile>> pickAudioFolder() async =>
      pickedFromDirectory(await _pickDirectory(), kAcceptedAudioExtensions);

  @override
  Future<PickedAudioFile?> pickFile({
    required Set<String> extensions,
    required String label,
    required String anyLabel,
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

/// The folder pick's conversion step: files whose extension is in
/// [extensions], each a lazy window over its browser file, ordered the
/// way the desktop walk orders what it lists.
///
/// Split out from the dialog because only the browser can mint a real
/// `webkitRelativePath`, so this is the seam a test drives.
List<PickedAudioFile> pickedFromDirectory(
  List<DirectoryEntry> entries,
  Set<String> extensions,
) {
  final out = <PickedAudioFile>[];
  for (final entry in entries) {
    final file = entry.file;
    // A directory pick cannot be filtered by the dialog - `accept` is
    // ignored once `webkitdirectory` is set - so the tree is filtered
    // here, the way the desktop walk filters what it lists.
    if (!hasAcceptedExtension(file.name, extensions)) continue;
    out.add(
      PickedAudioFile(
        name: file.name,
        size: file.size,
        relativeDir: _relativeDirOf(entry.relativePath),
        openRead: ([int? start, int? end]) => _readBlob(file, start, end),
      ),
    );
  }
  // The browser's own order is unspecified; a stable one keeps
  // transfers and tests deterministic, as on desktop.
  out.sort((a, b) {
    final byDir = a.relativeDir.compareTo(b.relativeDir);
    return byDir != 0 ? byDir : a.name.compareTo(b.name);
  });
  return out;
}

/// One file of a folder pick: the browser's handle and the path it was
/// found at, rooted at the chosen folder's own name.
typedef DirectoryEntry = ({web.File file, String relativePath});

/// Opens the browser's folder chooser and answers every file under the
/// chosen directory; empty when the user cancels.
///
/// Hand-rolled rather than taken from file_selector, whose web
/// implementation exposes `accept` and `multiple` and nothing else:
/// a folder pick is an `<input type="file">` carrying `webkitdirectory`,
/// which every engine WaxDeck's web build targets supports.
Future<List<DirectoryEntry>> _pickDirectory() {
  final completer = Completer<List<DirectoryEntry>>();
  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..multiple = true
    ..webkitdirectory = true
    ..style.display = 'none';
  web.EventListener? onFocus;
  void finish(List<DirectoryEntry> entries) {
    if (completer.isCompleted) return;
    if (onFocus != null) web.window.removeEventListener('focus', onFocus);
    // The File handles outlive the element they came from, so the input
    // goes back out of the document however the pick ended - including
    // the dismissals that used to leave one behind per attempt.
    input.remove();
    completer.complete(entries);
  }

  input.onChange.first.then((_) {
    final list = input.files;
    finish(<DirectoryEntry>[
      if (list != null)
        for (var i = 0; i < list.length; i++)
          if (list.item(i) case final file?)
            (file: file, relativePath: file.webkitRelativePath),
    ]);
  });
  // Dismissing the dialog, which the port answers as an empty pick the
  // way the desktop one does. `cancel` is the direct signal and not
  // every engine fires it, so the page regaining focus is the fallback:
  // a chooser is modal, so focus coming back means the dialog is gone,
  // and a moment later either the change event has landed or nothing
  // was picked. Without one of the two an await here never returns and
  // the affordance is dead for the rest of the session.
  input.addEventListener('cancel', ((web.Event _) => finish(const [])).toJS);
  onFocus = ((web.Event _) {
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      finish(const []);
    });
  }).toJS;
  web.window.addEventListener('focus', onFocus);
  web.document.body!.appendChild(input);
  input.click();
  return completer.future;
}

/// The directory part of a `webkitRelativePath`, which is the file's
/// path rooted at the chosen folder's own name - the same shape the
/// desktop walk builds, so `batchPath` reads alike on both.
String _relativeDirOf(String relativePath) {
  final cut = relativePath.lastIndexOf('/');
  return cut < 0 ? '' : relativePath.substring(0, cut);
}

/// One `[start, end)` window of a browser file. Slicing first is what
/// keeps the transfer's memory to the window in flight rather than the
/// whole file.
Stream<List<int>> _readBlob(web.Blob blob, int? start, int? end) async* {
  final slice = blob.slice(start ?? 0, end ?? blob.size);
  final buffer = await slice.arrayBuffer().toDart;
  yield buffer.toDart.asUint8List();
}
