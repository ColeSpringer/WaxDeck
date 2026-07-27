import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

Widget _host(Widget child) => MaterialApp(
  theme: buildWaxTheme(),
  home: Scaffold(body: child),
);

void main() {
  group('artwork placeholder', () {
    testWidgets('draws initials from a title', (tester) async {
      await tester.pumpWidget(
        _host(const ArtworkImage(size: 96, monogram: 'Salt Harbour')),
      );
      expect(find.text('SH'), findsOneWidget);
    });

    testWidgets('falls back to the domain glyph when a title has no '
        'letters', (tester) async {
      // Real libraries carry titles like "..." and "100%", and initials
      // taken from them are punctuation or nothing at all. An empty tile
      // says less than the domain glyph does.
      for (final title in <String>['...', '', '   ', '!?']) {
        await tester.pumpWidget(
          _host(
            ArtworkImage(size: 96, monogram: title, domain: WaxDomain.podcasts),
          ),
        );
        expect(find.byType(WaxIcon), findsOneWidget, reason: 'title "$title"');
        final icon = tester.widget<Icon>(find.byType(Icon));
        expect(icon.icon, WaxIcons.podcasts.regular);
      }
    });

    testWidgets('keeps digits, which are a legitimate monogram', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const ArtworkImage(size: 96, monogram: '1999')),
      );
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('keeps non-Latin initials', (tester) async {
      await tester.pumpWidget(
        _host(const ArtworkImage(size: 96, monogram: 'حديقة الليل')),
      );
      expect(find.byType(WaxIcon), findsNothing);
    });
  });

  group('artwork sizing', () {
    testWidgets('asks for the pixels it will paint, not the logical size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final asked = <int>[];
      await tester.pumpWidget(
        _host(
          ArtworkImage(
            size: 96,
            artwork: (int px) {
              asked.add(px);
              return null;
            },
          ),
        ),
      );
      expect(asked, <int>[288]);
    });

    testWidgets('rounds a fractional extent up', (tester) async {
      // A max-cross-axis grid hands its cells fractional widths; asking
      // for 336 pixels to paint 336.7 of them is a soft cover.
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final asked = <int>[];
      await tester.pumpWidget(
        _host(
          ArtworkImage(
            size: 168.34,
            artwork: (int px) {
              asked.add(px);
              return null;
            },
          ),
        ),
      );
      expect(asked, <int>[337]);
    });

    testWidgets('draws the monogram when the answer is no artwork', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          ArtworkImage(
            size: 96,
            monogram: 'Salt Harbour',
            artwork: (int px) => null,
          ),
        ),
      );
      expect(find.text('SH'), findsOneWidget);
    });
  });
}
