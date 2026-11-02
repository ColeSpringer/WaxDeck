import 'package:flutter/services.dart';
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

    testWidgets('an action in flight draws busy and takes no press', (
      tester,
    ) async {
      var presses = 0;
      await _pump(
        tester,
        WaxBanner(
          message: 'The directory could not be searched.',
          tone: WaxBannerTone.caution,
          actionLabel: 'Retry',
          actionBusy: true,
          onAction: () => presses++,
        ),
      );
      final action = find.widgetWithText(WaxButton, 'Retry');
      expect(tester.widget<WaxButton>(action).busy, isTrue);
      expect(find.byType(WaxSpinner), findsOneWidget);
      await tester.tap(action);
      await tester.pump();
      expect(presses, 0);
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

    testWidgets('its end timecode switches the span only when wired with '
        'a name', (tester) async {
      // A book's bar spans its chapter or the whole book; the control is
      // named for what a press does and valued with the length it shows.
      final semantics = tester.ensureSemantics();
      const book = NowPlayingData(
        title: 'There And Back Again',
        position: Duration(minutes: 10),
        duration: Duration(minutes: 30),
        playing: true,
        spanLabel: 'Show the whole book',
      );
      const ids = DeckBarIds(span: 'span');
      var toggled = 0;
      Future<void> pumpWith(NowPlayingData now, VoidCallback? onSpanToggle) =>
          _pump(
            tester,
            DeckBar(
              now: now,
              ids: ids,
              sizeClass: WaxSizeClass.wide,
              actions: DeckBarActions(
                onPlayPause: () {},
                onSeek: (_) {},
                onSpanToggle: onSpanToggle,
              ),
            ),
          );

      await pumpWith(book, () => toggled++);
      final span = find.bySemanticsIdentifier('span');
      expect(
        tester.getSemantics(span),
        isSemantics(
          label: 'Show the whole book',
          value: '30 minutes',
          isButton: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(span);
      await tester.pump();
      expect(toggled, 1);
      // The keyboard's press is the same one: Enter on the focused control.
      final stop = tester.widget<FocusableActionDetector>(
        find
            .ancestor(
              of: find.text('30:00'),
              matching: find.byType(FocusableActionDetector),
            )
            .first,
      );
      stop.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(toggled, 2);

      // Either half missing leaves a readout.
      await pumpWith(book, null);
      expect(span, findsNothing);
      expect(find.text('30:00'), findsOneWidget);
      await pumpWith(
        const NowPlayingData(
          title: 'There And Back Again',
          position: Duration(minutes: 10),
          duration: Duration(minutes: 30),
          playing: true,
        ),
        () => toggled++,
      );
      expect(span, findsNothing);
      expect(find.text('30:00'), findsOneWidget);
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

    testWidgets('an offer of something never played says so in its own '
        'heading', (tester) async {
      // Its heading is said first and stands in for a missing caption, so
      // no part of the offer names a place to pick up from.
      await _pump(
        tester,
        DeckBarOffer(
          title: 'Salt Harbour',
          heading: '1 queued item',
          onResume: () {},
          onDismiss: () {},
        ),
        size: const Size(420, 800),
      );

      expect(find.text('1 queued item'), findsOneWidget);
      expect(find.text('Pick up where you left off'), findsNothing);
      expect(
        find.bySemanticsLabel('1 queued item, Salt Harbour'),
        findsOneWidget,
      );
    });

    testWidgets('an offer says each of its lines once', (tester) async {
      // A count that is the whole title has no caption to repeat it.
      await _pump(
        tester,
        DeckBarOffer(
          title: '1 queued item',
          heading: '1 queued item',
          onResume: () {},
          onDismiss: () {},
        ),
        size: const Size(420, 800),
      );
      expect(find.text('1 queued item'), findsOneWidget);
      expect(find.bySemanticsLabel('1 queued item'), findsOneWidget);

      // Nor is the heading said twice by a caption that restates it.
      await _pump(
        tester,
        DeckBarOffer(
          title: 'Salt Harbour',
          subtitle: 'Pick up where you left off',
          onResume: () {},
          onDismiss: () {},
        ),
        size: const Size(420, 800),
      );
      expect(
        find.bySemanticsLabel('Pick up where you left off, Salt Harbour'),
        findsOneWidget,
      );
    });

    testWidgets('a subtitle that reads as the title is still drawn and '
        'said', (tester) async {
      // A self-titled song by an artist of the same name: the artist line
      // is a real one.
      await _pump(
        tester,
        DeckBarOffer(
          title: 'Weezer',
          subtitle: 'Weezer',
          onResume: () {},
          onDismiss: () {},
        ),
        size: const Size(420, 800),
      );
      expect(find.text('Weezer'), findsNWidgets(2));
      expect(
        find.bySemanticsLabel('Pick up where you left off, Weezer, Weezer'),
        findsOneWidget,
      );
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
