import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/stats/stats_controller.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

ListeningBucket _b(int y, int m, int d, [int ms = 1]) =>
    ListeningBucket(start: DateTime.utc(y, m, d), ms: ms, sessions: 1);

List<String> _days(List<ListeningBucket> buckets) => <String>[
  for (final b in buckets)
    '${b.start.year}-${b.start.month}-${b.start.day}:${b.ms}',
];

void main() {
  test('unsorted input draws in time order', () {
    expect(_days(evenBuckets([_b(2026, 7, 3, 9), _b(2026, 7, 1, 5)], 'day')), [
      '2026-7-1:5',
      '2026-7-2:0',
      '2026-7-3:9',
    ]);
  });

  test('a single bucket is drawn as it is', () {
    final one = [_b(2026, 7, 1)];
    expect(evenBuckets(one, 'day'), same(one));
  });

  test('a size this build does not know draws as the wire has it', () {
    expect(
      _days(evenBuckets([_b(2026, 7, 9, 2), _b(2026, 7, 1, 1)], 'quarter')),
      ['2026-7-1:1', '2026-7-9:2'],
    );
  });

  test('a start off the grid still draws, in its place', () {
    // Weeks from a Monday, and one bucket on a Wednesday.
    expect(
      _days(
        evenBuckets([
          _b(2026, 6, 29, 1),
          _b(2026, 7, 8, 3),
          _b(2026, 7, 13, 2),
        ], 'week'),
      ),
      ['2026-6-29:1', '2026-7-6:0', '2026-7-8:3', '2026-7-13:2'],
    );
  });

  // The wire's starts are calendar dates (midnight UTC), stepped by the
  // calendar, so a clock change in the caller's zone moves nothing: one
  // bucket per day or week across the US (March 8) and EU (October 25)
  // changes alike, each at midnight.
  test('days across a clock change stay one per calendar day', () {
    for (final (from, to) in <(ListeningBucket, ListeningBucket)>[
      (_b(2026, 3, 7), _b(2026, 3, 10)),
      (_b(2026, 10, 24), _b(2026, 10, 27)),
    ]) {
      final days = evenBuckets([from, to], 'day');
      expect(days, hasLength(4));
      for (var i = 0; i < days.length; i++) {
        expect(
          days[i].start,
          DateTime.utc(from.start.year, from.start.month, from.start.day + i),
        );
      }
    }
  });

  test('weeks across a clock change stay one per Monday', () {
    final weeks = evenBuckets([_b(2026, 3, 2), _b(2026, 3, 23)], 'week');
    expect(weeks.map((b) => b.start), <DateTime>[
      DateTime.utc(2026, 3, 2),
      DateTime.utc(2026, 3, 9),
      DateTime.utc(2026, 3, 16),
      DateTime.utc(2026, 3, 23),
    ]);
    expect(weeks.every((b) => b.start.weekday == DateTime.monday), isTrue);
  });
}
