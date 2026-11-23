import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// How much chrome sits above the first row of content, which is what
/// the report was about. Read off the content rather than off the bar:
/// a `SliverAppBar` is a sliver and has no box to measure.
Future<double> _chromeAboveContent(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWaxTheme(),
      home: const WaxScaffold(
        title: 'Music',
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: SizedBox(key: Key('content'), height: 2000),
          ),
        ],
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.getTopLeft(find.byKey(const Key('content'))).dy;
}

void main() {
  group('the large title band', () {
    testWidgets('is shallower on a phone than on a desktop window', (
      tester,
    ) async {
      // The reported forehead: a fixed 112 plus the status-bar inset a
      // primary bar adds to itself put a fifth of a phone window above
      // the first row of content.
      final compact = await _chromeAboveContent(tester, const Size(390, 844));
      final wide = await _chromeAboveContent(tester, const Size(1280, 900));
      expect(compact, lessThan(wide));
      expect(
        compact,
        WaxScaffold.shallowTitleHeight,
        reason: 'the drawn band is the height barHeight promises',
      );
      expect(wide, WaxScaffold.deepTitleHeight);
    });

    testWidgets('a phone on its side gets the shallow band too', (
      tester,
    ) async {
      // The size class is a width, and a landscape phone is 844 of them.
      // Taking the deep band and the 1.5x title there spends a fifth of
      // the shallowest window the app is ever drawn in on chrome - a
      // worse forehead than the portrait one this all started with.
      final landscape = await _chromeAboveContent(tester, const Size(844, 390));
      expect(landscape, WaxScaffold.shallowTitleHeight);
    });

    testWidgets('the title fits the band it is given', (tester) async {
      // A shallow band has no travel for Material's 1.5x expanded title
      // to fall through, so compact holds one size. If it did not, the
      // title would overflow the band it is drawn in.
      await _chromeAboveContent(tester, const Size(390, 844));
      expect(tester.takeException(), isNull);
      final title = tester.getRect(find.text('Music'));
      expect(title.height, lessThanOrEqualTo(WaxScaffold.shallowTitleHeight));
    });

    testWidgets('barHeight answers for the window it is asked in', (
      tester,
    ) async {
      late double large;
      late double small;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWaxTheme(),
          home: Builder(
            builder: (context) {
              large = WaxScaffold.barHeight(context);
              small = WaxScaffold.barHeight(context, largeTitle: false);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // The rail that reads this lays itself out under the bar; a stale
      // constant here puts its first letter behind the title.
      expect(large, WaxScaffold.shallowTitleHeight);
      expect(small, kToolbarHeight);
    });
  });

  group("the window's insets", () {
    const size = Size(700, 900);
    const insets = FakeViewPadding(top: 24, left: 40, right: 30, bottom: 20);
    final row = find.byKey(const Key('row'));
    final last = find.byKey(const Key('last'));

    Future<void> pump(
      WidgetTester tester, {
      FakeViewPadding padding = insets,
      List<Widget>? slivers,
      Widget? body,
      Widget? bottom,
      ScrollController? controller,
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1
        ..padding = padding
        ..viewPadding = padding;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWaxTheme(),
          home: WaxScaffold(
            title: 'Page',
            largeTitle: false,
            controller: controller,
            bottom: bottom,
            body: body,
            slivers: body == null
                ? slivers ??
                      <Widget>[
                        const SliverToBoxAdapter(
                          child: SizedBox(key: Key('row'), height: 40),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 2000)),
                        const SliverToBoxAdapter(
                          child: SizedBox(key: Key('last'), height: 40),
                        ),
                      ]
                : null,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets("the page's rows clear the side insets", (tester) async {
      await pump(tester);
      final rect = tester.getRect(row);
      expect(rect.left, 40);
      expect(rect.right, size.width - 30);
      expect(rect.top, 24 + kToolbarHeight, reason: 'the bar takes the top');
    });

    testWidgets("the page's end scrolls clear of the bottom inset", (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pump(tester, controller: controller);
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      expect(tester.getRect(last).bottom, size.height - 20);
    });

    testWidgets('a bar along its foot takes the bottom inset, not the page', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pump(
        tester,
        controller: controller,
        bottom: const SizedBox(key: Key('foot'), height: 40),
      );
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      final foot = tester.getRect(find.byKey(const Key('foot')));
      expect(foot.bottom, size.height);
      expect(tester.getRect(last).bottom, foot.top);
    });

    testWidgets('a list inside the page pads none of the insets the page '
        'and its bar have taken', (tester) async {
      await pump(
        tester,
        body: ListView(
          shrinkWrap: true,
          children: const <Widget>[SizedBox(key: Key('row'), height: 40)],
        ),
      );
      final list = tester.getRect(find.byType(ListView));
      expect(list.top, 24 + kToolbarHeight);
      expect(list.height, 40, reason: 'its ends');
      expect(tester.getRect(row).left, 40, reason: 'its rows');
    });

    testWidgets('a list filling the page pads none of them either', (
      tester,
    ) async {
      await pump(
        tester,
        slivers: <Widget>[
          SliverFillRemaining(
            hasScrollBody: true,
            child: ListView(
              children: const <Widget>[SizedBox(key: Key('row'), height: 40)],
            ),
          ),
        ],
      );
      final list = tester.getRect(find.byType(ListView));
      expect(tester.getRect(row).top, list.top, reason: 'its top');
      expect(list.bottom, size.height - 20, reason: 'its foot');
      expect(tester.getRect(row).left, 40, reason: 'its rows');
    });
  });

  group('a page that fills, with a bar along its foot', () {
    const size = Size(700, 900);
    const insets = FakeViewPadding(left: 40, right: 30, bottom: 20);
    final bar = find.byType(WaxFootBar);
    final controls = find.byKey(const Key('controls'));
    final body = find.byKey(const Key('body'));
    final list = find.byKey(const Key('list'));
    final back = find.byType(WaxIconButton);

    const footed = WaxFootedPane(
      body: SizedBox.expand(key: Key('body')),
      foot: WaxFootBar(child: SizedBox(key: Key('controls'), height: 40)),
    );

    /// Two panes side by side, a list at the start and [footed] at the end.
    const split = Row(
      children: <Widget>[
        Expanded(
          child: WaxInsetsTaken(
            end: true,
            child: SafeArea(
              top: false,
              child: SizedBox.expand(key: Key('list')),
            ),
          ),
        ),
        Expanded(child: WaxInsetsTaken(start: true, child: footed)),
      ],
    );

    Future<void> pump(
      WidgetTester tester, {
      Widget? fill,
      List<Widget>? slivers,
      Widget? bottom,
      TextDirection direction = TextDirection.ltr,
      bool largeTitle = false,
      String title = 'Page',
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1
        ..padding = insets
        ..viewPadding = insets;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWaxTheme(),
          builder: (context, child) =>
              Directionality(textDirection: direction, child: child!),
          home: WaxScaffold(
            title: title,
            largeTitle: largeTitle,
            onBack: () {},
            fill: fill,
            slivers: slivers,
            bottom: bottom,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets("the bar's surface runs to the window's edges and its "
        'controls keep inside the insets', (tester) async {
      await pump(tester, fill: footed);
      final box = tester.getRect(bar);
      expect((box.left, box.right, box.bottom), (0.0, 700.0, 900.0));
      final inner = tester.getRect(controls);
      expect((inner.left, inner.right, inner.bottom), (40.0, 670.0, 880.0));
      final above = tester.getRect(body);
      expect(
        (above.left, above.right, above.bottom),
        (40.0, 670.0, box.top),
        reason: 'what stands above it takes the sides',
      );
    });

    for (final direction in TextDirection.values) {
      testWidgets('${direction.name}: under the end pane of two, it reaches '
          'only the edges that pane stands against', (tester) async {
        await pump(tester, fill: split, direction: direction);
        final ltr = direction == TextDirection.ltr;
        final box = tester.getRect(bar);
        final inner = tester.getRect(controls);
        final start = tester.getRect(list);
        if (ltr) {
          expect((box.left, box.right, box.bottom), (350.0, 700.0, 900.0));
          expect((inner.left, inner.right), (350.0, 670.0));
          expect((start.left, start.right), (40.0, 350.0), reason: 'the list');
        } else {
          expect((box.left, box.right, box.bottom), (0.0, 350.0, 900.0));
          expect((inner.left, inner.right), (40.0, 350.0));
          expect((start.left, start.right), (350.0, 670.0), reason: 'the list');
        }
        expect(inner.bottom, 880.0);
        expect(start.bottom, 880.0, reason: 'the list takes the bottom');
      });
    }

    testWidgets('with no bar to draw, the pane takes the bottom inset too', (
      tester,
    ) async {
      await pump(
        tester,
        fill: const WaxFootedPane(body: SizedBox.expand(key: Key('body'))),
      );
      final rect = tester.getRect(body);
      expect((rect.left, rect.right, rect.bottom), (40.0, 670.0, 880.0));
    });

    testWidgets("under the page's own bar, the fill is handed none of the "
        'bottom inset', (tester) async {
      await pump(
        tester,
        fill: footed,
        bottom: const SizedBox(key: Key('foot'), height: 40),
      );
      final foot = tester.getRect(find.byKey(const Key('foot')));
      expect(tester.getRect(bar).bottom, foot.top);
      expect(tester.getRect(controls).bottom, foot.top);
    });

    for (final largeTitle in <bool>[false, true]) {
      testWidgets('its own bar on top sits as it does on any page'
          '${largeTitle ? ', its large title too' : ''}', (tester) async {
        final title = find.text('Page');
        await pump(tester, fill: footed, largeTitle: largeTitle);
        final filled = (tester.getRect(back), tester.getRect(title));
        await pump(
          tester,
          slivers: const <Widget>[SliverToBoxAdapter(child: SizedBox())],
          largeTitle: largeTitle,
        );
        expect(filled, (tester.getRect(back), tester.getRect(title)));
        expect(filled.$1.left, 40, reason: 'inside the side inset');
      });
    }

    for (final direction in TextDirection.values) {
      testWidgets('${direction.name}: a long large title wraps inside both '
          'side insets', (tester) async {
        const long =
            'A title long enough to run past the end of any window it is '
            'drawn in';
        await pump(
          tester,
          fill: footed,
          largeTitle: true,
          direction: direction,
          title: long,
        );
        final rect = tester.getRect(find.text(long));
        // The back control's room at the start, inside the start inset.
        if (direction == TextDirection.ltr) {
          expect(rect.left, greaterThanOrEqualTo(40 + WaxSpace.s48));
          expect(rect.right, lessThanOrEqualTo(700 - 30.0), reason: 'the end');
        } else {
          expect(rect.right, lessThanOrEqualTo(700 - 30 - WaxSpace.s48));
          expect(rect.left, greaterThanOrEqualTo(40.0), reason: 'the end');
        }
      });
    }

    testWidgets('rows of a page that scrolls are cut at the line of the '
        'bottom inset it took', (tester) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1
        ..padding = const FakeViewPadding(bottom: 30)
        ..viewPadding = const FakeViewPadding(bottom: 30);
      addTearDown(tester.view.reset);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      const row = Color(0xFFFF0000);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWaxTheme(),
          home: WaxScaffold(
            title: 'Page',
            largeTitle: false,
            controller: controller,
            slivers: <Widget>[
              SliverList.list(
                children: <Widget>[
                  for (var i = 0; i < 40; i++)
                    const SizedBox(height: 56, child: ColoredBox(color: row)),
                ],
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      // A row from 840 to 896 straddles the line at 870.
      final first = tester.getTopLeft(find.byType(ColoredBox).first).dy;
      controller.jumpTo(first + 56 * 15 - 840);
      await tester.pump();
      final out = await tester.runAsync(() async {
        final image = await captureImage(tester.element(find.byType(Scaffold)));
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        int red(double y) =>
            data.getUint8(((y.floor() * image.width) + 350) * 4);
        return (above: red(865), band: red(875));
      });
      expect(out!.above, 0xFF, reason: 'the row above the line');
      expect(out.band, isNot(0xFF), reason: 'nothing of it below the line');
    });
  });

  group('the floating button', () {
    Future<void> pumpWith(WidgetTester tester, Widget floating) =>
        tester.pumpWidget(
          MaterialApp(
            theme: buildWaxTheme(),
            home: WaxScaffold(
              title: 'T',
              body: const SizedBox(height: 200),
              floating: floating,
            ),
          ),
        );

    testWidgets('a button of another key swaps in as another button', (
      tester,
    ) async {
      await pumpWith(tester, const Text('first', key: ValueKey<String>('a')));
      await tester.pumpAndSettle();

      await pumpWith(tester, const Text('second', key: ValueKey<String>('b')));
      await tester.pump(const Duration(milliseconds: 50));

      // The Scaffold's swap: the old one leaves as the new one arrives.
      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('first'), findsNothing);
    });

    testWidgets('a button of the same key is updated in place', (tester) async {
      final key = GlobalKey();
      await pumpWith(tester, Text('first', key: key));
      await tester.pumpAndSettle();

      await pumpWith(tester, Text('second', key: key));
      await tester.pump();

      expect(find.text('first'), findsNothing);
      expect(find.text('second'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the page messages hook', () {
    Future<void> pump(WidgetTester tester, Widget page) =>
        tester.pumpWidget(MaterialApp(theme: buildWaxTheme(), home: page));

    testWidgets('a WaxScaffold hands its page to present, inside its own '
        'semantics node', (tester) async {
      var presented = 0;
      await pump(
        tester,
        WaxPageMessages(
          present: (page) {
            presented++;
            return _Presented(child: page);
          },
          child: const WaxScaffold(
            title: 'T',
            semanticsId: 'page',
            body: SizedBox(height: 200),
          ),
        ),
      );

      expect(presented, 1);
      final over = find.byType(_Presented);
      expect(
        find.descendant(of: over, matching: find.byType(Scaffold)),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: over,
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.identifier == 'page',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a WaxScaffold with no hook above is its Scaffold, '
        'untouched', (tester) async {
      await pump(
        tester,
        const WaxScaffold(
          title: 'T',
          semanticsId: 'page',
          body: SizedBox(height: 200),
        ),
      );

      final scaffold = tester.element(find.byType(Scaffold));
      Widget? parent;
      scaffold.visitAncestorElements((element) {
        parent = element.widget;
        return false;
      });
      expect(
        parent,
        isA<Semantics>().having((w) => w.properties.identifier, 'id', 'page'),
      );
    });

    testWidgets('a new hook presents the page again', (tester) async {
      final presents = <String>[];
      Widget hooked(String name) => WaxPageMessages(
        present: (page) {
          presents.add(name);
          return page;
        },
        child: const WaxScaffold(title: 'T', body: SizedBox(height: 200)),
      );
      await pump(tester, hooked('first'));
      await pump(tester, hooked('second'));

      expect(presents, ['first', 'second']);
    });

    testWidgets('a WaxScaffold hands its floating button to clear, which '
        'the Scaffold lays out where it lays the button itself', (
      tester,
    ) async {
      final button = WaxFab(
        glyph: WaxIcons.addPerson,
        label: 'Invite',
        onPressed: () {},
      );
      await pump(
        tester,
        WaxScaffold(
          title: 'T',
          body: const SizedBox(height: 200),
          floating: button,
        ),
      );
      final bare = tester.getRect(find.byType(WaxFab));

      await pump(
        tester,
        WaxPageMessages(
          present: (page) => page,
          clear: (button) => _Cleared(child: button),
          child: WaxScaffold(
            title: 'T',
            body: const SizedBox(height: 200),
            floating: button,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.ancestor(of: find.byType(WaxFab), matching: find.byType(_Cleared)),
        findsOneWidget,
      );
      expect(tester.getRect(find.byType(WaxFab)), bare);
    });
  });
}

class _Presented extends StatelessWidget {
  const _Presented({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _Cleared extends StatelessWidget {
  const _Cleared({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
