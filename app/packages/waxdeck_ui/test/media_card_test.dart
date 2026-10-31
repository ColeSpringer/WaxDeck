import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/rendering.dart' show MatrixUtils, SemanticsNode;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// The semantics node carrying [id].
SemanticsFinder _byIdentifier(String id) => find.semantics.byPredicate(
  (node) => node.getSemanticsData().identifier == id,
  describeMatch: (_) => 'identifier "$id"',
);

/// [node]'s rect in the view's logical pixels: the root node's transform
/// carries the device pixel ratio.
Rect _globalRect(SemanticsNode node, double devicePixelRatio) {
  var rect = node.rect;
  for (SemanticsNode? n = node; n != null; n = n.parent) {
    if (n.transform case final transform?) {
      rect = MatrixUtils.transformRect(transform, rect);
    }
  }
  return Rect.fromLTRB(
    rect.left / devicePixelRatio,
    rect.top / devicePixelRatio,
    rect.right / devicePixelRatio,
    rect.bottom / devicePixelRatio,
  );
}

/// Where nothing of the card is.
const _away = Offset(700, 500);

/// The disc a revealed card draws: 60 logical pixels, on the cover's
/// centre.
const _disc = WaxSpace.touchTarget + 2 * WaxSpace.s8;

/// The nearest labelled node around the focus.
String _focusedLabel() {
  String? label;
  FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
    label = switch (e.widget) {
      Semantics(:final properties) => properties.label,
      _ => null,
    };
    return label == null;
  });
  return label ?? 'none';
}

void main() {
  var plays = 0;
  var taps = 0;
  var mores = 0;
  var pins = 0;
  var after = 0;

  setUp(() {
    plays = 0;
    taps = 0;
    mores = 0;
    pins = 0;
    after = 0;
  });

  MediaCard card({
    String? playLabel,
    bool more = false,
    bool pin = false,
    WaxCaptionMode? captions,
    bool playable = true,
    VoidCallback? onPlay,
  }) => MediaCard(
    width: 160,
    data: const MediaTileData(title: 'Harbour FM', subtitle: 'Nightjar'),
    captions: captions,
    onTap: () => taps++,
    onPlay: playable ? (onPlay ?? () => plays++) : null,
    onMore: more ? () => mores++ : null,
    action: pin
        ? MediaCardAction(
            glyph: WaxIcons.star,
            label: 'Pin',
            onPressed: () => pins++,
          )
        : null,
    playLabel: playLabel,
    playSemanticsId: 'play-id',
  );

  Future<void> pumpCard(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: buildWaxTheme(),
      localizationsDelegates: waxLocalizationsDelegates,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(40),
          child: Align(
            alignment: Alignment.topLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                child,
                WaxButton(label: 'After', onPressed: () => after++),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Rect cover(WidgetTester tester) => tester.getRect(find.byType(ArtworkImage));

  /// A mouse that arrives from outside the card at [to].
  Future<TestGesture> mouseTo(WidgetTester tester, Offset to) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: _away);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(to);
    await tester.pumpAndSettle();
    return gesture;
  }

  Future<void> tab(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
  }

  bool focusedUnder(Finder finder) {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return find
        .ancestor(
          of: find.byElementPredicate((element) => element == context),
          matching: finder,
          matchRoot: true,
        )
        .evaluate()
        .isNotEmpty;
  }

  testWidgets('the play affordance takes the verb its caller names', (
    tester,
  ) async {
    await pumpCard(tester, card(playLabel: 'Tune in Harbour FM'));
    await mouseTo(tester, cover(tester).topLeft + const Offset(12, 12));

    await tester.tap(find.bySemanticsLabel('Tune in Harbour FM'));
    await tester.pump();
    expect(plays, 1);
    expect(taps, 0);
  });

  testWidgets('the play affordance is its own semantics node while revealed', (
    tester,
  ) async {
    await pumpCard(tester, card());
    await mouseTo(tester, cover(tester).topLeft + const Offset(12, 12));

    expect(_byIdentifier('play-id'), findsOne);
    // A web click on a tappable node becomes that node's tap, so the
    // play has to be the node under the pointer, not the card.
    tester.semantics.tap(_byIdentifier('play-id'));
    await tester.pump();
    expect(plays, 1);
    expect(taps, 0);
  });

  testWidgets('not revealed, the node is absent and a cover tap calls onTap', (
    tester,
  ) async {
    await pumpCard(tester, card());

    expect(_byIdentifier('play-id'), findsNothing);
    await tester.tap(find.byType(ArtworkImage));
    await tester.pump();
    expect(taps, 1);
    expect(plays, 0);
  });

  testWidgets('a revealed cover still opens the tile off the play disc', (
    tester,
  ) async {
    await pumpCard(tester, card());
    await mouseTo(tester, cover(tester).topLeft + const Offset(12, 12));

    // The scrim is paint: a press beside the disc reaches the card.
    await tester.tapAt(
      cover(tester).topLeft + const Offset(12, 12),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(taps, 1);
    expect(plays, 0);
  });

  testWidgets('a mouse reveals the play whatever the highlight mode', (
    tester,
  ) async {
    // A touch on a touchscreen laptop flips the highlight mode; the hover
    // play has to survive it.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    await pumpCard(tester, card());
    await mouseTo(tester, cover(tester).center);
    expect(_byIdentifier('play-id'), findsOne);
  });

  testWidgets('entering on the disc and leaving from it hides the play', (
    tester,
  ) async {
    await pumpCard(tester, card());
    final gesture = await mouseTo(tester, cover(tester).center);
    expect(_byIdentifier('play-id'), findsOne);

    await gesture.moveTo(_away);
    await tester.pumpAndSettle();
    expect(_byIdentifier('play-id'), findsNothing);
  });

  testWidgets('moving from the cover onto the disc keeps the card revealed', (
    tester,
  ) async {
    await pumpCard(tester, card());
    final gesture = await mouseTo(
      tester,
      cover(tester).topLeft + const Offset(12, 12),
    );
    expect(_byIdentifier('play-id'), findsOne);

    await gesture.moveTo(cover(tester).center);
    await tester.pumpAndSettle();
    expect(_byIdentifier('play-id'), findsOne);
  });

  testWidgets('the play fades out, and is no target while it does', (
    tester,
  ) async {
    await pumpCard(tester, card());
    final gesture = await mouseTo(tester, cover(tester).center);
    await gesture.moveTo(_away);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(
      find.byWidgetPredicate(
        (widget) => widget is WaxIcon && widget.glyph == WaxIcons.play,
      ),
      findsOne,
      reason: 'still drawn, fading',
    );
    expect(_byIdentifier('play-id'), findsNothing);
    await tester.tapAt(cover(tester).center, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(plays, 0);
    expect(taps, 1);
  });

  testWidgets('the play node is the disc it is drawn as', (tester) async {
    await pumpCard(tester, card());
    await mouseTo(tester, cover(tester).topLeft + const Offset(12, 12));

    final disc = Rect.fromCenter(
      center: cover(tester).center,
      width: _disc,
      height: _disc,
    );
    final node = _byIdentifier('play-id').evaluate().single;
    expect(_globalRect(node, tester.view.devicePixelRatio), disc);

    // The rim, outside the old 44 px button and inside the disc.
    await tester.tapAt(
      cover(tester).center + const Offset(0, 26),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(plays, 1);
    expect(taps, 0);
  });

  testWidgets('a right click on the disc raises the card menu', (tester) async {
    await pumpCard(tester, card(more: true));
    await mouseTo(tester, cover(tester).center);

    await tester.tapAt(
      cover(tester).center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(mores, 1);
    expect(plays, 0);
  });

  testWidgets('Tab then Enter opens a playable card without chips', (
    tester,
  ) async {
    await pumpCard(tester, card());
    await tab(tester);
    expect(focusedUnder(find.byType(MediaCard)), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('a reveal keeps the card it revealed', (tester) async {
    await pumpCard(tester, card(captions: WaxCaptionMode.onHover));
    Element detector() => tester.element(
      find
          .descendant(
            of: find.byType(MediaCard),
            matching: find.byType(FocusableActionDetector),
          )
          .first,
    );
    final before = detector();
    final gesture = await mouseTo(tester, cover(tester).center);
    expect(identical(detector(), before), isTrue);
    await gesture.moveTo(_away);
    await tester.pumpAndSettle();
    expect(identical(detector(), before), isTrue);
  });

  testWidgets('the action chip keeps its focus across a reveal', (
    tester,
  ) async {
    await pumpCard(tester, card(pin: true));
    // The card, the disc its focus reveals, then the pin.
    await tab(tester);
    await tab(tester);
    await tab(tester);
    expect(focusedUnder(find.bySemanticsLabel('Pin')), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(pins, 1);
    expect(taps, 0);
  });

  testWidgets('Tab walks the card, its controls, then leaves it', (
    tester,
  ) async {
    await pumpCard(tester, card(more: true));
    final seen = <String>[];
    for (var i = 0; i < 6; i++) {
      await tab(tester);
      // The nearest labelled one: a tooltip's focus listener between the
      // node and the control is a Semantics with nothing to say.
      String? label;
      FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
        label = switch (e.widget) {
          Semantics(:final properties) => properties.label,
          _ => null,
        };
        return label == null;
      });
      seen.add(label ?? 'none');
      if (focusedUnder(find.byType(WaxButton))) break;
    }
    // Reading order: the disc sits left of the corner chips.
    expect(seen, <String>[
      'Harbour FM, Nightjar',
      'Play Harbour FM',
      'More for Harbour FM',
      'After',
    ]);
  });

  testWidgets('a disc taken away while focused lets the card go', (
    tester,
  ) async {
    // A station's tile drops its play while the station plays.
    final playing = ValueNotifier<bool>(false);
    addTearDown(playing.dispose);
    await pumpCard(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: playing,
        builder: (context, on, _) => card(
          more: true,
          captions: WaxCaptionMode.onHover,
          playable: !on,
          onPlay: () => playing.value = true,
        ),
      ),
    );
    await tab(tester);
    await tab(tester);
    expect(focusedUnder(find.bySemanticsLabel('Play Harbour FM')), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(playing.value, isTrue);

    for (var i = 0; i < 4 && !focusedUnder(find.byType(WaxButton)); i++) {
      await tab(tester);
    }
    expect(focusedUnder(find.byType(WaxButton)), isTrue);
    expect(
      find.semantics.byLabel('More for Harbour FM'),
      findsNothing,
      reason: 'nothing holds the card revealed',
    );

    playing.value = false;
    await tester.pumpAndSettle();
    expect(_byIdentifier('play-id'), findsNothing);
  });

  /// Moves focus straight to the button after the card, as a click on a
  /// field or a skip link does, without passing through the card's parts.
  Future<void> focusAfter(WidgetTester tester) async {
    tester
        .widget<FocusableActionDetector>(
          find.descendant(
            of: find.widgetWithText(WaxButton, 'After'),
            matching: find.byType(FocusableActionDetector),
          ),
        )
        .focusNode!
        .requestFocus();
    await tester.pumpAndSettle();
  }

  bool discShown(WidgetTester tester) =>
      tester.widget<HoverPlayDisc>(find.byType(HoverPlayDisc)).visible;

  testWidgets('an overflow chip taken away while focused lets the card go, '
      'though the action chip stays', (tester) async {
    final more = ValueNotifier<bool>(true);
    addTearDown(more.dispose);
    await pumpCard(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: more,
        builder: (context, on, _) =>
            card(more: on, pin: true, captions: WaxCaptionMode.onHover),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tab(tester);
    }
    expect(focusedUnder(find.bySemanticsLabel('More for Harbour FM')), isTrue);

    more.value = false;
    await tester.pumpAndSettle();
    await focusAfter(tester);
    expect(focusedUnder(find.byType(WaxButton)), isTrue);
    expect(discShown(tester), isFalse, reason: 'nothing holds it revealed');
  });

  testWidgets('a focused card whose play and menu both go keeps its ring '
      'true to its focus, and lets go when focus leaves', (tester) async {
    final parts = ValueNotifier<bool>(true);
    addTearDown(parts.dispose);
    await pumpCard(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: parts,
        builder: (context, on, _) =>
            card(playable: on, more: on, captions: WaxCaptionMode.onHover),
      ),
    );
    bool ring() => tester
        .widget<WaxFocusRing>(
          find
              .descendant(
                of: find.byType(MediaCard),
                matching: find.byType(WaxFocusRing),
              )
              .first,
        )
        .focused;
    await tab(tester);
    expect(focusedUnder(find.byType(MediaCard)), isTrue);
    expect(ring(), isTrue);

    parts.value = false;
    await tester.pumpAndSettle();
    expect(ring(), focusedUnder(find.byType(MediaCard)));

    await focusAfter(tester);
    expect(ring(), isFalse);
  });

  testWidgets('a short card in a tall cell reveals only over itself', (
    tester,
  ) async {
    await pumpCard(
      tester,
      SizedBox(width: 160, height: 400, child: card(more: true)),
    );
    final content = tester.getRect(
      find
          .descendant(
            of: find.byType(MediaCard),
            matching: find.byType(FocusableActionDetector),
          )
          .first,
    );
    await mouseTo(tester, Offset(content.center.dx, content.bottom + 30));
    expect(_byIdentifier('play-id'), findsNothing);
  });

  for (final playable in <bool>[false, true]) {
    final form = playable ? 'play-only' : 'bare';
    testWidgets('a $form card keeps its node and hover to its content in a '
        'tall cell', (tester) async {
      await pumpCard(
        tester,
        SizedBox(width: 160, height: 400, child: card(playable: playable)),
      );
      // From the cover's top to the last caption line's bottom.
      final content = cover(
        tester,
      ).expandToInclude(tester.getRect(find.text('Nightjar')));
      final node = find.semantics
          .byLabel(RegExp('^Harbour FM, Nightjar'))
          .evaluate()
          .single;
      final rect = _globalRect(node, tester.view.devicePixelRatio);
      expect(rect.top, closeTo(content.top, 0.5));
      expect(rect.bottom, closeTo(content.bottom, 0.5));
      expect(rect.width, closeTo(160, 0.5));
      // The card's own hover region is held to the content too.
      final region = tester.getRect(
        find
            .descendant(
              of: find.byType(MediaCard),
              matching: find.byType(MouseRegion),
            )
            .first,
      );
      expect(region.top, closeTo(content.top, 0.5));
      expect(region.bottom, closeTo(content.bottom, 0.5));

      if (!playable) return;
      await mouseTo(tester, Offset(content.center.dx, content.bottom + 30));
      expect(_byIdentifier('play-id'), findsNothing);
    });
  }

  testWidgets('the corner of the disc square plays, as the node does', (
    tester,
  ) async {
    await pumpCard(tester, card());
    await mouseTo(tester, cover(tester).topLeft + const Offset(12, 12));
    // Inside the 60 px square, outside the drawn circle.
    await tester.tapAt(
      cover(tester).center + const Offset(27, 27),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(plays, 1);
    expect(taps, 0);
  });

  group('reverse traversal mirrors forward', () {
    MediaCard titled(String title, {bool more = false, bool pin = false}) =>
        MediaCard(
          width: 160,
          data: MediaTileData(title: title, subtitle: 'Nightjar'),
          onTap: () => taps++,
          onPlay: () => plays++,
          onMore: more ? () => mores++ : null,
          action: pin
              ? MediaCardAction(
                  glyph: WaxIcons.star,
                  label: 'Pin $title',
                  onPressed: () => pins++,
                )
              : null,
        );

    Future<void> pumpRow(
      WidgetTester tester, {
      bool more = false,
      bool pin = false,
    }) => pumpCard(
      tester,
      Row(
        mainAxisSize: MainAxisSize.min,
        spacing: WaxSpace.s16,
        children: <Widget>[
          for (final title in <String>['Zero', 'One', 'Two'])
            titled(title, more: more, pin: pin),
        ],
      ),
    );

    Future<void> tabTo(WidgetTester tester, String label) async {
      for (var i = 0; i < 16 && _focusedLabel() != label; i++) {
        await tab(tester);
      }
      expect(_focusedLabel(), label);
    }

    Future<List<String>> walk(
      WidgetTester tester, {
      required bool back,
      required int steps,
    }) async {
      final seen = <String>[];
      for (var i = 0; i < steps; i++) {
        if (back) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
          await tester.pumpAndSettle();
        } else {
          await tab(tester);
        }
        seen.add(_focusedLabel());
      }
      return seen;
    }

    for (final (name, more, pin, parts) in <(String, bool, bool, List<String>)>[
      ('without chips', false, false, <String>['Play One']),
      (
        'with the overflow chip',
        true,
        false,
        <String>['Play One', 'More for One'],
      ),
      (
        'with the overflow and the action chip',
        true,
        true,
        <String>['Play One', 'More for One', 'Pin One'],
      ),
      (
        'with the action chip alone',
        false,
        true,
        <String>['Play One', 'Pin One'],
      ),
    ]) {
      testWidgets('$name, Tab walks a card and its parts forward', (
        tester,
      ) async {
        await pumpRow(tester, more: more, pin: pin);
        await tabTo(tester, 'One, Nightjar');
        expect(
          await walk(tester, back: false, steps: parts.length + 1),
          <String>[...parts, 'Two, Nightjar'],
        );
      });

      testWidgets('$name, Shift+Tab from the next card walks them back', (
        tester,
      ) async {
        await pumpRow(tester, more: more, pin: pin);
        await tabTo(tester, 'Two, Nightjar');
        expect(
          await walk(tester, back: true, steps: parts.length + 1),
          <String>[...parts.reversed, 'One, Nightjar'],
        );
        // Each part's focus revealed its card on the way.
        if (more) {
          await tabTo(tester, 'Two, Nightjar');
          await walk(tester, back: true, steps: pin ? 2 : 1);
          expect(_focusedLabel(), 'More for One');
          expect(find.semantics.byLabel('More for One'), findsOne);
          expect(
            tester
                .widgetList<HoverPlayDisc>(find.byType(HoverPlayDisc))
                .where((disc) => disc.visible)
                .length,
            1,
          );
        }
      });
    }

    testWidgets('a hidden overflow chip has no node and takes no press', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpCard(tester, titled('One', more: true, pin: true));
      expect(find.semantics.byLabel('More for One'), findsNothing);
      expect(find.semantics.byLabel('Play One'), findsNothing);

      // Where the overflow sits once shown: beside the pin, in the corner.
      final art = cover(tester);
      await tester.tapAt(
        Offset(
          art.right - WaxSpace.s8 - WaxSpace.touchTarget * 1.5,
          art.top + WaxSpace.s8 + WaxSpace.touchTarget / 2,
        ),
      );
      await tester.pump();
      expect(mores, 0);
      expect(taps, 1);
      handle.dispose();
    });
  });

  testWidgets('the scrim and the disc fade on one animation', (tester) async {
    await pumpCard(tester, card());
    Animation<double> fadeOf(Type part) => tester
        .widget<FadeTransition>(
          find
              .descendant(
                of: find.byType(part),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity;
    expect(identical(fadeOf(HoverPlayScrim), fadeOf(HoverPlayDisc)), isTrue);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: _away);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(cover(tester).topLeft + const Offset(12, 12));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final value = fadeOf(HoverPlayDisc).value;
    expect(value, greaterThan(0));
    expect(value, lessThan(1));
  });

  testWidgets('a play that comes back to a card nobody hovers starts hidden', (
    tester,
  ) async {
    // A station's tile drops its play while it plays, and gets it back
    // when playback moves on, by then usually under no pointer.
    final playable = ValueNotifier<bool>(true);
    addTearDown(playable.dispose);
    await pumpCard(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: playable,
        builder: (context, on, _) => card(playable: on),
      ),
    );
    final gesture = await mouseTo(
      tester,
      cover(tester).topLeft + const Offset(12, 12),
    );
    playable.value = false;
    await tester.pumpAndSettle();
    await gesture.moveTo(_away);
    await tester.pumpAndSettle();

    playable.value = true;
    final seen = <double>[];
    double opacityOf(Type part) => tester
        .widget<FadeTransition>(
          find
              .descendant(
                of: find.byType(part),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;
    for (final wait in <Duration>[
      Duration.zero,
      const Duration(milliseconds: 40),
      const Duration(milliseconds: 40),
    ]) {
      await tester.pump(wait);
      seen
        ..add(opacityOf(HoverPlayScrim))
        ..add(opacityOf(HoverPlayDisc));
    }
    expect(seen, everyElement(0.0));
  });

  testWidgets('the disc presses through ink on its node\'s own callback', (
    tester,
  ) async {
    await pumpCard(tester, card());
    final disc = find.byType(HoverPlayDisc);
    final ink = tester.widget<InkResponse>(
      find.descendant(of: disc, matching: find.byType(InkResponse)),
    );
    final node = tester.widget<WaxTappable>(
      find.descendant(of: disc, matching: find.byType(WaxTappable)),
    );
    expect(ink.onTap, same(node.onPressed));
    expect(ink.highlightShape, BoxShape.circle);
  });

  testWidgets('a pointer over the disc lights it', (tester) async {
    await pumpCard(tester, card());
    await mouseTo(tester, cover(tester).center);
    // The ink the disc draws on is its own, over its ground.
    final glyph = find
        .descendant(
          of: find.byType(HoverPlayDisc),
          matching: find.byType(WaxIcon),
        )
        .first;
    final ground = Material.of(tester.element(glyph)) as RenderObject;
    final hover = Theme.of(tester.element(glyph)).hoverColor;
    expect(ground, paints..circle(color: hover));
  });

  testWidgets('a card with every part builds where nothing above is ink', (
    tester,
  ) async {
    // A shelf a screen draws straight into a scroll view, with no
    // scaffold over it: the hidden overflow is built there too.
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWaxTheme(),
        localizationsDelegates: waxLocalizationsDelegates,
        home: Align(
          alignment: Alignment.topLeft,
          child: card(more: true, pin: true),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  group('arrow keys and a card\'s hidden parts', () {
    // The root actions, installed as the app installs them.
    Map<Type, Action<Intent>> rootActions(BuildContext context) =>
        waxAppActions(context);

    MediaCard titled(String title, {bool pin = false}) => MediaCard(
      width: 120,
      data: MediaTileData(title: title, subtitle: 'N'),
      onTap: () {},
      onPlay: () {},
      action: pin
          ? MediaCardAction(
              glyph: WaxIcons.star,
              label: 'Pin $title',
              onPressed: () {},
            )
          : null,
    );

    Future<void> pumpHost(WidgetTester tester, Widget body) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Builder(
          builder: (context) => MaterialApp(
            theme: buildWaxTheme(),
            localizationsDelegates: waxLocalizationsDelegates,
            actions: rootActions(context),
            home: Scaffold(body: body),
          ),
        ),
      );
    }

    Widget grid({
      bool pin = false,
      int count = 6,
      ScrollController? controller,
    }) => GridView.count(
      controller: controller,
      crossAxisCount: 3,
      childAspectRatio: 0.6,
      children: <Widget>[
        for (var i = 0; i < count; i++)
          titled(String.fromCharCode(0x41 + i), pin: pin),
      ],
    );

    Future<String> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      return _focusedLabel();
    }

    testWidgets('Down from a card lands on the card below, not its disc', (
      tester,
    ) async {
      await pumpHost(tester, grid());
      expect(await press(tester, LogicalKeyboardKey.tab), 'A, N');
      expect(await press(tester, LogicalKeyboardKey.arrowRight), 'B, N');
      expect(await press(tester, LogicalKeyboardKey.arrowRight), 'C, N');
      expect(await press(tester, LogicalKeyboardKey.arrowDown), 'F, N');
      expect(await press(tester, LogicalKeyboardKey.arrowLeft), 'E, N');
      expect(await press(tester, LogicalKeyboardKey.arrowUp), 'B, N');
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('Down off the rows in view scrolls the whole card in', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await pumpHost(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 600,
            height: 500,
            child: grid(count: 30, controller: scroll),
          ),
        ),
      );
      expect(await press(tester, LogicalKeyboardKey.tab), 'A, N');
      for (final title in <String>['D', 'G', 'J', 'M']) {
        expect(await press(tester, LogicalKeyboardKey.arrowDown), '$title, N');
        final card = FocusManager.instance.primaryFocus!.rect;
        expect(card.top, greaterThanOrEqualTo(-0.5), reason: title);
        expect(card.bottom, lessThanOrEqualTo(500.5), reason: title);
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets(
      'Down into a grid from a control above lands on the first card',
      (tester) async {
        await pumpHost(
          tester,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              WaxButton(label: 'Above', onPressed: () {}),
              Expanded(child: grid()),
            ],
          ),
        );
        expect(await press(tester, LogicalKeyboardKey.tab), 'Above');
        expect(await press(tester, LogicalKeyboardKey.arrowDown), 'A, N');
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets('Right from a disc across a shelf lands on the next card', (
      tester,
    ) async {
      await pumpHost(
        tester,
        ShelfRow(
          title: 'Recently added',
          cardWidth: 120,
          items: <MediaTileData>[
            for (final title in <String>['One', 'Two', 'Three'])
              MediaTileData(title: title, subtitle: 'N'),
          ],
          onTapItem: (_) {},
          onPlayItem: (_) {},
        ),
      );
      expect(await press(tester, LogicalKeyboardKey.tab), 'One, N');
      expect(await press(tester, LogicalKeyboardKey.tab), 'Play One');
      expect(await press(tester, LogicalKeyboardKey.arrowRight), 'Two, N');
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('Tab and Shift+Tab still reach a card\'s disc', (tester) async {
      await pumpHost(tester, grid());
      expect(await press(tester, LogicalKeyboardKey.tab), 'A, N');
      expect(await press(tester, LogicalKeyboardKey.tab), 'Play A');
      expect(await press(tester, LogicalKeyboardKey.tab), 'B, N');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pumpAndSettle();
      expect(_focusedLabel(), 'Play A');
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets(
      'other nodes, a card\'s drawn action chip among them, are left alone',
      (tester) async {
        await pumpHost(
          tester,
          Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  WaxButton(label: 'Left', onPressed: () {}),
                  WaxButton(label: 'Right', onPressed: () {}),
                ],
              ),
              Expanded(child: grid(pin: true)),
            ],
          ),
        );
        expect(await press(tester, LogicalKeyboardKey.tab), 'Left');
        expect(await press(tester, LogicalKeyboardKey.arrowRight), 'Right');
        // A card's action chip is drawn whether or not the card is
        // revealed, so a move may stop on it as on any control.
        for (var i = 0; i < 12 && _focusedLabel() != 'C, N'; i++) {
          await press(tester, LogicalKeyboardKey.tab);
        }
        expect(_focusedLabel(), 'C, N');
        expect(await press(tester, LogicalKeyboardKey.arrowDown), 'Pin F');
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  });

  testWidgets('the play node sits beside the card node', (tester) async {
    await pumpCard(tester, card(more: true));
    await mouseTo(tester, cover(tester).topLeft + const Offset(12, 12));
    final play = _byIdentifier('play-id').evaluate().single;
    final cardNode = find.semantics
        .byLabel(RegExp('^Harbour FM, Nightjar'))
        .evaluate()
        .single;
    expect(play.parent, same(cardNode.parent));
  });
}
