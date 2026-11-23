import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

Widget _host(Widget child) => MaterialApp(
  theme: buildWaxTheme(),
  home: Scaffold(body: child),
);

/// A cover whose picture lands when the test says. Each instance is
/// another provider, as a cover asked under another name is.
class _TestCover extends ImageProvider<_TestCover> {
  /// The cover it is a picture of, null for one that names none.
  _TestCover(this.cover);

  final String? cover;

  final Completer<ImageInfo> _landing = Completer<ImageInfo>();

  void land(ui.Image image) => _landing.complete(ImageInfo(image: image));

  void fail() => _landing.completeError(StateError('404'));

  @override
  Future<_TestCover> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_TestCover>(this);

  @override
  ImageStreamCompleter loadImage(_TestCover key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(key._landing.future);
}

/// The app saying a cover was replaced.
class _Told extends ChangeNotifier {
  void tell() => notifyListeners();

  bool get heard => hasListeners;
}

Future<ui.Image> _picture(WidgetTester tester, int width) async => (await tester
    .runAsync(() => createTestImage(width: width, height: width)))!;

Future<void> _draw(WidgetTester tester, _TestCover image) => tester.pumpWidget(
  _host(
    ArtworkImage(
      size: 96,
      monogram: 'Salt Harbour',
      artwork: WaxArtwork((_) => image, cover: image.cover),
    ),
  ),
);

/// Lets a picture that has landed reach the screen and fade in. The
/// first frame after it lands may be the one that hears of it.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// The width of the picture on screen, null while none is drawn: none
/// held, or one held and faded out.
int? _drawn(WidgetTester tester) {
  final held = tester.widgetList<RawImage>(find.byType(RawImage));
  final image = held.isEmpty ? null : held.first.image;
  if (image == null) return null;
  final fades = tester.widgetList<FadeTransition>(
    find.descendant(
      of: find.byType(ArtworkImage),
      matching: find.byType(FadeTransition),
    ),
  );
  if (fades.isNotEmpty && fades.first.opacity.value < 1) return null;
  return image.width;
}

void main() {
  group('monogramInitials', () {
    test('takes the first letter or digit of each word', () {
      // Punctuation is skipped inside a word rather than drawn: "2(" on
      // an empty artwork slot was the bug.
      expect(monogramInitials('2morrow (Remix)'), '2R');
      expect(monogramInitials("(What's the Story) Morning Glory?"), 'WT');
      expect(monogramInitials('...hello'), 'H');
      expect(monogramInitials('Salt Harbour Nights'), 'SH');
    });

    test('takes a whole grapheme and upper-cases it', () {
      expect(monogramInitials('élan'), 'É');
      // Decomposed: the letter plus its combining acute is one cluster.
      expect(monogramInitials('élan'), 'É');
    });

    test('skips words with nothing usable and stops at max', () {
      expect(monogramInitials('\u{1F3B5} Mix'), 'M');
      expect(monogramInitials('_config', max: 1), 'C');
      expect(monogramInitials('Salt Harbour', max: 1), 'S');
    });

    test('is null when no word has a letter or digit', () {
      for (final name in <String>['', '   ', '...', '!? --', '\u{1F3B5}']) {
        expect(monogramInitials(name), isNull, reason: '"$name"');
      }
    });
  });

  group('artwork placeholder', () {
    testWidgets('draws initials from a title', (tester) async {
      await tester.pumpWidget(
        _host(const ArtworkImage(size: 96, monogram: 'Salt Harbour')),
      );
      expect(find.text('SH'), findsOneWidget);
    });

    testWidgets('skips punctuation to reach a letter', (tester) async {
      await tester.pumpWidget(
        _host(const ArtworkImage(size: 96, monogram: '2morrow (Remix)')),
      );
      expect(find.text('2R'), findsOneWidget);
      expect(find.text('2('), findsNothing);
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
            artwork: WaxArtwork((int px) {
              asked.add(px);
              return null;
            }),
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
            artwork: WaxArtwork((int px) {
              asked.add(px);
              return null;
            }),
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
            artwork: WaxArtwork((int px) => null),
          ),
        ),
      );
      expect(find.text('SH'), findsOneWidget);
    });
  });

  group('artwork', () {
    testWidgets('is a picture: a pointer over it offers nothing to press', (
      tester,
    ) async {
      // What plays sits beside the picture, never inside it: a row would
      // merge a play inside its own node, and a web click there would
      // open the row.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(const ArtworkImage(size: 120, monogram: 'Salt Harbour')),
      );
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(tester.getCenter(find.byType(ArtworkImage))),
      );
      await tester.pumpAndSettle();
      for (final part in <Type>[HoverPlayDisc, HoverPlayScrim, IgnorePointer]) {
        expect(
          find.descendant(
            of: find.byType(ArtworkImage),
            matching: find.byType(part),
          ),
          findsNothing,
          reason: '$part',
        );
      }
      expect(
        find.semantics.byPredicate(
          (node) => node.getSemanticsData().flagsCollection.isButton,
        ),
        findsNothing,
      );
      handle.dispose();
    });
  });

  group('a cover handed over again', () {
    testWidgets('under another name keeps its picture until the new one '
        'is ready', (tester) async {
      final old = await _picture(tester, 4);
      final fresh = await _picture(tester, 8);
      final first = _TestCover('/items/al-1/art');
      await _draw(tester, first);
      first.land(old);
      await _settle(tester);
      expect(_drawn(tester), 4);

      final second = _TestCover('/items/al-1/art');
      await _draw(tester, second);
      for (var frame = 0; frame < 6; frame++) {
        expect(_drawn(tester), 4, reason: 'frame $frame');
        expect(find.text('SH'), findsNothing);
        await tester.pump(const Duration(milliseconds: 50));
      }

      second.land(fresh);
      await tester.pump();
      await tester.pump();
      expect(_drawn(tester), 8);
    });

    testWidgets('keeps a picture that was drawn at once from memory', (
      tester,
    ) async {
      final old = await _picture(tester, 4);
      final first = _TestCover('/items/al-1/art');
      await _draw(tester, first);
      first.land(old);
      await _settle(tester);
      // Mounted again, the decoded copy answers in the same frame.
      await tester.pumpWidget(_host(const SizedBox()));
      await _draw(tester, first);
      expect(_drawn(tester), 4);

      await _draw(tester, _TestCover('/items/al-1/art'));
      for (var frame = 0; frame < 6; frame++) {
        expect(_drawn(tester), 4, reason: 'frame $frame');
        await tester.pump(const Duration(milliseconds: 50));
      }
    });

    testWidgets('for another cover in the same slot never shows the '
        'picture before it', (tester) async {
      // A list that reuses its rows by position hands a row another
      // item's cover, and the picture there is somebody else's.
      final old = await _picture(tester, 4);
      final fresh = await _picture(tester, 8);
      final first = _TestCover('/items/al-1/art');
      await _draw(tester, first);
      first.land(old);
      await _settle(tester);
      expect(_drawn(tester), 4);

      final other = _TestCover('/items/al-2/art');
      await _draw(tester, other);
      for (var frame = 0; frame < 6; frame++) {
        expect(_drawn(tester), isNull, reason: 'frame $frame');
        await tester.pump(const Duration(milliseconds: 50));
      }

      other.land(fresh);
      await _settle(tester);
      expect(_drawn(tester), 8);
    });

    testWidgets('that names no cover never shows the picture before it', (
      tester,
    ) async {
      final old = await _picture(tester, 4);
      final first = _TestCover(null);
      await _draw(tester, first);
      first.land(old);
      await _settle(tester);
      expect(_drawn(tester), 4);

      final second = _TestCover(null);
      await _draw(tester, second);
      expect(_drawn(tester), isNull);
      second.land(await _picture(tester, 8));
      await _settle(tester);
      expect(_drawn(tester), 8);

      // Nor does a cover that names itself take up a nameless one's.
      await _draw(tester, _TestCover('/items/al-1/art'));
      expect(_drawn(tester), isNull);
    });

    testWidgets('and answered that there is none draws the monogram', (
      tester,
    ) async {
      final old = await _picture(tester, 4);
      final first = _TestCover('/items/al-1/art');
      await _draw(tester, first);
      first.land(old);
      await _settle(tester);
      expect(find.text('SH'), findsNothing);

      final second = _TestCover('/items/al-1/art');
      await _draw(tester, second);
      expect(_drawn(tester), 4);
      second.fail();
      await tester.pump();
      await tester.pump();
      expect(find.text('SH'), findsOneWidget);
      expect(_drawn(tester), isNull);
    });
  });

  group('a cover on screen', () {
    testWidgets('asks again by itself when it is told its cover was '
        'replaced, and keeps its picture until the new one is ready', (
      tester,
    ) async {
      final old = await _picture(tester, 4);
      final fresh = await _picture(tester, 8);
      final told = _Told();
      ImageProvider? current = _TestCover('/items/al-1/art')..land(old);
      var asks = 0;
      var builds = 0;
      final artwork = WaxArtwork(
        (_) {
          asks++;
          return current;
        },
        cover: '/items/al-1/art',
        replaced: told,
      );
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              builds++;
              return ArtworkImage(
                size: 96,
                monogram: 'Salt Harbour',
                artwork: artwork,
              );
            },
          ),
        ),
      );
      await _settle(tester);
      expect(_drawn(tester), 4);
      expect((asks, builds), (1, 1));

      // Told nothing, it asks nothing.
      await tester.pump(const Duration(seconds: 1));
      expect(asks, 1);

      final next = _TestCover('/items/al-1/art');
      current = next;
      told.tell();
      await tester.pump();
      expect((asks, builds), (2, 1));
      expect(_drawn(tester), 4);
      next.land(fresh);
      await _settle(tester);
      expect(_drawn(tester), 8);
      expect((asks, builds), (2, 1));
    });

    testWidgets('with no picture asks again too', (tester) async {
      final told = _Told();
      _TestCover? current;
      await tester.pumpWidget(
        _host(
          ArtworkImage(
            size: 96,
            monogram: 'Salt Harbour',
            artwork: WaxArtwork(
              (_) => current,
              cover: '/items/al-1/art',
              replaced: told,
            ),
          ),
        ),
      );
      expect(find.text('SH'), findsOneWidget);

      current = _TestCover('/items/al-1/art')..land(await _picture(tester, 4));
      told.tell();
      await _settle(tester);
      expect(find.text('SH'), findsNothing);
      expect(_drawn(tester), 4);
    });

    testWidgets('stops listening when it leaves the screen, and listens to '
        'the artwork it is handed next', (tester) async {
      final first = _Told();
      final second = _Told();
      Widget cover(_Told told) => _host(
        ArtworkImage(
          size: 96,
          monogram: 'Salt Harbour',
          artwork: WaxArtwork((_) => null, replaced: told),
        ),
      );
      await tester.pumpWidget(cover(first));
      expect((first.heard, second.heard), (true, false));

      await tester.pumpWidget(cover(second));
      expect((first.heard, second.heard), (false, true));

      await tester.pumpWidget(_host(const SizedBox()));
      expect((first.heard, second.heard), (false, false));
    });
  });
}
