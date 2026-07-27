import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

const _music = NowPlayingData(
  title: 'Salt Harbour',
  subtitle: 'Nightjar',
  provenance: 'Playing from Salt Harbour',
  position: Duration(minutes: 2, seconds: 41),
  duration: Duration(minutes: 4, seconds: 5),
  playing: true,
);

Future<void> _pumpAt(
  WidgetTester tester,
  Widget child, {
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWaxTheme(),
      home: Scaffold(
        body: Align(alignment: Alignment.bottomCenter, child: child),
      ),
    ),
  );
}

void main() {
  group('deck bar', () {
    // The three-zone bar has four icon buttons and a speed chip on its
    // right. A flexed third cannot hold them below about 940 px, so every
    // width in between used to overflow, and no golden pinned a width
    // other than compact.
    for (final width in <double>[420, 600, 720, 840, 1000, 1280]) {
      testWidgets('lays out at ${width.toInt()} px without overflowing', (
        tester,
      ) async {
        await _pumpAt(
          tester,
          DeckBar(
            now: _music.copyWithSpeed(1.2),
            actions: DeckBarActions(
              onPlayPause: () {},
              onNext: () {},
              onPrevious: () {},
              onShuffle: () {},
              onRepeat: () {},
              onQueue: () {},
              onLyrics: () {},
              onCast: () {},
              onMore: () {},
              onSeek: (_) {},
              onStar: (_) {},
            ),
          ),
          size: Size(width, 600),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('shuffle and repeat run their own actions', (tester) async {
      var played = 0;
      var shuffled = 0;
      var repeated = 0;
      await _pumpAt(
        tester,
        DeckBar(
          now: _music,
          sizeClass: WaxSizeClass.wide,
          actions: DeckBarActions(
            onPlayPause: () => played++,
            onShuffle: () => shuffled++,
            onRepeat: () => repeated++,
          ),
        ),
        size: const Size(1280, 600),
      );

      // Both name the state they are in, so pressing one is pressing a
      // control that says what it will change.
      await tester.tap(find.bySemanticsLabel('Shuffle off'));
      await tester.tap(find.bySemanticsLabel('Repeat off'));
      await tester.pump();

      expect(shuffled, 1);
      expect(repeated, 1);
      expect(played, 0, reason: 'neither control may touch playback');
    });

    testWidgets('controls answer a screen reader tap', (tester) async {
      // The e2e suite clicks the semantics node and assistive tech sends
      // it a tap action, so a node that announces "button" and handles
      // nothing is a dead control on both.
      var played = 0;
      final semantics = tester.ensureSemantics();
      await _pumpAt(
        tester,
        DeckBar(
          now: _music,
          sizeClass: WaxSizeClass.compact,
          actions: DeckBarActions(onPlayPause: () => played++),
        ),
        size: const Size(420, 600),
      );

      final node = tester.getSemantics(find.bySemanticsLabel('Pause'));
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason: 'the node announcing the button must handle the tap',
      );
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.tap,
          nodeId: node.id,
          viewId: tester.view.viewId,
        ),
      );
      await tester.pump();
      expect(played, 1);
      semantics.dispose();
    });
  });

  group('player scaffold', () {
    testWidgets('fits a short, wide window', (tester) async {
      // 900x600 is not compact, so it takes the portrait arrangement:
      // artwork sized off width alone did not fit the height left over
      // after the title block, seek cluster, and transport.
      await _pumpAt(
        tester,
        SizedBox(
          width: 900,
          height: 600,
          child: PlayerScaffold(
            now: _music,
            transport: TransportCluster(playing: true, onPlayPause: () {}),
            seek: SeekCluster(now: _music, onSeek: (_) {}),
          ),
        ),
        size: const Size(900, 600),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders the provenance line from the data', (tester) async {
      await _pumpAt(
        tester,
        SizedBox(
          width: 420,
          height: 880,
          child: PlayerScaffold(
            now: _music,
            transport: TransportCluster(playing: true, onPlayPause: () {}),
            seek: SeekCluster(now: _music, onSeek: (_) {}),
          ),
        ),
        size: const Size(420, 880),
      );
      expect(find.text('Playing from Salt Harbour'), findsOneWidget);
    });
  });

  group('seek bar', () {
    testWidgets('a cancelled press releases the playhead', (tester) async {
      // A press that loses the gesture arena (press, then scroll the
      // page) never ends, and the scrub position it set used to stay put
      // for the life of the widget: the playhead froze there. Two
      // identical bars are drawn, one is pressed and cancelled, and the
      // painters have to agree afterwards.
      Duration? sought;
      const props = <String, Duration>{
        'position': Duration(seconds: 30),
        'duration': Duration(seconds: 100),
      };
      await _pumpAt(
        tester,
        Column(
          children: <Widget>[
            SizedBox(
              width: 400,
              child: WaxSeekBar(
                key: const Key('pressed'),
                position: props['position']!,
                duration: props['duration']!,
                onSeek: (value) => sought = value,
              ),
            ),
            SizedBox(
              width: 400,
              child: WaxSeekBar(
                key: const Key('untouched'),
                position: props['position']!,
                duration: props['duration']!,
                onSeek: (_) {},
              ),
            ),
          ],
        ),
        size: const Size(400, 400),
      );

      final pressed = find.byKey(const Key('pressed'));
      final gesture = await tester.startGesture(
        tester.getTopLeft(pressed) + const Offset(360, 12),
      );
      // Past the tap recogniser's deadline, so the press has actually
      // registered and moved the playhead before it is cancelled.
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.cancel();
      await tester.pumpAndSettle();

      expect(sought, isNull, reason: 'a cancelled press must not seek');
      CustomPainter painterOf(Finder bar) => tester
          .widget<CustomPaint>(
            find.descendant(of: bar, matching: find.byType(CustomPaint)).first,
          )
          .painter!;
      expect(
        painterOf(
          pressed,
        ).shouldRepaint(painterOf(find.byKey(const Key('untouched')))),
        isFalse,
        reason: 'the playhead is back where the data says it is',
      );
    });
  });
}

extension on NowPlayingData {
  NowPlayingData copyWithSpeed(double speed) => NowPlayingData(
    title: title,
    subtitle: subtitle,
    provenance: provenance,
    position: position,
    duration: duration,
    playing: playing,
    speed: speed,
  );
}
