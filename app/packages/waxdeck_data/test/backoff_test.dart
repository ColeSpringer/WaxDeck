import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

List<int> _seconds(Backoff backoff, int times) => [
  for (var i = 0; i < times; i++) backoff.take().inSeconds,
];

void main() {
  test('waits a second, then twice as long each time, and never longer '
      'than a minute', () {
    expect(_seconds(Backoff(), 9), [1, 2, 4, 8, 16, 32, 60, 60, 60]);
  });

  test('reset starts it over from the first wait', () {
    final backoff = Backoff();
    expect(_seconds(backoff, 4), [1, 2, 4, 8]);

    backoff.reset();
    expect(_seconds(backoff, 3), [1, 2, 4]);
  });

  test('one that starts at once waits nothing first, then a second, '
      'doubling, and starts over at once', () {
    final backoff = Backoff(startsAtOnce: true);
    expect(_seconds(backoff, 9), [0, 1, 2, 4, 8, 16, 32, 60, 60]);

    backoff.reset();
    expect(_seconds(backoff, 2), [0, 1]);
  });

  test('refuses a first wait of none, which would never grow', () {
    expect(() => Backoff(first: Duration.zero), throwsAssertionError);
    expect(
      () => Backoff(first: Duration.zero, startsAtOnce: true),
      throwsAssertionError,
    );
  });

  test('takes its first and last waits as given', () {
    final backoff = Backoff(
      first: const Duration(milliseconds: 250),
      last: const Duration(seconds: 1),
    );

    expect(
      [for (var i = 0; i < 5; i++) backoff.take().inMilliseconds],
      [250, 500, 1000, 1000, 1000],
    );
  });
}
