import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The e2e suite selects a control by `sem(id)`, which puts the id inside
/// a CSS double-quoted string, and an id built from a server's data (a
/// fold key holds a tag's text) can carry what such a string cannot hold
/// as itself. No JavaScript runs here, so this reads the generated helper
/// in e2e/tests/semantics-ids.ts: its code is the per-character map
/// pinned below, and its escape table is applied here as that code
/// applies it, then read back the way a CSS parser reads a string.
void main() {
  final source = File('../../e2e/tests/semantics-ids.ts').readAsStringSync();

  test('the selectors quote an id through the escape table', () {
    expect(
      source,
      contains(
        'const cssString = (value: string) =>\n'
        "  Array.from(value, (c) => CSS_STRING_ESCAPES[c] ?? c).join('');",
      ),
    );
    expect(source, contains(r'`[${SEMANTICS_ATTRIBUTE}="${cssString(id)}"]`'));
    expect(
      source,
      contains(r'`[${SEMANTICS_ATTRIBUTE}^="${cssString(prefix)}"]`'),
    );
  });

  test('an id comes back whole from its quoted selector', () {
    final table = _escapes(source);
    String quote(String value) =>
        [for (final c in value.split('')) table[c] ?? c].join();
    expect(quote('a"b\\c'), r'a\"b\\c');
    expect(quote('fold-row-artist-the beatles'), 'fold-row-artist-the beatles');
    for (final id in <String>[
      'fold-row-album-al:rg:joni\u001fblue\u001f\u001f\u001fjoni blue',
      'a"b\\c',
      'one\ntwo\rthree\ffour',
      'trailing\\',
      '"',
    ]) {
      expect(_readCssString(quote(id)), id, reason: 'quoted as ${quote(id)}');
    }
  });
}

/// The generated escape table, as JSON on its own line.
Map<String, String> _escapes(String source) {
  final line = RegExp(
    r'^const CSS_STRING_ESCAPES: [^=]+= (\{.*\});$',
    multiLine: true,
  ).firstMatch(source);
  expect(line, isNotNull, reason: 'no escape table in the generated helper');
  return (jsonDecode(line!.group(1)!) as Map<String, dynamic>)
      .cast<String, String>();
}

/// The inside of a CSS double-quoted string as CSS Syntax reads it: a raw
/// double quote or line break cannot stand in it, and a backslash takes
/// up to six hex digits (and one space after them) or the next character.
String _readCssString(String content) {
  final out = StringBuffer();
  final units = content.split('');
  var i = 0;
  while (i < units.length) {
    final c = units[i++];
    if (c == '"' || c == '\n' || c == '\r' || c == '\f') {
      throw FormatException('cannot stand in a CSS string', content, i - 1);
    }
    if (c != r'\') {
      out.write(c);
      continue;
    }
    if (i == units.length) throw FormatException('a trailing escape', content);
    var hex = '';
    while (i < units.length &&
        hex.length < 6 &&
        RegExp(r'^[0-9a-fA-F]$').hasMatch(units[i])) {
      hex += units[i++];
    }
    if (hex.isEmpty) {
      out.write(units[i++]);
      continue;
    }
    out.writeCharCode(int.parse(hex, radix: 16));
    if (i < units.length && units[i] == ' ') i++;
  }
  return out.toString();
}
