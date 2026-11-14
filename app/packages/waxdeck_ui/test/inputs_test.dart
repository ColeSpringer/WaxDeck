import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

Widget _host(Widget child, {double height = 400}) => MaterialApp(
  theme: buildWaxTheme(variant: WaxThemeVariant.dark),
  home: Scaffold(
    body: Center(
      child: SizedBox(width: 420, height: height, child: child),
    ),
  ),
);

void main() {
  group('WaxTextField', () {
    testWidgets('draws its label by default, over a field already filled', (
      tester,
    ) async {
      // The case a hint cannot cover, and the reason the label is the
      // default rather than something 35 of 38 call sites went without.
      // The hint is still in the tree - it is faded to nothing rather
      // than removed, which is why looking for the widget is not the
      // test - so the assertion is on what is actually on screen.
      final controller = TextEditingController(text: '12');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          WaxTextField(
            label: 'Transcodes at once',
            hint: 'never seen',
            controller: controller,
          ),
          height: 80,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Transcodes at once'), findsOneWidget);
      expect(
        tester
            .widgetList<AnimatedOpacity>(
              find.ancestor(
                of: find.text('never seen'),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .single
            .opacity,
        0,
        reason: 'a hint on a pre-filled field is painted at nothing',
      );
    });

    testWidgets('withheld, it is still the accessible name', (tester) async {
      // What every search box in the app is: a field whose surroundings
      // name it, which still has to answer to a screen reader.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const WaxTextField(label: 'Search', showLabel: false),
          height: 80,
        ),
      );
      expect(find.text('Search'), findsNothing);
      expect(find.bySemanticsLabel('Search'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('says what an empty value means, until it has to refuse', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const WaxTextField(
            label: 'Keep backups',
            helperText: 'Leave blank to keep every one',
          ),
          height: 120,
        ),
      );
      expect(find.text('Leave blank to keep every one'), findsOneWidget);

      // One line under a box, not two: the refusal is the more urgent
      // half and takes the place.
      await tester.pumpWidget(
        _host(
          const WaxTextField(
            label: 'Keep backups',
            helperText: 'Leave blank to keep every one',
            errorText: 'That is not a number',
          ),
          height: 120,
        ),
      );
      expect(find.text('Leave blank to keep every one'), findsNothing);
      expect(find.text('That is not a number'), findsOneWidget);
    });

    testWidgets('the line under the box is spoken by the box', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const WaxTextField(
            label: 'Keep backups',
            helperText: 'Leave blank to keep every one',
          ),
          height: 120,
        ),
      );

      // Drawn once and announced once, as part of the field rather than
      // as a stray node after it: a helper nothing the caret is in ever
      // says is a helper nobody using a screen reader hears.
      final node = tester.getSemantics(
        find.descendant(
          of: find.byType(WaxTextField),
          matching: find.byType(EditableText),
        ),
      );
      expect(node.label, 'Keep backups');
      expect(node.hint, 'Leave blank to keep every one');
      expect(
        find.bySemanticsLabel('Leave blank to keep every one'),
        findsNothing,
      );
      handle.dispose();
    });

    testWidgets('what sits beside the box is centred on the box', (
      tester,
    ) async {
      // A curation chip beside a field with help under it lined up with
      // the help, not with the box.
      await tester.pumpWidget(
        _host(
          const WaxTextField(
            label: 'Sort name',
            helperText: 'How this files in an A-to-Z list',
            beside: SizedBox(key: Key('chip'), width: 40, height: 20),
          ),
          height: 160,
        ),
      );
      expect(
        tester.getCenter(find.byKey(const Key('chip'))).dy,
        moreOrLessEquals(tester.getCenter(find.byType(TextField)).dy),
      );
      expect(
        tester.getTopLeft(find.text('How this files in an A-to-Z list')).dy,
        greaterThan(tester.getBottomLeft(find.byType(TextField)).dy),
      );
    });

    testWidgets('the drawn label is not announced a second time', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(const WaxTextField(label: 'Server URL'), height: 80),
      );
      expect(
        find.bySemanticsLabel('Server URL'),
        findsOneWidget,
        reason: 'the field owns the name; the drawn text is decoration',
      );
      handle.dispose();
    });

    testWidgets('a labelled field still reports its error', (tester) async {
      await tester.pumpWidget(
        _host(
          const WaxTextField(
            label: 'Server URL',
            errorText: 'That is not a URL',
          ),
          height: 120,
        ),
      );
      expect(find.text('Server URL'), findsOneWidget);
      expect(find.text('That is not a URL'), findsOneWidget);
    });

    testWidgets('holds its text to a bound counted in code points', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          WaxTextField(label: 'Name', controller: controller, maxCharacters: 4),
          height: 80,
        ),
      );
      await tester.enterText(find.byType(TextField), 'abcdef');
      expect(controller.text, 'abcd');
      // Three letters each carrying a combining accent: three graphemes,
      // six code points, which a grapheme count would let through.
      controller.clear();
      await tester.enterText(
        find.byType(TextField),
        String.fromCharCodes([0x65, 0x301, 0x65, 0x301, 0x65, 0x301]),
      );
      expect(controller.text.runes.length, 4);
    });

    // A bound of four, and the edits the platform's input method sends.
    Future<TextEditingController> bounded(WidgetTester tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          WaxTextField(label: 'Name', controller: controller, maxCharacters: 4),
          height: 80,
        ),
      );
      await tester.showKeyboard(find.byType(TextField));
      return controller;
    }

    Future<void> send(WidgetTester tester, TextEditingValue value) async {
      tester.testTextInput.updateEditingValue(value);
      await tester.pump();
    }

    const composingFive = TextEditingValue(
      text: 'abcde',
      selection: TextSelection.collapsed(offset: 5),
      composing: TextRange(start: 0, end: 5),
    );

    testWidgets(
      'cuts text still composing where input methods compose Latin text',
      (tester) async {
        final controller = await bounded(tester);
        await send(tester, composingFive);
        expect(controller.text, 'abcd');
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
        TargetPlatform.windows,
      }),
    );

    testWidgets(
      'waits for a composition to end before it cuts elsewhere',
      (tester) async {
        final controller = await bounded(tester);
        await send(tester, composingFive);
        expect(controller.text, 'abcde');
        await send(tester, composingFive.copyWith(composing: TextRange.empty));
        expect(controller.text, 'abcd');
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      }),
    );

    testWidgets('refuses a keystroke into a full field', (tester) async {
      final controller = await bounded(tester);
      await send(
        tester,
        const TextEditingValue(
          text: 'abcd',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      // A cut would keep the new letter and lose the last one.
      await send(
        tester,
        const TextEditingValue(
          text: 'abXcd',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      expect(controller.text, 'abcd');
      expect(controller.selection, const TextSelection.collapsed(offset: 2));
    });

    testWidgets('keeps the caret where a cut paste left it', (tester) async {
      final controller = await bounded(tester);
      await send(
        tester,
        const TextEditingValue(
          text: 'abc',
          selection: TextSelection.collapsed(offset: 0),
        ),
      );
      await send(
        tester,
        const TextEditingValue(
          text: 'XYZabc',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      expect(controller.text, 'XYZa');
      expect(controller.selection, const TextSelection.collapsed(offset: 3));
    });

    testWidgets('counts an emoji as one, and never splits one', (tester) async {
      final controller = await bounded(tester);
      final emoji = String.fromCharCode(0x1F600);
      await tester.enterText(find.byType(TextField), emoji * 4);
      expect(controller.text, emoji * 4, reason: 'four at a bound of four');
      controller.clear();
      await tester.enterText(find.byType(TextField), emoji * 5);
      expect(controller.text, emoji * 4);
    });

    testWidgets('a field with no bound keeps a long value whole', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(WaxTextField(label: 'Name', controller: controller), height: 80),
      );
      await tester.enterText(find.byType(TextField), 'n' * 5000);
      expect(controller.text.length, 5000);
    });

    // A digits-only field, opened on [text] and listening for the edits an
    // input method sends.
    Future<TextEditingController> digitsOnly(
      WidgetTester tester, {
      String text = '',
    }) async {
      final controller = TextEditingController(text: text);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          WaxTextField(
            label: 'Count',
            controller: controller,
            digitsOnly: true,
          ),
          height: 80,
        ),
      );
      await tester.showKeyboard(find.byType(TextField));
      return controller;
    }

    testWidgets('digits only drops what an edit inserts that is no digit', (
      tester,
    ) async {
      final controller = await digitsOnly(tester);
      await send(
        tester,
        const TextEditingValue(
          text: '-1,234.5x',
          selection: TextSelection.collapsed(offset: 9),
        ),
      );
      expect(controller.text, '12345');
      expect(controller.selection, const TextSelection.collapsed(offset: 5));
    });

    testWidgets('digits only leaves the text it opened on as it is', (
      tester,
    ) async {
      final controller = await digitsOnly(tester, text: '120.5');
      await send(
        tester,
        const TextEditingValue(
          text: '120.50',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      expect(controller.text, '120.50');
      await send(
        tester,
        const TextEditingValue(
          text: '120.50x',
          selection: TextSelection.collapsed(offset: 7),
        ),
      );
      expect(controller.text, '120.50');
      expect(controller.selection, const TextSelection.collapsed(offset: 6));
      // A deletion adds nothing, so there is nothing to refuse.
      await send(
        tester,
        const TextEditingValue(
          text: '120.5',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      expect(controller.text, '120.5');
    });

    testWidgets('digits only keeps the caret behind the edit it trimmed', (
      tester,
    ) async {
      final controller = await digitsOnly(tester, text: '12.5');
      await send(
        tester,
        const TextEditingValue(
          text: '12.5',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      // A letter typed before the point, and a pasted "7a" after it.
      await send(
        tester,
        const TextEditingValue(
          text: '12a.5',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      expect(controller.text, '12.5');
      expect(controller.selection, const TextSelection.collapsed(offset: 2));
      await send(
        tester,
        const TextEditingValue(
          text: '12.7a5',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      expect(controller.text, '12.75');
      expect(controller.selection, const TextSelection.collapsed(offset: 4));
    });

    testWidgets('digits only moves the composing range with the text', (
      tester,
    ) async {
      final controller = await digitsOnly(tester);
      await send(
        tester,
        const TextEditingValue(
          text: '12a4',
          selection: TextSelection.collapsed(offset: 4),
          composing: TextRange(start: 1, end: 4),
        ),
      );
      expect(controller.text, '124');
      expect(controller.selection, const TextSelection.collapsed(offset: 3));
      expect(controller.value.composing, const TextRange(start: 1, end: 3));

      // A range that held only what was dropped is no range.
      controller.clear();
      await send(
        tester,
        const TextEditingValue(
          text: '1a',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 1, end: 2),
        ),
      );
      expect(controller.text, '1');
      expect(controller.value.composing, TextRange.empty);
    });

    testWidgets('digits only reads a paste over a selection whole', (
      tester,
    ) async {
      // The paste ends in what the replaced text ended in, so the text the
      // two versions share would pass its point as the old one's.
      final controller = await digitsOnly(tester, text: '120.5');
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await send(
        tester,
        const TextEditingValue(
          text: '2.5',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      expect(controller.text, '25');
      expect(controller.selection, const TextSelection.collapsed(offset: 2));

      // The same inside the text: the selection holds the stored point and
      // the paste brings another, and neither is left.
      controller.value = const TextEditingValue(
        text: '12.5',
        selection: TextSelection(baseOffset: 1, extentOffset: 3),
      );
      await send(
        tester,
        const TextEditingValue(
          text: '17.5',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      expect(controller.text, '175');
      expect(controller.selection, const TextSelection.collapsed(offset: 2));
    });

    testWidgets('digits only leaves a selection cut or deleted as it falls', (
      tester,
    ) async {
      final controller = await digitsOnly(tester, text: '12.5');
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 2,
      );
      await send(
        tester,
        const TextEditingValue(
          text: '.5',
          selection: TextSelection.collapsed(offset: 0),
        ),
      );
      expect(controller.text, '.5');
      expect(controller.selection, const TextSelection.collapsed(offset: 0));

      // Inside the text, the stored point beside the cut stays.
      controller.value = const TextEditingValue(
        text: '1.25',
        selection: TextSelection(baseOffset: 2, extentOffset: 3),
      );
      await send(
        tester,
        const TextEditingValue(
          text: '1.5',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      expect(controller.text, '1.5');
      expect(controller.selection, const TextSelection.collapsed(offset: 2));
    });

    testWidgets(
      'digits only keeps a composing range inside the rewritten text',
      (tester) async {
        await digitsOnly(tester);
        final formatter = tester
            .widget<TextField>(find.byType(TextField))
            .inputFormatters!
            .single;

        // The platform channel refuses a range past the text in a debug build
        // and a release build does not, so this goes to the formatter whole.
        final formatted = formatter.formatEditUpdate(
          TextEditingValue.empty,
          const TextEditingValue(
            text: '12a4',
            selection: TextSelection.collapsed(offset: 4),
            composing: TextRange(start: 1, end: 9),
          ),
        );
        expect(formatted.text, '124');
        expect(formatted.composing, const TextRange(start: 1, end: 3));
      },
    );

    testWidgets('clears its own text and hands the empty value back', (
      tester,
    ) async {
      final changes = <String>[];
      await tester.pumpWidget(
        _host(
          WaxTextField(label: 'Search', onChanged: changes.add),
          height: 80,
        ),
      );

      await tester.enterText(find.byType(TextField), 'nightjar');
      await tester.pump();
      expect(changes.last, 'nightjar');

      // The clear control appears only with text in the field. It names
      // the field as the field is written: the label is copy, and
      // lowercasing it was a rule only English has.
      final clear = find.bySemanticsLabel('Clear Search');
      expect(clear, findsOneWidget);
      await tester.tap(clear);
      await tester.pump();

      // Both halves matter: the field empties, and the caller is told,
      // or a debounced query keeps answering the text nobody can see.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(changes.last, isEmpty);
      expect(find.bySemanticsLabel('Clear Search'), findsNothing);
    });

    testWidgets('a field without hints keeps autofill on, as a bare input', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const WaxTextField(label: 'Note')));
      final config = tester
          .state<EditableTextState>(find.byType(EditableText))
          .textInputConfiguration;
      expect(config.autofillConfiguration.enabled, isTrue);
    });

    testWidgets('null autofill hints turn autofill off', (tester) async {
      await tester.pumpWidget(
        _host(const WaxTextField(label: 'One-time code', autofillHints: null)),
      );
      final config = tester
          .state<EditableTextState>(find.byType(EditableText))
          .textInputConfiguration;
      expect(config.autofillConfiguration.enabled, isFalse);
    });

    testWidgets('hands autofill hints and autocorrect to the input', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const WaxTextField(
            label: 'Address',
            autofillHints: <String>[AutofillHints.url],
            autocorrect: false,
          ),
        ),
      );
      final input = tester.widget<TextField>(find.byType(TextField));
      expect(input.autofillHints, <String>[AutofillHints.url]);
      expect(input.autocorrect, isFalse);
    });

    testWidgets('a long helper line wraps and does not widen a dialog', (
      tester,
    ) async {
      Future<double> dialogWidth(String? helper) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildWaxTheme(variant: WaxThemeVariant.dark),
            home: Scaffold(
              body: AlertDialog(
                content: WaxTextField(label: 'Zone', helperText: helper),
              ),
            ),
          ),
        );
        return tester
            .getSize(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(IntrinsicWidth),
              ),
            )
            .width;
      }

      final bare = await dialogWidth(null);
      final helped = await dialogWidth(
        'A long sentence of help that, set on one line, is far wider than '
        'the field it sits under and would stretch the dialog around it',
      );
      expect(helped, bare);
    });

    testWidgets('names the input itself, not a wrapper around it', (
      tester,
    ) async {
      // One node per control, and the node is the text box: a wrapper
      // that declared the role would leave two textbox nodes for one
      // field, and the one carrying the name would be the one with no
      // input inside it.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(const WaxTextField(label: 'Search'), height: 80),
      );
      expect(
        tester.getSemantics(find.byType(EditableText)),
        matchesSemantics(
          label: 'Search',
          isTextField: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasFocusAction: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });

  group('WaxTextField validator', () {
    const userKey = ValueKey<String>('user');
    const passKey = ValueKey<String>('pass');

    Widget form(
      GlobalKey<FormState> key,
      List<TextEditingController> c, {
      AutovalidateMode autovalidate = AutovalidateMode.disabled,
      VoidCallback? onChanged,
    }) => _host(
      Form(
        key: key,
        autovalidateMode: autovalidate,
        onChanged: onChanged,
        child: Column(
          children: <Widget>[
            WaxTextField(
              key: userKey,
              label: 'Username',
              controller: c[0],
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            WaxTextField(
              key: passKey,
              label: 'Password',
              controller: c[1],
              obscureText: true,
              validator: (v) =>
                  (v == null || v.length < 8) ? 'Too short' : null,
            ),
          ],
        ),
      ),
      height: 300,
    );

    Finder under(Key field, String message) =>
        find.descendant(of: find.byKey(field), matching: find.text(message));

    List<TextEditingController> controllers() {
      final c = <TextEditingController>[
        TextEditingController(),
        TextEditingController(),
      ];
      addTearDown(() {
        for (final e in c) {
          e.dispose();
        }
      });
      return c;
    }

    testWidgets('validate draws each message under its own field and clears', (
      tester,
    ) async {
      final key = GlobalKey<FormState>();
      final c = controllers();
      await tester.pumpWidget(form(key, c));
      expect(find.text('Enter a name'), findsNothing);

      expect(key.currentState!.validate(), isFalse);
      await tester.pump();
      expect(under(userKey, 'Enter a name'), findsOneWidget);
      expect(under(passKey, 'Too short'), findsOneWidget);
      expect(under(userKey, 'Too short'), findsNothing);
      expect(under(passKey, 'Enter a name'), findsNothing);

      c[0].text = 'pippin';
      expect(key.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Enter a name'), findsNothing);
      expect(under(passKey, 'Too short'), findsOneWidget);

      c[1].text = 'hunter22hunter22';
      expect(key.currentState!.validate(), isTrue);
      await tester.pump();
      expect(find.text('Too short'), findsNothing);
    });

    testWidgets('typing reports to the form and autovalidates', (tester) async {
      final key = GlobalKey<FormState>();
      final c = controllers();
      var changes = 0;
      await tester.pumpWidget(
        form(
          key,
          c,
          autovalidate: AutovalidateMode.onUserInteraction,
          onChanged: () => changes++,
        ),
      );
      expect(find.text('Too short'), findsNothing);
      await tester.enterText(
        find.descendant(
          of: find.byKey(passKey),
          matching: find.byType(EditableText),
        ),
        'abc',
      );
      await tester.pump();
      expect(changes, greaterThan(0));
      expect(under(passKey, 'Too short'), findsOneWidget);
    });

    testWidgets('a field without a validator ignores the form', (tester) async {
      final key = GlobalKey<FormState>();
      await tester.pumpWidget(
        _host(
          Form(
            key: key,
            child: const WaxTextField(label: 'Note'),
          ),
        ),
      );
      expect(key.currentState!.validate(), isTrue);
    });

    group('semantics', () {
      /// The input's node, and whether a button sits above it.
      ({SemanticsNode input, bool underButton}) probe(WidgetTester tester) {
        final input = tester.getSemantics(find.byType(EditableText));
        var underButton = false;
        for (var n = input.parent; n != null; n = n.parent) {
          if (n.getSemanticsData().flagsCollection.isButton) {
            underButton = true;
          }
        }
        return (input: input, underButton: underButton);
      }

      Widget single({
        required TextEditingController controller,
        bool validated = false,
      }) => _host(
        Form(
          child: WaxTextField(
            label: 'Username',
            semanticsId: 'user-id',
            controller: controller,
            validator: validated
                ? (v) => (v == null || v.isEmpty) ? 'Enter a name' : null
                : null,
          ),
        ),
        height: 160,
      );

      testWidgets('a validated field keeps its clear button a sibling', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        final c = TextEditingController(text: 'pippin');
        addTearDown(c.dispose);
        await tester.pumpWidget(single(controller: c, validated: true));
        expect(find.bySemanticsLabel('Clear Username'), findsOneWidget);
        final shape = probe(tester);
        expect(shape.underButton, isFalse);
        expect(
          shape.input.getSemanticsData().flagsCollection.isTextField,
          true,
        );
        expect(shape.input.identifier, 'user-id');
        handle.dispose();
      });

      testWidgets('an unvalidated field has the same shape', (tester) async {
        final handle = tester.ensureSemantics();
        final c = TextEditingController(text: 'pippin');
        addTearDown(c.dispose);
        await tester.pumpWidget(single(controller: c));
        expect(probe(tester).underButton, isFalse);
        handle.dispose();
      });

      testWidgets('an empty invalid field reports on the input too', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        final c = TextEditingController();
        addTearDown(c.dispose);
        await tester.pumpWidget(single(controller: c, validated: true));
        expect(tester.state<FormState>(find.byType(Form)).validate(), isFalse);
        await tester.pump();
        final node = tester.getSemantics(find.byType(EditableText));
        expect(
          node.getSemanticsData().validationResult,
          SemanticsValidationResult.invalid,
        );
        expect(node.hint, 'Enter a name');
        handle.dispose();
      });

      testWidgets('the invalid result stays on the input while text is held', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        final c = TextEditingController();
        addTearDown(c.dispose);
        await tester.pumpWidget(
          _host(
            Form(
              child: WaxTextField(
                label: 'Username',
                controller: c,
                validator: (v) => (v ?? '').length < 5 ? 'Too short' : null,
              ),
            ),
            height: 160,
          ),
        );
        c.text = 'abc';
        await tester.pump();
        expect(tester.state<FormState>(find.byType(Form)).validate(), isFalse);
        await tester.pump();
        final shape = probe(tester);
        expect(shape.underButton, isFalse);
        expect(
          shape.input.getSemanticsData().validationResult,
          SemanticsValidationResult.invalid,
        );
        handle.dispose();
      });

      testWidgets('an explicit error reports the field invalid, and stops '
          'once it is gone', (tester) async {
        final handle = tester.ensureSemantics();
        Widget field(String? error) => _host(
          WaxTextField(label: 'Retention', errorText: error),
          height: 160,
        );
        await tester.pumpWidget(field('Too short'));
        SemanticsData input() =>
            tester.getSemantics(find.byType(EditableText)).getSemanticsData();
        expect(input().validationResult, SemanticsValidationResult.invalid);
        expect(input().hint, 'Too short');

        await tester.pumpWidget(field(null));
        expect(input().validationResult, SemanticsValidationResult.none);
        handle.dispose();
      });
    });

    for (final (name, before, after) in <(String, bool, bool)>[
      ('a validator that comes', false, true),
      ('a validator that goes', true, false),
    ]) {
      testWidgets('$name is refused', (tester) async {
        // Either way the field's subtree would remount, dropping focus and
        // the keyboard on the keystroke that flipped it.
        Widget field({required bool validated}) => _host(
          Form(
            child: WaxTextField(
              label: 'Username',
              validator: validated ? (v) => null : null,
            ),
          ),
          height: 160,
        );
        await tester.pumpWidget(field(validated: before));
        await tester.pumpWidget(field(validated: after));
        expect(
          tester.takeException(),
          isA<AssertionError>().having(
            (e) => e.message,
            'message',
            contains('a validator must not come and go'),
          ),
        );
      });
    }
  });

  group('WaxSegmented', () {
    testWidgets('unequal labels still get equal segments', (tester) async {
      await tester.pumpWidget(
        _host(
          Center(
            child: WaxSegmented(
              label: 'Source',
              segments: const [
                WaxSegment(name: 'rss', label: 'RSS'),
                WaxSegment(name: 'youtube', label: 'YouTube'),
              ],
              selected: 'rss',
              onSelect: (_) {},
            ),
          ),
          height: 120,
        ),
      );

      // The component's promise is a partition, not a pair of pills
      // each sized to its own word: every segment is as wide as the
      // widest label needs.
      final rss = tester.getRect(
        find.ancestor(of: find.text('RSS'), matching: find.byType(WaxTappable)),
      );
      final youtube = tester.getRect(
        find.ancestor(
          of: find.text('YouTube'),
          matching: find.byType(WaxTappable),
        ),
      );
      expect(rss.width, youtube.width);
    });

    testWidgets('reports the tapped segment by name', (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(
        _host(
          Center(
            child: WaxSegmented(
              label: 'Source',
              segments: const [
                WaxSegment(name: 'rss', label: 'RSS'),
                WaxSegment(name: 'youtube', label: 'YouTube'),
              ],
              selected: 'rss',
              onSelect: picked.add,
            ),
          ),
          height: 120,
        ),
      );

      await tester.tap(find.text('YouTube'));
      expect(picked, ['youtube']);
    });

    testWidgets('a null onSelect disables every segment', (tester) async {
      await tester.pumpWidget(
        _host(
          const Center(
            child: WaxSegmented(
              label: 'Source',
              segments: [
                WaxSegment(name: 'rss', label: 'RSS', semanticsId: 'seg-rss'),
                WaxSegment(name: 'youtube', label: 'YouTube'),
              ],
              selected: 'rss',
              onSelect: null,
            ),
          ),
          height: 120,
        ),
      );

      final rss = tester.widget<WaxTappable>(
        find.ancestor(of: find.text('RSS'), matching: find.byType(WaxTappable)),
      );
      expect(rss.onPressed, isNull);
      expect(
        tester.getSemantics(find.bySemanticsIdentifier('seg-rss')),
        isSemantics(hasEnabledState: true, isEnabled: false),
      );
    });
  });

  group('FilterChipRow', () {
    testWidgets('reports the chip name, not its label', (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(
        _host(
          FilterChipRow(
            chips: const <WaxFilterChip>[
              WaxFilterChip(name: 'all', label: 'All'),
              WaxFilterChip(name: 'podcasts', label: 'Podcasts'),
            ],
            selected: 'all',
            onSelect: picked.add,
          ),
          height: 80,
        ),
      );

      await tester.tap(find.text('Podcasts'));
      expect(picked, <String>['podcasts']);
    });

    testWidgets('the chosen chip reports itself selected', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          FilterChipRow(
            chips: const <WaxFilterChip>[
              WaxFilterChip(name: 'all', label: 'All'),
              WaxFilterChip(name: 'music', label: 'Music'),
            ],
            selected: 'music',
            onSelect: (_) {},
          ),
          height: 80,
        ),
      );

      expect(
        tester.getSemantics(find.bySemanticsLabel('Music')),
        matchesSemantics(
          label: 'Music',
          isButton: true,
          hasTapAction: true,
          // Every tappable reports whether it can be pressed, which is
          // what the shared treatment brought with it.
          hasEnabledState: true,
          isEnabled: true,
          // Selection is not signalled by colour alone.
          isSelected: true,
          hasSelectedState: true,
          // And the chip has to be reachable from a keyboard: excluding a
          // subtree drops the Focus widget's own focusable flag, which is
          // what web turns into a tabindex.
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
      handle.dispose();
    });
  });

  group('FastScrollRail', () {
    testWidgets('a tap reports the letter it landed on', (tester) async {
      final jumps = <String>[];
      await tester.pumpWidget(
        _host(
          Align(
            alignment: Alignment.centerRight,
            child: FastScrollRail(
              letters: fastScrollLetters,
              onLetter: jumps.add,
            ),
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Jump to M'));
      expect(jumps, <String>['M']);
    });

    testWidgets('a drag walks the alphabet without repeating a letter', (
      tester,
    ) async {
      final jumps = <String>[];
      await tester.pumpWidget(
        _host(
          Align(
            alignment: Alignment.centerRight,
            child: FastScrollRail(
              letters: fastScrollLetters,
              onLetter: jumps.add,
            ),
          ),
        ),
      );

      final rail = find.byType(FastScrollRail);
      final top = tester.getTopLeft(rail);
      final size = tester.getSize(rail);
      final gesture = await tester.startGesture(
        Offset(top.dx + size.width / 2, top.dy + 2),
      );
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(
          Offset(top.dx + size.width / 2, top.dy + size.height * i / 10),
        );
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();

      // Where the first report lands is a gesture-recognition detail (the
      // arena resolves a drag only after the slop distance), so what is
      // pinned is the walk: down the alphabet, in order, ending at Z.
      expect(jumps.length, greaterThan(3));
      expect(jumps.last, 'Z');
      for (var i = 1; i < jumps.length; i++) {
        // A drag that re-reported the same letter every frame would fire
        // a fetch per frame on the screen underneath.
        expect(jumps[i], isNot(jumps[i - 1]));
        expect(
          fastScrollLetters.indexOf(jumps[i]),
          greaterThan(fastScrollLetters.indexOf(jumps[i - 1])),
        );
      }
    });

    testWidgets('hides itself rather than drawing an illegible strip', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Align(
            alignment: Alignment.centerRight,
            child: FastScrollRail(letters: fastScrollLetters, onLetter: (_) {}),
          ),
          // 27 letters into 120 px is under 5 px a slice.
          height: 120,
        ),
      );
      expect(find.text('M'), findsNothing);
    });

    testWidgets('every letter stays reachable when the rail decimates', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Align(
            alignment: Alignment.centerRight,
            child: FastScrollRail(letters: fastScrollLetters, onLetter: (_) {}),
          ),
          // Tall enough to draw, short enough that some slices become
          // dots: the drawn glyphs thin out, the semantics nodes do not.
          height: 280,
        ),
      );

      expect(find.bySemanticsLabel('Jump to Q'), findsOneWidget);
      expect(find.bySemanticsLabel('Jump to Z'), findsOneWidget);
    });
  });

  group('MediaListRow.heightFor', () {
    for (final scale in <double>[1, 1.5, 2]) {
      testWidgets('matches what a row lays out at ${scale}x text', (
        tester,
      ) async {
        // The whole point of the helper: a screen scrolling to a row by
        // index multiplies this, so being short by a few pixels a row is
        // being short by a screenful after eighty of them.
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            // Sized to its content, the way a list lays its rows out:
            // a box that forces a height measures the box.
            child: _host(
              Column(
                mainAxisSize: MainAxisSize.min,
                children: const <Widget>[
                  MediaListRow(
                    data: MediaTileData(
                      title: 'Nightjar',
                      subtitle: '12 tracks',
                    ),
                  ),
                ],
              ),
              height: 400,
            ),
          ),
        );

        final context = tester.element(find.byType(MediaListRow));
        expect(
          tester.getSize(find.byType(MediaListRow)).height,
          MediaListRow.heightFor(context),
          reason: 'at ${scale}x',
        );
      });
    }
  });

  group('MediaListRow play count', () {
    Future<void> pumpRow(
      WidgetTester tester,
      MediaTileData data, {
      double width = 420,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: buildWaxTheme(variant: WaxThemeVariant.dark),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: MediaListRow(data: data, onTap: () {}, onMore: () {}),
            ),
          ),
        ),
      ),
    );

    const bare = MediaTileData(
      title: 'Harbour Lights',
      subtitle: 'Nightjar',
      trailingText: '4:18',
    );
    const counted = MediaTileData(
      title: 'Harbour Lights',
      subtitle: 'Nightjar',
      trailingText: '4:18',
      playCount: 12,
      playCountLabel: 'played 12 times',
      playCountSemanticsId: 'plays-0',
    );
    final playGlyph = find.byWidgetPredicate(
      (widget) => widget is WaxIcon && widget.glyph == WaxIcons.play,
    );

    testWidgets('sits left of the duration behind a play glyph, as one node '
        'that says it in words', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpRow(tester, bare);
      final durationAlone = tester.getTopLeft(find.text('4:18')).dx;

      await pumpRow(tester, counted);
      final count = find.text('12');
      final duration = find.text('4:18');
      // The duration keeps its column; the count takes the room before it.
      expect(tester.getTopLeft(duration).dx, durationAlone);
      expect(
        tester.getTopRight(count).dx + WaxSpace.s12,
        tester.getTopLeft(duration).dx,
      );
      expect(
        tester.getTopRight(playGlyph).dx + WaxSpace.s4,
        tester.getTopLeft(count).dx,
      );
      expect(tester.widget<WaxIcon>(playGlyph).size, 12);

      final colors = WaxColors.of(tester.element(count));
      final style = tester.widget<Text>(count).style!;
      expect(style.fontFamily, WaxType.monoData.fontFamily);
      expect(style.fontSize, WaxType.monoData.fontSize);
      expect(style.color, colors.textSecondary);
      expect(tester.widget<WaxIcon>(playGlyph).color, isNot(colors.accent));

      // One node in words, beside the row's own rather than inside it.
      expect(
        tester.getSemantics(find.bySemanticsIdentifier('plays-0')).label,
        'played 12 times',
      );
      expect(
        find.bySemanticsLabel('Harbour Lights, Nightjar, 4:18'),
        findsOneWidget,
      );
      final tooltip = find.ancestor(
        of: count,
        matching: find.byType(WaxTooltip),
      );
      expect(tooltip, findsOneWidget);
      expect(tester.widget<WaxTooltip>(tooltip).excludeFromSemantics, isTrue);

      // And the same words on hover.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(count));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('played 12 times'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('draws nothing and keeps no room at zero or with no count', (
      tester,
    ) async {
      await pumpRow(tester, bare);
      final durationAlone = tester.getTopLeft(find.text('4:18')).dx;

      for (final plays in <int?>[0, null]) {
        await pumpRow(
          tester,
          MediaTileData(
            title: 'Harbour Lights',
            subtitle: 'Nightjar',
            trailingText: '4:18',
            playCount: plays,
            playCountLabel: 'never played',
            playCountSemanticsId: 'plays-0',
          ),
        );
        expect(playGlyph, findsNothing, reason: '$plays');
        expect(find.text('0'), findsNothing, reason: '$plays');
        expect(find.bySemanticsIdentifier('plays-0'), findsNothing);
        expect(tester.getTopLeft(find.text('4:18')).dx, durationAlone);
      }
    });

    testWidgets('an ellipsized title stops eight pixels short of the duration, '
        'which keeps its column', (tester) async {
      await pumpRow(tester, bare, width: 270);
      final column = tester.getTopLeft(find.text('4:18')).dx;
      const long = 'Harbour Lights over the Long Water';
      for (final starred in <bool>[false, true]) {
        await pumpRow(
          tester,
          MediaTileData(
            title: long,
            subtitle: 'Nightjar',
            trailingText: '4:18',
            starred: starred,
          ),
          width: 270,
        );
        final title = find.text(long);
        expect(
          tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
          isTrue,
          reason: 'the title is cut',
        );
        expect(tester.getTopLeft(find.text('4:18')).dx, column);
        // A star brings its own gap, and the duration adds none to it.
        final before = starred
            ? tester
                  .getTopRight(
                    find.byWidgetPredicate(
                      (widget) =>
                          widget is WaxIcon && widget.glyph == WaxIcons.star,
                    ),
                  )
                  .dx
            : tester.getTopRight(title).dx;
        expect(before + WaxSpace.s8, column, reason: 'starred: $starred');
      }
    });

    testWidgets('from a thousand the count is compact', (tester) async {
      await pumpRow(
        tester,
        const MediaTileData(
          title: 'Harbour Lights',
          trailingText: '4:18',
          playCount: 1234,
          playCountLabel: 'played 1234 times',
        ),
      );
      expect(find.text('1.2K'), findsOneWidget);
      expect(find.text('1234'), findsNothing);
    });

    // The glyph and the number are one readout: a bare number beside the
    // duration reads as a second timestamp.
    for (final (width, drawn) in <(double, bool)>[
      (360, true),
      (320, true),
      (280, true),
      (279, false),
    ]) {
      testWidgets('at $width px the row draws '
          '${drawn ? 'the glyph and the number together' : 'no count'}, '
          'and always the duration and the overflow', (tester) async {
        await pumpRow(tester, counted, width: width);
        expect(playGlyph, drawn ? findsOneWidget : findsNothing);
        expect(find.text('12'), drawn ? findsOneWidget : findsNothing);
        expect(
          find.bySemanticsIdentifier('plays-0'),
          drawn ? findsOneWidget : findsNothing,
        );
        expect(find.text('4:18'), findsOneWidget);
        expect(find.byType(WaxIconButton), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a count arriving and going keeps the row, its element and '
        'its keyboard focus', (tester) async {
      MediaTileData plays(int count) => MediaTileData(
        title: 'Harbour Lights',
        trailingText: '4:18',
        playCount: count,
        playCountLabel: count > 0 ? 'played $count times' : null,
      );
      await pumpRow(tester, plays(0));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus;
      final ink = tester.element(find.byType(InkWell));
      expect(
        focused?.context,
        isNotNull,
        reason: 'Tab focuses the row to begin with',
      );

      for (final count in <int>[1, 0]) {
        await pumpRow(tester, plays(count));
        expect(playGlyph, count > 0 ? findsOneWidget : findsNothing);
        expect(
          identical(tester.element(find.byType(InkWell)), ink),
          isTrue,
          reason: 'the row element survives a count of $count',
        );
        expect(FocusManager.instance.primaryFocus, same(focused));
      }
    });

    testWidgets('a row that never carries a count measures nothing', (
      tester,
    ) async {
      // Null is the plain row, which may sit under an intrinsic pass; a
      // row that can carry a count reads its width at any count.
      await pumpRow(tester, bare);
      expect(
        find.descendant(
          of: find.byType(MediaListRow),
          matching: find.byType(LayoutBuilder),
        ),
        findsNothing,
      );
      await pumpRow(
        tester,
        const MediaTileData(title: 'Harbour Lights', playCount: 0),
      );
      expect(
        find.descendant(
          of: find.byType(MediaListRow),
          matching: find.byType(LayoutBuilder),
        ),
        findsOneWidget,
      );
    });
  });

  group('MediaCard.heightFor', () {
    for (final scale in <double>[1, 1.5]) {
      testWidgets('a long trailing readout stays inside the cell at '
          '${scale}x text', (tester) async {
        // The card reserves one caption line for the trailing readout, so
        // a readout that wrapped overflowed the cell by exactly one line
        // which a book's "1 hr 20 min left" did on the audiobooks hub.
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: _host(
              Builder(
                builder: (context) => SizedBox(
                  height: MediaCard.heightFor(context, width: 120),
                  child: const MediaCard(
                    width: 120,
                    data: MediaTileData(
                      title: 'A Very Long Book Title That Wraps Twice Over',
                      subtitle: 'An Author With A Long Name',
                      trailingText: '11 hr 20 min left of this one',
                    ),
                  ),
                ),
              ),
              height: 600,
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: 'at ${scale}x');
      });
    }
  });

  group('MediaCard corner controls', () {
    const tile = MediaTileData(
      title: 'Coastal FM',
      subtitle: 'Ambient',
      shape: ArtworkShape.circle,
    );

    testWidgets('the pin and the overflow share a row and leave the middle '
        'clear', (tester) async {
      // A station tile hand-rolled these over the card: a star and a
      // menu button stacked at its (0, 0) while the card drew its own
      // overflow at (8, 8) - two of the same glyph eight pixels apart.
      var pinned = 0;
      await tester.pumpWidget(
        _host(
          Align(
            alignment: Alignment.topLeft,
            child: MediaCard(
              width: 120,
              data: tile,
              action: MediaCardAction(
                glyph: WaxIcons.star,
                label: 'Pin Coastal FM',
                onPressed: () => pinned++,
              ),
              onMore: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The pin is a control a finger can reach with no pointer in the
      // room: it answers "is this pinned?" as well as offering a verb,
      // and a phone has no hover to reveal it with.
      final star = find.bySemanticsLabel('Pin Coastal FM');
      expect(star, findsOneWidget);
      await tester.tap(star);
      await tester.pump();
      expect(pinned, 1);

      // The buttons' own boxes, not the glyphs inside them: what is
      // being asserted is where the discs sit.
      Finder chip(WaxGlyph glyph) => find.ancestor(
        of: find.byIcon(glyph.regular),
        matching: find.byType(WaxIconButton),
      );
      // And the pin sits in the corner, not a chip's width inboard of
      // it, with no pointer in the room to reveal anything beside it.
      final atRest = tester.getRect(chip(WaxIcons.star));
      final card = tester.getRect(find.byType(MediaCard));
      expect(
        card.right - atRest.right,
        moreOrLessEquals(WaxSpace.s8, epsilon: 0.5),
      );
      expect(find.byIcon(WaxIcons.more.regular), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await tester.pump();
      await mouse.moveTo(tester.getCenter(find.byType(MediaCard)));
      await tester.pumpAndSettle();

      final starBox = tester.getRect(chip(WaxIcons.star));
      final moreBox = tester.getRect(chip(WaxIcons.more));
      expect(
        starBox.top,
        moreOrLessEquals(moreBox.top, epsilon: 0.5),
        reason: 'level with each other',
      );
      expect(
        moreBox.left - card.left,
        moreOrLessEquals(WaxSpace.s8, epsilon: 0.5),
        reason: 'the overflow has the opposite corner',
      );
      expect(
        moreBox.right,
        lessThanOrEqualTo(card.center.dx),
        reason: 'and neither chip reaches the middle, where the disc is',
      );
      expect(starBox.left, greaterThanOrEqualTo(card.center.dx));
      // The pin has not moved: the overflow appears in the other
      // corner, so nothing shifts under the pointer that revealed it.
      expect(starBox.right, moreOrLessEquals(atRest.right, epsilon: 0.5));

      // Resting on a chip keeps them drawn. The chips are a sibling of
      // the card, and a Stack hit-tests topmost first and stops - so
      // without a region of their own the card un-hovers, the overflow
      // vanishes from under the pointer, the card re-hovers, and the
      // pair strobes while every click lands on the card behind.
      await mouse.moveTo(tester.getCenter(chip(WaxIcons.star)));
      await tester.pumpAndSettle();
      expect(find.byIcon(WaxIcons.more.regular), findsOneWidget);
      await mouse.moveTo(tester.getCenter(chip(WaxIcons.more)));
      await tester.pumpAndSettle();
      expect(find.byIcon(WaxIcons.more.regular), findsOneWidget);
    });
  });

  group('MediaCard captions', () {
    const tile = MediaTileData(
      title: 'Salt Harbour',
      subtitle: 'Nightjar',
      trailingText: '4:05',
    );

    Finder captions() => find.ancestor(
      of: find.text('Nightjar'),
      matching: find.byType(AnimatedOpacity),
    );

    testWidgets('hiding them changes no measurement at all', (tester) async {
      // The invariant the whole mode rests on. A shelf commits to a
      // height before it lays its cards out, so a caption that stopped
      // taking room would resize the shelf under the pointer.
      final sizes = <WaxCaptionMode, Size>{};
      for (final mode in WaxCaptionMode.values) {
        await tester.pumpWidget(
          _host(
            Align(
              alignment: Alignment.topLeft,
              child: MediaCard(width: 120, captions: mode, data: tile),
            ),
          ),
        );
        await tester.pumpAndSettle();
        sizes[mode] = tester.getSize(find.byType(MediaCard));
      }
      expect(sizes[WaxCaptionMode.onHover], sizes[WaxCaptionMode.always]);
    });

    testWidgets('always is what a card draws with no mode passed', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const MediaCard(width: 120, data: tile)));
      await tester.pumpAndSettle();
      // Drawn plainly, and with no fade around it: an AnimatedOpacity
      // carries a controller and a ticker apiece, and a full grid is a
      // hundred cards animating a constant.
      expect(find.text('Nightjar'), findsOneWidget);
      expect(captions(), findsNothing);
    });

    testWidgets('on hover they are faded out until the pointer arrives', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          MediaCard(
            width: 120,
            captions: WaxCaptionMode.onHover,
            data: tile,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedOpacity>(captions()).opacity, 0);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      // A frame for the binding to notice a mouse exists at all: the
      // detector reports no hover until one is connected.
      await tester.pump();
      // The card's content: its box is the host's whole body, of which a
      // card without chips answers to the content alone.
      await mouse.moveTo(tester.getCenter(find.byType(ArtworkImage)));
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedOpacity>(captions()).opacity, 1);
    });

    testWidgets('a hidden caption is still announced', (tester) async {
      // The label is built from the data rather than from what is drawn,
      // so a screen reader hears the same card either way. Written down
      // because the obvious implementation - dropping the widgets -
      // would have taken the announcement with them.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const MediaCard(
            width: 120,
            captions: WaxCaptionMode.onHover,
            data: tile,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Salt Harbour, Nightjar, 4:05'), findsOne);
      handle.dispose();
    });

    testWidgets('the theme is where the mode comes from', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWaxTheme(captions: WaxCaptionMode.onHover),
          home: const Scaffold(
            body: Center(child: MediaCard(width: 120, data: tile)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedOpacity>(captions()).opacity, 0);
    });
  });

  group('MediaCard overflow chip', () {
    const tile = MediaTileData(title: 'Salt Harbour', subtitle: 'Nightjar');

    testWidgets('appears under a pointer and opens the menu', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        _host(
          Align(
            alignment: Alignment.topLeft,
            child: MediaCard(width: 120, data: tile, onMore: () => opened++),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Nothing is offered until a pointer is over the card: the chip
      // is a hover affordance, so a touch device keeps the long press
      // as its whole route in.
      // Not drawn, not announced, and taking no room: assistive tech is
      // offered the card's own long-press action rather than a chip
      // nobody can see, and a phone's layout is not shaped around one.
      expect(find.byIcon(WaxIcons.more.regular), findsNothing);
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('More for Salt Harbour'), findsNothing);
      handle.dispose();

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await tester.pump();
      await mouse.moveTo(tester.getCenter(find.byType(MediaCard)));
      await tester.pumpAndSettle();
      expect(find.byIcon(WaxIcons.more.regular), findsOneWidget);

      await tester.tap(find.byIcon(WaxIcons.more.regular));
      expect(opened, 1);
    });

    testWidgets('a card with no menu draws no chip', (tester) async {
      await tester.pumpWidget(
        _host(
          const Align(
            alignment: Alignment.topLeft,
            child: MediaCard(width: 120, data: tile),
          ),
        ),
      );
      expect(find.byIcon(WaxIcons.more.regular), findsNothing);
    });
  });

  group('fastScrollLetter', () {
    test('names the row a label belongs under', () {
      expect(fastScrollLetter('Nightjar'), 'N');
      expect(fastScrollLetter('the Sea and Cake'), 'T');
      expect(fastScrollLetter('  Padded'), 'P');
      expect(fastScrollLetter('4 Non Blondes'), '#');
      expect(fastScrollLetter('[Unknown Artist]'), '#');
      expect(fastScrollLetter(''), '#');
      // The fallback has no fold, so anything beyond ASCII reads as `#`.
      // Under a current server the accented label arrives carrying `O`
      // and this derivation never runs; inventing a fold here would be
      // a second one to keep in step with the catalog's.
      expect(fastScrollLetter('Ólafur Arnalds'), '#');
    });
  });

  group('WaxPill', () {
    testWidgets('announces the whole label and draws the short one', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          WaxPill(
            label: 'Playback speed 1.5x',
            text: '1.5x',
            mono: true,
            onPressed: () {},
          ),
          height: 80,
        ),
      );

      // A pill is a word in an outline, and the word is often shorter
      // than what it means: the rate reads "1.5x" and is announced as
      // the control it is.
      expect(find.text('1.5x'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Playback speed 1.5x')),
        isSemantics(label: 'Playback speed 1.5x', isButton: true),
      );
    });

    testWidgets('a reserved width holds whatever the readout says', (
      tester,
    ) async {
      Future<double> widthOf(String text) async {
        await tester.pumpWidget(
          _host(
            Center(
              child: WaxPill(
                label: 'Playback speed $text',
                text: text,
                reserve: '1.35x',
                mono: true,
                onPressed: () {},
              ),
            ),
            height: 80,
          ),
        );
        return tester.getSize(find.byType(WaxPill)).width;
      }

      expect(await widthOf('1x'), await widthOf('1.35x'));
    });

    testWidgets('reports on and off rather than leaving it to colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          WaxPill(label: 'Trim silence', selected: true, onPressed: () {}),
          height: 80,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Trim silence')),
        isSemantics(isSelected: true),
      );
    });

    testWidgets('busy spins where its word was, live, and takes no press', (
      tester,
    ) async {
      var presses = 0;
      Future<void> pill({required bool busy}) => tester.pumpWidget(
        _host(
          Center(
            child: WaxPill(
              label: 'Voice boost',
              busy: busy,
              onPressed: () => presses++,
            ),
          ),
          height: 80,
        ),
      );

      await pill(busy: false);
      final idle = tester.getSize(find.byType(WaxPill));
      await pill(busy: true);

      // The spinner stands in the word's room, so the pill keeps its size.
      expect(find.byType(WaxSpinner), findsOneWidget);
      expect(tester.getSize(find.byType(WaxPill)), idle);
      // Working, not unavailable: the live ink, and said as working.
      final colors = WaxColors.dark;
      expect(
        tester.widget<WaxSpinner>(find.byType(WaxSpinner)).color,
        colors.textSecondary,
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Voice boost')),
        isSemantics(label: 'Voice boost', value: 'Working', isButton: true),
      );
      await tester.tap(find.byType(WaxPill));
      await tester.pump();
      expect(presses, 0);
    });

    testWidgets('a null press disables it in the tree, not only in ink', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const WaxPill(label: 'Voice boost', onPressed: null), height: 80),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Voice boost')),
        isSemantics(hasEnabledState: true, isEnabled: false),
      );
    });
  });

  group('WaxTextField enabled', () {
    testWidgets('off takes no typing and dims the text', (tester) async {
      final controller = TextEditingController(text: 'kept');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          WaxTextField(
            label: 'Only these',
            controller: controller,
            enabled: false,
          ),
        ),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse);
      final colors = WaxColors.of(tester.element(find.byType(TextField)));
      expect(field.style?.color, colors.textDisabled);

      // Text is held, so no clear control stands where it would be.
      expect(find.byType(WaxIconButton), findsNothing);
      expect(controller.text, 'kept');
    });

    testWidgets('off and empty draws its label, hint and box disabled', (
      tester,
    ) async {
      // The usual disabled field holds nothing, so dimming only the typed
      // text left it looking exactly like a live one.
      Future<({Color label, Color? hint, BoxDecoration box})> drawn(
        bool enabled,
      ) async {
        await tester.pumpWidget(
          _host(
            WaxTextField(
              label: 'Only these',
              hint: 'Words to match',
              glyph: WaxIcons.search,
              enabled: enabled,
            ),
          ),
        );
        final box = tester.widget<AnimatedContainer>(
          find.ancestor(
            of: find.byType(TextField),
            matching: find.byType(AnimatedContainer),
          ),
        );
        return (
          label: tester.widget<Text>(find.text('Only these')).style!.color!,
          hint: tester
              .widget<TextField>(find.byType(TextField))
              .decoration
              ?.hintStyle
              ?.color,
          box: box.decoration! as BoxDecoration,
        );
      }

      final colors = WaxColors.dark;
      final live = await drawn(true);
      final off = await drawn(false);
      expect(live.label, isNot(colors.textDisabled));
      expect(off.label, colors.textDisabled);
      expect(off.hint, colors.textDisabled);
      expect(
        tester.widget<WaxIcon>(find.byType(WaxIcon)).color,
        colors.textDisabled,
      );
      expect(
        off.box.color,
        isNot(live.box.color),
        reason: 'the box steps back',
      );
    });
  });
}
