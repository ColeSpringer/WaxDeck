import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/playback_session.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

void main() {
  test(
    'a disposing session does not stop the engine a newer one owns',
    () async {
      final repo = FakeRepository(items: [testItem('tr-a'), testItem('tr-b')]);
      final engine = FakeEngine(mediaDuration: const Duration(seconds: 30));

      final sessionA = PlaybackSession(
        repository: repo,
        engine: engine,
        item: testItem('tr-a'),
        clientId: 'test',
      );
      await sessionA.start();
      engine.advance(const Duration(seconds: 2));
      engine.advance(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);

      // Route handoff: A's teardown is fire-and-forget while B starts on
      // the same shared engine.
      final disposing = sessionA.dispose();
      final sessionB = PlaybackSession(
        repository: repo,
        engine: engine,
        item: testItem('tr-b'),
        clientId: 'test',
      );
      await sessionB.start();
      await disposing;

      expect(
        engine.playing,
        isTrue,
        reason: "A's teardown stopped B's playback",
      );
      expect(engine.loadedUrl, contains('tr-b'));

      // A's final checkpoint recorded A's own position, snapshotted before
      // B replaced the media.
      final aCheckpoints = repo.putPlayStateCalls
          .where((c) => c.pid == 'tr-a')
          .toList();
      expect(aCheckpoints.last.positionMs, 4000);

      // B still owns the engine, so B's teardown does stop it.
      await sessionB.dispose();
      expect(engine.playing, isFalse);
    },
  );
}
