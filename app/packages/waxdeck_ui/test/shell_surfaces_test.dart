import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/rendering.dart' show RendererBinding;
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

    group('the wide bar', () {
      var seeks = 0;
      Duration? lastSeek;
      var held = 0;
      var queued = 0;
      var expanded = 0;
      Future<TestGesture> pumpWide(
        WidgetTester tester, {
        bool seekable = true,
        bool level = false,
      }) async {
        seeks = held = queued = expanded = 0;
        lastSeek = null;
        await _pump(
          tester,
          DeckBar(
            now: level
                ? const NowPlayingData(
                    title: 'Salt Harbour',
                    subtitle: 'Nightjar',
                    position: Duration(minutes: 2, seconds: 41),
                    duration: Duration(minutes: 4, seconds: 5),
                    playing: true,
                    volume: 0.5,
                  )
                : _music,
            sizeClass: WaxSizeClass.wide,
            // No shuffle: it is drawn greyed.
            actions: DeckBarActions(
              onPlayPause: () {},
              onExpand: () => expanded++,
              onSeek: seekable
                  ? (to) {
                      seeks++;
                      lastSeek = to;
                    }
                  : null,
              onVolume: level ? (_) {} : null,
              onLongPress: () => held++,
              onQueue: () => queued++,
            ),
          ),
        );
        final mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          pointer: 1,
        );
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        return mouse;
      }

      Future<MouseCursor?> cursorAt(
        WidgetTester tester,
        TestGesture mouse,
        Offset at,
      ) async {
        await mouse.moveTo(at);
        await tester.pump();
        return RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);
      }

      testWidgets('points a hand wherever a click opens the player', (
        tester,
      ) async {
        final mouse = await pumpWide(tester);
        final transport = tester.getRect(
          find
              .ancestor(
                of: find.bySemanticsLabel('Pause'),
                matching: find.byType(Row),
              )
              .first,
        );
        expect(
          await cursorAt(
            tester,
            mouse,
            tester.getCenter(find.text('Salt Harbour').first),
          ),
          SystemMouseCursors.click,
        );
        expect(
          await cursorAt(
            tester,
            mouse,
            Offset(transport.right + 24, transport.center.dy),
          ),
          SystemMouseCursors.click,
        );
        expect(
          await cursorAt(
            tester,
            mouse,
            tester.getCenter(find.bySemanticsLabel('Shuffle off')),
          ),
          SystemMouseCursors.basic,
          reason: 'a greyed control does nothing, and says so',
        );
      });

      testWidgets('a click that drifts still presses the control', (
        tester,
      ) async {
        // A mouse's slop is a pixel, so a bar-wide swipe would take
        // every click that moved at all from the control under it.
        final mouse = await pumpWide(tester);
        await mouse.moveTo(tester.getCenter(find.bySemanticsLabel('Queue')));
        await mouse.down(tester.getCenter(find.bySemanticsLabel('Queue')));
        await mouse.moveBy(const Offset(0, 3));
        await mouse.up();
        await tester.pump();
        expect(queued, 1);
      });

      testWidgets('a held press on the track still scrubs', (tester) async {
        // A hold anywhere on the bar would beat a seek that waited
        // before it moved.
        final mouse = await pumpWide(tester);
        final track = tester.getCenter(find.bySemanticsLabel('Position'));
        await mouse.moveTo(track);
        await mouse.down(track);
        await tester.pump(const Duration(seconds: 1));
        await mouse.moveBy(const Offset(40, 0));
        await tester.pump();
        await mouse.up();
        await tester.pump();
        expect(seeks, greaterThan(0));
        expect(held, 0);
      });

      testWidgets('a track it cannot seek shows the arrow and opens nothing', (
        tester,
      ) async {
        final mouse = await pumpWide(tester, seekable: false);
        final track = tester.getCenter(find.bySemanticsLabel('Position'));
        expect(
          await cursorAt(tester, mouse, track),
          SystemMouseCursors.basic,
          reason: 'a greyed track does nothing, and says so',
        );
        await mouse.down(track);
        await mouse.up();
        await tester.pump();
        expect(expanded, 0, reason: 'a greyed track is not a way in');
      });

      testWidgets('a hold on what is playing opens the item menu', (
        tester,
      ) async {
        await pumpWide(tester);
        await tester.longPress(find.text('Salt Harbour').first);
        await tester.pump();
        expect(held, 1);
        expect(expanded, 0);
      });

      // Where a swipe up is a scroll or a scrub and not a way in: the
      // blank band beside the transport, and both tracks.
      final scrolls = <String, Offset Function(WidgetTester)>{
        'the blank band beside the transport': (tester) {
          final transport = tester.getRect(
            find
                .ancestor(
                  of: find.bySemanticsLabel('Pause'),
                  matching: find.byType(Row),
                )
                .first,
          );
          return Offset(transport.right + 24, transport.center.dy);
        },
        'the seek track': (tester) =>
            tester.getCenter(find.bySemanticsLabel('Position')),
        'the volume slider': (tester) =>
            tester.getCenter(find.bySemanticsLabel('Volume')),
      };
      for (final MapEntry(key: name, value: spot) in scrolls.entries) {
        testWidgets('a touch fling up over $name opens nothing', (
          tester,
        ) async {
          await pumpWide(tester, level: true);
          await tester.flingFrom(spot(tester), const Offset(0, -80), 1000);
          await tester.pump();
          expect(expanded, 0);
        });

        testWidgets('a trackpad swipe up over $name opens nothing', (
          tester,
        ) async {
          await pumpWide(tester, level: true);
          await tester.trackpadFlingFrom(
            spot(tester),
            const Offset(0, -80),
            1000,
          );
          await tester.pump();
          expect(expanded, 0, reason: 'a two-finger scroll is not a way in');
        });
      }

      testWidgets('a touch drag that starts steeply up the seek track seeks', (
        tester,
      ) async {
        await pumpWide(tester);
        final start = tester.getCenter(find.bySemanticsLabel('Position'));
        final finger = await tester.startGesture(start);
        var at = Duration.zero;
        Future<void> move(Offset by) async {
          at += const Duration(milliseconds: 16);
          await finger.moveBy(by, timeStamp: at);
          await tester.pump(const Duration(milliseconds: 16));
        }

        // More up than along, then along the track for long enough that the
        // release carries no upward speed.
        await move(const Offset(4, -24));
        for (var i = 0; i < 12; i++) {
          await move(const Offset(8, 0));
        }
        await finger.up();
        await tester.pump();
        expect(expanded, 0, reason: 'the player stayed shut');
        expect(seeks, 1);
        expect(
          lastSeek,
          greaterThan(_music.duration * 0.6),
          reason: 'the track followed the finger to the right of the middle',
        );
      });

      testWidgets('a touch fling up over what is playing opens the player', (
        tester,
      ) async {
        await pumpWide(tester);
        await tester.flingFrom(
          tester.getCenter(find.text('Salt Harbour').first),
          const Offset(0, -80),
          1000,
        );
        await tester.pump();
        expect(expanded, 1);
      });

      testWidgets('a trackpad swipe up over what is playing opens the player', (
        tester,
      ) async {
        await pumpWide(tester);
        await tester.trackpadFlingFrom(
          tester.getCenter(find.text('Salt Harbour').first),
          const Offset(0, -80),
          1000,
        );
        await tester.pump();
        expect(expanded, 1);
      });

      testWidgets(
        'a mouse drag up opens nothing, over the title or beside it',
        (tester) async {
          await pumpWide(tester);
          await tester.flingFrom(
            tester.getCenter(find.text('Salt Harbour').first),
            const Offset(0, -80),
            1000,
            deviceKind: PointerDeviceKind.mouse,
          );
          await tester.pump();
          await tester.flingFrom(
            scrolls.values.first(tester),
            const Offset(0, -80),
            1000,
            deviceKind: PointerDeviceKind.mouse,
          );
          await tester.pump();
          expect(expanded, 0, reason: 'a mouse swipes nothing');
        },
      );
    });

    testWidgets('a compact bar opens on a touch swipe up', (tester) async {
      var expanded = 0;
      await _pump(
        tester,
        DeckBar(
          now: _music,
          sizeClass: WaxSizeClass.compact,
          actions: DeckBarActions(
            onPlayPause: () {},
            onExpand: () => expanded++,
          ),
        ),
        size: const Size(420, 800),
      );
      await tester.flingFrom(
        tester.getCenter(find.text('Salt Harbour').first),
        const Offset(0, -60),
        1000,
      );
      await tester.pump();
      expect(expanded, 1);
    });
  });
}
