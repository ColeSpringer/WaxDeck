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

      // The clear control appears only with text in the field.
      final clear = find.bySemanticsLabel('Clear search');
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
      expect(find.bySemanticsLabel('Clear search'), findsNothing);
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

  group('SearchField', () {
    testWidgets('a launcher is a button that carries no text', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(SearchField(onTap: () => taps++), height: 80),
      );

      // No field at all: the screen it opens owns the query, so there is
      // no second text state to keep in step.
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byType(SearchField));
      expect(taps, 1);
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

  group('formatSpan', () {
    test('answers how much, not what time it is', () {
      expect(formatSpan(const Duration(hours: 6)), '6 hr');
      expect(formatSpan(const Duration(hours: 1, minutes: 20)), '1 hr 20 min');
      expect(formatSpan(const Duration(minutes: 45)), '45 min');
      // Minutes are noise past ten hours, and a span under a minute is
      // still a minute rather than none.
      expect(formatSpan(const Duration(hours: 12, minutes: 40)), '12 hr');
      expect(formatSpan(const Duration(seconds: 20)), '1 min');
      expect(formatSpan(Duration.zero), '1 min');
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
      // Beyond ASCII there is no row to name, and inventing one per
      // script is a collation problem.
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
}
