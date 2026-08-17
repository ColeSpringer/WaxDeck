import 'package:alchemist/alchemist.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';
import 'package:waxdeck_ui_catalog/composites/album_composite.dart';
import 'package:waxdeck_ui_catalog/composites/home_composite.dart';
import 'package:waxdeck_ui_catalog/composites/player_composite.dart';
import 'package:waxdeck_ui_catalog/sample_library.dart';

/// The composites are the taste checkpoint, so they are also the goldens
/// that would catch a regression in it: a spacing change that reads fine
/// in isolation but wrecks the shelf rhythm shows up here first.
///
/// Dark and light are both baselined. Light is half the audience and gets
/// reviewed side by side rather than derived by inspection of the dark
/// build.
/// Decodes the artwork, then pumps a fixed number of frames.
///
/// Alchemist's own image precache finishes with `pumpAndSettle`, which
/// never returns on a screen holding a playing row: its bars animate for
/// as long as they are visible. So the decode happens here and the
/// settle is replaced by a deterministic frame count.
Future<void> _pump(WidgetTester tester) async {
  await tester.runAsync(() async {
    final decodes = <Future<void>>[];
    for (final element in find.byType(Image).evaluate()) {
      decodes.add(precacheImage((element.widget as Image).image, element));
    }
    for (final element in find.byType(DecoratedBox).evaluate()) {
      final decoration = (element.widget as DecoratedBox).decoration;
      if (decoration is BoxDecoration && decoration.image != null) {
        decodes.add(precacheImage(decoration.image!.image, element));
      }
    }
    await Future.wait(decodes);
  });
  await pumpNTimes(4, const Duration(milliseconds: 120))(tester);
}

Widget _screen(
  WaxThemeVariant variant,
  Widget child, {
  double width = 420,
  double height = 880,
}) => MediaQuery(
  data: MediaQueryData(size: Size(width, height)),
  child: Theme(
    data: buildWaxTheme(variant: variant),
    child: SizedBox(
      width: width,
      height: height,
      child: Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => child),
      ),
    ),
  ),
);

void main() {
  late SampleArt art;

  setUpAll(() async {
    art = await SampleArt.generate(SampleArt.seeds, size: 128);
  });

  group('composites', () {
    goldenTest(
      'home answers what you were listening to',
      fileName: 'home',
      pumpBeforeTest: _pump,
      builder: () => GoldenTestGroup(
        columns: 2,
        children: <Widget>[
          for (final variant in <WaxThemeVariant>[
            WaxThemeVariant.dark,
            WaxThemeVariant.light,
          ])
            GoldenTestScenario(
              name: 'home ${variant.name}',
              child: _screen(
                variant,
                HomeComposite(
                  art: art,
                  now: SampleLibrary.nowPlayingMusic(art),
                ),
              ),
            ),
        ],
      ),
    );

    goldenTest(
      'album detail keeps the technical channel one level down',
      fileName: 'album_detail',
      pumpBeforeTest: _pump,
      builder: () => GoldenTestGroup(
        columns: 2,
        children: <Widget>[
          for (final variant in <WaxThemeVariant>[
            WaxThemeVariant.dark,
            WaxThemeVariant.light,
          ])
            GoldenTestScenario(
              name: 'album ${variant.name}',
              child: _screen(
                variant,
                AlbumComposite(
                  art: art,
                  now: SampleLibrary.nowPlayingMusic(art),
                ),
              ),
            ),
        ],
      ),
    );

    goldenTest(
      'the player wears each medium as its own face',
      fileName: 'players',
      pumpBeforeTest: _pump,
      builder: () => GoldenTestGroup(
        columns: 2,
        children: <Widget>[
          for (final face in WaxDomain.values)
            GoldenTestScenario(
              name: 'player ${face.name}',
              child: _screen(
                WaxThemeVariant.dark,
                PlayerComposite(art: art, face: face),
              ),
            ),
          GoldenTestScenario(
            name: 'player music light',
            child: _screen(WaxThemeVariant.light, PlayerComposite(art: art)),
          ),
          GoldenTestScenario(
            name: 'player music oled',
            child: _screen(WaxThemeVariant.oled, PlayerComposite(art: art)),
          ),
        ],
      ),
    );

    goldenTest(
      'a desktop window earns its width',
      fileName: 'home_desktop',
      pumpBeforeTest: _pump,
      builder: () => GoldenTestGroup(
        columns: 1,
        children: <Widget>[
          GoldenTestScenario(
            name: 'home expanded dark',
            child: _screen(
              WaxThemeVariant.dark,
              HomeComposite(art: art, now: SampleLibrary.nowPlayingMusic(art)),
              width: 1240,
              height: 820,
            ),
          ),
        ],
      ),
    );
  });
}
