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
