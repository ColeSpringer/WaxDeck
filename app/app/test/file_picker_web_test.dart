@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck/src/uploads/file_picker_web.dart';
import 'package:web/web.dart' as web;

/// The folder pick's conversion, which only a browser can run: it turns
/// `web.File` handles into the lazy references the transfer windows
/// through.
///
/// The dialog above it is not testable anywhere - opening a folder
/// chooser needs a user gesture and a human to answer it - so the seam
/// is [pickedFromDirectory], which takes the handles and the paths the
/// browser would have filled in. `@TestOn('browser')` keeps it out of
/// the VM sweep; `make test-app-chrome` selects it by its suffix.
void main() {
  web.File file(String name, List<int> bytes) =>
      web.File(<JSUint8Array>[Uint8List.fromList(bytes).toJS].toJS, name);

  DirectoryEntry entry(String path, [List<int> bytes = const <int>[0]]) {
    final name = path.substring(path.lastIndexOf('/') + 1);
    return (file: file(name, bytes), relativePath: path);
  }

  test('a picked folder keeps its audio, in tree order', () {
    final pick = pickedFromDirectory(<DirectoryEntry>[
      entry('The Wall/CD2/b.flac'),
      entry('The Wall/cover.jpg'),
      entry('The Wall/top.mp3'),
      entry('The Wall/CD1/a.mp3'),
      entry('The Wall/notes.txt'),
    ], kAcceptedAudioExtensions);

    expect(pick.files.map((f) => f.name).toList(), <String>[
      'top.mp3',
      'a.mp3',
      'b.flac',
    ]);
    expect(pick.files.map((f) => f.relativeDir).toList(), <String>[
      'The Wall',
      'The Wall/CD1',
      'The Wall/CD2',
    ]);
    // What the filter dropped is counted, not silent: the cover and the
    // notes here, and never as DRM.
    expect(pick.skippedUnsupported, 2);
    expect(pick.skippedDrm, 0);
  });

  test('audible files count apart from the rest of the filtered', () {
    final pick = pickedFromDirectory(<DirectoryEntry>[
      entry('Book/part1.aax'),
      entry('Book/part2.AAXC'),
      entry('Book/cover.jpg'),
    ], kAcceptedAudioExtensions);
    expect(pick.files, isEmpty);
    expect(pick.skippedDrm, 2);
    expect(pick.skippedUnsupported, 1);
  });

  test('a browser that fills no relative path lands the file at the top', () {
    final pick = pickedFromDirectory(<DirectoryEntry>[
      entry('lonely.mp3'),
    ], kAcceptedAudioExtensions);
    expect(pick.files.single.relativeDir, isEmpty);
  });

  test('a picked file is a window over its handle, not its bytes', () async {
    final picked = pickedFromDirectory(<DirectoryEntry>[
      entry('Album/a.mp3', <int>[0, 1, 2, 3, 4, 5, 6, 7]),
    ], kAcceptedAudioExtensions).files.single;

    expect(picked.size, 8);
    // Web picks carry no filesystem path; the transfer dispatches on
    // that, so a path here would send it down the dart:io arm.
    expect(picked.path, isNull);

    final window = await picked.openRead!(2, 5).expand((c) => c).toList();
    expect(window, <int>[2, 3, 4]);
    final whole = await picked.openRead!().expand((c) => c).toList();
    expect(whole, <int>[0, 1, 2, 3, 4, 5, 6, 7]);
  });
}
