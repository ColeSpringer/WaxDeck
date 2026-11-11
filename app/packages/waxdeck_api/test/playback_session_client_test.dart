import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'support/recording_adapter.dart';

WaxDeckClient _client(Object? body) => clientOn(RecordingAdapter(body: body));

// An answer was had, so this is no outage, and the reason names the field.
Matcher _malformed(String reason) => throwsA(
  isA<WaxDeckApiException>()
      .having((e) => e.code, 'code', 'transport-decode')
      .having((e) => e.message, 'message', reason)
      .having((e) => e.statusCode, 'statusCode', 200)
      .having((e) => e.unreachable, 'unreachable', isFalse),
);

void main() {
  test('an answer that does not decode fails with its status', () async {
    await expectLater(
      _client({'id': 7}).getPlaybackSession('ps-1'),
      _malformed('PlaybackSessionInfo.id: expected a string, got int'),
    );
  });

  test('an entry that does not decode fails its answer the same way', () async {
    await expectLater(
      _client({
        'sessions': [
          {
            'id': 'ps-1',
            'endpointId': 'pe-1',
            'authority': 'remote',
            'index': 0,
            'positionMs': 0,
            'positionAt': '2026-07-01T00:00:00Z',
            'rate': 1,
            'entries': [
              {'pid': 'tr-1', 'title': 7},
            ],
          },
        ],
      }).listPlaybackSessionHistory(),
      _malformed('PlaybackSessionEntry.title: expected a string, got int'),
    );
  });

  test('an answer missing a required field fails with its status', () async {
    await expectLater(
      _client(<String, Object?>{}).getPlaybackSession('ps-1'),
      _malformed('PlaybackSessionInfo.id: missing'),
    );
  });
}
