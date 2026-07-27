import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_box.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/artwork/artwork_store.dart';

const _art = 'https://deck.local/api/v1/items/tr-1/art';

Widget _host(_RecordingStore store, Widget child) => ProviderScope(
  overrides: [artworkStoreProvider.overrideWithValue(store)],
  child: MaterialApp(
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('a box asks for the pixels it turned out to be', (tester) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final store = _RecordingStore();
    await tester.pumpWidget(
      _host(
        store,
        const SizedBox(
          width: 48,
          height: 48,
          child: ArtworkBox(
            artUrl: _art,
            placeholder: ColoredBox(color: Color(0xFF000000)),
          ),
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
    await tester.pumpWidget(
      _host(
        store,
        const SizedBox(
          width: 120,
          height: 180,
          child: ArtworkBox(
            artUrl: _art,
            placeholder: ColoredBox(color: Color(0xFF000000)),
          ),
        ),
      ),
    );
    expect(store.asked, <int>[180]);
  });

  testWidgets('no artwork draws the placeholder and asks for nothing', (
    tester,
  ) async {
    final store = _RecordingStore();
    await tester.pumpWidget(
      _host(
        store,
        const SizedBox(
          width: 48,
          height: 48,
          child: ArtworkBox(artUrl: null, placeholder: Text('no cover')),
        ),
      ),
    );
    expect(find.text('no cover'), findsOneWidget);
    expect(store.asked, isEmpty);
  });
}

/// A store that records the sizes it was asked for and draws nothing.
class _RecordingStore extends ArtworkStore {
  final List<int> asked = <int>[];

  @override
  String get baseUrl => '';

  @override
  ImageProvider? imageFor(String? artUrl, int px) {
    asked.add(px);
    return null;
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
  Future<void> evict(String artUrl) async {}

  @override
  Future<void> forgetEverything() async {}

  @override
  void dispose() {}
}
