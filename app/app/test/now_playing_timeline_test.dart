import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/settings/client_prefs.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

/// The gapless-in-a-browser path: a queue minted as one stream, its
/// members crossed inside media that never stops, and every way that
/// arrangement can be interrupted.
///
/// The engine here is the same [FakeEngine] the ordinary suite drives,
/// which implements the timeline half of the port; what is under test is
/// the feeder and the controller around it, not a browser.
const _a = 'tr-01JZX5N8QW3F4V9T2B7KDTRACKA';
const _b = 'tr-01JZX5N8QW3F4V9T2B7KDTRACKB';
const _c = 'tr-01JZX5N8QW3F4V9T2B7KDTRACKC';
const _episode = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';

const _trackMs = 214000;

const _album = QueueSource(
  kind: QueueSourceKind.album,
  label: 'Kind of Blue',
  pid: 'al-1',
);

/// Records which renderings were handed back while the engine was
/// still on the stream they replaced, which is the one moment a release
/// can take a listener's slot away from the stream about to use it.
class _TimingRepository extends FakeRepository {
  _TimingRepository(this.engine, {required super.items});

  final FakeEngine engine;

  /// The pids released while the engine had not yet loaded anything
  /// other than that same rendering.
  final releasedWhileLoading = <String>[];

  @override
  Future<void> releaseQueueTimeline(String pid) {
    final playing = engine.loadedTimeline?.url;
    if (playing != null && playing == _urlOf(pid)) {
      releasedWhileLoading.add(pid);
    }
    return super.releaseQueueTimeline(pid);
  }

  /// The URL the fake minted for one pid, so a release can be matched
  /// against what the engine is actually playing.
  String? _urlOf(String pid) {
    final n = int.tryParse(pid.replaceFirst('tl-fake', ''));
    if (n == null) return null;
    return timelineCalls.length >= n
        ? '/media/hls/master.m3u8?tl=${timelineCalls[n - 1].pids.join('.')}'
              '&rk=${timelineCalls[n - 1].formats?.firstOrNull ?? 'aac'}'
              '&mt=test-token-$n'
        : null;
  }
}

({ProviderContainer container, _TimingRepository repo, FakeEngine engine})
_harness({List<ItemSummary>? items, bool gapless = true}) {
  final engine = FakeEngine(
    mediaDuration: const Duration(milliseconds: _trackMs),
  );
  final repo = _TimingRepository(
    engine,
    items: items ?? [testItem(_a), testItem(_b), testItem(_c)],
  );
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      audioEngineProvider.overrideWithValue(engine),
      webGaplessProvider.overrideWith(() => _Gapless(gapless)),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, repo: repo, engine: engine);
}

/// The switch, forced on without a settings store behind it.
class _Gapless extends WebGapless {
  _Gapless(this.on);

  final bool on;

  @override
  bool build() => on;
}

extension on ProviderContainer {
  NowPlayingController get playback => read(nowPlayingProvider.notifier);
  QueueController get queue => read(queueControllerProvider.notifier);
  QueueState get queueState => read(queueControllerProvider);
}

/// Runs the stream forward in steps small enough to count as listening,
/// letting the engine's events land between them.
Future<void> _play(FakeEngine engine, int ms, {int stepMs = 2000}) async {
  for (var played = 0; played < ms; played += stepMs) {
    engine.advance(Duration(milliseconds: stepMs));
    await pumpEventQueue();
  }
}

/// One member per pid at 48 kHz, carrying the rendering the server
/// chose - which is not always one the caller asked for.
QueueTimeline _mint(List<String> pids, {required String format, String? pid}) {
  const samples = _trackMs * 48000 ~/ 1000;
  var offset = 0;
  final members = <QueueTimelineMember>[];
  for (final pid in pids) {
    members.add(
      QueueTimelineMember(
        pid: pid,
        offsetSamples: offset,
        durationSamples: samples,
      ),
    );
    offset += samples;
  }
  return QueueTimeline(
    pid: pid,
    url: '/media/hls/master.m3u8?tl=${pids.join('.')}&mt=t',
    mimeType: 'application/vnd.apple.mpegurl',
    durationMs: offset * 1000 ~/ 48000,
    expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 30)),
    envelopeRate: 48000,
    format: format,
    members: members,
  );
}

void main() {
  test(
    'a music queue is minted once and started at its first member',
    () async {
      final h = _harness();
      h.container.playback.play([
        testItem(_a),
        testItem(_b),
        testItem(_c),
      ], source: _album);
      await pumpEventQueue();

      expect(h.repo.timelineCalls, hasLength(1));
      expect(h.repo.timelineCalls.single.pids, [_a, _b, _c]);
      // What the engine says it can decode rides the mint: a rendering it
      // cannot play is silence with nothing to explain it.
      expect(h.repo.timelineCalls.single.formats, h.engine.timelineFormats);
      expect(h.engine.loadedTimeline, isNotNull);
      expect(h.engine.currentMember, 0);
      expect(h.engine.playing, isTrue);
      expect(h.container.read(nowPlayingProvider).item?.pid, _a);
    },
  );

  test('a seam adopts the next member without minting again', () async {
    final h = _harness();
    h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
    await pumpEventQueue();
    final first = h.container.read(nowPlayingProvider).session;

    await _play(h.engine, _trackMs + 4000);

    expect(h.container.read(nowPlayingProvider).item?.pid, _b);
    expect(h.engine.currentMember, 1);
    expect(h.container.queueState.currentIndex, 1);
    expect(h.repo.timelineCalls, hasLength(1), reason: 'one mint, one stream');
    expect(
      h.container.read(nowPlayingProvider).session,
      isNot(same(first)),
      reason: 'the crossing is a new session over the same stream',
    );
    // The finished track is credited with its own duration, not with
    // wherever the stream stood when the session let go.
    final report = h.repo.reportedSessions.firstWhere((s) => s.pid == _a);
    expect(report.finished, isTrue);
    expect(h.repo.playPositions[_a], _trackMs);
  });

  test('a long queue crosses every seam on the one stream', () async {
    const d = 'tr-01JZX5N8QW3F4V9T2B7KDTRACKD';
    const e = 'tr-01JZX5N8QW3F4V9T2B7KDTRACKE';
    final items = [
      testItem(_a),
      testItem(_b),
      testItem(_c),
      testItem(d),
      testItem(e),
    ];
    final h = _harness(items: items);
    h.container.playback.play(items, source: _album);
    await pumpEventQueue();

    for (final expected in [_b, _c, d, e]) {
      await _play(h.engine, _trackMs + 4000);
      expect(h.container.read(nowPlayingProvider).item?.pid, expected);
    }

    expect(h.repo.timelineCalls.map((c) => c.pids.length).toList(), [
      5,
    ], reason: 'one mint covers the run; a mint a track is the bug');
  });

  test('a skip inside the stream seeks rather than reloading', () async {
    final h = _harness();
    h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
    await pumpEventQueue();
    final url = h.engine.loadedUrl;

    await h.container.playback.next();
    await pumpEventQueue();

    expect(h.container.read(nowPlayingProvider).item?.pid, _b);
    expect(h.engine.currentMember, 1);
    expect(h.engine.loadedUrl, url, reason: 'the same stream is still loaded');
    expect(h.repo.timelineCalls, hasLength(1));

    await h.container.playback.previous();
    await pumpEventQueue();
    expect(h.engine.currentMember, 0);
    expect(h.repo.timelineCalls, hasLength(1));
  });

  test(
    'a podcast in the queue ends the run and plays its own stream',
    () async {
      final h = _harness(
        items: [
          testItem(_a),
          testItem(_episode, mediaType: MediaType.podcast),
          testItem(_c),
        ],
      );
      h.container.playback.play([
        testItem(_a),
        testItem(_episode, mediaType: MediaType.podcast),
      ], source: _album);
      await pumpEventQueue();

      expect(h.repo.timelineCalls.single.pids, [_a], reason: 'the run stops');

      h.container.queue.jumpTo(1);
      await pumpEventQueue();

      expect(h.engine.loadedTimeline, isNull);
      expect(h.engine.loadedUrl, contains(_episode));
    },
  );

  test('a next item no timeline can hold is asked about once', () async {
    final h = _harness(
      items: [
        testItem(_a),
        testItem(_episode, mediaType: MediaType.podcast),
      ],
    );
    h.container.playback.play([
      testItem(_a),
      testItem(_episode, mediaType: MediaType.podcast),
    ], source: _album);
    await pumpEventQueue();
    expect(h.repo.timelineCalls, hasLength(1));

    // The rest of the track, with the arming rule running on every
    // position tick. A podcast will not become renderable, so asking
    // again would be a render a second - which is what this pins.
    await _play(h.engine, _trackMs ~/ 2, stepMs: 1000);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    await pumpEventQueue();

    expect(h.repo.timelineCalls, hasLength(1));
  });

  test('a server that renders no timelines is asked once', () async {
    final h = _harness();
    h.repo.timelineError = const WaxDeckApiException(
      code: 'feature-unavailable',
      message: 'queue timelines need the streaming engine',
      statusCode: 501,
    );
    h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
    await pumpEventQueue();

    expect(h.engine.loadedTimeline, isNull);
    expect(h.engine.loadedUrl, contains(_a));
    expect(
      h.container.read(webGaplessStatusProvider),
      'feature-unavailable',
      reason: 'the switch says why it is doing nothing',
    );

    h.container.queue.jumpTo(1);
    await pumpEventQueue();
    expect(
      h.repo.timelineCalls,
      hasLength(1),
      reason: 'the answer is about the server, not the queue',
    );
  });

  test('a timeline that is lost reloads where the listener stands', () async {
    final h = _harness();
    h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
    await pumpEventQueue();
    await _play(h.engine, 10000);
    final session = h.container.read(nowPlayingProvider).session;
    final at = h.engine.position;

    final was = h.engine.loadedTimeline!.url;

    h.engine.loseTimeline();
    await pumpEventQueue();

    expect(h.repo.timelineCalls, hasLength(2), reason: 're-minted');
    expect(h.engine.loadedTimeline, isNotNull);
    expect(
      h.engine.loadedTimeline!.url,
      isNot(was),
      reason: 'a re-mint is a different stream, so this is a real reload',
    );
    expect(h.engine.currentMember, 0);
    expect(h.engine.position, at);
    expect(
      h.engine.playing,
      isTrue,
      reason:
          'a listener who was listening is listening again; the '
          'engine silences itself as part of losing the stream, so the '
          'reload cannot read the answer back off it',
    );
    expect(
      h.container.read(nowPlayingProvider).session,
      same(session),
      reason: 'the same listen session carries across the reload',
    );
  });

  test(
    'a timeline lost with nothing to re-mint falls back to the item',
    () async {
      final h = _harness();
      h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
      await pumpEventQueue();
      await _play(h.engine, 10000);

      // The stream is gone whichever way the re-mint goes, so a mint the
      // server turns down has to leave the listener playing something.
      h.repo.timelineError = WaxDeckApiException(
        code: 'conflict',
        message: 'no',
        statusCode: 409,
      );
      h.engine.loseTimeline();
      await pumpEventQueue();

      expect(h.engine.loadedTimeline, isNull);
      expect(
        h.engine.loadedUrl,
        contains(_a),
        reason: 'the item the listener was on, played the ordinary way',
      );
      expect(h.engine.playing, isTrue);
    },
  );

  test('an engine that cannot play a timeline is never asked to', () async {
    final h = _harness();
    // A browser whose player library never arrived, or whose media
    // source decodes none of the formats. Answered before the mint,
    // because a mint is a render and a transcode slot.
    h.engine.timelinesReady = false;
    h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
    await pumpEventQueue();

    expect(h.repo.timelineCalls, isEmpty);
    expect(h.engine.loadedTimeline, isNull);
    expect(h.engine.loadedUrl, contains(_a));
    expect(
      h.container.read(webGaplessStatusProvider),
      'gapless-unsupported',
      reason: 'the switch says why it is doing nothing',
    );

    h.container.queue.jumpTo(1);
    await pumpEventQueue();
    expect(h.repo.timelineCalls, isEmpty, reason: 'asked once, not per track');
  });

  test(
    'a rendering this browser cannot decode is refused, not played',
    () async {
      final h = _harness();
      h.engine.timelineFormats = const <String>['flac'];
      // What the server actually rendered, which is what decides: with
      // none of the caller's formats producible it falls back to its own
      // ladder, and playing that is silence with nothing to explain it.
      h.repo.timelines = (pids) =>
          _mint(pids, format: 'aac', pid: 'tl-undecodable');
      h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
      await pumpEventQueue();

      expect(h.repo.timelineCalls, hasLength(1));
      expect(h.engine.loadedTimeline, isNull);
      expect(h.engine.loadedUrl, contains(_a));
      expect(h.container.read(webGaplessStatusProvider), 'gapless-format');
      // And handed straight back. The server minted it: a slot is taken
      // and a rendering is stashed listing this listener, for a stream
      // nothing here will ever fetch. What plays instead is a
      // progressive stream per track, each wanting a slot of its own, so
      // at a cap of one the next track is refused by the rendering
      // nobody is on.
      expect(h.repo.timelineReleases, hasLength(1));
    },
  );

  test(
    'a mint the transcode limit turned down is said, and then cleared',
    () async {
      final h = _harness();
      h.repo.timelineError = WaxDeckApiException(
        code: 'transcode-limited',
        message: 'busy',
        statusCode: 429,
      );
      h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
      await pumpEventQueue();

      expect(h.engine.loadedTimeline, isNull);
      expect(
        h.container.read(webGaplessStatusProvider),
        'transcode-limited',
        reason: 'a switch that is on and doing nothing has to explain itself',
      );

      // The cap is about how busy the server is, not about this queue, so
      // the next mint that lands has to take the notice down again.
      h.repo.timelineError = null;
      h.container.queue.jumpTo(1);
      await pumpEventQueue();

      expect(h.engine.loadedTimeline, isNotNull);
      expect(h.container.read(webGaplessStatusProvider), isNull);
    },
  );

  test('a member the stream will not reach next is never armed', () async {
    final h = _harness();
    h.container.playback.play([
      testItem(_a),
      testItem(_b),
      testItem(_c),
    ], source: _album);
    await pumpEventQueue();
    expect(h.repo.timelineCalls, hasLength(1));

    // The middle track leaves the queue. The stream still holds it as
    // member 1, so the seam ahead is the removed track's - and arming
    // the queue's next entry, which sits at member 2, would label that
    // crossing with a track the listener will not hear for minutes.
    h.container.queue.removeAt(1);
    await pumpEventQueue();

    await _play(h.engine, _trackMs + 4000);

    final now = h.container.read(nowPlayingProvider);
    expect(now.entry?.pid, _c);
    expect(
      h.engine.loadedTimeline!.members[h.engine.currentMember].pid,
      now.entry!.pid,
      reason: 'the member playing is the entry the deck names',
    );
  });

  test(
    'a refusal met on a fetch is published and nothing falls back',
    () async {
      final h = _harness();
      h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
      await pumpEventQueue();

      h.engine.refuseTimeline('transcode-limited');
      await pumpEventQueue();

      expect(h.container.read(webGaplessStatusProvider), 'transcode-limited');
      expect(h.repo.timelineCalls, hasLength(1), reason: 'no re-mint helps');
      expect(h.engine.playing, isFalse);
    },
  );

  test(
    'a tail append re-mints behind the stream and never reloads it',
    () async {
      final h = _harness();
      h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
      await pumpEventQueue();
      final first = h.engine.loadedTimeline!.url;

      // Appended mid-track. The stream playing is still the right audio
      // all the way to its end, and nothing was minted yet: what follows
      // this track is still a member of the timeline already loaded.
      h.container.queue.addToEnd([_c]);
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await pumpEventQueue();
      expect(
        h.engine.loadedTimeline!.url,
        first,
        reason: 'no mid-track reload',
      );
      expect(h.repo.timelineCalls, hasLength(1));

      // Crossing into the last member is where the append starts to
      // matter: what comes after it is not on this timeline, so a
      // replacement is minted from where the queue stands and waits.
      await _play(h.engine, _trackMs + 4000);
      expect(h.container.read(nowPlayingProvider).item?.pid, _b);
      expect(h.engine.loadedTimeline!.url, first);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await pumpEventQueue();
      expect(h.repo.timelineCalls, hasLength(2));
      expect(h.repo.timelineCalls.last.pids, [_b, _c]);
      expect(h.engine.loadedTimeline!.url, first, reason: 'still waiting');

      // And it takes over as this one runs out.
      final outgoing = h.container.playback.loadedTimelinePid;
      await _play(h.engine, _trackMs + 4000);
      expect(h.container.read(nowPlayingProvider).item?.pid, _c);
      expect(h.engine.loadedTimeline!.url, isNot(first));
      expect(h.repo.timelineCalls, hasLength(2));

      // The rendering nobody is on any more goes back at the swap. The
      // server counts a listener as listening until it hears otherwise,
      // so one dropped silently keeps their slot alive for the minute
      // the release exists to save - including past the stop, where the
      // release for the stream they were actually on would find this
      // one still inside the idle window.
      expect(h.repo.timelineReleases, [outgoing]);
      expect(h.container.playback.loadedTimelinePid, isNot(outgoing));
      // And it goes back after the replacement is loaded, not before.
      // A slot is per listener, and a release only reaches the gate
      // when none of this listener's renderings has been fetched inside
      // the idle minute - which a replacement minted a track ago is.
      // Letting go first puts the slot back before the new stream asks
      // for its first fragment, and on a full server that fetch is
      // refused with a code the player is told not to recover from.
      expect(
        h.repo.releasedWhileLoading,
        isEmpty,
        reason: 'a rendering was handed back before its replacement loaded',
      );
    },
  );

  test(
    'a queue still being measured plays the ordinary way meanwhile',
    () async {
      final h = _harness();
      h.repo.timelineError = const WaxDeckApiException(
        code: 'timeline-measuring',
        message: 'the server is still measuring this queue',
        statusCode: 202,
        params: {'job': 'jb-1'},
      );
      h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
      await pumpEventQueue();

      expect(
        h.engine.loadedTimeline,
        isNull,
        reason: 'this track plays plainly',
      );
      expect(h.engine.loadedUrl, contains(_a));

      // Re-requesting is the poll: once measurement finishes the same
      // request answers, and the timeline is swapped in at the seam.
      h.repo.timelineError = null;
      await Future<void>.delayed(const Duration(seconds: 4));
      await pumpEventQueue();
      expect(h.repo.timelineCalls.length, greaterThan(1));

      await _play(h.engine, _trackMs + 4000);
      expect(h.container.read(nowPlayingProvider).item?.pid, _b);
      expect(h.engine.loadedTimeline, isNotNull);
    },
  );

  test('the switch off leaves the ordinary per-item path alone', () async {
    final h = _harness(gapless: false);
    h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
    await pumpEventQueue();

    expect(h.repo.timelineCalls, isEmpty);
    expect(h.engine.loadedTimeline, isNull);
    expect(h.engine.loadedUrl, contains(_a));
  });

  test('a lap of repeat one does not leak the track after it', () async {
    final h = _harness();
    h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
    await pumpEventQueue();
    h.container.queue.setRepeat(QueueRepeat.one);
    await pumpEventQueue();

    // Past the seam, which is the whole point: a timeline holds the
    // next track too, so an item ending is a position passing a number
    // and the stream runs straight on into music the listener did not
    // ask for.
    await _play(h.engine, _trackMs + 4000);

    expect(
      h.engine.timelineSeeks,
      contains(0),
      reason: 'the stream is put back on the repeating member',
    );
    expect(h.container.queueState.currentIndex, 0);
    expect(h.engine.currentMember, 0);
    expect(
      h.container.read(nowPlayingProvider).entry?.pid,
      _a,
      reason: 'still the track on repeat',
    );
  });

  test('a paused restore loads the member without playing it', () async {
    final h = _harness();
    h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
    await pumpEventQueue();
    await h.container.playback.goingAway();

    final resumed = _harness();
    resumed.container.playback.restore(
      QueueState(
        entries: const [
          QueueEntry(queueId: 'q1', pid: _a),
          QueueEntry(queueId: 'q2', pid: _b),
        ],
        sourceOrder: const ['q1', 'q2'],
        currentIndex: 1,
        shuffled: false,
        repeat: QueueRepeat.off,
        source: _album,
        nextQueueId: 3,
      ),
    );
    await pumpEventQueue();

    expect(resumed.engine.loadedTimeline, isNotNull);
    // Minted from where the queue stands rather than from its head: the
    // run starts at the entry being played, so the restored entry is
    // this timeline's first member.
    expect(resumed.repo.timelineCalls.single.pids, [_b]);
    expect(resumed.engine.currentMember, 0);
    expect(resumed.engine.playing, isFalse);
  });

  test('stopping hands the rendering back', () async {
    final h = _harness();
    h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
    await pumpEventQueue();
    expect(h.container.playback.loadedTimelinePid, isNotNull);
    final held = h.container.playback.loadedTimelinePid;
    expect(h.repo.timelineReleases, isEmpty);

    await h.container.playback.goingAway();
    await pumpEventQueue();

    // The slot goes back at the stop rather than a minute later, and
    // once: a rendering released twice is a second request for nothing.
    expect(h.repo.timelineReleases, [held]);
    expect(h.container.playback.loadedTimelinePid, isNull);
  });

  test('a lost rendering is released only when the re-mint differs', () async {
    final h = _harness();
    h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
    await pumpEventQueue();
    final was = h.container.playback.loadedTimelinePid;

    h.engine.loseTimeline();
    await pumpEventQueue();

    expect(h.repo.timelineCalls, hasLength(2));
    expect(h.repo.timelineReleases, [was]);
    expect(h.container.playback.loadedTimelinePid, isNot(was));

    // A server that answers the same rendering back is not released:
    // that would hand back the slot the new stream is about to fetch on.
    final again = h.container.playback.loadedTimelinePid;
    h.repo.timelines = (pids) => _mint(pids, format: 'aac', pid: again);
    h.engine.loseTimeline();
    await pumpEventQueue();
    expect(h.repo.timelineReleases, [was]);
    expect(again, isNotNull);
  });
}
