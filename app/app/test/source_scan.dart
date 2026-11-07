/// Scanning Dart source as text, for the conventions tests that count
/// constructs in it (`ui_conventions_test.dart`,
/// `harness_conventions_test.dart`).
library;

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
///
/// With [strings], the text of every string literal is blanked too, its
/// quotes and the code in its interpolations kept, so a construct named
/// in a string is not found as code.
String blankComments(String source, {bool strings = false}) {
  final out = StringBuffer();
  final stack = <_Frame>[];
  var i = 0;

  void text(String chars) =>
      out.write(strings ? chars.replaceAll(_notNewline, ' ') : chars);

  while (i < source.length) {
    final frame = stack.isEmpty ? null : stack.last;

    if (frame != null && frame.inString) {
      final quote = frame.quote!;
      if (!frame.raw && source[i] == r'\' && i + 1 < source.length) {
        text(source.substring(i, i + 2));
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
      text(source[i]);
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

    final quote = quoteAt(source, i);
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

final _notNewline = RegExp(r'[^\n]');

/// The quote that opens a string literal at [i], or null.
String? quoteAt(String source, int i) {
  for (final quote in <String>["'''", '"""', "'", '"']) {
    if (source.startsWith(quote, i)) return quote;
  }
  return null;
}
