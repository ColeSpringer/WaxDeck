import 'dart:io';
import 'dart:typed_data';

/// The file's size in bytes.
Future<int> localFileLength(String path) => File(path).length();

/// Reads up to [length] bytes at [offset]; short only at end of file.
Future<Uint8List> readLocalFileRange(
  String path,
  int offset,
  int length,
) async {
  final raf = await File(path).open();
  try {
    await raf.setPosition(offset);
    return Uint8List.fromList(await raf.read(length));
  } finally {
    await raf.close();
  }
}
