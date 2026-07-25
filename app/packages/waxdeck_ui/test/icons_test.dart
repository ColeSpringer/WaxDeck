import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

void main() {
  group('icon subsets', () {
    final manifest =
        jsonDecode(File('fonts/phosphor-subset.json').readAsStringSync())
            as Map<String, dynamic>;

    Set<int> glyphsIn(String family) =>
        (manifest[family]! as List<dynamic>).cast<int>().toSet();

    test('ship every glyph WaxIcons names', () {
      // The fonts are subset from the codepoints declared in
      // wax_icon.dart, so a name added without re-running
      // tools/fetch-icons.sh would render as a blank box at runtime and
      // pass every widget test. This is the check that catches it.
      final regular = glyphsIn('PhosphorRegular');
      final fill = glyphsIn('PhosphorFill');
      for (final entry in WaxIcons.all.entries) {
        expect(
          regular,
          contains(entry.value.regular.codePoint),
          reason:
              '${entry.key} is missing from the regular subset: re-run '
              'tools/fetch-icons.sh',
        );
        expect(
          fill,
          contains(entry.value.fill.codePoint),
          reason:
              '${entry.key} is missing from the fill subset: re-run '
              'tools/fetch-icons.sh',
        );
      }
    });

    test('carry nothing the app does not name', () {
      final named = WaxIcons.all.values.map((g) => g.codePoint).toSet();
      expect(glyphsIn('PhosphorRegular'), named);
      expect(glyphsIn('PhosphorFill'), named);
    });

    test('resolve to the vendored families, both weights', () {
      expect(WaxIcons.play.regular.fontFamily, 'PhosphorRegular');
      expect(WaxIcons.play.fill.fontFamily, 'PhosphorFill');
      expect(WaxIcons.play.regular.fontPackage, 'waxdeck_ui');
      expect(
        WaxIcons.play.resolve(active: true),
        WaxIcons.play.fill,
        reason: 'active state is the fill weight, never colour alone',
      );
    });

    testWidgets('renders the active weight when selected', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWaxTheme(),
          home: const Scaffold(
            body: Column(
              children: <Widget>[
                WaxIcon(WaxIcons.star),
                WaxIcon(WaxIcons.star, active: true, semanticLabel: 'Starred'),
              ],
            ),
          ),
        ),
      );
      final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
      expect(icons.first.icon!.fontFamily, 'PhosphorRegular');
      expect(icons.last.icon!.fontFamily, 'PhosphorFill');
      expect(icons.last.semanticLabel, 'Starred');
    });
  });
}
