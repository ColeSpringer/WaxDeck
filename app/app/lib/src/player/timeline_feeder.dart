import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

import '../queue/queue_state.dart';
import 'playback_session.dart';

/// How many members one mint covers. The server takes 500, but a
/// timeline is immutable and every edit past its end costs another
/// mint, so a long queue is rendered in runs: one reload every fifty
/// tracks against a render the server has to hold for the whole queue's
/// duration.
const int kTimelineMembers = 50;

/// One minted timeline and the queue entries it was minted for.
///
/// Queue ids rather than pids: the same pid can sit in a queue twice,
/// and what a member has to answer is "is *this* entry the one playing",
/// which only the id can.
class _Minted {
  const _Minted(this.media, this.queueIds);

  final TimelineMedia media;
  final List<String> queueIds;

  int indexOf(String queueId) => queueIds.indexOf(queueId);
}

/// Keeps a queue rendered as one gapless stream, and hands the player
/// the member it should be playing.
///
/// Owned by the now-playing controller, which is the only thing that
/// knows when a start, a crossing, or a queue edit happened. The feeder
/// itself holds one loaded timeline, at most one freshly minted
/// replacement waiting for a seam to swap at, and the reason it gave up
/// when a server cannot render one at all.
///
/// Nothing here ever reloads mid-track except a timeline that stopped
/// being servable. A queue edit mints a replacement and waits: the
/// listener hears the swap at the seam they were going to hear anyway.
class TimelineFeeder {
  TimelineFeeder({
    required this.repository,
    required this.engine,
    required this.enabled,
    required this.crossfadeSeconds,
    required this.maxBitrateKbps,
    required this.resolve,
    this.onStatus,
    this.remintDelay = const Duration(milliseconds: 750),
    this.measuringDelay = const Duration(seconds: 3),
  });

  final WaxDeckRepository repository;
  final AudioEnginePort engine;

  /// Whether the listener has asked for this at all.
  final bool Function() enabled;

  /// The account's crossfade, which shapes the seams the mint returns.
  final double? Function() crossfadeSeconds;

  /// The quality ceiling this listener chose, null for unlimited. Not
  /// sent to the mint - a timeline has no bitrate parameter - but
  /// applied to the formats offered, because asking for lossless is
  /// how a rendering gets to be lossless.
  final int? Function() maxBitrateKbps;

  /// Resolves a queue pid to its summary, so a run stops where the
  /// music does. The controller's own resolver, cache included.
  final Future<ItemSummary?> Function(String pid) resolve;

  /// Told what to say about gapless on this device: null when it is
  /// working, a reason when it is not.
  final void Function(String? reason)? onStatus;

  /// How long a queue edit settles before a replacement is minted. A
  /// drag across a queue screen is many edits, and each one would
  /// otherwise cost a render.
  final Duration remintDelay;

  /// How long to wait before asking again while the server measures.
  /// Re-requesting is the poll: the contract says a mint answers
  /// immediately once measurement finishes.
  final Duration measuringDelay;

  _Minted? _loaded;
  _Minted? _pending;
  Timer? _retry;
  bool _minting = false;

  /// The queue id a replacement is being minted to reach. Asked once
  /// per entry: an entry no timeline can hold - a podcast, a book, an
  /// item the server refuses - will not become one, and re-asking on
  /// every position tick would be a render a second for the rest of the
  /// track.
  String? _wanted;

  /// What was last said about gapless on this device, so the same
  /// answer is not published twice.
  String? _reason;

  /// Whether to stop asking for the life of this container. Set when an
  /// answer is about this pair of ends rather than about a queue - a
  /// server that renders no timelines, a browser that plays none, a
  /// server whose renderings this browser cannot decode - since asking
  /// again every track would be a request per track for an answer that
  /// will not change.
  bool _off = false;

  /// Whether the engine can play a timeline at all, once it has been
  /// asked. Null until the first music start, because the answer costs
  /// a script fetch and a listener who never plays music never pays it.
  bool? _engineReady;

  TimelineAudioEngine? get _timelineEngine {
    final engine = this.engine;
    return engine is TimelineAudioEngine ? engine : null;
  }

  /// Whether this session is playing a member rather than its own
  /// stream, which is what decides who arms the next item.
  bool holds(PlaybackSession session) =>
      _loaded != null && session.timeline != null;

  /// The member [entry] should start on, minting a timeline for it when
  /// nothing loaded holds it. Null means the ordinary per-item path:
  /// the flag is off, the engine plays no timelines, the item is not
  /// music, or a mint was refused.
  Future<TimelineSlot?> slotFor(
    QueueEntry entry,
    ItemSummary item,
    QueueState queue,
  ) async {
    if (!_admits(item)) return null;
    if (!await _engineCanPlay()) return null;
    final held = _slotIn(_loaded, entry);
    if (held != null) return held;
    // A replacement minted while the outgoing timeline played on: if
    // this start landed on it, it is simply the timeline now.
    final promoted = _slotIn(_pending, entry);
    if (promoted != null) {
      _loaded = _pending;
      _pending = null;
      return promoted;
    }
    final minted = await _mintFrom(queue, entry);
    if (minted == null) return null;
    _loaded = minted;
    _pending = null;
    return _slotIn(minted, entry);
  }

  /// The member [entry] is on the loaded timeline, without minting.
  /// What a crossing needs: the stream is already playing it.
  TimelineSlot? slotAt(QueueEntry entry) => _slotIn(_loaded, entry);

  /// The next member as the controller's preload record, so a crossing
  /// knows what it crossed into.
  ///
  /// Answers from the loaded timeline in the ordinary case and from a
  /// pending replacement when the queue's tail moved; when neither
  /// holds the next entry it arms nothing and asks for a replacement,
  /// which lands well before the seam unless the edit was made in the
  /// last moment of a track.
  Future<({QueueEntry entry, PlayInfo info})?> armNext(QueueState queue) async {
    final loaded = _loaded;
    final engine = _timelineEngine;
    if (loaded == null || engine == null) return null;
    final next = queue.nextEntry;
    if (next == null) {
      _wanted = null;
      return null;
    }
    // The member the stream will actually run into, which is the only
    // one a crossing can be about. Looking the next entry up anywhere on
    // the timeline armed a member the stream would not reach for
    // minutes: remove the track between two others and the crossing
    // into the removed one arrives labelled as the track after it, so
    // the deck, the media session and the listen report all name
    // something the listener is not hearing.
    final ahead = engine.currentMember + 1;
    if (ahead < loaded.queueIds.length &&
        loaded.queueIds[ahead] == next.queueId) {
      _wanted = null;
      return (
        entry: next,
        info: _infoFor(next.pid, TimelineSlot(loaded.media, ahead)),
      );
    }
    // A replacement is a different stream, swapped in at whatever seam
    // the outgoing one reaches, so any member of it will do.
    final swapped = _slotIn(_pending, next);
    if (swapped != null) {
      _wanted = null;
      return (entry: next, info: _infoFor(next.pid, swapped));
    }
    if (_wanted == next.queueId) return null;
    _wanted = next.queueId;
    // A next item no timeline can hold - a podcast, a book - is not
    // worth a render: the run would stop before it and hand back the
    // rendering already loaded. Resolved rather than assumed, and
    // cached by the resolver, so this costs nothing after the first
    // tick.
    final item = await resolve(next.pid);
    if (item == null || item.mediaType != MediaType.music) return null;
    _scheduleRemint(queue);
    return null;
  }

  /// Puts the stream back at the head of the member it has just run
  /// into the far side of.
  ///
  /// A timeline holds the whole queue, so an item ending is a position
  /// passing a number rather than a stream stopping - and a lap of
  /// repeat one has no next entry to arm, so the seam arrives with
  /// nothing to cross into and the listener hears the head of the track
  /// after theirs. Rewound before the queue is told anything; the
  /// restart that follows is the ordinary repeat.
  void rewindMember() {
    final loaded = _loaded;
    final engine = _timelineEngine;
    if (loaded == null || engine == null) return;
    // Only when the stream playing is that timeline. A run that ended
    // at a podcast leaves the record standing while the ordinary path
    // plays, and a seam there is an item ending, not a member crossing.
    if (engine.loadedTimeline?.url != loaded.media.url) return;
    final back = engine.currentMember - 1;
    if (back < 0) return;
    unawaited(engine.seekToMember(back, Duration.zero));
  }

  /// Swaps to a replacement timeline as the crossing into [entry]
  /// settles. Playback is running and stays running: this is the one
  /// load that must not pause first.
  ///
  /// False when the swap failed, which is not a swap that did nothing:
  /// a replacement always has a new URL, so the load tore the outgoing
  /// stream down before it began. Nothing is playing, and the caller
  /// has to start the item rather than adopt it.
  Future<bool> settleSwap(QueueEntry entry) async {
    final pending = _pending;
    final engine = _timelineEngine;
    if (pending == null || engine == null) return true;
    final member = pending.indexOf(entry.queueId);
    if (member < 0) return true;
    _pending = null;
    _loaded = pending;
    try {
      await engine.loadTimeline(
        pending.media,
        member: member,
        position: engine.position,
        play: true,
      );
      return true;
    } on Object catch (error) {
      debugPrint('timeline swap failed: $error');
      _loaded = null;
      return false;
    }
  }

  /// Re-mints and reloads a timeline that stopped being servable, at
  /// the position it stood at. The one mid-track reload.
  ///
  /// False when nothing was recovered, and the caller owes the listener
  /// a start on the ordinary path: the stream that was playing is gone
  /// either way, so a silent return here is silence.
  Future<bool> onLost(
    PlaybackSession? session,
    QueueState queue, {
    required bool resume,
  }) async {
    final entry = queue.currentEntry;
    if (session == null || entry == null) {
      clear();
      return false;
    }
    // A stream can outlive the reason it exists: the switch goes off,
    // or a server says it renders none, while a timeline loaded earlier
    // plays on to the end of its track. Losing that one is not a reason
    // to mint another.
    if (_off || !enabled()) {
      clear();
      return false;
    }
    _loaded = null;
    _pending = null;
    final minted = await _mintFrom(queue, entry);
    final slot = _slotIn(minted, entry);
    if (minted == null || slot == null) return false;
    _loaded = minted;
    try {
      await session.reloadTimeline(slot, resume: resume);
      return true;
    } on Object catch (error) {
      debugPrint('timeline reload failed: $error');
      _loaded = null;
      return false;
    }
  }

  /// A refusal met mid-stream. Nothing to fall back to - the ordinary
  /// path sits under the same limit - so the reason is published and
  /// the stream stays where it stopped.
  void onRefused(String code) => _say(code);

  /// Drops everything. The engine is stopped by whoever called this.
  void clear() {
    _retry?.cancel();
    _retry = null;
    _loaded = null;
    _pending = null;
    _wanted = null;
  }

  void dispose() {
    _retry?.cancel();
    _retry = null;
  }

  /// Whether the engine can take a timeline at all, asked once.
  ///
  /// Ahead of the mint, never after it: a browser whose player library
  /// never arrived, or whose media source decodes none of the formats,
  /// answers false here having cost the listener nothing. Asked after
  /// the mint instead, the same browser spent a render and a transcode
  /// slot per music track and then failed the load, which the start
  /// path reads as a bad file and skips.
  Future<bool> _engineCanPlay() async {
    final engine = _timelineEngine;
    if (engine == null) return false;
    final known = _engineReady;
    if (known != null) return known;
    var ready = false;
    try {
      ready = await engine.prepareTimelines();
    } on Object catch (error) {
      debugPrint('timeline engine could not prepare: $error');
    }
    _engineReady = ready;
    if (!ready) _giveUp('gapless-unsupported');
    return ready;
  }

  /// Stops asking, for the life of this container, and says why.
  void _giveUp(String reason) {
    _off = true;
    _say(reason);
  }

  /// Publishes what to say about gapless here: a reason when it is not
  /// working, null when it is.
  ///
  /// Cleared as well as set, and only on a change. A refusal met once -
  /// the server's session cap, reached because somebody else was
  /// streaming - otherwise stood as "this server cannot render a queue
  /// as one stream" for the life of the container, long after the very
  /// next mint had succeeded.
  void _say(String? reason) {
    if (_reason == reason) return;
    _reason = reason;
    onStatus?.call(reason);
  }

  bool _admits(ItemSummary item) {
    if (_off || !enabled()) return false;
    if (_timelineEngine == null) return false;
    if (_engineReady == false) return false;
    // Music only, for the same reason the preload window is music only:
    // spoken word carries per-item speed and trimming that a seam
    // inside one stream cannot apply, and a book rolls its parts inside
    // one session already.
    return item.mediaType == MediaType.music;
  }

  /// The decodable formats a listener who set a quality ceiling is
  /// asking for: the lossy ones. A ceiling is what a listener chose for
  /// this connection, and a whole queue rendered losslessly is the one
  /// thing they were choosing against - the single-item path already
  /// sends the same number and the server already honours it there.
  ///
  /// Only when something lossy survives: a browser that decodes nothing
  /// else is better served the rendering it can play than none at all.
  List<String>? _withinQuality(List<String>? formats) {
    if (formats == null || maxBitrateKbps() == null) return formats;
    final lossy = <String>[
      for (final f in formats)
        if (f != 'flac' && f != 'alac') f,
    ];
    return lossy.isEmpty ? formats : lossy;
  }

  TimelineSlot? _slotIn(_Minted? held, QueueEntry entry) {
    if (held == null) return null;
    final member = held.indexOf(entry.queueId);
    return member < 0 ? null : TimelineSlot(held.media, member);
  }

  /// What a member would have answered had it been resolved on its own.
  PlayInfo _infoFor(String pid, TimelineSlot slot) => PlayInfo(
    pid: pid,
    url: slot.media.url,
    mimeType: slot.media.mimeType,
    durationMs: slot.durationMs,
    seekable: true,
    expiresAt: slot.media.expiresAt,
  );

  /// Mints over the run of consecutive music entries beginning at
  /// [entry]. The run stops at the first thing a timeline cannot hold,
  /// so a podcast in the middle of a queue simply ends the render
  /// rather than refusing it.
  Future<_Minted?> _mintFrom(QueueState queue, QueueEntry entry) async {
    if (_minting) return null;
    final start = queue.entries.indexWhere((e) => e.queueId == entry.queueId);
    if (start < 0) return null;
    _minting = true;
    try {
      final run = await _musicRun(queue, start);
      if (run.isEmpty) return null;
      final decodable = _withinQuality(
        _timelineEngine?.supportedTimelineFormats,
      );
      final tl = await repository.createQueueTimeline(
        <String>[for (final e in run) e.pid],
        crossfadeSeconds: crossfadeSeconds(),
        formats: decodable,
      );
      // What came back, not what was asked for. A server that can
      // produce none of them falls back to its own ladder and says so
      // in the answer, and playing that is silence with nothing to
      // explain it - which is the whole reason the format is reported.
      // Sticky, because the answer is about this pair of ends and will
      // not be different for the next queue.
      final rendered = tl.format;
      if (decodable != null &&
          decodable.isNotEmpty &&
          rendered != null &&
          rendered.isNotEmpty &&
          !decodable.contains(rendered)) {
        _giveUp('gapless-format');
        return null;
      }
      _say(null);
      return _Minted(_mediaFrom(tl), <String>[for (final e in run) e.queueId]);
    } on WaxDeckApiException catch (e) {
      _handleMintRefusal(e, queue, entry);
      return null;
    } on Object catch (error) {
      // Transport, or anything else nobody planned for: this start
      // takes the ordinary path and the next one asks again.
      debugPrint('timeline mint failed: $error');
      return null;
    } finally {
      _minting = false;
    }
  }

  void _handleMintRefusal(
    WaxDeckApiException e,
    QueueState queue,
    QueueEntry entry,
  ) {
    switch (e.statusCode) {
      case 501:
        // This server renders no timelines at all. Said once, and then
        // never asked again: the answer is about the server, not the
        // queue.
        _giveUp(e.code);
      case 202:
        // Member lengths are still being measured. This track plays the
        // ordinary way while the mint is asked for again; re-requesting
        // is the poll the contract describes, and the replacement is
        // swapped in at the next seam.
        _scheduleRemint(queue, delay: measuringDelay);
      case 429:
        // The server's transcode limit, met at the mint. Not sticky -
        // it is about how busy the server is, not about this queue -
        // but said, because a switch that is on and doing nothing has
        // to explain itself. The next mint that lands clears it.
        _say(e.code);
      default:
        // A queue this server cannot render as one stream (409), a bad
        // crossfade (400): the ordinary path plays it and a different
        // queue may well mint.
        debugPrint('timeline mint refused: ${e.code}');
    }
  }

  void _scheduleRemint(QueueState queue, {Duration? delay}) {
    if (_off) return;
    _retry?.cancel();
    _retry = Timer(delay ?? remintDelay, () async {
      _retry = null;
      final entry = queue.currentEntry;
      if (entry == null) return;
      final minted = await _mintFrom(queue, entry);
      if (minted == null) return;
      // Held rather than installed: the stream playing is the one the
      // listener is hearing, and the swap belongs at a seam.
      _pending = minted;
    });
  }

  Future<List<QueueEntry>> _musicRun(QueueState queue, int start) async {
    final window = <QueueEntry>[];
    for (
      var i = start;
      i < queue.entries.length && window.length < kTimelineMembers;
      i++
    ) {
      window.add(queue.entries[i]);
    }
    // Resolved together: fifty sequential reads would put the mint
    // behind the track it is for.
    final items = await Future.wait(
      window.map((e) => resolve(e.pid).catchError((Object _) => null)),
    );
    final run = <QueueEntry>[];
    for (var i = 0; i < window.length; i++) {
      final item = items[i];
      if (item == null || item.mediaType != MediaType.music) break;
      run.add(window[i]);
    }
    return run;
  }

  TimelineMedia _mediaFrom(QueueTimeline tl) => TimelineMedia(
    url: tl.url,
    mimeType: tl.mimeType,
    durationMs: tl.durationMs,
    envelopeRate: tl.envelopeRate,
    expiresAt: tl.expiresAt,
    crossfadeSeconds: tl.crossfadeSeconds,
    format: tl.format,
    members: <TimelineMember>[
      for (final m in tl.members)
        TimelineMember(
          pid: m.pid,
          offsetSamples: m.offsetSamples,
          durationSamples: m.durationSamples,
        ),
    ],
  );
}
