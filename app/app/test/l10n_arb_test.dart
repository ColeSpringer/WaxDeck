import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The translation gate: what gen-l10n does not check and Weblate needs.
///
/// gen-l10n reads the template and fills a missing translation from it
/// silently, so a locale that quietly stopped keeping up still compiles
/// and still renders - in English, at whichever key was forgotten. The
/// checks here are the ones that fail instead:
///
/// - every locale carries exactly the template's keys, so es never
///   drifts behind en and never grows a key en does not have;
/// - every template key has a non-empty description, which is the only
///   context a translator gets;
/// - every placeholder a message interpolates is declared with a type,
///   and every translation interpolates the same set - a dropped
///   placeholder is a sentence with a hole in it;
/// - no message is blank, which passes every check above and compiles
///   to a getter that answers the empty string;
/// - keys stay sorted, which is what keeps a table navigable;
/// - the machine-drafted locale still carries the note saying so, so its
///   copy is never handed to a translator tool as finished work.
///
/// The app's table is authored as per-feature fragments in `l10n/`
/// (`<feature>/<locale>.arb`), which `make generate` merges into the
/// bundles gen-l10n reads. The checks above run per fragment, so a
/// failure names the file that takes the fix; on top of them, a key
/// must live in the longest directory name that prefixes it - placement
/// is a spelling question, not a judgment call - and the committed bundle
/// must be exactly the merge of the fragments, which is what makes a
/// bundler that mis-merged fail here instead of shipping. The design
/// system's table is small enough to stay one file per locale and keeps
/// the per-file checks only.
void main() {
  final features = _features();
  final appLocales = _appLocales(features);

  test('l10n/ holds feature directories and README.md only', () {
    expect(
      Directory(_fragmentRoot).existsSync(),
      isTrue,
      reason: '$_fragmentRoot: the fragment tree the app table is built from',
    );
    final strays = Directory(_fragmentRoot)
        .listSync()
        .where((e) => e is! Directory)
        .map((e) => e.path.replaceAll('\\', '/').split('/').last)
        .where((n) => n != 'README.md' && !n.startsWith('.'))
        .toList();
    expect(strays, isEmpty, reason: 'not a feature directory: $strays');
    final misnamed = features.where((f) => !_dirName.hasMatch(f)).toList();
    expect(
      misnamed,
      isEmpty,
      reason: 'a feature directory is a key prefix, lower case: $misnamed',
    );
    expect(
      appLocales,
      contains('en'),
      reason: 'the template locale; extraction is from English source',
    );
  });

  for (final feature in features) {
    group('app l10n/$feature', () {
      final dir = '$_fragmentRoot/$feature';

      test('carries exactly the app locales', () {
        final found = Directory(dir)
            .listSync()
            .map((e) => e.path.replaceAll('\\', '/').split('/').last)
            .where((n) => !n.startsWith('.'))
            .toList();
        expect(
          found.toSet(),
          appLocales.map((l) => '$l.arb').toSet(),
          reason: '$dir: one fragment per locale, nothing else',
        );
      });

      _checkTable(
        read: (locale) => _Arb.parse(File('$dir/$locale.arb')),
        fileFor: (locale) => '$dir/$locale.arb',
        locales: appLocales,
      );

      test('keys carry the directory\'s prefix', () {
        final misplaced = <String>[];
        for (final locale in appLocales) {
          final arb = _Arb.parse(File('$dir/$locale.arb'));
          for (final key in arb.keys) {
            final home = _dirFor(key, features);
            if (home != feature) {
              misplaced.add(
                '$dir/$locale.arb: $key belongs in '
                '${home ?? '<a new directory>'}/',
              );
            }
          }
        }
        expect(misplaced, isEmpty, reason: misplaced.join('\n'));
      });

      test('globals are the locale stamp and x- notes', () {
        for (final locale in appLocales) {
          final globals = _Arb.parse(File('$dir/$locale.arb')).globals;
          expect(
            globals['@@locale'],
            locale,
            reason: '$dir/$locale.arb: @@locale names the file\'s locale',
          );
          _expectDraftMarker(globals, locale, '$dir/$locale.arb');
          // The ARB Editor extension otherwise checks a fragment against
          // l10n.yaml's whole-app template; this scopes it to the
          // directory (and, self-referenced from en.arb, to nothing).
          expect(
            globals['@@x-template'],
            'en.arb',
            reason:
                '$dir/$locale.arb: @@x-template points the editor at the '
                'directory\'s own template',
          );
          final foreign = globals.keys
              .where((g) => g != '@@locale' && !g.startsWith('@@x-'))
              .toList();
          expect(
            foreign,
            isEmpty,
            reason:
                '$dir/$locale.arb: a fragment carries @@locale and @@x- '
                'notes only: $foreign',
          );
        }
      });
    });
  }

  test('x- notes read the same in every fragment of a locale', () {
    // A note like @@x-machine-translated is about the locale, so one
    // fragment hand-reviewed (or annotated) out of step with the rest
    // would misstate the whole merged table. @@x-template is per-file
    // and exempt. The bundler enforces this at generate time; this is
    // what fails on a tree that has not been through it yet.
    for (final locale in appLocales) {
      Map<String, Object?>? first;
      String? firstWhere;
      for (final feature in features) {
        final where = '$_fragmentRoot/$feature/$locale.arb';
        final notes = Map.of(_Arb.parse(File(where)).globals)
          ..remove('@@locale')
          ..remove('@@x-template');
        if (first == null) {
          first = notes;
          firstWhere = where;
          continue;
        }
        expect(
          _Arb._same(notes, first),
          isTrue,
          reason: '$where: @@x- notes disagree with $firstWhere',
        );
      }
    }
  });

  group('app bundle', () {
    test('one bundle per fragment locale', () {
      // A retired locale must take its bundle with it: an untouched
      // committed app_<locale>.arb is invisible to the drift gate, and
      // gen-l10n would keep compiling the locale from it.
      final found = _localesOf('lib/src/l10n/arb', prefix: 'app_');
      expect(
        found.toSet(),
        appLocales.toSet(),
        reason: 'lib/src/l10n/arb holds a bundle per l10n/ locale',
      );
    });

    for (final locale in appLocales) {
      test('$locale is the merge of the fragments', () {
        final bundle = _Arb.parse(File('lib/src/l10n/arb/app_$locale.arb'));
        expect(
          bundle.keys,
          orderedEquals(bundle.keys.toList()..sort()),
          reason: 'app_$locale.arb: the bundler emits sorted keys',
        );
        final merged = _Arb.merge(
          features.map(
            (f) => _Arb.parse(File('$_fragmentRoot/$f/$locale.arb')),
          ),
        );
        final diff = bundle.diff(merged);
        expect(
          diff,
          isEmpty,
          reason:
              'app_$locale.arb is generated from l10n/*/$locale.arb by '
              '`make generate`; it disagrees:\n${diff.join('\n')}',
        );
      });
    }
  });

  group('waxdeck_ui ARB', () {
    const dir = '../packages/waxdeck_ui/lib/src/l10n/arb';
    final locales = _localesOf(dir, prefix: 'wax_');

    test('carries its table', () {
      // Derived from the directory, so a wax_<locale>.arb the app does
      // not have yet still gets checked - and a moved package fails
      // here by name instead of passing every check against nothing.
      expect(
        locales,
        contains('en'),
        reason:
            '$dir: the design system\'s template; if the package moved, '
            'move this path with it',
      );
    });

    test('globals name the locale and how it was drafted', () {
      for (final locale in locales) {
        final where = '$dir/wax_$locale.arb';
        final globals = _Arb.parse(File(where)).globals;
        expect(
          globals['@@locale'],
          locale,
          reason: '$where: @@locale names the file\'s locale',
        );
        _expectDraftMarker(globals, locale, where);
      }
    });

    _checkTable(
      read: (locale) => _Arb.parse(File('$dir/wax_$locale.arb')),
      fileFor: (locale) => '$dir/wax_$locale.arb',
      locales: locales,
    );
  });

  // ICU nests, so the placeholder reader walks the grammar; these pin
  // the shapes the tables use.
  group('placeholder reading', () {
    Set<String> of(String message) =>
        _Arb.parseString('{"k": ${jsonEncode(message)}}').placeholders('k');

    test('takes a plain interpolation', () {
      expect(of('Playing on {endpoint}'), {'endpoint'});
      expect(of('{hours} hr {minutes} min'), {'hours', 'minutes'});
      expect(of('Nothing to fill'), isEmpty);
    });

    test('takes the plural argument and not its branches', () {
      expect(
        of('{count, plural, =1{Cleared 1 task} other{Cleared {count} tasks}}'),
        {'count'},
      );
      expect(of('{n, plural, other {Albums}}'), {'n'});
    });

    test('takes a select argument and not its cases', () {
      expect(of('{kind, select, album{Album} other{Item}}'), {'kind'});
    });

    test('takes a placeholder nested inside a branch', () {
      expect(of('{count, plural, other{{count} of {total}}}'), {
        'count',
        'total',
      });
      // A case name is an identifier and so is an English word, which
      // is why this is parsed rather than pattern-matched.
      expect(of('{n, plural, other{Hola {name}}}'), {'n', 'name'});
    });
  });
}

/// Paths are relative to `app/app`, which is where this test runs.
const _fragmentRoot = 'l10n';

final _dirName = RegExp(r'^[a-z0-9]+$');

/// The locale whose copy was drafted by machine alongside extraction and
/// has not been read by a native speaker yet, and the note that says so.
const _machineDrafted = 'es';
const _draftMarker = '@@x-machine-translated';

/// On every fragment of the drafted locale and on none of the template's.
/// A translator tool reads the note as "needs review", so a file that lost
/// it would be offered as finished work. It comes off when somebody has
/// read the locale, and that person edits this test in the same change.
void _expectDraftMarker(
  Map<String, Object?> globals,
  String locale,
  String where,
) {
  if (locale == _machineDrafted) {
    expect(
      globals[_draftMarker],
      isA<String>().having((s) => s.trim(), 'note', isNotEmpty),
      reason:
          '$where: $locale is machine-drafted, so every fragment carries '
          '$_draftMarker saying so; taking it off is a review decision, '
          'and _machineDrafted in this test moves with it',
    );
    return;
  }
  expect(
    globals.containsKey(_draftMarker),
    isFalse,
    reason:
        '$where: $locale is not drafted copy; $_draftMarker is not its note',
  );
}

/// The `<prefix><locale>.arb` stems a directory holds, sorted. Empty
/// when the directory is missing, which the callers turn into a named
/// failure rather than a silent one.
List<String> _localesOf(String dir, {String prefix = ''}) {
  final d = Directory(dir);
  if (!d.existsSync()) return const [];
  return d
      .listSync()
      .whereType<File>()
      .map((f) => f.path.replaceAll('\\', '/').split('/').last)
      .where((n) => !n.startsWith('.') && n.endsWith('.arb'))
      .where((n) => n.startsWith(prefix))
      .map((n) => n.substring(prefix.length, n.length - '.arb'.length))
      .toList()
    ..sort();
}

/// The app's locales, derived from the fragment tree itself so there is
/// no second list to keep in step: the union of every feature's stems.
/// A directory out of step with the union fails its own locales test.
/// The locale the others are checked against is en everywhere, because
/// extraction is from English source.
List<String> _appLocales(List<String> features) {
  final union = <String>{};
  for (final feature in features) {
    union.addAll(_localesOf('$_fragmentRoot/$feature'));
  }
  return union.toList()..sort();
}

/// The feature a key files under: the longest declared directory name
/// that prefixes it. `booksTitle` lives in `book/` unless a `books/`
/// directory exists to claim it, so a list screen's keys shelve with
/// their medium without renaming either. Null when no directory
/// matches, which is what a new prefix looks like.
/// tools/gen-l10n-bundle.dart applies the same reading.
String? _dirFor(String key, List<String> features) {
  String? home;
  for (final feature in features) {
    if (key.startsWith(feature) && feature.length > (home?.length ?? 0)) {
      home = feature;
    }
  }
  return home;
}

List<String> _features() {
  final root = Directory(_fragmentRoot);
  if (!root.existsSync()) return const [];
  return root
      .listSync()
      .whereType<Directory>()
      .map((d) => d.path.replaceAll('\\', '/').split('/').last)
      .where((n) => !n.startsWith('.'))
      .toList()
    ..sort();
}

/// The per-table checks: content quality, run against whichever files a
/// table is authored in - a fragment directory or a single-file bundle.
void _checkTable({
  required _Arb Function(String locale) read,
  required String Function(String locale) fileFor,
  required List<String> locales,
}) {
  // Every read happens inside a test body, so a missing or malformed
  // file fails that test with its path instead of aborting the whole
  // file's load with zero tests registered.
  test('every key is described and its placeholders typed', () {
    final template = read('en');
    final missing = <String>[];
    for (final key in template.keys) {
      final meta = template.meta[key];
      final description = meta?['description'];
      if (description is! String || description.trim().isEmpty) {
        missing.add('$key: no @$key description');
        continue;
      }
      final declared =
          (meta?['placeholders'] as Map?)?.cast<String, Object?>() ?? const {};
      for (final name in template.placeholders(key)) {
        final spec = declared[name];
        if (spec is! Map || spec['type'] is! String) {
          missing.add('$key: placeholder {$name} needs a type in @$key');
        }
      }
    }
    expect(missing, isEmpty, reason: missing.join('\n'));
  });

  test('keys are sorted', () {
    for (final locale in locales) {
      final keys = read(locale).keys;
      expect(
        keys,
        orderedEquals(keys.toList()..sort()),
        reason:
            '${fileFor(locale)}: keys are read in alphabetical order; '
            'sort them',
      );
    }
  });

  test('no message is blank', () {
    // An empty value satisfies every other check here and compiles
    // to `String get x => ''`, so the only thing that ever reports
    // it is the button that draws nothing.
    final blank = <String>[];
    for (final locale in locales) {
      final arb = read(locale);
      for (final key in arb.keys) {
        if (arb.value(key).trim().isEmpty) {
          blank.add('${fileFor(locale)}: $key is empty');
        }
      }
    }
    expect(blank, isEmpty, reason: blank.join('\n'));
  });

  for (final locale in locales.where((l) => l != 'en')) {
    test('$locale matches the template', () {
      final template = read('en');
      final translation = read(locale);
      expect(
        translation.keys.toSet(),
        template.keys.toSet(),
        reason:
            '${fileFor(locale)}: a translation lands with the key '
            'that mints it, so the two files always hold the same set',
      );
      final holes = <String>[];
      for (final key in translation.keys) {
        if (!template.keys.contains(key)) continue;
        final want = template.placeholders(key);
        final got = translation.placeholders(key);
        if (!setEquals(want, got)) {
          holes.add('$key: template takes $want, $locale takes $got');
        }
      }
      expect(holes, isEmpty, reason: holes.join('\n'));
    });
  }
}

/// An ARB file split into its messages, their `@` metadata, and the
/// file-level `@@` globals.
class _Arb {
  _Arb(this.keys, this.meta, this.globals);

  // A missing file throws with its path: parsing an empty table in its
  // place would let every downstream check pass against nothing.
  factory _Arb.parse(File file) => _Arb.parseString(file.readAsStringSync());

  factory _Arb.parseString(String source) {
    final json = jsonDecode(source) as Map<String, Object?>;
    final keys = <String>[];
    final meta = <String, Map<String, Object?>>{};
    final values = <String, String>{};
    final globals = <String, Object?>{};
    for (final entry in json.entries) {
      if (entry.key.startsWith('@@')) {
        globals[entry.key] = entry.value;
        continue;
      }
      if (entry.key.startsWith('@')) {
        meta[entry.key.substring(1)] = (entry.value as Map).cast();
        continue;
      }
      keys.add(entry.key);
      values[entry.key] = entry.value as String;
    }
    return _Arb(keys, meta, globals).._values.addAll(values);
  }

  /// The union a bundle is expected to hold. Collisions are impossible
  /// in checked fragments - a key spells its one directory - so this
  /// merges without looking for them. `@@x-template` stays behind: it
  /// aims an editor at the fragment's own template file, which is a
  /// fact about the fragment, not about the locale.
  factory _Arb.merge(Iterable<_Arb> parts) {
    final merged = _Arb([], {}, {});
    for (final part in parts) {
      merged.keys.addAll(part.keys);
      merged.meta.addAll(part.meta);
      merged.globals.addAll(
        Map.fromEntries(
          part.globals.entries.where((g) => g.key != '@@x-template'),
        ),
      );
      merged._values.addAll(part._values);
    }
    merged.keys.sort();
    return merged;
  }

  final List<String> keys;
  final Map<String, Map<String, Object?>> meta;
  final Map<String, Object?> globals;
  final _values = <String, String>{};

  /// The message a key holds.
  String value(String key) => _values[key] ?? '';

  /// Where this table disagrees with [other], one line each.
  List<String> diff(_Arb other) {
    final lines = <String>[];
    for (final key in {...keys, ...other.keys}) {
      if (!other.keys.contains(key)) {
        lines.add('$key: only in the bundle');
      } else if (!keys.contains(key)) {
        lines.add('$key: only in the fragments');
      } else if (value(key) != other.value(key)) {
        lines.add('$key: messages differ');
      } else if (!_same(meta[key], other.meta[key])) {
        lines.add('$key: @$key metadata differs');
      }
    }
    if (!_same(globals, other.globals)) {
      lines.add('@@ globals differ: $globals vs ${other.globals}');
    }
    return lines;
  }

  static bool _same(Object? a, Object? b) {
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

  /// The placeholder names a message interpolates, at every depth.
  ///
  /// Read out of the message rather than out of its metadata, because
  /// the metadata is what a translation does not carry: this is the
  /// check that a translator kept the hole the sentence needs.
  ///
  /// ICU nests, so a brace is not always a placeholder. In
  /// `{count, plural, =1{Album} other{Albums}}` only the first one is,
  /// and reading `Album` as a name would demand a declared type for it
  /// and then compare it against the Spanish branch. A pattern cannot
  /// tell them apart - a select case is an arbitrary identifier, so
  /// `other{Hola {name}}` and `{count, select, other{...}}` put an
  /// identifier before a brace for opposite reasons - so this walks the
  /// grammar.
  Set<String> placeholders(String key) {
    final found = <String>{};
    _readMessage(value(key), 0, found);
    return found;
  }

  /// Message text from [i] to the brace that closes the branch holding
  /// it, or to the end. Answers the index it stopped at.
  static int _readMessage(String s, int i, Set<String> found) {
    while (i < s.length && s[i] != '}') {
      i = s[i] == '{' ? _readArgument(s, i, found) : i + 1;
    }
    return i;
  }

  /// `{name}` or `{name, type, case{message} ...}` at the brace [i].
  /// Answers the index just past its closing brace.
  static int _readArgument(String s, int i, Set<String> found) {
    var j = _skipSpace(s, i + 1);
    final name = _word.matchAsPrefix(s, j);
    // Not an argument at all. Nothing here writes a bare brace into
    // copy (the convention is to reword rather than escape), so this is
    // a malformed message; gen-l10n is what reports it.
    if (name == null) return i + 1;
    found.add(name.group(0)!);
    j = _skipSpace(s, name.end);
    if (j < s.length && s[j] == '}') return j + 1;
    if (j >= s.length || s[j] != ',') return j;
    final type = _word.matchAsPrefix(s, _skipSpace(s, j + 1));
    if (type == null) return j;
    j = _skipSpace(s, type.end);
    if (j < s.length && s[j] == ',') j = _skipSpace(s, j + 1);
    while (j < s.length && s[j] != '}') {
      final selector = _selector.matchAsPrefix(s, j);
      if (selector == null) return j;
      j = _skipSpace(s, selector.end);
      if (j >= s.length || s[j] != '{') return j;
      j = _readMessage(s, j + 1, found);
      if (j < s.length && s[j] == '}') j++;
      j = _skipSpace(s, j);
    }
    return j < s.length ? j + 1 : j;
  }

  static int _skipSpace(String s, int i) {
    while (i < s.length && s[i].trim().isEmpty) {
      i++;
    }
    return i;
  }

  static final _word = RegExp(r'\w+');

  /// A plural's `=1`/`other` or a select's own case name.
  static final _selector = RegExp(r'=?\w+');
}
