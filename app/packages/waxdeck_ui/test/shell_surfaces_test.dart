import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

const _music = NowPlayingData(
  title: 'Salt Harbour',
  subtitle: 'Nightjar',
  position: Duration(minutes: 2, seconds: 41),
  duration: Duration(minutes: 4, seconds: 5),
  playing: true,
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWaxTheme(),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('banner', () {
    testWidgets('announces itself and runs its one action', (tester) async {
      // A live region, because a connection dropping is not something to
      // discover by exploring the page.
      final semantics = tester.ensureSemantics();
      var reloaded = 0;
      await _pump(
        tester,
        WaxBanner(
          tone: WaxBannerTone.notice,
          message: 'WaxDeck was updated. Reload to get the new version.',
          actionLabel: 'Reload',
          onAction: () => reloaded++,
        ),
      );

      expect(
        tester
            .getSemantics(
              find.bySemanticsLabel(
                'WaxDeck was updated. Reload to get the new version.',
              ),
            )
            .getSemanticsData()
            .toString(),
        contains('isLiveRegion'),
      );

      await tester.tap(find.bySemanticsLabel('Reload'));
      await tester.pump();
      expect(reloaded, 1);
      semantics.dispose();
    });

    testWidgets('offers a dismiss only where one is honest', (tester) async {
      await _pump(
        tester,
        const WaxBanner(message: 'Reconnecting to the server.'),
      );
      expect(find.bySemanticsLabel('Dismiss'), findsNothing);

      var dismissed = 0;
      await _pump(
        tester,
        WaxBanner(
          message: 'Reconnecting to the server.',
          onDismiss: () => dismissed++,
        ),
      );
      await tester.tap(find.bySemanticsLabel('Dismiss'));
      await tester.pump();
      expect(dismissed, 1);
    });
  });

  group('side panel', () {
    testWidgets('is a named region that can be closed', (tester) async {
      var closed = 0;
      await _pump(
        tester,
        SizedBox(
          width: 360,
          child: WaxSidePanel(
            title: 'Queue',
            onClose: () => closed++,
            child: const Center(child: Text('up next')),
          ),
        ),
      );

      expect(find.text('Queue'), findsOneWidget);
      expect(find.text('up next'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Close panel'));
      await tester.pump();
      expect(closed, 1);
    });
  });

  group('deck bar', () {
    testWidgets('draws no control for a surface nobody wired', (tester) async {
      // A greyed button that will never do anything reads as broken; the
      // transport is the opposite case and keeps its controls, because a
      // bar that loses its next button on the last track moves under the
      // hand.
      await _pump(
        tester,
        DeckBar(
          now: _music,
          sizeClass: WaxSizeClass.wide,
          actions: DeckBarActions(onPlayPause: () {}, onQueue: () {}),
        ),
      );

      expect(find.bySemanticsLabel('Queue'), findsOneWidget);
      expect(find.bySemanticsLabel('Lyrics'), findsNothing);
      expect(find.bySemanticsLabel('More'), findsNothing);
      expect(find.bySemanticsLabel('Next'), findsOneWidget);
    });

    testWidgets('leaves the position to the control that owns it', (
      tester,
    ) async {
      // The bar's own value would re-announce at every tick, which is
      // noise; the seek bar says where the item stands, as a spoken time.
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        DeckBar(
          now: _music,
          sizeClass: WaxSizeClass.wide,
          actions: DeckBarActions(onPlayPause: () {}, onSeek: (_) {}),
        ),
      );

      final bar = tester
          .getSemantics(find.bySemanticsLabel('Now playing bar'))
          .getSemanticsData();
      expect(bar.value, contains('Salt Harbour'));
      expect(bar.value, isNot(contains('minute')));
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Position'))
            .getSemanticsData()
            .value,
        '2 minutes 41 seconds of 4 minutes 5 seconds',
      );
      semantics.dispose();
    });

    testWidgets('ticks from its ticker, not from its data', (tester) async {
      final ticker = ValueNotifier<Duration>(Duration.zero);
      addTearDown(ticker.dispose);
      await _pump(
        tester,
        DeckBar(
          now: _music,
          sizeClass: WaxSizeClass.compact,
          positionTicker: ticker,
          actions: DeckBarActions(onPlayPause: () {}),
        ),
        size: const Size(420, 800),
      );

      double progress() => tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value!;
      expect(progress(), 0, reason: 'the ticker is where it starts');

      ticker.value = const Duration(minutes: 2, seconds: 3);
      await tester.pump();
      expect(progress(), closeTo(0.5, 0.01));
    });

    testWidgets('the offer resumes or is turned down', (tester) async {
      var resumed = 0;
      var dismissed = 0;
      await _pump(
        tester,
        DeckBarOffer(
          title: 'Salt Harbour',
          subtitle: 'Nightjar',
          onResume: () => resumed++,
          onDismiss: () => dismissed++,
        ),
        size: const Size(420, 800),
      );

      await tester.tap(find.bySemanticsLabel('Resume'));
      await tester.tap(find.bySemanticsLabel('Not now'));
      await tester.pump();
      expect(resumed, 1);
      expect(dismissed, 1);
    });

    testWidgets('a held bar opens the item menu', (tester) async {
      // The gesture has a button beside it, always: the overflow runs
      // the same handler.
      var held = 0;
      await _pump(
        tester,
        DeckBar(
          now: _music,
          sizeClass: WaxSizeClass.compact,
          actions: DeckBarActions(
            onPlayPause: () {},
            onLongPress: () => held++,
          ),
        ),
        size: const Size(420, 800),
      );

      await tester.longPress(find.text('Salt Harbour'));
      await tester.pump();
      expect(held, 1);
    });
  });
}
