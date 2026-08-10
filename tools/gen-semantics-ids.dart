// Generates the semantics-identifier registry the app and the e2e suite
// both compile against.
//
// The identifiers Flutter renders as `flt-semantics-identifier` are the
// contract the browser-driven suite steers by. Written as literals in two
// places, that contract drifts silently: a renamed widget id fails a spec
// with "element not found" instead of "you renamed the contract". So one
// registry emits both sides: app/semantics-ids/, one JSON file per group,
// read in filename order. The filename is the group name, and a group file
// maps constant names to identifier strings:
//
//   { "doc": "...", "ids": { "auditRow": "audit-row-{id}" } }
//
// An id with `{name}` placeholders becomes a function in both languages,
// its parameters the placeholders in order of first appearance.
//
//   dart run tools/gen-semantics-ids.dart        (via `make generate`)
//
// Uses only dart: libraries, so it runs without a package resolution.
import 'dart:convert';
import 'dart:io';

const _dartOut = 'app/app/lib/src/shell/semantics_ids.dart';
const _tsOut = 'e2e/tests/semantics-ids.ts';
const _sourceDir = 'app/semantics-ids';
const _retired = 'app/semantics-ids.json';

final _placeholder = RegExp(r'\{([a-zA-Z0-9_]+)\}');

// Names that cannot be an identifier in the generated code: Dart's
// reserved words, `get`/`set` (ambiguous in member position), and the
// words the TS output cannot take as a parameter in module (strict)
// code. One merged set for constants and placeholders both; nothing
// here is a name anyone wants for a control anyway.
const _reserved = {
  'assert', 'await', 'break', 'case', 'catch', 'class', 'const',
  'continue', 'debugger', 'default', 'delete', 'do', 'else', 'enum',
  'export', 'extends', 'false', 'final', 'finally', 'for', 'function',
  'get', 'if', 'implements', 'import', 'in', 'instanceof', 'interface',
  'is', 'let', 'new', 'null', 'package', 'private', 'protected',
  'public', 'rethrow', 'return', 'set', 'static', 'super', 'switch',
  'this', 'throw', 'true', 'try', 'typeof', 'var', 'void', 'while',
  'with', 'yield', //
};

class _Group {
  _Group(this.name, this.doc, this.entries);

  final String name;
  final String doc;
  final List<_Entry> entries;
}

class _Entry {
  _Entry(this.name, this.id, this.params);

  final String name;
  final String id;
  final List<String> params;
}

Never _fail(String message) {
  stderr.writeln('gen-semantics-ids: $message');
  exit(1);
}

void main(List<String> args) {
  final root = Directory.current.path;
  final dir = Directory('$root/$_sourceDir');
  if (!dir.existsSync()) {
    stderr.writeln('gen-semantics-ids: run from the repository root');
    exit(2);
  }
  // The monolith the directory replaced. Entries added there would be
  // ignored here, so its reappearance fails loudly instead of quietly.
  if (File('$root/$_retired').existsSync()) {
    _fail(
      '$_retired is retired: fold its entries into '
      '$_sourceDir/<group>.json and delete it',
    );
  }

  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.uri.pathSegments.last.endsWith('.json'))
          .where((f) => !f.uri.pathSegments.last.startsWith('.'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) _fail('no group files in $_sourceDir/');

  final seen = <String, String>{};
  final groups = [for (final file in files) _readGroup(file, seen)];

  final dart = _dart(groups);
  final typescript = _typescript(groups);
  // Nothing may reach the output still shaped like a placeholder: an
  // interpolation that failed to substitute compiles fine and ships an
  // identifier no element carries, which the specs would report as a
  // missing element rather than as a generator fault.
  for (final output in <String>[dart, typescript]) {
    // A brace preceded by `$` is an interpolation that did substitute.
    final leftover = RegExp(r'(?<!\$)\{[a-zA-Z0-9_]+\}').firstMatch(output);
    if (leftover != null) {
      _fail('"${leftover.group(0)}" survived substitution');
    }
  }

  File('$root/$_dartOut').writeAsStringSync(dart);
  File('$root/$_tsOut').writeAsStringSync(typescript);
  stdout.writeln(
    'gen-semantics-ids: ${seen.length} identifiers -> $_dartOut, $_tsOut',
  );
}

/// Reads one group file. [seen] holds every constant name across groups,
/// because the generated registry is a single flat namespace.
_Group _readGroup(File file, Map<String, String> seen) {
  final base = file.uri.pathSegments.last;
  final where = '$_sourceDir/$base';
  final name = base.substring(0, base.length - '.json'.length);
  if (!RegExp(r'^[a-z][a-z0-9-]*$').hasMatch(name)) {
    _fail('$where: group files are named <lowercase-kebab>.json');
  }
  Object? decoded;
  try {
    decoded = _decodeStrict(file.readAsStringSync(), where);
  } on FormatException catch (e) {
    _fail('$where: ${e.message}');
  }
  if (decoded is! Map<String, dynamic>) {
    _fail('$where: expected {"doc": ..., "ids": {...}}');
  }
  final unknown = decoded.keys.where((k) => k != 'doc' && k != 'ids');
  if (unknown.isNotEmpty) {
    _fail(
      '$where: unknown key "${unknown.first}" (a group file is '
      '{"doc": ..., "ids": {...}})',
    );
  }
  final doc = decoded['doc'];
  if (doc is! String || doc.isEmpty) {
    _fail('$where: "doc" must say what the group covers');
  }
  // Interpolated into a single-line comment in both outputs, whole
  // outputs the leftover-placeholder guard then scans: a newline would
  // split the comment into bare code, and a braced word would read as a
  // placeholder that failed to substitute.
  if (!RegExp(r'^[ -~]+$').hasMatch(doc) || doc.contains(RegExp(r'[{}]'))) {
    _fail('$where: "doc" must be one line of printable ASCII, no braces');
  }
  final ids = decoded['ids'];
  if (ids is! Map<String, dynamic> || ids.isEmpty) {
    _fail('$where: "ids" must map constant names to identifier strings');
  }
  final entries = <_Entry>[];
  for (final MapEntry(key: constant, value: id) in ids.entries) {
    if (!RegExp(r'^[a-z][a-zA-Z0-9]*$').hasMatch(constant)) {
      _fail('$where: "$constant" is not a lowerCamelCase constant name');
    }
    if (_reserved.contains(constant)) {
      _fail('$where: "$constant" is a reserved word in Dart or TypeScript');
    }
    if (id is! String || id.isEmpty) {
      _fail('$where: "$constant" must map to an identifier string');
    }
    final previous = seen[constant];
    if (previous != null) {
      _fail('$where: "$constant" is declared twice ($previous and $id)');
    }
    seen[constant] = id;
    entries.add(_Entry(constant, id, _params(where, constant, id)));
  }
  return _Group(name, doc, entries);
}

/// jsonDecode, except a key an object declares twice is an error
/// instead of a silent last-one-wins, which here would drop a registry
/// entry without a trace.
Object? _decodeStrict(String source, String where) {
  final decoded = jsonDecode(source);
  final duplicated = _duplicateKeys(source);
  if (duplicated.isNotEmpty) {
    _fail('$where: duplicate key "${duplicated.join('", "')}"');
  }
  return decoded;
}

/// The keys declared more than once in a single object of [source],
/// which must already be well-formed JSON (jsonDecode vets it first).
///
/// Grammar-level: a string is a key exactly when its next token is a
/// colon, and each object on the stack tracks its own keys -- so a
/// duplicate is reported as itself, never as the keys inside a value
/// the collapse discarded.
List<String> _duplicateKeys(String source) {
  final stack = <Set<String>>[];
  final duplicated = <String>[];
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    if (c == '{') {
      stack.add(<String>{});
      i++;
    } else if (c == '}') {
      stack.removeLast();
      i++;
    } else if (c == '"') {
      i++;
      final start = i;
      while (source[i] != '"') {
        i += source[i] == r'\' ? 2 : 1;
      }
      final key = source.substring(start, i);
      i++;
      var j = i;
      while (j < source.length && ' \t\n\r'.contains(source[j])) {
        j++;
      }
      if (j < source.length && source[j] == ':') {
        if (!stack.last.add(key) && !duplicated.contains(key)) {
          duplicated.add(key);
        }
      }
    } else {
      i++;
    }
  }
  return duplicated;
}

/// A function entry's parameters: the placeholders in [id], in order of
/// first appearance. A brace the placeholder pattern does not consume is
/// a malformed placeholder, which would ship as literal text in an
/// identifier no element carries; outside the holes, ids keep to the
/// kebab alphabet, so nothing (quote, backslash, dollar) can break the
/// emitted literals either.
List<String> _params(String where, String constant, String id) {
  final params = <String>[];
  for (final match in _placeholder.allMatches(id)) {
    final param = match.group(1)!;
    if (!RegExp(r'^[a-z][a-zA-Z0-9]*$').hasMatch(param)) {
      _fail('$where: "$constant" placeholder {$param} is not lowerCamelCase');
    }
    if (_reserved.contains(param)) {
      _fail(
        '$where: "$constant" placeholder {$param} is a reserved word in '
        'Dart or TypeScript',
      );
    }
    if (!params.contains(param)) params.add(param);
  }
  final stripped = id.replaceAll(_placeholder, '');
  if (stripped.contains(RegExp(r'[{}]'))) {
    _fail('$where: "$constant" has a malformed placeholder in "$id"');
  }
  if (!RegExp(r'^[a-z0-9-]*$').hasMatch(stripped)) {
    _fail(
      '$where: "$constant" id "$id" may only use a-z, 0-9, "-", and '
      '{placeholder} holes',
    );
  }
  return params;
}

String _dart(List<_Group> groups) {
  final buffer = StringBuffer()
    ..writeln('// GENERATED by `make generate` from $_sourceDir/. Do not edit.')
    ..writeln('//')
    ..writeln('// The semantics identifiers this app exposes. Every')
    ..writeln('// `Semantics(identifier:)` in the client reads from here, and')
    ..writeln('// the e2e suite compiles against the same list in')
    ..writeln('// e2e/tests/semantics-ids.ts, so the two cannot drift.')
    ..writeln()
    ..writeln('/// Stable identifiers for the controls the e2e suite drives.')
    ..writeln('abstract final class SemanticsIds {');

  for (final group in groups) {
    buffer
      ..writeln()
      ..writeln('  // ${group.name}: ${group.doc}');
    for (final entry in group.entries) {
      if (entry.params.isEmpty) {
        buffer.writeln("  static const String ${entry.name} = '${entry.id}';");
      } else {
        final signature = entry.params.map((p) => 'Object $p').join(', ');
        buffer.writeln(
          "  static String ${entry.name}($signature) => '${_dartBody(entry.id)}';",
        );
      }
    }
  }

  buffer.writeln('}');
  return buffer.toString();
}

/// Interpolates the placeholders for Dart, bracing a name only where the
/// next character would otherwise be read as part of it.
///
/// The following character is inspected rather than matched, because a
/// pattern can put two placeholders side by side: consuming the character
/// after `{a}` in `{a}{b}` would eat the opening brace of `{b}` and leave
/// it in the output as literal text.
String _dartBody(String id) => id.replaceAllMapped(_placeholder, (m) {
  final next = m.end < id.length ? id[m.end] : '';
  final name = m.group(1);
  return RegExp(r'[A-Za-z0-9_]').hasMatch(next) ? '\${$name}' : '\$$name';
});

String _typescript(List<_Group> groups) {
  final buffer = StringBuffer()
    ..writeln('// GENERATED by `make generate` from $_sourceDir/. Do not edit.')
    ..writeln('//')
    ..writeln('// The semantics identifiers the app exposes as')
    ..writeln('// flt-semantics-identifier attributes. Import these rather')
    ..writeln('// than writing the strings: a rename then fails to compile')
    ..writeln('// here instead of failing as a missing element at runtime.')
    ..writeln()
    ..writeln('export const SemanticsIds = {');

  for (final group in groups) {
    buffer
      ..writeln()
      ..writeln('  // ${group.name}: ${group.doc}');
    for (final entry in group.entries) {
      if (entry.params.isEmpty) {
        buffer.writeln("  ${entry.name}: '${entry.id}',");
      } else {
        final signature = entry.params
            .map((p) => '$p: string | number')
            .join(', ');
        var body = entry.id;
        for (final param in entry.params) {
          body = body.replaceAll('{$param}', '\${$param}');
        }
        buffer.writeln('  ${entry.name}: ($signature) => `$body`,');
      }
    }
  }

  buffer
    ..writeln('} as const;')
    ..writeln()
    ..writeln('/// The fixed head of a parameterized identifier, for')
    ..writeln('/// matching a whole family at once: every share row, every')
    ..writeln('/// item, every queue entry. `SemanticsIds` builds one id')
    ..writeln('/// from its arguments and cannot answer "any of them", so')
    ..writeln('/// specs used to write the prefix out by hand - which is a')
    ..writeln('/// literal that survives a rename in silence, the one hole')
    ..writeln('/// left in the registry.')
    ..writeln('///')
    ..writeln('/// An id whose first character is a placeholder has no fixed')
    ..writeln('/// head and is absent here.')
    ..writeln('export const SemanticsIdPrefixes = {');
  for (final group in groups) {
    final prefixed = group.entries
        .where((e) => e.params.isNotEmpty)
        .where((e) => !e.id.startsWith('{'))
        .toList();
    if (prefixed.isEmpty) continue;
    buffer
      ..writeln()
      ..writeln('  // ${group.name}: ${group.doc}');
    for (final entry in prefixed) {
      final head = entry.id.substring(0, entry.id.indexOf('{'));
      buffer.writeln("  ${entry.name}: '$head',");
    }
  }
  buffer
    ..writeln('} as const;')
    ..writeln()
    ..writeln('/// The attribute Flutter renders an identifier into.')
    ..writeln('/// Named so that nothing has to spell it: a hand-typed')
    ..writeln('/// copy is what the conformance ratchet is looking for,')
    ..writeln('/// and reading the attribute off an element is a real')
    ..writeln('/// need that should not have to earn an exemption.')
    ..writeln(
      "export const SEMANTICS_ATTRIBUTE = 'flt-semantics-identifier';",
    )
    ..writeln()
    ..writeln('/// The attribute selector Flutter renders an identifier as.')
    ..writeln("export const sem = (id: string) =>")
    ..writeln('  `[\${SEMANTICS_ATTRIBUTE}="\${id}"]`;')
    ..writeln()
    ..writeln('/// The same selector, matching every identifier that starts')
    ..writeln('/// with [prefix] - a `SemanticsIdPrefixes` member.')
    ..writeln('export const semPrefix = (prefix: string) =>')
    ..writeln('  `[\${SEMANTICS_ATTRIBUTE}^="\${prefix}"]`;');
  return buffer.toString();
}
