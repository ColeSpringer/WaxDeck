import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';
import 'source_scan.dart';

/// How tests build their provider world, as a ratchet.
///
/// A test that opens its own `ProviderScope` or `ProviderContainer` with an
/// `overrides:` list names every port it needs, in every file, and each
/// copy drifts: a port added to the app is faked in some tests and
/// reaches a real plugin in the rest. `test/app_host.dart` holds the one
/// builder (`appContainer`) and the mount helpers (`pumpApp`, `mountApp`)
/// with the default fakes in place; a test passes only what differs.
///
/// So the constructions are counted, per file, against a committed
/// allowlist that may only ever shrink. A count over its allowance fails
/// with the helper to reach for; a count under it fails just as loudly
/// with "lower it", which is what stops a conversion from stalling
/// half-done. A file with no entry has no tolerance at all, and an entry
/// naming a file that no longer exists fails too, so a rename cannot carry
/// a stale floor along with it. The host files are counted like any other:
/// `app_host.dart` builds the one container and stays on the list.
///
/// Re-seed after a deliberate change to what is counted:
///
///     WAXDECK_HARNESS_CONVENTIONS=write flutter test test/harness_conventions_test.dart
void main() {
  group('harness conventions', () {
    test('the allowlist only ever shrinks', () {
      final found = <String, List<_Site>>{};
      for (final file in _sources()) {
        final path = _pathOf(file);
        final sites = _sitesIn(file.readAsStringSync());
        if (sites.isNotEmpty) found[path] = sites;
      }

      checkRatchet(
        allowlist: _allowlist,
        writeVariable: 'WAXDECK_HARNESS_CONVENTIONS',
        reseedWhen: 'changing what is counted',
        counts: _countsOf(found),
        overBudget: (file, _) => _describe(file, found[file]!),
      );
    });
  });

  // What the counter reads, pinned directly: a count that quietly stops
  // seeing a shape reports zero for a file still building its own world.
  group('the construction counter', () {
    int count(String source) => _constructionsIn(_blanked(source)).length;

    test('counts a scope or a container carrying overrides', () {
      expect(count('ProviderScope(overrides: [a], child: c)'), 1);
      expect(count('final c = ProviderContainer(overrides: [a]);'), 1);
      expect(count('const ProviderScope(overrides: [], child: c)'), 1);
      expect(count('ProviderContainer(\n  overrides: [\n    a,\n  ],\n)'), 1);
      expect(count('ProviderScope(child: c, overrides: o)'), 1);
    });

    test('counts the named spellings too', () {
      expect(count('ProviderContainer.test(overrides: [a])'), 1);
      expect(count('final c = ProviderContainer.new(overrides: [a]);'), 1);
      expect(count('ProviderScope.new(overrides: [a], child: c)'), 1);
      expect(
        count('ProviderContainer.test(\n  overrides: [\n    a,\n  ],\n)'),
        1,
      );
      expect(count('ProviderContainer.test()'), 0);
      expect(count('ProviderContainer.test(parent: p)'), 0);
      expect(count('ProviderScope.containerOf(context)'), 0);
      expect(count('UncontrolledProviderScope.new(container: c, child: w)'), 0);
    });

    test('leaves one with none', () {
      expect(count('ProviderScope(child: c)'), 0);
      expect(count('ProviderContainer()'), 0);
      expect(count('ProviderContainer(parent: p)'), 0);
    });

    test('never counts an uncontrolled scope', () {
      expect(count('UncontrolledProviderScope(container: c, child: w)'), 0);
      expect(count('UncontrolledProviderScope(overrides: o, child: w)'), 0);
    });

    test('reads a construction\'s own arguments, not what is nested', () {
      expect(count('ProviderScope(child: Foo(overrides: [a]))'), 0);
      expect(count('ProviderScope(child: f(x, overrides: y))'), 0);
      expect(count('ProviderScope(child: Foo(), overrides: [a])'), 1);
      expect(
        count('ProviderContainer(parent: ProviderContainer(overrides: [a]))'),
        1,
      );
    });

    test('counts each construction on its own', () {
      expect(
        count(
          'ProviderScope(overrides: [a], '
          'child: ProviderScope(overrides: [b], child: c))',
        ),
        2,
      );
    });

    test('walks past brackets inside strings and nested calls', () {
      expect(
        count(
          "ProviderContainer(\n"
          "  observers: [Obs(')')],\n"
          "  retry: (_, _) => null,\n"
          "  overrides: [a(')', \"(\")],\n"
          ")",
        ),
        1,
      );
    });

    test('a comment is not code', () {
      expect(count('// ProviderScope(overrides: [a])'), 0);
      expect(count('/* ProviderContainer(overrides: [a]) */'), 0);
      expect(count('ProviderScope(\n  // overrides: [a]\n  child: c)'), 0);
    });

    test('a string is not code, but what it interpolates is', () {
      expect(count("'ProviderScope(overrides: [a])'"), 0);
      expect(count("'''\nProviderContainer(overrides: [a])\n'''"), 0);
      expect(count("ProviderScope(key: Key('a, overrides: x'), child: c)"), 0);
      expect(count(r"'${ProviderContainer(overrides: [a])}'"), 1);
    });

    test('says which line each one starts on', () {
      const source =
          'void main() {\n'
          '  final a = ProviderContainer(\n'
          '    overrides: [x],\n'
          '  );\n'
          '  final b = ProviderContainer();\n'
          '  final c = ProviderScope(overrides: [y], child: z);\n'
          '}\n';
      expect(_sitesIn(source), [
        (line: 2, snippet: 'final a = ProviderContainer('),
        (
          line: 6,
          snippet: 'final c = ProviderScope(overrides: [y], child: z);',
        ),
      ]);
    });
  });

  group('the over-budget hint', () {
    test('lists each construction and names the helper to reach for', () {
      final hint = _describe('a_test.dart', [
        (line: 3, snippet: 'final c = ProviderContainer('),
        (line: 9, snippet: 'ProviderScope(overrides: o, child: c)'),
      ]);
      expect(hint, contains('a_test.dart:3  final c = ProviderContainer('));
      expect(hint, contains('a_test.dart:9  ProviderScope(overrides: o'));
      expect(hint, contains('appContainer()'));
      expect(hint, contains('pumpApp() (test/app_host.dart)'));
    });
  });
}

/// The committed allowance per file, relative to `app/app` (where this
/// test runs).
const _allowlist = 'test/harness_conventions_allowlist.json';

/// Where the fix for a breach lives.
const _host = 'test/app_host.dart';

typedef _Site = ({int line, String snippet});

/// A `ProviderScope(` or `ProviderContainer(` call, by any constructor name
/// (`.test(`, `.new(`). Word-bounded, so `UncontrolledProviderScope(` is no
/// match: it builds nothing, it hosts a container somebody else built.
final _construction = RegExp(
  r'\b(?:ProviderScope|ProviderContainer)(?:\.\w+)?\(',
);

/// `overrides:` standing as an argument's name: first in the list or after
/// a comma, never inside a value.
final _overridesArgument = RegExp(r'(?:^|,)\s*overrides\s*:');

/// [source] ready for counting: comments and the text of strings blanked.
String _blanked(String source) => blankComments(source, strings: true);

/// Where in [code] (already blanked) each construction carrying an
/// `overrides:` argument of its own starts.
List<int> _constructionsIn(String code) => [
  for (final match in _construction.allMatches(code))
    if (_carriesOverrides(code, match.end - 1)) match.start,
];

/// Whether the call whose `(` is at [open] has an `overrides:` argument of
/// its own, found by walking the brackets so that a nested call's
/// arguments are its own business.
bool _carriesOverrides(String code, int open) {
  final own = StringBuffer();
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    final char = code[i];
    final before = depth;
    if ('([{'.contains(char)) depth++;
    if (')]}'.contains(char)) depth--;
    if (depth == 0) break;
    own.write(before == 1 && depth == 1 ? char : ' ');
  }
  return _overridesArgument.hasMatch(own.toString());
}

/// Every construction in [source], by line. Offsets survive the blanking,
/// so the line is the file's own.
List<_Site> _sitesIn(String source) {
  final lines = source.split('\n');
  _Site site(int at) {
    final index = '\n'.allMatches(source.substring(0, at)).length;
    return (line: index + 1, snippet: lines[index].trim());
  }

  return [for (final at in _constructionsIn(_blanked(source))) site(at)];
}

/// The one rule this test counts, as the allowlist names it.
const _rule = 'provider-overrides';

/// [found] as the ratchet counts it.
Map<String, Map<String, int>> _countsOf(Map<String, List<_Site>> found) => {
  for (final entry in found.entries) entry.key: {_rule: entry.value.length},
};

/// An over-budget file's constructions, and where the fix for them lives.
String _describe(String file, List<_Site> sites) =>
    '${sites.map((s) => '  $file:${s.line}  ${s.snippet}').join('\n')}\n'
    '    -> build the container with appContainer() and mount with '
    'pumpApp() ($_host); ports go as appContainer parameters, '
    'anything else as extra';

/// A source's path with forward slashes, as the allowlist spells it.
String _pathOf(File file) => file.path.split(Platform.pathSeparator).join('/');

/// Every Dart file under `test/`, hosts and helpers included.
List<File> _sources() =>
    Directory('test')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
