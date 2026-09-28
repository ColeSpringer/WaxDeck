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
}
