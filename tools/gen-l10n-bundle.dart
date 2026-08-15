// Merges the app's per-feature ARB fragments into the per-locale
// bundles gen-l10n reads.
//
// gen-l10n takes exactly one ARB file per locale, and at a couple of
// thousand keys that file is unworkable to author in. So the app's
// table is written as fragments in app/app/l10n/ - one directory per
// key prefix, one file per locale:
//
//   l10n/player/en.arb   l10n/player/es.arb
//
// and this merges them into app/app/lib/src/l10n/arb/app_<locale>.arb,
// committed and drift-checked like the OpenAPI bundle. A fragment
// carries `@@locale`, optional `@@x-` notes (carried through, and they
// must read the same in every fragment of a locale), and messages that
// live in the longest directory name prefixing them - a key spells the
// one place it can live. app/app/test/l10n_arb_test.dart holds the
// content checks; what fails here is what would make the merge wrong
// or lossy.
//
// Nothing is written until every locale has validated, and each bundle
// then goes temp-in-target-dir -> flush -> rename, untouched when
// already up to date - the same discipline as cmd/specbundle. A bundle
// whose locale no longer has fragments is deleted, so a retired locale
// cannot ship on a stale committed file.
//
//   dart run tools/gen-l10n-bundle.dart        (via `make generate`)
//
// Uses only dart: libraries, so it runs without a package resolution.
import 'dart:convert';
import 'dart:io';

const _sourceDir = 'app/app/l10n';
const _outDir = 'app/app/lib/src/l10n/arb';

final _feature = RegExp(r'^[a-z0-9]+$');
final _locale = RegExp(r'^[a-z]{2,3}(_[A-Za-z0-9]+)*$');

Never _fail(String message) {
  stderr.writeln('gen-l10n-bundle: $message');
  exit(1);
}

/// The directory a key files under: the longest declared directory
/// name that prefixes it. `booksTitle` lives in `book/` unless a
/// `books/` directory exists to claim it, so a list screen's keys
/// shelve with their medium without renaming either. Null when no
/// directory matches. l10n_arb_test.dart applies the same reading.
String? _dirFor(String key, List<String> features) {
  String? home;
  for (final feature in features) {
    if (key.startsWith(feature) && feature.length > (home?.length ?? 0)) {
      home = feature;
    }
  }
  return home;
}

void main(List<String> args) {
  final source = Directory(_sourceDir);
  if (!source.existsSync()) {
    stderr.writeln('gen-l10n-bundle: run from the repository root');
    exit(2);
  }

  final features = <String>[];
  for (final entry in source.listSync()) {
    final base = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
    // The OS's droppings (.DS_Store and friends), same as the
    // semantics-id generator.
    if (base.startsWith('.')) continue;
    if (entry is! Directory) {
      if (base != 'README.md') {
        _fail('$_sourceDir/$base: fragments live in <feature>/<locale>.arb');
      }
      continue;
    }
    if (!_feature.hasMatch(base)) {
      _fail('$_sourceDir/$base: a feature directory is a key prefix');
    }
    features.add(base);
  }
  features.sort();
  if (features.isEmpty) _fail('no fragment directories in $_sourceDir/');

  final locales = _locales(features.first);
  for (final feature in features.skip(1)) {
    final found = _locales(feature);
    if (!_sameList(found, locales)) {
      _fail(
        '$_sourceDir/$feature carries [${found.join(', ')}], '
        '$_sourceDir/${features.first} carries [${locales.join(', ')}]: '
        'every feature carries every locale',
      );
    }
  }

  // Every locale validates before anything is written, so a bad es
  // fragment cannot leave a fresh en bundle beside a stale es one.
  final bundles = <String, String>{};
  final counts = <String, int>{};
  for (final locale in locales) {
    final values = <String, String>{};
    final meta = <String, Object?>{};
    Map<String, Object?>? notes;
    String? notesWhere;
    for (final feature in features) {
      final where = '$_sourceDir/$feature/$locale.arb';
      final decoded = _decodeStrict(File(where).readAsStringSync(), where);
      if (decoded is! Map<String, dynamic>) {
        _fail('$where: an ARB file is a JSON object');
      }
      final fileKeys = <String>{};
      final fileMeta = <String>[];
      final fileNotes = <String, Object?>{};
      for (final MapEntry(:key, :value) in decoded.entries) {
        if (key == '@@locale') {
          if (value != locale) {
            _fail(
              '$where: @@locale says "$value"; the filename says the '
              'locale, and they must agree',
            );
          }
          continue;
        }
        if (key.startsWith('@@')) {
          if (!key.startsWith('@@x-')) {
            _fail(
              '$where: a fragment carries @@locale and @@x- notes '
              'only, not "$key"',
            );
          }
          // Aims an editor at the fragment's own template file - a fact
          // about the fragment, not the locale, so it stays behind.
          if (key == '@@x-template') continue;
          fileNotes[key] = value;
          continue;
        }
        if (key.startsWith('@')) {
          fileMeta.add(key.substring(1));
          meta[key.substring(1)] = value;
          continue;
        }
        if (value is! String) {
          _fail('$where: "$key" must hold a message string');
        }
        final home = _dirFor(key, features);
        if (home == null) {
          _fail(
            '$where: no directory\'s name prefixes "$key"; a new prefix '
            'is a new directory under $_sourceDir/',
          );
        }
        if (home != feature) {
          _fail('$where: "$key" belongs in $_sourceDir/$home/');
        }
        // The prefix rule already gives every key one home; this is the
        // backstop that keeps a bundler bug from quietly last-one-wins.
        if (values.containsKey(key)) {
          _fail('$where: "$key" is already declared');
        }
        fileKeys.add(key);
        values[key] = value;
      }
      for (final base in fileMeta) {
        if (!fileKeys.contains(base)) {
          _fail('$where: @$base has no "$base" in the same fragment');
        }
      }
      // A note is about the locale, so it reads the same in every
      // fragment - or in none. Anything else means one fragment was
      // reviewed or annotated and the merged table would misstate the
      // other thirty-seven.
      if (notes == null) {
        notes = fileNotes;
        notesWhere = where;
      } else if (!_same(notes, fileNotes)) {
        _fail(
          '$where: @@x- notes disagree with $notesWhere; a locale-wide '
          'note reads the same in every fragment (or in none)',
        );
      }
    }

    final sortedKeys = values.keys.toList()..sort();
    final bundle = <String, Object?>{
      '@@locale': locale,
      for (final note in (notes ?? {}).keys.toList()..sort())
        note: notes![note],
      for (final key in sortedKeys) ...{
        key: values[key],
        if (meta.containsKey(key)) '@$key': meta[key],
      },
    };
    bundles['app_$locale.arb'] =
        '${const JsonEncoder.withIndent('  ').convert(bundle)}\n';
    counts[locale] = sortedKeys.length;
  }

  // A locale whose fragments are gone must take its bundle with it:
  // an untouched committed file is invisible to the drift gate, and
  // gen-l10n would keep compiling the locale from it.
  for (final entry in Directory(_outDir).listSync()) {
    final base = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (entry is! File || base.startsWith('.') || !base.endsWith('.arb')) {
      continue;
    }
    if (!bundles.containsKey(base)) {
      entry.deleteSync();
      stdout.writeln('gen-l10n-bundle: pruned $_outDir/$base (no fragments)');
    }
  }
  bundles.forEach(
    (name, content) => _writeIfChanged('$_outDir/$name', content),
  );

  final sizes = counts.values.toSet();
  final keySummary = sizes.length == 1
      ? '${sizes.first} keys'
      : counts.entries.map((e) => '${e.value} ${e.key}').join(', ');
  stdout.writeln(
    'gen-l10n-bundle: $keySummary, ${features.length} features, '
    '${locales.length} locales -> $_outDir',
  );
}

/// Replaces [out] atomically (temp in target dir, flush, rename) and
/// leaves an up-to-date file untouched, like cmd/specbundle.
void _writeIfChanged(String out, String content) {
  final file = File(out);
  if (file.existsSync() && file.readAsStringSync() == content) return;
  final tmp = File('$_outDir/.gen-l10n-$pid.tmp');
  try {
    final raf = tmp.openSync(mode: FileMode.write);
    raf.writeStringSync(content);
    raf.flushSync();
    raf.closeSync();
    tmp.renameSync(out);
  } finally {
    if (tmp.existsSync()) tmp.deleteSync();
  }
}

/// The locales a feature directory carries, from its filenames.
List<String> _locales(String feature) {
  final locales = <String>[];
  for (final entry in Directory('$_sourceDir/$feature').listSync()) {
    final base = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (base.startsWith('.')) continue;
    if (entry is! File || !base.endsWith('.arb')) {
      _fail(
        '$_sourceDir/$feature/$base: a feature directory holds '
        '<locale>.arb files only',
      );
    }
    final locale = base.substring(0, base.length - '.arb'.length);
    if (!_locale.hasMatch(locale)) {
      _fail('$_sourceDir/$feature/$base: not a locale name');
    }
    locales.add(locale);
  }
  locales.sort();
  if (locales.isEmpty) _fail('$_sourceDir/$feature/ is empty');
  return locales;
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Structural equality for decoded JSON, because `!=` on a Map or List
/// is identity and two byte-identical notes would read as disagreeing.
bool _same(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k]));
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_same(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// jsonDecode, except a key an object declares twice is an error
/// instead of a silent last-one-wins, which here would drop a message
/// or its metadata without a trace.
Object? _decodeStrict(String source, String where) {
  Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (e) {
    _fail('$where: ${e.message}');
  }
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
