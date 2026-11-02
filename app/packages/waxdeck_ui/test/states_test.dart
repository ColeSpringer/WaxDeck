import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// A page-sized host, which is the shape these panes are drawn at: both
/// wrap a `Center` that fills whatever it is given.
Widget _host(Widget child) => MaterialApp(
  theme: buildWaxTheme(variant: WaxThemeVariant.dark),
  home: Scaffold(body: child),
);

/// The semantics node one identifier names.
SemanticsNode _node(WidgetTester tester, String id) {
  SemanticsNode? found;
  void walk(SemanticsNode node) {
    if (node.identifier == id) found = node;
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(tester.binding.rootElement!.renderObject!.debugSemantics!);
  expect(found, isNotNull, reason: 'no semantics node named $id');
  return found!;
}

void main() {
  // A container that merges its descendants takes their actions with
  // them, and both of these panes fill the viewport: on web a tappable
  // node draws flt-tappable with pointer-events over its whole rect, so
  // a click anywhere on an empty page fired the invitation's button.
  group('a full-page state pane', () {
    testWidgets('does not become one page-sized tap target', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        _host(
          EmptyState(
            title: 'Nothing here yet',
            message: 'Add something to see it.',
            actionLabel: 'Add',
            onAction: () => pressed++,
            semanticsId: 'empty',
            actionSemanticsId: 'empty-action',
          ),
        ),
      );
      final handle = tester.ensureSemantics();
      await tester.pump();

      final pane = _node(tester, 'empty');
      expect(
        pane.getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
        reason: 'the pane must not answer the button\'s tap',
      );
      // The button keeps a node of its own, so the action is still
      // reachable where it is drawn.
      expect(
        _node(
          tester,
          'empty-action',
        ).getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );

      // The boundary costs the container its merged text, so the label
      // has to be carried across with it or the pane announces nothing.
      expect(pane.label, contains('Nothing here yet'));
      expect(pane.label, contains('Add something to see it.'));
      // And the lines keep nodes of their own, so a reader can navigate
      // to them and a spec can find them by text.
      expect(find.text('Nothing here yet'), findsOne);
      expect(find.text('Add something to see it.'), findsOne);

      // A click on the far corner, nowhere near the button.
      await tester.tapAt(const Offset(8, 8));
      await tester.pump();
      expect(pressed, 0);

      handle.dispose();
    });

    testWidgets('an empty state with no message draws one line of text', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const EmptyState(title: 'Nothing here yet', semanticsId: 'empty'),
        ),
      );
      final handle = tester.ensureSemantics();
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(EmptyState),
          matching: find.byType(Text),
        ),
        findsOne,
      );
      expect(find.text('Nothing here yet'), findsOne);
      // The spoken name is the title alone, with no stray separator.
      expect(_node(tester, 'empty').label, 'Nothing here yet');

      handle.dispose();
    });

    testWidgets('announces the error rather than an empty live region', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          ErrorState(
            title: 'Could not load',
            message: 'The server did not answer.',
            onRetry: () {},
            semanticsId: 'error',
            retrySemanticsId: 'error-retry',
          ),
        ),
      );
      final handle = tester.ensureSemantics();
      await tester.pump();

      final pane = _node(tester, 'error');
      // The pair WaxBanner sets together: a live region that stopped
      // merging its descendants would announce an empty string on every
      // error, which no layout test would catch.
      expect(pane.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      expect(pane.label, contains('Could not load'));
      expect(pane.label, contains('The server did not answer.'));
      expect(find.text('The server did not answer.'), findsOne);
      expect(pane.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      expect(
        _node(
          tester,
          'error-retry',
        ).getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );

      handle.dispose();
    });
  });

  testWidgets('an error state still retrying draws its retry busy', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      _host(
        ErrorState(
          message: 'The server did not answer.',
          retrying: true,
          onRetry: () => presses++,
        ),
      ),
    );
    final retry = find.widgetWithText(WaxButton, 'Try again');
    // Working, not unavailable: the retry is already running.
    expect(tester.widget<WaxButton>(retry).busy, isTrue);
    await tester.tap(retry);
    await tester.pump();
    expect(presses, 0);
  });

  testWidgets('an empty state whose action is under way draws it busy', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        EmptyState(
          title: 'Nothing matches yet',
          actionLabel: 'Load more',
          actionBusy: true,
          onAction: () {},
        ),
      ),
    );
    final button = tester.widget<WaxButton>(find.byType(WaxButton));
    expect(button.busy, isTrue);
    expect(button.label, 'Load more');
  });

  group('a Load more footer', () {
    Widget footer({required bool loading, VoidCallback? onLoadMore}) => _host(
      ListView(
        children: <Widget>[
          LoadMoreFooter(
            label: 'Load more',
            loading: loading,
            semanticsId: 'more',
            onLoadMore: onLoadMore ?? () {},
          ),
        ],
      ),
    );

    Finder ghost() => find.byType(SkeletonShapes);

    testWidgets('offers the button alone while nothing loads', (tester) async {
      var asked = 0;
      await tester.pumpWidget(
        footer(loading: false, onLoadMore: () => asked++),
      );

      expect(ghost(), findsNothing);
      expect(
        tester.widget<WaxButton>(find.byType(WaxButton)).icon,
        WaxIcons.caretDown,
        reason: 'it points to where the rows land',
      );
      await tester.tap(find.byType(WaxButton));
      expect(asked, 1);
    });

    testWidgets('a press keeps its button, busy and focused, over the ghost', (
      tester,
    ) async {
      await tester.pumpWidget(footer(loading: false));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final button = tester.element(find.byType(WaxButton));
      bool focusedInButton() {
        var inside = false;
        FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
          inside = identical(e, button);
          return !inside;
        });
        return inside;
      }

      expect(focusedInButton(), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpWidget(footer(loading: true));
      await tester.pump();

      expect(tester.element(find.byType(WaxButton)), same(button));
      expect(tester.widget<WaxButton>(find.byType(WaxButton)).busy, isTrue);
      expect(focusedInButton(), isTrue);
      expect(ghost(), findsOneWidget);
      expect(
        tester.getRect(ghost()).top,
        greaterThanOrEqualTo(tester.getRect(find.byType(WaxButton)).bottom),
      );
    });

    testWidgets('a page a scroll asked for is the ghost alone', (tester) async {
      await tester.pumpWidget(footer(loading: true));
      await tester.pump();

      expect(find.byType(WaxButton), findsNothing);
      expect(ghost(), findsOneWidget);
    });

    testWidgets('a landed page ends the press', (tester) async {
      await tester.pumpWidget(footer(loading: false));
      await tester.tap(find.byType(WaxButton));
      await tester.pumpWidget(footer(loading: true));
      await tester.pumpWidget(footer(loading: false));
      // The next page is a scroll's.
      await tester.pumpWidget(footer(loading: true));
      await tester.pump();

      expect(find.byType(WaxButton), findsNothing);
      expect(ghost(), findsOneWidget);
    });
  });

  group('a ghost in a bounded host', () {
    // Six list rows are 336 tall: 40 of block and 16 of padding each.
    const rows = 6 * 56.0;

    testWidgets('shorter than its rows clips instead of overflowing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 90,
              child: SkeletonShapes(shape: SkeletonShape.list),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(SkeletonShapes)), const Size(400, 90));
      expect(
        find.descendant(
          of: find.byType(SkeletonShapes),
          matching: find.byType(ClipRect),
        ),
        findsOne,
        reason: 'the rows past the bottom edge are cut off, not drawn over',
      );
    });

    testWidgets('under a flexible it takes the room a column leaves', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 120,
              child: Column(
                children: <Widget>[
                  SizedBox(height: 60),
                  Flexible(
                    child: SkeletonShapes(shape: SkeletonShape.list, count: 3),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(SkeletonShapes)).height, 60);
    });

    testWidgets('in a dialog shrink-wraps to its rows', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => WaxButton(
              label: 'Open',
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const Dialog(
                  child: SkeletonShapes(shape: SkeletonShape.list),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      // The ghost animates forever, so the route's fade is played by
      // hand: judged at opacity 0 nothing has been painted yet.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(tester.takeException(), isNull);
      // The dialog's own room is far taller; a ghost that takes it all
      // makes a dialog that jumps when the content lands.
      expect(tester.getSize(find.byType(SkeletonShapes)).height, rows);
    });

    testWidgets('an unbounded host gets every row, as before', (tester) async {
      await tester.pumpWidget(
        _host(
          const SingleChildScrollView(
            child: SkeletonShapes(shape: SkeletonShape.list),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(SkeletonShapes)).height, rows);
    });

    testWidgets('a filling sliver still sizes it by its rows', (tester) async {
      tester.view.physicalSize = const Size(800, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          const CustomScrollView(
            slivers: <Widget>[
              SliverFillRemaining(
                hasScrollBody: false,
                child: SkeletonShapes(shape: SkeletonShape.list),
              ),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      // Taller than the window: the page scrolls to the last row.
      expect(tester.getSize(find.byType(SkeletonShapes)).height, rows);
    });
  });

  group('a state pane in a short space', () {
    const box = Key('box');
    Widget empty() => EmptyState(
      glyph: WaxIcons.search,
      title: 'Nothing here yet',
      message: 'Add something to see it, and it will be listed here.',
      actionLabel: 'Add',
      onAction: () {},
    );
    Widget error() => ErrorState(
      title: 'Could not load',
      message: 'The server did not answer, so nothing could be listed.',
      detail: 'GET /api/v1/items 503',
      onRetry: () {},
    );
    final panes = <(String, Widget Function(), String, String)>[
      ('an empty state', empty, 'Nothing here yet', 'Add'),
      ('an error state', error, 'Could not load', 'Try again'),
    ];

    Future<void> sized(WidgetTester tester, Size size, Widget child) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(child));
    }

    for (final (name, pane, heading, button) in panes) {
      testWidgets('$name stays centred where there is room', (tester) async {
        await sized(tester, const Size(800, 600), pane());

        expect(tester.takeException(), isNull);
        final top = tester.getTopLeft(find.text(heading)).dy;
        final bottom = tester.getBottomLeft(find.text(button)).dy;
        expect((top + bottom) / 2, closeTo(300, 24));
        expect(tester.getCenter(find.text(heading)).dx, closeTo(400, 1));
      });

      testWidgets('$name scrolls within a box shorter than itself', (
        tester,
      ) async {
        await sized(
          tester,
          const Size(800, 600),
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(key: box, height: 120, child: pane()),
          ),
        );

        expect(tester.takeException(), isNull);
        final room = tester.getRect(find.byKey(box));
        expect(tester.getRect(find.text(button)).top, greaterThan(room.bottom));
        await tester.drag(find.text(heading), const Offset(0, -400));
        await tester.pump();
        final reached = tester.getRect(find.text(button));
        expect(reached.top, greaterThanOrEqualTo(room.top));
        expect(reached.bottom, lessThanOrEqualTo(room.bottom));
      });

      testWidgets('$name in an unbounded host takes only its own height', (
        tester,
      ) async {
        await sized(
          tester,
          const Size(800, 600),
          SingleChildScrollView(
            child: Column(
              children: <Widget>[
                pane(),
                const SizedBox(key: box, height: 10),
              ],
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(
          tester.getTopLeft(find.byKey(box)).dy,
          lessThan(400),
          reason: 'sized by its content, not by the window',
        );
      });
    }

    // Long enough to wrap at a phone's width, so even an upright phone at
    // large text measures the pane short when asked at the window's width.
    const longTitle =
        'Administrators only, and this title is long enough to wrap';
    const longMessage =
        'This area is for the people who run this server. Ask one of them '
        'if you need something changed here, or go back to your library.';
    final longPanes = <(String, Widget Function(), String)>[
      (
        'an empty state',
        () => EmptyState(
          glyph: WaxIcons.search,
          title: longTitle,
          message: longMessage,
          actionLabel: 'Back to the library',
          onAction: () {},
        ),
        'Back to the library',
      ),
      (
        'an error state',
        () => ErrorState(
          title: longTitle,
          message: longMessage,
          detail: 'GET /api/v1/items 503',
          onRetry: () {},
        ),
        'Try again',
      ),
    ];

    // A filling sliver asks its child how tall it wants to be at the
    // window's width, not at the pane's narrower column. Answered at the
    // window's width the pane came back short and scrolled within itself,
    // a scroll trap inside the page, instead of lengthening the page.
    for (final (name, pane, button) in longPanes) {
      for (final (label, size, scale) in <(String, Size, double)>[
        ('a short wide window', const Size(1200, 240), 1.0),
        ('a phone on its side at large text', const Size(900, 400), 2.0),
        ('an upright phone at large text', const Size(412, 700), 2.0),
      ]) {
        testWidgets('$name under a filling sliver on $label lengthens the '
            'page', (tester) async {
          final page = ScrollController();
          addTearDown(page.dispose);
          await sized(
            tester,
            size,
            Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: CustomScrollView(
                  controller: page,
                  slivers: <Widget>[
                    const SliverToBoxAdapter(child: SizedBox(height: 56)),
                    SliverFillRemaining(hasScrollBody: false, child: pane()),
                  ],
                ),
              ),
            ),
          );

          expect(tester.takeException(), isNull);
          final inner = tester
              .state<ScrollableState>(
                find.descendant(
                  of: find.byType(SliverFillRemaining),
                  matching: find.byType(Scrollable),
                ),
              )
              .position;
          expect(inner.maxScrollExtent, 0, reason: 'nothing to scroll within');
          page.jumpTo(page.position.maxScrollExtent);
          await tester.pump();
          final reached = tester.getRect(find.text(button));
          expect(reached.bottom, lessThanOrEqualTo(size.height));
          expect(reached.top, greaterThanOrEqualTo(0));
        });
      }
    }
  });

  group('a filter chip row', () {
    testWidgets('keeps one node per chip, and none for the row', (
      tester,
    ) async {
      final picked = <String>[];
      await tester.pumpWidget(
        _host(
          Align(
            alignment: Alignment.topCenter,
            child: FilterChipRow(
              chips: const <WaxFilterChip>[
                WaxFilterChip(
                  name: 'all',
                  label: 'All',
                  semanticsId: 'chip-all',
                ),
                WaxFilterChip(
                  name: 'music',
                  label: 'Music',
                  semanticsId: 'chip-music',
                ),
              ],
              selected: 'all',
              onSelect: picked.add,
              semanticsId: 'chips',
            ),
          ),
        ),
      );
      final handle = tester.ensureSemantics();
      await tester.pump();

      // Merged, the row answered to whichever chip merged last: a press
      // on the row selected a chip nobody aimed at, and the search
      // screen's own e2e passed because of it.
      expect(
        _node(
          tester,
          'chips',
        ).getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
      );
      for (final id in <String>['chip-all', 'chip-music']) {
        expect(
          _node(tester, id).getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
          reason: '$id must stay individually reachable',
        );
      }

      handle.dispose();
    });
  });
}
