import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_player/waxdeck_player.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

/// The handler drives every OS media surface - the Android notification
/// and Auto, MediaSession in the browser, MPRIS, the Windows transport
/// controls - because all of them are
/// implementations of the one interface it speaks. Its state is what
/// each of them draws, so what it publishes is worth pinning.
///
/// Built directly rather than through `initWaxDeckAudioService`, which
/// registers with the platform: what is under test is the handler, not
/// the registration.
///
/// The controls are asserted by their labels rather than by naming
/// audio_service's own action constants, so this package keeps the
/// wrapping rule too: the handler stays the one file that touches those
/// types.
void main() {
  late FakeEngine engine;
  late WaxDeckAudioHandler handler;
  late List<String> played;
  late List<int> jumped;

  setUp(() {
    engine = FakeEngine();
    played = <String>[];
    jumped = <int>[];
    handler = WaxDeckAudioHandler(
      engine: engine,
      onPlayFromMediaId: (pid) async => played.add(pid),
      onSkipNext: () async {},
      onSkipPrevious: () async {},
      onSkipToQueueItem: (index) async => jumped.add(index),
    );
  });

  MediaSessionItem item(
    String id, {
    String title = 'Track',
    bool live = false,
  }) => MediaSessionItem(
    id: id,
    title: title,
    artist: 'Artist',
    album: 'Album',
    duration: live ? null : const Duration(minutes: 3),
    artUri: live ? null : Uri.parse('file:///covers/$id'),
    live: live,
  );

  test('what is playing reaches the OS as a media item', () {
    handler.publish(item('tr-1'));

    final published = handler.mediaItem.value!;
    expect(published.id, 'tr-1');
    expect(published.title, 'Track');
    expect(published.artist, 'Artist');
    expect(published.album, 'Album');
    expect(published.duration, const Duration(minutes: 3));
    expect(published.artUri, Uri.parse('file:///covers/tr-1'));
    expect(published.isLive, isFalse);
  });

  test('nothing playing clears the metadata rather than leaving it', () {
    handler.publish(item('tr-1'));
    handler.publish(null);
    expect(handler.mediaItem.value, isNull);
  });

  test('a queue is published with the row that is playing', () async {
    handler.publishQueue(<MediaSessionItem>[
      item('tr-1'),
      item('tr-2', title: 'Second'),
    ], index: 1);

    expect(handler.queue.value.map((m) => m.id), <String>['tr-1', 'tr-2']);
    expect(handler.playbackState.value.queueIndex, 1);

    // A row chosen on a head unit steps the app's queue by index: the
    // same item queued twice is ordinary, and an id would step to the
    // wrong one of the pair.
    await handler.skipToQueueItem(1);
    expect(jumped, <int>[1]);
  });

  test('an empty queue has no row playing', () {
    handler.publishQueue(const <MediaSessionItem>[]);
    expect(handler.queue.value, isEmpty);
    expect(handler.playbackState.value.queueIndex, isNull);
  });

  test('an item offers the whole transport', () {
    handler.publish(item('tr-1'));

    final state = handler.playbackState.value;
    expect(state.controls.map((c) => c.label), <String>[
      'Previous',
      'Rewind',
      'Play',
      'Fast Forward',
      'Next',
      'Stop',
    ]);
    expect(state.systemActions.map((a) => a.name), contains('seek'));
  });

  test('a station offers only the verb it has', () {
    handler.publish(item('rs-1', title: 'Fixture FM', live: true));

    final state = handler.playbackState.value;
    // No seek, no skip, no jumps: a station has no position to move and
    // nothing to step to, and four dead buttons on a steering wheel read
    // as an app that has broken. What is left is the one verb it has.
    expect(state.controls.map((c) => c.label), <String>['Play', 'Stop']);
    expect(state.systemActions.map((a) => a.name), isNot(contains('seek')));
    expect(handler.mediaItem.value!.isLive, isTrue);
  });

  test('an item after a station gets its transport back', () {
    handler.publish(item('rs-1', live: true));
    handler.publish(item('tr-1'));

    final state = handler.playbackState.value;
    expect(state.systemActions.map((a) => a.name), contains('seek'));
    expect(state.controls.map((c) => c.label), contains('Next'));
  });

  test('a browse leaf plays through the app rather than the engine', () async {
    await handler.playFromMediaId('tr-9');
    expect(played, <String>['tr-9']);
    expect(engine.loadedUrl, isNull);
  });

  test('the browse tree is empty where the build has no mirror', () async {
    expect(await handler.getChildren(browseRootId), isEmpty);
  });

  test('a swiped-away task finalizes, and is not a stop', () async {
    // Android keeps the foreground service alive after the app leaves
    // recents, which is what makes a queue survive an app switch - and
    // what left music playing out of a window somebody had thrown
    // away. Routed to the app's finalize rather than to its stop, and
    // the difference is the whole point: a stop is defined as the verb
    // that silences playback and leaves the checkpoint, the listen
    // report and the session Connect is advertising exactly where they
    // stood.
    var stopped = 0;
    var finalized = 0;
    // Its own engine, not the shared one: a handler subscribes to four
    // of the engine's streams in its constructor and has nothing that
    // unsubscribes, so a second one over `engine` would publish state
    // beside the setUp handler for the rest of the file.
    final ownEngine = FakeEngine();
    final routed = WaxDeckAudioHandler(
      engine: ownEngine,
      onPlayFromMediaId: (_) async {},
      onStop: () async => stopped++,
      onGoingAway: () async => finalized++,
    );
    // Loaded first, so the engine's state is one it could have left
    // rather than the one it was born in.
    await ownEngine.load('https://example.test/a.flac');

    await routed.onTaskRemoved();

    expect(finalized, 1);
    expect(stopped, 0, reason: 'a departure is not a stop');
    // And the sound goes with it: the service outlives the task, so
    // finalizing without silencing would leave music playing out of an
    // app that is gone.
    expect(ownEngine.processingState, EngineProcessingState.idle);
  });

  test('a task removed with no app behind it still stops the sound', () async {
    // The fallback the whole handler is written around: a build with no
    // session layer has nobody to route to, and silence is still the
    // right answer.
    await engine.load('https://example.test/a.flac');
    await handler.onTaskRemoved();
    expect(engine.processingState, EngineProcessingState.idle);
  });
}
