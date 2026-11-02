import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/shell/in_flight.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// Two verbs on one surface, each a button, and a way to close it.
class _Surface extends StatefulWidget {
  const _Surface({required this.work});

  /// What each verb runs, by its name.
  final Map<String, Future<void> Function(_SurfaceState state)> work;

  @override
  State<_Surface> createState() => _SurfaceState();
}

class _SurfaceState extends State<_Surface> with InFlight<_Surface, String> {
  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      for (final name in widget.work.keys)
        WaxButton(
          label: name,
          semanticsId: name,
          busy: busyBy(name),
          onPressed: busy
              ? null
              : () => unawaited(runAs(name, () => widget.work[name]!(this))),
        ),
    ],
  );
}

Future<void> _pump(
  WidgetTester tester,
  Map<String, Future<void> Function(_SurfaceState state)> work,
) => tester.pumpWidget(
  MaterialApp(
    theme: buildWaxTheme(),
    home: Scaffold(body: _Surface(work: work)),
  ),
);

WaxButton _button(WidgetTester tester, String name) =>
    tester.widget<WaxButton>(find.widgetWithText(WaxButton, name));

void main() {
  testWidgets('the starter draws busy and the rest stand unavailable', (
    tester,
  ) async {
    final save = Completer<void>();
    await _pump(tester, {'Save': (_) => save.future, 'Delete': (_) async {}});

    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(_button(tester, 'Save').busy, isTrue);
    expect(_button(tester, 'Delete').busy, isFalse);
    expect(_button(tester, 'Delete').onPressed, isNull);

    save.complete();
    await tester.pump();
    expect(_button(tester, 'Save').busy, isFalse);
    expect(_button(tester, 'Delete').onPressed, isNotNull);
  });

  testWidgets('a second start while one runs is dropped', (tester) async {
    final save = Completer<void>();
    var deletes = 0;
    await _pump(tester, {
      'Save': (_) => save.future,
      'Delete': (_) async => deletes++,
    });
    await tester.tap(find.text('Save'));
    await tester.pump();

    final state = tester.state<_SurfaceState>(find.byType(_Surface));
    await state.runAs('Delete', () async => deletes++);
    expect(deletes, 0);
    expect(state.busyBy('Save'), isTrue);
    save.complete();
    await tester.pump();
  });

  testWidgets('work that throws still clears its key', (tester) async {
    await _pump(tester, {'Save': (_) async => throw StateError('refused')});
    final state = tester.state<_SurfaceState>(find.byType(_Surface));

    await expectLater(
      state.runAs('Save', () async => throw StateError('refused')),
      throwsStateError,
    );
    await tester.pump();
    expect(state.busy, isFalse);
  });

  testWidgets('nothing draws busy while the work waits on the person', (
    tester,
  ) async {
    final answer = Completer<bool>();
    final done = Completer<void>();
    await _pump(tester, {
      'Save': (state) async {
        await state.whileAsking(() => answer.future);
        await done.future;
      },
      'Delete': (_) async {},
    });

    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(_button(tester, 'Save').busy, isFalse);
    expect(_button(tester, 'Delete').onPressed, isNull, reason: 'still busy');

    answer.complete(true);
    await tester.pump();
    expect(_button(tester, 'Save').busy, isTrue);
    done.complete();
    await tester.pump();
  });

  testWidgets('a dialog its work closed keeps the key on its way out', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWaxTheme(),
        home: Builder(
          builder: (context) => WaxButton(
            label: 'Open',
            onPressed: () => unawaited(
              showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: _Surface(
                    work: {
                      'Save': (state) async {
                        Navigator.of(state.context).pop();
                      },
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byType(_Surface), findsOneWidget, reason: 'still leaving');
    expect(_button(tester, 'Save').busy, isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(_Surface), findsNothing);
  });
}
