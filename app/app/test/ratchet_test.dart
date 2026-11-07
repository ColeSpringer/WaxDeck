import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';

/// The shared ratchet's own mechanics, apart from what either conventions
/// test counts with it. A message pinned here is the message both of them
/// print.
void main() {
  group('the ratchet', () {
    List<String> check(
      Map<String, int> allowed,
      Map<String, int> actual, {
      Set<String> gone = const <String>{},
    }) => ratchetFailures(
      allowed: {
        for (final entry in allowed.entries) entry.key: {'rule': entry.value},
      },
      counts: {
        for (final entry in actual.entries) entry.key: {'rule': entry.value},
      },
      overBudget: (file, rule) => '  detail for $file',
      exists: (file) => !gone.contains(file),
    );

    test('passes a file at its allowance', () {
      expect(check({'a.dart': 2}, {'a.dart': 2}), isEmpty);
      expect(check({}, {}), isEmpty);
    });

    test('fails a file over its allowance, with the caller\'s detail', () {
      expect(check({'a.dart': 1}, {'a.dart': 2}), [
        'a.dart: rule x2, allowed 1\n  detail for a.dart',
      ]);
    });

    test('holds a file with no entry to nothing at all', () {
      expect(check({}, {'new_test.dart': 1}), [
        'new_test.dart: rule x1, allowed 0\n  detail for new_test.dart',
      ]);
    });

    test('fails a file under its allowance until the entry is lowered', () {
      final failures = check({'a.dart': 3}, {'a.dart': 1});
      expect(failures, [
        'a.dart: rule x1, allowlist still says 3 - ratchet: lower it to 1',
      ]);
    });

    test('fails a converted file until its entry is dropped', () {
      final failures = check({'a.dart': 3}, {});
      expect(failures.single, contains('lower it to 0 (or drop the entry)'));
    });

    test('fails an entry for a file that no longer exists', () {
      final failures = check({'old_test.dart': 1}, {}, gone: {'old_test.dart'});
      expect(failures, [
        'old_test.dart: allowlisted, but there is no such file - drop the '
            'entry (a rename must not carry its old tolerance along)',
      ]);
    });

    test('holds each rule of a file to its own allowance', () {
      final failures = ratchetFailures(
        allowed: {
          'a.dart': {'one': 1, 'two': 2},
        },
        counts: {
          'a.dart': {'one': 2, 'two': 1, 'three': 1},
        },
        overBudget: (file, rule) => '  detail $rule',
        exists: (_) => true,
      );
      expect(failures, [
        'a.dart: one x2, allowed 1\n  detail one',
        'a.dart: three x1, allowed 0\n  detail three',
        'a.dart: two x1, allowlist still says 2 - ratchet: lower it to 1',
      ]);
    });
  });

  group('the allowlist file', () {
    late Directory dir;
    late String path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('ratchet');
      path = '${dir.path}/allowlist.json';
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('is written sorted and reads back as the same counts', () {
      final counts = {
        'b.dart': {'y': 2, 'x': 1},
        'a.dart': {'z': 3},
      };
      writeAllowlist(path, counts);
      expect(
        File(path).readAsStringSync(),
        '{\n'
        '  "a.dart": {\n    "z": 3\n  },\n'
        '  "b.dart": {\n    "x": 1,\n    "y": 2\n  }\n'
        '}\n',
      );
      expect(readAllowlist(path), counts);
    });

    test('is checked with a reason that says how and when to re-seed', () {
      writeAllowlist(path, {
        'a.dart': {'rule': 1},
      });
      const unset = 'WAXDECK_RATCHET_TEST_UNSET';
      void run(int count) => checkRatchet(
        allowlist: path,
        writeVariable: unset,
        reseedWhen: 'testing',
        counts: {
          'a.dart': {'rule': count},
        },
        overBudget: (file, rule) => '  detail for $file',
      );

      expect(() => run(1), returnsNormally);
      expect(
        () => run(2),
        throwsA(
          isA<TestFailure>().having(
            (failure) => failure.message,
            'message',
            contains(
              'The allowlist in $path only ever shrinks; re-seed it with '
              '$unset=write only when testing.\n\n'
              'a.dart: rule x2, allowed 1\n  detail for a.dart',
            ),
          ),
        ),
      );
    });
  });
}
