import 'package:test/test.dart';
import 'package:waxdeck_api/src/gen/codec.g.dart';
import 'package:waxdeck_api/src/wire.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

const _ctx = WireContext(baseUrl: '');

void main() {
  test('an import entry that failed carries its sentence and reason', () {
    final outcome = decodeOpmlImportOutcome({
      'feedUrl': 'https://members.example/feed.xml',
      'error': "The feed's host refused the request; it may need a login.",
      'reason': 'host-refused',
    }, _ctx);
    expect(outcome.feedUrl, 'https://members.example/feed.xml');
    expect(
      outcome.error,
      "The feed's host refused the request; it may need a login.",
    );
    expect(outcome.reason, 'host-refused');
    expect(outcome.failed, isTrue);
  });

  test('an import entry that landed is the show it became', () {
    final outcome = decodeOpmlImportOutcome({
      'feedUrl': 'https://feeds.example/one.xml',
      'title': 'One',
      'pid': 'pc-01JZX5N8QW3F4V9T2B7KD3M9R6',
    }, _ctx);
    expect(outcome.title, 'One');
    expect(outcome.pid, 'pc-01JZX5N8QW3F4V9T2B7KD3M9R6');
    expect(outcome.failed, isFalse);
  });

  test('an entry with neither a show nor an error did not land', () {
    final outcome = decodeOpmlImportOutcome({
      'feedUrl': 'https://feeds.example/x.xml',
    }, _ctx);
    expect(outcome.failed, isTrue);
  });
}
