import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/playback_session.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

const _episodePid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';
const _showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const _bookPid = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';
const _trackPid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';

/// Voice boost is applied by the server as it mints the stream, so what a
/// mint says of it is what the listener hears: the listener's own choice
/// this session as `voiceBoost`, and this device's default, for spoken
/// word, as `voiceBoostDefault`, which the server takes where nothing is
/// stored for the show or book.
void main() {
  late FakeRepository repo;
  late FakeEngine engine;

  setUp(() {
    repo = FakeRepository(items: [testItem(_trackPid)])
      ..books[_bookPid] = testBook(_bookPid)
      ..addSubscription(testShow(_showPid))
      ..episodesByShow[_showPid] = [testEpisode(_episodePid)];
    engine = FakeEngine(mediaDuration: const Duration(milliseconds: 214000));
  });

  Future<PlaybackSession> started(
    ItemSummary item, {
    bool defaultVoiceBoost = false,
  }) async {
    final session = PlaybackSession(
      repository: repo,
      engine: engine,
      item: item,
      clientId: 'test',
      initialPositionMs: 0,
      defaultVoiceBoost: defaultVoiceBoost,
    );
    addTearDown(session.dispose);
    await session.start();
    return session;
  }

  const asked = (voiceBoost: null, voiceBoostDefault: true);
  const unasked = (voiceBoost: null, voiceBoostDefault: null);

  test('an episode with the device default on and nothing stored asks the '
      'server for it', () async {
    final session = await started(
      testEpisode(_episodePid),
      defaultVoiceBoost: true,
    );

    expect(session.voiceBoost.value, isTrue);
    expect(repo.playInfoBoosts, [asked]);
  });

  test('a book with the device default on asks the server for it', () async {
    await started(
      testItem(_bookPid, mediaType: MediaType.audiobook),
      defaultVoiceBoost: true,
    );

    expect(repo.playInfoBoosts, [asked]);
  });

  test(
    'with the device default off a mint says nothing of the boost',
    () async {
      await started(testEpisode(_episodePid));

      expect(repo.playInfoBoosts, [unasked]);
    },
  );

  test('music never sends the device default', () async {
    final session = await started(testItem(_trackPid), defaultVoiceBoost: true);

    expect(session.voiceBoost.value, isFalse);
    expect(repo.playInfoBoosts, [unasked]);
  });

  test('a boost the listener chose reopens with it', () async {
    final session = await started(testEpisode(_episodePid));

    expect(await session.setVoiceBoost(true), isTrue);
    await pumpEventQueue();

    expect(repo.playInfoBoosts, [
      unasked,
      (voiceBoost: true, voiceBoostDefault: null),
    ]);
  });

  test('a choice of off is sent over the device default', () async {
    final session = await started(
      testEpisode(_episodePid),
      defaultVoiceBoost: true,
    );

    expect(await session.setVoiceBoost(false), isTrue);
    await pumpEventQueue();

    expect(repo.playInfoBoosts, [
      asked,
      (voiceBoost: false, voiceBoostDefault: true),
    ]);
  });

  test('a toggle on an item that keeps no settings reopens with it', () async {
    // Reached by pid alone, an episode carries no show to store against.
    final session = await started(
      testItem(_episodePid, mediaType: MediaType.podcast),
    );

    expect(await session.setVoiceBoost(true), isTrue);
    await pumpEventQueue();

    expect(repo.putSubscriptionSettingsCalls, isEmpty);
    expect(repo.playInfoBoosts, [
      unasked,
      (voiceBoost: true, voiceBoostDefault: null),
    ]);
    expect(engine.loadedUrls, hasLength(2));
  });
}
