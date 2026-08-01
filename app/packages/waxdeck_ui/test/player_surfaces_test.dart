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
            // Everything the right cluster can hold at once, the volume
            // slider included: it is 80 px of track plus a mute glyph, so
            // it is the largest thing ever added to that cluster and the
            // widths between compact and wide are where it lands hardest.
            now: _music.copyWithSpeed(1.2).copyWithVolume(0.6),
            actions: DeckBarActions(
              onPlayPause: () {},
              onNext: () {},
              onPrevious: () {},
              onShuffle: () {},
              onRepeat: () {},
              onQueue: () {},
              onLyrics: () {},
              onCast: () {},
              onVolume: (_) {},
              onMute: () {},
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

    // The face with the most under its artwork: the volume slot and the
    // action row are what the music rebuild added, and they are what a
    // hero sized off a fraction of the window overflows on.
    for (final size in <Size>[
      Size(360, 640),
      Size(412, 732),
      Size(320, 480),
      Size(900, 600),
      Size(1280, 800),
    ]) {
      testWidgets(
        'a full face fits ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _pumpAt(
            tester,
            SizedBox(
              width: size.width,
              height: size.height,
              child: PlayerScaffold(
                now: _music,
                transport: TransportCluster(
                  playing: true,
                  onPlayPause: () {},
                  onPrevious: () {},
                  onNext: () {},
                  onShuffle: () {},
                  onRepeat: () {},
                ),
                seek: SeekCluster(now: _music, onSeek: (_) {}),
                volume: WaxSlider(
                  value: 0.6,
                  onChanged: (_) {},
                  label: 'Volume',
                ),
                actionRow: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    WaxIconButton(
                      glyph: WaxIcons.queue,
                      label: 'Queue',
                      onPressed: () {},
                    ),
                    WaxIconButton(
                      glyph: WaxIcons.more,
                      label: 'More',
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
            size: size,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    // Compact landscape takes the other arrangement entirely, and every
    // size in the sweep above takes the portrait one - which is how a
    // volume row and an action row were added to a column with no room
    // for them and nothing said so. 568x320 is a phone on its side.
    for (final size in <Size>[
      Size(568, 320),
      Size(480, 320),
      Size(740, 360),
      Size(844, 390),
    ]) {
      testWidgets('a full face fits landscape ${size.width.toInt()}x'
          '${size.height.toInt()}', (tester) async {
        await _pumpAt(
          tester,
          SizedBox(
            width: size.width,
            height: size.height,
            child: PlayerScaffold(
              now: _music,
              transport: TransportCluster(
                playing: true,
                onPlayPause: () {},
                onPrevious: () {},
                onNext: () {},
                onShuffle: () {},
                onRepeat: () {},
              ),
              seek: SeekCluster(now: _music, onSeek: (_) {}),
              volume: WaxSlider(value: 0.6, onChanged: (_) {}, label: 'Volume'),
              actionRow: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  WaxIconButton(
                    glyph: WaxIcons.queue,
                    label: 'Queue',
                    onPressed: () {},
                  ),
                  WaxIconButton(
                    glyph: WaxIcons.more,
                    label: 'More',
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
          size: size,
        );
        expect(tester.takeException(), isNull);
        // The transport is the widest thing that does not wrap, so it
        // is what says whether the column got the room it needs.
        expect(find.byType(TransportCluster), findsOneWidget);
      });
    }

    testWidgets('the surface offers a screen reader no scroll to fall out of', (
      tester,
    ) async {
      // A vertical drag left in the semantics tree publishes scrollUp
      // and scrollDown on the surface, and a screen-reader scroll
      // synthesises a drag long enough to cross the dismiss threshold:
      // swiping to read the player would close it.
      final handle = tester.ensureSemantics();
      var collapsed = 0;
      await _pumpAt(
        tester,
        SizedBox(
          width: 420,
          height: 880,
          child: PlayerScaffold(
            now: _music,
            onCollapse: () => collapsed++,
            ids: const PlayerIds(surface: 'player-surface'),
            transport: TransportCluster(playing: true, onPlayPause: () {}),
            seek: SeekCluster(now: _music, onSeek: (_) {}),
          ),
        ),
        size: const Size(420, 880),
      );

      final data = tester
          .getSemantics(find.bySemanticsIdentifier('player-surface'))
          .getSemanticsData();
      expect(data.actions & SemanticsAction.scrollDown.index, 0);
      expect(data.actions & SemanticsAction.scrollUp.index, 0);
      expect(collapsed, 0);
      handle.dispose();
    });

    testWidgets('the surface is a handle on the player, not a sink for it', (
      tester,
    ) async {
      // A container that leaves its children implicit swallows their
      // text: the title, the artist, and both timecodes fold into the
      // surface's own label, addressable nowhere else, and a screen
      // reader gets one string that counts up once a second.
      final handle = tester.ensureSemantics();
      await _pumpAt(
        tester,
        SizedBox(
          width: 420,
          height: 880,
          child: PlayerScaffold(
            now: _music,
            ids: const PlayerIds(surface: 'player-surface'),
            transport: TransportCluster(playing: true, onPlayPause: () {}),
            seek: SeekCluster(now: _music, onSeek: (_) {}),
          ),
        ),
        size: const Size(420, 880),
      );

      expect(
        tester
            .getSemantics(find.bySemanticsIdentifier('player-surface'))
            .getSemanticsData()
            .label,
        isEmpty,
      );
      for (final label in <String>[
        'Salt Harbour',
        'Nightjar',
        '2:41',
        '4:05',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      handle.dispose();
    });

    testWidgets('a short drag springs back rather than collapsing', (
      tester,
    ) async {
      var collapsed = 0;
      await _pumpAt(
        tester,
        SizedBox(
          width: 420,
          height: 880,
          child: PlayerScaffold(
            now: _music,
            onCollapse: () => collapsed++,
            transport: TransportCluster(playing: true, onPlayPause: () {}),
            seek: SeekCluster(now: _music, onSeek: (_) {}),
          ),
        ),
        size: const Size(420, 880),
      );

      // From the title block, which is not a control: a drag started on
      // the seek bar belongs to the seek bar.
      await tester.drag(find.text('Nightjar'), const Offset(0, 60));
      await tester.pumpAndSettle();
      expect(collapsed, 0);
      // And it comes back: a surface left 60 px down is the gesture
      // half-applied.
      expect(
        tester.getTopLeft(find.text('Nightjar')).dy,
        closeTo(tester.getTopLeft(find.text('Salt Harbour')).dy + 30, 30),
      );
    });

    testWidgets('a long drag collapses the player', (tester) async {
      var collapsed = 0;
      await _pumpAt(
        tester,
        SizedBox(
          width: 420,
          height: 880,
          child: PlayerScaffold(
            now: _music,
            onCollapse: () => collapsed++,
            transport: TransportCluster(playing: true, onPlayPause: () {}),
            seek: SeekCluster(now: _music, onSeek: (_) {}),
          ),
        ),
        size: const Size(420, 880),
      );

      await tester.drag(find.text('Nightjar'), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(collapsed, 1);
    });

    testWidgets('the space around the artwork drags too', (tester) async {
      // Most of a player is backdrop, and a dismissal that only worked
      // where a widget happened to be drawn would read as broken.
      var collapsed = 0;
      await _pumpAt(
        tester,
        SizedBox(
          width: 420,
          height: 880,
          child: PlayerScaffold(
            now: _music,
            onCollapse: () => collapsed++,
            transport: TransportCluster(playing: true, onPlayPause: () {}),
            seek: SeekCluster(now: _music, onSeek: (_) {}),
          ),
        ),
        size: const Size(420, 880),
      );

      // Hard against the left gutter, beside the hero rather than on it.
      await tester.dragFrom(const Offset(8, 300), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(collapsed, 1);
    });

    testWidgets('a flick collapses it without the distance', (tester) async {
      var collapsed = 0;
      await _pumpAt(
        tester,
        SizedBox(
          width: 420,
          height: 880,
          child: PlayerScaffold(
            now: _music,
            onCollapse: () => collapsed++,
            transport: TransportCluster(playing: true, onPlayPause: () {}),
            seek: SeekCluster(now: _music, onSeek: (_) {}),
          ),
        ),
        size: const Size(420, 880),
      );

      await tester.fling(find.text('Nightjar'), const Offset(0, 80), 1600);
      await tester.pumpAndSettle();
      expect(collapsed, 1);
    });

    testWidgets('a player with nowhere to collapse to takes no drag', (
      tester,
    ) async {
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
      final before = tester.getTopLeft(find.text('Nightjar'));
      await tester.drag(find.text('Nightjar'), const Offset(0, 200));
      await tester.pump();
      expect(tester.getTopLeft(find.text('Nightjar')), before);
    });
  });

  group('deck bar title block', () {
    testWidgets('the needle sits beside the title, not adrift in the bar', (
      tester,
    ) async {
      // The subtitle row defaulted to MainAxisSize.max, which stretched
      // the title block to the zone's width and pushed the playing
      // indicator to the middle of the bar - the stray tonearm both bug
      // screenshots show.
      await _pumpAt(
        tester,
        DeckBar(
          now: _music,
          actions: DeckBarActions(onPlayPause: () {}),
        ),
        size: const Size(1280, 200),
      );

      final title = tester.getRect(find.text('Salt Harbour'));
      final needle = tester.getRect(find.byType(PlayingIndicator));
      expect(
        needle.left - title.right,
        lessThan(40),
        reason: 'the needle rides with the text, not with the zone edge',
      );
    });
  });

  group('seek bar', () {
    testWidgets('a track with no length offers no seek', (tester) async {
      // Every position is a fraction of the duration, so at zero a scrub or
      // a keyboard step seeks to the start. Callers reach that without
      // meaning to, so the guard is in the widget.
      Duration? sought;
      await _pumpAt(
        tester,
        SizedBox(
          width: 400,
          child: WaxSeekBar(
            position: Duration.zero,
            duration: Duration.zero,
            onSeek: (value) => sought = value,
            semanticsId: 'seek',
          ),
        ),
        size: const Size(400, 200),
      );

      final node = tester.getSemantics(find.bySemanticsIdentifier('seek'));
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.increase),
        isFalse,
      );
      await tester.tapAt(
        tester.getTopLeft(find.byType(WaxSeekBar)) + const Offset(200, 12),
      );
      await tester.pumpAndSettle();
      expect(sought, isNull);
    });

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

  NowPlayingData copyWithVolume(double volume) => NowPlayingData(
    title: title,
    subtitle: subtitle,
    provenance: provenance,
    position: position,
    duration: duration,
    playing: playing,
    speed: speed,
    volume: volume,
  );
}
