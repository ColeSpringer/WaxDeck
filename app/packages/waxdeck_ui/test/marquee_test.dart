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
