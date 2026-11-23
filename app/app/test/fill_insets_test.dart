import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/metadata/metadata_screen.dart';
import 'package:waxdeck/src/metadata/release_workbench.dart';
import 'package:waxdeck/src/review/review_entry_screen.dart';
import 'package:waxdeck/src/review/review_screen.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';
import 'row_finders.dart';

/// A page given a `WaxScaffold.fill` takes none of the window's side or
/// bottom insets itself: each part of the fill takes those of the edges it
/// stands against. Every page with a fill is drawn here under insets on
/// every side, in each of its shapes, and nothing it draws may sit in one.
void main() {
  test('every page with a fill is drawn here', () {
    expect(_pagesWithAFill(), _scenes.keys.toSet());
  });

  const insets = FakeViewPadding(top: 24, left: 44, right: 30, bottom: 34);
  for (final MapEntry(key: file, value: scenes) in _scenes.entries) {
    for (final scene in scenes) {
      testWidgets('$file, ${scene.name}: nothing it draws sits in an inset', (
        tester,
      ) async {
        tester.view
          ..physicalSize = scene.size
          ..devicePixelRatio = 1
          ..padding = insets
          ..viewPadding = insets;
        addTearDown(tester.view.reset);
        await scene.pump(tester);
        await tester.pumpAndSettle();

        final inside = Rect.fromLTRB(
          insets.left,
          insets.top,
          scene.size.width - insets.right,
          scene.size.height - insets.bottom,
        ).inflate(0.5);
        final drawn = _drawn(
          tester.renderObject(find.byType(WaxScaffold).first),
        );
        expect(drawn, isNotEmpty, reason: 'the page drew nothing to check');
        expect(
          [
            for (final (what, rect) in drawn)
              if (!_contains(inside, rect)) '$what at $rect',
          ],
          isEmpty,
          reason: 'inside $inside',
        );
      });
    }
  }
}

typedef _Scene = ({
  String name,
  Size size,
  Future<void> Function(WidgetTester tester) pump,
});

/// Each page with a fill, by its file under `lib/`, in each shape it
/// takes.
final Map<String, List<_Scene>> _scenes = {
  'lib/src/review/review_entry_screen.dart': [
    (
      name: 'the entry over its decision bar',
      size: const Size(1000, 900),
      pump: (tester) => mountApp(
        tester,
        const ReviewEntryScreen(entryId: 'rv-1'),
        container: appContainer(repo: _review()),
        routed: false,
      ),
    ),
  ],
  'lib/src/metadata/metadata_screen.dart': [
    (
      name: 'the editor over its save bar',
      size: const Size(800, 900),
      pump: (tester) => mountApp(
        tester,
        const MetadataScreen(pid: 'tr-A'),
        container: appContainer(repo: _release()),
        routed: false,
      ),
    ),
  ],
  'lib/src/metadata/release_workbench.dart': [
    (name: 'the list alone', size: const Size(600, 900), pump: _workbench),
    (
      name: 'the list alone, over its bulk bar',
      size: const Size(600, 900),
      pump: (tester) async {
        await _workbench(tester);
        await tester.longPress(_member('tr-A'));
      },
    ),
    (
      name: 'the list and the album',
      size: const Size(1200, 900),
      pump: _workbench,
    ),
    (
      name: 'the list and a track',
      size: const Size(1200, 900),
      pump: (tester) async {
        await _workbench(tester);
        await tester.tap(_member('tr-A'));
      },
    ),
    (
      name: 'the list and checked tracks',
      size: const Size(1200, 900),
      pump: (tester) async {
        await _workbench(tester);
        await tester.longPress(_member('tr-A'));
        await tester.pumpAndSettle();
        await tester.tap(_member('tr-B'));
      },
    ),
  ],
  'lib/src/review/review_screen.dart': [
    (
      name: 'the queue alone',
      size: const Size(700, 900),
      pump: (tester) => _queue(tester, const ReviewScreen()),
    ),
    (
      name: 'the queue alone, over its bulk bar',
      size: const Size(700, 900),
      pump: (tester) async {
        await _queue(tester, const ReviewScreen());
        await tester.longPress(_entry('rv-1'));
      },
    ),
    (
      name: 'the queue and an entry',
      size: const Size(1200, 900),
      pump: (tester) =>
          _queue(tester, const ReviewSurface(openEntryId: 'rv-1')),
    ),
    (
      name: 'the queue and an entry, over the bulk bar',
      size: const Size(1200, 900),
      pump: (tester) async {
        await _queue(tester, const ReviewSurface(openEntryId: 'rv-1'));
        await tester.longPress(_entry('rv-2'));
      },
    ),
  ],
};

/// The files under `lib/` that build a `WaxScaffold` with a `fill:`.
Set<String> _pagesWithAFill() {
  final found = <String>{};
  for (final file in Directory('lib').listSync(recursive: true)) {
    if (file is! File || !file.path.endsWith('.dart')) continue;
    final unit = parseString(
      content: file.readAsStringSync(),
      path: file.absolute.path,
      throwIfDiagnostics: false,
    ).unit;
    final finder = _FillFinder();
    unit.accept(finder);
    if (finder.found) found.add(file.path.replaceAll(r'\', '/'));
  }
  return found;
}

class _FillFinder extends RecursiveAstVisitor<void> {
  var found = false;

  bool _fills(String name, ArgumentList arguments) =>
      name == 'WaxScaffold' &&
      arguments.arguments.whereType<NamedArgument>().any(
        (argument) => argument.name.lexeme == 'fill',
      );

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null &&
        _fills(node.methodName.name, node.argumentList)) {
      found = true;
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (_fills(node.constructorName.type.toSource(), node.argumentList)) {
      found = true;
    }
    super.visitInstanceCreationExpression(node);
  }
}

/// Whether [rect] lies within [inside].
bool _contains(Rect inside, Rect rect) =>
    rect.left >= inside.left &&
    rect.top >= inside.top &&
    rect.right <= inside.right &&
    rect.bottom <= inside.bottom;

/// What [root] draws that is content rather than a surface - text, a
/// field's text, an image - each as the part of it that can show once its
/// ancestors' clips are applied. Nothing hidden counts.
List<(String, Rect)> _drawn(RenderObject root) {
  final drawn = <(String, Rect)>[];
  void visit(RenderObject node) {
    if (node is RenderOffstage && node.offstage) return;
    if (node is RenderOpacity && node.opacity == 0) return;
    if (node is RenderAnimatedOpacity && node.opacity.value == 0) return;
    final what = switch (node) {
      RenderParagraph() => switch (node.text.toPlainText()) {
        // An icon's glyph, which has no name of its own to print.
        final text when text.runes.every((r) => r >= 0xE000 && r <= 0xF8FF) =>
          'a glyph',
        final text => '"$text"',
      },
      RenderEditable() => 'the field "${node.text?.toPlainText()}"',
      RenderImage() => 'an image',
      _ => null,
    };
    if (what != null && node is RenderBox) {
      if (_shown(node) case final shown?) drawn.add((what, shown));
    }
    node.visitChildren(visit);
  }

  visit(root);
  return drawn;
}

/// [box] in the window, cut by every clip above it; null where nothing of
/// it shows.
Rect? _shown(RenderBox box) {
  if (!box.hasSize || box.size.isEmpty) return null;
  var rect = MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
  RenderObject child = box;
  for (var parent = box.parent; parent != null; parent = parent.parent) {
    if (parent.describeApproximatePaintClip(child) case final clip?) {
      rect = rect.intersect(
        MatrixUtils.transformRect(parent.getTransformTo(null), clip),
      );
      if (rect.width <= 0 || rect.height <= 0) return null;
    }
    child = parent;
  }
  return rect;
}

const _admin = SessionState(
  authenticated: true,
  user: WaxDeckUser(id: 'us-1', username: 'admin', roles: <String>['admin']),
);

const _album = 'al-01JZX5N8QW3F4V9T2B7KDALBUM';

/// A release of two tracks with their tags, read by an administrator.
FakeRepository _release() {
  final repo = FakeRepository(
    sessionState: _admin,
    items: [
      testItem('tr-A', title: 'Salt Harbour'),
      testItem('tr-B', title: 'Nightjar'),
    ],
  );
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

Future<void> _workbench(WidgetTester tester) async {
  await mountApp(
    tester,
    const ReleaseWorkbench(pid: _album),
    container: appContainer(repo: _release()),
  );
  await tester.pumpAndSettle();
}

Finder _member(String pid) => rowWithIdentifier(SemanticsIds.workbenchRow(pid));

/// Two pending entries, the first one with candidates and a diff to read.
FakeRepository _review() {
  final repo = FakeRepository();
  repo.reviewEntries = [
    testReviewEntry('rv-1'),
    testReviewEntry('rv-2', title: 'Second Album'),
  ];
  repo.reviewEntryDetails['rv-1'] = ReviewEntryDetail(
    id: 'rv-1',
    kind: 'match',
    status: 'pending',
    mediaType: MediaType.music,
    origin: 'upload',
    title: 'Neon Meridian',
    artist: 'The Cardinal Waves',
    trackCount: 1,
    createdAt: DateTime.utc(2026, 7, 1),
    candidates: const [
      ReviewCandidate(
        mbid: 'mb-1',
        title: 'Neon Meridian',
        artist: 'The Cardinal Waves',
        year: 2011,
        similarityPct: 94,
        pairings: [
          CandidatePairing(
            trackIndex: 0,
            position: 1,
            title: 'Opening Tide',
            artist: 'The Cardinal Waves',
            distance: 0.05,
          ),
        ],
      ),
    ],
    tracks: const [
      ReviewTrack(
        pid: 'tr-1',
        path: '/music/a.flac',
        title: 'opening tide (untagged)',
        trackNo: 1,
        durationMs: 200000,
      ),
    ],
  );
  return repo;
}

Future<void> _queue(WidgetTester tester, Widget screen) async {
  await mountApp(
    tester,
    screen,
    container: appContainer(repo: _review()),
    routed: false,
  );
  await tester.pumpAndSettle();
}

Finder _entry(String id) =>
    find.bySemanticsIdentifier(SemanticsIds.reviewRow(id));
