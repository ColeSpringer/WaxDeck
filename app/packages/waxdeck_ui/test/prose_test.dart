import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

Widget _host(Widget child) => MaterialApp(
  theme: buildWaxTheme(),
  home: Scaffold(
    body: Center(child: SizedBox(width: 640, child: child)),
  ),
);

/// Drags a mouse across one line of [text], start to end.
Future<void> _dragAcross(
  WidgetTester tester,
  Finder text, {
  Finder? to,
  PointerDeviceKind kind = PointerDeviceKind.mouse,
}) async {
  final from = tester.getRect(text);
  final end = tester.getRect(to ?? text);
  final gesture = await tester.startGesture(
    from.centerLeft + const Offset(1, 0),
    kind: kind,
  );
  await tester.pump();
  await gesture.moveTo(end.centerRight - const Offset(1, 0));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// A mouse drag of a few pixels from the start of [text]: past the
/// selection's own slop and well inside a tap's, which is where the
/// selection has to win or the control under it takes a tap.
Future<void> _nudge(WidgetTester tester, Finder text) async {
  final start = tester.getRect(text).centerLeft + const Offset(1, 0);
  final gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  for (var step = 1; step <= 3; step++) {
    await gesture.moveBy(const Offset(2, 0));
    await tester.pump();
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

/// What a copy puts on the clipboard, pressed the way a reader does.
Future<String?> _copy(WidgetTester tester) async {
  String? copied;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    },
  );
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  return copied;
}

/// A child that counts how many times it was built from nothing.
class _Counted extends StatefulWidget {
  const _Counted(this.starts);

  final List<int> starts;

  @override
  State<_Counted> createState() => _CountedState();
}

class _CountedState extends State<_Counted> {
  @override
  void initState() {
    super.initState();
    widget.starts.add(1);
  }

  @override
  Widget build(BuildContext context) => const Text('Kept');
}

void main() {
  group('WaxProse', () {
    testWidgets('a drag selects the line and a copy takes it', (tester) async {
      await tester.pumpWidget(
        _host(const WaxProse('Holds every slot as it is')),
      );

      await _dragAcross(tester, find.text('Holds every slot as it is'));

      expect(await _copy(tester), 'Holds every slot as it is');
    });

    testWidgets('a block selects across its texts', (tester) async {
      await tester.pumpWidget(
        _host(
          const WaxProse.block(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[Text('No podcasts yet'), Text('Follow one')],
            ),
          ),
        ),
      );

      await _dragAcross(
        tester,
        find.text('No podcasts yet'),
        to: find.text('Follow one'),
      );

      final copied = await _copy(tester);
      expect(copied, contains('No podcasts yet'));
      expect(copied, contains('Follow one'));
    });

    testWidgets('a block on a page built under another one waits for it', (
      tester,
    ) async {
      // A deep link builds the pages under the top one offstage, never
      // laid out, and the area orders its texts by where they sit.
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWaxTheme(),
          initialRoute: '/top',
          routes: <String, WidgetBuilder>{
            '/': (_) => const Scaffold(
              body: WaxProse.block(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[Text('Under one'), Text('Under two')],
                ),
              ),
            ),
            '/top': (_) => const Scaffold(body: Text('On top')),
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // And once it is the top page again, it selects.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      await _dragAcross(
        tester,
        find.text('Under one'),
        to: find.text('Under two'),
      );
      expect(await _copy(tester), contains('Under two'));
    });

    testWidgets('a covered page keeps its area and its child', (tester) async {
      // Rebuilding the area per flip cost a platform view on the web and
      // a platform query on Android at every tab switch.
      final starts = <int>[];
      Widget host({required bool showing}) => _host(
        TickerMode(
          enabled: showing,
          child: WaxProse.block(child: _Counted(starts)),
        ),
      );
      await tester.pumpWidget(host(showing: true));
      final area = tester.state(find.byType(SelectableRegion));
      await tester.pumpWidget(host(showing: false));
      await tester.pumpWidget(host(showing: true));
      expect(starts, hasLength(1));
      expect(tester.state(find.byType(SelectableRegion)), same(area));
    });

    testWidgets('is not a tab stop, nor is anything in it', (tester) async {
      // The inner node stands in for the web build's context-menu view.
      await tester.pumpWidget(
        _host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              WaxButton(label: 'Before', onPressed: () {}),
              const WaxProse.block(
                child: Focus(child: Text('Help between two controls')),
              ),
              WaxButton(label: 'After', onPressed: () {}),
            ],
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(Focus.of(tester.element(find.text('Before'))).hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(Focus.of(tester.element(find.text('After'))).hasFocus, isTrue);
    });

    testWidgets('a tap leaves the focus where it was', (tester) async {
      // Only a selection takes it: a tap on the help under a search box
      // closed the keyboard.
      await tester.pumpWidget(
        _host(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              WaxTextField(label: 'Search', autofocus: true),
              WaxProse('Nothing for zzzz'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = FocusManager.instance.primaryFocus;

      await tester.tap(find.text('Nothing for zzzz'));
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus, same(field));
    });

    testWidgets('a tap beside a shorter line still taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          Align(
            alignment: Alignment.topLeft,
            child: WaxProse.block(
              onTap: () => taps++,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Origin: a local file on the server'),
                  Text('Edit'),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tapAt(
        tester.getRect(find.text('Edit')).centerRight + const Offset(40, 0),
      );
      await tester.pumpAndSettle();

      expect(taps, 1);
    });

    testWidgets('holds the browser menu off while the pointer is over it', (
      tester,
    ) async {
      // On the web the semantics tree sits over the text, so the
      // browser's menu opens on a node with nothing to copy.
      addTearDown(debugResetBrowserMenu);
      await tester.pumpWidget(
        _host(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(height: 80, key: Key('outside')),
              WaxProse('Holds every slot as it is'),
            ],
          ),
        ),
      );
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(
        tester.getCenter(find.text('Holds every slot as it is')),
      );
      await tester.pump();
      expect(debugBrowserMenuState, (1, true));

      await gesture.moveTo(tester.getCenter(find.byKey(const Key('outside'))));
      await tester.pump();
      expect(debugBrowserMenuState, (0, false));
    });

    testWidgets(
      'a right-click on the selection copies all of it',
      variant: TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
        TargetPlatform.linux,
        TargetPlatform.windows,
      }),
      (tester) async {
        await tester.pumpWidget(
          _host(
            const WaxProse.block(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[Text('No podcasts yet'), Text('Follow one')],
              ),
            ),
          ),
        );
        await _dragAcross(
          tester,
          find.text('No podcasts yet'),
          to: find.text('Follow one'),
        );

        final gesture = await tester.startGesture(
          tester.getCenter(find.text('Follow one')),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await gesture.up();
        await tester.pumpAndSettle();

        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        await tester.tap(find.text('Copy'));
        await tester.pumpAndSettle();
        expect(copied, contains('No podcasts yet'));
        expect(copied, contains('Follow one'));
      },
    );

    testWidgets(
      'its menu keeps the selection it acts on',
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
      (tester) async {
        // On the web a press focuses the button's semantics element, and
        // focus leaving the area clears its selection, but only in a
        // running app, which a test is not by default.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(
          _host(const WaxProse('Holds every slot as it is')),
        );
        final text = find.text('Holds every slot as it is');
        await _dragAcross(tester, text);
        final gesture = await tester.startGesture(
          tester.getRect(text).centerLeft + const Offset(20, 0),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await gesture.up();
        await tester.pumpAndSettle();

        // What the engine does with the browser's focus landing there.
        final copy = tester.getSemantics(find.text('Copy'));
        if (copy.getSemanticsData().hasAction(SemanticsAction.focus)) {
          copy.owner!.performAction(copy.id, SemanticsAction.focus);
          await tester.pump();
        }

        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        await tester.tap(find.text('Copy'));
        await tester.pumpAndSettle();
        expect(copied, 'Holds every slot as it is');
      },
    );

    testWidgets(
      "its menu sets the labels in the app's type",
      variant: TargetPlatformVariant.all(),
      (tester) async {
        // The stock labels name no face, and the web build cannot fetch
        // the engine's default (web/index.html): a blank box.
        await tester.pumpWidget(
          _host(const WaxProse('Holds every slot as it is')),
        );
        final text = find.text('Holds every slot as it is');
        switch (defaultTargetPlatform) {
          case TargetPlatform.android:
          case TargetPlatform.fuchsia:
          case TargetPlatform.iOS:
            await tester.longPress(text);
          case TargetPlatform.linux:
          case TargetPlatform.macOS:
          case TargetPlatform.windows:
            await _dragAcross(tester, text);
            // Inside the glyphs: the paragraph's box runs past its end.
            final gesture = await tester.startGesture(
              tester.getRect(text).centerLeft + const Offset(20, 0),
              kind: PointerDeviceKind.mouse,
              buttons: kSecondaryMouseButton,
            );
            await gesture.up();
        }
        await tester.pumpAndSettle();

        final label = tester.renderObject<RenderParagraph>(find.text('Copy'));
        expect(label.text.style?.fontFamily, isNotNull);
      },
    );

    testWidgets('a link inside prose still opens', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        _host(
          WaxProse.block(
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  const TextSpan(text: 'Notes with '),
                  WidgetSpan(
                    child: GestureDetector(
                      onTap: () => opened++,
                      child: const Text('a link'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('a link'));
      await tester.pumpAndSettle();

      expect(opened, 1);
    });
  });

  group('selectable help', () {
    // One per design-system surface that draws help or a message, so a
    // component that goes back to a bare Text is caught here.
    final surfaces = <String, Widget>{
      'setting row': WaxSettingRow(
        title: 'Pin this cover',
        help: 'Holds every slot as it is',
        control: WaxSwitch(value: false, label: 'Pin', onChanged: (_) {}),
      ),
      'text field': const WaxTextField(
        label: 'Name',
        helperText: 'Holds every slot as it is',
      ),
      'banner': const WaxBanner(message: 'Holds every slot as it is'),
      'entity header': const EntityHeader(
        title: 'Salt Harbour',
        description: 'Holds every slot as it is',
      ),
      'artwork caption': const ArtworkCaption('Holds every slot as it is'),
      'empty state': const EmptyState(
        title: 'Nothing here',
        message: 'Holds every slot as it is',
      ),
      'error state': const ErrorState(message: 'Holds every slot as it is'),
    };
    for (final entry in surfaces.entries) {
      testWidgets('${entry.key} help selects', (tester) async {
        await tester.pumpWidget(_host(entry.value));

        await _dragAcross(tester, find.text('Holds every slot as it is'));

        expect(
          await _copy(tester),
          'Holds every slot as it is',
          reason: entry.key,
        );
      });
    }

    testWidgets("a radio option's help selects without choosing it", (
      tester,
    ) async {
      final chosen = <int>[];
      await tester.pumpWidget(
        _host(
          WaxRadioGroup<int>(
            value: 0,
            options: const <WaxRadioOption<int>>[
              WaxRadioOption(
                value: 0,
                label: 'Move to trash',
                help: 'Restorable from the trash screen',
              ),
              WaxRadioOption(value: 1, label: 'Delete', help: 'Gone for good'),
            ],
            onChanged: chosen.add,
          ),
        ),
      );

      await _dragAcross(tester, find.text('Gone for good'));
      expect(await _copy(tester), 'Gone for good');

      // A drag short enough to have been a tap is still a selection.
      await _nudge(tester, find.text('Gone for good'));
      expect(chosen, isEmpty);
    });

    testWidgets("a tap on a radio option's help still chooses it", (
      tester,
    ) async {
      final chosen = <int>[];
      await tester.pumpWidget(
        _host(
          WaxRadioGroup<int>(
            value: 0,
            options: const <WaxRadioOption<int>>[
              WaxRadioOption(value: 0, label: 'Move to trash'),
              WaxRadioOption(value: 1, label: 'Delete', help: 'Gone for good'),
            ],
            onChanged: chosen.add,
          ),
        ),
      );

      await tester.tap(find.text('Gone for good'));
      await tester.pumpAndSettle();

      expect(chosen, <int>[1]);
    });

    testWidgets('the artwork caption selects under a collapse detector', (
      tester,
    ) async {
      // The player's surface dismisses on a tap and on a vertical drag,
      // and the caption sits on it.
      var collapses = 0;
      await tester.pumpWidget(
        _host(
          SizedBox(
            height: 300,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => collapses++,
              onVerticalDragEnd: (_) => collapses++,
              child: const Center(
                child: ArtworkCaption('From Cover Art Archive'),
              ),
            ),
          ),
        ),
      );

      await _dragAcross(tester, find.text('From Cover Art Archive'));
      expect(await _copy(tester), 'From Cover Art Archive');

      // Nor is a drag short enough to have been a tap taken as one.
      await _nudge(tester, find.text('From Cover Art Archive'));
      expect(collapses, 0);

      // A finger's vertical drag is still the surface's.
      await tester.dragFrom(
        tester.getCenter(find.text('From Cover Art Archive')),
        const Offset(0, 120),
      );
      await tester.pumpAndSettle();
      expect(collapses, 1);
    });
  });
}
