import 'package:flutter/services.dart';

import 'file_picker_port.dart';

/// Android folder picking over the `waxdeck/saf` platform channel.
///
/// The channel stays a thin capability grant: the Kotlin side opens the
/// system tree picker, walks the tree a page at a time, and reads byte
/// windows on demand. Everything with a policy in it - the extension
/// filter, the DRM accounting, ordering, the transfer - stays Dart-side
/// behind [FilePickerPort], like every other platform.
const _channel = MethodChannel('waxdeck/saf');

/// One `readChunk` round trip. Matches the transfer's own window
/// (UploadsController.chunkBytes), so an upload usually costs one
/// channel call per window it sends.
const _safReadChunk = 1024 * 1024;

/// How many entries one `nextTreeBatch` asks for. The walk is pulled
/// rather than pushed: picking "Internal storage" used to encode tens
/// of thousands of entries onto the main thread and hold three copies
/// of them at once, and a bounded page means the peak is a page
/// wherever the folder's size lands.
const kSafTreeBatch = 500;

/// Opens the tree picker and walks the chosen folder into lazy
/// [PickedAudioFile]s, filtered and counted like the desktop walk;
/// empty when the user cancels. Throws a [PlatformException] when the
/// pick itself failed (no picker on the ROM, a provider that errored
/// mid-walk, a walk that answered nothing) - the caller words that,
/// because a short pick here would read as a small folder.
///
/// [batch] is how many entries one page asks for, and exists as an
/// argument so the on-device suite can cross a page boundary against a
/// probe folder small enough to push onto an emulator. Production
/// leaves it at [kSafTreeBatch].
Future<FolderPick> pickSafAudioFolder(
  UploadFormatSets formats, {
  int batch = kSafTreeBatch,
}) async {
  final granted = await _channel.invokeMapMethod<String, Object?>('pickTree');
  if (granted == null) return const FolderPick();
  // The walk is open from the moment the grant answers, so everything
  // below runs under the finally that drops it - including reading the
  // rest of the grant. Its name comes out first and without a cast
  // that could throw, because it is what the finally needs to name the
  // walk it is dropping.
  final walk = granted['walk'];
  final builder = FolderPickBuilder(formats);
  var done = false;
  try {
    final root = granted['root']! as String;
    while (!done) {
      final page = await _channel.invokeMapMethod<String, Object?>(
        'nextTreeBatch',
        <String, Object?>{'walk': walk, 'max': batch},
      );
      // A page that is not a page is a protocol failure, not the end:
      // stopping here would hand back a truncated pick as a complete
      // one, which is the one answer this walk must never give.
      // No message: the code is the whole contract here, the caller
      // words every pick failure the same way, and a sentence sitting
      // in lib that nothing ever shows is copy by the ratchet's
      // reckoning and dead weight by anyone else's.
      if (page == null) throw PlatformException(code: 'enumerate-failed');
      done = page['done'] == true;
      for (final raw in page['entries']! as List<Object?>) {
        _take(builder, root, (raw! as Map).cast<String, Object?>());
      }
    }
  } finally {
    // A walk nobody finished holds its place in the tree; one that ran
    // to `done` has already dropped itself.
    if (!done && walk != null) {
      try {
        await _channel.invokeMethod<void>('disposeTreeWalk', <String, Object?>{
          'walk': walk,
        });
      } on Object {
        // Best effort, and deliberately every throwable: this runs on
        // the failure path too, and anything raised here would replace
        // the reason the pick failed with itself.
      }
    }
  }
  return builder.build();
}

/// Folds one walked entry into the pick.
///
/// [root] is the granted tree's own display name. Kotlin reports each
/// directory relative to it, so the root is sent once instead of on
/// every entry, and the `(relativeDir, name)` shape the desktop and web
/// walks build is composed here.
void _take(FolderPickBuilder builder, String root, Map<String, Object?> entry) {
  final name = entry['name']! as String;
  if (!builder.keep(name)) return;
  final size = (entry['size']! as num).toInt();
  if (size < 0) {
    // The provider reported no size, and a session must declare one
    // up front; counted rather than vanished, so a folder of these
    // still explains itself.
    builder.skipUnreadable();
    return;
  }
  final dir = entry['relativeDir']! as String;
  final uri = entry['uri']! as String;
  builder.files.add(
    PickedAudioFile(
      name: name,
      size: size,
      relativeDir: joinRelativeDir(root, dir),
      openRead: ([int? start, int? end]) =>
          _readWindows(uri, start ?? 0, end ?? size),
    ),
  );
}

/// One `[start, end)` window as channel-sized reads. The Kotlin side
/// keeps one stream open per document and hands out sequential chunks,
/// so a transfer reads each byte once; only the chunk in flight ever
/// crosses the channel. A short or empty answer means the document
/// ended early (shrunk since the pick); the stream ends and the
/// transfer's own size accounting reports it.
Stream<List<int>> _readWindows(String uri, int start, int end) async* {
  var offset = start;
  while (offset < end) {
    final want = end - offset > _safReadChunk ? _safReadChunk : end - offset;
    final bytes = await _channel.invokeMethod<Uint8List>('readChunk', {
      'uri': uri,
      'start': offset,
      'length': want,
    });
    if (bytes == null || bytes.isEmpty) return;
    yield bytes;
    offset += bytes.length;
    if (bytes.length < want) return;
  }
}
