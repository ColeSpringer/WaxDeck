import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/play_progress.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

/// Watches the progress of [items] the way a listing screen does, and hands
/// the view to [onView] each time it builds.
class _Probe extends ConsumerWidget {
  const _Probe({required this.items, required this.onView});

  final List<ItemSummary> items;
  final void Function(PlayProgressView view) onView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    onView(watchPlayProgress(ref, items));
    return const SizedBox.shrink();
  }
}

void main() {
  testWidgets('120 rows are read in windows of 50, 50 and 20, and the view '
      'answers for each', (tester) async {
    final repo = FakeRepository();
    final items = <ItemSummary>[
      for (var i = 0; i < 120; i++)
        testItem('tr-${i.toString().padLeft(3, '0')}'),
    ];
    repo.playPositions['tr-115'] = 90000;
    late PlayProgressView view;

    await pumpApp(
      tester,
      _Probe(items: items, onView: (v) => view = v),
      container: appContainer(repo: repo),
      routed: false,
    );

    expect(repo.playStateBatches.map((batch) => batch.length), <int>[
      50,
      50,
      20,
    ]);
    expect(view['tr-115'].positionMs, 90000);
    expect(view['tr-115'].inProgress, isTrue);
    // A row the read did not cover reads as not started, never as missing.
    expect(view['tr-999'], same(PlayProgress.none));
  });
}
