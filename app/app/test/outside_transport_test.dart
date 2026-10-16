import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/connect/queue_gateway.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/player/sleep_timer.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck/src/shell/lifecycle_banners.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player/waxdeck_player.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

const _a = 'tr-01JZX5N8QW3F4V9T2B7KDTRACKA';
const _b = 'tr-01JZX5N8QW3F4V9T2B7KDTRACKB';
const _book = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';
const _station = 'rs-01JZX5N8QW3F4V9T2B7KDRADIO1';
const _trackMs = 214000;

const _album = QueueSource(
  kind: QueueSourceKind.album,
  label: 'Kind of Blue',
  pid: 'al-1',
);

const _offline = WaxDeckApiException(
  code: 'transport',
  message: 'network unreachable',
);

({ProviderContainer container, FakeRepository repo, FakeEngine engine})
_harness({List<ItemSummary>? items}) {
  final repo = FakeRepository(items: items ?? [testItem(_a), testItem(_b)]);
  final engine = FakeEngine(
    mediaDuration: const Duration(milliseconds: _trackMs),
  );
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      audioEngineProvider.overrideWithValue(engine),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, repo: repo, engine: engine);
}

extension on ProviderContainer {
  NowPlayingController get playback => read(nowPlayingProvider.notifier);
  QueueGateway get gateway => read(queueGatewayProvider);
}

Future<void> _settle() async {
  await pumpEventQueue();
  await pumpEventQueue();
}

/// The transport verbs raised outside a session's own controls - the lock
/// screen, a headset, the sleep countdown, a routed command - mean what
/// they say whatever playback is in the middle of: a start in flight, a
/// load of the session's own, a failed start waiting for the server.
void main() {
  group('a pause from outside', () {
    test('before the next track\'s session exists lands it paused', () async {
      final h = _harness();
      await h.container.playback.playPids([_a], source: _album);
      expect(h.engine.playing, isTrue);
      // An item named by pid alone resolves first, so the start stands
      // in its resolve with the outgoing session still the live one.
      final gate = Completer<void>();
      h.repo.getItemGate = gate;
      final starting = h.container.playback.playPids([_b], source: _album);
      await _settle();
      await h.container.gateway.pause();
      h.repo.getItemGate = null;
      gate.complete();
      await starting;
      await _settle();
      expect(h.engine.loadedUrl, contains(_b));
      expect(h.engine.playing, isFalse);
    });

    test('a seek from outside before the next track\'s session exists lands '
        'on that track', () async {
      final h = _harness();
      await h.container.playback.playPids([_a], source: _album);
      h.engine.advance(const Duration(seconds: 20));
      final gate = Completer<void>();
      h.repo.getItemGate = gate;
      final starting = h.container.playback.playPids([_b], source: _album);
      await _settle();
      final seeking = h.container.gateway.seek(const Duration(seconds: 75));
      await _settle();
      h.repo.getItemGate = null;
      gate.complete();
      await starting;
      expect(await seeking, isTrue);
      await _settle();
      expect(h.engine.loadedUrl, contains(_b));
      expect(h.engine.position, const Duration(seconds: 75));
      expect(
        h.repo.putPlayStateCalls.where(
          (c) => c.pid == _a && c.positionMs > 20000,
        ),
        isEmpty,
        reason: 'the outgoing track keeps its own place',
      );
    });

    test('while the next track loads lands it paused', () async {
      final h = _harness();
      await h.container.playback.playPids([_a], source: _album);
      final gate = Completer<void>();
      h.repo.playInfoGate = gate;
      final starting = h.container.playback.playPids([_b], source: _album);
      await _settle();
      await h.container.gateway.pause();
      h.repo.playInfoGate = null;
      gate.complete();
      await starting;
      await _settle();
      expect(h.engine.loadedUrl, contains(_b));
      expect(h.engine.playing, isFalse);
    });

    test('while a failed start waits for the server keeps it waiting for a '
        'press', () async {
      final h = _harness();
      final link = h.container.read(liveLinkProvider.notifier)
        ..report(connected: false);
      h.repo.playInfoError = _offline;
      await h.container.playback.playPids([_a], source: _album);
      await _settle();
      expect(h.container.read(nowPlayingProvider).error, isNotNull);

      // The sleep countdown runs out over the pane.
      await h.container.gateway.pause();
      h.repo.playInfoError = null;
      link.report(connected: true);
      await _settle();
      expect(h.engine.playing, isFalse);
      expect(h.container.read(nowPlayingProvider).session, isNull);
    });
  });

  test(
    'a queue emptied while a start resolves reads as nothing opening',
    () async {
      final h = _harness();
      final gate = Completer<void>();
      h.repo.getItemGate = gate;
      final starting = h.container.playback.playPids([_b], source: _album);
      await _settle();
      expect(h.container.playback.opening.value, isTrue);

      h.container.read(queueControllerProvider.notifier).clear();
      await _settle();
      expect(h.container.playback.opening.value, isFalse);
      expect(h.container.playback.meansToPlay, isFalse);
      expect(await h.container.gateway.play(), isFalse);

      h.repo.getItemGate = null;
      gate.complete();
      await starting;
    },
  );

  test('a track that fails while it plays says it could not go on, not '
      'that it could not start', () async {
    final h = _harness();
    await h.container.playback.playPids([_a], source: _album);
    h.engine.advance(const Duration(seconds: 10));
    h.engine.failPlayback(
      refusal: const StreamRefusal(status: 429, code: 'transcode-limited'),
    );
    await _settle();
    expect(h.container.read(nowPlayingProvider).error, isNotNull);
    expect(
      shellMessageText(h.container.read(shellMessengerProvider)),
      "Couldn't keep playing Prancing Pony Blues",
    );
  });

  test('a station tuned while a failed start waits keeps the engine when '
      'the server comes back', () async {
    final h = _harness();
    final station = RadioStation(
      pid: _station,
      name: 'Coastal FM',
      streamUrl: 'https://stream.example/coastal',
      createdAt: DateTime.utc(2026, 7, 1),
    );
    h.repo.radioStationsByPid[_station] = station;
    final link = h.container.read(liveLinkProvider.notifier)
      ..report(connected: false);
    h.repo.playInfoError = _offline;
    await h.container.playback.playPids([_a], source: _album);
    await _settle();
    expect(h.container.read(nowPlayingProvider).error, isNotNull);

    await h.container.read(radioPlaybackProvider.notifier).play(station);
    h.repo.playInfoError = null;
    link.report(connected: true);
    await _settle();
    expect(h.container.read(radioPlaybackProvider).station?.pid, _station);
    expect(h.engine.loadedUrl, isNot(contains(_a)));
    expect(h.engine.playing, isTrue);
  });

  test('a stop from outside while a reload loads is not undone', () async {
    final h = _harness();
    await h.container.playback.playPids([_a], source: _album);
    h.engine.advance(const Duration(seconds: 10));
    final gate = Completer<void>();
    h.engine.loadGate = gate;
    // A dropped connection: recovered by a fresh mint and a reload where
    // the listener stood, meaning to play.
    h.engine.failPlayback();
    await _settle();
    await h.container.gateway.stop();
    gate.complete();
    await _settle();
    expect(h.engine.playing, isFalse);
    expect(h.repo.playInfoCalls, hasLength(2), reason: 'no mint after it');
  });

  test('the resume when the server comes back keeps an end-of-chapter stop '
      'armed on the same book', () async {
    final h = _harness(
      items: const [
        ItemSummary(
          pid: _book,
          mediaType: MediaType.audiobook,
          title: 'There And Back Again',
          durationMs: 1200000,
        ),
      ],
    );
    h.repo.books[_book] = testBook(_book, durationMs: 1200000, partCount: 2);
    h.engine.mediaDuration = const Duration(minutes: 10);
    await h.container.playback.playPids(
      [_book],
      source: _album,
      positionMs: 60000,
    );
    await _settle();
    h.container
        .read(sleepTimerProvider.notifier)
        .startEndOfChapter(300000, pid: _book);
    final link = h.container.read(liveLinkProvider.notifier);

    link.report(connected: false);
    h.repo.playInfoError = _offline;
    h.engine.failPlayback();
    await _settle();
    expect(h.container.read(nowPlayingProvider).error, isNotNull);

    h.repo.playInfoError = null;
    link.report(connected: true);
    await _settle();
    expect(h.engine.playing, isTrue);
    expect(h.container.read(sleepTimerProvider).endOfChapterEndMs, 300000);

    h.engine.advance(const Duration(minutes: 5));
    await _settle();
    expect(h.engine.playing, isFalse, reason: 'it stopped at the chapter');
  });

  test('a play on an end a sleep stop held, with nothing queued after it, '
      'plays the item again', () async {
    final h = _harness(
      items: const [
        ItemSummary(
          pid: _book,
          mediaType: MediaType.audiobook,
          title: 'There And Back Again',
          durationMs: 120000,
        ),
      ],
    );
    h.repo.books[_book] = testBook(_book, durationMs: 120000, partCount: 2);
    h.engine.mediaDuration = const Duration(minutes: 1);
    await h.container.playback.playPids(
      [_book],
      source: _album,
      positionMs: 100000,
    );
    await _settle();
    h.container
        .read(sleepTimerProvider.notifier)
        .startEndOfChapter(120000, pid: _book);
    h.engine.advance(const Duration(seconds: 21));
    await _settle();
    expect(h.engine.playing, isFalse);

    h.container.playback.togglePlayback();
    await _settle();
    expect(h.engine.playing, isTrue);
    expect(h.repo.playInfoCalls.last.positionMs, 0);
  });

  test(
    'a reload in the last half minute prepares the next track again',
    () async {
      final h = _harness();
      await h.container.playback.playPids([_a, _b], source: _album);
      h.engine.advance(const Duration(milliseconds: 190000));
      await _settle();
      expect(h.engine.preloadedUrl, contains(_b));

      h.engine.failPlayback();
      await _settle();
      expect(
        h.engine.loadedUrls.where((url) => url.contains(_a)),
        hasLength(2),
      );
      expect(h.engine.preloadedUrl, contains(_b));
    },
  );
}
