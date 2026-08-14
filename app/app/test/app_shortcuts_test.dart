import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/shell/shortcuts.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'localized_host.dart';

/// A declined key has to reach the ancestors that own it, which is what
/// `CallbackShortcuts` cannot do: it reports a key handled the moment an
/// activator accepts, before the callback runs.
void main() {
  testWidgets('a focused control keeps its space', (tester) async {
    var fired = 0;
    var pressed = 0;
    final elsewhere = FocusNode(debugLabel: 'not-a-control');
    addTearDown(elsewhere.dispose);
    await tester.pumpWidget(
      localizedHost(
        theme: buildWaxTheme(variant: WaxThemeVariant.dark),
        Scaffold(
          body: AppShortcuts(
            autofocus: false,
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.space): () => fired++,
            },
            child: Column(
              children: <Widget>[
                Focus(
                  focusNode: elsewhere,
                  autofocus: true,
                  child: const SizedBox(height: 20),
                ),
                WaxButton(label: 'Play', onPressed: () => pressed++),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(fired, 1, reason: 'focus is on nothing pressable');

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(pressed, 1);
    expect(fired, 1);
  });

  testWidgets('a field keeps its arrows, and the palette chord still fires', (
    tester,
  ) async {
    var seeks = 0;
    var palettes = 0;
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      localizedHost(
        theme: buildWaxTheme(variant: WaxThemeVariant.dark),
        Scaffold(
          body: AppShortcuts(
            autofocus: false,
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(
                LogicalKeyboardKey.arrowLeft,
                shift: true,
              ): () =>
                  seeks++,
            },
            typingBindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(
                LogicalKeyboardKey.keyK,
                control: true,
              ): () =>
                  palettes++,
            },
            child: WaxTextField(label: 'Search', controller: controller),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'night');
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(seeks, 0);
    expect(controller.selection.baseOffset, 5);
    expect(controller.selection.extentOffset, 4);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(palettes, 1);
  });
}
