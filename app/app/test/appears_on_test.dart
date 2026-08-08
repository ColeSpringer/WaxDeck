import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/music/artist_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

FacetBucket _album(String label, {String? pid, int count = 1}) => FacetBucket(
  key: pid == null ? '' : pid.substring(3),
  label: label,
  count: count,
  entityPid: pid,
  unknown: pid == null,
);

void main() {
  group('appearsOnBuckets', () {
    // The endpoint answers album buckets counted over this artist's
    // credits, so six credited tracks off one compilation arrive as one
    // bucket carrying six. Nothing left to collapse.
    test('keeps a release the artist does not head, with its count', () {
      final kept = appearsOnBuckets(<FacetBucket>[
        _album('Big Compilation', pid: 'al-comp', count: 6),
      ], const <String>{});

      expect(kept, hasLength(1));
      expect(kept.single.label, 'Big Compilation');
      expect(kept.single.count, 6);
    });

    // A release the artist heads is already drawn under Releases;
    // leaving it here makes the screen repeat itself.
    test('excludes releases already drawn as the artist own', () {
      final kept = appearsOnBuckets(
        <FacetBucket>[
          _album('Their Own Record', pid: 'al-own'),
          _album('Someone Else', pid: 'al-other'),
        ],
        const <String>{'al-own'},
      );

      expect(kept.map((b) => b.entityPid), <String>['al-other']);
    });

    // Two releases can share a title, so the exclusion keys on the entity
    // pid. Dropping both because one matched is the bug the Releases
    // shelf avoids by opening its tiles positionally.
    test('two releases sharing a title are told apart by pid', () {
      final kept = appearsOnBuckets(
        <FacetBucket>[
          _album('Greatest Hits', pid: 'al-mine'),
          _album('Greatest Hits', pid: 'al-theirs'),
        ],
        const <String>{'al-mine'},
      );

      expect(kept.map((b) => b.entityPid), <String>['al-theirs']);
      expect(kept.single.label, 'Greatest Hits');
    });

    // [Non-Album] is a real bucket the enumeration returns, and it has no
    // entity behind it: a card drawn for it would open nothing.
    test('drops the unknown bucket', () {
      final kept = appearsOnBuckets(<FacetBucket>[
        _album('[Non-Album]', count: 3),
        _album('Someone Else', pid: 'al-other'),
      ], const <String>{});

      expect(kept.map((b) => b.entityPid), <String>['al-other']);
    });

    test('nothing credited is an empty shelf, not an error', () {
      expect(
        appearsOnBuckets(const <FacetBucket>[], const <String>{}),
        isEmpty,
      );
    });
  });
}
