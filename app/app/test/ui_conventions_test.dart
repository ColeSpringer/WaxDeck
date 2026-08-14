import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The conventions a compiler cannot see, as a ratchet.
///
/// The app's screens are supposed to reach for `waxdeck_ui` - its rows,
/// its glyphs, its spacing ladder, its type - rather than for Material's
/// primitives, and to look their copy up rather than type it. Most of
/// that is habit, and habits regress silently: a screen written in a
/// hurry grows a `SwitchListTile` beside nine `WaxSettingRow`s and
/// nothing says so.
///
/// So it is counted, per file, against a committed allowlist that may
/// only ever shrink. A count over its allowance fails with the
/// convention to reach for instead; a count under it fails just as
/// loudly with "lower it", which is what stops a conversion from
/// stalling half-done. A file with no entry has no tolerance at all -
/// that is the half that holds new code to the conventions from its
/// first line - and an entry naming a file that no longer exists fails
/// too, so a rename cannot carry a stale floor along with it.
///
/// Re-seed after adding a rule:
///
///     WAXDECK_UI_CONVENTIONS=write flutter test test/ui_conventions_test.dart
void main() {
  group('ui conventions', () {
    test('the allowlist only ever shrinks', () {
      final counts = <String, Map<String, int>>{};
      final findings = <String, List<_Finding>>{};

      for (final file in _sources()) {
        final path = file.path.split(Platform.pathSeparator).join('/');
        if (_isGenerated(path)) continue;
        final source = file.readAsStringSync();
        final lines = source.split('\n');
        final code = _code(source);
        for (final rule in _rules) {
          if (!rule.appliesTo(path)) continue;
          for (final hit in rule.find(code)) {
            // Offsets survive the blanking - a comment becomes spaces of
            // the same width - so the line is the file's own.
            final line = '\n'.allMatches(code.substring(0, hit.at)).length + 1;
            counts.putIfAbsent(path, () => <String, int>{});
            counts[path]![rule.name] = (counts[path]![rule.name] ?? 0) + 1;
            findings
                .putIfAbsent(path, () => <_Finding>[])
                .add(_Finding(rule, line, lines[line - 1].trim(), hit));
          }
        }
      }

      final allowlistFile = File('test/ui_conventions_allowlist.json');
      if (Platform.environment['WAXDECK_UI_CONVENTIONS'] == 'write') {
        allowlistFile.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(_sorted(counts))}\n',
        );
        return;
      }

      final allowed = (jsonDecode(allowlistFile.readAsStringSync()) as Map).map(
        (file, rules) => MapEntry(
          file as String,
          (rules as Map).map(
            (rule, count) => MapEntry(rule as String, count as int),
          ),
        ),
      );

      final failures = <String>[];
      for (final file in <String>{
        ...allowed.keys,
        ...counts.keys,
      }.toList()..sort()) {
        if (!counts.containsKey(file) && !File(file).existsSync()) {
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
            final over = findings[file]!.where((f) => f.rule.name == rule);
            failures.add(
              '$file: $rule x$actual, allowed $budget\n'
              '${over.map((f) => f.describe(file)).join('\n')}',
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

      expect(
        failures,
        isEmpty,
        reason:
            'The allowlist in test/ui_conventions_allowlist.json only ever '
            'shrinks; re-seed it with WAXDECK_UI_CONVENTIONS=write only when '
            'adding a rule.\n\n${failures.join('\n\n')}',
      );
    });
  });

  // What the copy rule reads, pinned directly. Its counts are a sweep's
  // done-signal, and a rule that quietly stops seeing a shape reports
  // zero for a file still full of English.
  group('the copy rule', () {
    List<String> found(String code) =>
        _CopyRule().find(code).map((h) => h.hint).toList();

    test('reads past a ternary, a fallback, an arrow, and a switch', () {
      expect(found("label: on ? 'Shuffle on' : 'Shuffle off',"), hasLength(2));
      expect(found("title: item?.name ?? 'Loading',"), hasLength(1));
      expect(
        found("label: switch (r) { A() => 'Repeat all', B() => 'One' },"),
        hasLength(2),
      );
      expect(found("starLabel: (s) => s ? 'Unstar' : 'Star',"), hasLength(2));
    });

    test('reads a name by what it ends in', () {
      expect(found("ratingLabel: (n) => 'stars',"), hasLength(1));
      expect(found("emptyMessage: 'nothing here',"), hasLength(1));
      expect(found("messenger.show('started'),"), hasLength(1));
    });

    test('a literal being matched against is not copy', () {
      expect(found("label: frame['message'] as String,"), isEmpty);
      expect(found("label: switch (k) { 'detected' => other },"), isEmpty);
      expect(found("label: kind == 'backup' ? a : b,"), isEmpty);
    });

    test('formatting is not copy', () {
      expect(found(r"text: '$count',"), isEmpty);
      expect(found(r"message: warnings.join('\n'),"), isEmpty);
    });

    test('prose split across lines is one site', () {
      expect(
        found("message:\n  'one half '\n  'and the other',"),
        hasLength(1),
      );
    });

    test('a name and the widget under it count once', () {
      expect(found("title: Text('Backups'),"), hasLength(1));
    });
  });
}

/// The generated sources, in which every rule is meaningless because
/// nobody writes them. A directory stands for everything under it.
const _generated = <String>[
  'lib/src/shell/semantics_ids.dart',
  'lib/src/shell/app_version.dart',
  'lib/src/l10n/gen',
];

bool _isGenerated(String path) =>
    _generated.any((g) => path == g || path.startsWith('$g/'));

/// Every package held to the conventions, relative to `app/app`, which
/// is where this test runs.
///
/// The catalogue is in because it is the taste reference the
/// screen-level audit judges against and would otherwise be the one
/// Flutter app in the repo where a `SwitchListTile` is invisible. Its
/// copy is the one thing it is not held to; see [_CopyRule.appliesTo].
///
/// `waxdeck_ui` itself is in for one rule and out for the rest: it
/// declares the ladder, the glyphs, and the type scale, so raw
/// measurements and Material primitives are what it is made of - but its
/// copy is copy like anywhere else, and it holds eighty strings no caller
/// can pass in. See [_Rule.appliesTo], which is where that split lives.
const _roots = <String>[
  'lib',
  _designSystem,
  '../packages/waxdeck_ui/example/lib',
  '../packages/waxdeck_data/lib',
  '../packages/waxdeck_player/lib',
];

/// The design system's own sources, which every rule but the copy one
/// has nothing to say about.
const _designSystem = '../packages/waxdeck_ui/lib';

List<File> _sources() => <File>[
  for (final root in _roots)
    if (Directory(root).existsSync())
      ...Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
]..sort((a, b) => a.path.compareTo(b.path));

/// One breach: where it is, and any pointer built from its text.
class _Hit {
  const _Hit(this.at, [this.hint = '']);

  final int at;
  final String hint;
}

/// A rule states what it forbids and what to reach for instead.
class _Rule {
  const _Rule({required this.name, required this.pattern, required this.fix});

  final String name;
  final RegExp pattern;
  final String fix;

  /// Whether this rule has anything to say about [path].
  ///
  /// The design system is the standing exception: it is what the ladder,
  /// the glyphs, and the type scale are made of, so counting raw
  /// measurements and Material primitives there would count the
  /// definitions. [_CopyRule] overrides this, because copy is copy
  /// wherever it is written.
  bool appliesTo(String path) => !path.startsWith('$_designSystem/');

  Iterable<_Hit> find(String code) =>
      pattern.allMatches(code).map((m) => _Hit(m.start));
}

/// The insets rule, which a bare pattern does not fit. An `EdgeInsets`
/// call runs across lines as often as not and nests brackets when an
/// argument is computed, so its arguments are read by walking the
/// brackets rather than by matching.
class _InsetsRule extends _Rule {
  _InsetsRule()
    : super(
        name: 'raw-inset',
        // The unnamed constructor as well as the named ones:
        // `EdgeInsets(left: 16)` is the same offence spelled the long
        // way, and a pattern that demanded a `.name` waved it through.
        pattern: RegExp(r'\bEdgeInsets(?:Directional)?(?:\.\w+)?\('),
        fix: 'use the WaxSpace ladder',
      );

  /// A number standing where an argument's value goes: after the open
  /// bracket, a separator, or a label, and nothing but the next
  /// separator after it.
  ///
  /// Narrow on purpose. `WaxSpace.s12` hides digits inside an
  /// identifier, and `gutter.horizontal / 2` is arithmetic on a token
  /// rather than a measurement somebody typed - neither is the thing
  /// this rule is about, and a looser test reports both. The leading
  /// `-` is here because `only(top: -6)` is as raw as `only(top: 6)`.
  static final _literal = RegExp(
    r'(?:^|[(,:?])\s*(-?\d+(?:\.\d+)?)\s*(?=[,)]|$)',
  );

  static const _ladder = <int>[4, 8, 12, 16, 20, 24, 32, 40, 48, 64];

  @override
  Iterable<_Hit> find(String code) sync* {
    for (final match in pattern.allMatches(code)) {
      final args = arguments(code, match.end);
      if (args == null) continue;
      // Zero is structure rather than measurement - `fromLTRB(0, 0, 0,
      // WaxSpace.s8)` is already written the way the ladder wants - so
      // it is not counted and has no rung to point at.
      final values = _literal
          .allMatches(args)
          .map((m) => double.parse(m.group(1)!))
          .where((v) => v != 0)
          .toSet();
      if (values.isEmpty) continue;
      yield _Hit(match.start, rungs(values));
    }
  }

  /// The inset's own arguments: the text between the opening bracket at
  /// [start] and its partner, with anything nested inside a further call
  /// blanked out.
  ///
  /// Blanked rather than kept, because a number handed to another
  /// function is that function's business and not a measurement in
  /// pixels. `EdgeInsets.all(_s(0.07))` scales a share card by a
  /// fraction of its canvas; reading the 0.07 as a length produced the
  /// advice "0.07 -> nearest s4" and an allowlist entry that could never
  /// go to zero.
  static String? arguments(String code, int start) {
    final own = StringBuffer();
    var depth = 1;
    for (var i = start; i < code.length; i++) {
      final char = code[i];
      if (char == '(') depth++;
      if (char == ')') depth--;
      if (depth == 0) return own.toString();
      own.write(depth == 1 && char != '(' ? char : ' ');
    }
    return null;
  }

  /// The nearest rung to each literal, so the failure says what to type.
  static String rungs(Set<double> values) => (values.toList()..sort())
      .map((value) {
        final rung = _ladder.reduce(
          (a, b) => (a - value).abs() <= (b - value).abs() ? a : b,
        );
        final near = value.toString().replaceAll(RegExp(r'\.0$'), '');
        return rung == value
            ? '$near -> WaxSpace.s$rung'
            : '$near -> nearest s$rung';
      })
      .join(', ');
}

/// The gap rule: a childless `SizedBox` measured in raw pixels.
///
/// The commonest raw measurement in the codebase by a wide margin, and
/// the one an inset rule alone leaves untouched - the space between two
/// widgets is spacing whether it is spelled as padding or as an empty
/// box.
///
/// Childless is the whole distinction, and it is why this walks the
/// brackets rather than matching a pattern. `SizedBox(width: 360, child:
/// field)` is a content box being given a width, and 360 is not a rung
/// on a scale that stops at 64; `SizedBox(height: 8)` is a gap.
class _GapRule extends _Rule {
  _GapRule()
    : super(
        name: 'raw-gap',
        pattern: RegExp(r'\bSizedBox\('),
        fix: 'use the WaxSpace ladder',
      );

  static final _measure = RegExp(
    r'(?:^|,)\s*(?:width|height):\s*(-?\d+(?:\.\d+)?)\s*(?=[,)]|$)',
  );

  @override
  Iterable<_Hit> find(String code) sync* {
    for (final match in pattern.allMatches(code)) {
      final args = _InsetsRule.arguments(code, match.end);
      if (args == null || args.contains('child:')) continue;
      final values = _measure
          .allMatches(args)
          .map((m) => double.parse(m.group(1)!))
          .where((v) => v != 0)
          .toSet();
      if (values.isEmpty) continue;
      yield _Hit(match.start, _InsetsRule.rungs(values));
    }
  }
}

/// The copy rule: an English sentence typed into a widget rather than
/// looked up.
///
/// Copy is the one convention that cannot be spotted by its shape - a
/// string literal is a string literal - so it is spotted by its
/// position: the child of a `Text`, or the value of an argument name
/// that carries words to a reader. Everything else a widget is handed
/// (a pid, a wire token, a semantics identifier, a route) reaches it
/// under a different name.
///
/// A literal with no letters left once its interpolations are removed is
/// not copy: `'$count'` and `'  -  '` are formatting, and counting them
/// would put a floor on a file that has nothing to translate.
class _CopyRule extends _Rule {
  _CopyRule()
    : super(
        name: 'hardcoded-copy',
        // Matched by what the name ends in rather than by a list of
        // whole names: `starLabel`, `remainingLabel` and `activeLabel`
        // carry sentences no less than `label` does, and a hand-kept
        // list is a list somebody adds a name beside. The four spelled
        // out in full are the ones whose suffix says nothing.
        pattern: RegExp(
          r'\b(?:Selectable)?Text\(\s*|'
          // The shell messenger takes its sentence positionally.
          r'\.show\(\s*|'
          r'\b\w*(?:[Ll]abel|[Tt]itle|[Oo]verline|[Cc]aption|[Hh]elp'
          r'|[Hh]int|[Tt]ooltip|[Mm]essage|[Bb]lurb|[Dd]etail'
          r'|[Tt]agline|[Ss]ubject)\s*:\s*|'
          r'\b(?:text|errorText|confirmWord|semanticLabel)\s*:\s*',
        ),
        fix:
            'move it to an ARB key and read it through context.l10n '
            '(context.waxL10n inside the design system)',
      );

  /// Interpolations, so what is left is what a translator would work on.
  static final _interpolation = RegExp(r'\$\{[^{}]*\}|\$\w+');

  /// Escapes go with them: the `n` in `'\n'` is a newline, not a word,
  /// and a separator counted as copy is a floor on a finished file.
  static final _escape = RegExp(r'\\.');
  static final _letter = RegExp(r'[A-Za-z]');

  /// The design system is in - its components own eighty strings a
  /// caller cannot reach, and that is exactly the copy that goes
  /// untranslated by default.
  ///
  /// The catalogue is out: its strings are the demo library it draws -
  /// album titles, specimen copy - and none of it is ever translated, so
  /// counting them would put a permanent floor on the one root where a
  /// nonzero count means nothing.
  @override
  bool appliesTo(String path) =>
      !path.startsWith('../packages/waxdeck_ui/example/');

  /// Every literal in the argument's value, not the one at its head.
  ///
  /// Copy hides one token in - behind a `?:`, a `??`, an arrow, a
  /// switch arm - and a rule that reads only the head declares those
  /// files finished having never seen them. Both branches of a ternary
  /// are two sentences to translate, so both are counted.
  ///
  /// Offsets are what dedupe: `title: Text('x')` matches twice, once on
  /// the name and once on the widget, and it is one string either way.
  @override
  Iterable<_Hit> find(String code) sync* {
    final seen = <int>{};
    for (final match in pattern.allMatches(code)) {
      final end = _valueEnd(code, match.end);
      var i = match.end;
      while (i < end) {
        final read = _readLiteral(code, i);
        if (read == null) {
          i++;
          continue;
        }
        final after = _skipContinuations(code, read.end, end);
        final matched = _isMatchedAgainst(code, read.start, read.end);
        i = after;
        if (!seen.add(read.start)) continue;
        if (matched) continue;
        final words = read.body
            .replaceAll(_interpolation, '')
            .replaceAll(_escape, '');
        if (!_letter.hasMatch(words)) continue;
        yield _Hit(read.start, _preview(words));
      }
    }
  }

  /// Where the value ends: the comma or closing bracket at the depth it
  /// started on. Strings are stepped over whole, so a bracket inside one
  /// cannot close it.
  static int _valueEnd(String code, int start) {
    var depth = 0;
    var i = start;
    while (i < code.length) {
      final read = _readLiteral(code, i);
      if (read != null) {
        i = read.end;
        continue;
      }
      final c = code[i];
      if (c == '(' || c == '[' || c == '{') depth++;
      if (c == ')' || c == ']' || c == '}') {
        if (depth == 0) return i;
        depth--;
      }
      if (depth == 0 && (c == ',' || c == ';')) return i;
      i++;
    }
    return code.length;
  }

  /// Whether the literal is being compared rather than drawn.
  ///
  /// A switch pattern (`'detected' =>`), a map or index key
  /// (`frame['message']`), and an equality test are all wire tokens
  /// standing in an expression that does draw copy. Counting them
  /// would put a floor on files with nothing left to translate, which
  /// is the same lie as missing the copy, pointed the other way.
  static bool _isMatchedAgainst(String code, int start, int end) {
    var before = start - 1;
    while (before >= 0 && (code[before] == ' ' || code[before] == '\n')) {
      before--;
    }
    if (before >= 0 && code[before] == '[') return true;
    if (before >= 1 && (code.startsWith('==', before - 1))) return true;
    if (before >= 1 && (code.startsWith('!=', before - 1))) return true;
    if (before >= 3 && code.startsWith('case', before - 3)) return true;
    var after = end;
    while (after < code.length && (code[after] == ' ' || code[after] == '\n')) {
      after++;
    }
    return code.startsWith('=>', after) || code.startsWith(']', after);
  }

  /// Past the adjacent segments of one literal. Prose split across lines
  /// is one copy site and becomes one ARB key, so it counts once.
  static int _skipContinuations(String code, int end, int limit) {
    var i = end;
    while (i < limit) {
      if (code[i] == ' ' || code[i] == '\n' || code[i] == '\r') {
        i++;
        continue;
      }
      final next = _readLiteral(code, i);
      if (next == null) return i;
      i = next.end;
    }
    return i;
  }

  static String _preview(String words) {
    final flat = words.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 40 ? "'$flat'" : "'${flat.substring(0, 39)}...'";
  }

  /// The string literal beginning at [start], or null if what stands
  /// there is not one. The bounds ride along, because the value scan
  /// has to step over a literal to know a bracket inside it is not a
  /// bracket.
  ///
  /// Interpolations are walked rather than stopped at, because a quote
  /// inside one (`'Added "${item.title}"'`) is not the literal's end.
  static ({int start, int end, String body})? _readLiteral(
    String code,
    int start,
  ) {
    var i = start;
    final raw = i < code.length && code[i] == 'r';
    if (raw) i++;
    final quote = _quoteAt(code, i);
    if (quote == null) return null;
    i += quote.length;
    final body = StringBuffer();
    while (i < code.length) {
      if (!raw && code[i] == r'\' && i + 1 < code.length) {
        body.write(code.substring(i, i + 2));
        i += 2;
        continue;
      }
      if (!raw && code.startsWith(r'${', i)) {
        // Nested quotes and braces live in here; hand the whole
        // interpolation through so the stripper can drop it whole.
        final end = _interpolationEnd(code, i + 2);
        if (end == null) return null;
        body.write(code.substring(i, end));
        i = end;
        continue;
      }
      if (code.startsWith(quote, i)) {
        return (start: start, end: i + quote.length, body: body.toString());
      }
      // A single-quoted literal cannot span a line; an unterminated one
      // is a scan that went wrong, not a finding.
      if (quote.length == 1 && code[i] == '\n') return null;
      body.write(code[i]);
      i++;
    }
    return null;
  }

  static int? _interpolationEnd(String code, int start) {
    var depth = 1;
    for (var i = start; i < code.length; i++) {
      if (code[i] == '{') depth++;
      if (code[i] == '}') {
        depth--;
        if (depth == 0) return i + 1;
      }
    }
    return null;
  }
}

final _rules = <_Rule>[
  _Rule(
    name: 'material-list-tile',
    // The generic form too: `RadioListTile<T>(` is the same
    // primitive wearing a type argument.
    pattern: RegExp(
      r'\b(?:Switch|Checkbox|Radio|Expansion)?ListTile(?:<[^>]*>)?\(',
    ),
    fix:
        'use WaxSettingRow (a control on the right) or WaxOptionRow '
        '(a tappable row), which carry the house metrics and semantics',
  ),
  _Rule(
    name: 'material-icon',
    // `Icons.` and nothing else: `WaxIcons.play` does not match, because
    // the name it ends with is not the name it is.
    pattern: RegExp(r'(?<![\w.])Icons\.\w+'),
    fix:
        'use WaxIcons, whose glyphs are the vendored subset fonts '
        '(a missing one is added with `make icons`, never by hand)',
  ),
  _InsetsRule(),
  _Rule(
    name: 'material-text-theme',
    pattern: RegExp(r'\btextTheme\b'),
    fix:
        "use WaxType, whose styles name the app's own faces; Material's "
        'text theme is a different scale wearing the same words',
  ),
  _GapRule(),
  _Rule(
    name: 'raw-radius',
    pattern: RegExp(r'\bBorderRadius\.circular\(\s*\d'),
    fix: 'use WaxRadius, which owns the corner scale',
  ),
  _CopyRule(),
];

class _Finding {
  const _Finding(this.rule, this.line, this.snippet, this.hit);

  final _Rule rule;
  final int line;
  final String snippet;
  final _Hit hit;

  String describe(String file) =>
      '  $file:$line  $snippet\n'
      '    -> ${rule.fix}${hit.hint.isEmpty ? '' : ' (${hit.hint})'}';
}

/// One nesting level: a string literal being read, or the code inside
/// one of its interpolations.
class _Frame {
  _Frame.string(this.quote, this.raw) : braces = 0;
  _Frame.interpolation() : quote = null, raw = false, braces = 1;

  final String? quote;
  final bool raw;
  int braces;

  bool get inString => quote != null;
}

/// The source with its comments blanked out, so that a doc comment
/// explaining a convention is not counted as a breach of it.
///
/// Offsets are preserved - a comment becomes spaces of the same width,
/// not nothing - so a match's position is still the file's own. String
/// literals are tracked only so that a `//` inside one does not start a
/// comment.
///
/// Strings and interpolations nest, which is why this is a stack rather
/// than a flag. `'${map['k']}'` is one string, holding code, holding
/// another string: a scanner that closed at the quote before `k` would
/// read `]}'` as the start of a fresh literal and put every boundary
/// after it on the wrong side. That direction of error under-counts,
/// and an under-count reports green.
String _code(String source) {
  final out = StringBuffer();
  final stack = <_Frame>[];
  var i = 0;

  while (i < source.length) {
    final frame = stack.isEmpty ? null : stack.last;

    if (frame != null && frame.inString) {
      final quote = frame.quote!;
      if (!frame.raw && source[i] == r'\' && i + 1 < source.length) {
        out.write(source.substring(i, i + 2));
        i += 2;
        continue;
      }
      // A raw string interpolates nothing; `$` is just a dollar there.
      if (!frame.raw && source.startsWith(r'${', i)) {
        out.write(r'${');
        i += 2;
        stack.add(_Frame.interpolation());
        continue;
      }
      if (source.startsWith(quote, i)) {
        out.write(quote);
        i += quote.length;
        stack.removeLast();
        continue;
      }
      // A single-quoted string cannot span a line, so stopping at the
      // newline keeps an unterminated one from swallowing the file.
      if (quote.length == 1 && source[i] == '\n') {
        stack.removeLast();
        continue;
      }
      out.write(source[i]);
      i++;
      continue;
    }

    if (source.startsWith('//', i)) {
      while (i < source.length && source[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }
    if (source.startsWith('/*', i)) {
      // Dart nests block comments, so the depth is counted rather than
      // stopping at the first close.
      var depth = 0;
      while (i < source.length) {
        if (source.startsWith('/*', i)) {
          depth++;
          out.write('  ');
          i += 2;
        } else if (source.startsWith('*/', i)) {
          depth--;
          out.write('  ');
          i += 2;
          if (depth == 0) break;
        } else {
          out.write(source[i] == '\n' ? '\n' : ' ');
          i++;
        }
      }
      continue;
    }

    final quote = _quoteAt(source, i);
    if (quote != null) {
      // `r` marks a raw string only where it starts a token - `[r'x']`,
      // never the tail of an identifier. Compiling Dart cannot put an
      // identifier against a quote at all, so the second half of this
      // is unreachable; the scanner should not have to prove that about
      // whatever it is pointed at.
      final raw =
          i > 0 &&
          source[i - 1] == 'r' &&
          (i == 1 || !_identifier.hasMatch(source[i - 2]));
      out.write(quote);
      i += quote.length;
      stack.add(_Frame.string(quote, raw));
      continue;
    }

    if (frame != null) {
      if (source[i] == '{') frame.braces++;
      if (source[i] == '}') {
        frame.braces--;
        if (frame.braces == 0) {
          out.write('}');
          i++;
          stack.removeLast();
          continue;
        }
      }
    }

    out.write(source[i]);
    i++;
  }
  return out.toString();
}

final _identifier = RegExp(r'[\w$]');

String? _quoteAt(String source, int i) {
  for (final quote in <String>["'''", '"""', "'", '"']) {
    if (source.startsWith(quote, i)) return quote;
  }
  return null;
}

Map<String, Map<String, int>> _sorted(Map<String, Map<String, int>> counts) {
  final files = counts.keys.toList()..sort();
  return <String, Map<String, int>>{
    for (final file in files)
      file: <String, int>{
        for (final rule in counts[file]!.keys.toList()..sort())
          rule: counts[file]![rule]!,
      },
  };
}
