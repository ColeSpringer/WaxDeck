import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/recency_map.dart';

/// The recency map the caches share: insertion order is recency, so the
/// newest entry goes last and the oldest is first to go.
void main() {
  test('a put moves the key to the newest end', () {
    final map = <String, int>{'a': 1, 'b': 2}..putNewest('a', 3, capacity: 5);

    expect(map.keys, ['b', 'a']);
    expect(map['a'], 3);
  });

  test('past its capacity the oldest entries go', () {
    final map = <String, int>{'a': 1, 'b': 2, 'c': 3}
      ..putNewest('d', 4, capacity: 2);

    expect(map.keys, ['c', 'd']);
  });
}
