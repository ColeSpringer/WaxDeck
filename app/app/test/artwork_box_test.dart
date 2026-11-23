import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_box.dart';
import 'package:waxdeck/src/artwork/artwork_store.dart';
import 'package:waxdeck_data/waxdeck_data.dart' show OwedPin;
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';

const _art = 'https://deck.local/api/v1/items/tr-1/art';
const _other = 'https://deck.local/api/v1/items/tr-2/art';

Future<void> _mount(WidgetTester tester, _RecordingStore store, Widget child) =>
    mountApp(
      tester,
      Scaffold(body: Center(child: child)),
      container: appContainer(artwork: store),
      routed: false,
    );

void main() {
  testWidgets('a box asks for the pixels it turned out to be', (tester) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final store = _RecordingStore();
    await _mount(
      tester,
      store,
      const SizedBox(
        width: 48,
        height: 48,
        child: ArtworkBox(
          artUrl: _art,
          placeholder: ColoredBox(color: Color(0xFF000000)),
        ),
      ),
    );
    expect(store.asked, <int>[96]);
  });

  testWidgets('a taller box asks for its longest edge', (tester) async {
    // The old screens put artwork in an Expanded, where the height is
    // what the layout decided and the width is the column's.
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = _RecordingStore();
    await _mount(
      tester,
      store,
      const SizedBox(
        width: 120,
        height: 180,
        child: ArtworkBox(
          artUrl: _art,
          placeholder: ColoredBox(color: Color(0xFF000000)),
        ),
      ),
    );
    expect(store.asked, <int>[180]);
  });

  testWidgets('no artwork draws the placeholder and asks for nothing', (
    tester,
  ) async {
    final store = _RecordingStore();
    await _mount(
      tester,
      store,
      const SizedBox(
        width: 48,
        height: 48,
        child: ArtworkBox(artUrl: null, placeholder: Text('no cover')),
      ),
    );
    expect(find.text('no cover'), findsOneWidget);
    expect(store.asked, isEmpty);
  });

  group('a box handed its cover again', () {
    // The slot stays and what it is handed changes, as a row's does.
    // Its second half only makes the slot build again.
    final shown = ValueNotifier<(String, int)>((_art, 0));
    Future<void> mount(WidgetTester tester, _RecordingStore store) {
      shown.value = (_art, 0);
      return _mount(
        tester,
        store,
        ValueListenableBuilder<(String, int)>(
          valueListenable: shown,
          builder: (context, slot, _) => SizedBox(
            width: 48,
            height: 48,
            child: ArtworkBox(
              artUrl: slot.$1,
              placeholder: const Text('no cover'),
            ),
          ),
        ),
      );
    }

    int? drawn(WidgetTester tester) =>
        tester.widget<RawImage>(find.byType(RawImage)).image?.width;

    testWidgets('under another name keeps its picture until the new one is '
        'ready', (tester) async {
      final old = (await tester.runAsync(
        () => createTestImage(width: 4, height: 4),
      ))!;
      final fresh = (await tester.runAsync(
        () => createTestImage(width: 8, height: 8),
      ))!;
      final store = _RecordingStore();
      final first = store.images[_art] = _TestCover();
      await mount(tester, store);
      first.land(old);
      await tester.pump();
      await tester.pump();
      expect(drawn(tester), 4);

      // What a replacement does: the same URL, another provider.
      final second = store.images[_art] = _TestCover();
      shown.value = (_art, 1);
      await tester.pump();
      expect(drawn(tester), 4);
      await tester.pump(const Duration(milliseconds: 100));
      expect(drawn(tester), 4);

      second.land(fresh);
      await tester.pump();
      await tester.pump();
      expect(drawn(tester), 8);
    });

    testWidgets('for another cover never shows the picture before it', (
      tester,
    ) async {
      final old = (await tester.runAsync(
        () => createTestImage(width: 4, height: 4),
      ))!;
      final store = _RecordingStore();
      final first = store.images[_art] = _TestCover();
      store.images[_other] = _TestCover();
      await mount(tester, store);
      first.land(old);
      await tester.pump();
      await tester.pump();
      expect(drawn(tester), 4);

      shown.value = (_other, 0);
      await tester.pump();
      expect(drawn(tester), isNull);
    });
  });

  group('a cover on screen follows its store', () {
    // Each of the two widgets that draw a cover, drawing [artUrl].
    final kinds = <String, Widget Function(_RecordingStore, String)>{
      'a design-system cover': (store, artUrl) =>
          ArtworkImage(size: 48, artwork: store.source(artUrl)),
      'a box': (store, artUrl) => SizedBox(
        width: 48,
        height: 48,
        child: ArtworkBox(artUrl: artUrl, placeholder: const Text('none')),
      ),
    };

    int asksFor(_RecordingStore store, String artUrl) =>
        store.askedFor.where((asked) => asked == artUrl).length;

    for (final MapEntry(key: kind, value: cover) in kinds.entries) {
      testWidgets('$kind whose URL is evicted asks again, with no rebuild of '
          'what holds it and its picture kept meanwhile', (tester) async {
        final old = (await tester.runAsync(
          () => createTestImage(width: 4, height: 4),
        ))!;
        final fresh = (await tester.runAsync(
          () => createTestImage(width: 8, height: 8),
        ))!;
        final store = _RecordingStore();
        store.images[_art] = _TestCover()..land(old);
        final builds = <int>[];
        await _mount(
          tester,
          store,
          _Held(builds: builds, child: () => cover(store, _art)),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(tester.widget<RawImage>(find.byType(RawImage)).image?.width, 4);
        final asks = asksFor(store, _art);
        final built = builds.length;

        final next = store.images[_art] = _TestCover();
        await store.evict(_art);
        await tester.pump();
        expect(asksFor(store, _art), asks + 1);
        expect(builds, hasLength(built));
        expect(tester.widget<RawImage>(find.byType(RawImage)).image?.width, 4);

        next.land(fresh);
        await tester.pump();
        await tester.pump();
        expect(tester.widget<RawImage>(find.byType(RawImage)).image?.width, 8);
      });

      testWidgets('$kind is not touched by the eviction of another URL', (
        tester,
      ) async {
        final store = _RecordingStore();
        await _mount(tester, store, cover(store, _art));
        final asks = asksFor(store, _art);

        await store.evict(_other);
        await tester.pump();
        expect(asksFor(store, _art), asks);
      });

      testWidgets('$kind that left the screen is not listened to any more', (
        tester,
      ) async {
        final store = _RecordingStore();
        await _mount(tester, store, cover(store, _art));
        expect(store.listening, 1);

        await _mount(tester, store, const SizedBox());
        expect(store.listening, 0);
        final asks = store.askedFor.length;
        await store.evict(_art);
        await store.evictAll();
        await tester.pump();
        expect(store.askedFor, hasLength(asks));
      });
    }

    testWidgets('every cover on screen asks again, once, when covers changed '
        'and nothing says which', (tester) async {
      final store = _RecordingStore();
      await _mount(
        tester,
        store,
        Column(
          children: <Widget>[
            kinds['a design-system cover']!(store, _art),
            kinds['a box']!(store, _art),
            kinds['a design-system cover']!(store, _other),
            kinds['a box']!(store, _other),
          ],
        ),
      );
      expect((asksFor(store, _art), asksFor(store, _other)), (2, 2));

      await store.evictAll();
      await tester.pump();
      expect((asksFor(store, _art), asksFor(store, _other)), (4, 4));
      await tester.pump(const Duration(seconds: 1));
      expect(store.askedFor, hasLength(8));
    });
  });
}

/// Counts how often what holds a cover was built.
class _Held extends StatelessWidget {
  const _Held({required this.builds, required this.child});

  final List<int> builds;
  final Widget Function() child;

  @override
  Widget build(BuildContext context) {
    builds.add(builds.length);
    return child();
  }
}

/// A cover whose picture lands when the test says.
class _TestCover extends ImageProvider<_TestCover> {
  final Completer<ImageInfo> _landing = Completer<ImageInfo>();

  void land(ui.Image image) => _landing.complete(ImageInfo(image: image));

  @override
  Future<_TestCover> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_TestCover>(this);

  @override
  ImageStreamCompleter loadImage(_TestCover key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(key._landing.future);
}

/// A store that records the sizes it was asked for and draws nothing.
class _RecordingStore extends ArtworkStore {
  final List<int> asked = <int>[];

  @override
  String get baseUrl => '';

  /// What each URL draws; nothing for the rest.
  final Map<String, ImageProvider> images = <String, ImageProvider>{};

  /// The URL of each ask, in order.
  final List<String?> askedFor = <String?>[];

  @override
  ImageProvider? imageFor(String? artUrl, int px) {
    asked.add(px);
    askedFor.add(artUrl);
    return images[artUrl];
  }

  @override
  Future<Uint8List?> bytesFor(String artUrl, int px) async => null;

  @override
  Future<void> warm(String artUrl, int px) async {}

  @override
  Future<void> pinForOffline(String pid, String? artUrl) async {}

  @override
  Future<void> unpin(String pid) async {}

  @override
  Future<void> unpinExact(String pid, List<OwedPin> owed) async {}

  @override
  Future<void> evict(String artUrl) async => noteReplaced(artUrl);

  @override
  Future<void> evictAll() async => noteAllReplaced();

  @override
  void oweEvictAll() {}

  @override
  Future<void> forgetEverything() async {}

  @override
  void dispose() {}
}
