import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

// One theme for every pump, so a change of dependencies cannot stand in for
// a change of widget.
final _theme = buildWaxTheme(variant: WaxThemeVariant.dark);

Widget _host(
  Widget bar, {
  Locale locale = const Locale('en'),
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  theme: _theme,
  locale: locale,
  builder: (context, child) =>
      Directionality(textDirection: direction, child: child!),
  localizationsDelegates: waxLocalizationsDelegates,
  supportedLocales: WaxLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(child: SizedBox(width: 200, child: bar)),
  ),
);

SemanticsNode _bar(WidgetTester tester) =>
    tester.getSemantics(find.byType(WaxProgressBar));

void main() {
  testWidgets('a progress bar reports its fraction', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(const WaxProgressBar(value: 0.42)));

    expect(_bar(tester).value, '42%');
    expect(tester.getSize(find.byType(WaxProgressBar)).height, 4);

    handle.dispose();
  });

  testWidgets('the fraction is spelled the way the locale spells it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(const WaxProgressBar(value: 0.42), locale: const Locale('es')),
    );

    expect(_bar(tester).value, '42 %');

    handle.dispose();
  });

  testWidgets('a value outside zero to one is held to the ends', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(const WaxProgressBar(value: 1.7)));
    expect(_bar(tester).value, '100%');
    await tester.pumpWidget(_host(const WaxProgressBar(value: -1)));
    expect(_bar(tester).value, '0%');

    handle.dispose();
  });

  testWidgets('an indeterminate bar reports no value and keeps moving', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(const WaxProgressBar()));

    expect(_bar(tester).value, isEmpty);
    expect(tester.hasRunningAnimations, isTrue);

    handle.dispose();
  });

  testWidgets('a value that is not finite is a bar of unknown length', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    for (final value in <double>[
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      await tester.pumpWidget(_host(WaxProgressBar(value: value)));

      expect(_bar(tester).value, isEmpty, reason: '$value');
      expect(tester.hasRunningAnimations, isTrue, reason: '$value');
    }

    handle.dispose();
  });

  testWidgets('reduced motion holds the indeterminate segment still', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWaxTheme(variant: WaxThemeVariant.dark),
        localizationsDelegates: waxLocalizationsDelegates,
        supportedLocales: WaxLocalizations.supportedLocales,
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Center(child: SizedBox(width: 200, child: WaxProgressBar())),
          ),
        ),
      ),
    );

    expect(tester.hasRunningAnimations, isFalse);
    // At rest inside the track, not parked off its start edge.
    final segment = tester.getRect(
      find.descendant(
        of: find.byType(FractionallySizedBox),
        matching: find.byType(ColoredBox),
      ),
    );
    final track = tester.getRect(find.byType(WaxProgressBar));
    expect(segment.width, greaterThan(0));
    expect(segment.left, greaterThanOrEqualTo(track.left));
    expect(segment.right, lessThanOrEqualTo(track.right));
  });

  testWidgets(
    'gaining and losing a value in place starts and stops the sweep',
    (tester) async {
      await tester.pumpWidget(_host(const WaxProgressBar()));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpWidget(_host(const WaxProgressBar(value: 0.5)));
      // A ticker stopped mid-frame lets go over the next frames; a sweep
      // still running would never settle.
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pumpWidget(_host(const WaxProgressBar()));
      expect(tester.hasRunningAnimations, isTrue);
    },
  );

  testWidgets('the fill starts at the leading edge, whichever way text runs', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const WaxProgressBar(value: 0.5), direction: TextDirection.rtl),
    );

    final fill = tester.getRect(
      find.descendant(
        of: find.byType(FractionallySizedBox),
        matching: find.byType(ColoredBox),
      ),
    );
    final track = tester.getRect(find.byType(WaxProgressBar));
    expect(fill.right, moreOrLessEquals(track.right));
    expect(fill.width, moreOrLessEquals(track.width / 2));
  });
  testWidgets('the fill is the accent unless the bar is given a tone', (
    tester,
  ) async {
    Color? fill() => tester
        .widget<ColoredBox>(
          find.descendant(
            of: find.byType(FractionallySizedBox),
            matching: find.byType(ColoredBox),
          ),
        )
        .color;

    await tester.pumpWidget(_host(const WaxProgressBar(value: 0.5)));
    final colors = WaxColors.of(tester.element(find.byType(WaxProgressBar)));
    expect(fill(), colors.accent);

    // A quota at its cap, drawn as the verdict it is; so is a sweep.
    for (final value in <double?>[1, null]) {
      await tester.pumpWidget(
        _host(WaxProgressBar(value: value, tone: colors.error)),
      );
      expect(fill(), colors.error, reason: '$value');
    }
  });

  group('an empty bar in a parent that measures its content', () {
    testWidgets('sits in a loose intrinsic-width column', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme,
          localizationsDelegates: waxLocalizationsDelegates,
          supportedLocales: WaxLocalizations.supportedLocales,
          home: const Scaffold(
            body: Center(
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[Text('Marking'), WaxProgressBar(value: 0)],
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(WaxProgressBar), findsOneWidget);
    });

    testWidgets('sits in a dialog\'s content', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme,
          localizationsDelegates: waxLocalizationsDelegates,
          supportedLocales: WaxLocalizations.supportedLocales,
          home: const Scaffold(
            body: AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[Text('Marking'), WaxProgressBar(value: 0)],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(WaxProgressBar), findsOneWidget);
    });
  });
}
