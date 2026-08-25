import 'package:flutter/services.dart';

import 'file_picker_port.dart';

/// Android folder picking over the `waxdeck/saf` platform channel.
///
/// The channel stays a thin capability grant: the Kotlin side opens the
/// system tree picker, walks the tree, and reads byte windows on
/// demand. Everything with a policy in it - the extension filter, the
/// DRM accounting, ordering, the transfer - stays Dart-side behind
/// [FilePickerPort], like every other platform.
const _channel = MethodChannel('waxdeck/saf');

/// One `readChunk` round trip. Matches the transfer's own window
/// (UploadsController.chunkBytes), so an upload usually costs one
/// channel call per window it sends.
const _safReadChunk = 1024 * 1024;

/// Opens the tree picker and walks the chosen folder into lazy
/// [PickedAudioFile]s, filtered and counted like the desktop walk;
/// empty when the user cancels. Throws a [PlatformException] when the
/// pick itself failed (no picker on the ROM, a provider that errored
/// mid-walk) - the caller words that, because an empty pick here would
/// read as a folder of nothing.
Future<FolderPick> pickSafAudioFolder(UploadFormatSets formats) async {
  final entries = await _channel.invokeListMethod<Object?>('pickTree');
  if (entries == null) return const FolderPick();
  final builder = FolderPickBuilder(formats);
  for (final raw in entries) {
    final entry = (raw! as Map).cast<String, Object?>();
    final name = entry['name']! as String;
    if (!builder.keep(name)) continue;
    final size = (entry['size']! as num).toInt();
    if (size < 0) {
      // The provider reported no size, and a session must declare one
      // up front; counted rather than vanished, so a folder of these
      // still explains itself.
      builder.skipUnreadable();
      continue;
    }
    final uri = entry['uri']! as String;
    builder.files.add(
      PickedAudioFile(
        name: name,
        size: size,
        relativeDir: entry['relativeDir']! as String,
        openRead: ([int? start, int? end]) =>
            _readWindows(uri, start ?? 0, end ?? size),
      ),
    );
  }
  return builder.build();
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
