import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/uploads/audio_drop_area.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';

void main() {
  test(
    'flattens web-style directory items, rebuilding relative dirs',
    () async {
      // The shape desktop_drop delivers for a web folder drop. On the
      // test VM the io XFile ignores the name it is handed and splits
      // one off the path, so the fakes join the host's way.
      final sep = Platform.pathSeparator;
      String fake(String name) => '${sep}drop-fake$sep$name';
      DropItemFile file(String name) => DropItemFile.fromData(
        Uint8List(4),
        name: name,
        length: 4,
        path: fake(name),
      );
      final items = <DropItem>[
        DropItemDirectory(fake('Boxset'), [
          DropItemDirectory(fake('CD1'), [file('one.flac')], name: 'CD1'),
          DropItemDirectory(fake('CD2'), [file('two.flac')], name: 'CD2'),
          file('cover.jpg'),
        ], name: 'Boxset'),
        file('loose.mp3'),
      ];

      final picked = await normalizeDrop(items, kAcceptedAudioExtensions);
      expect(picked, hasLength(3));
      final byName = {for (final p in picked) p.name: p};
      expect(byName['one.flac']!.relativeDir, 'Boxset/CD1');
      expect(byName['two.flac']!.relativeDir, 'Boxset/CD2');
      expect(byName['loose.mp3']!.relativeDir, '');
      // The jpg fell to the extension filter.
      expect(byName.containsKey('cover.jpg'), isFalse);
    },
  );

  test('expands an on-disk directory item recursively', () async {
    final root = await Directory.systemTemp.createTemp('waxdeck-drop-test');
    addTearDown(() => root.delete(recursive: true));
    final disc = Directory('${root.path}/CD1');
    await disc.create();
    await File('${root.path}/top.mp3').writeAsBytes(List.filled(8, 1));
    await File('${disc.path}/deep.flac').writeAsBytes(List.filled(8, 2));
    await File('${disc.path}/notes.txt').writeAsString('skip me');

    // Linux and Windows deliver a dropped folder as a plain path item.
    final picked = await normalizeDrop([
      DropItemFile(root.path),
    ], kAcceptedAudioExtensions);
    expect(picked, hasLength(2));
    final byName = {for (final p in picked) p.name: p};
    final rootName = root.path.split(Platform.pathSeparator).last;
    expect(byName['top.mp3']!.relativeDir, rootName);
    expect(byName['deep.flac']!.relativeDir, '$rootName/CD1');
    expect(byName['deep.flac']!.path, isNotNull);
    expect(byName['deep.flac']!.size, 8);
  });

  test('filters loose files to the accepted extension set', () async {
    DropItemFile data(String name) => DropItemFile.fromData(
      Uint8List(2),
      name: name,
      length: 2,
      path: '/drop-fake/$name',
    );
    final picked = await normalizeDrop([
      data('keep.OPUS'),
      data('drop.pdf'),
      data('extensionless'),
    ], kAcceptedAudioExtensions);
    expect(picked.map((p) => p.name), ['keep.OPUS']);
  });

  test('the zip set admits archives only', () async {
    DropItemFile data(String name) => DropItemFile.fromData(
      Uint8List(2),
      name: name,
      length: 2,
      path: '/drop-fake/$name',
    );
    final picked = await normalizeDrop(
      [data('backup.zip'), data('song.mp3')],
      {'zip'},
    );
    expect(picked.map((p) => p.name), ['backup.zip']);
  });
}
