import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_player/waxdeck_player.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

/// The play arriving from an OS surface - a lock screen, a headset
/// button, a head unit, a Bluetooth remote - and where it has to land.
///
/// The engine restarts a finished item on its own, so a play that went
/// straight at it would sound right and leave the session's per-play
/// bookkeeping standing from the play before: the replay would be
/// reported finished before it started. Routing is the fix, and this is
/// what holds it in place.
void main() {
  Future<WaxDeckAudioHandler> handlerFor(
    FakeEngine engine, {
    Future<void> Function()? onPlay,
  }) async => WaxDeckAudioHandler(
    engine: engine,
    onPlayFromMediaId: (_) async {},
    onPlay: onPlay,
  );

  test('a play from an OS surface goes to the app, not the engine', () async {
    final engine = FakeEngine(mediaDuration: const Duration(seconds: 10));
    addTearDown(engine.dispose);
    await engine.load('/stream');
    var routed = 0;
    final handler = await handlerFor(engine, onPlay: () async => routed++);

    await handler.play();

    expect(routed, 1);
    expect(
      engine.playing,
      isFalse,
      reason: 'the engine is the app callback\'s to drive, not the handler\'s',
    );
  });

  test('a play falls through to the engine with nothing to route to', () async {
    final engine = FakeEngine(mediaDuration: const Duration(seconds: 10));
    addTearDown(engine.dispose);
    await engine.load('/stream');
    final handler = await handlerFor(engine);

    await handler.play();

    expect(engine.playing, isTrue);
  });

  test('pause stays the engine\'s, routed or not', () async {
    final engine = FakeEngine(mediaDuration: const Duration(seconds: 10));
    addTearDown(engine.dispose);
    await engine.load('/stream');
    final handler = await handlerFor(engine, onPlay: () async {});
    await engine.play();

    await handler.pause();

    expect(
      engine.playing,
      isFalse,
      reason: 'a pause is read off the engine transition, so it needs no seam',
    );
  });
}
