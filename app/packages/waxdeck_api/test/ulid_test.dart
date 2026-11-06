import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

const _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// The millisecond timestamp in a ULID's first ten characters.
int _timeOf(String ulid) {
  var ms = 0;
  for (final char in ulid.substring(0, 10).split('')) {
    ms = ms * 32 + _crockford.indexOf(char);
  }
  return ms;
}

void main() {
  test('a ULID parses strictly: Crockford, 26 long, first char 0-7', () {
    final seen = <String>{};
    for (var i = 0; i < 500; i++) {
      final id = newUlid();
      expect(
        RegExp(r'^[0-7][0-9A-HJKMNP-TV-Z]{25}$').hasMatch(id),
        isTrue,
        reason: id,
      );
      expect(seen.add(id), isTrue);
    }
  });

  test('a ULID carries the time it was minted', () {
    final before = DateTime.now().millisecondsSinceEpoch;
    final id = newUlid();
    final after = DateTime.now().millisecondsSinceEpoch;
    expect(_timeOf(id), inInclusiveRange(before, after));
  });

  test('ULIDs minted later sort later', () async {
    final first = newUlid();
    await Future<void>.delayed(const Duration(milliseconds: 2));
    expect(newUlid().compareTo(first), greaterThan(0));
  });

  test('a pid names its item by the ULID after its prefix', () {
    expect(
      ulidOf('tr-01JZX5N8QW3F4V9T2B7KD3M9R6'),
      '01JZX5N8QW3F4V9T2B7KD3M9R6',
    );
    // A kind change keeps the ULID and moves only the prefix.
    expect(
      ulidOf('bk-01JZX5N8QW3F4V9T2B7KD3M9R6'),
      ulidOf('tr-01JZX5N8QW3F4V9T2B7KD3M9R6'),
    );
    expect(ulidOf('01JZX5N8QW3F4V9T2B7KD3M9R6'), '01JZX5N8QW3F4V9T2B7KD3M9R6');
  });
}
