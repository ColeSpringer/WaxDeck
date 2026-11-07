/// The ratchet behind the conventions tests (`ui_conventions_test.dart`,
/// `harness_conventions_test.dart`): a committed allowlist of counts, per
/// file and rule, that may only ever shrink.
///
/// A test keeps what is its own - what it counts, the hint for an
/// over-budget file, its allowlist path and re-seed variable - and hands the
/// counts here. Scanning source is `source_scan.dart`'s business.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Occurrences per file, then per rule.
typedef RatchetCounts = Map<String, Map<String, int>>;

/// Checks [counts] against the allowlist at [allowlist], or, when the
/// environment variable [writeVariable] is `write`, re-seeds the allowlist
/// from them. [reseedWhen] finishes the failure's sentence on when re-seeding
/// is right; [overBudget] describes the findings of an over-budget file and
/// rule.
void checkRatchet({
  required String allowlist,
  required String writeVariable,
  required String reseedWhen,
  required RatchetCounts counts,
  required String Function(String file, String rule) overBudget,
}) {
  if (Platform.environment[writeVariable] == 'write') {
    writeAllowlist(allowlist, counts);
    return;
  }
  final failures = ratchetFailures(
    allowed: readAllowlist(allowlist),
    counts: counts,
    overBudget: overBudget,
  );
  expect(
    failures,
    isEmpty,
    reason:
        'The allowlist in $allowlist only ever shrinks; re-seed it with '
        '$writeVariable=write only when $reseedWhen.\n\n'
        '${failures.join('\n\n')}',
  );
}

/// What stands between the allowlist and the code: one message per file and
/// rule whose count is not exactly its allowance.
///
/// A file with no entry is allowed nothing, and an entry for a file that
/// is neither counted nor [exists] fails, so a rename cannot carry its old
/// tolerance along.
List<String> ratchetFailures({
  required RatchetCounts allowed,
  required RatchetCounts counts,
  required String Function(String file, String rule) overBudget,
  bool Function(String file)? exists,
}) {
  exists ??= (file) => File(file).existsSync();
  final failures = <String>[];
  for (final file in <String>{
    ...allowed.keys,
    ...counts.keys,
  }.toList()..sort()) {
    if (!counts.containsKey(file) && !exists(file)) {
      failures.add(
        '$file: allowlisted, but there is no such file - drop the entry '
        '(a rename must not carry its old tolerance along)',
      );
      continue;
    }
    final rules = <String>{
      ...?allowed[file]?.keys,
      ...?counts[file]?.keys,
    }.toList()..sort();
    for (final rule in rules) {
      final budget = allowed[file]?[rule] ?? 0;
      final actual = counts[file]?[rule] ?? 0;
      if (actual > budget) {
        failures.add(
          '$file: $rule x$actual, allowed $budget\n'
          '${overBudget(file, rule)}',
        );
      } else if (actual < budget) {
        failures.add(
          '$file: $rule x$actual, allowlist still says $budget - '
          'ratchet: lower it to $actual'
          '${actual == 0 ? ' (or drop the entry)' : ''}',
        );
      }
    }
  }
  return failures;
}

/// The allowlist at [path].
RatchetCounts readAllowlist(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as Map).map(
      (file, rules) => MapEntry(
        file as String,
        (rules as Map).map(
          (rule, count) => MapEntry(rule as String, count as int),
        ),
      ),
    );

/// Writes [counts] to [path], files and rules in order.
void writeAllowlist(String path, RatchetCounts counts) {
  final sorted = <String, Map<String, int>>{
    for (final file in counts.keys.toList()..sort())
      file: <String, int>{
        for (final rule in counts[file]!.keys.toList()..sort())
          rule: counts[file]![rule]!,
      },
  };
  File(path).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(sorted)}\n',
  );
}
