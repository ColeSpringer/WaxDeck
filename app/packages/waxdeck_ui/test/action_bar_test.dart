import 'dart:async';
import 'dart:ui' show PointerDeviceKind, Tristate;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

Future<void> _pump(WidgetTester tester, Widget child, {double scale = 1}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: buildWaxTheme(),
        localizationsDelegates: waxLocalizationsDelegates,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: Scaffold(body: Center(child: child)),
          ),
        ),
      ),
    );

const _download = 'download';

/// A primary pill, then the download action in every state it has.
List<WaxAction> _everyState() => <WaxAction>[
  WaxAction(
    label: 'Play',
    semanticsId: 'play',
    glyph: WaxIcons.play,
    emphasis: WaxActionEmphasis.primary,
    onPressed: () {},
  ),
  WaxAction(
    label: 'Download',
    semanticsId: 'ready',
    glyph: WaxIcons.downloads,
    onPressed: () {},
  ),
  WaxAction(
    label: 'Download',
    semanticsId: 'busy',
    glyph: WaxIcons.downloads,
    state: const WaxActionState.busy(),
    onPressed: () {},
  ),
  const WaxAction(
    label: 'Downloading',
    semanticsId: 'progress',
    glyph: WaxIcons.downloads,
    state: WaxActionState.progress(0.42),
  ),
  const WaxAction(
    label: 'Downloaded',
    semanticsId: 'done',
    glyph: WaxIcons.downloads,
    state: WaxActionState.done(),
  ),
  const WaxAction(
    label: 'Queued for download',
    semanticsId: 'status',
    glyph: WaxIcons.downloads,
    state: WaxActionState.status(),
  ),
  WaxAction(
    label: 'Retry download',
    semanticsId: 'failed',
    glyph: WaxIcons.downloads,
    state: const WaxActionState.failed(),
    detail: 'Not enough space on this device',
    onPressed: () {},
  ),
];

Finder _pill(String id) =>
    find.byWidgetPredicate((w) => w is WaxButton && w.semanticsId == id);

SemanticsData _node(WidgetTester tester, String id) =>
    tester.getSemantics(find.bySemanticsIdentifier(id)).getSemanticsData();

/// The semantics id of the pill holding keyboard focus, or null when
/// focus is anywhere else.
String? _focusedPill() => FocusManager.instance.primaryFocus?.context
    ?.findAncestorWidgetOfExactType<WaxButton>()
    ?.semanticsId;

void main() {
  testWidgets('every pill in a bar shares one height across all six states '
      'at 1.0 text scale', (tester) async {
    await _pump(
      tester,
      SizedBox(width: 400, child: WaxActionBar(actions: _everyState())),
    );
    final heights = tester
        .widgetList<WaxButton>(find.byType(WaxButton))
        .map((pill) => tester.getSize(_pill(pill.semanticsId!)).height)
        .toList();
    expect(heights, hasLength(7));
    expect(heights.toSet(), <double>{WaxSpace.touchTarget});
  });

  testWidgets('at 2.0 every pill keeps the touch-target minimum, padding '
      'and type, and a wrapped label grows only its own pill', (tester) async {
    await _pump(
      tester,
      SizedBox(width: 280, child: WaxActionBar(actions: _everyState())),
      scale: 2,
    );
    expect(tester.takeException(), isNull);
    final pills = tester.widgetList<WaxButton>(find.byType(WaxButton));
    expect(pills, hasLength(7));
    final oneLine = <double>{};
    for (final pill in pills) {
      final id = pill.semanticsId!;
      final box = tester.getRect(_pill(id));
      expect(
        box.height,
        greaterThanOrEqualTo(WaxSpace.touchTarget),
        reason: id,
      );
      final label = find
          .descendant(of: _pill(id), matching: find.byType(Text))
          .first;
      final text = tester.getRect(label);
      final glyph = find.descendant(
        of: _pill(id),
        matching: find.byType(WaxIcon),
      );
      final leading = glyph.evaluate().isEmpty
          ? text.left
          : tester.getRect(glyph.first).left;
      expect(text.top - box.top, greaterThanOrEqualTo(WaxSpace.s8), reason: id);
      expect(
        box.bottom - text.bottom,
        greaterThanOrEqualTo(WaxSpace.s8),
        reason: id,
      );
      expect(
        leading - box.left,
        greaterThanOrEqualTo(WaxSpace.s20 - 0.01),
        reason: id,
      );
      expect(
        box.right - text.right,
        greaterThanOrEqualTo(WaxSpace.s20 - 0.01),
        reason: id,
      );
      final style = tester.widget<Text>(label).style!;
      expect(style.fontSize, WaxType.label.fontSize, reason: id);
      expect(style.fontWeight, WaxType.label.fontWeight, reason: id);
      if (id != 'status') oneLine.add(box.height);
    }
    // Every kind and state on one line is one height, filled or tonal.
    expect(oneLine, hasLength(1));
    // The one label too long for the box wraps and grows its own pill.
    expect(
      tester.getSize(_pill('status')).height,
      greaterThan(oneLine.single + 10),
    );
  });

  testWidgets('a status action is not a button in semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, WaxActionBar(actions: _everyState()));
    for (final id in <String>['status', 'done']) {
      final node = _node(tester, id);
      expect(node.flagsCollection.isButton, isFalse, reason: id);
      expect(node.hasAction(SemanticsAction.tap), isFalse, reason: id);
      expect(node.flagsCollection.isEnabled, Tristate.none, reason: id);
      expect(node.flagsCollection.isFocused, Tristate.none, reason: id);
    }
    expect(_node(tester, 'status').label, 'Queued for download');
    expect(_node(tester, 'done').label, 'Downloaded');
    semantics.dispose();
  });

  testWidgets('a progress action reports its value', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, WaxActionBar(actions: _everyState()));
    final node = _node(tester, 'progress');
    expect(node.label, 'Downloading');
    expect(node.value, '42%');
    expect(node.hasAction(SemanticsAction.tap), isFalse);
    semantics.dispose();
  });

  testWidgets('a progress action with no share to report is the busy pill', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      WaxActionBar(
        actions: <WaxAction>[
          const WaxAction(
            label: 'Downloading',
            semanticsId: 'progress',
            glyph: WaxIcons.downloads,
            // 0 of 0: a transfer whose size is not known yet.
            state: WaxActionState.progress(double.nan),
          ),
        ],
      ),
    );
    expect(find.byType(WaxSpinner), findsOneWidget);
    expect(_node(tester, 'progress').value, 'Working');
    semantics.dispose();
  });

  test('a progress state carries how far it has got as its progress', () {
    expect(
      const WaxActionState.progress(0.42),
      isA<WaxActionProgress>().having((s) => s.progress, 'progress', 0.42),
    );
  });

  test('a second primary action asserts', () {
    WaxAction primary(String id) => WaxAction(
      label: id,
      semanticsId: id,
      emphasis: WaxActionEmphasis.primary,
      onPressed: () {},
    );
    WaxAction secondary(String id) =>
        WaxAction(label: id, semanticsId: id, onPressed: () {});
    expect(
      () => WaxActionBar(actions: <WaxAction>[primary('a'), primary('b')]),
      throwsAssertionError,
    );
    expect(
      () => WaxActionBar(actions: <WaxAction>[secondary('a'), primary('b')]),
      throwsAssertionError,
    );
    expect(
      () => WaxActionBar(actions: <WaxAction>[primary('a'), secondary('b')]),
      returnsNormally,
    );
  });

  testWidgets('each state draws the pill its rule names', (tester) async {
    await _pump(tester, WaxActionBar(actions: _everyState()));
    WaxButton pill(String id) => tester.widget<WaxButton>(_pill(id));
    expect(pill('play').kind, WaxButtonKind.filled);
    expect(pill('ready').kind, WaxButtonKind.tonal);
    expect(pill('busy').busy, isTrue);
    expect(pill('progress').progress, 0.42);
    expect(pill('status').status, isTrue);
    expect(pill('status').icon, WaxIcons.downloads);
    // Finished with no verb left is a state to read, never the disabled
    // tint.
    expect(pill('done').status, isTrue);
    expect(pill('done').icon, WaxIcons.success);
    expect(pill('failed').kind, WaxButtonKind.tonal);
    expect(pill('failed').icon, WaxIcons.warning);
    expect(pill('failed').onPressed, isNotNull);

    final colors = WaxColors.of(tester.element(_pill('done')));
    final ink = tester
        .widget<Text>(
          find.descendant(of: _pill('done'), matching: find.byType(Text)),
        )
        .style
        ?.color;
    expect(ink, colors.textSecondary);
  });

  testWidgets('a failed action with no press is a status pill', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      WaxActionBar(
        actions: <WaxAction>[
          const WaxAction(
            label: 'Download failed',
            semanticsId: 'failed',
            glyph: WaxIcons.downloads,
            state: WaxActionState.failed(),
            detail: 'The server went away',
          ),
        ],
      ),
    );
    final pill = tester.widget<WaxButton>(_pill('failed'));
    expect(pill.status, isTrue);
    expect(pill.icon, WaxIcons.warning);
    final colors = WaxColors.of(tester.element(_pill('failed')));
    expect(
      tester.widget<Text>(find.text('Download failed')).style?.color,
      colors.textSecondary,
    );
    final node = _node(tester, 'failed');
    expect(node.flagsCollection.isButton, isFalse);
    expect(node.flagsCollection.isEnabled, Tristate.none);
    expect(node.hint, 'The server went away');
    semantics.dispose();
  });

  for (final (name, state) in <(String, WaxActionState)>[
    ('busy', const WaxActionState.busy()),
    ('progress', const WaxActionState.progress(0.3)),
  ]) {
    testWidgets('a $name pill opens its detail on hover', (tester) async {
      await _pump(
        tester,
        WaxActionBar(
          actions: <WaxAction>[
            WaxAction(
              label: 'Download',
              semanticsId: _download,
              state: state,
              detail: 'Waits for Wi-Fi',
              onPressed: () {},
            ),
          ],
        ),
      );
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      addTearDown(pointer.removePointer);
      await pointer.moveTo(tester.getCenter(_pill(_download)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('Waits for Wi-Fi'), findsOneWidget);
    });
  }

  testWidgets('a primary action that is not ready is a tonal pill', (
    tester,
  ) async {
    await _pump(
      tester,
      WaxActionBar(
        actions: <WaxAction>[
          const WaxAction(
            label: 'Fetched',
            semanticsId: 'fetched',
            emphasis: WaxActionEmphasis.primary,
            state: WaxActionState.done(),
          ),
        ],
      ),
    );
    expect(tester.widget<WaxButton>(_pill('fetched')).status, isTrue);
  });

  testWidgets('a done action with a press is a tonal pill with the done '
      'glyph', (tester) async {
    var pressed = 0;
    await _pump(
      tester,
      WaxActionBar(
        actions: <WaxAction>[
          WaxAction(
            label: 'Remove download',
            semanticsId: _download,
            glyph: WaxIcons.downloads,
            state: const WaxActionState.done(),
            onPressed: () => pressed++,
          ),
        ],
      ),
    );
    final pill = tester.widget<WaxButton>(_pill(_download));
    expect(pill.status, isFalse);
    expect(pill.kind, WaxButtonKind.tonal);
    expect(pill.icon, WaxIcons.success);
    await tester.tap(_pill(_download));
    expect(pressed, 1);
  });

  testWidgets('detail is the tooltip and the hint, never a second chip', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, WaxActionBar(actions: _everyState()));
    const reason = 'Not enough space on this device';
    expect(find.text(reason), findsNothing);
    expect(
      find.descendant(
        of: _pill('failed'),
        matching: find.byWidgetPredicate(
          (w) => w is WaxTooltip && w.message == reason,
        ),
      ),
      findsOneWidget,
    );
    final node = _node(tester, 'failed');
    expect(node.label, 'Retry download');
    expect(node.hint, reason);
    expect(find.byType(WaxButton), findsNWidgets(7));
    semantics.dispose();
  });

  testWidgets('a status detail is its hint too', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      WaxActionBar(
        actions: <WaxAction>[
          const WaxAction(
            label: 'Queued',
            spokenLabel: 'Queued for download',
            semanticsId: 'queued',
            state: WaxActionState.status(),
            detail: 'Waits for Wi-Fi',
          ),
        ],
      ),
    );
    final node = _node(tester, 'queued');
    expect(node.label, 'Queued for download');
    expect(node.hint, 'Waits for Wi-Fi');
    expect(find.text('Waits for Wi-Fi'), findsNothing);
    semantics.dispose();
  });

  testWidgets('a spoken label replaces the drawn one for a reader', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      WaxActionBar(
        actions: <WaxAction>[
          WaxAction(
            label: 'Resume',
            spokenLabel: 'Resume chapter 9',
            semanticsId: 'resume',
            emphasis: WaxActionEmphasis.primary,
            onPressed: () {},
          ),
        ],
      ),
    );
    expect(_node(tester, 'resume').label, 'Resume chapter 9');
    expect(find.text('Resume'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('trailing widgets follow the pills and the overflow is last', (
    tester,
  ) async {
    await _pump(
      tester,
      SizedBox(
        width: 700,
        child: WaxActionBar(
          actions: <WaxAction>[
            WaxAction(
              label: 'Play',
              semanticsId: 'play',
              emphasis: WaxActionEmphasis.primary,
              onPressed: () {},
            ),
          ],
          trailing: <Widget>[StarButton(starred: false, onChanged: (_) {})],
          overflow: WaxMenuButton<int>(
            items: const <WaxMenuItem<int>>[
              WaxMenuItem<int>(value: 1, label: 'Share'),
            ],
            onSelected: (_) {},
          ),
        ),
      ),
    );
    final play = tester.getRect(_pill('play'));
    final star = tester.getRect(find.byType(StarButton));
    final more = tester.getRect(find.byType(WaxMenuButton<int>));
    expect(star.left, greaterThan(play.right));
    expect(more.left, greaterThan(star.right));
    expect(star.center.dy, closeTo(play.center.dy, 0.01));
  });

  WaxActionBar shortBar({WrapAlignment alignment = WrapAlignment.start}) =>
      WaxActionBar(
        alignment: alignment,
        actions: <WaxAction>[
          WaxAction(
            label: 'Play',
            semanticsId: 'play',
            emphasis: WaxActionEmphasis.primary,
            onPressed: () {},
          ),
          WaxAction(label: 'Shuffle', semanticsId: 'shuffle', onPressed: () {}),
        ],
        trailing: <Widget>[StarButton(starred: false, onChanged: (_) {})],
        overflow: WaxMenuButton<int>(
          items: const <WaxMenuItem<int>>[
            WaxMenuItem<int>(value: 1, label: 'Share'),
          ],
          onSelected: (_) {},
        ),
      );

  testWidgets('right to left, the row runs from the right edge', (
    tester,
  ) async {
    await _pump(
      tester,
      Directionality(
        textDirection: TextDirection.rtl,
        child: SizedBox(width: 700, child: shortBar()),
      ),
    );
    final bar = tester.getRect(find.byType(WaxActionBar));
    final play = tester.getRect(_pill('play'));
    final shuffle = tester.getRect(_pill('shuffle'));
    final star = tester.getRect(find.byType(StarButton));
    final more = tester.getRect(find.byType(WaxMenuButton<int>));
    expect(play.right, closeTo(bar.right, 0.01));
    expect(shuffle.right, lessThan(play.left));
    expect(star.right, lessThan(shuffle.left));
    expect(more.right, lessThan(star.left));
  });

  for (final alignment in <WrapAlignment>[
    WrapAlignment.start,
    WrapAlignment.center,
    WrapAlignment.end,
  ]) {
    final article = alignment == WrapAlignment.end ? 'an' : 'a';
    testWidgets('$article ${alignment.name} bar sits its row at that edge', (
      tester,
    ) async {
      await _pump(
        tester,
        SizedBox(width: 700, child: shortBar(alignment: alignment)),
      );
      final bar = tester.getRect(find.byType(WaxActionBar));
      final first = tester.getRect(_pill('play')).left - bar.left;
      final last =
          bar.right - tester.getRect(find.byType(WaxMenuButton<int>)).right;
      switch (alignment) {
        case WrapAlignment.start:
          expect(first, closeTo(0, 0.01));
        case WrapAlignment.end:
          expect(last, closeTo(0, 0.01));
        default:
          expect(first, closeTo(last, 0.01));
      }
    });
  }

  group('keyboard focus', () {
    /// A bar whose download becomes [after] when pressed.
    Widget flipping(
      ValueNotifier<bool> pressed,
      (String, WaxActionState) after,
    ) => ValueListenableBuilder<bool>(
      valueListenable: pressed,
      builder: (context, isPressed, _) => WaxActionBar(
        actions: <WaxAction>[
          WaxAction(
            label: 'Play',
            semanticsId: 'play',
            emphasis: WaxActionEmphasis.primary,
            onPressed: () {},
          ),
          WaxAction(
            label: isPressed ? after.$1 : 'Download',
            semanticsId: _download,
            glyph: WaxIcons.downloads,
            state: isPressed ? after.$2 : const WaxActionState.ready(),
            onPressed: isPressed ? null : () => pressed.value = true,
          ),
        ],
        trailing: <Widget>[StarButton(starred: false, onChanged: (_) {})],
      ),
    );

    const queued = ('Queued for download', WaxActionState.status());

    String? starFocused() => FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<StarButton>()
        ?.runtimeType
        .toString();

    /// Tabs to the download, presses it, and checks it flipped in place.
    Future<void> pressDownload(
      WidgetTester tester,
      ValueNotifier<bool> pressed,
    ) async {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focusedPill(), _download);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(pressed.value, isTrue);
      expect(tester.widget<WaxButton>(_pill(_download)).status, isTrue);
    }

    for (final after in <(String, WaxActionState)>[
      queued,
      ('Downloaded', const WaxActionState.done()),
      ('Download failed', const WaxActionState.failed()),
    ]) {
      testWidgets('focus stays on an action that turns into a '
          '${after.$2.runtimeType} pill', (tester) async {
        final pressed = ValueNotifier<bool>(false);
        addTearDown(pressed.dispose);
        await _pump(tester, flipping(pressed, after));
        await pressDownload(tester, pressed);
        expect(
          _focusedPill(),
          _download,
          reason: 'focus must not fall to the root',
        );

        // The next Tab continues from the slot.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(starFocused(), 'StarButton');

        // Once left, the status pill is no stop of its own.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(_focusedPill(), 'play');
      });
    }

    testWidgets('a slot keeps its focus when its id changes with its state', (
      tester,
    ) async {
      final pressed = ValueNotifier<bool>(false);
      addTearDown(pressed.dispose);
      await _pump(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: pressed,
          builder: (context, isPressed, _) => WaxActionBar(
            actions: <WaxAction>[
              WaxAction(
                label: 'Play',
                semanticsId: 'play',
                emphasis: WaxActionEmphasis.primary,
                onPressed: () {},
              ),
              WaxAction(
                label: isPressed ? 'Queued for download' : 'Download',
                slot: _download,
                semanticsId: isPressed ? 'queued' : 'fetch',
                glyph: WaxIcons.downloads,
                state: isPressed
                    ? const WaxActionState.status()
                    : const WaxActionState.ready(),
                onPressed: isPressed ? null : () => pressed.value = true,
              ),
            ],
            trailing: <Widget>[StarButton(starred: false, onChanged: (_) {})],
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focusedPill(), 'fetch');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(_focusedPill(), 'queued');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(starFocused(), 'StarButton');
    });

    testWidgets('a toggle whose id changes with its state keeps its focus, '
        'and the next Enter presses the same pill', (tester) async {
      var done = false;
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => WaxActionBar(
            actions: <WaxAction>[
              WaxAction(
                label: 'Play',
                semanticsId: 'play',
                emphasis: WaxActionEmphasis.primary,
                onPressed: () {},
              ),
              WaxAction(
                label: done ? 'Remove download' : 'Download',
                slot: _download,
                semanticsId: done ? 'remove' : 'fetch',
                glyph: WaxIcons.downloads,
                state: done
                    ? const WaxActionState.done()
                    : const WaxActionState.ready(),
                onPressed: () => setState(() => done = !done),
              ),
              WaxAction(label: 'Share', semanticsId: 'share', onPressed: () {}),
            ],
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focusedPill(), 'fetch');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(done, isTrue);
      expect(_focusedPill(), 'remove');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(done, isFalse, reason: 'the second Enter undid the first');
      expect(_focusedPill(), 'fetch');
    });

    testWidgets('a status pill without a detail that never held focus is no '
        'tab stop', (tester) async {
      final pressed = ValueNotifier<bool>(true);
      addTearDown(pressed.dispose);
      await _pump(tester, flipping(pressed, queued));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focusedPill(), 'play');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(starFocused(), 'StarButton');
    });

    /// A bar of Play, then [action], then a star.
    Widget barWith(WaxAction action) => WaxActionBar(
      actions: <WaxAction>[
        WaxAction(
          label: 'Play',
          semanticsId: 'play',
          emphasis: WaxActionEmphasis.primary,
          onPressed: () {},
        ),
        action,
      ],
      trailing: <Widget>[StarButton(starred: false, onChanged: (_) {})],
    );

    /// Tabs twice, past Play, and lets the focus label measure and open.
    Future<void> tabToSecond(WidgetTester tester) async {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }

    testWidgets('Tab onto a failed pill shows its detail', (tester) async {
      const reason = 'Not enough space on this device';
      await _pump(
        tester,
        barWith(
          WaxAction(
            label: 'Retry download',
            semanticsId: 'failed',
            glyph: WaxIcons.downloads,
            state: const WaxActionState.failed(),
            detail: reason,
            onPressed: () {},
          ),
        ),
      );
      expect(find.text(reason), findsNothing);
      await tabToSecond(tester);
      expect(_focusedPill(), 'failed');
      expect(find.text(reason), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(starFocused(), 'StarButton');
      expect(find.text(reason), findsNothing);
    });

    testWidgets('Tab reaches an action with no press but a reason, and '
        'shows it', (tester) async {
      const why = 'Connect to Wi-Fi to download';
      await _pump(
        tester,
        barWith(
          const WaxAction(
            label: 'Download',
            semanticsId: 'unavailable',
            glyph: WaxIcons.downloads,
            detail: why,
          ),
        ),
      );
      await tabToSecond(tester);
      expect(_focusedPill(), 'unavailable');
      expect(find.text(why), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(starFocused(), 'StarButton');
    });

    testWidgets('Tab reaches a status pill with a detail and shows it', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      const why = 'Waits for Wi-Fi';
      await _pump(
        tester,
        barWith(
          const WaxAction(
            label: 'Queued for download',
            semanticsId: 'queued',
            glyph: WaxIcons.downloads,
            state: WaxActionState.status(),
            detail: why,
          ),
        ),
      );
      final node = _node(tester, 'queued');
      expect(node.flagsCollection.isButton, isFalse);
      expect(node.hasAction(SemanticsAction.tap), isFalse);
      expect(node.flagsCollection.isFocused, Tristate.isFalse);

      await tabToSecond(tester);
      expect(_focusedPill(), 'queued');
      expect(find.text(why), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(_focusedPill(), 'queued', reason: 'inert to presses');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(starFocused(), 'StarButton');
      semantics.dispose();
    });

    testWidgets('a focused status pill gets its focus back after a dialog', (
      tester,
    ) async {
      final pressed = ValueNotifier<bool>(false);
      addTearDown(pressed.dispose);
      await _pump(tester, flipping(pressed, queued));
      await pressDownload(tester, pressed);

      final context = tester.element(_pill(_download));
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => const SizedBox.square(dimension: 10),
        ),
      );
      await tester.pumpAndSettle();
      expect(_focusedPill(), isNull);
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
      expect(_focusedPill(), _download);
    });

    testWidgets(
      'a focused status pill gets its focus back when the app resumes',
      (tester) async {
        Future<void> lifecycle(AppLifecycleState state) =>
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .handlePlatformMessage(
                  'flutter/lifecycle',
                  const StringCodec().encodeMessage(state.toString()),
                  (_) {},
                );

        final pressed = ValueNotifier<bool>(false);
        addTearDown(pressed.dispose);
        await _pump(tester, flipping(pressed, queued));
        await pressDownload(tester, pressed);

        await lifecycle(AppLifecycleState.inactive);
        await tester.pump();
        expect(_focusedPill(), isNull);
        await lifecycle(AppLifecycleState.resumed);
        await tester.pump();
        expect(_focusedPill(), _download);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    // A detail that comes or goes while the pill holds focus, which is how
    // a press that fails, and a retry, arrive.
    const reason = 'Not enough space on this device';
    WaxAction ready() => WaxAction(
      label: 'Download',
      semanticsId: _download,
      glyph: WaxIcons.downloads,
      onPressed: () {},
    );
    WaxAction failed() => WaxAction(
      label: 'Retry download',
      semanticsId: _download,
      glyph: WaxIcons.downloads,
      state: const WaxActionState.failed(),
      detail: reason,
      onPressed: () {},
    );
    WaxAction busy() => WaxAction(
      label: 'Download',
      semanticsId: _download,
      glyph: WaxIcons.downloads,
      state: const WaxActionState.busy(),
      onPressed: () {},
    );

    /// A bar whose download is `states[step]`.
    Widget stepping(ValueNotifier<int> step, List<WaxAction> states) =>
        ValueListenableBuilder<int>(
          valueListenable: step,
          builder: (context, i, _) => barWith(states[i]),
        );

    bool ring(WidgetTester tester) => tester
        .widget<WaxFocusRing>(
          find
              .descendant(
                of: _pill(_download),
                matching: find.byType(WaxFocusRing),
              )
              .first,
        )
        .focused;

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a focused pill whose detail arrives, then goes, keeps its '
        'ring true to its focus and shows the reason once it arrives', (
      tester,
    ) async {
      final step = ValueNotifier<int>(0);
      addTearDown(step.dispose);
      await _pump(
        tester,
        stepping(step, <WaxAction>[ready(), failed(), busy()]),
      );
      await tabToSecond(tester);
      expect(_focusedPill(), _download);
      expect(ring(tester), isTrue);
      expect(find.text(reason), findsNothing);

      step.value = 1;
      await settle(tester);
      expect(_focusedPill(), _download);
      expect(ring(tester), isTrue);
      expect(find.text(reason), findsOneWidget, reason: 'the reason shows');

      step.value = 2;
      await settle(tester);
      expect(_focusedPill(), _download);
      expect(ring(tester), isTrue);
      expect(find.text(reason), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await settle(tester);
      expect(starFocused(), 'StarButton');
      expect(ring(tester), isFalse, reason: 'one ring on screen');
    });

    for (final (name, from, to) in <(String, WaxAction, WaxAction)>[
      ('ready to failed with a reason', ready(), failed()),
      ('failed with a reason to busy', failed(), busy()),
    ]) {
      testWidgets('a focused pill flipped $name lets its ring go when Tab '
          'leaves it', (tester) async {
        final semantics = tester.ensureSemantics();
        final step = ValueNotifier<int>(0);
        addTearDown(step.dispose);
        await _pump(tester, stepping(step, <WaxAction>[from, to]));
        await tabToSecond(tester);
        step.value = 1;
        await settle(tester);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await settle(tester);
        expect(starFocused(), 'StarButton');
        expect(ring(tester), isFalse);
        expect(
          _node(tester, _download).flagsCollection.isFocused,
          isNot(Tristate.isTrue),
        );
        semantics.dispose();
      });
    }

    testWidgets('a failed pill with a reason, retried into a status with '
        'none, is no stop once left', (tester) async {
      final retried = ValueNotifier<bool>(false);
      addTearDown(retried.dispose);
      await _pump(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: retried,
          builder: (context, isRetried, _) => barWith(
            isRetried
                ? const WaxAction(
                    label: 'Queued for download',
                    semanticsId: _download,
                    state: WaxActionState.status(),
                  )
                : WaxAction(
                    label: 'Retry download',
                    semanticsId: _download,
                    state: const WaxActionState.failed(),
                    detail: reason,
                    onPressed: () => retried.value = true,
                  ),
          ),
        ),
      );
      await tabToSecond(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(retried.value, isTrue);
      expect(_focusedPill(), _download);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(starFocused(), 'StarButton');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(_focusedPill(), 'play');
    });
  });
}
