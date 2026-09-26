import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auto/media_session_init.dart';
import 'package:waxdeck/src/l10n/off_tree.dart';
import 'package:waxdeck_player/waxdeck_player.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

/// The transport verbs arriving from an OS surface - a lock screen, a
/// headset button, a head unit, a Bluetooth remote - and where they have
/// to land.
///
/// The engine restarts a finished item on its own, so a play that went
/// straight at it would sound right and leave the session's per-play
/// bookkeeping standing from the play before: the replay would be
/// reported finished before it started. Routing is the fix, and this is
/// what holds it in place.
///
/// Stop has the mirror problem, and pause deliberately does not: a
/// pause is a gap the session reads off the engine's own transition,
/// while a stop is an end, and live radio keeps a tuned station in
/// state beside the engine that nothing else lets go of.
void main() {
  Future<WaxDeckAudioHandler> handlerFor(
    FakeEngine engine, {
    Future<void> Function()? onPlay,
    Future<void> Function()? onStop,
  }) async => WaxDeckAudioHandler(
    engine: engine,
    onPlayFromMediaId: (_) async {},
    onPlay: onPlay,
    onStop: onStop,
    controlLabels: _english,
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

  test('a pause stays the engine, routed or not', () async {
    final engine = FakeEngine(mediaDuration: const Duration(seconds: 10));
    addTearDown(engine.dispose);
    await engine.load('/stream');
    final handler = await handlerFor(
      engine,
      onPlay: () async {},
      onStop: () async {},
    );
    await engine.play();

    await handler.pause();

    expect(
      engine.playing,
      isFalse,
      reason:
          'a pause is a gap the session reads off the engine itself, so it '
          'needs no seam even when a stop has one',
    );
  });

  test('a stop from an OS surface goes to the app when one is wired', () async {
    final engine = FakeEngine(mediaDuration: const Duration(seconds: 10));
    addTearDown(engine.dispose);
    await engine.load('/stream');
    var routed = 0;
    final handler = await handlerFor(engine, onStop: () async => routed++);
    await engine.play();

    await handler.stop();

    expect(routed, 1);
    expect(engine.playing, isTrue);
  });

  test('a stop falls through to the engine with nothing to route to', () async {
    final engine = FakeEngine(mediaDuration: const Duration(seconds: 10));
    addTearDown(engine.dispose);
    await engine.load('/stream');
    final handler = await handlerFor(engine);
    await engine.play();

    await handler.stop();

    expect(engine.playing, isFalse);
  });
  test('a control relabelled in another language is redrawn', () async {
    final engine = FakeEngine(mediaDuration: const Duration(seconds: 10));
    addTearDown(engine.dispose);
    final handler = await handlerFor(engine);
    MediaSessionExtra extend(String label) =>
        MediaSessionExtra(action: 'extend', label: label, onPressed: () {});

    handler
      ..showExtra(extend('Extend 10 min'))
      ..showExtra(extend('Ampliar 10 min'));

    expect(handler.playbackState.value.controls.last.label, 'Ampliar 10 min');
  });
  test('the transport buttons speak the app language', () async {
    final engine = FakeEngine(mediaDuration: const Duration(seconds: 10));
    addTearDown(engine.dispose);
    final handler = await handlerFor(engine);
    List<String> labels() => [
      for (final control in handler.playbackState.value.controls) control.label,
    ];
    handler.publish(const MediaSessionItem(id: 'tr-1', title: 'One'));
    expect(labels(), ['Back 10 seconds', 'Play', 'Forward 30 seconds', 'Stop']);

    handler.controlLabels = const MediaControlLabels(
      play: 'Reproducir',
      pause: 'Pausar',
      stop: 'Detener',
      previous: 'Anterior',
      next: 'Siguiente',
      back: 'Atrás 10 segundos',
      forward: 'Adelante 30 segundos',
    );

    expect(labels(), [
      'Atrás 10 segundos',
      'Reproducir',
      'Adelante 30 segundos',
      'Detener',
    ]);
  });
  test('the app words the buttons from its own copy', () {
    final labels = mediaControlLabels(l10nFor(const [Locale('es')]));

    expect(labels.pause, 'Pausar');
    expect(labels.back, 'Atrás 10 segundos');
  });
}

const _english = MediaControlLabels(
  play: 'Play',
  pause: 'Pause',
  stop: 'Stop',
  previous: 'Previous',
  next: 'Next',
  back: 'Back 10 seconds',
  forward: 'Forward 30 seconds',
);
