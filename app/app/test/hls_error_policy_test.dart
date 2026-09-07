import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

/// What an hls.js error means, read off the fields hls.js sends. Pure
/// so it runs here on the VM: the engine that acts on it is browser-only.
void main() {
  HlsErrorKind kind({
    int? status,
    String type = 'networkError',
    String details = '',
  }) => hlsErrorKind(status: status, type: type, details: details);

  test('the server saying no is read off the status, whatever the type', () {
    expect(kind(status: 429), HlsErrorKind.refused);
    expect(kind(status: 429, type: 'mediaError'), HlsErrorKind.refused);
    for (final gone in <int>[401, 404, 410]) {
      expect(kind(status: gone), HlsErrorKind.gone, reason: 'http $gone');
    }
    // The status wins over the type: a fetch that answered 404 is a
    // rendering that is gone, however hls.js filed the consequence.
    expect(
      kind(status: 404, type: 'mediaError', details: 'bufferAppendError'),
      HlsErrorKind.gone,
    );
  });

  test(
    'a codec this browser cannot play is the one media error no retry answers',
    () {
      for (final detail in <String>[
        'bufferAddCodecError',
        'bufferIncompatibleCodecsError',
        'manifestIncompatibleCodecsError',
      ]) {
        expect(
          kind(type: 'mediaError', details: detail),
          HlsErrorKind.unplayable,
          reason: detail,
        );
      }
    },
  );

  test('every other media error is the pipeline, not the file', () {
    // The buffer hiccuping under load, a fragment that would not parse
    // once: hls.js documents recovering these in place, and none of
    // them says anything about the rendering.
    for (final detail in <String>[
      // What the pipeline actually said, twice in one load, under
      // twenty busy cores: the measured case this exists for.
      'mediaSourceRequiresReset',
      'bufferAppendError',
      'bufferAppendingError',
      'bufferStalledError',
      'bufferFullError',
      'fragParsingError',
      'remuxAllocError',
      '',
    ]) {
      expect(
        kind(type: 'mediaError', details: detail),
        HlsErrorKind.media,
        reason: '"$detail"',
      );
    }
  });

  test('anything else fatal is the fetch', () {
    expect(kind(status: 500), HlsErrorKind.transport);
    expect(kind(type: 'networkError'), HlsErrorKind.transport);
    expect(kind(type: 'otherError'), HlsErrorKind.transport);
    expect(kind(type: ''), HlsErrorKind.transport);
  });
}
