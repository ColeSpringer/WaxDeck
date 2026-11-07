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
/// Its mounts (`mountApp`, `pumpApp`, `pumpWholeApp`, `mountHost`) own the
/// container they host: disposed with the tree, and swapped for another
/// only after a frame of their own. A test hosting a container in an
/// `UncontrolledProviderScope` of its own leaves both to chance, so those
/// scopes are counted too, in every file but `app_host.dart`, which holds
/// the mounts.
///
/// So both are counted, per file and rule, against a committed allowlist
/// that may only ever shrink. A count over its allowance fails with the
/// helper to reach for; a count under it fails just as loudly with "lower
/// it", which is what stops a conversion from stalling half-done. A file
/// with no entry has no tolerance at all, and an entry naming a file that
/// no longer exists fails too, so a rename cannot carry a stale floor along
/// with it. The host's constructions are counted like any other's:
/// `app_host.dart` builds the one container and stays on the list. Any
/// other file on it is named, for each rule it is allowed, in
/// [_builtByHand] or [_mountedByHand] with the reason the harness cannot
/// build its world or mount it.
///
/// Re-seed after a deliberate change to what is counted:
///
///     WAXDECK_HARNESS_CONVENTIONS=write flutter test test/harness_conventions_test.dart
void main() {
  group('harness conventions', () {
    test('the allowlist only ever shrinks', () {
      final found = <String, Map<String, List<_Site>>>{};
      for (final file in _sources()) {
        final path = _pathOf(file);
        final source = file.readAsStringSync();
        final rules = {
          _overridesRule: _sitesIn(source),
          _mountRule: _mountsIn(path, source),
        }..removeWhere((_, sites) => sites.isEmpty);
        if (rules.isNotEmpty) found[path] = rules;
      }

      checkRatchet(
        allowlist: _allowlist,
        writeVariable: 'WAXDECK_HARNESS_CONVENTIONS',
        reseedWhen: 'changing what is counted',
        counts: _countsOf(found),
        overBudget: (file, rule) => _describe(file, rule, found[file]![rule]!),
      );
    });

    test('every file allowed a construction of its own says why', () {
      expect(
        _filesAllowed(_overridesRule),
        {_host, ..._builtByHand.keys},
        reason:
            'name each file allowed a construction but $_host in '
            '_builtByHand with why the harness cannot build its world, and '
            'drop the reason of a file no longer listed',
      );
      expect(_builtByHand.values.where((why) => why.trim().isEmpty), isEmpty);
    });

    test('every file allowed a scope of its own says why', () {
      expect(
        _filesAllowed(_mountRule),
        _mountedByHand.keys.toSet(),
        reason:
            'name each file allowed a scope of its own in _mountedByHand '
            'with why the harness cannot mount it, and drop the reason of a '
            'file no longer listed',
      );
      expect(_mountedByHand.values.where((why) => why.trim().isEmpty), isEmpty);
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

  // The mount counter, pinned the same way.
  group('the mount counter', () {
    int count(String source, {String path = 'test/a_test.dart'}) =>
        _mountsIn(path, source).length;

    test('counts a scope mounted by hand in a test file', () {
      expect(count('UncontrolledProviderScope(container: c, child: w)'), 1);
      expect(count('UncontrolledProviderScope.new(container: c, child: w)'), 1);
      expect(
        count('UncontrolledProviderScope(\n  container: c,\n  child: w,\n)'),
        1,
      );
      for (final path in ['test/fakes/a.dart', 'test/player_host.dart']) {
        expect(
          count(
            'UncontrolledProviderScope(container: c, child: w)',
            path: path,
          ),
          1,
        );
      }
    });

    test('leaves the host, which mounts for every other file', () {
      const mount = 'UncontrolledProviderScope(container: c, child: w)';
      expect(count(mount, path: 'test/app_host.dart'), 0);
    });

    test('a comment or a string is not a mount', () {
      expect(count('// UncontrolledProviderScope(container: c, child: w)'), 0);
      expect(count('/* UncontrolledProviderScope(container: c) */'), 0);
      expect(count("'UncontrolledProviderScope(container: c, child: w)'"), 0);
      expect(
        count(r"'${UncontrolledProviderScope(container: c, child: w)}'"),
        1,
      );
    });

    test('a scope building its own container is not one', () {
      expect(count('ProviderScope(child: w)'), 0);
      expect(count('ProviderScope.containerOf(context)'), 0);
    });
  });

  group('the over-budget hint', () {
    test('lists each construction and names the helper to reach for', () {
      final hint = _describe('a_test.dart', _overridesRule, [
        (line: 3, snippet: 'final c = ProviderContainer('),
        (line: 9, snippet: 'ProviderScope(overrides: o, child: c)'),
      ]);
      expect(hint, contains('a_test.dart:3  final c = ProviderContainer('));
      expect(hint, contains('a_test.dart:9  ProviderScope(overrides: o'));
      expect(hint, contains('appContainer()'));
      expect(hint, contains('pumpApp() (test/app_host.dart)'));
    });

    test('lists each scope mounted by hand and names the mounts', () {
      final hint = _describe('a_test.dart', _mountRule, [
        (line: 4, snippet: 'UncontrolledProviderScope('),
      ]);
      expect(hint, contains('a_test.dart:4  UncontrolledProviderScope('));
      for (final helper in [
        'pumpApp()',
        'mountApp()',
        'pumpWholeApp()',
        'mountHost()',
        'leaveScreen()',
      ]) {
        expect(hint, contains(helper));
      }
    });
  });

  // A repository faked inside a test drifts from the shared one: every
  // endpoint the API gains has to be faked again there. So the fakes are
  // the only implementers, and a test wanting other answers extends
  // FakeRepository.
  group('fakes live in one place', () {
    test('only the fakes implement the repository or a tag interface', () {
      final found = [
        for (final file in _sources())
          if (!_mayImplement(_pathOf(file)))
            for (final site in _implementersIn(file.readAsStringSync()))
              '  ${_pathOf(file)}:${site.line}  ${site.snippet}',
      ];
      expect(
        found,
        isEmpty,
        reason:
            'extend FakeRepository (test/fakes.dart), or fake the endpoint '
            'in its tag mixin under test/fakes/:\n${found.join('\n')}',
      );
    });
  });

  group('the implementer finder', () {
    List<int> lines(String source) => [
      for (final site in _implementersIn(source)) site.line,
    ];

    test('finds a tag interface or the repository being implemented', () {
      expect(lines('class X implements LibraryApi {}'), [1]);
      expect(lines('class X implements WaxDeckRepository {}'), [1]);
      expect(lines('mixin M on S implements Comparable<M>, SharesApi {}'), [1]);
      expect(lines('abstract base class X implements PlaylistsApi {}'), [1]);
      expect(lines('class X = Y with Z implements WaxDeckRepository;'), [1]);
    });

    test('finds an enum or an extension type implementing one', () {
      expect(lines('enum E implements LibraryApi { a }'), [1]);
      expect(
        lines('extension type X(LibraryApi api) implements LibraryApi {}'),
        [1],
      );
    });

    test('reads a header across lines, past a record type', () {
      expect(
        lines(
          'void f() {}\n'
          'class X extends Base<({int a})>\n'
          '    with M\n'
          '    implements WaxDeckRepository {\n'
          '}\n',
        ),
        [2],
      );
    });

    test('leaves a subclass of the fake and other interfaces', () {
      expect(lines('class X extends FakeRepository {}'), isEmpty);
      expect(lines('class X extends LibraryApi {}'), isEmpty);
      expect(lines('class X implements Comparable<X> {}'), isEmpty);
      expect(lines('class X {\n  final LibraryApi api;\n}'), isEmpty);
    });

    test('a comment is not code', () {
      expect(lines('// class X implements LibraryApi {}'), isEmpty);
      expect(lines('/// class X implements WaxDeckRepository {}'), isEmpty);
      expect(lines('/* class X implements LibraryApi {} */'), isEmpty);
    });

    test('a string is not code', () {
      expect(lines("const s = 'class X implements LibraryApi {}';"), isEmpty);
      expect(
        lines("const s = '''\nclass X implements WaxDeckRepository {}\n''';"),
        isEmpty,
      );
    });

    test('exempts fakes.dart and the files directly under fakes/', () {
      expect(_mayImplement('test/fakes.dart'), isTrue);
      expect(_mayImplement('test/fakes/library_fake.dart'), isTrue);
      expect(_mayImplement('test/fakes/deeper/x.dart'), isFalse);
      expect(_mayImplement('test/library_fake.dart'), isFalse);
    });
  });
}

/// The committed allowance per file, relative to `app/app` (where this
/// test runs).
const _allowlist = 'test/harness_conventions_allowlist.json';

/// Where the fix for a breach lives.
const _host = 'test/app_host.dart';

/// The files besides [_host] allowed a construction of their own, each with
/// why `appContainer` cannot build their world.
const _builtByHand = <String, String>{
  'test/catalog_check_section_test.dart':
      'overrides the repository with a builder that follows the server '
      'address; appContainer overrides it with a value',
  'test/server_switch_downloads_test.dart':
      'overrides the repository with a builder that follows the server '
      'address, and builds the sync engine and downloads on it; '
      'appContainer overrides the repository with a value',
};

/// The files allowed a scope of their own, each with why the harness
/// cannot mount it.
const _mountedByHand = <String, String>{
  'test/app_host_test.dart':
      'pins how the harness takes over from a scope mounted by hand',
};

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

/// An `UncontrolledProviderScope(` call, `.new(` too: a container hosted in
/// a scope the harness did not mount.
final _handMount = RegExp(r'\bUncontrolledProviderScope(?:\.new)?\(');

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

/// Every construction in [source], by line.
List<_Site> _sitesIn(String source) =>
    _sitesAt(source, _constructionsIn(_blanked(source)));

/// Every scope the file at [path], holding [source], mounts by hand, by
/// line; none in the host.
List<_Site> _mountsIn(String path, String source) => path == _host
    ? const <_Site>[]
    : _sitesAt(source, [
        for (final match in _handMount.allMatches(_blanked(source)))
          match.start,
      ]);

/// What in [source] starts at each of [offsets], by line. Offsets survive
/// the blanking, so the line is the file's own.
List<_Site> _sitesAt(String source, List<int> offsets) {
  final lines = source.split('\n');
  _Site site(int at) {
    final index = '\n'.allMatches(source.substring(0, at)).length;
    return (line: index + 1, snippet: lines[index].trim());
  }

  return [for (final at in offsets) site(at)];
}

/// A construction carrying overrides, as the allowlist names the rule.
const _overridesRule = 'provider-overrides';

/// A scope mounted by hand, as the allowlist names the rule.
const _mountRule = 'hand-mounted-scope';

/// [found] as the ratchet counts it.
Map<String, Map<String, int>> _countsOf(
  Map<String, Map<String, List<_Site>>> found,
) => {
  for (final MapEntry(key: file, value: rules) in found.entries)
    file: {
      for (final MapEntry(key: rule, value: sites) in rules.entries)
        rule: sites.length,
    },
};

/// The files the allowlist allows [rule].
Set<String> _filesAllowed(String rule) => {
  for (final MapEntry(:key, :value) in readAllowlist(_allowlist).entries)
    if (value.containsKey(rule)) key,
};

/// Where the fix for each rule's breaches lives.
const _fixes = {
  _overridesRule:
      'build the container with appContainer() and mount with pumpApp() '
      '($_host); ports go as appContainer parameters, anything else as '
      'extra',
  _mountRule:
      'mount with pumpApp() or mountApp(), the whole app with '
      'pumpWholeApp() and any other host with mountHost() ($_host), whose '
      'scope owns the container; leaveScreen() takes a screen away and '
      'keeps it',
};

/// An over-budget file's sites for [rule], and where the fix for them lives.
String _describe(String file, String rule, List<_Site> sites) =>
    '${sites.map((s) => '  $file:${s.line}  ${s.snippet}').join('\n')}\n'
    '    -> ${_fixes[rule]}';

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

/// Whether the file at [path] may implement the repository: the fakes'
/// barrel and the files directly under `test/fakes/`.
bool _mayImplement(String path) =>
    path == 'test/fakes.dart' || _fakePart.hasMatch(path);

/// A file directly under `test/fakes/`.
final _fakePart = RegExp(r'^test/fakes/[^/]+\.dart$');

/// A class, mixin, enum or extension type declaration, up to its name.
final _declaration = RegExp(
  r'\b(?:class|mixin|enum|extension\s+type)\s+[\w$]+',
);

/// The keyword opening an `implements` clause.
final _implementsKeyword = RegExp(r'\bimplements\b');

/// The repository or one of its tag interfaces, as a type name.
final _repositoryType = RegExp(r'\b(?:WaxDeckRepository|[A-Z][\w$]*Api)\b');

/// Every declaration in [source] whose `implements` clause names the
/// repository or a tag interface, by the line its keyword is on.
List<_Site> _implementersIn(String source) {
  final code = _blanked(source);
  final lines = source.split('\n');
  _Site site(int at) {
    final index = '\n'.allMatches(code.substring(0, at)).length;
    return (line: index + 1, snippet: lines[index].trim());
  }

  return [
    for (final match in _declaration.allMatches(code))
      if (_implementsRepository(_headerFrom(code, match.end)))
        site(match.start),
  ];
}

/// A declaration's header from [from] to the brace opening its body, or
/// the `;` ending a mixin application. A record type's braces sit inside
/// parentheses, so those are walked past.
String _headerFrom(String code, int from) {
  var depth = 0;
  for (var i = from; i < code.length; i++) {
    final char = code[i];
    if (char == '(') depth++;
    if (char == ')') depth--;
    if (depth == 0 && (char == '{' || char == ';')) {
      return code.substring(from, i);
    }
  }
  return code.substring(from);
}

/// Whether [header] has an `implements` clause naming the repository or
/// a tag interface.
bool _implementsRepository(String header) {
  final clause = _implementsKeyword.firstMatch(header);
  return clause != null &&
      _repositoryType.hasMatch(header.substring(clause.end));
}
