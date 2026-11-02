import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';

/// The identifiers Flutter renders as `flt-semantics-identifier` are what
/// the browser-driven e2e suite steers by, and the suite compiles against
/// the same generated list. That only holds while nobody writes an
/// identifier string by hand, so this test walks the source and says so
/// when someone does.
void main() {
  group('semantics id registry', () {
    final lib = Directory('lib');
    final sources = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('shell/semantics_ids.dart'))
        .toList();

    // Both spellings. `identifier:` is what a raw Semantics widget
    // takes; `semanticsId:` is what every design-system component takes,
    // and it is the one the console screens reached for - so a guard
    // that watched only the first stayed green through a whole phase of
    // hand-typed handles. `clearSemanticsId`, `backSemanticsId` and the
    // rest of the family end in the same word and are caught by the
    // same pattern.
    test('no screen writes an identifier string by hand', () {
      final offenders = <String>[];
      final literal = RegExp(
        r"""(?:[Ii]dentifier|[sS]emanticsId):\s*(?:const\s+)?['"]""",
      );
      for (final file in sources) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (literal.hasMatch(lines[i])) {
            offenders.add('${file.path}:${i + 1}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Add the identifier to its group in app/semantics-ids/, run '
            '`make generate`, and use SemanticsIds instead:\n'
            '${offenders.join('\n')}',
      );
    });

    // The same rule for the tests: a finder that types an identifier
    // the registry generates goes stale silently on a rename, one literal
    // at a time. A finder string is a generated id when it equals a fixed
    // one or fits a parameterised one's shape; a Key compares against the
    // fixed ones only, since plain widget keys share their prefixes.
    test('no test types an identifier the registry generates', () {
      // Each exempt file types identifiers on purpose, and says why.
      const exempt = <String, String>{
        // This file pins the frozen vocabulary by its literal values.
        'test/semantics_ids_registry_test.dart': 'the vocabulary itself',
      };
      final registry = _registry();
      final offenders = <String>[];
      for (final root in <String>['test', 'integration_test']) {
        final files = Directory(root)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) => !exempt.containsKey(f.path));
        for (final file in files) {
          for (final (:line, :id) in _typedIdentifiers(
            file.readAsStringSync(),
            registry,
          )) {
            offenders.add('${file.path}:$line $id');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Use the SemanticsIds constant for each of these, or add the '
            'file to the exemptions with the reason it must type one:\n'
            '${offenders.join('\n')}',
      );
    });

    test('the guard sees a finder that the formatter split across lines', () {
      const source = '''
final a = find.bySemanticsIdentifier(
  'login-username',
);
final b = waxControl<WaxButton>(
  'user-row-us-3',
);
final c = find.byKey(const Key(
  'login-submit',
));
''';
      expect(_typedIdentifiers(source, _registry()).toList(), [
        (line: 1, id: 'login-username'),
        (line: 4, id: 'user-row-us-3'),
        (line: 7, id: 'login-submit'),
      ]);
    });

    test('every generated identifier is unique', () {
      final files = Directory('../semantics-ids')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();
      expect(files, isNotEmpty, reason: 'no group files in app/semantics-ids');
      final ids = <String>[];
      for (final file in files) {
        final source =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        ids.addAll((source['ids']! as Map<String, dynamic>).values.cast());
      }
      expect(ids.toSet().length, ids.length, reason: 'duplicate identifiers');
    });

    test('the frozen accessibility vocabulary is intact', () {
      // The a11y audit drives login through roles and names alone, and
      // the sync spec drives starring by identifier. These names are the
      // contract; renaming one is a spec change, not a refactor.
      expect(SemanticsIds.loginUsername, 'login-username');
      expect(SemanticsIds.loginPassword, 'login-password');
      expect(SemanticsIds.loginSubmit, 'login-submit');
      expect(SemanticsIds.starButton(''), 'star-button');
      expect(SemanticsIds.item('tr-01'), 'item-tr-01');
    });
  });
}

/// The registry's fixed identifiers, and a shape for each parameterised
/// one.
({Set<String> fixed, List<RegExp> shaped}) _registry() {
  final fixed = <String>{};
  final shaped = <RegExp>[];
  for (final file in Directory(
    '../semantics-ids',
  ).listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
    final source = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    for (final id
        in (source['ids']! as Map<String, dynamic>).values.cast<String>()) {
      if (!id.contains('{')) {
        fixed.add(id);
        continue;
      }
      final parts = id.split(RegExp(r'\{[A-Za-z]+\}'));
      shaped.add(RegExp('^${parts.map(RegExp.escape).join('.+')}\$'));
    }
  }
  return (fixed: fixed, shaped: shaped);
}

/// Every generated identifier [source] types: a finder string that is a
/// fixed id or fits a parameterised one's shape, and a `Key` string that
/// is a fixed id (plain widget keys share the shapes' prefixes), with
/// the line each one starts on.
Iterable<({int line, String id})> _typedIdentifiers(
  String source,
  ({Set<String> fixed, List<RegExp> shaped}) registry,
) sync* {
  final finder = RegExp(
    r"(?:bySemanticsIdentifier|waxControl<[^>]*>)\(\s*'([^'$\\]+)'",
  );
  final key = RegExp(r"Key\(\s*'([^'$\\]+)',?\s*\)");
  // Matched over the whole source, so a call the formatter broke after
  // its bracket still reads as one; the line is where the call starts.
  int lineOf(int offset) =>
      '\n'.allMatches(source.substring(0, offset)).length + 1;
  final hits = <({int at, String id})>[
    for (final m in finder.allMatches(source))
      if (registry.fixed.contains(m[1]) ||
          registry.shaped.any((shape) => shape.hasMatch(m[1]!)))
        (at: m.start, id: m[1]!),
    for (final m in key.allMatches(source))
      if (registry.fixed.contains(m[1])) (at: m.start, id: m[1]!),
  ]..sort((a, b) => a.at.compareTo(b.at));
  for (final hit in hits) {
    yield (line: lineOf(hit.at), id: hit.id);
  }
}
