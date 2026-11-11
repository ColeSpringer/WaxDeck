import 'dart:convert';

import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'support/recording_adapter.dart';

const _item = <String, Object?>{
  'pid': 'bk-01JZX5N8QW3F4V9T2B7KD3M9R7',
  'mediaType': 'audiobook',
  'title': 'The Fixture Book',
  'artist': 'Ada Author',
  'durationMs': 15000,
  'artUrl': '/api/v1/items/bk-01JZX5N8QW3F4V9T2B7KD3M9R7/art',
};

void main() {
  test('a preview sends the document and reads every line', () async {
    final adapter = RecordingAdapter()
      ..body = <String, Object?>{
        'matched': 1,
        'merged': 1,
        'unmatched': 2,
        'entries': <Object?>[
          <String, Object?>{
            'path': '/books/part1.m4b',
            'outcome': 'matched',
            'item': _item,
          },
          <String, Object?>{
            'path': '/books/part2.m4b',
            'outcome': 'merged',
            'item': _item,
          },
          <String, Object?>{
            'path': '/music/missing.flac',
            'outcome': 'unmatched',
          },
          // An outcome this build has never heard of reads as unmatched,
          // without the item it may carry.
          <String, Object?>{
            'path': '/music/later.flac',
            'outcome': 'something-newer',
            'item': _item,
          },
        ],
      };
    final client = clientOn(adapter);

    final preview = await client.previewPlaylistM3u('#EXTM3U\n/a.flac\n');

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, endsWith('/playlists/m3u/preview'));
    // Every line is resolved before the answer: the long budget, not the
    // ordinary thirty seconds.
    expect(request.receiveTimeout, const Duration(minutes: 30));
    expect(jsonDecode(jsonEncode(request.data)), {
      'content': '#EXTM3U\n/a.flac\n',
    });
    expect((preview.matched, preview.merged, preview.unmatched), (1, 1, 2));
    expect(
      [for (final line in preview.lines) (line.path, line.outcome)],
      [
        ('/books/part1.m4b', M3uLineOutcome.matched),
        ('/books/part2.m4b', M3uLineOutcome.merged),
        ('/music/missing.flac', M3uLineOutcome.unmatched),
        ('/music/later.flac', M3uLineOutcome.unmatched),
      ],
    );
    final book = preview.lines.first.item!;
    expect(book.pid, 'bk-01JZX5N8QW3F4V9T2B7KD3M9R7');
    expect(book.mediaType, MediaType.audiobook);
    expect(book.artist, 'Ada Author');
    expect(
      book.artUrl,
      'http://host:4420/api/v1/items/bk-01JZX5N8QW3F4V9T2B7KD3M9R7/art',
    );
    expect(preview.lines[1].item?.pid, book.pid);
    expect(preview.lines[2].item, isNull);
    expect(preview.lines[3].item, isNull);
  });
}
