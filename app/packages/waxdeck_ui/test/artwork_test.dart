import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
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

    testWidgets('a wordmark sets the whole name', (tester) async {
      // The surfaces where the artwork *is* the identification - a
      // full-screen radio face, a dial tile - and most stations arrive
      // with no logo at all, so two letters on a swatch names nothing.
      await tester.pumpWidget(
        _host(
          const ArtworkImage(
            size: 200,
            monogram: 'Radio Nightjar',
            placeholder: ArtworkPlaceholder.wordmark,
            domain: WaxDomain.radio,
          ),
        ),
      );
      expect(find.text('Radio Nightjar'), findsOneWidget);
      expect(find.text('RN'), findsNothing);
    });

    testWidgets('a wordmark below the legibility floor draws initials', (
      tester,
    ) async {
      // The call sites declare intent and the component decides what
      // fits: two lines of legible type do not go in a deck bar's
      // thumbnail, so the same declaration draws initials there.
      await tester.pumpWidget(
        _host(
          const ArtworkImage(
            size: 48,
            monogram: 'Radio Nightjar',
            placeholder: ArtworkPlaceholder.wordmark,
            domain: WaxDomain.radio,
          ),
        ),
      );
      expect(find.text('RN'), findsOneWidget);
      expect(find.text('Radio Nightjar'), findsNothing);
    });

    testWidgets('only a wordmark is textured', (tester) async {
      // The grain belongs to the station mark. An initials tile is what
      // every coverless album, queue row, and search hit draws, and
      // texturing those is a tiled decoration plus a saveLayer on the
      // surfaces that draw the most placeholders.
      await tester.pumpWidget(
        _host(
          const ArtworkImage(
            size: 200,
            monogram: 'Salt Harbour',
            domain: WaxDomain.music,
          ),
        ),
      );
      expect(find.byType(Opacity), findsNothing);
    });

    testWidgets('a wordmark with no usable name falls to the domain glyph', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const ArtworkImage(
            size: 200,
            monogram: '...',
            placeholder: ArtworkPlaceholder.wordmark,
            domain: WaxDomain.radio,
          ),
        ),
      );
      expect(find.byType(WaxIcon), findsOneWidget);
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

  group('artwork play affordance', () {
    Future<TestPointer> hoverOver(WidgetTester tester, Finder finder) async {
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(tester.getCenter(finder)));
      await tester.pumpAndSettle();
      return pointer;
    }

    testWidgets('appears under a pointer and plays', (tester) async {
      var played = 0;
      await tester.pumpWidget(
        _host(
          ArtworkImage(
            size: 120,
            monogram: 'Salt Harbour',
            onPlay: () => played++,
            playLabel: 'Play Salt Harbour',
          ),
        ),
      );

      // Scoped to the artwork: a Scaffold has IgnorePointers of its own,
      // and this is a statement about the overlay rather than about
      // Material.
      final overlay = find.descendant(
        of: find.byType(ArtworkImage),
        matching: find.byType(IgnorePointer),
      );
      // Nothing is offered until a pointer is over the artwork: the
      // affordance is a hover, so a touch device never sees it and the
      // artwork's own gesture is never taken from it.
      expect(tester.widget<IgnorePointer>(overlay).ignoring, isTrue);

      await hoverOver(tester, find.byType(ArtworkImage));
      expect(tester.widget<IgnorePointer>(overlay).ignoring, isFalse);
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.descendant(
                of: find.byType(ArtworkImage),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        1,
      );

      await tester.tap(find.bySemanticsLabel('Play Salt Harbour'));
      await tester.pumpAndSettle();
      expect(played, 1);
    });

    testWidgets('is not a tab stop while it is invisible', (tester) async {
      // IgnorePointer and a zero opacity stop it being seen or clicked
      // and neither stops it being tabbed to. A grid of these is a run
      // of invisible stops where Enter starts playback with nothing on
      // screen to say why.
      var played = 0;
      await tester.pumpWidget(
        _host(
          Column(
            children: <Widget>[
              ArtworkImage(
                size: 120,
                monogram: 'Salt Harbour',
                onPlay: () => played++,
                playLabel: 'Play Salt Harbour',
              ),
              TextButton(onPressed: () {}, child: const Text('after')),
            ],
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        played,
        0,
        reason: 'tabbing must not reach a control nothing is drawing',
      );
    });

    testWidgets('is absent entirely without an onPlay', (tester) async {
      // Opt-in per call site: a cover in an editor is a picture, and a
      // play button over it would be a lie.
      await tester.pumpWidget(
        _host(const ArtworkImage(size: 120, monogram: 'Salt Harbour')),
      );
      await hoverOver(tester, find.byType(ArtworkImage));
      expect(
        find.descendant(
          of: find.byType(ArtworkImage),
          matching: find.byType(IgnorePointer),
        ),
        findsNothing,
      );
    });
  });
}
