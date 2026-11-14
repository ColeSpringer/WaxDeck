import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/admin/backups_screen.dart';
import 'package:waxdeck/src/admin/users_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/client_prefs.dart';
import 'package:waxdeck/src/settings/settings_registry.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck/src/uploads/share_intake.dart';
import 'package:waxdeck/src/music/music_controllers.dart' show MusicDimension;
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck_api/waxdeck_api.dart'
    show ItemSummary, MediaType, SessionState, ThemePref, WaxDeckUser;
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

/// The whole app with one screen that reads the theme and counts how often
/// it is asked to rebuild: a theme that lerps over a fade rebuilds every
/// dependent on every frame of it.
class _Probe {
  _Probe() {
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Builder(
            builder: (context) {
              builds++;
              canvas = WaxColors.of(context).canvas;
              rowHeight = WaxLayout.of(context).rowHeight;
              return const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
  }

  late final GoRouter router;
  var builds = 0;
  late Color canvas;
  late double rowHeight;
}

Future<ProviderContainer> _pumpProbeApp(WidgetTester tester, _Probe probe) =>
    pumpWholeApp(
      tester,
      container: appContainer(
        extra: [routerProvider.overrideWithValue(probe.router)],
      ),
    );

/// The whole app with [screen] as its one route, at a window the screen
/// fits in. The share sheet is inert, as in [_pumpShell].
Future<ProviderContainer> _pumpScreen(WidgetTester tester, Widget screen) {
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (context, state) => screen)],
  );
  addTearDown(router.dispose);
  return pumpWholeApp(
    tester,
    container: appContainer(
      extra: [
        routerProvider.overrideWithValue(router),
        filePickerProvider.overrideWithValue(null),
        shareIntakeProvider.overrideWithValue(const InertShareIntakePort()),
      ],
    ),
  );
}

const _admin = SessionState(
  authenticated: true,
  user: WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']),
);

/// The colour a paragraph is drawn in this frame.
Color? _ink(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style?.color;

/// The signed-in shell at desktop width, mounted as the adaptive shell's
/// own tests mount it: the sidebar, its search pill and a selected
/// destination are on screen, each colouring itself from the theme.
///
/// The share sheet is inert: reading back a frame runs real async, where
/// the platform channel it polls on start answers that it is missing.
///
/// At home, or at [at] over [repo].
Future<ProviderContainer> _pumpShell(
  WidgetTester tester, {
  FakeRepository? repo,
  String? at,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = await pumpWholeApp(
    tester,
    container: appContainer(
      repo: repo ?? FakeRepository(sessionState: _admin),
      extra: [
        shareIntakeProvider.overrideWithValue(const InertShareIntakePort()),
      ],
    ),
  );
  if (at != null) {
    container.read(routerProvider).go(at);
    await tester.pumpAndSettle();
  }
  expect(find.byType(WaxSidebar), findsOneWidget);
  expect(find.byType(SearchField), findsOneWidget);
  expect(
    tester.widget<WaxShellFrame>(find.byType(WaxShellFrame)).selected,
    isNotNull,
  );
  return container;
}

/// What [of] is drawn in this frame, RGBA.
Future<Uint8List> _drawn(WidgetTester tester, Finder of) async =>
    (await tester.runAsync(() async {
      final image = await captureImage(tester.element(of));
      try {
        return (await image.toByteData())!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }))!;

/// Where a rebuilt [text] sits: the Material over it, by what built that
/// Material, which is the one whose eased style it read.
String _easedBy(Element text) {
  Element? material;
  text.visitAncestorElements((above) {
    if (above.widget is Material) material = above;
    return material == null;
  });
  return (material ?? text).debugGetCreatorChain(8);
}

int _pixelsDiffering(Uint8List a, Uint8List b) {
  var count = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] ||
        a[i + 1] != b[i + 1] ||
        a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
      count++;
    }
  }
  return count;
}

/// Changes that move the theme or its density, each applied the way the app
/// receives it.
final _changes = <String, void Function(WidgetTester, ProviderContainer)>{
  'theme': (tester, container) =>
      container.read(themeSettingProvider.notifier).set(ThemePref.dark),
  'density': (tester, container) =>
      container.read(densityProvider.notifier).set(WaxDensity.compact),
  'system appearance': (tester, container) {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  },
};

/// What the guard below mounts: the shell's empty home, and an artist's
/// page in the shell, whose release cards and track rows put the card and
/// row components on screen.
final _guardedSurfaces =
    <String, Future<ProviderContainer> Function(WidgetTester)>{
      'the signed-in shell': _pumpShell,
      'an artist page in the signed-in shell': (tester) async {
        final container = await _pumpShell(
          tester,
          repo: FakeRepository(sessionState: _admin)
            ..facetItems['artist 1'] = <ItemSummary>[
              for (var i = 1; i <= 3; i++)
                ItemSummary(
                  pid: 'tr-$i',
                  mediaType: MediaType.music,
                  title: 'Track $i',
                  artist: 'Nightjar',
                  album: 'Gullwing',
                  artistPid: 'ar-1',
                  albumPid: 'al-1',
                  trackNumber: i,
                  durationMs: 240000,
                ),
            ]
            ..finishedPids.add('tr-1'),
          at: WaxRoute.musicBucket(MusicDimension.artists, 'ar-1'),
        );
        expect(find.byType(MediaCard), findsOneWidget);
        expect(find.byType(MediaListRow), findsNWidgets(3));
        return container;
      },
    };

/// Real screens with a Text that names no colour, so it draws whatever
/// default style it sits under: the screen, and that text.
final _bareTextScreens = <String, ({Widget screen, String text})>{
  'in a WaxScaffold body': (
    screen: const BackupsScreen(),
    text: 'No backups yet',
  ),
  'under a Scaffold of its own': (
    screen: const UsersScreen(view: UsersView.invites),
    text: 'No invites yet',
  ),
};

void main() {
  testWidgets('a theme change reaches the tree on the next frame', (
    tester,
  ) async {
    final probe = _Probe();
    final container = await _pumpProbeApp(tester, probe);
    expect(probe.canvas, WaxColors.light.canvas);

    _changes['theme']!(tester, container);
    await tester.pump();

    expect(probe.canvas, WaxColors.dark.canvas);
  });

  testWidgets('the system flipping appearance lands on the next frame too', (
    tester,
  ) async {
    final probe = _Probe();
    final container = await _pumpProbeApp(tester, probe);
    expect(probe.canvas, WaxColors.light.canvas);

    _changes['system appearance']!(tester, container);
    await tester.pump();

    expect(probe.canvas, WaxColors.dark.canvas);
  });

  testWidgets('a density change lands on the next frame too', (tester) async {
    final probe = _Probe();
    final container = await _pumpProbeApp(tester, probe);
    final comfortable = WaxLayout.forDensity(WaxDensity.comfortable);
    final compact = WaxLayout.forDensity(WaxDensity.compact);
    expect(probe.rowHeight, comfortable.rowHeight);
    expect(compact.rowHeight, isNot(comfortable.rowHeight));

    _changes['density']!(tester, container);
    await tester.pump();

    expect(probe.rowHeight, compact.rowHeight);
  });

  // Their own tests, so each assertion can fail on its own: a switch that
  // is still animating keeps asking for frames.
  for (final MapEntry(:key, :value) in _changes.entries) {
    testWidgets('a $key change leaves no frame scheduled', (tester) async {
      final probe = _Probe();
      final container = await _pumpProbeApp(tester, probe);

      value(tester, container);
      await tester.pump();

      expect(
        tester.binding.hasScheduledFrame,
        isFalse,
        reason: 'nothing is animating the switch',
      );
    });
  }

  // Over the whole shell a colour change is judged by what is drawn rather
  // than by whether a frame is scheduled: the framework's own Scaffold and
  // app bar Materials still ease their default text style into a new theme
  // for kThemeChangeDuration, which nothing outside them can shorten. They
  // repaint nothing, because WaxScaffold puts a plain style between them and
  // everything a screen draws; the guard below counts what would rebuild.
  for (final key in ['theme', 'system appearance']) {
    testWidgets('a $key change over the signed-in shell lands in one frame', (
      tester,
    ) async {
      final container = await _pumpShell(tester);
      final before = await _drawn(tester, find.byType(WaxShellFrame));

      _changes[key]!(tester, container);
      await tester.pump();
      final next = await _drawn(tester, find.byType(WaxShellFrame));
      await tester.pumpAndSettle();
      final settled = await _drawn(tester, find.byType(WaxShellFrame));

      expect(
        _pixelsDiffering(before, next),
        isPositive,
        reason: 'the change redrew the shell',
      );
      expect(
        _pixelsDiffering(next, settled),
        0,
        reason: 'nothing eased into the change after its first frame',
      );
    });
  }

  // Semantics off, because a scroll view takes a new position when the
  // theme changes and a live semantics tree republishes it a frame later,
  // drawing nothing.
  testWidgets(
    'a density change over the signed-in shell leaves no frame scheduled',
    semanticsEnabled: false,
    (tester) async {
      final container = await _pumpShell(tester);

      _changes['density']!(tester, container);
      await tester.pump();

      expect(
        tester.binding.hasScheduledFrame,
        isFalse,
        reason: 'nothing is animating the switch',
      );
    },
  );

  // A Material eases its default text style into a new theme, so a Text
  // that names no colour would draw the old theme's ink for a while. The
  // frame right after the change must already be the settled one.
  for (final MapEntry(key: where, value: subject) in _bareTextScreens.entries) {
    testWidgets('inherited text lands with a theme change $where', (
      tester,
    ) async {
      final container = await _pumpScreen(tester, subject.screen);
      final screen = find.byType(subject.screen.runtimeType);
      expect(tester.widget<Text>(find.text(subject.text)).style?.color, isNull);
      expect(_ink(tester, subject.text), WaxColors.light.textPrimary);
      final before = await _drawn(tester, screen);

      _changes['theme']!(tester, container);
      await tester.pump();
      final next = await _drawn(tester, screen);
      await tester.pumpAndSettle();
      final settled = await _drawn(tester, screen);

      expect(
        _pixelsDiffering(before, next),
        isPositive,
        reason: 'the change redrew the screen',
      );
      expect(
        _pixelsDiffering(next, settled),
        0,
        reason: 'the text eased into the change after its first frame',
      );
      expect(_ink(tester, subject.text), WaxColors.dark.textPrimary);
    });
  }

  // The guard for the class: a Material eases its default text style into a
  // new theme, and every Text under it, coloured or not, rebuilds on each
  // frame of the ease. So after the switch's own frame no Text may rebuild
  // until the old ease would have ended; a new Material over text brings
  // it back. Counted through the framework's rebuild hook, which sees every
  // element the build owner rebuilds.
  for (final (key, where) in [
    for (final key in ['theme', 'system appearance'])
      for (final where in _guardedSurfaces.keys) (key, where),
  ]) {
    testWidgets('no Text rebuilds after a $key change over $where', (
      tester,
    ) async {
      final container = await _guardedSurfaces[where]!(tester);
      final rebuilt = <Element>[];
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        if (element.widget is Text) rebuilt.add(element);
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);

      _changes[key]!(tester, container);
      await tester.pump();
      expect(rebuilt, isNotEmpty, reason: 'the switch itself rebuilt text');
      rebuilt.clear();
      const frame = Duration(milliseconds: 16);
      for (
        var elapsed = Duration.zero;
        elapsed <= kThemeChangeDuration;
        elapsed += frame
      ) {
        await tester.pump(frame);
      }

      expect(
        rebuilt.map(_easedBy).toSet(),
        isEmpty,
        reason: 'text under a default text style that eases into the theme',
      );
    });
  }

  // Picking a theme closes the picker's menu while the theme it picked
  // arrives, and the menu follows it.
  testWidgets('the theme picker\'s menu closes in the theme just picked', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      at: WaxRoute.settingsSection(SettingsSection.appearance),
    );
    final picker = find.bySemanticsIdentifier(SemanticsIds.themeSelect);
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    final labels = find.descendant(
      of: find.byWidgetPredicate((w) => w is PopupMenuItem),
      matching: find.byType(Text),
    );
    Iterable<Color?> inks() => tester
        .renderObjectList<RenderParagraph>(labels)
        .map((paragraph) => paragraph.text.style?.color);
    expect(inks(), hasLength(ThemePref.values.length));
    expect(inks(), everyElement(WaxColors.light.textPrimary));

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.settingOption('theme', 'dark')),
    );
    await tester.pump();

    expect(inks(), hasLength(ThemePref.values.length), reason: 'closing');
    expect(inks(), everyElement(WaxColors.dark.textPrimary));
    await tester.pumpAndSettle();
    expect(labels, findsNothing);
  });

  testWidgets('a theme change rebuilds a theme dependent once', (tester) async {
    final probe = _Probe();
    final container = await _pumpProbeApp(tester, probe);

    final before = probe.builds;
    _changes['theme']!(tester, container);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(probe.builds - before, 1);
    expect(probe.canvas, WaxColors.dark.canvas);
  });
}
