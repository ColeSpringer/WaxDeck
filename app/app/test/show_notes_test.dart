import 'localized_host.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/podcasts/show_notes.dart';

Widget _host(String html, {void Function(String url)? onOpenLink}) =>
    localizedHost(
      Scaffold(
        body: SingleChildScrollView(
          child: ShowNotesView(html: html, onOpenLink: onOpenLink),
        ),
      ),
    );

void main() {
  testWidgets('plain text passes through untouched', (tester) async {
    await tester.pumpWidget(_host('Just some plain text.'));
    expect(
      find.text('Just some plain text.', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('bold and italic render inside a paragraph', (tester) async {
    await tester.pumpWidget(
      _host('<p>Hello <b>bold</b> and <em>slanted</em> world</p>'),
    );
    expect(
      find.text('Hello bold and slanted world', findRichText: true),
      findsOneWidget,
    );
    final blocks = parseShowNotes(
      '<p>Hello <b>bold</b> and <em>slanted</em> world</p>',
    );
    expect(blocks, hasLength(1));
    expect(blocks.single.runs.map((r) => r.bold), [
      false,
      true,
      false,
      false,
      false,
    ]);
    expect(blocks.single.runs[3].italic, isTrue);
  });

  testWidgets('unordered and ordered lists render their items', (tester) async {
    await tester.pumpWidget(
      _host('<ul><li>First</li><li>Second</li></ul><ol><li>Uno</li></ol>'),
    );
    expect(find.text('First', findRichText: true), findsOneWidget);
    expect(find.text('Second', findRichText: true), findsOneWidget);
    expect(find.text('Uno', findRichText: true), findsOneWidget);
    expect(find.text('- '), findsNWidgets(2));
    expect(find.text('1. '), findsOneWidget);
  });

  testWidgets('links render and tap through to the opener', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      _host(
        '<p>Visit <a href="https://pony.example/">the inn</a> today</p>',
        onOpenLink: opened.add,
      ),
    );
    expect(find.text('the inn'), findsOneWidget);
    await tester.tap(find.text('the inn'));
    expect(opened, ['https://pony.example/']);
  });

  testWidgets('script content is dropped, never rendered as markup', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host('<script>alert("boom")</script><p>Safe text</p>'),
    );
    expect(find.text('Safe text', findRichText: true), findsOneWidget);
    expect(find.textContaining('alert', findRichText: true), findsNothing);
    expect(find.textContaining('<script>', findRichText: true), findsNothing);
  });

  testWidgets('malformed markup degrades to text without crashing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host('<p><b>unclosed bold <weird-tag attr>text</p> trailing <'),
    );
    expect(find.text('unclosed bold text', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('trailing <', findRichText: true),
      findsOneWidget,
    );
  });

  test('headings, quotes, rules, and pre map to their block kinds', () {
    final blocks = parseShowNotes(
      '<h2>Title</h2><blockquote>Quoted</blockquote><hr>'
      '<pre>code  here</pre>',
    );
    expect(blocks.map((b) => b.kind), [
      ShowNotesBlockKind.heading2,
      ShowNotesBlockKind.blockquote,
      ShowNotesBlockKind.rule,
      ShowNotesBlockKind.pre,
    ]);
    // Preformatted text keeps its internal whitespace.
    expect(blocks.last.runs.single.text, 'code  here');
  });

  test('entities decode and unknown tags keep their text content', () {
    final blocks = parseShowNotes('<p>Fish &amp; chips &#39;n&#39; more</p>');
    expect(
      blocks.single.runs.map((r) => r.text).join(),
      "Fish & chips 'n' more",
    );

    final unknown = parseShowNotes('<p><marquee>still here</marquee></p>');
    expect(unknown.single.runs.single.text, 'still here');
  });

  test('a run of line breaks collapses to one blank line', () {
    // What feeds actually send: paragraphs laid out with <br> rather than
    // <p>, five or six deep. Each one is its own literal newline run, and
    // the edge trim only reaches a block's two ends - so a clamped height
    // used to spend itself on blank lines with the text clipped under
    // them.
    final blocks = parseShowNotes(
      'Episode notes<br><br><br><br><br>Links below',
    );
    expect(blocks, hasLength(1));
    expect(
      blocks.single.runs.map((r) => r.text).join(),
      'Episode notes\n\nLinks below',
    );

    // A single break still breaks the line.
    expect(
      parseShowNotes('One<br>Two').single.runs.map((r) => r.text).join(),
      'One\nTwo',
    );

    // Whitespace between the breaks does not save them: the stretch is
    // read for the newlines it carries, not run by run.
    expect(
      parseShowNotes(
        'One<br>\n  <br>\t<br>Two',
      ).single.runs.map((r) => r.text).join(),
      'One\n\nTwo',
    );

    // Preformatted blocks keep every one: there the whitespace is the
    // content.
    expect(
      parseShowNotes(
        '<pre>a<br><br><br>b</pre>',
      ).single.runs.map((r) => r.text).join(),
      'a\n\n\nb',
    );
  });

  test('tables flatten to text rows', () {
    final blocks = parseShowNotes(
      '<table><tr><td>a</td><td>b</td></tr><tr><td>c</td></tr></table>',
    );
    final text = blocks.map((b) => b.runs.map((r) => r.text).join()).join('|');
    expect(text, contains('a'));
    expect(text, contains('b'));
    expect(text, contains('c'));
  });
}
