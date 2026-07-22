import 'dart:typed_data';

Future<int> localFileLength(String path) async {
  throw UnsupportedError('no local file access on this platform');
}

Future<Uint8List> readLocalFileRange(
  String path,
  int offset,
  int length,
) async {
  throw UnsupportedError('no local file access on this platform');
}
