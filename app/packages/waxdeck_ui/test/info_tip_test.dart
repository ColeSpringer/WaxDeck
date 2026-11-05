import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

const _message = 'Counts only the plays you finished';

Widget _page(Widget body) => MaterialApp(
  theme: buildWaxTheme(variant: WaxThemeVariant.dark),
  localizationsDelegates: waxLocalizationsDelegates,
  supportedLocales: WaxLocalizations.supportedLocales,
  home: Scaffold(body: body),
);

Widget _host(Widget tip) => _page(
  Column(
    children: <Widget>[
      Center(child: tip),
      Expanded(
        child: GestureDetector(
          key: const Key('elsewhere'),
          behavior: HitTestBehavior.opaque,
          onTap: () {},
        ),
      ),
    ],
  ),
);

void main() {
  testWidgets('an info tip opens its text on tap and names it in semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(const WaxInfoTip(message: _message, semanticsId: 'tip')),
    );

    expect(find.text(_message), findsNothing);
    final node = tester.getSemantics(find.bySemanticsIdentifier('tip'));
    expect(node.label, _message);
    expect(node.getSemanticsData().flagsCollection.isButton, isTrue);

    await tester.tap(find.byType(WaxInfoTip));
    await tester.pump();
    expect(find.text(_message), findsOne);

    handle.dispose();
  });

  testWidgets('a label names the glyph and the message stays the popover', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        const WaxInfoTip(
          message: _message,
          label: 'About play counts',
          semanticsId: 'tip',
        ),
      ),
    );

    expect(
      tester.getSemantics(find.bySemanticsIdentifier('tip')).label,
      'About play counts',
    );
    await tester.tap(find.byType(WaxInfoTip));
    await tester.pump();
    expect(find.text(_message), findsOne);

    handle.dispose();
  });

  testWidgets('a second tap, an outside tap and Escape each close it', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const WaxInfoTip(message: _message)));

    await tester.tap(find.byType(WaxInfoTip));
    await tester.pump();
    expect(find.text(_message), findsOne);
    await tester.tap(find.byType(WaxInfoTip));
    await tester.pump();
    expect(find.text(_message), findsNothing);

    await tester.tap(find.byType(WaxInfoTip));
    await tester.pump();
    await tester.tap(find.byKey(const Key('elsewhere')));
    await tester.pump();
    expect(find.text(_message), findsNothing);

    await tester.tap(find.byType(WaxInfoTip));
    await tester.pump();
    expect(find.text(_message), findsOne);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text(_message), findsNothing);
  });

  testWidgets('hovering the glyph shows the text after the tooltip delay', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const WaxInfoTip(message: _message)));
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);

    await pointer.moveTo(tester.getCenter(find.byType(WaxInfoTip)));
    await tester.pump();
    expect(find.text(_message), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text(_message), findsOne);
  });

  testWidgets('keyboard focus on the glyph shows the text', (tester) async {
    await tester.pumpWidget(
      _host(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const WaxInfoTip(message: _message),
            WaxButton(label: 'Next', onPressed: () {}),
          ],
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();
    expect(find.text(_message), findsOne);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();
    expect(find.text(_message), findsNothing);
  });

  testWidgets('Enter on the focused glyph opens it once, and Escape closes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const WaxInfoTip(message: _message),
            WaxButton(label: 'Next', onPressed: () {}),
          ],
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    // The focus label gave way to the popover rather than doubling it.
    expect(find.text(_message), findsOne);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    // Focus is back on the glyph, so its own label is what is left.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();
    expect(find.text(_message), findsNothing);
  });

  group('the popover and the label are one text', () {
    Widget tipAndNext() => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const WaxInfoTip(message: _message),
        WaxButton(label: 'Next', onPressed: () {}),
      ],
    );

    bool glyphHoldsFocus() =>
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<WaxInfoTip>() !=
        null;

    testWidgets('tabbing away from an open popover closes it', (tester) async {
      await tester.pumpWidget(_host(tipAndNext()));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsOne);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsNothing);

      // Round again: one copy, the focus label, and never two.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsOne);
    });

    testWidgets('hovering again while the popover is open shows one copy', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const WaxInfoTip(message: _message)));
      final center = tester.getCenter(find.byType(WaxInfoTip));
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      addTearDown(pointer.removePointer);

      await pointer.moveTo(center);
      await pointer.down(center);
      await pointer.up();
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsOne);

      await pointer.moveTo(const Offset(5, 5));
      await tester.pump();
      await pointer.moveTo(center);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text(_message), findsOne);
    });

    testWidgets('Escape leaves no text and returns focus to the glyph', (
      tester,
    ) async {
      await tester.pumpWidget(_host(tipAndNext()));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump();

      expect(find.text(_message), findsNothing);
      expect(glyphHoldsFocus(), isTrue);

      // Leaving and coming back is a fresh arrival, which labels again.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsOne);
    });

    testWidgets('Escape on a focus label dismisses it', (tester) async {
      await tester.pumpWidget(_host(tipAndNext()));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsOne);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text(_message), findsNothing);
    });

    testWidgets('Escape with the node it came from gone does not throw', (
      tester,
    ) async {
      final present = ValueNotifier<bool>(true);
      await tester.pumpWidget(
        _host(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ValueListenableBuilder<bool>(
                valueListenable: present,
                builder: (_, here, _) => here
                    ? const Focus(
                        autofocus: true,
                        child: SizedBox.square(dimension: 10),
                      )
                    : const SizedBox(),
              ),
              const WaxInfoTip(message: _message),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(WaxInfoTip));
      await tester.pump();
      await tester.pump();
      present.value = false;
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.text(_message), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('beside a scrolling page', () {
    Widget scrolling({double lead = 100}) => ListView(
      children: <Widget>[
        SizedBox(height: lead),
        const Align(
          alignment: Alignment.centerLeft,
          child: WaxInfoTip(message: _message),
        ),
        for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('r$i')),
      ],
    );

    testWidgets('a wheel scroll closes the popover with its glyph moving', (
      tester,
    ) async {
      await tester.pumpWidget(_page(scrolling()));
      await tester.tap(find.byType(WaxInfoTip));
      await tester.pump();
      expect(find.text(_message), findsOne);

      final wheel = TestPointer(7, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(wheel.hover(const Offset(400, 400)));
      await tester.sendEventToBinding(wheel.scroll(const Offset(0, 120)));
      await tester.pump();
      await tester.pump();

      expect(find.text(_message), findsNothing);
    });

    testWidgets('tabbing to a glyph below the fold labels it inside the view', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 300));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _page(
          ListView(
            children: <Widget>[
              for (var i = 0; i < 4; i++)
                SizedBox(height: 100, child: Text('row $i')),
              const Align(
                alignment: Alignment.centerLeft,
                child: WaxInfoTip(message: _message),
              ),
              const SizedBox(height: 300),
            ],
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final label = tester.getRect(find.text(_message));
      expect(label.bottom, lessThanOrEqualTo(300));
      expect(label.top, greaterThanOrEqualTo(0));
      expect(
        tester.getRect(find.byType(WaxInfoTip)).bottom,
        lessThanOrEqualTo(300),
      );
    });
  });

  group('after the popover closes', () {
    Widget tipAndNext() => _host(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const WaxInfoTip(message: _message),
          WaxButton(label: 'Next', onPressed: () {}),
        ],
      ),
    );

    Future<void> openByKeyboard(WidgetTester tester) async {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
    }

    Future<TestGesture> mouseAt(WidgetTester tester, Offset at) async {
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: at);
      addTearDown(pointer.removePointer);
      return pointer;
    }

    testWidgets('hovering the glyph labels it again, Escape return or not', (
      tester,
    ) async {
      await tester.pumpWidget(tipAndNext());
      final glyph = tester.getCenter(find.byType(WaxInfoTip));
      final pointer = await mouseAt(tester, const Offset(700, 500));
      await openByKeyboard(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsNothing);

      for (var visit = 0; visit < 2; visit++) {
        await pointer.moveTo(glyph);
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pump();
        expect(find.text(_message), findsOne, reason: 'hover $visit');
        await pointer.moveTo(const Offset(700, 500));
        await tester.pump();
        expect(find.text(_message), findsNothing);
      }
    });

    testWidgets('a click elsewhere leaves no label for the same focus', (
      tester,
    ) async {
      await tester.pumpWidget(tipAndNext());
      await openByKeyboard(tester);
      expect(find.text(_message), findsOne);

      final pointer = await mouseAt(tester, const Offset(700, 500));
      await pointer.down(tester.getCenter(find.byKey(const Key('elsewhere'))));
      await pointer.up();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsNothing);
    });

    testWidgets('a second press on the glyph leaves no label either', (
      tester,
    ) async {
      await tester.pumpWidget(tipAndNext());
      await openByKeyboard(tester);

      final glyph = tester.getCenter(find.byType(WaxInfoTip));
      final pointer = await mouseAt(tester, glyph);
      await pointer.down(glyph);
      await pointer.up();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsNothing);
    });

    Future<void> shiftTab(WidgetTester tester) async {
      await simulateKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await simulateKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      await tester.pump();
    }

    Future<TestGesture> clickGlyph(WidgetTester tester) async {
      final glyph = tester.getCenter(find.byType(WaxInfoTip));
      final pointer = await mouseAt(tester, const Offset(700, 500));
      await pointer.moveTo(glyph);
      await pointer.down(glyph);
      await pointer.up();
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsOne);
      return pointer;
    }

    testWidgets('a pointer popover closed by a click elsewhere leaves a '
        'later Tab onto the glyph labelled', (tester) async {
      await tester.pumpWidget(tipAndNext());
      final pointer = await clickGlyph(tester);

      await pointer.moveTo(const Offset(700, 500));
      await pointer.down(const Offset(700, 500));
      await pointer.up();
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsOne);
    });

    testWidgets('with another control focused first, Shift+Tab onto the '
        'glyph after a pointer popover is labelled', (tester) async {
      await tester.pumpWidget(tipAndNext());
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final pointer = await clickGlyph(tester);

      await pointer.moveTo(const Offset(700, 500));
      await pointer.down(const Offset(700, 500));
      await pointer.up();
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsNothing);

      await shiftTab(tester);
      expect(find.text(_message), findsOne);
    });

    testWidgets('a popover closed by a scroll leaves a later Tab labelled', (
      tester,
    ) async {
      await tester.pumpWidget(
        _page(
          ListView(
            children: <Widget>[
              const SizedBox(height: 100),
              const Align(
                alignment: Alignment.centerLeft,
                child: WaxInfoTip(message: _message),
              ),
              for (var i = 0; i < 40; i++)
                SizedBox(height: 60, child: Text('r$i')),
            ],
          ),
        ),
      );
      await tester.tap(find.byType(WaxInfoTip));
      await tester.pump();
      await tester.pump();
      final wheel = TestPointer(7, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(wheel.hover(const Offset(400, 400)));
      await tester.sendEventToBinding(wheel.scroll(const Offset(0, 40)));
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsOne);
    });

    testWidgets('Escape on a pointer popover with no focus before it leaves '
        'a later Tab labelled', (tester) async {
      await tester.pumpWidget(tipAndNext());
      await clickGlyph(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsOne);
    });

    testWidgets('a fresh arrival from the keyboard labels again', (
      tester,
    ) async {
      await tester.pumpWidget(tipAndNext());
      await openByKeyboard(tester);
      await tester.tap(find.byKey(const Key('elsewhere')));
      await tester.pump();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsOne);
    });
  });

  group('a pointer open leaves focus where it was', () {
    String? focusedButton() => FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<WaxButton>()
        ?.label;

    Widget fieldAndTip(FocusNode field) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 240,
          child: WaxTextField(label: 'Name', focusNode: field),
        ),
        const WaxInfoTip(message: _message),
      ],
    );

    testWidgets('a tap beside a focused text field leaves the field focused '
        'and the popover open', (tester) async {
      final field = FocusNode();
      addTearDown(field.dispose);
      await tester.pumpWidget(_host(fieldAndTip(field)));
      field.requestFocus();
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.tap(find.byType(WaxInfoTip));
      await tester.pump();
      await tester.pump();

      expect(find.text(_message), findsOne);
      expect(field.hasPrimaryFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue, reason: 'the keyboard');
    });

    testWidgets('after a mouse open, Tab moves on from the control that '
        'held focus', (tester) async {
      await tester.pumpWidget(
        _host(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              WaxButton(label: 'First', onPressed: () {}),
              WaxButton(label: 'Second', onPressed: () {}),
              const WaxInfoTip(message: _message),
            ],
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusedButton(), 'First');

      final glyph = tester.getCenter(find.byType(WaxInfoTip));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: glyph);
      addTearDown(mouse.removePointer);
      await mouse.down(glyph);
      await mouse.up();
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsOne);
      expect(focusedButton(), 'First');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusedButton(), 'Second');
    });

    testWidgets('Escape closes a pointer popover and takes only that press', (
      tester,
    ) async {
      final field = FocusNode();
      addTearDown(field.dispose);
      var escapes = 0;
      await tester.pumpWidget(
        _host(
          Focus(
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                escapes++;
              }
              return KeyEventResult.ignored;
            },
            child: fieldAndTip(field),
          ),
        ),
      );
      field.requestFocus();
      await tester.pump();
      await tester.tap(find.byType(WaxInfoTip));
      await tester.pump();
      await tester.pump();
      expect(field.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text(_message), findsNothing);
      expect(field.hasPrimaryFocus, isTrue);
      expect(escapes, 0, reason: 'closing the popover was that press');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(escapes, 1, reason: 'with nothing open the key is the field\'s');
    });

    testWidgets('Tab after a tap open moves on and closes the popover', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              WaxButton(label: 'First', onPressed: () {}),
              WaxButton(label: 'Second', onPressed: () {}),
              const WaxInfoTip(message: _message),
            ],
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.tap(find.byType(WaxInfoTip));
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsOne);
      expect(focusedButton(), 'First');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump();
      expect(focusedButton(), 'Second');
      expect(find.text(_message), findsNothing);
    });

    testWidgets('a dialog opened from the focused control takes its own '
        'first Escape', (tester) async {
      await tester.pumpWidget(
        _page(
          Builder(
            builder: (context) => Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  WaxButton(
                    label: 'Rename',
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => Dialog(
                        child: WaxButton(label: 'Save', onPressed: () {}),
                      ),
                    ),
                  ),
                  const WaxInfoTip(message: _message),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.tap(find.byType(WaxInfoTip));
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsOne);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOne);
      expect(find.text(_message), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('a mouse press on the glyph closes a popover a tap opened '
        'beside a field', (tester) async {
      // The press first drops the field's focus to the page, as a mouse
      // press beside a field does, then toggles the popover shut.
      final field = FocusNode();
      addTearDown(field.dispose);
      await tester.pumpWidget(_host(fieldAndTip(field)));
      field.requestFocus();
      await tester.pump();
      await tester.tap(find.byType(WaxInfoTip));
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsOne);

      final glyph = tester.getCenter(find.byType(WaxInfoTip));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: glyph);
      addTearDown(mouse.removePointer);
      await mouse.down(glyph);
      await tester.pump();
      await mouse.up();
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsNothing);
    });

    testWidgets('focus that lands on the glyph keeps a tap-opened popover', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const WaxInfoTip(message: _message),
              WaxButton(label: 'Next', onPressed: () {}),
            ],
          ),
        ),
      );
      await tester.tap(find.byType(WaxInfoTip));
      await tester.pump();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<WaxTappable>()
            ?.label,
        _message,
      );
      expect(find.text(_message), findsOne);
    });

    testWidgets('a pointer popover is no tab stop', (tester) async {
      await tester.pumpWidget(
        _host(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const WaxInfoTip(message: _message),
              WaxButton(label: 'Next', onPressed: () {}),
            ],
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusedButton(), 'Next');
      await tester.tap(find.byType(WaxInfoTip));
      await tester.pump();
      await tester.pump();

      // From the last control Tab comes round to the glyph, not into the
      // popover hanging under the row.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<WaxTappable>(),
        isNotNull,
      );
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<WaxInfoTip>(),
        isNotNull,
      );
    });
  });

  testWidgets('the label is gone in the first frame the popover shows', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const WaxInfoTip(message: _message)));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();
    expect(find.text(_message), findsOne);

    await simulateKeyDownEvent(LogicalKeyboardKey.enter);
    await simulateKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text(_message), findsOne);
  });

  group('for assistive technology', () {
    testWidgets('a label keeps the message reachable without a press', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const WaxInfoTip(
            message: _message,
            label: 'About play counts',
            semanticsId: 'tip',
          ),
        ),
      );

      final data = tester
          .getSemantics(find.bySemanticsIdentifier('tip'))
          .getSemanticsData();
      expect(data.label, 'About play counts');
      expect('${data.tooltip}${data.hint}', contains(_message));
      handle.dispose();
    });

    testWidgets('no label means the message is spoken once', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(const WaxInfoTip(message: _message, semanticsId: 'tip')),
      );

      final data = tester
          .getSemantics(find.bySemanticsIdentifier('tip'))
          .getSemanticsData();
      expect(data.label, _message);
      expect(data.tooltip, isEmpty);
      expect(data.hint, isEmpty);
      handle.dispose();
    });
  });

  group('when the window changes under an open popover', () {
    Widget at(Alignment alignment) => _page(
      Align(
        alignment: alignment,
        child: const WaxInfoTip(message: _message),
      ),
    );

    testWidgets('it stays while the glyph does not move', (tester) async {
      addTearDown(tester.view.reset);
      await tester.pumpWidget(at(Alignment.topLeft));
      await tester.tap(find.byType(WaxInfoTip));
      await tester.pump();

      // A keyboard coming and going, as when focus leaves a text field.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsOne);
    });

    testWidgets('it closes when the glyph moves', (tester) async {
      addTearDown(tester.view.reset);
      await tester.pumpWidget(at(Alignment.bottomRight));
      await tester.tap(find.byType(WaxInfoTip));
      await tester.pump();
      expect(find.text(_message), findsOne);

      tester.view.physicalSize = const Size(600, 400);
      await tester.pump();
      await tester.pump();
      expect(find.text(_message), findsNothing);
    });
  });

  testWidgets('a scroll that ends it as the tip is removed does not throw', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_page(_Harness(key: key, controller: controller)));
    await tester.tap(find.byType(WaxInfoTip));
    await tester.pump();
    expect(find.text(_message), findsOne);

    // The jump lands in the build that also drops the tip.
    key.currentState!.dropTipAndJump();
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text(_message), findsNothing);
  });

  group(
    'a host draws its info right after its title, on the title\'s line',
    () {
      WaxSwitch toggle() =>
          WaxSwitch(value: false, label: 'Crossfade', onChanged: (_) {});

      for (final (name, host, title) in <(String, Widget, String)>[
        (
          'a setting row',
          WaxSettingRow(
            title: 'Crossfade',
            info: _message,
            infoSemanticsId: 'tip',
            control: toggle(),
          ),
          'Crossfade',
        ),
        (
          'a setting row with a help line',
          WaxSettingRow(
            title: 'Crossfade',
            help: 'Overlap the end of one track with the next',
            info: _message,
            infoSemanticsId: 'tip',
            glyph: WaxIcons.downloads,
            control: toggle(),
          ),
          'Crossfade',
        ),
        (
          'a section header',
          SectionHeader(
            overline: 'Playback',
            title: 'Listening',
            info: _message,
            infoSemanticsId: 'tip',
            actionLabel: 'Reset',
            onAction: () {},
          ),
          'Listening',
        ),
        (
          'a title given its info directly',
          titleWithInfo(const Text('Listening'), _message, semanticsId: 'tip'),
          'Listening',
        ),
      ]) {
        testWidgets(name, (tester) async {
          final handle = tester.ensureSemantics();
          await tester.pumpWidget(
            _page(Center(child: SizedBox(width: 480, child: host))),
          );
          final words = tester.getRect(find.text(title));
          final glyph = tester.getRect(find.byType(WaxInfoTip));
          expect(glyph.left, moreOrLessEquals(words.right, epsilon: 0.01));
          expect(
            glyph.center.dy,
            moreOrLessEquals(words.center.dy, epsilon: 1),
          );
          expect(
            tester.getSemantics(find.bySemanticsIdentifier('tip')).label,
            _message,
          );

          await tester.tap(find.byType(WaxInfoTip));
          await tester.pumpAndSettle();
          expect(find.text(_message), findsOneWidget);
          handle.dispose();
        });
      }

      testWidgets('a title given its info directly can be any widget', (
        tester,
      ) async {
        await tester.pumpWidget(
          _page(
            Center(
              child: SizedBox(
                width: 480,
                child: titleWithInfo(toggle(), _message),
              ),
            ),
          ),
        );
        final control = tester.getRect(find.byType(WaxSwitch));
        final glyph = tester.getRect(find.byType(WaxInfoTip));
        expect(glyph.left, moreOrLessEquals(control.right, epsilon: 0.01));
        expect(
          glyph.center.dy,
          moreOrLessEquals(control.center.dy, epsilon: 1),
        );
      });

      testWidgets('and none without one', (tester) async {
        await tester.pumpWidget(
          _page(
            Column(
              children: <Widget>[
                WaxSettingRow(title: 'Crossfade', control: toggle()),
                const SectionHeader(title: 'Listening'),
                titleWithInfo(const Text('Listening'), null),
              ],
            ),
          ),
        );
        expect(find.byType(WaxInfoTip), findsNothing);
      });
    },
  );

  group('a host in a slot that sets its height', () {
    WaxSettingRow row({String? info, String title = 'Crossfade'}) =>
        WaxSettingRow(
          title: title,
          info: info,
          control: WaxSwitch(value: false, label: title, onChanged: (_) {}),
        );

    // A fixed height, a column's share, a list's item extent.
    final slots = <(String, Widget Function(Widget))>[
      (
        'a fixed-height box',
        (host) => SizedBox(width: 420, height: 96, child: host),
      ),
      (
        'an Expanded',
        (host) => SizedBox(
          width: 420,
          height: 96,
          child: Column(children: <Widget>[Expanded(child: host)]),
        ),
      ),
      (
        'a list with an item extent',
        (host) => SizedBox(
          width: 420,
          height: 300,
          child: ListView(itemExtent: 96, children: <Widget>[host]),
        ),
      ),
    ];

    Future<void> pumpIn(WidgetTester tester, Widget slot) => tester.pumpWidget(
      _page(Align(alignment: Alignment.topLeft, child: slot)),
    );

    for (final (name, slot) in slots) {
      testWidgets('$name: a setting row fills it and centres its line, info '
          'or none, and its dry and intrinsic sizes agree', (tester) async {
        final seen = <String, ({Rect title, double minH, double maxH})>{};
        for (final info in <String?>[null, _message]) {
          await pumpIn(tester, slot(row(info: info)));
          final box = tester.renderObject<RenderBox>(
            find.byType(WaxSettingRow),
          );
          final whole = tester.getRect(find.byType(WaxSettingRow));
          final title = tester.getRect(find.text('Crossfade'));
          final why = info == null ? 'without info' : 'with info';
          expect(whole.size, const Size(420, 96), reason: why);
          expect(
            title.center.dy,
            moreOrLessEquals(whole.center.dy, epsilon: 0.5),
            reason: why,
          );
          expect(box.getDryLayout(box.constraints), box.size, reason: why);
          seen[why] = (
            title: title,
            minH: box.getMinIntrinsicHeight(420),
            maxH: box.getMaxIntrinsicHeight(420),
          );
          if (info != null) {
            final tip = tester.getRect(find.byType(WaxInfoTip));
            expect(tip.left, moreOrLessEquals(title.right, epsilon: 0.01));
            expect(
              tip.center.dy,
              moreOrLessEquals(title.center.dy, epsilon: 1),
            );
          }
        }
        expect(seen['with info'], seen['without info']);
      });

      testWidgets('$name: a section header lays out alike, info or none', (
        tester,
      ) async {
        final rects = <Rect>[];
        for (final info in <String?>[null, _message]) {
          await pumpIn(
            tester,
            slot(SectionHeader(title: 'Listening', info: info)),
          );
          rects.add(tester.getRect(find.byType(SectionHeader)));
        }
        expect(rects.first, rects.last);
        expect(rects.first.size, const Size(420, 96));
      });
    }

    testWidgets('in a tight slot the tip follows a title that moves', (
      tester,
    ) async {
      final title = ValueNotifier<String>('Crossfade');
      addTearDown(title.dispose);
      await pumpIn(
        tester,
        SizedBox(
          width: 420,
          height: 96,
          child: ValueListenableBuilder<String>(
            valueListenable: title,
            builder: (_, words, _) => row(info: _message, title: words),
          ),
        ),
      );
      title.value = 'Crossfade between albums';
      await tester.pump();
      final words = tester.getRect(find.text('Crossfade between albums'));
      expect(
        tester.getRect(find.byType(WaxInfoTip)).left,
        moreOrLessEquals(words.right, epsilon: 0.01),
      );
    });
  });

  group('a host keeps its shape as an info comes and goes', () {
    testWidgets('a setting row keeps its control\'s focus', (tester) async {
      final info = ValueNotifier<String?>(null);
      addTearDown(info.dispose);
      await tester.pumpWidget(
        _page(
          ListView(
            children: <Widget>[
              ValueListenableBuilder<String?>(
                valueListenable: info,
                builder: (_, words, _) => WaxSettingRow(
                  title: 'Crossfade',
                  info: words,
                  control: WaxSwitch(
                    value: false,
                    label: 'Crossfade',
                    onChanged: (_) {},
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      bool onSwitch() =>
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<WaxSwitch>() !=
          null;
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(onSwitch(), isTrue);

      for (final words in <String?>[_message, null, _message]) {
        info.value = words;
        await tester.pump();
        await tester.pump();
        expect(onSwitch(), isTrue, reason: '$words');
      }
    });

    testWidgets('a section header keeps its title', (tester) async {
      final info = ValueNotifier<String?>(null);
      addTearDown(info.dispose);
      await tester.pumpWidget(
        _page(
          ValueListenableBuilder<String?>(
            valueListenable: info,
            builder: (_, words, _) =>
                SectionHeader(title: 'Listening', info: words),
          ),
        ),
      );
      final title = tester.element(find.text('Listening'));
      for (final words in <String?>[_message, null]) {
        info.value = words;
        await tester.pump();
        expect(
          identical(tester.element(find.text('Listening')), title),
          isTrue,
          reason: '$words',
        );
      }
    });
  });

  group('a setting row keeps its title line when an info arrives', () {
    const title = 'Crossfade';
    const help = 'Between tracks from different albums';

    /// A row with help and a glyph at [density] and [scale], in a list
    /// where it takes its own height, under a neighbour a stray target
    /// would land on.
    Future<({Rect row, Rect title, Rect help, Rect glyph, Rect control})> row(
      WidgetTester tester, {
      String? info,
      WaxDensity density = WaxDensity.comfortable,
      double scale = 1,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWaxTheme(variant: WaxThemeVariant.dark, density: density),
          localizationsDelegates: waxLocalizationsDelegates,
          supportedLocales: WaxLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: ListView(
                  children: <Widget>[
                    const SizedBox(height: WaxSpace.s48),
                    Align(
                      alignment: AlignmentDirectional.topStart,
                      child: SizedBox(
                        width: 480,
                        child: WaxSettingRow(
                          title: title,
                          help: help,
                          info: info,
                          glyph: WaxIcons.downloads,
                          control: WaxSwitch(
                            value: false,
                            label: title,
                            onChanged: (_) {},
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      return (
        row: tester.getRect(find.byType(WaxSettingRow)),
        title: tester.getRect(find.text(title)),
        help: tester.getRect(find.text(help)),
        glyph: tester.getRect(
          find
              .descendant(
                of: find.byType(WaxSettingRow),
                matching: find.byType(WaxIcon),
              )
              .first,
        ),
        control: tester.getRect(find.byType(WaxSwitch)),
      );
    }

    for (final density in WaxDensity.values) {
      for (final scale in <double>[0.85, 1, 2]) {
        testWidgets('${density.name} at ${scale}x: nothing set against the '
            'title moves, and the whole 44 px target is inside the row', (
          tester,
        ) async {
          final without = await row(tester, density: density, scale: scale);
          final with_ = await row(
            tester,
            info: _message,
            density: density,
            scale: scale,
          );
          expect(with_.row, without.row, reason: 'the row\'s own height');
          expect(with_.title, without.title);
          expect(with_.glyph, without.glyph);
          expect(with_.help, without.help);
          expect(with_.control, without.control);

          final words = with_.title;
          final tip = tester.getRect(find.byType(WaxInfoTip));
          expect(tip.size, const Size.square(WaxSpace.touchTarget));
          expect(tip.left, moreOrLessEquals(words.right, epsilon: 0.01));
          expect(tip.top, greaterThanOrEqualTo(with_.row.top - 0.01));
          expect(tip.bottom, lessThanOrEqualTo(with_.row.bottom + 0.01));
          // Each edge of the target opens it, the top one above the
          // title's own line.
          for (final edge in <double>[tip.top + 0.5, tip.bottom - 0.5]) {
            await tester.tapAt(Offset(tip.center.dx, edge));
            await tester.pumpAndSettle();
            expect(find.text(_message), findsOneWidget, reason: '$edge');
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(find.text(_message), findsNothing);
          }
        });
      }
    }

    testWidgets('and Tab still reaches the tip before the control', (
      tester,
    ) async {
      await row(tester, info: _message);
      bool focusIn<T extends Widget>() =>
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<T>() !=
          null;
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusIn<WaxInfoTip>(), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusIn<WaxSwitch>(), isTrue);
    });
  });
}

class _Harness extends StatefulWidget {
  const _Harness({required this.controller, super.key});

  final ScrollController controller;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool showTip = true;
  bool jump = false;

  void dropTipAndJump() => setState(() {
    jump = true;
    showTip = false;
  });

  @override
  Widget build(BuildContext context) {
    if (jump) {
      jump = false;
      widget.controller.jumpTo(30);
    }
    return ListView(
      controller: widget.controller,
      children: <Widget>[
        const SizedBox(height: 100),
        if (showTip)
          const Align(
            alignment: Alignment.centerLeft,
            child: WaxInfoTip(message: _message),
          )
        else
          const SizedBox(height: 44),
        for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('r$i')),
      ],
    );
  }
}
