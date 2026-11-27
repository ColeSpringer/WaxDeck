import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_autofill.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'localized_host.dart';

/// The saved flag of every time anything ended an autofill context.
List<bool> _ended(WidgetTester tester) => [
  for (final call in tester.testTextInput.log)
    if (call.method == 'TextInput.finishAutofillContext')
      call.arguments as bool,
];

/// A credential form beside a plain field, under the app's root group;
/// [show] takes the form down when set false.
Future<void> _mount(
  WidgetTester tester,
  CredentialAutofillController controller,
  ValueNotifier<bool> show,
) => tester.pumpWidget(
  localizedHost(
    Scaffold(
      body: ListView(
        children: <Widget>[
          const WaxTextField(label: 'Search'),
          ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (context, shown, _) => shown
                ? CredentialAutofill(
                    controller: controller,
                    child: const WaxTextField(
                      label: 'Username',
                      autofillHints: <String>[AutofillHints.username],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('a form taken down unfinished ends its context unsaved, once', (
    tester,
  ) async {
    final show = ValueNotifier(true);
    addTearDown(show.dispose);
    await _mount(tester, CredentialAutofillController(), show);
    expect(_ended(tester), isEmpty);
    show.value = false;
    await tester.pump();
    expect(_ended(tester), <bool>[false]);
  });

  testWidgets('a field focused where the form went keeps the context open', (
    tester,
  ) async {
    final show = ValueNotifier(true);
    addTearDown(show.dispose);
    await _mount(tester, CredentialAutofillController(), show);
    await tester.showKeyboard(find.byType(EditableText).first);
    show.value = false;
    await tester.pump();
    expect(_ended(tester), isEmpty);
  });

  testWidgets('a context its screen ended is not ended again', (tester) async {
    final show = ValueNotifier(true);
    addTearDown(show.dispose);
    final controller = CredentialAutofillController();
    await _mount(tester, controller, show);
    controller.finish(accepted: true);
    show.value = false;
    await tester.pump();
    expect(_ended(tester), <bool>[true]);
  });

  testWidgets('on the desktop nothing joins or ends a context', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final show = ValueNotifier(true);
      addTearDown(show.dispose);
      final controller = CredentialAutofillController();
      await _mount(tester, controller, show);
      expect(find.byType(AutofillGroup), findsNothing);
      controller.finish(accepted: true);
      show.value = false;
      await tester.pump();
      expect(_ended(tester), isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
