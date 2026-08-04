/// The native build's cover for the OS media surfaces.
///
/// Every one of them - the Android notification, MPRIS, the Windows
/// transport controls, macOS's now-playing panel - fetches the artwork
/// out of process, and none of them can be handed this app's bearer
/// token. So the bytes are fetched here, through the store that already
/// authenticates and already caches them, and written to a file the OS
/// can read on its own.
///
/// One file per cover rather than one file reused, because every one of
/// those surfaces caches by URI: a path that never changes is a lock
/// screen still showing the last album three tracks later.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../artwork/artwork_store.dart';
import '../sync/test_env/test_env.dart';
import 'session_artwork.dart';

/// How many covers stay on disk.
///
/// A handful, because a surface may still be reading the file for the
/// track before this one while the next is written, and because a head
/// unit draws the published queue's rows from their own files. Small
/// enough that the directory is never worth a sweep of its own.
const int _keep = 8;

/// The cover for [artUrl] as a file the OS may read, or null when the
/// item has no artwork or the bytes could not be had.
///
/// Best effort throughout: a lock screen with no cover is a cosmetic
/// loss, and nothing about it is worth failing a track change over.
Future<Uri?> mediaSessionArtUri(ArtworkStore store, String? artUrl) async {
  if (artUrl == null || artUrl.isEmpty) return null;
  try {
    final directory = await _artDirectory();
    if (directory == null) return null;
    final file = File(p.join(directory.path, _nameFor(artUrl)));
    // Already fetched for this cover: hand back the same path rather
    // than re-fetching and rewriting it, which is what a queue whose
    // rows share an album cover would otherwise do per row.
    if (await file.exists()) {
      // The prune is by modification time, and this one is in use now.
      try {
        await file.setLastModified(DateTime.now());
      } on FileSystemException {
        // A read-only or unhappy filesystem: the cover still resolves,
        // and the worst case is the one this guard was avoiding.
      }
      return file.uri;
    }
    final bytes = await store.bytesFor(artUrl, kMediaSessionArtRung);
    if (bytes == null || bytes.isEmpty) return null;
    await _writeAtomically(file, bytes);
    await _prune(directory);
    return file.uri;
  } on Object catch (failure) {
    debugPrint('media session artwork skipped: $failure');
    return null;
  }
}

/// Drops every cover written for the OS surfaces.
///
/// Called when this device stops being what is playing: a signed-out
/// account's covers are not a cache to keep warm.
Future<void> forgetMediaSessionArt() async {
  try {
    final directory = await _artDirectory();
    if (directory == null) return;
    await directory.delete(recursive: true);
  } on Object catch (failure) {
    debugPrint('media session artwork not cleared: $failure');
  } finally {
    // Forgotten as well as deleted: a held path that no longer exists
    // fails every later write, silently, for the rest of the process.
    _cached = null;
  }
}

Directory? _cached;

/// Names temp files apart. Two writes of one cover overlap routinely -
/// the feed republishes an item as its duration settles - and a shared
/// temp path interleaves them into a half-written JPEG.
int _writes = 0;

Future<Directory?> _artDirectory() async {
  // A widget test has no application-support directory and no OS surface
  // to hand a file to, the same reason the artwork store draws monograms
  // there. Without this every test that mounts the app ends by failing a
  // platform channel on its way out.
  if (inFlutterTest) return null;
  final cached = _cached;
  if (cached != null) return cached;
  final support = await getApplicationSupportDirectory();
  final directory = Directory(p.join(support.path, 'media-session-art'));
  await directory.create(recursive: true);
  return _cached = directory;
}

/// The file name for a cover: a digest of the URL it came from, so the
/// same cover is written once and a different one is a different path.
/// The extension is left off - the surfaces sniff the bytes, and the art
/// endpoint answers whatever format it stored.
String _nameFor(String artUrl) =>
    '${sha256.convert(utf8.encode(artUrl)).toString().substring(0, 32)}'
    '-$kMediaSessionArtRung';

/// Temp in the target directory, fsync, verify, atomic rename (the
/// file-write durability rule). Not ceremony for a cover: the reader is
/// another process that may open the path at any moment, and a
/// half-written JPEG is exactly what it would find without this.
Future<void> _writeAtomically(File file, Uint8List bytes) async {
  final temp = File('${file.path}.${_writes++}$_tempSuffix');
  try {
    final handle = await temp.open(mode: FileMode.writeOnly);
    try {
      await handle.writeFrom(bytes);
      await handle.flush();
    } finally {
      await handle.close();
    }
    // The rule's verify step: a short write is a full disk, and
    // renaming one publishes a truncated cover as a whole one.
    if (await temp.length() != bytes.length) {
      throw FileSystemException('short write', temp.path);
    }
    await temp.rename(file.path);
  } on Object {
    // Never renamed, and the prune skips temps, so it has to go now.
    try {
      await temp.delete();
    } on FileSystemException {
      // Already gone, or a filesystem that will not say.
    }
    rethrow;
  }
}

/// What an unfinished write is called while it is unfinished.
const String _tempSuffix = '.tmp';

/// Keeps the newest [_keep] covers and deletes the rest.
Future<void> _prune(Directory directory) async {
  final files = <File>[
    await for (final entity in directory.list())
      // A write in flight is not a cover, and counting it would evict
      // a real one.
      if (entity is File && !entity.path.endsWith(_tempSuffix)) entity,
  ];
  if (files.length <= _keep) return;
  final stamped = <(DateTime, File)>[];
  for (final file in files) {
    stamped.add((await file.lastModified(), file));
  }
  stamped.sort((a, b) => b.$1.compareTo(a.$1));
  for (final (_, file) in stamped.skip(_keep)) {
    // A file another process has open is a delete the platform may
    // refuse; it comes round again on the next prune.
    try {
      await file.delete();
    } on FileSystemException {
      continue;
    }
  }
}
