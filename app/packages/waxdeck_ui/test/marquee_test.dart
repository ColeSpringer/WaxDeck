import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

const _long =
    'Concerto for Two Violins in D minor, BWV 1043: II. Largo ma non tanto';
const _short = 'Salt Harbour';

/// [child] in a slot too narrow for [_long] and wide enough for
/// [_short], which is the deck bar's own situation.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool reducedMotion = false,
  double textScale = 1,
  double width = 200,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWaxTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: reducedMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  );
}

/// Where the moving copy sits relative to its slot. Constant means it is
/// not travelling.
double _offsetOf(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.descendant(
      of: find.byType(WaxMarqueeText),
      matching: find.byType(Transform),
    ),
  );
  return transform.transform.getTranslation().x;
}

/// Pumps until the line stops travelling, which is its hold at the far
/// end of the run - the travel distance is the text's own width, so the
/// timing cannot be arithmetic from the parameters alone.
Future<void> _pumpToFarEnd(WidgetTester tester) async {
  var previous = _offsetOf(tester);
  for (var i = 0; i < 400; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final current = _offsetOf(tester);
    if (previous < 0 && current == previous) return;
    previous = current;
  }
  fail('the line never reached the end of its travel');
}

/// The soft edges the line is currently drawn with.
({double start, double end}) _fadesOf(WidgetTester tester) {
  final fade = tester.widget<EdgeFade>(
    find.descendant(
      of: find.byType(WaxMarqueeText),
      matching: find.byType(EdgeFade),
    ),
  );
  return (start: fade.start, end: fade.end);
}

void main() {
  testWidgets('a title that fits does not move, and holds no ticker', (
    tester,
  ) async {
    await _pump(tester, const WaxMarqueeText(_short));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text(_short), findsOneWidget);
    // The whole cost of a title that fits: a plain line. No clip, no
    // shader, no animation driving a frame a sixtieth of a second.
    expect(
      find.descendant(
        of: find.byType(WaxMarqueeText),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
    // And no pending frames, which is what a live ticker would leave.
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a title that overflows travels and comes back', (tester) async {
    // Both timings named, so the phases below are arithmetic rather
    // than a guess at the defaults: a 200ms hold at each end and a
    // travel at 100px a second.
    await _pump(
      tester,
      const WaxMarqueeText(
        _long,
        velocity: 100,
        pause: Duration(milliseconds: 200),
      ),
    );
    await tester.pump();

    // Holds at the start first: a line that begins moving the instant it
    // appears is one nobody has read the beginning of.
    expect(_offsetOf(tester), 0);
    await tester.pump(const Duration(milliseconds: 150));
    expect(_offsetOf(tester), 0);

    // Then travels, leftwards, which is what a negative translation is.
    await tester.pump(const Duration(milliseconds: 1200));
    final travelled = _offsetOf(tester);
    expect(travelled, lessThan(0));

    // Out to the far end and held there, so the end of the name is
    // readable too rather than being passed through.
    await tester.pump(const Duration(milliseconds: 1400));
    final far = _offsetOf(tester);
    expect(far, lessThan(travelled));

    // And back rather than wrapping: a title left standing at its own
    // end reads as a bug.
    await tester.pump(const Duration(milliseconds: 1600));
    expect(_offsetOf(tester), greaterThan(far));

    // Stopped so the test does not end with a running ticker.
    await _pump(tester, const SizedBox.shrink());
  });

  testWidgets('the fade follows the travel, not the edges', (tester) async {
    // A pair of fixed edges softened the first characters while the
    // line was parked at its start and the last ones while it was
    // parked at its end - the name looking clipped at exactly the two
    // moments it is meant to be read.
    await _pump(
      tester,
      const WaxMarqueeText(
        _long,
        velocity: 100,
        pause: Duration(milliseconds: 200),
      ),
    );
    await tester.pump();

    // At rest at its start: nothing hidden on the reading side, and a
    // fade only where the rest of the name is.
    expect(_offsetOf(tester), 0);
    expect(_fadesOf(tester).start, 0);
    expect(_fadesOf(tester).end, 16);

    // Mid-travel there is text on both sides, so both fade.
    await tester.pump(const Duration(milliseconds: 1200));
    expect(_offsetOf(tester), lessThan(0));
    expect(_fadesOf(tester).start, 16);
    expect(_fadesOf(tester).end, 16);

    // Parked at the far end, where the last characters are the ones
    // being read.
    await _pumpToFarEnd(tester);
    expect(_fadesOf(tester).start, 16);
    expect(_fadesOf(tester).end, 0);

    await _pump(tester, const SizedBox.shrink());
  });

  testWidgets('it rests between runs rather than parking for good', (
    tester,
  ) async {
    // The old shape ran its cycles and then held at offset zero
    // forever. On a station - one subtitle per song rather than one per
    // track - that is a line parked for minutes with its end under a
    // fade, which reads as a name that is cut off and not as one that
    // has finished scrolling.
    await _pump(
      tester,
      const WaxMarqueeText(
        _long,
        velocity: 100,
        pause: Duration(milliseconds: 200),
        cycles: 1,
        rest: Duration(seconds: 2),
      ),
    );
    await tester.pumpAndSettle();

    // One round trip done, and still: no frames are being scheduled
    // for it, which is the whole point of resting rather than looping.
    expect(_offsetOf(tester), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);

    // The rest elapses and it goes again.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(_offsetOf(tester), lessThan(0));

    // And rests again after that pass rather than looping from here on.
    await tester.pumpAndSettle();
    expect(_offsetOf(tester), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);

    await _pump(tester, const SizedBox.shrink());
  });

  testWidgets('a slot that changes during a rest is picked up on the next '
      'run', (tester) async {
    // The pending distance is read at a cycle boundary, and a resting
    // line has none: a window resized mid-rest would have run its next
    // pass on the old tween, overshooting a slot that narrowed.
    await _pump(
      tester,
      const WaxMarqueeText(
        _long,
        velocity: 100,
        pause: Duration(milliseconds: 200),
        cycles: 1,
        rest: Duration(seconds: 2),
      ),
    );
    await tester.pumpAndSettle();
    expect(_offsetOf(tester), 0);

    // Narrower, so there is further to travel than the armed run knows.
    await _pump(
      tester,
      const WaxMarqueeText(
        _long,
        velocity: 100,
        pause: Duration(milliseconds: 200),
        cycles: 1,
        rest: Duration(seconds: 2),
      ),
      width: 120,
    );
    await tester.pump();

    await tester.pump(const Duration(seconds: 2));
    await _pumpToFarEnd(tester);
    // The fade is computed from the same distance the tween runs, so a
    // stale one leaves the far end soft.
    expect(_fadesOf(tester).end, 0);

    await _pump(tester, const SizedBox.shrink());
  });

  testWidgets('a line taken off screen leaves no timer behind', (tester) async {
    // A resting line holds a pending timer; the test framework fails
    // the test if one outlives the tree, which is the same leak that
    // would fire `setState` on a disposed state in the app.
    await _pump(
      tester,
      const WaxMarqueeText(
        _long,
        velocity: 100,
        pause: Duration(milliseconds: 200),
        cycles: 1,
        rest: Duration(seconds: 2),
      ),
    );
    await tester.pumpAndSettle();
    await _pump(tester, const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('reduced motion draws the still line instead', (tester) async {
    await _pump(tester, const WaxMarqueeText(_long), reducedMotion: true);
    await tester.pump(const Duration(seconds: 3));

    expect(
      find.descendant(
        of: find.byType(WaxMarqueeText),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a title that only overflows when scaled up still moves', (
    tester,
  ) async {
    // Measured with the scale the line is drawn at, not the unscaled
    // default. Without it a title that fits at 1x and overflows at
    // 1.6x measures as fitting - so the marquee never runs for the
    // reader who most needs it - and the height it reports is short by
    // the same factor, which clips the glyphs inside the bar's clip.
    await _pump(
      tester,
      const WaxMarqueeText(_short),
      textScale: 1.6,
      width: 110,
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(WaxMarqueeText),
        matching: find.byType(Transform),
      ),
      findsOneWidget,
      reason: 'the scaled line overflows a slot the unscaled one fits',
    );
    // And the slot is as tall as the scaled line: the moving copy is
    // laid out unbounded and drawn inside a clip of this height, so a
    // height measured at 1x shears the tops and bottoms off.
    final scaled = tester.getSize(find.byType(WaxMarqueeText)).height;
    await _pump(tester, const WaxMarqueeText(_short), width: 110);
    await tester.pump();
    expect(
      scaled,
      greaterThan(tester.getSize(find.byType(WaxMarqueeText)).height),
    );

    await _pump(tester, const SizedBox.shrink());
  });

  testWidgets('reduced motion turned back off starts the line over', (
    tester,
  ) async {
    // Stopping the controller without clearing it leaves the re-arm
    // gate closed: the same title, the same overflow, and a controller
    // that is not null. The line stayed frozen wherever the stop caught
    // it, first characters clipped, until the track changed.
    await _pump(tester, const WaxMarqueeText(_long, velocity: 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(_offsetOf(tester), lessThan(0), reason: 'it was mid-travel');

    await _pump(
      tester,
      const WaxMarqueeText(_long, velocity: 100),
      reducedMotion: true,
    );
    await tester.pump();

    await _pump(tester, const WaxMarqueeText(_long, velocity: 100));
    await tester.pump();
    expect(
      _offsetOf(tester),
      0,
      reason: 'it came back frozen where the stop caught it',
    );

    await _pump(tester, const SizedBox.shrink());
  });

  testWidgets('a screen reader hears the whole name, not what is in frame', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const WaxMarqueeText(_long));
    await tester.pump();

    expect(find.bySemanticsLabel(_long), findsOneWidget);
    handle.dispose();
    await _pump(tester, const SizedBox.shrink());
  });
}
