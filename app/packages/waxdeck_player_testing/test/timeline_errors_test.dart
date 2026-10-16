import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

/// Where the timeline's reading of a server answer and the stream probe's
/// meet: the same answer means the same thing to both.
void main() {
  test('the server refusing the file itself is unplayable on both', () {
    // A fragment the engine would not make audio of: no re-mint or retry
    // plays it, which is what the probe reads a 415 or 422 as too.
    for (final status in <int>[415, 422]) {
      expect(
        hlsErrorKind(status: status, type: 'networkError'),
        HlsErrorKind.unplayable,
        reason: 'http $status',
      );
      expect(
        interpretProbe(status).verdict,
        StreamProbe.unplayable,
        reason: 'http $status',
      );
    }
  });
}
