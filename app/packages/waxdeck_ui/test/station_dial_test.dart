import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

const _stations = <DialStation>[
  DialStation(name: 'Coastal FM'),
  DialStation(name: 'Deck Radio'),
  DialStation(name: 'Night Jazz'),
];

void _ignoreTune(int index) {}

void _ignoreStop() {}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(600, 400),
  bool reducedMotion = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWaxTheme(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reducedMotion),
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the station dial', () {
    testWidgets('names the centred station and tunes it in', (tester) async {
      var tuned = -1;
      await _pump(
        tester,
        StationDial(
          stations: _stations,
          onTune: (index) => tuned = index,
          initialIndex: 1,
        ),
        reducedMotion: true,
      );

      expect(find.text('Deck Radio'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Tune in'));
      await tester.pumpAndSettle();
      expect(tuned, 1);
    });

    testWidgets('offers stop rather than pause on the station playing', (
      tester,
    ) async {
      var stopped = false;
      await _pump(
        tester,
        StationDial(
          stations: const <DialStation>[
            DialStation(name: 'Coastal FM', playing: true),
          ],
          onTune: (_) {},
          onStop: () => stopped = true,
        ),
        reducedMotion: true,
      );

      // A paused live stream resumes at the live edge anyway, so the
      // transport does not pretend otherwise.
      expect(find.bySemanticsLabel('Stop'), findsOneWidget);
      expect(find.bySemanticsLabel('Tune in'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Stop'));
      await tester.pumpAndSettle();
      expect(stopped, isTrue);
    });

    testWidgets('starting playback does not shift the cluster', (tester) async {
      // The ICY line only exists while something plays, and a slot that
      // appeared with it used to shove the name, the button, and the
      // grid below down the moment a stream started.
      await _pump(
        tester,
        const StationDial(
          stations: <DialStation>[DialStation(name: 'Coastal FM')],
          onTune: _ignoreTune,
        ),
        reducedMotion: true,
      );
      final idleHeight = tester.getSize(find.byType(StationDial)).height;
      final idleButton = tester.getTopLeft(find.bySemanticsLabel('Tune in'));

      await _pump(
        tester,
        const StationDial(
          stations: <DialStation>[
            DialStation(
              name: 'Coastal FM',
              playing: true,
              nowPlaying: 'Ora Lune - Bell Tower',
            ),
          ],
          onTune: _ignoreTune,
          onStop: _ignoreStop,
        ),
        reducedMotion: true,
      );

      expect(
        tester.getSize(find.byType(StationDial)).height,
        idleHeight,
        reason: 'the ICY slot is reserved, so the flip moves nothing',
      );
      expect(
        tester.getTopLeft(find.bySemanticsLabel('Stop')).dy,
        idleButton.dy,
        reason: 'the transport stays put through the playing flip',
      );
    });

    testWidgets('the live pill stays inside the station slot', (tester) async {
      await _pump(
        tester,
        const StationDial(
          stations: <DialStation>[
            DialStation(name: 'Coastal FM', playing: true),
          ],
          onTune: _ignoreTune,
          onStop: _ignoreStop,
        ),
        reducedMotion: true,
      );

      final logo = tester.getRect(find.byType(ArtworkImage).first);
      final pill = tester.getRect(
        find.ancestor(of: find.text('LIVE'), matching: find.byType(Container)),
      );
      expect(
        pill.bottom,
        lessThanOrEqualTo(logo.bottom + 0.01),
        reason: 'the pill is contained by the slot, not hung below it',
      );
    });

    testWidgets('keeps the logo band out of the traversal order', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        StationDial(stations: _stations, onTune: (_) {}),
        reducedMotion: true,
      );

      // The grid below the dial has a row per station, so twelve circular
      // logos in the traversal order buy nothing and cost the way out of
      // them. What remains is the centred station's caption and its one
      // tune control: a single control, and a large button naming what it
      // does is as useful to a screen reader as to anyone.
      expect(find.bySemanticsLabel('Coastal FM'), findsOneWidget);
      expect(find.bySemanticsLabel('Deck Radio'), findsNothing);
      expect(find.bySemanticsLabel('Night Jazz'), findsNothing);
      final tune = tester.getSemantics(find.bySemanticsLabel('Tune in'));
      expect(tune.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      semantics.dispose();
    });

    testWidgets('draws the ICY line only under the station playing it', (
      tester,
    ) async {
      await _pump(
        tester,
        StationDial(
          stations: const <DialStation>[
            DialStation(
              name: 'Coastal FM',
              playing: true,
              nowPlaying: 'Ornithology',
            ),
            // The same title on a station nobody is listening to would
            // attach a stream's song to the wrong name.
            DialStation(name: 'Deck Radio', nowPlaying: 'Ornithology'),
          ],
          onTune: (_) {},
          onStop: () {},
        ),
        reducedMotion: true,
      );

      expect(find.text('Ornithology'), findsOneWidget);
    });

    testWidgets('shrinking the pinned list does not read past its end', (
      tester,
    ) async {
      // Unpinning the last favourite while the needle is on it leaves the
      // centred index outside the list, which the next build would index
      // into.
      await _pump(
        tester,
        StationDial(stations: _stations, onTune: (_) {}, initialIndex: 2),
        reducedMotion: true,
      );
      expect(find.text('Night Jazz'), findsOneWidget);

      await _pump(
        tester,
        StationDial(
          stations: _stations.take(1).toList(),
          onTune: (_) {},
          initialIndex: 2,
        ),
        reducedMotion: true,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Coastal FM'), findsOneWidget);
    });

    testWidgets('the needle moves without a pointer', (tester) async {
      // Excluding the logo band keeps twelve logos out of the traversal
      // order, and it also left the one tune control stuck on whatever
      // station the dial opened on: moving the needle was a flick or a
      // mouse tap, neither of which a keyboard or a screen reader has.
      final semantics = tester.ensureSemantics();
      var tuned = -1;
      await _pump(
        tester,
        StationDial(stations: _stations, onTune: (index) => tuned = index),
        reducedMotion: true,
      );

      final dial = tester.getSemantics(find.bySemanticsLabel('Station dial'));
      expect(dial.value, 'Coastal FM, 1 of 3');
      expect(dial.increasedValue, 'Deck Radio, 2 of 3');
      // Nowhere to go at the ends, and it says so rather than offering a
      // step that does nothing.
      expect(dial.decreasedValue, '');
      expect(
        dial.getSemanticsData().hasAction(SemanticsAction.decrease),
        isFalse,
      );

      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.increase,
          nodeId: dial.id,
          viewId: tester.view.viewId,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Deck Radio'), findsOneWidget);
      // And the tune control follows the needle rather than the station the
      // dial opened on, which is the whole point.
      await tester.tap(find.bySemanticsLabel('Tune in'));
      await tester.pumpAndSettle();
      expect(tuned, 1);
      semantics.dispose();
    });

    testWidgets('an empty dial draws nothing at all', (tester) async {
      await _pump(
        tester,
        StationDial(stations: const <DialStation>[], onTune: (_) {}),
      );
      expect(find.byType(WaxButton), findsNothing);
    });
  });

  group('the slider', () {
    testWidgets('announces a level and can be set by a screen reader', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var level = 0.5;
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => WaxSlider(
            value: level,
            label: 'Volume',
            glyph: WaxIcons.volume,
            mutedGlyph: WaxIcons.volumeMuted,
            onChanged: (next) => setState(() => level = next),
          ),
        ),
      );

      final node = tester.getSemantics(find.bySemanticsLabel('Volume'));
      // A percentage, because that is what a level is: a slider announcing
      // "0.55" is reading its implementation out loud.
      expect(node.value, '50%');
      expect(node.increasedValue, '55%');
      expect(node.decreasedValue, '45%');

      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.increase,
          nodeId: node.id,
          viewId: tester.view.viewId,
        ),
      );
      await tester.pumpAndSettle();
      expect(level, closeTo(0.55, 0.001));
      semantics.dispose();
    });

    testWidgets('a level of zero draws as muted without being told', (
      tester,
    ) async {
      // The remote screen forgot to pass `muted`, so a silenced endpoint
      // drew an un-muted speaker. Asked of the value instead of the caller,
      // because the glyph exists to be right about exactly this.
      await _pump(
        tester,
        WaxSlider(
          value: 0,
          label: 'Volume',
          glyph: WaxIcons.volume,
          mutedGlyph: WaxIcons.volumeMuted,
          onChanged: (_) {},
          onMute: () {},
        ),
      );
      expect(find.bySemanticsLabel('Unmute'), findsOneWidget);
      expect(find.bySemanticsLabel('Mute'), findsNothing);
    });

    testWidgets('a mute control says what it will do next', (tester) async {
      await _pump(
        tester,
        WaxSlider(
          value: 0,
          muted: true,
          label: 'Volume',
          glyph: WaxIcons.volume,
          mutedGlyph: WaxIcons.volumeMuted,
          onChanged: (_) {},
          onMute: () {},
        ),
      );
      expect(find.bySemanticsLabel('Unmute'), findsOneWidget);
    });

    testWidgets('without a mute handler the glyph is not a control', (
      tester,
    ) async {
      // Where a caller has nowhere to remember the level it silenced, a
      // glyph that mutes and cannot un-mute is worse than a label.
      await _pump(
        tester,
        WaxSlider(
          value: 0.4,
          label: 'Volume',
          glyph: WaxIcons.volume,
          onChanged: (_) {},
        ),
      );
      expect(find.bySemanticsLabel('Mute'), findsNothing);
      expect(find.bySemanticsLabel('Volume'), findsOneWidget);
    });

    testWidgets('no setter disables it, and says so', (tester) async {
      await _pump(
        tester,
        const WaxSlider(value: 0.4, label: 'Volume', onChanged: null),
      );
      final node = tester.getSemantics(find.bySemanticsLabel('Volume'));
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.increase),
        isFalse,
      );
    });
  });

  group('the option row', () {
    testWidgets('announces once and leaves its trailing control its own '
        'node', (tester) async {
      // The defect MediaListRow shipped: excluding a whole row's subtree so
      // it announces once takes its own controls out of the semantics tree
      // while leaving them perfectly visible.
      var trailing = 0;
      await _pump(
        tester,
        WaxOptionRow(
          title: 'Kitchen speaker',
          subtitle: 'Remote volume control',
          glyph: WaxIcons.cast,
          onTap: () {},
          trailing: WaxIconButton(
            glyph: WaxIcons.more,
            label: 'More for Kitchen speaker',
            onPressed: () => trailing++,
          ),
        ),
      );

      expect(
        find.bySemanticsLabel('Kitchen speaker, Remote volume control'),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsLabel('More for Kitchen speaker'));
      await tester.pumpAndSettle();
      expect(trailing, 1);
    });

    testWidgets('a row that cannot be taken still says what it is', (
      tester,
    ) async {
      await _pump(
        tester,
        const WaxOptionRow(
          title: 'Porch radio',
          subtitle: 'Offline',
          glyph: WaxIcons.cast,
          enabled: false,
        ),
      );
      // Unavailable rather than hidden: a listener looking for the porch
      // speaker needs to be told it is off, not left to wonder.
      // Announced, and not activatable: the consequence a listener feels,
      // rather than the flag behind it.
      final node = tester.getSemantics(
        find.bySemanticsLabel('Porch radio, Offline'),
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    });

    testWidgets('a highlight that is not playback does not announce one', (
      tester,
    ) async {
      // The connection check draws a reachable cast address as active, and
      // with the default prefix every one announced as playing.
      await _pump(
        tester,
        const Column(
          children: <Widget>[
            WaxOptionRow(
              title: 'Kitchen speaker',
              subtitle: 'In use',
              glyph: WaxIcons.cast,
              active: true,
            ),
            WaxOptionRow(
              title: 'http://192.168.1.20:4420',
              subtitle: 'Detected on this network, reachable',
              glyph: WaxIcons.check,
              active: true,
              activeLabel: null,
            ),
          ],
        ),
      );

      expect(
        find.bySemanticsLabel('Playing, Kitchen speaker, In use'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'http://192.168.1.20:4420, Detected on this network, reachable',
        ),
        findsOneWidget,
      );
    });
  });
}
