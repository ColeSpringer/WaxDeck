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

const _podcast = NowPlayingData(
  title: 'What the harbour remembers',
  domain: WaxDomain.podcasts,
  position: Duration(minutes: 18, seconds: 6),
  duration: Duration(minutes: 58, seconds: 12),
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

    testWidgets('a source caption sits under the hero and still fits', (
      tester,
    ) async {
      // The caption is drawn inside the slot the hero was measured
      // into, so the artwork has to give up its height rather than the
      // column overflowing by a line. A short window is where that
      // shows: there is no slack to absorb it.
      await _pumpAt(
        tester,
        SizedBox(
          width: 420,
          height: 620,
          child: PlayerScaffold(
            now: _music,
            artworkCaption: 'From the Cover Art Archive',
            transport: TransportCluster(playing: true, onPlayPause: () {}),
            seek: SeekCluster(now: _music, onSeek: (_) {}),
          ),
        ),
        size: const Size(420, 620),
      );
      expect(tester.takeException(), isNull);

      final caption = tester.getRect(find.text('From the Cover Art Archive'));
      final art = tester.getRect(find.byType(ArtworkImage).first);
      expect(
        caption.top,
        greaterThanOrEqualTo(art.bottom),
        reason: 'the caption belongs under the picture it describes',
      );
      expect(
        caption.width,
        lessThanOrEqualTo(art.width + 1),
        reason: 'bounded by the artwork, so a long provider name wraps',
      );
    });

    testWidgets('a reserved caption line holds the cover still', (
      tester,
    ) async {
      // The mark arrives from a read drawn after the first frame and is
      // absent for a library nothing has enriched, and on radio it turns
      // over with the songs. Without the slot held the cover is drawn at
      // one extent and then another - mid-Hero flight from the deck bar,
      // on a window narrow enough for the extent to bind.
      Future<Rect> heroBox({String? caption, required bool reserved}) async {
        await _pumpAt(
          tester,
          SizedBox(
            width: 420,
            height: 620,
            child: PlayerScaffold(
              now: _music,
              artworkCaption: caption,
              artworkCaptionReserved: reserved,
              transport: TransportCluster(playing: true, onPlayPause: () {}),
              seek: SeekCluster(now: _music, onSeek: (_) {}),
            ),
          ),
          size: const Size(420, 620),
        );
        return tester.getRect(find.byType(ArtworkImage).first);
      }

      // The whole rect, not its width: reserving the extent without
      // standing in the box for it leaves the cover the same size and
      // moves it up the screen, which is the same jump.
      final waiting = await heroBox(reserved: true);
      final arrived = await heroBox(
        caption: 'From the Cover Art Archive',
        reserved: true,
      );
      expect(waiting, arrived);

      // And a face that reserves nothing still gets the whole extent.
      final never = await heroBox(reserved: false);
      expect(never.width, greaterThan(arrived.width));
    });

    testWidgets('the provenance centres against the header, not the gap', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        SizedBox(
          width: 900,
          height: 880,
          child: PlayerScaffold(
            now: _music,
            onCollapse: () {},
            transport: TransportCluster(playing: true, onPlayPause: () {}),
            seek: SeekCluster(now: _music, onSeek: (_) {}),
            // Three controls against one: the asymmetry is the whole
            // point, and it is what a centre taken from the leftover
            // space gets wrong.
            trailingHeaderActions: <Widget>[
              WaxIconButton(
                glyph: WaxIcons.cast,
                label: 'Play on another device',
                onPressed: () {},
              ),
              WaxIconButton(
                glyph: WaxIcons.downloads,
                label: 'Download',
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
        size: const Size(900, 880),
      );

      final provenance = tester.getRect(find.text('Playing from Salt Harbour'));
      final surface = tester.getRect(find.byType(PlayerScaffold));
      expect(provenance.center.dx, moreOrLessEquals(surface.center.dx));
    });

    testWidgets('the header grows with the type rather than spilling', (
      tester,
    ) async {
      // The toolbar lays its middle out inside the height the bar
      // states and nothing clips it, so a bar pinned to one touch target
      // paints a large accessibility size over the artwork below.
      Future<Rect> headerAt(double scale) async {
        await _pumpAt(
          tester,
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: SizedBox(
              width: 900,
              height: 880,
              child: PlayerScaffold(
                now: _music,
                onCollapse: () {},
                transport: TransportCluster(playing: true, onPlayPause: () {}),
                seek: SeekCluster(now: _music, onSeek: (_) {}),
              ),
            ),
          ),
          size: const Size(900, 880),
        );
        return tester.getRect(find.text('Playing from Salt Harbour'));
      }

      // The bar the provenance sits in, found through the button beside
      // it: the toolbar gives both slots the bar's own height.
      Rect bar() => tester.getRect(
        find
            .ancestor(
              of: find.byType(NavigationToolbar),
              matching: find.byType(SizedBox),
            )
            .first,
      );

      final plain = await headerAt(1);
      final plainBar = bar();
      expect(plainBar.height, WaxSpace.touchTarget);
      expect(plain.height, lessThanOrEqualTo(plainBar.height));

      final large = await headerAt(3);
      final largeBar = bar();
      expect(largeBar.height, greaterThan(plainBar.height));
      expect(
        large.height,
        lessThanOrEqualTo(largeBar.height),
        reason: 'the provenance stays inside the bar it is laid out in',
      );
    });

    testWidgets('a click beside the provenance collapses the player', (
      tester,
    ) async {
      // The middle is only as wide as its own text now, so the run
      // between it and the trailing island is bare surface - which is
      // what dismisses.
      var collapsed = 0;
      await _pumpAt(
        tester,
        SizedBox(
          width: 900,
          height: 880,
          child: PlayerScaffold(
            now: _music,
            onCollapse: () => collapsed++,
            transport: TransportCluster(playing: true, onPlayPause: () {}),
            seek: SeekCluster(now: _music, onSeek: (_) {}),
            trailingHeaderActions: <Widget>[
              WaxIconButton(
                glyph: WaxIcons.more,
                label: 'More',
                onPressed: () {},
              ),
            ],
          ),
        ),
        size: const Size(900, 880),
      );

      final provenance = tester.getRect(find.text('Playing from Salt Harbour'));
      await tester.tapAt(
        Offset(provenance.right + WaxSpace.s24, provenance.center.dy),
      );
      await tester.pump();
      expect(collapsed, 1);
    });

    testWidgets('the title block centres every line on its own width', (
      tester,
    ) async {
      // Centred as a pair with `titleTrailing`, the title sat left of
      // centre while the subtitle did not. Every alignment screenshot.
      await _pumpAt(
        tester,
        SizedBox(
          width: 420,
          height: 880,
          child: PlayerScaffold(
            now: _music,
            // The shape the item faces carry: six 44 px buttons and a
            // gap, which is most of the content box.
            titleTrailing: const SizedBox(
              key: Key('rating'),
              width: 272,
              height: 44,
            ),
            transport: TransportCluster(playing: true, onPlayPause: () {}),
            seek: SeekCluster(now: _music, onSeek: (_) {}),
          ),
        ),
        size: const Size(420, 880),
      );

      final title = tester.getRect(find.text('Salt Harbour'));
      final subtitle = tester.getRect(find.text('Nightjar'));
      final rating = tester.getRect(find.byKey(const Key('rating')));

      expect(
        rating.top,
        greaterThanOrEqualTo(subtitle.bottom),
        reason: 'its own line, under the subtitle rather than beside the title',
      );
      expect(title.center.dx, moreOrLessEquals(subtitle.center.dx, epsilon: 1));
      expect(title.center.dx, moreOrLessEquals(rating.center.dx, epsilon: 1));
    });

    testWidgets('the end of a queue greys next rather than dropping it', (
      tester,
    ) async {
      // Two questions, one slot before this: onNext asks whether the
      // surface offers a next at all - a spoken-word face does not - and
      // answering "nowhere to go" with null would take the button out of
      // the row and re-centre the transport under the listener's thumb.
      final semantics = tester.ensureSemantics();
      await _pumpAt(
        tester,
        SizedBox(
          width: 420,
          height: 880,
          child: PlayerScaffold(
            now: _music,
            transport: TransportCluster(
              playing: true,
              onPlayPause: () {},
              onPrevious: () {},
              onNext: () {},
              canNext: false,
            ),
            seek: SeekCluster(now: _music, onSeek: (_) {}),
          ),
        ),
        size: const Size(420, 880),
      );

      final node = tester.getSemantics(find.bySemanticsLabel('Next'));
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
        reason: 'drawn, and reported dead rather than left to its tint',
      );
      semantics.dispose();
    });

    group('the hero', () {
      Future<double> heroAt(
        WidgetTester tester,
        Size size, {
        NowPlayingData now = _music,
      }) async {
        await _pumpAt(
          tester,
          SizedBox(
            width: size.width,
            height: size.height,
            child: PlayerScaffold(
              now: now,
              transport: TransportCluster(playing: true, onPlayPause: () {}),
              seek: SeekCluster(now: now, onSeek: (_) {}),
            ),
          ),
          size: size,
        );
        return tester.widget<ArtworkImage>(find.byType(ArtworkImage)).size;
      }

      testWidgets('grows with the window rather than sitting at a flat cap', (
        tester,
      ) async {
        final phone = await heroAt(tester, const Size(420, 880));
        final desktop = await heroAt(tester, const Size(1280, 1000));

        expect(
          desktop,
          greaterThan(phone),
          reason: 'a window with room to fill drew a phone-sized square',
        );
      });

      testWidgets('keeps podcasts smaller without shrinking them', (
        tester,
      ) async {
        // One cap, so the ratio is taken once. Against a per-arrangement
        // cap it was a reduction of a reduction, and landscape - which
        // has the least room to start with - lost a third of its cover.
        for (final window in <Size>[
          const Size(1280, 1000), // portrait, desktop
          const Size(568, 320), // landscape, phone
          const Size(1280, 400), // landscape, short desktop window
        ]) {
          final music = await heroAt(tester, window);
          final show = await heroAt(tester, window, now: _podcast);

          expect(
            show,
            lessThanOrEqualTo(music),
            reason: 'a show cover is the same square every episode: $window',
          );
          expect(
            show,
            greaterThanOrEqualTo(200),
            reason: 'and never smaller than it was drawn before: $window',
          );
        }
      });
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

    // A pointer has no pull-down. On a wide window the content is a
    // 520 px column in the middle and the rest is backdrop, which is
    // where a mouse expects a modal surface to close from.
    testWidgets('a click off the content collapses the player', (tester) async {
      var collapsed = 0;
      await _pumpAt(
        tester,
        SizedBox(
          width: 900,
          height: 880,
          child: PlayerScaffold(
            now: _music,
            onCollapse: () => collapsed++,
            transport: TransportCluster(playing: true, onPlayPause: () {}),
            seek: SeekCluster(now: _music, onSeek: (_) {}),
          ),
        ),
        size: const Size(900, 880),
      );

      // Well outside the centred content box: (900 - 520) / 2 = 190 px
      // of gutter either side.
      await tester.tapAt(const Offset(40, 440));
      await tester.pump();
      expect(collapsed, 1);
    });

    testWidgets('a click on the content is not a dismissal', (tester) async {
      var collapsed = 0;
      await _pumpAt(
        tester,
        SizedBox(
          width: 900,
          height: 880,
          child: PlayerScaffold(
            now: _music,
            onCollapse: () => collapsed++,
            transport: TransportCluster(playing: true, onPlayPause: () {}),
            seek: SeekCluster(now: _music, onSeek: (_) {}),
          ),
        ),
        size: const Size(900, 880),
      );

      // The artwork, the title, and the slack between the clusters: all
      // content, none of it a way out. The last is the one that matters
      // -- a thumb that misses a control by a few pixels has not asked
      // to leave.
      await tester.tap(find.byType(ArtworkImage).first);
      await tester.tap(find.text('Nightjar'));
      await tester.tapAt(
        tester.getBottomLeft(find.text('Nightjar')) + const Offset(20, 4),
      );
      await tester.pump();
      expect(collapsed, 0);
    });

    testWidgets('a near-miss on a header control is not a dismissal', (
      tester,
    ) async {
      // A Row does not hit-test the slack around its children, so
      // without islanding the controls a thumb a few pixels off the
      // overflow menu falls through to the surface and shuts the player.
      var collapsed = 0;
      await _pumpAt(
        tester,
        SizedBox(
          width: 900,
          height: 880,
          child: PlayerScaffold(
            now: _music,
            onCollapse: () => collapsed++,
            transport: TransportCluster(playing: true, onPlayPause: () {}),
            seek: SeekCluster(now: _music, onSeek: (_) {}),
            trailingHeaderActions: <Widget>[
              WaxIconButton(
                glyph: WaxIcons.more,
                label: 'More',
                onPressed: () {},
              ),
            ],
          ),
        ),
        size: const Size(900, 880),
      );

      // Just off each control, inside the gutter its island keeps. Not
      // on the controls themselves: the chevron collapsing when pressed
      // is the chevron working.
      final more = find.bySemanticsLabel('More');
      await tester.tapAt(tester.getTopLeft(more) - const Offset(2, 0));
      final collapse = find.bySemanticsLabel('Collapse player');
      await tester.tapAt(tester.getTopRight(collapse) + const Offset(2, 20));
      await tester.pump();
      expect(collapsed, 0);

      // The stretch between them is still the way out, which is what a
      // phone depends on: there the content box is the full width and
      // this is the only region left to tap.
      await tester.tapAt(const Offset(450, 20));
      await tester.pump();
      expect(collapsed, 1);
    });

    testWidgets('the header stretch is a way out too', (tester) async {
      var collapsed = 0;
      await _pumpAt(
        tester,
        SizedBox(
          width: 900,
          height: 880,
          child: PlayerScaffold(
            now: _music,
            onCollapse: () => collapsed++,
            transport: TransportCluster(playing: true, onPlayPause: () {}),
            seek: SeekCluster(now: _music, onSeek: (_) {}),
          ),
        ),
        size: const Size(900, 880),
      );

      // The empty run between the collapse button and the trailing
      // actions, which is backdrop wearing a Row.
      await tester.tapAt(const Offset(450, 20));
      await tester.pump();
      expect(collapsed, 1);
    });

    testWidgets('a player with nowhere to collapse to takes no click', (
      tester,
    ) async {
      // One policy for both gestures: a null onCollapse turns off the
      // pull-down and the click together, so a scaffold with no way out
      // cannot be half-dismissed.
      await _pumpAt(
        tester,
        SizedBox(
          width: 900,
          height: 880,
          child: PlayerScaffold(
            now: _music,
            transport: TransportCluster(playing: true, onPlayPause: () {}),
            seek: SeekCluster(now: _music, onSeek: (_) {}),
          ),
        ),
        size: const Size(900, 880),
      );
      await tester.tapAt(const Offset(40, 440));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the dismissing surface publishes no tap of its own', (
      tester,
    ) async {
      // On web a tappable node is drawn as a rect with pointer-events
      // over its whole area: published, this one would be an unnamed
      // control the size of the window sitting over every control that
      // does have a name. The way out for a screen reader is the
      // collapse button, exactly as it was for the drag.
      final handle = tester.ensureSemantics();
      await _pumpAt(
        tester,
        SizedBox(
          width: 900,
          height: 880,
          child: PlayerScaffold(
            now: _music,
            onCollapse: () {},
            ids: const PlayerIds(surface: 'player-surface'),
            transport: TransportCluster(playing: true, onPlayPause: () {}),
            seek: SeekCluster(now: _music, onSeek: (_) {}),
          ),
        ),
        size: const Size(900, 880),
      );

      final data = tester
          .getSemantics(find.bySemanticsIdentifier('player-surface'))
          .getSemanticsData();
      expect(data.actions & SemanticsAction.tap.index, 0);
      handle.dispose();
    });
  });

  group('deck bar title block', () {
    testWidgets('the star rides with the text, not with the zone edge', (
      tester,
    ) async {
      // The subtitle row defaults to MainAxisSize.max, which stretches
      // the title block to the whole zone and strands whatever follows
      // it in the middle of the bar.
      await _pumpAt(
        tester,
        DeckBar(
          now: _music,
          sizeClass: WaxSizeClass.wide,
          actions: DeckBarActions(onPlayPause: () {}, onStar: (_) {}),
        ),
        size: const Size(1280, 200),
      );

      final title = tester.getRect(find.text('Salt Harbour'));
      final star = tester.getRect(find.bySemanticsLabel(RegExp('star|Star')));
      expect(star.left - title.right, lessThan(40));
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

    // Divisions along a bar that spans something with divisions in it:
    // a book's chapters under a whole-book envelope.
    testWidgets('marks are decoration, not a second slider', (tester) async {
      await _pumpAt(
        tester,
        SizedBox(
          width: 400,
          child: WaxSeekBar(
            position: const Duration(minutes: 10),
            duration: const Duration(hours: 1),
            marks: const <Duration>[
              Duration(minutes: 15),
              Duration(minutes: 40),
            ],
            onSeek: (_) {},
            semanticsId: 'seek',
          ),
        ),
        size: const Size(400, 200),
      );

      // The slider still announces one position and one span. Forty
      // ticks announced would be the shape of a picture a screen reader
      // cannot see, and the chapter list is where a chapter is chosen.
      final node = tester.getSemantics(find.bySemanticsIdentifier('seek'));
      expect(node.getSemanticsData().value, contains('of'));
      expect(node.childrenCount, 0);
    });

    test('a mark outside the span is dropped, not clamped', () {
      const hour = Duration(hours: 1);
      expect(
        markFractions(const <Duration>[Duration(minutes: 30)], hour),
        <double>[0.5],
      );
      // Past the end, and exactly on either edge: none of the three is
      // a division inside the span, and clamping them would draw ticks
      // on the rail claiming a chapter starts where the bar stops.
      expect(
        markFractions(const <Duration>[
          Duration(minutes: 15),
          Duration(hours: 2),
          Duration.zero,
          hour,
        ], hour),
        <double>[0.25],
      );
      // Nothing to draw reads the same as no marks at all.
      expect(markFractions(const <Duration>[hour], hour), isNull);
      expect(markFractions(null, hour), isNull);
      expect(markFractions(const <Duration>[], hour), isNull);
      // No span is no timeline to place anything on.
      expect(
        markFractions(const <Duration>[Duration(minutes: 5)], Duration.zero),
        isNull,
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
