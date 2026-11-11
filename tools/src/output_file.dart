// The write the generators under tools/ share: temp file in the target
// directory, flushed and read back, then renamed over the target, and
// nothing at all when the target holds the content already, so its mtime
// stays - make decides what to rebuild by it.
import 'dart:convert';
import 'dart:io';

/// Replaces [path] with [content] unless it holds it already.
void writeIfChanged(String path, String content) {
  final bytes = utf8.encode(content);
  final file = File(path);
  if (file.existsSync() && _same(file.readAsBytesSync(), bytes)) return;
  final tmp = File(
    '${file.parent.path}/.${file.uri.pathSegments.last}.$pid.tmp',
  );
  try {
    final raf = tmp.openSync(mode: FileMode.write);
    try {
      raf.writeFromSync(bytes);
      raf.flushSync();
    } finally {
      raf.closeSync();
    }
    if (!_same(tmp.readAsBytesSync(), bytes)) {
      throw FileSystemException(
        'the temp file reads back other than what was written',
        path,
      );
    }
    tmp.renameSync(path);
  } finally {
    if (tmp.existsSync()) tmp.deleteSync();
  }
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
