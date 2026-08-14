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
/// - keys stay sorted, which is what keeps a 1,300-key file navigable
///   across a sweep landing in six slices.
void main() {
  for (final bundle in _bundles) {
    group('${bundle.name} ARB', () {
      final template = bundle.read(bundle.templateLocale);

      test('every key is described and its placeholders typed', () {
        final missing = <String>[];
        for (final key in template.keys) {
          final meta = template.meta[key];
          final description = meta?['description'];
          if (description is! String || description.trim().isEmpty) {
            missing.add('$key: no @$key description');
            continue;
          }
          final declared =
              (meta?['placeholders'] as Map?)?.cast<String, Object?>() ??
              const {};
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
        for (final locale in bundle.locales) {
          final keys = bundle.read(locale).keys;
          expect(
            keys,
            orderedEquals(keys.toList()..sort()),
            reason:
                '${bundle.fileFor(locale)}: keys are read in prefix-then-'
                'alphabetical blocks; sort them',
          );
        }
      });

      test('no message is blank', () {
        // An empty value satisfies every other check here and compiles
        // to `String get x => ''`, so the only thing that ever reports
        // it is the button that draws nothing.
        final blank = <String>[];
        for (final locale in bundle.locales) {
          final arb = bundle.read(locale);
          for (final key in arb.keys) {
            if (arb.value(key).trim().isEmpty) {
              blank.add('${bundle.fileFor(locale)}: $key is empty');
            }
          }
        }
        expect(blank, isEmpty, reason: blank.join('\n'));
      });

      for (final locale in bundle.locales.where(
        (l) => l != bundle.templateLocale,
      )) {
        test('$locale matches the template', () {
          final translation = bundle.read(locale);
          expect(
            translation.keys.toSet(),
            template.keys.toSet(),
            reason:
                '${bundle.fileFor(locale)}: a translation lands with the key '
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
    });
  }

  // The seeded ARBs are brace-free, so nothing above reads an ICU
  // message until the sweep lands its first plural.
  group('placeholder reading', () {
    Set<String> of(String message) =>
        _Arb.parse('{"k": ${jsonEncode(message)}}').placeholders('k');

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

/// One package's ARB directory.
class _Bundle {
  const _Bundle({
    required this.name,
    required this.dir,
    required this.prefix,
    required this.locales,
  });

  final String name;
  final String dir;
  final String prefix;
  final List<String> locales;

  /// The locale the others are checked against; en everywhere, because
  /// extraction is from English source.
  String get templateLocale => 'en';

  String fileFor(String locale) => '$dir/${prefix}_$locale.arb';

  _Arb read(String locale) =>
      _Arb.parse(File(fileFor(locale)).readAsStringSync());
}

/// Paths are relative to `app/app`, which is where this test runs.
const _bundles = <_Bundle>[
  _Bundle(
    name: 'app',
    dir: 'lib/src/l10n/arb',
    prefix: 'app',
    locales: <String>['en', 'es'],
  ),
  // The design system keeps a table of its own, for the copy no caller
  // can pass in. Checked from here rather than from that package,
  // because these are the checks and there is one of them.
  _Bundle(
    name: 'waxdeck_ui',
    dir: '../packages/waxdeck_ui/lib/src/l10n/arb',
    prefix: 'wax',
    locales: <String>['en', 'es'],
  ),
];

/// An ARB file split into its messages and their `@` metadata.
class _Arb {
  _Arb(this.keys, this.meta);

  factory _Arb.parse(String source) {
    final json = jsonDecode(source) as Map<String, Object?>;
    final keys = <String>[];
    final meta = <String, Map<String, Object?>>{};
    final values = <String, String>{};
    for (final entry in json.entries) {
      // `@@locale` and friends describe the file, not a message.
      if (entry.key.startsWith('@@')) continue;
      if (entry.key.startsWith('@')) {
        meta[entry.key.substring(1)] = (entry.value as Map).cast();
        continue;
      }
      keys.add(entry.key);
      values[entry.key] = entry.value as String;
    }
    return _Arb(keys, meta).._values.addAll(values);
  }

  final List<String> keys;
  final Map<String, Map<String, Object?>> meta;
  final _values = <String, String>{};

  /// The message a key holds.
  String value(String key) => _values[key] ?? '';

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
