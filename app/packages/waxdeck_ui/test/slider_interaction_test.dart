import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// The pointer contract of the track controls: live reporting while a
/// drag moves, forgiveness at the ends and under a mouse's drift, and
/// scrolling left alone. Each of these was a filed bug: a level that
/// only changed on release, and clicks that demanded pixel accuracy.
Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(400, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWaxTheme(),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('slider', () {
    testWidgets('a drag reports the level while the finger moves', (
      tester,
    ) async {
      final reported = <double>[];
      await _pump(
        tester,
        WaxSlider(
          value: 0.5,
          trackWidth: 200,
          label: 'Volume',
          onChanged: reported.add,
        ),
      );

      final rect = tester.getRect(find.byType(WaxSlider));
      final centre = rect.center;
      final gesture = await tester.startGesture(centre);
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      // Deliberately off any step boundary, so the release has an exact
      // value the live stream has not already delivered: a release that
      // lands exactly on the last stepped report stays silent.
      await gesture.moveBy(const Offset(33, 0));
      await tester.pump();

      expect(
        reported,
        isNotEmpty,
        reason: 'the level must move under the finger, not on release',
      );
      for (final value in reported) {
        expect(
          (value / 0.05).round() * 0.05,
          moreOrLessEquals(value),
          reason: 'live values arrive quantized to the step',
        );
      }

      final before = reported.length;
      await gesture.up();
      await tester.pump();
      expect(
        reported.length,
        greaterThan(before),
        reason: 'release commits the exact final value',
      );
      // 63 px right of centre on a 200 px track is 0.815 of the way.
      expect(reported.last, moreOrLessEquals(0.815, epsilon: 0.001));
    });

    testWidgets('a held press hands over to the drag without a stale level', (
      tester,
    ) async {
      // Past the tap deadline the press has previewed the knob; when the
      // drag then claims the arena, the tap's cancel and the drag's
      // start resolve in one synchronous dispatch, so the preview never
      // renders fallen back to the old value and the live stream starts
      // from the drag.
      final reported = <double>[];
      await _pump(
        tester,
        WaxSlider(
          value: 0.5,
          trackWidth: 200,
          label: 'Volume',
          onChanged: reported.add,
        ),
      );

      final rect = tester.getRect(find.byType(WaxSlider));
      final gesture = await tester.startGesture(
        Offset(rect.left + WaxSlider.defaultEndSlop + 40, rect.center.dy),
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(reported, isEmpty, reason: 'a held press previews, only');

      await gesture.moveBy(const Offset(120, 0));
      await tester.pump();
      expect(
        reported,
        isNotEmpty,
        reason: 'the drag the press became reports live',
      );

      await gesture.up();
      await tester.pump();
      expect(reported.last, moreOrLessEquals(0.8, epsilon: 0.01));
    });

    testWidgets('the knob follows the finger before the arena settles', (
      tester,
    ) async {
      // Inside a scroll view a touch drag must travel the platform's
      // disambiguation slop before the track wins the pointer, and the
      // knob used to sit still through that stretch: the drag read as
      // lagging the finger. It paints from the first event now, while
      // the level still applies only once the drag actually wins.
      final reported = <double>[];
      await _pump(
        tester,
        ListView(
          children: [
            Center(
              child: WaxSlider(
                value: 0.5,
                trackWidth: 200,
                label: 'Volume',
                onChanged: reported.add,
              ),
            ),
          ],
        ),
      );

      final rect = tester.getRect(find.byType(WaxSlider));
      final gesture = await tester.startGesture(
        Offset(rect.left + WaxSlider.defaultEndSlop + 100, rect.center.dy),
      );
      await gesture.moveBy(const Offset(8, 0));
      await tester.pump();

      expect(reported, isEmpty, reason: 'nothing applies before a win');
      expect(
        tester.getSemantics(find.bySemanticsLabel('Volume')).value,
        '54%',
        reason: 'the knob already follows the finger',
      );

      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(reported, isNotEmpty, reason: 'the drag won and reports live');
      await gesture.up();
      await tester.pump();
    });

    testWidgets('a scroll that wins lets go of the knob', (tester) async {
      final reported = <double>[];
      await _pump(
        tester,
        ListView(
          children: [
            Center(
              child: WaxSlider(
                value: 0.5,
                trackWidth: 200,
                label: 'Volume',
                onChanged: reported.add,
              ),
            ),
            const SizedBox(height: 800),
          ],
        ),
      );

      final rect = tester.getRect(find.byType(WaxSlider));
      final gesture = await tester.startGesture(
        Offset(rect.left + WaxSlider.defaultEndSlop + 100, rect.center.dy),
      );
      // Vertical past the slop: the list claims the pointer. The raw
      // glide events keep arriving underneath, and must stop painting.
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();

      expect(reported, isEmpty, reason: 'a touch scroll must not set a level');
      expect(
        tester.getSemantics(find.bySemanticsLabel('Volume')).value,
        '50%',
        reason: 'the knob reverts when the scroll wins and stays put',
      );
      await gesture.up();
      await tester.pump();
    });

    testWidgets('a deliberate press-and-release click lands', (tester) async {
      // Press, pause past the tap deadline, release without moving: the
      // losing drag recognisers fire their cancels at the sweep the
      // release runs, before the winning tap's own callbacks, and
      // un-gated those cancels wiped the pressed preview - the tap then
      // committed the value the slider already had, a dead tap on the
      // most careful click there is.
      final reported = <double>[];
      await _pump(
        tester,
        WaxSlider(
          value: 0.2,
          trackWidth: 200,
          label: 'Volume',
          onChanged: reported.add,
        ),
      );

      final rect = tester.getRect(find.byType(WaxSlider));
      final gesture = await tester.startGesture(
        Offset(rect.left + WaxSlider.defaultEndSlop + 150, rect.center.dy),
      );
      await tester.pump(const Duration(milliseconds: 150));
      await gesture.up();
      await tester.pump();

      expect(reported, isNotEmpty, reason: 'the held click must land');
      expect(reported.last, moreOrLessEquals(0.75, epsilon: 0.01));
    });

    testWidgets('a mouse press applies the level before release', (
      tester,
    ) async {
      // A click used to land the moment it was pressed, and a press
      // that only painted until release read as a dead control under a
      // held button. Touch keeps the preview-only press (the held-press
      // case above); a mouse click is a decision.
      final reported = <double>[];
      await _pump(
        tester,
        WaxSlider(
          value: 0.2,
          trackWidth: 200,
          label: 'Volume',
          onChanged: reported.add,
        ),
      );

      final rect = tester.getRect(find.byType(WaxSlider));
      final gesture = await tester.startGesture(
        Offset(rect.left + WaxSlider.defaultEndSlop + 150, rect.center.dy),
        kind: PointerDeviceKind.mouse,
      );
      // Past the tap deadline, still held: the level has already moved.
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        reported,
        isNotEmpty,
        reason: 'a mouse click is a decision, not a preview',
      );
      expect(reported.last, moreOrLessEquals(0.75, epsilon: 0.03));

      await gesture.up();
      await tester.pump();
      expect(reported.last, moreOrLessEquals(0.75, epsilon: 0.01));
    });

    testWidgets('a mouse click with a pixel of drift still sets the level', (
      tester,
    ) async {
      // A mouse click drifts a pixel or two between press and release,
      // which is past the precise-pointer slop, so the tap recogniser
      // rejects it - and an ancestor vertical-drag handler (the player's
      // drag-to-dismiss, a scroll view) claims the gesture instead. The
      // click silently did nothing. The competitor here is the player
      // scaffold's shape: a plain vertical-drag detector over the whole
      // surface.
      final reported = <double>[];
      var surfaceDragged = false;
      await _pump(
        tester,
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (_) => surfaceDragged = true,
          child: Center(
            child: WaxSlider(
              value: 0.2,
              trackWidth: 200,
              label: 'Volume',
              onChanged: reported.add,
            ),
          ),
        ),
      );

      final rect = tester.getRect(find.byType(WaxSlider));
      // 0.75 of the drawn track: slop inset plus three quarters.
      final at = Offset(
        rect.left + WaxSlider.defaultEndSlop + 150,
        rect.center.dy,
      );
      final gesture = await tester.startGesture(
        at,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 2));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(reported, isNotEmpty, reason: 'the drifted click must land');
      expect(reported.last, moreOrLessEquals(0.75, epsilon: 0.01));
      expect(
        surfaceDragged,
        isFalse,
        reason: 'the click belongs to the track, not the surface behind it',
      );
    });

    testWidgets('one mouse click is one event', (tester) async {
      // The press applies the exact value and the release must not
      // repeat it: two events per click is two unordered network writes
      // for a caller like the remote volume.
      final reported = <double>[];
      await _pump(
        tester,
        WaxSlider(
          value: 0.2,
          trackWidth: 200,
          label: 'Volume',
          onChanged: reported.add,
        ),
      );

      final rect = tester.getRect(find.byType(WaxSlider));
      final gesture = await tester.startGesture(
        Offset(rect.left + WaxSlider.defaultEndSlop + 150, rect.center.dy),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(reported, hasLength(1), reason: 'one decision, one event');
      expect(reported.single, moreOrLessEquals(0.75, epsilon: 0.01));
    });

    testWidgets('a secondary click neither sets nor pins the level', (
      tester,
    ) async {
      // The raw listener hears every button and the recognisers refuse
      // all but the primary one, so nothing would ever commit or cancel
      // what a right-click pressed: it used to jump the level and leave
      // the knob pinned at the click. It must be no gesture at all -
      // and must not eat the primary click that follows.
      final reported = <double>[];
      await _pump(
        tester,
        WaxSlider(
          value: 0.2,
          trackWidth: 200,
          label: 'Volume',
          onChanged: reported.add,
        ),
      );

      final rect = tester.getRect(find.byType(WaxSlider));
      final at = Offset(
        rect.left + WaxSlider.defaultEndSlop + 150,
        rect.center.dy,
      );
      final secondary = await tester.startGesture(
        at,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await secondary.up();
      await tester.pump();

      expect(reported, isEmpty, reason: 'a right-click is not a level');
      expect(
        tester.getSemantics(find.bySemanticsLabel('Volume')).value,
        '20%',
        reason: 'nothing previews under a refused button',
      );

      final primary = await tester.startGesture(
        at,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await primary.up();
      await tester.pump();
      expect(reported, isNotEmpty, reason: 'the next real click still lands');
      expect(reported.last, moreOrLessEquals(0.75, epsilon: 0.01));
    });

    testWidgets('a platform cancel lets go of the preview', (tester) async {
      // A palm rejection or a system gesture ends the sequence with a
      // cancel no recogniser reports while nothing had claimed the
      // pointer; unanswered, the pressed preview stayed latched at the
      // press for good.
      final reported = <double>[];
      await _pump(
        tester,
        WaxSlider(
          value: 0.2,
          trackWidth: 200,
          label: 'Volume',
          onChanged: reported.add,
        ),
      );

      final rect = tester.getRect(find.byType(WaxSlider));
      final gesture = await tester.startGesture(
        Offset(rect.left + WaxSlider.defaultEndSlop + 150, rect.center.dy),
      );
      await tester.pump();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Volume')).value,
        '75%',
        reason: 'the press previews',
      );

      await gesture.cancel();
      await tester.pump();
      expect(reported, isEmpty, reason: 'a cancelled press applies nothing');
      expect(
        tester.getSemantics(find.bySemanticsLabel('Volume')).value,
        '20%',
        reason: 'the preview reverts when the platform takes the pointer',
      );
    });

    testWidgets('a press just past either track end clamps', (tester) async {
      final reported = <double>[];
      await _pump(
        tester,
        WaxSlider(
          value: 0.5,
          trackWidth: 200,
          label: 'Volume',
          onChanged: reported.add,
        ),
      );

      final rect = tester.getRect(find.byType(WaxSlider));
      await tester.tapAt(Offset(rect.right - 2, rect.center.dy));
      await tester.pump();
      expect(reported.last, 1.0);

      await tester.tapAt(Offset(rect.left + 2, rect.center.dy));
      await tester.pump();
      expect(reported.last, 0.0);
    });

    testWidgets('a slider disabled mid-drag lets go of the knob', (
      tester,
    ) async {
      // Disabling disposes the recognisers during the rebuild, and their
      // cancel callbacks land mid-build where setState must not run -
      // the state lets go of its preview in didUpdateWidget instead, so
      // the knob reads the value again rather than the dead preview.
      Future<void> pumpSlider(ValueChanged<double>? onChanged) => _pump(
        tester,
        WaxSlider(
          value: 0.2,
          trackWidth: 200,
          label: 'Volume',
          onChanged: onChanged,
        ),
      );

      await pumpSlider((_) {});
      final rect = tester.getRect(find.byType(WaxSlider));
      final gesture = await tester.startGesture(
        Offset(rect.left + WaxSlider.defaultEndSlop + 180, rect.center.dy),
      );
      await tester.pump(const Duration(milliseconds: 150));

      await pumpSlider(null);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Volume')).value,
        '20%',
        reason: 'the knob reads the value again, not the dead preview',
      );

      // The disable also swallowed the release (the listener callbacks
      // were nulled), so the track must let go of the followed pointer
      // itself or every press after re-enabling is refused.
      final reported = <double>[];
      await pumpSlider(reported.add);
      await tester.tapAt(
        Offset(rect.left + WaxSlider.defaultEndSlop + 150, rect.center.dy),
      );
      await tester.pump();
      expect(
        reported,
        isNotEmpty,
        reason: 're-enabled, the next press must land',
      );
      expect(
        reported.last,
        moreOrLessEquals(0.75, epsilon: 0.01),
        reason: 'landed where it was pressed, not a commit of the old value',
      );
    });

    testWidgets('a touch scroll over the slider is still a scroll', (
      tester,
    ) async {
      final reported = <double>[];
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        ListView(
          controller: controller,
          children: <Widget>[
            const SizedBox(height: 200),
            Center(
              child: WaxSlider(
                value: 0.5,
                trackWidth: 200,
                label: 'Volume',
                onChanged: reported.add,
              ),
            ),
            const SizedBox(height: 800),
          ],
        ),
      );

      final gesture = await tester.startGesture(
        tester.getRect(find.byType(WaxSlider)).center,
      );
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(0, -30));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(controller.offset, greaterThan(0), reason: 'the list scrolled');
      expect(
        reported,
        isEmpty,
        reason: 'a scroll that started on the track sets no level',
      );
    });
  });

  group('seek bar', () {
    testWidgets('a scrub previews and commits only on release', (tester) async {
      final sought = <Duration>[];
      await _pump(
        tester,
        SizedBox(
          width: 400,
          child: WaxSeekBar(
            position: const Duration(seconds: 25),
            duration: const Duration(seconds: 100),
            onSeek: sought.add,
          ),
        ),
      );

      final rect = tester.getRect(find.byType(WaxSeekBar));
      final gesture = await tester.startGesture(
        Offset(rect.left + 100, rect.center.dy),
      );
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      expect(
        sought,
        isEmpty,
        reason: 'a live seek per drag frame would spam stream loads',
      );

      await gesture.up();
      await tester.pump();
      expect(sought, hasLength(1));
      expect(
        sought.single.inMilliseconds,
        closeTo(75000, 2000),
        reason: 'release seeks to where the scrub ended',
      );
    });

    testWidgets('a bar disabled mid-scrub releases the playhead', (
      tester,
    ) async {
      // A frame arriving with no duration disables the bar, which
      // disposes the recognisers during the rebuild; their cancel
      // callbacks land mid-build where setState must not run, so the
      // state lets go in didUpdateWidget and the playhead is not pinned
      // where the finger was.
      Future<void> pumpPair(Duration duration) => _pump(
        tester,
        Column(
          children: <Widget>[
            SizedBox(
              width: 400,
              child: WaxSeekBar(
                key: const Key('scrubbed'),
                position: const Duration(seconds: 25),
                duration: duration,
                onSeek: duration > Duration.zero ? (_) {} : null,
              ),
            ),
            SizedBox(
              width: 400,
              child: WaxSeekBar(
                key: const Key('untouched'),
                position: const Duration(seconds: 25),
                duration: duration,
                onSeek: duration > Duration.zero ? (_) {} : null,
              ),
            ),
          ],
        ),
      );

      await pumpPair(const Duration(seconds: 100));
      final scrubbed = find.byKey(const Key('scrubbed'));
      final gesture = await tester.startGesture(
        tester.getRect(scrubbed).centerLeft + const Offset(300, 0),
      );
      await tester.pump(const Duration(milliseconds: 150));

      await pumpPair(Duration.zero);
      await gesture.up();
      await tester.pumpAndSettle();

      CustomPainter painterOf(Finder bar) => tester
          .widget<CustomPaint>(
            find.descendant(of: bar, matching: find.byType(CustomPaint)).first,
          )
          .painter!;
      expect(
        painterOf(
          scrubbed,
        ).shouldRepaint(painterOf(find.byKey(const Key('untouched')))),
        isFalse,
        reason: 'the scrub let go when the bar disabled',
      );
    });

    testWidgets('the plain bar is a full touch target', (tester) async {
      // A 24 px box over a 4 px track demanded the accuracy the bug
      // report named; the box is the touch target whatever is drawn.
      await _pump(
        tester,
        SizedBox(
          width: 400,
          child: WaxSeekBar(
            position: Duration.zero,
            duration: const Duration(seconds: 100),
            onSeek: (_) {},
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(WaxSeekBar)).height,
        WaxSpace.touchTarget,
      );
    });
  });
}
