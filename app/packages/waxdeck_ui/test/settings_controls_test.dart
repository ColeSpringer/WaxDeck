import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

Widget _host(Widget child, {double height = 200}) => MaterialApp(
  theme: buildWaxTheme(variant: WaxThemeVariant.dark),
  home: Scaffold(
    body: Center(
      child: SizedBox(width: 420, height: height, child: child),
    ),
  ),
);

/// Fires the semantics tap action on the node carrying [identifier], the
/// way a screen reader activates a control - which is a different path
/// from a pointer tap and is the one worth checking separately.
///
/// The owner comes off the node rather than off the binding: the node is
/// the thing the action is for, and reaching through the binding means
/// picking which pipeline owner holds it.
void activateBySemantics(WidgetTester tester, String identifier) {
  final node = tester.getSemantics(find.bySemanticsIdentifier(identifier));
  node.owner!.performAction(node.id, SemanticsAction.tap);
}

void main() {
  group('WaxSwitch', () {
    testWidgets('reports the setting as its name and the state as toggled', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          WaxSwitch(
            value: true,
            label: 'Scrobble radio',
            semanticsId: 'setting-radio',
            onChanged: (_) {},
          ),
        ),
      );

      // A switch announces its state; a button would announce neither
      // "on" nor a way to hear it change. Checked flag by flag rather
      // than with an exhaustive matcher, because the node also carries
      // the focus action the ring needs and that is not what this is
      // about.
      expect(
        tester.getSemantics(find.bySemanticsIdentifier('setting-radio')),
        matchesSemantics(
          identifier: 'setting-radio',
          label: 'Scrobble radio',
          hasToggledState: true,
          isToggled: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          // The ring needs it; naming it here is what keeps this
          // matcher exhaustive about everything else.
          hasFocusAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('a tap and a screen reader each toggle it exactly once', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final changes = <bool>[];
      await tester.pumpWidget(
        _host(
          WaxSwitch(
            value: false,
            label: 'Scrobble radio',
            semanticsId: 'setting-radio',
            onChanged: changes.add,
          ),
        ),
      );

      await tester.tap(find.bySemanticsIdentifier('setting-radio'));
      await tester.pumpAndSettle();
      expect(changes, <bool>[true], reason: 'a pointer tap fired twice');

      activateBySemantics(tester, 'setting-radio');
      await tester.pumpAndSettle();
      expect(changes, <bool>[
        true,
        true,
      ], reason: 'a semantics activation fired twice');
      handle.dispose();
    });

    testWidgets('a null handler is drawn and announced as disabled', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const WaxSwitch(
            value: false,
            label: 'Scrobble radio',
            semanticsId: 'setting-radio',
            onChanged: null,
          ),
        ),
      );

      // Asserted on what a screen reader acts on rather than on the
      // whole flag set: no way to activate it, and it says why.
      final data = tester
          .getSemantics(find.bySemanticsIdentifier('setting-radio'))
          .getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(data.hasAction(SemanticsAction.focus), isFalse);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      handle.dispose();
    });
  });

  group('WaxChoice', () {
    Widget choice(List<String> opened, {ValueChanged<int>? onChanged}) =>
        WaxChoice<int>(
          value: 15,
          options: const <int>[15, 30, 45],
          labelFor: (value) => '$value seconds',
          label: 'Skip back by',
          semanticsId: 'setting-skip-back',
          onChanged: onChanged ?? (value) => opened.add('$value'),
        );

    testWidgets('draws its current value and announces it after the name', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(choice(<String>[])));

      // The value is on the control, not hidden behind it: that is the
      // whole difference from WaxMenuButton.
      expect(find.text('15 seconds'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.bySemanticsIdentifier('setting-skip-back'))
            .label,
        'Skip back by, 15 seconds',
      );
      handle.dispose();
    });

    testWidgets('a tap opens exactly one menu, not one per gesture path', (
      tester,
    ) async {
      // The reason this test exists: WaxTappable contributes semantics,
      // the focus flag, and the ring and adds no gesture, so the child
      // carries the pointer handler - which leaves two ways in. If they
      // both fired, two menus would stack and every option would be
      // found twice.
      await tester.pumpWidget(_host(choice(<String>[])));

      await tester.tap(find.bySemanticsIdentifier('setting-skip-back'));
      await tester.pumpAndSettle();

      expect(find.text('30 seconds'), findsOneWidget);
      expect(find.text('45 seconds'), findsOneWidget);
      // Two: the closed control behind the menu, and the menu's own row.
      expect(find.text('15 seconds'), findsNWidgets(2));
    });

    testWidgets('a screen reader opens one menu too, and choosing reports '
        'once', (tester) async {
      final handle = tester.ensureSemantics();
      final chosen = <int>[];
      await tester.pumpWidget(_host(choice(<String>[], onChanged: chosen.add)));

      activateBySemantics(tester, 'setting-skip-back');
      await tester.pumpAndSettle();
      expect(find.text('45 seconds'), findsOneWidget);

      await tester.tap(find.text('45 seconds'));
      await tester.pumpAndSettle();
      expect(chosen, <int>[45]);
      handle.dispose();
    });

    testWidgets('a null handler opens nothing and announces disabled', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          WaxChoice<int>(
            value: 15,
            options: const <int>[15, 30],
            labelFor: (value) => '$value seconds',
            label: 'Skip back by',
            semanticsId: 'setting-skip-back',
            onChanged: null,
          ),
        ),
      );

      final data = tester
          .getSemantics(find.bySemanticsIdentifier('setting-skip-back'))
          .getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(data.hasAction(SemanticsAction.focus), isFalse);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);

      await tester.tap(
        find.bySemanticsIdentifier('setting-skip-back'),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.text('30 seconds'), findsNothing);
      handle.dispose();
    });
  });

  group('WaxRadioGroup', () {
    const options = <WaxRadioOption<String>>[
      WaxRadioOption<String>(
        value: 'trash',
        label: 'Move to trash',
        help: 'Restorable from the trash screen',
        semanticsId: 'delete-mode-trash',
      ),
      WaxRadioOption<String>(
        value: 'permanent',
        label: 'Delete permanently',
        help: 'Gone for good',
        semanticsId: 'delete-mode-permanent',
      ),
    ];

    testWidgets('every option and its consequence is on screen', (
      tester,
    ) async {
      // The whole reason this exists beside WaxChoice: in a destructive
      // dialog the second answer cannot be behind a tap.
      await tester.pumpWidget(
        _host(
          WaxRadioGroup<String>(
            value: 'trash',
            options: options,
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('Move to trash'), findsOneWidget);
      expect(find.text('Delete permanently'), findsOneWidget);
      expect(find.text('Gone for good'), findsOneWidget);
    });

    testWidgets('announces as a group, and which one is checked', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          WaxRadioGroup<String>(
            value: 'trash',
            options: options,
            onChanged: (_) {},
          ),
        ),
      );

      expect(
        tester.getSemantics(find.bySemanticsIdentifier('delete-mode-trash')),
        matchesSemantics(
          label: 'Move to trash, Restorable from the trash screen',
          identifier: 'delete-mode-trash',
          isInMutuallyExclusiveGroup: true,
          hasCheckedState: true,
          isChecked: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      // The other one is in the same group and not checked, which is
      // the half that says choosing this un-chooses that.
      expect(
        tester
            .getSemantics(find.bySemanticsIdentifier('delete-mode-permanent'))
            .getSemanticsData()
            .flagsCollection
            .isChecked,
        CheckedState.isFalse,
      );
      handle.dispose();
    });

    testWidgets('a tap anywhere on the row reports its value', (tester) async {
      final chosen = <String>[];
      await tester.pumpWidget(
        _host(
          WaxRadioGroup<String>(
            value: 'trash',
            options: options,
            onChanged: chosen.add,
          ),
        ),
      );

      // The label, not the mark: a 20-pixel circle is not the target.
      await tester.tap(find.text('Delete permanently'));
      expect(chosen, <String>['permanent']);
    });

    testWidgets('a null callback disables every option, and reports it', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const WaxRadioGroup<String>(
            value: 'trash',
            options: options,
            onChanged: null,
          ),
        ),
      );

      // Reported disabled as well as drawn so, and with no tap to
      // offer: a control that looks dead and answers anyway is the
      // worse half of the pair. Asserted flag by flag rather than
      // against a whole node, because the disabled shape here is
      // WaxSwitch's disabled shape and this is not the place to pin
      // every one of its flags.
      final data = tester
          .getSemantics(find.bySemanticsIdentifier('delete-mode-permanent'))
          .getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(data.hasAction(SemanticsAction.focus), isFalse);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      handle.dispose();
    });
  });
}
