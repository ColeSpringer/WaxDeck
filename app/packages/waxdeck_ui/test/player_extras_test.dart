import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

const _now = NowPlayingData(
  title: 'Salt Harbour',
  subtitle: 'Nightjar',
  position: Duration(minutes: 2, seconds: 41),
  duration: Duration(minutes: 4, seconds: 5),
  playing: true,
);

const _lines = <LyricLine>[
  LyricLine(at: Duration.zero, text: 'The tide comes in'),
  LyricLine(at: Duration(seconds: 10), text: 'and the harbour lights go'),
  LyricLine(at: Duration(seconds: 20), text: 'out one by one'),
];

/// Peaks with a shape, so a painter that drew nothing would be visible
/// as a painter that drew nothing.
final _peaks = <double>[for (var i = 0; i < 200; i++) (i % 20) / 19];

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(800, 600),
  bool reducedMotion = false,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWaxTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          disableAnimations: reducedMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('lyrics', () {
    testWidgets('the line being sung is the one the position is in', (
      tester,
    ) async {
      final position = ValueNotifier(const Duration(seconds: 12));
      addTearDown(position.dispose);
      await _pump(
        tester,
        LyricsView(
          position: position,
          lines: _lines,
          lineSemanticsId: (index) => 'line-$index',
        ),
      );

      final semantics = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.bySemanticsIdentifier('line-1')),
        isSemantics(isSelected: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsIdentifier('line-2')),
        isSemantics(isSelected: false),
      );
      semantics.dispose();
    });

    testWidgets('the highlight follows the position without a rebuild', (
      tester,
    ) async {
      final position = ValueNotifier(Duration.zero);
      addTearDown(position.dispose);
      await _pump(
        tester,
        LyricsView(
          position: position,
          lines: _lines,
          lineSemanticsId: (index) => 'line-$index',
        ),
      );

      position.value = const Duration(seconds: 21);
      await tester.pump();

      final semantics = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.bySemanticsIdentifier('line-2')),
        isSemantics(isSelected: true),
      );
      semantics.dispose();
    });

    testWidgets('a line seeks to its own moment', (tester) async {
      final position = ValueNotifier(Duration.zero);
      addTearDown(position.dispose);
      Duration? sought;
      await _pump(
        tester,
        LyricsView(
          position: position,
          lines: _lines,
          onSeek: (at) => sought = at,
          lineSemanticsId: (index) => 'line-$index',
        ),
      );

      await tester.tap(find.text('out one by one'));
      expect(sought, const Duration(seconds: 20));
    });

    testWidgets('untimed words are a block, not a list that cannot follow', (
      tester,
    ) async {
      final position = ValueNotifier(Duration.zero);
      addTearDown(position.dispose);
      await _pump(
        tester,
        LyricsView(
          position: position,
          text: 'A verse with no timings at all',
          followSemanticsId: 'follow',
        ),
      );

      expect(find.text('A verse with no timings at all'), findsOneWidget);
      // Nothing to follow means no offer to resume following: the button
      // appears when a scroll takes over from the playhead, and there is
      // no playhead here.
      expect(find.bySemanticsIdentifier('follow'), findsNothing);
    });

    testWidgets('a row grows with the text, so two lines never clip', (
      tester,
    ) async {
      // A long line, so both of the two a row allows are used. At the
      // fixed 56 this row was, two lines of body text fit at exactly one
      // hundred percent and were cut at every notch above.
      //
      // Measured against what the type actually needs rather than
      // against what the row drew, and that is the whole point: a row
      // too short for its text does not overflow and does not throw. The
      // paragraph is handed a maximum height, reports it, and paints the
      // second line off the bottom - so `takeException` sees nothing and
      // the rendered size is the wrong one by construction.
      const line = LyricLine(
        at: Duration.zero,
        text:
            'and the harbour lights go out, one at a time, until the '
            'water is the only thing still moving',
      );
      for (final scale in <double>[1, 1.5, 2]) {
        final position = ValueNotifier(Duration.zero);
        addTearDown(position.dispose);
        await _pump(
          tester,
          LyricsView(position: position, lines: const <LyricLine>[line]),
          // Narrow, so the line has to wrap to the second row at all.
          size: const Size(320, 600),
          textScale: scale,
        );

        final drawn = tester.getSize(find.text(line.text));
        final needs = TextPainter(
          text: TextSpan(text: line.text, style: WaxType.body),
          textScaler: TextScaler.linear(scale),
          maxLines: 2,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: drawn.width);
        expect(
          needs.didExceedMaxLines || needs.height > 0,
          isTrue,
          reason: 'the sample line should wrap at ${scale}x',
        );

        final extent = tester
            .widget<ListView>(find.byType(ListView))
            .itemExtent!;
        expect(
          extent,
          greaterThanOrEqualTo(needs.height),
          reason:
              'two lines of body text want ${needs.height} px at ${scale}x '
              'and the row gives $extent',
        );
      }
    });

    testWidgets('a scroll takes over, and the offer puts it back', (
      tester,
    ) async {
      final position = ValueNotifier(Duration.zero);
      addTearDown(position.dispose);
      await _pump(
        tester,
        LyricsView(
          position: position,
          lines: <LyricLine>[
            for (var i = 0; i < 60; i++)
              LyricLine(
                at: Duration(seconds: i),
                text: 'Line $i',
              ),
          ],
          followSemanticsId: 'follow',
        ),
        size: const Size(400, 400),
      );

      expect(find.bySemanticsIdentifier('follow'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('follow'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('follow'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('follow'), findsNothing);
    });
  });

  group('visualizer', () {
    testWidgets('both modes draw without overflowing', (tester) async {
      for (final mode in WaxVisualizerMode.values) {
        final position = ValueNotifier(const Duration(minutes: 1));
        addTearDown(position.dispose);
        await _pump(
          tester,
          VisualizerStage(
            position: position,
            duration: const Duration(minutes: 4),
            peaks: _peaks,
            mode: mode,
            playing: true,
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull, reason: mode.name);
      }
    });

    testWidgets('a tap anywhere on the picture seeks there', (tester) async {
      final position = ValueNotifier(Duration.zero);
      addTearDown(position.dispose);
      Duration? sought;
      await _pump(
        tester,
        VisualizerStage(
          position: position,
          duration: const Duration(minutes: 4),
          peaks: _peaks,
          mode: WaxVisualizerMode.waveform,
          onSeek: (at) => sought = at,
        ),
        size: const Size(800, 600),
      );

      final stage = tester.getRect(find.byType(VisualizerStage));
      await tester.tapAt(Offset(stage.left + stage.width / 4, stage.center.dy));
      // A quarter of the way across a four-minute track is a minute in,
      // give or take the pixel the tap landed on.
      expect(sought!.inSeconds, closeTo(60, 2));
    });

    testWidgets('a scrub previews and commits once, not once per frame', (
      tester,
    ) async {
      final position = ValueNotifier(Duration.zero);
      addTearDown(position.dispose);
      final sought = <Duration>[];
      await _pump(
        tester,
        VisualizerStage(
          position: position,
          duration: const Duration(minutes: 4),
          peaks: _peaks,
          mode: WaxVisualizerMode.waveform,
          onSeek: sought.add,
        ),
        size: const Size(800, 600),
      );

      final stage = tester.getRect(find.byType(VisualizerStage));
      final gesture = await tester.startGesture(
        Offset(stage.left + 40, stage.center.dy),
      );
      for (var i = 1; i <= 12; i++) {
        await gesture.moveBy(const Offset(40, 0));
        await tester.pump();
      }
      // Twelve pointer events, and the engine has heard nothing: a seek
      // per drag frame is what this shape exists to avoid.
      expect(sought, isEmpty);

      await gesture.up();
      await tester.pump();
      expect(sought, hasLength(1));
      // Where the finger left off: 40 plus twelve moves of 40 is 520 of
      // 800, which is most of the way through a four-minute track.
      expect(sought.single.inSeconds, closeTo(156, 4));
    });

    testWidgets('a press held and then dragged commits once, at the end', (
      tester,
    ) async {
      final position = ValueNotifier(Duration.zero);
      addTearDown(position.dispose);
      final sought = <Duration>[];
      await _pump(
        tester,
        VisualizerStage(
          position: position,
          duration: const Duration(minutes: 4),
          peaks: _peaks,
          mode: WaxVisualizerMode.waveform,
          onSeek: sought.add,
        ),
        size: const Size(800, 600),
      );

      final stage = tester.getRect(find.byType(VisualizerStage));
      final gesture = await tester.startGesture(
        Offset(stage.left + 40, stage.center.dy),
      );
      // Held past the press timeout, so the tap declares itself before
      // the drag takes the gesture off it. The cancel that follows must
      // drop the preview rather than seek to where the finger landed.
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveBy(const Offset(400, 0));
      await tester.pump();
      expect(sought, isEmpty);

      await gesture.up();
      await tester.pump();
      expect(sought, hasLength(1));
      expect(sought.single.inSeconds, closeTo(132, 4));
    });

    testWidgets('and the picture follows the finger while it is down', (
      tester,
    ) async {
      final position = ValueNotifier(Duration.zero);
      addTearDown(position.dispose);
      await _pump(
        tester,
        VisualizerStage(
          position: position,
          duration: const Duration(minutes: 4),
          peaks: _peaks,
          mode: WaxVisualizerMode.waveform,
          onSeek: (_) {},
        ),
        size: const Size(800, 600),
      );

      final stage = tester.getRect(find.byType(VisualizerStage));
      final gesture = await tester.startGesture(
        Offset(stage.left + 400, stage.center.dy),
      );
      await tester.pump();
      // The engine keeps ticking underneath during a scrub, and it must
      // not drag the preview back out from under the finger.
      position.value = const Duration(seconds: 3);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await gesture.up();
      await tester.pump();
    });

    testWidgets('the platter turns while there is sound', (tester) async {
      final position = ValueNotifier(Duration.zero);
      addTearDown(position.dispose);
      await _pump(
        tester,
        VisualizerStage(
          position: position,
          duration: const Duration(minutes: 4),
          peaks: _peaks,
          mode: WaxVisualizerMode.platter,
          playing: true,
        ),
      );

      // Past the artwork's own fade, so what is left running is the
      // disc rather than anything transient the frame brought with it.
      await tester.pump(const Duration(seconds: 1));
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('and holds still when paused or under reduced motion', (
      tester,
    ) async {
      final position = ValueNotifier(Duration.zero);
      addTearDown(position.dispose);
      await _pump(
        tester,
        VisualizerStage(
          position: position,
          duration: const Duration(minutes: 4),
          peaks: _peaks,
          mode: WaxVisualizerMode.platter,
          playing: false,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.hasRunningAnimations, isFalse);

      await _pump(
        tester,
        VisualizerStage(
          position: position,
          duration: const Duration(minutes: 4),
          peaks: _peaks,
          mode: WaxVisualizerMode.platter,
          playing: true,
        ),
        reducedMotion: true,
      );
      await tester.pump(const Duration(seconds: 1));
      // Playing, and still: a continuous rotation is exactly the motion
      // the setting exists to stop.
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('car mode', () {
    testWidgets('draws on true black whatever theme it was opened from', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          // Light, which is the case that matters: a driver who set the
          // app to paper did not set their car to it.
          theme: buildWaxTheme(variant: WaxThemeVariant.light),
          home: CarModeScaffold(now: _now, onPlayPause: () {}),
        ),
      );
      await tester.pump();

      final inside = tester.element(find.byType(TransportCluster));
      expect(WaxColors.of(inside).canvas, WaxColors.oled.canvas);
    });

    testWidgets('the controls are the size a moving car needs', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWaxTheme(),
          home: CarModeScaffold(
            now: _now,
            onPlayPause: () {},
            ids: const PlayerIds(play: 'car-toggle'),
          ),
        ),
      );
      await tester.pump();

      final play = tester.getSize(find.bySemanticsIdentifier('car-toggle'));
      expect(play.width, CarModeScaffold.controlSize);
      expect(play.height, CarModeScaffold.controlSize);
    });

    testWidgets('a swipe left is next and a swipe right is previous', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var next = 0;
      var previous = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWaxTheme(),
          home: CarModeScaffold(
            now: _now,
            onPlayPause: () {},
            onNext: () => next++,
            onPrevious: () => previous++,
          ),
        ),
      );
      await tester.pump();

      await tester.fling(
        find.byType(CarModeScaffold),
        const Offset(-200, 0),
        800,
      );
      await tester.pumpAndSettle();
      expect(next, 1);
      expect(previous, 0);

      await tester.fling(
        find.byType(CarModeScaffold),
        const Offset(200, 0),
        800,
      );
      await tester.pumpAndSettle();
      expect(previous, 1);
    });

    testWidgets('the transport survives a short window at large text', (
      tester,
    ) async {
      // A landscape phone on a dashboard mount, which is the whole
      // scenario, at the text scale the layout system promises to
      // honour. The fixed column ran off the bottom here and took the
      // play button with it.
      for (final size in <Size>[
        Size(800, 360),
        Size(360, 360),
        Size(360, 320),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildWaxTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(2),
              ),
              child: CarModeScaffold(
                now: const NowPlayingData(
                  title: 'A Really Quite Long Track Title That Wraps',
                  subtitle: 'Some Artist With A Long Name',
                  position: Duration(minutes: 2),
                  duration: Duration(minutes: 4),
                  playing: true,
                ),
                onPlayPause: () {},
                onNext: () {},
                onPrevious: () {},
                onExit: () {},
                ids: const PlayerIds(play: 'car-toggle'),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull, reason: '$size');
        final play = tester.getRect(find.bySemanticsIdentifier('car-toggle'));
        expect(
          play.bottom,
          lessThanOrEqualTo(size.height),
          reason: 'the play button is off the bottom at $size',
        );
      }
    });

    testWidgets('a hand steadying itself is not a track change', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var next = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWaxTheme(),
          home: CarModeScaffold(
            now: _now,
            onPlayPause: () {},
            onNext: () => next++,
          ),
        ),
      );
      await tester.pump();

      // A slow drag the whole width of the screen: distance without
      // speed, which is what a hand sliding across a mount looks like.
      await tester.timedDrag(
        find.byType(CarModeScaffold),
        const Offset(-300, 0),
        const Duration(seconds: 3),
      );
      await tester.pumpAndSettle();
      expect(next, 0);
    });
  });
}
