import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kDoubleTapMinTime;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

const _music = NowPlayingData(
  title: 'Salt Harbour',
  subtitle: 'Nightjar',
  position: Duration(minutes: 2, seconds: 41),
  duration: Duration(minutes: 4, seconds: 5),
  playing: true,
);

const _station = NowPlayingData(
  title: 'Fixture FM',
  subtitle: 'Somebody - Something',
  position: Duration.zero,
  duration: Duration.zero,
  live: true,
  playing: true,
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  // The window the desktop port asks the compositor for.
  tester.view.physicalSize = const Size(kMiniPlayerWidth, kMiniPlayerHeight);
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
  testWidgets('fits the window it is drawn for', (tester) async {
    await _pump(tester, const MiniPlayer(now: _music));

    final size = tester.getSize(find.byType(MiniPlayer));
    expect(size.width, kMiniPlayerWidth);
    expect(size.height, kMiniPlayerHeight);
    // Nothing overflows: at this size the title block is what yields,
    // and it fade-clips rather than pushing the transport off the edge.
    expect(tester.takeException(), isNull);
  });

  testWidgets('names what is playing and offers the transport', (tester) async {
    var played = 0;
    var next = 0;
    var previous = 0;
    var restored = 0;
    await _pump(
      tester,
      MiniPlayer(
        now: _music,
        actions: DeckBarActions(
          onPlayPause: () => played++,
          onNext: () => next++,
          onPrevious: () => previous++,
        ),
        onRestore: () => restored++,
      ),
    );

    expect(find.text('Salt Harbour'), findsOneWidget);
    expect(find.text('Nightjar'), findsOneWidget);

    // Playing, so the control says what it will do.
    await tester.tap(find.bySemanticsLabel('Pause'));
    await tester.tap(find.bySemanticsLabel('Next'));
    await tester.tap(find.bySemanticsLabel('Previous'));
    await tester.tap(find.bySemanticsLabel('Back to the full window'));
    expect(<int>[played, next, previous, restored], <int>[1, 1, 1, 1]);
  });

  testWidgets('the artwork and title drag the window', (tester) async {
    // A frameless window has no title bar to grab, so this is the only
    // way to move it.
    var dragged = 0;
    await _pump(tester, MiniPlayer(now: _music, onDrag: () => dragged++));

    await tester.timedDrag(
      find.text('Salt Harbour'),
      const Offset(40, 0),
      const Duration(milliseconds: 100),
    );
    expect(dragged, 1);
  });

  testWidgets('the transport is outside the drag handle', (tester) async {
    // A mouse's hit slop is one pixel, so a pan recognizer over the
    // buttons wins the click that moves at all.
    var dragged = 0;
    var played = 0;
    await _pump(
      tester,
      MiniPlayer(
        now: _music,
        actions: DeckBarActions(onPlayPause: () => played++),
        onDrag: () => dragged++,
      ),
    );

    final play = tester.getCenter(find.bySemanticsLabel('Pause'));
    final gesture = await tester.startGesture(
      play,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(4, 2));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(played, 1);
    expect(dragged, 0);
  });

  testWidgets('double-clicking the handle goes back to the app', (
    tester,
  ) async {
    var restored = 0;
    await _pump(tester, MiniPlayer(now: _music, onRestore: () => restored++));

    await tester.tap(find.text('Salt Harbour'));
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(find.text('Salt Harbour'));
    await tester.pumpAndSettle();

    expect(restored, 1);
  });

  testWidgets('a station draws no progress hairline', (tester) async {
    await _pump(tester, const MiniPlayer(now: _station));
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await _pump(tester, const MiniPlayer(now: _music));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('the hairline alone follows the position', (tester) async {
    final position = ValueNotifier(const Duration(minutes: 1));
    addTearDown(position.dispose);
    await _pump(tester, MiniPlayer(now: _music, positionTicker: position));

    double bar() => tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .value!;
    final before = bar();
    position.value = const Duration(minutes: 3);
    await tester.pump();
    expect(bar(), greaterThan(before));
  });

  testWidgets('it announces itself as one surface', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      const MiniPlayer(
        now: _music,
        ids: MiniPlayerIds(surface: 'mini-window'),
      ),
    );

    final node = tester.getSemantics(find.bySemanticsIdentifier('mini-window'));
    expect(node.value, contains('Playing'));
    expect(node.value, contains('Salt Harbour'));
    semantics.dispose();
  });
}
