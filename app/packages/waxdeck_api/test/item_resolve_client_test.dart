import 'dart:convert';

import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'support/recording_adapter.dart';

const _track = 'tr-01JZX5N8QW3F4V9T2B7KD3M9R6';
const _book = 'bk-01JZX5N8QW3F4V9T2B7KD3M9R7';
const _gone = 'tr-01JZX5N8QW3F4V9T2B7KD3M9R8';

void main() {
  test('a lookup sends the pids and reads the summaries and the '
      'departed', () async {
    final adapter = RecordingAdapter()
      ..body = <String, Object?>{
        'items': <Object?>[
          <String, Object?>{
            'pid': _book,
            'mediaType': 'audiobook',
            'title': 'The Fixture Book',
            'durationMs': 15000,
          },
        ],
        'departed': <Object?>[_gone],
      };
    final client = clientOn(adapter);

    final resolved = await client.resolveItems([_track, _gone]);

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, endsWith('/library/items/resolve'));
    expect(jsonDecode(jsonEncode(request.data)), <String, Object?>{
      'pids': <Object?>[_track, _gone],
    });
    expect(resolved.items.single.pid, _book);
    expect(resolved.items.single.mediaType, MediaType.audiobook);
    expect(resolved.items.single.title, 'The Fixture Book');
    expect(resolved.departed, [_gone]);
  });

  test('every miss out of sight reads as nothing departed', () async {
    final adapter = RecordingAdapter()
      ..body = const <String, Object?>{'items': <Object?>[]};
    final client = clientOn(adapter);

    final resolved = await client.resolveItems([_track]);

    expect(resolved.items, isEmpty);
    expect(resolved.departed, isEmpty);
  });

  test('nothing to look up asks nothing', () async {
    final adapter = RecordingAdapter();
    final client = clientOn(adapter);

    final resolved = await client.resolveItems(const []);

    expect(adapter.requests, isEmpty);
    expect(resolved.items, isEmpty);
    expect(resolved.departed, isEmpty);
  });
}
