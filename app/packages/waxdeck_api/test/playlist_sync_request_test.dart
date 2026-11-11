import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'support/recording_adapter.dart';

void main() {
  // mirror-trash is the spelling no Dart identifier carries.
  test('mode and source are sent as the wire strings', () async {
    final adapter = RecordingAdapter.refusing();
    final client = clientOn(adapter);
    await expectLater(
      client.previewPlaylistSync('pl-1', mode: 'mirror-trash', source: 'csv'),
      throwsA(isA<WaxDeckApiException>()),
    );
    await expectLater(
      client.setPlaylistSource('pl-1', mode: 'mirror-trash', source: 'csv'),
      throwsA(isA<WaxDeckApiException>()),
    );
    expect(
      [
        for (final r in adapter.requests)
          ((r.data as Map)['mode'], (r.data as Map)['source']),
      ],
      [('mirror-trash', 'csv'), ('mirror-trash', 'csv')],
    );
  });
}
