import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/playback_session.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

const _showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const _episodePid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';

/// A start used to be three round trips before the engine was handed a
/// URL: show config, then play state, then play-info. On a
/// not-yet-fetched episode - where the server still has a redirect
/// chain to walk once play-info answers - that was the difference a
/// listener felt as a slow first play.
void main() {
  test('the three start reads go out together', () async {
    final repo = FakeRepository()
      ..addSubscription(testShow(_showPid))
      ..episodesByShow[_showPid] = [testEpisode(_episodePid)];
    final session = PlaybackSession(
      repository: repo,
      engine: FakeEngine(),
      item: testEpisode(_episodePid),
      clientId: 'test',
    );
    addTearDown(session.dispose);

    // The show config held open. Anything that waited on it has not
    // been asked for yet.
    final gate = Completer<void>();
    repo.podcastGate = gate;
    final started = session.start();
    await pumpEventQueue();

    expect(repo.getPodcastCalls, [_showPid]);
    expect(
      repo.playInfoCalls,
      hasLength(1),
      reason: 'play-info waited on the show config',
    );
    expect(repo.playStateReads, [
      _episodePid,
    ], reason: 'the play state waited on the show config');

    gate.complete();
    await started;
  });

  test('the read that fails first does not decide what start does', () async {
    // A server mid-restart answers 503 to one read and 404 to the
    // other, and the offline fallback branches on the status code it is
    // handed: 503 plays the downloaded copy, anything else rethrows.
    // Left to whichever socket landed first, the same start would
    // behave differently run to run. Play state is the one whose
    // failure decides, which is the order the serialized version had.
    final repo = FakeRepository()
      ..addSubscription(testShow(_showPid))
      ..episodesByShow[_showPid] = [testEpisode(_episodePid)]
      ..getPlayStateError = const WaxDeckApiException(
        code: 'unavailable',
        message: 'restarting',
        statusCode: 503,
      )
      ..playInfoError = const WaxDeckApiException(
        code: 'not-found',
        message: 'gone',
        statusCode: 404,
      );
    final session = PlaybackSession(
      repository: repo,
      engine: FakeEngine(),
      item: testEpisode(_episodePid),
      clientId: 'test',
    );
    addTearDown(session.dispose);

    // No downloads port, so the 503 falls through to a rethrow - what
    // matters is which of the two failures got there.
    await expectLater(
      session.start(),
      throwsA(
        isA<WaxDeckApiException>().having((e) => e.statusCode, 'status', 503),
      ),
    );
  });

  test('a start with a given position reads no play state', () async {
    // The overlap must not have turned a read the old path skipped
    // into one that always goes out.
    final repo = FakeRepository()
      ..addSubscription(testShow(_showPid))
      ..episodesByShow[_showPid] = [testEpisode(_episodePid)];
    final session = PlaybackSession(
      repository: repo,
      engine: FakeEngine(),
      item: testEpisode(_episodePid),
      clientId: 'test',
      initialPositionMs: 5000,
    );
    addTearDown(session.dispose);

    await session.start();
    expect(repo.playStateReads, isEmpty);
  });
}
