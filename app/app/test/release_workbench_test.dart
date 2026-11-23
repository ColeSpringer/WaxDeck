import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/l10n/explain_error.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_es.dart';
import 'package:waxdeck/src/metadata/album_pane.dart';
import 'package:waxdeck/src/metadata/release_workbench.dart';
import 'package:waxdeck/src/music/album_detail.dart';
import 'package:waxdeck/src/music/album_screen.dart';
import 'package:waxdeck/src/music/listing_screen.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/shell/navigation_history.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fake_browser.dart';
import 'fakes.dart';
import 'row_finders.dart';

const _album = 'al-01JZX5N8QW3F4V9T2B7KDALBUM';
const _regrouped = 'al-01JZX5N8QW3F4V9T2B7KDNEWER';

Finder _byId(String id) => find.bySemanticsIdentifier(id);

Finder _trackRow(String pid) =>
    rowWithIdentifier(SemanticsIds.workbenchRow(pid));

const _admin = SessionState(
  authenticated: true,
  user: WaxDeckUser(id: 'us-1', username: 'admin', roles: <String>['admin']),
);

/// One member's metadata refused while it is named in [refused], with
/// every read counted by pid.
class _MetadataRefused extends FakeRepository {
  _MetadataRefused(this.refused)
    : super(
        sessionState: _admin,
        items: [
          testItem('tr-A', title: 'Salt Harbour'),
          testItem('tr-B', title: 'Nightjar'),
        ],
      );

  final Set<String> refused;
  final asked = <String, int>{};

  @override
  Future<ItemMetadata> getItemMetadata(String pid) async {
    asked[pid] = (asked[pid] ?? 0) + 1;
    if (refused.contains(pid)) {
      throw const WaxDeckApiException(
        code: 'forbidden',
        message: 'not an administrator',
        statusCode: 403,
      );
    }
    return super.getItemMetadata(pid);
  }
}

FakeRepository _repo() => _seeded(
  FakeRepository(
    sessionState: _admin,
    items: [
      testItem('tr-A', title: 'Salt Harbour'),
      testItem('tr-B', title: 'Nightjar'),
    ],
  ),
);

/// The album and its two members' tags, on [repo].
FakeRepository _seeded(FakeRepository repo) {
  repo.albums[_album] = const AlbumDetail(
    pid: _album,
    title: 'Long Exposure',
    year: 1975,
    itemCount: 2,
  );
  repo.facetItems['album ${_album.substring(3)}'] = <ItemSummary>[
    testItem('tr-A', title: 'Salt Harbour'),
    testItem('tr-B', title: 'Nightjar'),
  ];
  // The bulk form reads each member to say which values the selection
  // agrees on: artist is common, year is mixed.
  repo.itemFieldsByPid['tr-A'] = {
    'title': 'Salt Harbour',
    'artist': 'The Casket Girls',
    'album': 'Long Exposure',
    'year': '1975',
  };
  repo.itemFieldsByPid['tr-B'] = {
    'title': 'Nightjar',
    'artist': 'The Casket Girls',
    'album': 'Long Exposure',
    'year': '1976',
  };
  return repo;
}

/// The release, whose rewrite onto another release's name merges it into
/// [_regrouped].
FakeRepository _merging() {
  final repo = _repo();
  repo.renameEntityResult = const EntityRenameResult(
    entityPid: _album,
    outcome: EntityRenameOutcome.merged,
    members: 2,
    credits: 0,
    mergedInto: _regrouped,
  );
  repo.albums[_regrouped] = const AlbumDetail(
    pid: _regrouped,
    title: 'Renamed Harbour',
    itemCount: 2,
  );
  repo.facetItems['album ${_regrouped.substring(3)}'] =
      repo.facetItems['album ${_album.substring(3)}']!;
  return repo;
}

Future<void> _pump(
  WidgetTester tester,
  FakeRepository repo, {
  Size size = const Size(1200, 2000),
  bool pushed = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await _mount(tester, repo, pushed: pushed);
  await tester.pumpAndSettle();
}

Future<void> _mount(
  WidgetTester tester,
  FakeRepository repo, {
  bool pushed = false,
}) => mountApp(
  tester,
  const ReleaseWorkbench(pid: _album),
  container: appContainer(repo: repo),
  pushed: pushed,
);

/// Hands back one small image whatever is asked for.
class _OneImage implements FilePickerPort {
  @override
  bool get canPickFolders => false;

  @override
  Future<List<PickedAudioFile>> pickAudioFiles({
    String audioLabel = '',
    String anyLabel = '',
    UploadFormatSets formats = const UploadFormatSets(),
  }) async => const [];

  @override
  Future<FolderPick> pickAudioFolder({
    UploadFormatSets formats = const UploadFormatSets(),
  }) async => const FolderPick();

  @override
  Future<PickedAudioFile?> pickFile({
    required Set<String> extensions,
    required String label,
    String anyLabel = '',
  }) async => PickedAudioFile(
    name: 'cover.png',
    size: 64,
    openRead: ([int? start, int? end]) =>
        Stream<List<int>>.value(Uint8List(64)),
  );
}

/// The album's own page, which an album's overflow opens the workbench
/// from.
final _albumPage = WaxRoute.musicBucket(MusicDimension.albums, _album);

/// The whole app at a desktop window, or [size], the workbench pushed over
/// [from] (Music) as an album's overflow opens it; in [browser]'s tab
/// where one is given.
Future<GoRouter> _openInApp(
  WidgetTester tester,
  FakeRepository repo, {
  Size size = const Size(1600, 1200),
  String from = WaxRoute.music,
  FilePickerPort? picker,
  FakeBrowser? browser,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = appContainer(
    repo: repo,
    extra: [
      if (picker != null) filePickerProvider.overrideWithValue(picker),
      if (browser != null) browserHistoryProvider.overrideWithValue(browser),
    ],
  );
  await pumpWholeApp(tester, container: container);
  final router = container.read(routerProvider)..go(from);
  await tester.pumpAndSettle();
  unawaited(router.push<void>(WaxRoute.metadata(_album)));
  await tester.pumpAndSettle();
  return router;
}

/// The whole app at a desktop window opened cold on the workbench's link,
/// in [browser]'s tab, or in a fresh one unless [native].
Future<GoRouter> _linkedInApp(
  WidgetTester tester,
  FakeRepository repo, {
  bool native = false,
  FakeBrowser? browser,
}) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.defaultRouteNameTestValue = WaxRoute.metadata(
    _album,
  );
  addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
  final tab = browser ?? (native ? null : FakeBrowser());
  final container = appContainer(
    repo: repo,
    extra: [if (tab != null) browserHistoryProvider.overrideWithValue(tab)],
  );
  await pumpWholeApp(tester, container: container);
  final router = container.read(routerProvider);
  expect(_top(router), WaxRoute.metadata(_album));
  return router;
}

/// Every location [router] arrives with from here on, its root's and each
/// push's: one it never arrived with was never built.
List<String> _arrivedWith(GoRouter router) {
  final delegate = router.routerDelegate;
  final seen = <String>[];
  void walk(List<RouteMatchBase> matches) {
    for (final match in matches) {
      switch (match) {
        case ShellRouteMatch():
          walk(match.matches);
        case ImperativeRouteMatch():
          seen.add(match.matches.uri.path);
        case _:
      }
    }
  }

  void heard() {
    seen.add(delegate.currentConfiguration.uri.path);
    walk(delegate.currentConfiguration.matches);
  }

  delegate.addListener(heard);
  addTearDown(() => delegate.removeListener(heard));
  return seen;
}

/// Whether a page of the release [pid] is anywhere in the tree, offstage
/// too: its workbench or its album page.
bool _anyPageOf(String pid) => find
    .byWidgetPredicate(
      (widget) =>
          (widget is ReleaseWorkbench && widget.pid == pid) ||
          (widget is AlbumScreen && widget.pid == pid),
      skipOffstage: false,
    )
    .evaluate()
    .isNotEmpty;

/// The page on top of [router]'s screen: a push keeps the location it
/// was made from.
String _top(GoRouter router) => pageOnTop(router)!.location;

/// Every message raised to the shell from here on, in order.
List<ShellMessage> _raised(WidgetTester tester) {
  final raised = <ShellMessage>[];
  final heard =
      ProviderScope.containerOf(
        tester.element(find.byType(Navigator).first),
        listen: false,
      ).listen(shellMessagesProvider, (_, next) {
        if (next != null) raised.add(next);
      });
  addTearDown(heard.close);
  return raised;
}

/// The container [tester]'s screen runs over.
ProviderContainer _containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(Navigator).first),
      listen: false,
    );

/// The release as a screen still watching it reads it, kept read while
/// the workbench is gone: the album page Back lands on draws it.
AlbumDetail? Function() _watchedAlbum(WidgetTester tester) {
  final container = _containerOf(tester);
  container.listen(albumDetailProvider(_album), (_, _) {});
  return () => container.read(albumDetailProvider(_album)).value;
}

/// Closes the album or bulk sheet on top, as a swipe down does.
Future<void> _dismissSheet(WidgetTester tester, String inside) async {
  Navigator.of(tester.element(_byId(inside))).pop();
  await tester.pumpAndSettle();
  expect(_byId(inside), findsNothing);
}

void main() {
  testWidgets("the members list pads none of the window's insets: the page "
      'and its bar have taken them', (tester) async {
    const insets = FakeViewPadding(top: 24, bottom: 34);
    tester.view
      ..padding = insets
      ..viewPadding = insets;
    await _pump(tester, _repo());

    final list = find.descendant(
      of: _byId(SemanticsIds.workbenchList),
      matching: find.byType(ListView),
    );
    expect(
      tester
          .widget<SliverPadding>(
            find.descendant(of: list, matching: find.byType(SliverPadding)),
          )
          .padding,
      EdgeInsets.zero,
    );
    expect(tester.getRect(list).bottom, 2000 - 34, reason: 'its foot');
  });

  group("the foot bars stand on the window's foot", () {
    const insets = FakeViewPadding(left: 40, right: 30, bottom: 20);

    Future<void> pumpInset(WidgetTester tester, {Size? size}) async {
      tester.view
        ..padding = insets
        ..viewPadding = insets;
      await _pump(tester, _repo(), size: size ?? const Size(1200, 2000));
    }

    /// The save bar in the pane: its surface from the pane's start to the
    /// window's end and foot, its contents inside the insets.
    void expectPaneBar(WidgetTester tester) {
      final pane = tester.getRect(_byId(SemanticsIds.workbenchPane));
      final bar = tester.getRect(find.byType(WaxFootBar));
      expect((bar.left, bar.right, bar.bottom), (pane.left, 1200.0, 2000.0));
      final inner = tester.getRect(_byId(SemanticsIds.metadataSaveBar));
      expect(
        (inner.left, inner.right, inner.bottom),
        (pane.left, 1200 - 30.0, 2000 - 20.0),
      );
      final list = tester.getRect(_byId(SemanticsIds.workbenchList));
      expect((list.left, list.bottom), (40.0, 2000 - 20.0), reason: 'the list');
    }

    testWidgets("two panes: a track's save bar", (tester) async {
      await pumpInset(tester);
      await tester.tap(_trackRow('tr-A'));
      await tester.pumpAndSettle();
      expectPaneBar(tester);
    });

    testWidgets("two panes: the bulk form's save bar", (tester) async {
      await pumpInset(tester);
      await tester.longPress(_trackRow('tr-A'));
      await tester.pumpAndSettle();
      await tester.tap(_trackRow('tr-B'));
      await tester.pumpAndSettle();
      expect(_byId(SemanticsIds.workbenchBulkPane), findsOneWidget);
      expectPaneBar(tester);
    });

    testWidgets('one pane: the bulk sheet takes a side cutout only for what '
        'of it reaches past the gap beside the sheet', (tester) async {
      tester.view
        ..padding = const FakeViewPadding(left: 44, bottom: 20)
        ..viewPadding = const FakeViewPadding(left: 44, bottom: 20);
      await _pump(tester, _repo(), size: const Size(650, 900));
      await tester.longPress(_trackRow('tr-A'));
      await tester.pumpAndSettle();
      await tester.tap(_byId(SemanticsIds.workbenchBulkEdit));
      await tester.pumpAndSettle();

      final pane = _byId(SemanticsIds.workbenchBulkPane);
      final sheet = tester.getRect(pane);
      expect((sheet.left, sheet.right), (5.0, 645.0), reason: 'the sheet');
      final form = tester.getRect(
        find.descendant(of: pane, matching: find.byType(SingleChildScrollView)),
      );
      expect(form.left, 44.0, reason: 'the form, at the cutout line');
      final bar = tester.getRect(find.byType(WaxFootBar));
      expect((bar.left, bar.right, bar.bottom), (5.0, 645.0, 900.0));
      expect(tester.getRect(_byId(SemanticsIds.metadataSaveBar)).left, 44.0);
    });

    testWidgets("one pane: the bulk bar's surface reaches the window's edges "
        'at the foot, its controls and the list above it clear of the '
        'insets', (tester) async {
      await pumpInset(tester, size: const Size(500, 900));
      await tester.longPress(_trackRow('tr-A'));
      await tester.pumpAndSettle();

      final bar = tester.getRect(_byId(SemanticsIds.workbenchBulkBar));
      expect((bar.left, bar.right, bar.bottom), (0.0, 500.0, 900.0));
      final edit = tester.getRect(_byId(SemanticsIds.workbenchBulkEdit));
      expect(edit.right, 500 - 30 - 16.0, reason: 'its controls, the end');
      expect(edit.bottom, lessThanOrEqualTo(900 - 20.0));
      final list = tester.getRect(_byId(SemanticsIds.workbenchList));
      expect((list.left, list.right, list.bottom), (40.0, 470.0, bar.top));
    });
  });

  group('the two panes hold their floors inside the side insets', () {
    const insets = FakeViewPadding(left: 44, right: 30);

    /// The narrowest window that holds both once the list and the pane
    /// have taken the cutouts beside them.
    const fits = ReleaseWorkbench.twoPaneMinWidth + 44 + 30;

    Future<void> pumpAt(WidgetTester tester, double width) async {
      tester.view
        ..padding = insets
        ..viewPadding = insets;
      await _pump(tester, _repo(), size: Size(width, 900));
    }

    double list(WidgetTester tester) =>
        tester.getSize(_byId(SemanticsIds.workbenchList)).width;
    double pane(WidgetTester tester) =>
        tester.getSize(find.byType(AlbumPane)).width;

    testWidgets('one pane until the room inside the cutouts holds both', (
      tester,
    ) async {
      await pumpAt(tester, fits - 1);
      expect(find.byType(WaxSplitter), findsNothing);

      await pumpAt(tester, fits);
      expect(find.byType(WaxSplitter), findsOneWidget);
      expect(list(tester), ReleaseWorkbench.listMin, reason: 'the list');
      expect(pane(tester), ReleaseWorkbench.paneMin, reason: 'the pane');
    });

    testWidgets('the seam dragged to either end leaves each part its floor '
        'inside the cutout beside it', (tester) async {
      await pumpAt(tester, 1200);
      Future<void> drag(double dx) async {
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(WaxSplitter)),
        );
        await gesture.moveBy(Offset(dx.sign * 40, 0));
        await gesture.moveBy(Offset(dx, 0));
        await gesture.up();
        await tester.pumpAndSettle();
      }

      await drag(2000);
      expect(pane(tester), ReleaseWorkbench.paneMin, reason: 'the pane');
      await drag(-2000);
      expect(list(tester), ReleaseWorkbench.listMin, reason: 'the list');
    });
  });

  group("the workbench's sheets", () {
    /// The window's insets as the engine reports them under a keyboard
    /// [keyboard] tall: a gesture bar of 34 and a cutout each side.
    void engine(WidgetTester tester, {double keyboard = 0}) {
      tester.view
        ..viewPadding = const FakeViewPadding(left: 44, right: 30, bottom: 34)
        ..viewInsets = FakeViewPadding(bottom: keyboard)
        ..padding = FakeViewPadding(
          left: 44,
          right: 30,
          bottom: math.max(0, 34 - keyboard),
        );
    }

    /// One pane, the sheet as wide as the window, so it reaches both
    /// cutouts.
    Future<void> pump(WidgetTester tester) async {
      engine(tester);
      await _pump(tester, _repo(), size: const Size(600, 900));
    }

    Future<void> openAlbum(WidgetTester tester) async {
      await tester.tap(_byId(SemanticsIds.workbenchAlbumRow));
      await tester.pumpAndSettle();
    }

    Future<void> openBulk(WidgetTester tester) async {
      await tester.longPress(_trackRow('tr-A'));
      await tester.pumpAndSettle();
      await tester.tap(_byId(SemanticsIds.workbenchBulkEdit));
      await tester.pumpAndSettle();
      expect(_byId(SemanticsIds.workbenchBulkPane), findsOneWidget);
    }

    testWidgets("the album sheet's form keeps inside the cutouts and above "
        'the gesture bar', (tester) async {
      await pump(tester);
      await openAlbum(tester);
      final form = tester.getRect(find.byType(AlbumPane));
      expect((form.left, form.right, form.bottom), (44.0, 570.0, 900 - 34.0));
    });

    for (final keyboard in <double>[17, 300]) {
      testWidgets('the album sheet rises over a keyboard $keyboard tall', (
        tester,
      ) async {
        await pump(tester);
        await openAlbum(tester);
        engine(tester, keyboard: keyboard);
        await tester.pumpAndSettle();
        // The keyboard's top, or the gesture bar's where it is taller.
        final foot = 900 - math.max(keyboard, 34);
        expect(tester.getRect(find.byType(AlbumPane)).bottom, foot);
      });

      testWidgets('the bulk sheet and its save bar rise over a keyboard '
          '$keyboard tall', (tester) async {
        await pump(tester);
        await openBulk(tester);
        engine(tester, keyboard: keyboard);
        await tester.pumpAndSettle();
        final bar = tester.getRect(find.byType(WaxFootBar));
        expect(bar.bottom, 900 - keyboard, reason: "the bar's surface");
        expect(
          tester.getRect(_byId(SemanticsIds.metadataSaveBar)).bottom,
          900 - math.max(keyboard, 34),
          reason: 'its controls',
        );
        final form = tester.getRect(
          find.descendant(
            of: _byId(SemanticsIds.workbenchBulkPane),
            matching: find.byType(SingleChildScrollView),
          ),
        );
        expect(form.bottom, bar.top, reason: 'the form');
      });
    }
  });

  for (final height in <double>[390, 300]) {
    for (final width in <double>[1200, 420]) {
      testWidgets('lays out without overflow at ${width}x$height', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await _mount(tester, _repo());
        expect(tester.takeException(), isNull, reason: 'first frame');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'settled');
      });
    }
  }

  testWidgets('waits for the session before it refuses anyone', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _repo()..getSessionGate = Completer<void>();
    await _mount(tester, repo);
    await tester.pump();

    expect(find.text('Only administrators can edit a release'), findsNothing);
    expect(find.byType(SkeletonShapes), findsOneWidget);

    repo.getSessionGate!.complete();
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.metadataWorkbench), findsOneWidget);
  });

  testWidgets(
    'the member list on its way is a ghost that fits a short window',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 440);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = _repo()..listItemsGate = Completer<void>();
      await _mount(tester, repo);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SkeletonShapes), findsWidgets);
      expect(tester.takeException(), isNull);
      repo.listItemsGate!.complete();
      repo.listItemsGate = null;
      await tester.pumpAndSettle();
    },
  );

  testWidgets('the next page of members is one ghost row, not a spinner', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _repo();
    repo.facetItems['album ${_album.substring(3)}'] = <ItemSummary>[
      for (var i = 0; i <= kQueueCap; i++) testItem('tr-$i', title: 'Track $i'),
    ];
    await _mount(tester, repo);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ReleaseWorkbench)),
    );
    repo.listItemsGate = Completer<void>();
    final loading = container
        .read(
          musicItemsProvider((
            dimension: MusicDimension.albums,
            segment: _album,
            domain: BrowseDomain.wholeLibrary,
          )).notifier,
        )
        .loadMore();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final list = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    list.position.jumpTo(list.position.maxScrollExtent);
    await tester.pump();
    list.position.jumpTo(list.position.maxScrollExtent);
    await tester.pump();

    expect(find.byType(SkeletonShapes), findsOneWidget);
    expect(find.byType(WaxSpinner), findsNothing);
    expect(tester.takeException(), isNull);
    repo.listItemsGate!.complete();
    repo.listItemsGate = null;
    await loading;
    await tester.pumpAndSettle();
  });

  testWidgets('the album pane opens first and a track tap swaps its editor '
      'in', (tester) async {
    final repo = _repo();
    await _pump(tester, repo);

    // The default selection is the release itself.
    expect(_byId(SemanticsIds.albumEditor), findsOneWidget);
    expect(_byId(SemanticsIds.workbenchRow('tr-A')), findsOneWidget);

    await tester.tap(_trackRow('tr-A'));
    await tester.pumpAndSettle();

    // The item editor for the tapped member, in place of the album form.
    expect(_byId(SemanticsIds.metadataField('title')), findsOneWidget);
    expect(_byId(SemanticsIds.albumEditor), findsNothing);

    await tester.tap(_byId(SemanticsIds.workbenchAlbumRow));
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.albumEditor), findsOneWidget);
  });

  testWidgets('checked tracks open the bulk form; common values seed and '
      'mixed ones say so', (tester) async {
    final repo = _repo();
    await _pump(tester, repo);

    await tester.longPress(_trackRow('tr-A'));
    await tester.pumpAndSettle();
    await tester.tap(_trackRow('tr-B'));
    await tester.pumpAndSettle();

    expect(_byId(SemanticsIds.workbenchBulkPane), findsOneWidget);
    // The selection agrees on the artist, so the field opens on it.
    expect(find.text('The Casket Girls'), findsOneWidget);
    // It disagrees on the title and the year, so those fields open
    // empty under the sentinel: an untouched mixed field is never sent.
    expect(find.text('Mixed'), findsNWidgets(2));
    // Artist and album are common values read from the files; the fields
    // neither track holds draw no chip.
    expect(find.text('tags'), findsNWidgets(2));
    expect(find.byType(CodecChip), findsNWidgets(4));

    await tester.enterText(
      _byId(SemanticsIds.workbenchBulkField('artist')),
      'The Harbour Lights',
    );
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.workbenchBulkSave));
    await tester.pumpAndSettle();

    final call = repo.bulkEditCalls.single;
    expect(call.itemPids, ['tr-A', 'tr-B']);
    // Only the edited field rides the batch - not the mixed year, not
    // the agreed-but-untouched title or album.
    expect(call.fields, {'artist': 'The Harbour Lights'});
    expect(call.skipLocked, isFalse);
    expect(call.force, isFalse);

    // The toggle is the pointer's way out of selection, and it lives in
    // the list header rather than in a virtualised row, so a scroll
    // down a long release can never dispose it.
    expect(_byId(SemanticsIds.workbenchSelectToggle), findsOneWidget);
    await tester.tap(_byId(SemanticsIds.workbenchSelectToggle));
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.workbenchBulkPane), findsNothing);
  });

  testWidgets('a bulk seed the server refuses says so at once and is asked '
      'once', (tester) async {
    final repo = _MetadataRefused({'tr-B'});
    _seeded(repo);
    await _pump(tester, repo);
    await tester.longPress(_trackRow('tr-A'));
    await tester.pumpAndSettle();
    await tester.tap(_trackRow('tr-B'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(repo.asked['tr-B'], 1);
    final retry = find.widgetWithText(WaxButton, 'Try again');
    expect(tester.widget<WaxButton>(retry).busy, isFalse);
  });

  testWidgets('a rename seed the server refuses is asked once', (tester) async {
    final repo = _MetadataRefused({'tr-A', 'tr-B'});
    _seeded(repo);
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Not settled: a retrying card's busy Try again keeps frames coming
    // for the whole backoff, so settling would sit through it.
    await _mount(tester, repo);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    // The album pane's seed reads the first member and nothing else.
    expect(repo.asked, {'tr-A': 1});
    final retry = find.widgetWithText(WaxButton, 'Try again');
    expect(tester.widget<WaxButton>(retry).busy, isFalse);
  });

  testWidgets('a shared value credits whoever set it on every track, and '
      'sources that differ credit no one', (tester) async {
    final repo = _repo();
    // Both tracks' artist was set by hand, and their album read from the
    // files. Their album artist agrees, but one track's was set by hand.
    repo.itemProvenance['tr-A'] = const [
      FieldProvenance(field: 'artist', source: 'user', locked: true),
      FieldProvenance(field: 'album_artist', source: 'user', locked: true),
    ];
    repo.itemProvenance['tr-B'] = const [
      FieldProvenance(field: 'artist', source: 'user', locked: true),
    ];
    repo.itemFieldsByPid['tr-A']!['album_artist'] = 'The Casket Girls';
    repo.itemFieldsByPid['tr-B']!['album_artist'] = 'The Casket Girls';
    await _pump(tester, repo);

    await tester.longPress(_trackRow('tr-A'));
    await tester.pumpAndSettle();
    await tester.tap(_trackRow('tr-B'));
    await tester.pumpAndSettle();

    /// The chip drawn level with [field]'s box, if any.
    String? chipBeside(String field) {
      final box = tester.getRect(_byId(SemanticsIds.workbenchBulkField(field)));
      for (final chip in find.byType(CodecChip).evaluate()) {
        final at = tester.getCenter(find.byWidget(chip.widget));
        if (at.dy >= box.top && at.dy <= box.bottom) {
          return (chip.widget as CodecChip).label;
        }
      }
      return null;
    }

    expect(chipBeside('artist'), 'you');
    expect(chipBeside('album'), 'tags');
    expect(chipBeside('album_artist'), isNull);
    expect(chipBeside('title'), 'Mixed');
  });

  // The rewrite goes through the entity rename, not a bulk edit over a
  // drained member list: the server enumerates the members, so a page
  // that scrolled only part of the way cannot split the release.
  Future<void> rewriteAlbum(WidgetTester tester, String title) async {
    await tester.ensureVisible(_byId(SemanticsIds.albumRewriteField('album')));
    await tester.pumpAndSettle();
    await tester.enterText(
      _byId(SemanticsIds.albumRewriteField('album')),
      title,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(_byId(SemanticsIds.albumRewriteApply));
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.albumRewriteApply));
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.albumRewriteConfirm));
    await tester.pumpAndSettle();
  }

  testWidgets('the rewrite section renames the release in place', (
    tester,
  ) async {
    final repo = _repo();
    await _pump(tester, repo);
    final raised = _raised(tester);
    await rewriteAlbum(tester, 'Renamed Harbour');
    expect(raised.map(shellMessageText), ['Rewrote 2 tracks']);

    // Force, because the rewrite itself locks these fields: without it
    // the second rename would refuse on the first one's locks.
    final call = repo.renameEntityCalls.single;
    expect(call.entityType, 'album');
    expect(call.entityPid, _album);
    expect(call.fields, {'album': 'Renamed Harbour'});
    expect(call.force, isTrue);
    expect(repo.bulkEditCalls, isEmpty);

    // The release kept its pid, so the workbench stays where it is and
    // shows the new title.
    expect(find.text('Renamed Harbour'), findsWidgets);
    expect(find.text('Long Exposure'), findsNothing);
  });

  // An album's year follows its tracks rather than keying the release,
  // and the server refuses one in a rename, so the section offers the
  // two fields that key it and nothing it would only refuse.
  testWidgets('the rewrite section offers the keying fields alone', (
    tester,
  ) async {
    await _pump(tester, _repo());
    await tester.ensureVisible(_byId(SemanticsIds.albumRewriteField('album')));
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.albumRewriteField('album')), findsOneWidget);
    expect(
      _byId(SemanticsIds.albumRewriteField('album_artist')),
      findsOneWidget,
    );
    expect(_byId(SemanticsIds.albumRewriteField('year')), findsNothing);
    expect(find.text('Album and album artist'), findsOneWidget);
  });

  /// Clears the release's MusicBrainz id in the album pane and saves.
  Future<void> clearMbid(WidgetTester tester) async {
    final mbid = _byId(SemanticsIds.metadataField('mbid'));
    await tester.ensureVisible(mbid);
    await tester.pumpAndSettle();
    await tester.enterText(mbid, '');
    await tester.pumpAndSettle();
    final save = _byId(SemanticsIds.metadataSave);
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pump();
  }

  testWidgets('a rewrite onto a taken name merges, and the workbench '
      'follows the survivor', (tester) async {
    final repo = _merging();
    await _pump(tester, repo);
    final raised = _raised(tester);
    await rewriteAlbum(tester, 'Renamed Harbour');

    // The named release is gone, so the surface moved to the one that
    // absorbed it rather than sitting on a dead pid.
    expect(find.text('Renamed Harbour'), findsWidgets);
    expect(find.text('Long Exposure'), findsNothing);
    expect(raised.map(shellMessageText), ['Merged into the existing release.']);
    expect(raised.single.onAction, isNull);
    expect(
      raised.single.resolve(AppLocalizationsEs()),
      AppLocalizationsEs().musicAlbumRewriteMerged,
      reason: 'worded in the locale that draws it',
    );
  });

  testWidgets('a rewrite that merges once a page was opened over the '
      'workbench leaves that page up, offers the survivor in one message, '
      "and back returns to the survivor's workbench, not the release merged "
      'away', (tester) async {
    final repo = _merging();
    final router = await _openInApp(tester, repo);
    final gate = repo.renameEntityGate = Completer<void>();
    await rewriteAlbum(tester, 'Renamed Harbour');
    final raised = _raised(tester);

    unawaited(router.push<void>(WaxRoute.settings));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(_top(router), WaxRoute.settings, reason: 'where the visitor went');
    final offer = raised.single;
    expect(shellMessageText(offer), AppLocalizationsEn().metadataMergedReady);
    expect(offer.actionLabelIn(AppLocalizationsEn()), 'Open');
    final es = AppLocalizationsEs();
    expect(
      offer.resolve(es),
      es.metadataMergedReady,
      reason: 'worded at the draw',
    );
    expect(offer.actionLabelIn(es), es.commonOpen);
    await tester.pumpAndSettle();
    expect(find.text(AppLocalizationsEn().metadataMergedReady), findsOneWidget);

    // The workbench under that page is the survivor's now.
    tester.element(find.byType(WaxScaffold).last).back();
    await tester.pumpAndSettle();
    expect(_top(router), WaxRoute.metadata(_regrouped));
    expect(_anyPageOf(_album), isFalse);
    expect(find.text('Renamed Harbour'), findsWidgets);

    // Offered where the visitor was; here it is up already.
    offer.onAction!();
    await tester.pumpAndSettle();
    expect(_top(router), WaxRoute.metadata(_regrouped));
    expect(
      find.byType(ReleaseWorkbench, skipOffstage: false),
      findsOneWidget,
      reason: 'no second copy over itself',
    );

    tester.element(find.byType(ReleaseWorkbench)).back();
    await tester.pumpAndSettle();
    expect(_top(router), WaxRoute.music);
    expect(find.byType(ReleaseWorkbench, skipOffstage: false), findsNothing);
  });

  testWidgets('a rewrite that merges as its sheet is dismissed still takes '
      'the workbench to the survivor, and says so', (tester) async {
    final repo = _merging();
    await _pump(tester, repo, size: const Size(500, 900));
    await tester.tap(_byId(SemanticsIds.workbenchAlbumRow));
    await tester.pumpAndSettle();
    final gate = repo.renameEntityGate = Completer<void>();
    await rewriteAlbum(tester, 'Renamed Harbour');
    final raised = _raised(tester);

    await _dismissSheet(tester, SemanticsIds.albumEditor);
    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.widget<ReleaseWorkbench>(find.byType(ReleaseWorkbench)).pid,
      _regrouped,
    );
    expect(find.text('Renamed Harbour'), findsWidgets);
    expect(raised.map(shellMessageText), ['Merged into the existing release.']);
    expect(raised.single.onAction, isNull);
  });

  testWidgets('an mbid cleared that merges as its sheet is dismissed still '
      'takes the workbench to the survivor, and says so', (tester) async {
    final repo = _merging()..entityEditMergesInto = _regrouped;
    repo.albums[_album] = const AlbumDetail(
      pid: _album,
      title: 'Long Exposure',
      mbid: 'b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d',
      itemCount: 2,
    );
    await _pump(tester, repo, size: const Size(500, 900));
    await tester.tap(_byId(SemanticsIds.workbenchAlbumRow));
    await tester.pumpAndSettle();
    final gate = repo.editEntityGate = Completer<void>();
    await clearMbid(tester);
    final raised = _raised(tester);

    await _dismissSheet(tester, SemanticsIds.albumEditor);
    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repo.entityEdits.single.edits, {'mbid': ''});
    expect(
      tester.widget<ReleaseWorkbench>(find.byType(ReleaseWorkbench)).pid,
      _regrouped,
    );
    expect(raised.map(shellMessageText), ['Merged into the existing release.']);
    expect(raised.single.onAction, isNull);
  });

  /// The whole app at a phone's width on the workbench gone to as a link
  /// is (the player's Edit metadata goes there the same way).
  Future<GoRouter> goneToAtPhoneWidth(
    WidgetTester tester,
    FakeRepository repo,
  ) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = appContainer(repo: repo);
    await pumpWholeApp(tester, container: container);
    final router = container.read(routerProvider)
      ..go(WaxRoute.metadata(_album));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('the album sheet goes with its workbench when a go to another '
      "release takes the workbench's page", (tester) async {
    final router = await goneToAtPhoneWidth(tester, _merging());
    await tester.tap(_byId(SemanticsIds.workbenchAlbumRow));
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.albumEditor), findsOneWidget);

    router.go(WaxRoute.metadata(_regrouped));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_top(router), WaxRoute.metadata(_regrouped));
    expect(_byId(SemanticsIds.albumEditor), findsNothing);
    expect(
      tester.widget<ReleaseWorkbench>(find.byType(ReleaseWorkbench)).pid,
      _regrouped,
    );
  });

  testWidgets('the bulk sheet goes with its workbench when a go to another '
      "release takes the workbench's page", (tester) async {
    final router = await goneToAtPhoneWidth(tester, _merging());
    await tester.longPress(_trackRow('tr-A'));
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.workbenchBulkEdit));
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.workbenchBulkPane), findsOneWidget);

    router.go(WaxRoute.metadata(_regrouped));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_top(router), WaxRoute.metadata(_regrouped));
    expect(_byId(SemanticsIds.workbenchBulkPane), findsNothing);
  });

  testWidgets('a save from the album sheet as a go to another release takes '
      'its workbench still goes out, and says so', (tester) async {
    final repo = _merging();
    final router = await goneToAtPhoneWidth(tester, repo);
    await tester.tap(_byId(SemanticsIds.workbenchAlbumRow));
    await tester.pumpAndSettle();
    final label = _byId(SemanticsIds.metadataField('label'));
    await tester.ensureVisible(label);
    await tester.pumpAndSettle();
    await tester.enterText(label, 'Harbour Lights Records');
    await tester.pumpAndSettle();
    final raised = _raised(tester);

    router.go(WaxRoute.metadata(_regrouped));
    await tester.pump();
    // The sheet, still drawn, answers its Save as the workbench that
    // opened it has gone.
    tester
        .widgetList<WaxButton>(find.byType(WaxButton))
        .firstWhere((button) => button.semanticsId == SemanticsIds.metadataSave)
        .onPressed!();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repo.entityEdits.single.edits, {'label': 'Harbour Lights Records'});
    expect(raised.map(shellMessageText), ['Saved']);
    expect(_byId(SemanticsIds.albumEditor), findsNothing);
  });

  testWidgets('a rewrite that merges while its sheet is up closes the sheet '
      'and puts the survivor in place of the workbench', (tester) async {
    final repo = _merging();
    final router = await _openInApp(tester, repo, size: const Size(500, 900));
    await tester.tap(_byId(SemanticsIds.workbenchAlbumRow));
    await tester.pumpAndSettle();
    final raised = _raised(tester);
    await rewriteAlbum(tester, 'Renamed Harbour');

    expect(tester.takeException(), isNull);
    expect(_byId(SemanticsIds.albumEditor), findsNothing);
    expect(_top(router), WaxRoute.metadata(_regrouped));
    expect(find.text('Renamed Harbour'), findsWidgets);
    expect(raised.map(shellMessageText), ['Merged into the existing release.']);

    tester.element(find.byType(ReleaseWorkbench)).back();
    await tester.pumpAndSettle();
    expect(_top(router), WaxRoute.music);
    expect(find.byType(ReleaseWorkbench, skipOffstage: false), findsNothing);
  });

  testWidgets('a rewrite that merges once its sheet and the workbench were '
      'left offers the survivor where the visitor is, in one message', (
    tester,
  ) async {
    final repo = _merging();
    await _pump(tester, repo, size: const Size(500, 900), pushed: true);
    final router = GoRouter.of(tester.element(find.byType(ReleaseWorkbench)));
    await tester.tap(_byId(SemanticsIds.workbenchAlbumRow));
    await tester.pumpAndSettle();
    final gate = repo.renameEntityGate = Completer<void>();
    await rewriteAlbum(tester, 'Renamed Harbour');
    final raised = _raised(tester);

    await _dismissSheet(tester, SemanticsIds.albumEditor);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(ReleaseWorkbench), findsNothing);
    final left = _top(router);
    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_top(router), left, reason: 'where the visitor went');
    expect(find.byType(ReleaseWorkbench, skipOffstage: false), findsNothing);
    final offer = raised.single;
    expect(shellMessageText(offer), AppLocalizationsEn().metadataMergedReady);
    expect(offer.actionLabelIn(AppLocalizationsEn()), 'Open');

    offer.onAction!();
    await tester.pumpAndSettle();
    expect(_top(router), WaxRoute.metadata(_regrouped));
    expect(find.text('Renamed Harbour'), findsWidgets);
  });

  testWidgets('an mbid cleared that merges once back left the workbench '
      'offers the survivor in one message, and the release is not shown '
      'again', (tester) async {
    final repo = _merging()..entityEditMergesInto = _regrouped;
    repo.albums[_album] = const AlbumDetail(
      pid: _album,
      title: 'Long Exposure',
      mbid: 'b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d',
      itemCount: 2,
    );
    final router = await _openInApp(tester, repo);
    final gate = repo.editEntityGate = Completer<void>();
    await clearMbid(tester);
    final raised = _raised(tester);

    tester.element(find.byType(ReleaseWorkbench)).back();
    await tester.pumpAndSettle();
    expect(_top(router), WaxRoute.music);
    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repo.entityEdits.single.edits, {'mbid': ''});
    expect(_top(router), WaxRoute.music, reason: 'where the visitor went');
    expect(find.byType(ReleaseWorkbench, skipOffstage: false), findsNothing);
    final offer = raised.single;
    expect(shellMessageText(offer), AppLocalizationsEn().metadataMergedReady);
    expect(offer.actionLabelIn(AppLocalizationsEn()), 'Open');
    expect(find.text(AppLocalizationsEn().metadataMergedReady), findsOneWidget);

    offer.onAction!();
    await tester.pumpAndSettle();
    expect(_top(router), WaxRoute.metadata(_regrouped));
    expect(
      tester.widget<ReleaseWorkbench>(find.byType(ReleaseWorkbench)).pid,
      _regrouped,
    );
  });

  /// Checks both tracks and moves them onto another album's name, which
  /// the server answers with the release they landed on; settled unless
  /// the server is held, which keeps the save busy.
  Future<void> regroup(
    WidgetTester tester,
    FakeRepository repo, {
    bool held = false,
  }) async {
    repo.bulkEditRegroupsTo = _regrouped;
    await tester.longPress(_trackRow('tr-A'));
    await tester.pumpAndSettle();
    await tester.tap(_trackRow('tr-B'));
    await tester.pumpAndSettle();
    await tester.enterText(
      _byId(SemanticsIds.workbenchBulkField('album')),
      'Renamed Harbour',
    );
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.workbenchBulkSave));
    if (held) {
      await tester.pump();
    } else {
      await tester.pumpAndSettle();
    }
  }

  testWidgets("a regroup's door opens the release the tracks moved to in "
      'place of the workbench', (tester) async {
    final repo = _merging();
    await _pump(tester, repo, pushed: true);
    final router = GoRouter.of(tester.element(find.byType(ReleaseWorkbench)));
    await regroup(tester, repo);

    final door = raisedMessage(tester)!;
    expect(door.actionLabel, 'Open it');
    await pressRaisedAction(tester);

    expect(tester.takeException(), isNull);
    expect(_top(router), WaxRoute.metadata(_regrouped));
    expect(
      tester.widget<ReleaseWorkbench>(find.byType(ReleaseWorkbench)).pid,
      _regrouped,
    );
  });

  testWidgets("a regroup's door taken once the workbench was left opens the "
      'release the tracks moved to where the visitor is', (tester) async {
    final repo = _merging();
    await _pump(tester, repo, pushed: true);
    final router = GoRouter.of(tester.element(find.byType(ReleaseWorkbench)));
    await regroup(tester, repo);
    expect(raisedMessage(tester)!.actionLabel, 'Open it');

    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(ReleaseWorkbench), findsNothing);
    await pressRaisedAction(tester);

    expect(tester.takeException(), isNull);
    expect(_top(router), WaxRoute.metadata(_regrouped));
    expect(
      tester.widget<ReleaseWorkbench>(find.byType(ReleaseWorkbench)).pid,
      _regrouped,
    );
  });

  testWidgets('a rename that lands once the workbench was left says so '
      'where the visitor is, and the release is read again', (tester) async {
    final repo = _repo();
    await _pump(tester, repo, pushed: true);
    final router = GoRouter.of(tester.element(find.byType(ReleaseWorkbench)));
    final album = _watchedAlbum(tester);
    final gate = repo.renameEntityGate = Completer<void>();
    await rewriteAlbum(tester, 'Renamed Harbour');
    final raised = _raised(tester);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(ReleaseWorkbench), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(raised.map(shellMessageText), [
      AppLocalizationsEn().musicAlbumRewriteRenamed(2),
    ]);
    expect(album()?.title, 'Renamed Harbour');
  });

  testWidgets('a rename refused once the workbench was left says so where '
      'the visitor is', (tester) async {
    final repo = _repo();
    await _pump(tester, repo, pushed: true);
    final router = GoRouter.of(tester.element(find.byType(ReleaseWorkbench)));
    final gate = repo.renameEntityGate = Completer<void>();
    await rewriteAlbum(tester, 'Renamed Harbour');
    final raised = _raised(tester);

    router.pop();
    await tester.pumpAndSettle();
    const refusal = WaxDeckApiException(
      code: 'conflict',
      message: 'that name is reserved',
      statusCode: 409,
    );
    repo.metadataError = refusal;
    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(raised.map(shellMessageText), [
      explainRefusal(AppLocalizationsEn(), refusal),
    ]);
  });

  testWidgets('an album saved once the workbench was left says so where the '
      'visitor is, and the release is read again', (tester) async {
    final repo = _repo();
    await _pump(tester, repo, pushed: true);
    final router = GoRouter.of(tester.element(find.byType(ReleaseWorkbench)));
    final album = _watchedAlbum(tester);
    final gate = repo.editEntityGate = Completer<void>();
    final label = _byId(SemanticsIds.metadataField('label'));
    await tester.ensureVisible(label);
    await tester.pumpAndSettle();
    await tester.enterText(label, 'Harbour Lights Records');
    await tester.pumpAndSettle();
    final save = _byId(SemanticsIds.metadataSave);
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pump();
    final raised = _raised(tester);

    router.pop();
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repo.entityEdits.single.edits, {'label': 'Harbour Lights Records'});
    expect(raised.map(shellMessageText), ['Saved']);
    expect(album()?.label, 'Harbour Lights Records');
  });

  testWidgets('a bulk edit that lands once the workbench was left says so '
      'where the visitor is, and its door opens the release the tracks '
      'moved to', (tester) async {
    final repo = _merging();
    await _pump(tester, repo, pushed: true);
    final router = GoRouter.of(tester.element(find.byType(ReleaseWorkbench)));
    final container = _containerOf(tester);
    final listing = (
      dimension: MusicDimension.albums,
      segment: _album,
      domain: BrowseDomain.wholeLibrary,
    );
    container.listen(musicItemsProvider(listing), (_, _) {});
    final gate = repo.bulkEditGate = Completer<void>();
    await regroup(tester, repo, held: true);
    final raised = _raised(tester);

    router.pop();
    await tester.pumpAndSettle();
    repo.facetItems['album ${_album.substring(3)}'] = <ItemSummary>[
      testItem('tr-A', title: 'Fresh Name'),
    ];
    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(raised.map(shellMessageText), [
      'Edited 2 tracks\nThe edited tracks moved to a new album entry.',
    ]);
    expect(raised.single.actionLabel, 'Open it');
    expect(
      container
          .read(musicItemsProvider(listing))
          .value
          ?.items
          .map((item) => item.title),
      ['Fresh Name'],
    );

    raised.single.onAction!();
    await tester.pumpAndSettle();
    expect(_top(router), WaxRoute.metadata(_regrouped));
  });

  testWidgets("a member's save that lands once the workbench was left has the "
      "release's members read again", (tester) async {
    final repo = _repo()..editItemMetadataGate = Completer<void>();
    await _pump(tester, repo, pushed: true);
    final router = GoRouter.of(tester.element(find.byType(ReleaseWorkbench)));
    final container = _containerOf(tester);
    final listing = (
      dimension: MusicDimension.albums,
      segment: _album,
      domain: BrowseDomain.wholeLibrary,
    );
    container.listen(musicItemsProvider(listing), (_, _) {});
    await tester.tap(_trackRow('tr-A'));
    await tester.pumpAndSettle();
    await tester.enterText(
      _byId(SemanticsIds.metadataField('title')),
      'Fresh Name',
    );
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.metadataSave));
    await tester.pump();

    router.pop();
    await tester.pumpAndSettle();
    repo.facetItems['album ${_album.substring(3)}'] = <ItemSummary>[
      testItem('tr-A', title: 'Fresh Name'),
      testItem('tr-B', title: 'Nightjar'),
    ];
    repo.editItemMetadataGate!.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      container
          .read(musicItemsProvider(listing))
          .value
          ?.items
          .map((item) => item.title),
      ['Fresh Name', 'Nightjar'],
    );
  });

  /// The release attributed its cover to [from], as the album page draws
  /// it, and its front slot filled.
  FakeRepository coverFrom(String from) {
    final repo = _repo()
      ..artRoles.add(const ArtRoleInfo(role: 'front', format: 'jpeg'))
      ..entityArtworkGate = Completer<void>();
    repo.albums[_album] = AlbumDetail(
      pid: _album,
      title: 'Long Exposure',
      itemCount: 2,
      artSource: ArtSource(source: from),
    );
    return repo;
  }

  /// Back from the workbench to the album page while the cover write is
  /// held, the release then attributing its cover to [now] as the write
  /// lands.
  Future<void> leaveThenLand(
    WidgetTester tester,
    GoRouter router,
    FakeRepository repo,
    String now,
  ) async {
    // Frames rather than settling: the slot draws busy while it writes.
    await tester.pump(const Duration(milliseconds: 500));
    tester.element(find.byType(ReleaseWorkbench)).back();
    await tester.pumpAndSettle();
    expect(_top(router), _albumPage);
    final album = repo.albums[_album]!;
    repo.albums[_album] = AlbumDetail(
      pid: _album,
      title: album.title,
      itemCount: album.itemCount,
      artSource: ArtSource(source: now),
    );
    repo.entityArtworkGate!.complete();
    await tester.pumpAndSettle();
  }

  testWidgets('a cover set once the workbench was left has the album page '
      'say where its cover now comes from', (tester) async {
    final repo = coverFrom('tag');
    final router = await _openInApp(
      tester,
      repo,
      from: _albumPage,
      picker: _OneImage(),
    );
    final set = _byId(SemanticsIds.artSlotSet('front'));
    await tester.ensureVisible(set);
    await tester.pumpAndSettle();
    await tester.tap(set);
    await tester.pump();

    await leaveThenLand(tester, router, repo, 'user');

    expect(tester.takeException(), isNull);
    expect(repo.entityArtworkCalls.single.entityPid, _album);
    expect(find.text('Set by hand'), findsOneWidget);
    expect(find.text('Art from the file'), findsNothing);
  });

  testWidgets('a cover set in the workbench is evicted, and read again by '
      'the albums index under it', (tester) async {
    final repo = coverFrom('tag')..entityArtworkGate = null;
    final albums = WaxRoute.musicIndex(MusicDimension.albums);
    final router = await _openInApp(
      tester,
      repo,
      from: albums,
      picker: _OneImage(),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ReleaseWorkbench)),
      listen: false,
    );
    final store = container.read(artworkStoreProvider) as FakeArtworkStore;
    int indexReads() =>
        repo.facetReads.where((read) => read.dimension == 'album').length;
    final before = indexReads();
    final set = _byId(SemanticsIds.artSlotSet('front'));
    await tester.ensureVisible(set);
    await tester.pumpAndSettle();
    await tester.tap(set);
    await tester.pumpAndSettle();

    expect(repo.entityArtworkCalls.single.entityPid, _album);
    expect(store.evicted, [repo.artUrlFor(_album)]);
    expect(indexReads(), before, reason: 'a covered index reads nothing');

    tester.element(find.byType(ReleaseWorkbench)).back();
    await tester.pumpAndSettle();
    expect(_top(router), albums);
    expect(indexReads(), before + 1);
  });

  testWidgets('a cover cleared once the workbench was left has the album page '
      'say where its cover now comes from', (tester) async {
    final repo = coverFrom('user');
    final router = await _openInApp(tester, repo, from: _albumPage);
    final clear = _byId(SemanticsIds.artSlotClear('front'));
    await tester.ensureVisible(clear);
    await tester.pumpAndSettle();
    await tester.tap(clear);
    await tester.pumpAndSettle();
    await tester.enterText(_byId(SemanticsIds.confirmField), 'clear');
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.confirmAccept));
    await tester.pump();

    await leaveThenLand(tester, router, repo, 'tag');

    expect(tester.takeException(), isNull);
    expect(repo.clearEntityArtworkCalls.single.entityPid, _album);
    expect(find.text('Art from the file'), findsOneWidget);
    expect(find.text('Set by hand'), findsNothing);
  });

  testWidgets('keys act on the list, and never while a form field has '
      'focus', (tester) async {
    final repo = _repo();
    await _pump(tester, repo);

    // Cursor onto the first track, then space checks it: the selection
    // starts from the keyboard alone.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.workbenchBulkPane), findsOneWidget);

    // Escape leaves the selection.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.workbenchBulkPane), findsNothing);
    expect(_byId(SemanticsIds.albumEditor), findsOneWidget);

    // With a text field focused, the same keys are typing, not
    // commands: nothing may steal a space mid-word.
    await tester.tap(_byId(SemanticsIds.metadataField('sort')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.workbenchBulkPane), findsNothing);
  });

  testWidgets('compact is the list alone, and a track pushes its own '
      'editor', (tester) async {
    final repo = _repo();
    await _pump(tester, repo, size: const Size(500, 900));

    // No pane below the two-pane width: the list is the screen.
    expect(_byId(SemanticsIds.workbenchPane), findsNothing);
    expect(_byId(SemanticsIds.albumEditor), findsNothing);

    await tester.tap(_trackRow('tr-A'));
    await tester.pumpAndSettle();

    // The member's canonical location, through the real route table.
    expect(_byId(SemanticsIds.metadataEditor), findsOneWidget);
  });

  testWidgets('compact opens the album form as a sheet', (tester) async {
    final repo = _repo();
    await _pump(tester, repo, size: const Size(500, 900));

    await tester.tap(_byId(SemanticsIds.workbenchAlbumRow));
    await tester.pumpAndSettle();

    expect(_byId(SemanticsIds.albumEditor), findsOneWidget);
  });

  testWidgets('compact bulk bar opens the bulk form as a sheet', (
    tester,
  ) async {
    final repo = _repo();
    await _pump(tester, repo, size: const Size(500, 900));

    await tester.longPress(_trackRow('tr-A'));
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.workbenchBulkBar), findsOneWidget);

    await tester.tap(_byId(SemanticsIds.workbenchBulkEdit));
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.workbenchBulkPane), findsOneWidget);
  });

  testWidgets('a dirty pane asks before a selection change discards it', (
    tester,
  ) async {
    final repo = _repo();
    await _pump(tester, repo);

    await tester.tap(_trackRow('tr-A'));
    await tester.pumpAndSettle();
    await tester.enterText(
      _byId(SemanticsIds.metadataField('title')),
      'Half-typed rename',
    );
    await tester.pumpAndSettle();

    // Swapping to the album row would re-key the pane and drop the
    // draft, so the workbench asks first; Cancel keeps everything.
    await tester.tap(_byId(SemanticsIds.workbenchAlbumRow));
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.workbenchDiscardConfirm), findsOneWidget);
    expect(
      find.text('The edits you have not saved here will be lost.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Half-typed rename'), findsOneWidget);
    expect(_byId(SemanticsIds.albumEditor), findsNothing);

    // Confirming really discards and swaps.
    await tester.tap(_byId(SemanticsIds.workbenchAlbumRow));
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.workbenchDiscardConfirm));
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.albumEditor), findsOneWidget);

    // A clean pane swaps without asking.
    await tester.tap(_trackRow('tr-B'));
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.workbenchDiscardConfirm), findsNothing);
    expect(_byId(SemanticsIds.metadataField('title')), findsOneWidget);
  });

  testWidgets("a rematch message's door asks about the edits of the pane on "
      'screen, not of the pane that offered it', (tester) async {
    final repo = _repo();
    await _pump(tester, repo);
    final router = GoRouter.of(tester.element(find.byType(ReleaseWorkbench)));
    String location() => router.routerDelegate.currentConfiguration.uri.path;
    final at = location();

    // Rematched from tr-A's pane, whose message then outlives it.
    await tester.tap(_trackRow('tr-A'));
    await tester.pumpAndSettle();
    final rematch = _byId(SemanticsIds.metadataRematch);
    await tester.ensureVisible(rematch);
    await tester.pumpAndSettle();
    await tester.tap(rematch);
    await tester.pumpAndSettle();
    final open = raisedMessage(tester)!.onAction!;
    await tester.tap(_trackRow('tr-B'));
    await tester.pumpAndSettle();
    await tester.enterText(
      _byId(SemanticsIds.metadataField('title')),
      'Half-typed rename',
    );
    await tester.pumpAndSettle();

    // Frames rather than settling: a door gone at once opens the entry,
    // still being identified, whose spinner never stops.
    Future<void> frames() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    open();
    await frames();
    expect(location(), at);
    expect(_byId(SemanticsIds.workbenchDiscardConfirm), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(location(), at);
    expect(find.text('Half-typed rename'), findsOneWidget);

    open();
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.workbenchDiscardConfirm));
    await frames();
    expect(location(), WaxRoute.reviewEntry('re-FAKE0'));
  });

  testWidgets('clearing a mixed bulk field stages a wipe; untouched mixed '
      'fields stay out of the batch', (tester) async {
    final repo = _repo();
    await _pump(tester, repo);

    await tester.longPress(_trackRow('tr-A'));
    await tester.pumpAndSettle();
    await tester.tap(_trackRow('tr-B'));
    await tester.pumpAndSettle();

    // The year disagrees across the pair, so it opens empty; typing
    // and clearing it back to empty is the one gesture that means
    // "wipe it on every track", and it must survive the value compare.
    await tester.enterText(
      _byId(SemanticsIds.workbenchBulkField('year')),
      '1999',
    );
    await tester.pumpAndSettle();
    await tester.enterText(_byId(SemanticsIds.workbenchBulkField('year')), '');
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.workbenchBulkSave));
    await tester.pumpAndSettle();

    final call = repo.bulkEditCalls.single;
    expect(call.itemPids, ['tr-A', 'tr-B']);
    // The wiped year rides the batch; the equally mixed but untouched
    // title does not.
    expect(call.fields, {'year': ''});
  });

  testWidgets('a member saved in the pane refreshes the list beside it', (
    tester,
  ) async {
    final repo = _repo();
    await _pump(tester, repo);

    await tester.tap(_trackRow('tr-A'));
    await tester.pumpAndSettle();

    // What the next fetch will say; without the pane's save
    // invalidating the members, nothing ever asks for it.
    repo.facetItems['album ${_album.substring(3)}'] = <ItemSummary>[
      testItem('tr-A', title: 'Fresh Name'),
      testItem('tr-B', title: 'Nightjar'),
    ];
    await tester.enterText(
      _byId(SemanticsIds.metadataField('title')),
      'Fresh Name',
    );
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.metadataSave));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: _byId(SemanticsIds.workbenchList),
        matching: _byId(SemanticsIds.workbenchRow('tr-A')),
      ),
      findsOneWidget,
    );
    expect(find.text('Salt Harbour'), findsNothing);
  });

  /// The rows the members list draws by title, for a refresh assertion.
  Finder listed(String title) => find.descendant(
    of: _byId(SemanticsIds.workbenchList),
    matching: find.text(title),
  );

  /// What the next members read answers, so a list that never asks
  /// again keeps the old titles.
  void freshMembers(FakeRepository repo) =>
      repo.facetItems['album ${_album.substring(3)}'] = <ItemSummary>[
        testItem('tr-A', title: 'Fresh Name'),
        testItem('tr-B', title: 'Nightjar'),
      ];

  testWidgets('a bulk save refreshes the members list', (tester) async {
    final repo = _repo();
    await _pump(tester, repo);
    await tester.longPress(_trackRow('tr-A'));
    await tester.pumpAndSettle();
    await tester.tap(_trackRow('tr-B'));
    await tester.pumpAndSettle();

    freshMembers(repo);
    await tester.enterText(
      _byId(SemanticsIds.workbenchBulkField('artist')),
      'The Harbour Lights',
    );
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.workbenchBulkSave));
    await tester.pumpAndSettle();

    expect(listed('Fresh Name'), findsOneWidget);
    expect(listed('Salt Harbour'), findsNothing);
  });

  testWidgets('a rewrite refreshes the members list', (tester) async {
    final repo = _repo();
    await _pump(tester, repo);
    freshMembers(repo);
    await rewriteAlbum(tester, 'Renamed Harbour');

    expect(listed('Fresh Name'), findsOneWidget);
    expect(listed('Salt Harbour'), findsNothing);
  });

  group('a release merged away', () {
    final merged = WaxRoute.metadata(_album);
    final survivor = WaxRoute.metadata(_regrouped);
    final survivorPage = WaxRoute.musicBucket(
      MusicDimension.albums,
      _regrouped,
    );

    testWidgets('once a page was opened over the workbench, is reached by '
        "neither back nor forward in a browser tab: each shows the survivor's "
        'workbench on its entry', (tester) async {
      final repo = _merging();
      final browser = FakeBrowser();
      final router = await _openInApp(tester, repo, browser: browser);
      final gate = repo.renameEntityGate = Completer<void>();
      await rewriteAlbum(tester, 'Renamed Harbour');
      unawaited(router.push<void>(WaxRoute.settings));
      await tester.pumpAndSettle();
      gate.complete();
      await tester.pumpAndSettle();
      final arrived = _arrivedWith(router);
      final (at, entries) = (browser.index, browser.entries.length);

      tester.element(find.byType(WaxScaffold).last).back();
      await tester.pumpAndSettle();
      expect(_top(router), survivor);
      expect(browser.index, at - 1);
      expect(browser.pushes, [survivor], reason: 'written over its entry');
      tester.element(find.byType(WaxScaffold).last).back();
      await tester.pumpAndSettle();
      expect(_top(router), WaxRoute.music);
      expect(browser.index, at - 2);
      browser.goForward();
      await tester.pumpAndSettle();
      expect(_top(router), survivor);
      expect(browser.index, at - 1);
      browser.goForward();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(_top(router), WaxRoute.settings);
      expect(browser.index, at);
      expect(browser.entries, hasLength(entries), reason: 'none minted');
      expect(arrived, isNot(contains(merged)));
      expect(_anyPageOf(_album), isFalse);
      expect(browser.pushes, isNot(contains(merged)));
    });

    testWidgets("gone to by its link as the app's first entry, gives way to "
        'the survivor when browser back reaches it', (tester) async {
      final repo = _merging();
      // The tab opens on the link, which its first entry is.
      tester.platformDispatcher.defaultRouteNameTestValue = merged;
      final browser = FakeBrowser();
      final router = await _linkedInApp(tester, repo, browser: browser);
      final gate = repo.renameEntityGate = Completer<void>();
      await rewriteAlbum(tester, 'Renamed Harbour');
      router.go(WaxRoute.music);
      await tester.pumpAndSettle();
      gate.complete();
      await tester.pumpAndSettle();
      expect(_top(router), WaxRoute.music, reason: 'where the visitor went');
      final arrived = _arrivedWith(router);

      browser.goBack();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(arrived, isNot(contains(merged)));
      expect(_anyPageOf(_album), isFalse);
      expect(_top(router), survivor);
      expect(browser.index, 0);
      expect(browser.location, survivor, reason: 'written over its entry');
    });

    for (final native in <bool>[false, true]) {
      final how = native ? 'natively' : 'in a browser tab';

      testWidgets('on a workbench gone to by its link, once a page was opened '
          'over it, is not shown again by back $how', (tester) async {
        final repo = _merging();
        final router = await _linkedInApp(tester, repo, native: native);
        final gate = repo.renameEntityGate = Completer<void>();
        await rewriteAlbum(tester, 'Renamed Harbour');
        final raised = _raised(tester);
        unawaited(router.push<void>(WaxRoute.settings));
        await tester.pumpAndSettle();
        gate.complete();
        await tester.pumpAndSettle();
        expect(
          _top(router),
          WaxRoute.settings,
          reason: 'where the visitor went',
        );
        expect(
          shellMessageText(raised.single),
          AppLocalizationsEn().metadataMergedReady,
        );
        final arrived = _arrivedWith(router);

        tester.element(find.byType(WaxScaffold).last).back();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(arrived, isNot(contains(merged)));
        expect(_anyPageOf(_album), isFalse);
        // What the release went on as takes its place.
        expect(_top(router), survivor);
        expect(
          tester.widget<ReleaseWorkbench>(find.byType(ReleaseWorkbench)).pid,
          _regrouped,
        );
      });

      testWidgets('with a second visit opened before the answer, swaps the '
          'visit the visitor is on, and no visit keeps it $how', (
        tester,
      ) async {
        final repo = _merging();
        final router = await _openInApp(
          tester,
          repo,
          from: _albumPage,
          browser: native ? null : FakeBrowser(),
        );
        final gate = repo.renameEntityGate = Completer<void>();
        await rewriteAlbum(tester, 'Renamed Harbour');
        final raised = _raised(tester);
        tester.element(find.byType(ReleaseWorkbench)).back();
        await tester.pumpAndSettle();
        expect(_top(router), _albumPage);
        // The album's overflow again.
        unawaited(router.push<void>(merged));
        await tester.pumpAndSettle();

        gate.complete();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(_top(router), survivor);
        expect(
          tester.widget<ReleaseWorkbench>(find.byType(ReleaseWorkbench)).pid,
          _regrouped,
        );
        expect(raised.map(shellMessageText), [
          'Merged into the existing release.',
        ]);
        expect(raised.single.onAction, isNull);
        expect(_anyPageOf(_album), isFalse);
        final arrived = _arrivedWith(router);
        tester.element(find.byType(ReleaseWorkbench)).back();
        await tester.pumpAndSettle();
        expect(arrived, isNot(contains(merged)));
        expect(arrived, isNot(contains(_albumPage)));
        expect(_anyPageOf(_album), isFalse);
      });

      testWidgets('with the visitor back on its album page as it lands, puts '
          "the survivor's album page in its place $how", (tester) async {
        final repo = _merging();
        final router = await _openInApp(
          tester,
          repo,
          from: _albumPage,
          browser: native ? null : FakeBrowser(),
        );
        final gate = repo.renameEntityGate = Completer<void>();
        await rewriteAlbum(tester, 'Renamed Harbour');
        final raised = _raised(tester);
        tester.element(find.byType(ReleaseWorkbench)).back();
        await tester.pumpAndSettle();
        expect(_top(router), _albumPage);

        gate.complete();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          _top(router),
          WaxRoute.musicBucket(MusicDimension.albums, _regrouped),
        );
        expect(_anyPageOf(_album), isFalse);
        expect(raised.map(shellMessageText), [
          'Merged into the existing release.',
        ]);
        expect(raised.single.onAction, isNull);
      });

      testWidgets("puts the survivor's album page under the survivor it was "
          'swapped for, which back reaches $how', (tester) async {
        final repo = _merging();
        final router = await _openInApp(
          tester,
          repo,
          from: _albumPage,
          browser: native ? null : FakeBrowser(),
        );
        await rewriteAlbum(tester, 'Renamed Harbour');
        expect(_top(router), survivor);
        final arrived = _arrivedWith(router);

        tester.element(find.byType(ReleaseWorkbench)).back();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(arrived, isNot(contains(_albumPage)));
        expect(_anyPageOf(_album), isFalse);
        expect(_top(router), survivorPage);
        expect(
          tester.widget<AlbumScreen>(find.byType(AlbumScreen)).pid,
          _regrouped,
        );
      });

      testWidgets('once a page was opened over the workbench, puts the '
          "survivor's workbench and album page under that page, which back "
          'reaches in turn $how', (tester) async {
        final repo = _merging();
        final router = await _openInApp(
          tester,
          repo,
          from: _albumPage,
          browser: native ? null : FakeBrowser(),
        );
        final gate = repo.renameEntityGate = Completer<void>();
        await rewriteAlbum(tester, 'Renamed Harbour');
        unawaited(router.push<void>(WaxRoute.settings));
        await tester.pumpAndSettle();
        gate.complete();
        await tester.pumpAndSettle();
        expect(_top(router), WaxRoute.settings);
        expect(_anyPageOf(_album), isFalse);
        final arrived = _arrivedWith(router);

        tester.element(find.byType(WaxScaffold).last).back();
        await tester.pumpAndSettle();
        expect(_top(router), survivor);
        expect(
          tester.widget<ReleaseWorkbench>(find.byType(ReleaseWorkbench)).pid,
          _regrouped,
        );
        tester.element(find.byType(ReleaseWorkbench)).back();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(_top(router), survivorPage);
        expect(
          tester.widget<AlbumScreen>(find.byType(AlbumScreen)).pid,
          _regrouped,
        );
        expect(arrived, isNot(contains(merged)));
        expect(arrived, isNot(contains(_albumPage)));
        expect(_anyPageOf(_album), isFalse);
      });
    }
  });

  // A write that keeps the release can still dissolve its group: a retitle
  // onto a title the artist already has moves the album into that group,
  // and the group it left is gone. The answer names the pair with no
  // survivor of the release's own, and the group's page goes the way a
  // merged record's does.
  group('a release group the write folded', () {
    const goneGroup = 'rg-01JZX5N8QW3F4V9T2B7KDGONEG';
    const keptGroup = 'rg-01JZX5N8QW3F4V9T2B7KDKEPTG';
    final gonePage = WaxRoute.musicBucket(
      MusicDimension.releaseGroups,
      goneGroup,
    );
    final keptPage = WaxRoute.musicBucket(
      MusicDimension.releaseGroups,
      keptGroup,
    );
    const folded = [FoldedEntity(pid: goneGroup, into: keptGroup)];

    /// Both groups listed, the release under each.
    FakeRepository grouped(FakeRepository repo) {
      for (final group in [goneGroup, keptGroup]) {
        repo.facetItems['release-group ${group.substring(3)}'] = [
          testItem('tr-A', title: 'Salt Harbour'),
        ];
      }
      return repo;
    }

    bool anyPageOfGone() => find
        .byWidgetPredicate(
          (widget) =>
              widget is MusicListingScreen && widget.segment == goneGroup,
          skipOffstage: false,
        )
        .evaluate()
        .isNotEmpty;

    /// Back from the workbench, opened over the group's page, reaches the
    /// group it became; in a tab, on the entry the group's page had, and
    /// forward and back again walk the two entries with it.
    Future<void> backReachesTheKeptGroup(
      WidgetTester tester,
      GoRouter router,
      FakeBrowser? browser,
      List<String> arrived, {
      required String release,
    }) async {
      expect(tester.takeException(), isNull);
      expect(_top(router), WaxRoute.metadata(release));
      tester.element(find.byType(ReleaseWorkbench)).back();
      await tester.pumpAndSettle();
      expect(_top(router), keptPage);
      expect(anyPageOfGone(), isFalse);
      if (browser != null) {
        expect(browser.location, keptPage, reason: 'written over its entry');
        browser.goForward();
        await tester.pumpAndSettle();
        expect(_top(router), WaxRoute.metadata(release));
        browser.goBack();
        await tester.pumpAndSettle();
        expect(_top(router), keptPage);
      }
      expect(arrived, isNot(contains(gonePage)));
      expect(anyPageOfGone(), isFalse);
    }

    for (final (native, merged) in <(bool, bool)>[
      (false, false),
      (true, false),
      (false, true),
    ]) {
      final how =
          '${merged ? 'merging the release' : 'keeping the release'}, '
          '${native ? 'natively' : 'in a browser tab'}';
      final release = merged ? _regrouped : _album;

      testWidgets('by a rewrite: back reaches the group it became, $how', (
        tester,
      ) async {
        final repo = grouped(merged ? _merging() : _repo())
          ..renameEntityResult = EntityRenameResult(
            entityPid: _album,
            outcome: merged
                ? EntityRenameOutcome.merged
                : EntityRenameOutcome.renamed,
            members: 2,
            credits: 0,
            mergedInto: merged ? _regrouped : null,
            movedAlbums: merged ? const [] : const [_album],
            folded: folded,
          );
        final browser = native ? null : FakeBrowser();
        final router = await _openInApp(
          tester,
          repo,
          from: gonePage,
          browser: browser,
        );
        await rewriteAlbum(tester, 'Renamed Harbour');
        // From the answer on: what the walk lands on.
        final arrived = _arrivedWith(router);

        await backReachesTheKeptGroup(
          tester,
          router,
          browser,
          arrived,
          release: release,
        );
      });

      testWidgets('by an mbid cleared: back reaches the group it became, '
          '$how', (tester) async {
        final repo = grouped(merged ? _merging() : _repo())
          ..entityEditResult = MetadataEditResult(
            applied: true,
            mergedInto: merged ? _regrouped : null,
            movedAlbums: merged ? const [] : const [_album],
            folded: folded,
          );
        repo.albums[_album] = const AlbumDetail(
          pid: _album,
          title: 'Long Exposure',
          mbid: 'b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d',
          itemCount: 2,
        );
        final browser = native ? null : FakeBrowser();
        final router = await _openInApp(
          tester,
          repo,
          from: gonePage,
          browser: browser,
        );
        await clearMbid(tester);
        await tester.pumpAndSettle();
        final arrived = _arrivedWith(router);

        expect(repo.entityEdits.single.edits, {'mbid': ''});
        await backReachesTheKeptGroup(
          tester,
          router,
          browser,
          arrived,
          release: release,
        );
      });
    }
  });
}
