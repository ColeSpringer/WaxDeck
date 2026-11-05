import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

Future<void> _pump(WidgetTester tester, Widget header, {double width = 900}) {
  tester.view
    ..physicalSize = Size(width, 1200)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      theme: buildWaxTheme(),
      localizationsDelegates: waxLocalizationsDelegates,
      home: Scaffold(body: SingleChildScrollView(child: header)),
    ),
  );
}

void main() {
  testWidgets('actions, trailing and overflow share one WaxActionBar', (
    tester,
  ) async {
    await _pump(
      tester,
      EntityHeader(
        title: 'The Harbour Tapes',
        actions: <WaxAction>[
          WaxAction(
            label: 'Play',
            semanticsId: 'play',
            glyph: WaxIcons.play,
            emphasis: WaxActionEmphasis.primary,
            onPressed: () {},
          ),
          WaxAction(label: 'Shuffle', semanticsId: 'shuffle', onPressed: () {}),
        ],
        trailing: <Widget>[StarButton(starred: true, onChanged: (_) {})],
        overflow: const SizedBox(key: ValueKey<String>('menu')),
      ),
    );
    final bar = find.byType(WaxActionBar);
    expect(bar, findsOneWidget);
    expect(
      find.descendant(of: bar, matching: find.byType(WaxButton)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: bar, matching: find.byType(StarButton)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bar, matching: find.byKey(const ValueKey('menu'))),
      findsOneWidget,
    );
    expect(
      find.byType(WaxButton),
      findsNWidgets(2),
      reason: 'no pill outside the bar',
    );
  });

  testWidgets('the header reads its lines in the order it draws them', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      EntityHeader(
        title: 'The Harbour Tapes',
        subtitle: 'Read by someone',
        metadata: '1975 · 3 parts',
        description: 'People line',
        semanticsId: 'header',
        links: <EntityHeaderLink>[
          EntityHeaderLink(
            label: 'by An Author',
            semanticsId: 'author',
            onPressed: () {},
          ),
        ],
        actions: <WaxAction>[
          WaxAction(label: 'Play', semanticsId: 'play', onPressed: () {}),
        ],
      ),
    );
    // One node for the words, title to people line, with the links and
    // the actions as their own nodes: nothing in between is lifted out
    // of its place.
    expect(
      tester.getSemantics(find.bySemanticsIdentifier('header')).label,
      'The Harbour Tapes\nRead by someone\n1975 · 3 parts\nPeople line',
    );
    semantics.dispose();
  });

  testWidgets('a header with nothing to do draws no bar', (tester) async {
    await _pump(tester, const EntityHeader(title: 'Series'));
    expect(find.byType(WaxActionBar), findsNothing);
  });

  testWidgets('the links are drawn under the subtitle, tappable and named', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var authorTaps = 0;
    var seriesTaps = 0;
    await _pump(
      tester,
      EntityHeader(
        title: 'A Bright Shore',
        subtitle: 'Read by Ines Marchetti',
        links: <EntityHeaderLink>[
          EntityHeaderLink(
            label: 'By Mirren Vaux',
            semanticsId: 'author-link',
            onPressed: () => authorTaps++,
          ),
          EntityHeaderLink(
            label: 'Book 2 of The Tide Almanac',
            semanticsId: 'series-link',
            onPressed: () => seriesTaps++,
          ),
        ],
      ),
    );
    final author = find.text('By Mirren Vaux');
    final series = find.text('Book 2 of The Tide Almanac');
    expect(author, findsOneWidget);
    expect(series, findsOneWidget);
    expect(
      tester.getTopLeft(author).dy,
      greaterThan(tester.getBottomLeft(find.text('Read by Ines Marchetti')).dy),
    );
    expect(
      tester.getTopLeft(series).dy,
      greaterThan(tester.getBottomLeft(author).dy),
      reason: 'one per line, in the order given',
    );
    final node = tester.getSemantics(find.bySemanticsIdentifier('series-link'));
    expect(node.label, contains('Book 2 of The Tide Almanac'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(find.byType(WaxButton), findsNWidgets(2));
    for (final button in tester.widgetList<WaxButton>(find.byType(WaxButton))) {
      expect(
        tester.getSize(find.byWidget(button)).height,
        WaxSpace.touchTarget,
        reason: 'each link keeps the vertical touch target',
      );
    }
    await tester.tap(series);
    await tester.pump();
    expect((authorTaps, seriesTaps), (0, 1));
    await tester.tap(author);
    await tester.pump();
    expect((authorTaps, seriesTaps), (1, 1));
    semantics.dispose();
  });

  testWidgets('no links draws no button', (tester) async {
    await _pump(tester, const EntityHeader(title: 'A Bright Shore'));
    expect(find.byType(WaxButton), findsNothing);
  });

  testWidgets('the link follows the text block alignment', (tester) async {
    final header = EntityHeader(
      title: 'A Bright Shore',
      subtitle: 'Read by Ines Marchetti',
      links: <EntityHeaderLink>[
        EntityHeaderLink(label: 'Series', semanticsId: 'l', onPressed: _noop),
      ],
    );
    final title = find.text('A Bright Shore');
    final link = find.text('Series');
    await _pump(tester, header, width: 400);
    expect(
      tester.getCenter(link).dx,
      closeTo(tester.getCenter(title).dx, 0.5),
      reason: 'centred under a centred title when stacked',
    );
    await _pump(tester, header, width: 1200);
    expect(
      tester.getTopLeft(link).dx,
      closeTo(tester.getTopLeft(title).dx, 0.5),
      reason: 'start-aligned with the title beside the art',
    );
  });

  testWidgets('a wrapped link lines up its lines with the header', (
    tester,
  ) async {
    const label =
        'Book 12 of The Long Chronicle of the Harbour and Everything Past It';
    final header = EntityHeader(
      title: 'A Bright Shore',
      links: <EntityHeaderLink>[
        EntityHeaderLink(label: label, semanticsId: 'l', onPressed: _noop),
      ],
    );
    RenderParagraph paragraph() =>
        tester.renderObject<RenderParagraph>(find.text(label));

    await _pump(tester, header, width: 320);
    expect(
      paragraph().size.height,
      greaterThan(paragraph().preferredLineHeight * 1.5),
      reason: 'the label wraps at a phone width',
    );
    expect(paragraph().textAlign, TextAlign.center);
    await _pump(tester, header, width: 1200);
    expect(paragraph().textAlign, TextAlign.start);
  });
}

void _noop() {}
