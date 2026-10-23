import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'player_host.dart';

const _showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW02';
const _episodePid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0002';

/// A server whose streaming engine is away when a skip map is first
/// asked for, and which has built the map by the next ask.
class _EngineBackLater extends FakeRepository {
  int skipMapReads = 0;

  @override
  Future<SkipMap> getSkipMap(String pid, {int? partIndex}) async {
    skipMapReads++;
    if (skipMapReads == 1) {
      throw const WaxDeckApiException(
        code: 'feature-unavailable',
        message: 'a skip map needs the streaming engine',
        statusCode: 503,
        params: {'feature': 'streaming-engine'},
      );
    }
    return super.getSkipMap(pid, partIndex: partIndex);
  }
}

void main() {
  testWidgets('a skip map the engine was away for is asked again, as a '
      'pending one is, and trims once it is built', (tester) async {
    final repo = _EngineBackLater()
      ..addSubscription(
        testShow(_showPid),
        settings: const SubscriptionSettings(trimSilence: true),
      )
      ..episodesByShow[_showPid] = [testEpisode(_episodePid, showPid: _showPid)]
      ..skipMaps[_episodePid] = const SkipMap(
        state: 'ready',
        spans: [SkipSpan(startMs: 5000, endMs: 15000)],
      );
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testEpisode(_episodePid, showPid: _showPid),
    );
    expect(repo.skipMapReads, 1);

    await tester.pump(const Duration(seconds: 30));
    expect(
      repo.skipMapReads,
      2,
      reason: 'the engine-away answer gets the retry a pending map gets',
    );

    for (var i = 0; i < 5; i++) {
      engine.advance(const Duration(seconds: 1));
      await tester.pump();
    }
    expect(engine.position, const Duration(seconds: 15));
    await harness.endPlayback(tester);
  });
}
