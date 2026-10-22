import 'package:test/test.dart';
import 'package:waxdeck_api/src/mapping.dart';
import 'package:waxdeck_api_gen/waxdeck_api_gen.dart' as gen;

void main() {
  test('an import entry that failed carries its sentence and reason', () {
    final outcome = opmlImportOutcomeFromGen(
      gen.OpmlImportEntry(
        (b) => b
          ..feedUrl = 'https://members.example/feed.xml'
          ..error = "The feed's host refused the request; it may need a login."
          ..reason = 'host-refused',
      ),
    );
    expect(outcome.feedUrl, 'https://members.example/feed.xml');
    expect(
      outcome.error,
      "The feed's host refused the request; it may need a login.",
    );
    expect(outcome.reason, 'host-refused');
    expect(outcome.failed, isTrue);
  });

  test('an import entry that landed is the show it became', () {
    final outcome = opmlImportOutcomeFromGen(
      gen.OpmlImportEntry(
        (b) => b
          ..feedUrl = 'https://feeds.example/one.xml'
          ..title = 'One'
          ..pid = 'pc-01JZX5N8QW3F4V9T2B7KD3M9R6',
      ),
    );
    expect(outcome.title, 'One');
    expect(outcome.pid, 'pc-01JZX5N8QW3F4V9T2B7KD3M9R6');
    expect(outcome.failed, isFalse);
  });

  test('an entry with neither a show nor an error did not land', () {
    final outcome = opmlImportOutcomeFromGen(
      gen.OpmlImportEntry((b) => b..feedUrl = 'https://feeds.example/x.xml'),
    );
    expect(outcome.failed, isTrue);
  });
}
