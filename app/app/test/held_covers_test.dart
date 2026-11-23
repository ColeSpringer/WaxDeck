import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/downloads/downloads_controller.dart';
import 'package:waxdeck/src/downloads/held_covers.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import 'app_host.dart';
import 'fakes.dart';

/// Counts the reads of what the device holds: one per build of the
/// Downloads list.
class _CountedDownloads extends FakeDownloads {
  int reads = 0;

  @override
  Future<List<DownloadedItem>> stored() {
    reads++;
    return super.stored();
  }
}

/// Hands the test what the native store calls as each cover is pinned.
class _LandsWhenTold extends FakeArtworkStore {
  void Function(String pid)? landed;

  @override
  void pinHeld(Map<String, String> held, {void Function(String pid)? landed}) =>
      this.landed = landed;
}

/// Long enough for a list told to rebuild to have done it.
const _turn = Duration(milliseconds: 1);

void main() {
  late _CountedDownloads downloads;
  late _LandsWhenTold store;
  late List<String> pids;

  /// A container with the Downloads list on screen and the store handed
  /// what is held; answers how many times the list had been built by then.
  Future<int> reached(WidgetTester tester) async {
    final container = appContainer(downloads: downloads, artwork: store);
    final shown = container.listen(downloadsProvider, (_, _) {});
    addTearDown(shown.close);
    await tester.pump();
    await pinHeldCovers(container);
    await tester.pump();
    expect(store.landed, isNotNull);
    return downloads.reads;
  }

  setUp(() {
    pids = <String>[
      for (var i = 0; i < 500; i++) 'tr-01JZX5N8QW3F4V9T2B7KD${1000 + i}',
    ];
    downloads = _CountedDownloads()
      ..setStored(<DownloadedItem>[
        for (final pid in pids)
          DownloadedItem(pid: pid, sizeBytes: 1024, files: 1, complete: true),
      ]);
    store = _LandsWhenTold();
  });

  tearDown(() => downloads.dispose());

  testWidgets('a run of covers landing rebuilds the Downloads list a few '
      'times, not once each, and not only when it ends', (tester) async {
    final before = await reached(tester);

    var midway = 0;
    for (final (i, pid) in pids.indexed) {
      store.landed!(pid);
      await tester.pump(const Duration(milliseconds: 10));
      if (i == pids.length ~/ 2) midway = downloads.reads - before;
    }
    await tester.pump(const Duration(minutes: 1));

    expect(downloads.reads - before, lessThan(8));
    expect(midway, greaterThan(1), reason: 'covers show as the run goes');
  });

  testWidgets('one cover landing rebuilds it at once, and once', (
    tester,
  ) async {
    final before = await reached(tester);

    store.landed!(pids.first);
    await tester.pump(_turn);
    expect(downloads.reads - before, 1);

    await tester.pump(const Duration(minutes: 1));
    expect(downloads.reads - before, 1);
  });

  testWidgets('covers landing after a run has paused are shown at once '
      'again', (tester) async {
    final before = await reached(tester);
    for (final pid in pids.take(20)) {
      store.landed!(pid);
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pump(const Duration(minutes: 1));
    final after = downloads.reads - before;

    store.landed!(pids.last);
    await tester.pump(_turn);
    expect(downloads.reads - before, after + 1);
    await tester.pump(const Duration(minutes: 1));
  });
}
