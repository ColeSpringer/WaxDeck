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
  const _Minted(this.media, this.queueIds, this.pid);

  final TimelineMedia media;
  final List<String> queueIds;

  /// The rendering's own id, for handing its transcode slot back when
  /// this stops being played. Null from a server that mints none.
  final String? pid;

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

  /// A rendering a promote handed off, held until the one that replaced
  /// it is being fetched. See the promote in [slotFor].
  _Minted? _handedOff;

  Timer? _retry;
  bool _minting = false;

  /// Bumped by every teardown. A mint already awaiting cannot be
  /// cancelled, so the callback that installed it compares this and
  /// hands the rendering back instead of storing it somewhere nothing
  /// will ever look again.
  int _generation = 0;

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
    _flushHandedOff();
    if (!_admits(item)) return null;
    if (!await _engineCanPlay()) return null;
    final held = _slotIn(_loaded, entry);
    if (held != null) return held;
    // A replacement minted while the outgoing timeline played on: if
    // this start landed on it, it is simply the timeline now.
    final promoted = _slotIn(_pending, entry);
    if (promoted != null) {
      // Handed off rather than let go of. The caller loads the promoted
      // rendering after this returns, and a slot is per listener: a
      // release only reaches the gate when none of this listener's
      // renderings has been fetched inside the idle minute, and a
      // replacement minted a track ago is exactly that. Letting the
      // outgoing one go here would put the slot back before the new
      // stream asks for its first fragment, which on a full server is a
      // refusal the player is told not to recover from.
      _handedOff = _loaded;
      _loaded = _pending;
      _pending = null;
      return promoted;
    }
    final minted = await _mintFrom(queue, entry);
    if (minted == null) return null;
    _releaseAll([_loaded, _pending], keeping: minted);
    _loaded = minted;
    _pending = null;
    return _slotIn(minted, entry);
  }

  /// The member [entry] is on the loaded timeline, without minting.
  /// What a crossing needs: the stream is already playing it.
  TimelineSlot? slotAt(QueueEntry entry) {
    _flushHandedOff();
    return _slotIn(_loaded, entry);
  }

  /// The start this feeder handed a slot to is loaded and fetching.
  ///
  /// Which is when a rendering a promote handed off can go back: the
  /// stream that replaced it is holding the slot itself now, so the
  /// release cannot leave the listener with none.
  void started() => _flushHandedOff();

  /// Lets go of a rendering handed off by a promote, now that the one
  /// that replaced it is being fetched.
  void _flushHandedOff() {
    final gone = _handedOff;
    _handedOff = null;
    _replace(gone, _loaded);
  }

  /// The next member as the controller's preload record, so a crossing
  /// knows what it crossed into.
  ///
  /// Answers from the loaded timeline in the ordinary case and from a
  /// pending replacement when the queue's tail moved; when neither
  /// holds the next entry it arms nothing and asks for a replacement,
  /// which lands well before the seam unless the edit was made in the
  /// last moment of a track.
  Future<({QueueEntry entry, PlayInfo info})?> armNext(QueueState queue) async {
    // The caller arms the next member once the start it just asked for
    // has loaded, which is where a promote's hand-off is safe to let
    // go of: the new stream is fetching and holding the slot itself.
    _flushHandedOff();
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
    final outgoing = _loaded;
    _pending = null;
    _loaded = pending;
    try {
      await engine.loadTimeline(
        pending.media,
        member: member,
        position: engine.position,
        play: true,
      );
      // After the load, not before it: until this returns the outgoing
      // stream may still be the one playing, and handing its slot back
      // early leaves it fetching against a cap it no longer counts
      // towards.
      _replace(outgoing, pending);
      return true;
    } on Object catch (error) {
      debugPrint('timeline swap failed: $error');
      // A replacement always has a new URL, so the load tore the
      // outgoing stream down before it began: neither rendering is
      // playing and both go back.
      _replace(outgoing, null);
      _release(pending);
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
    final outgoing = <_Minted?>[_loaded, _pending];
    _loaded = null;
    _pending = null;
    // After the mint rather than before it, so the pid it answers is
    // known: a re-mint of a queue the server still holds answers the
    // same one.
    final minted = await _mintFrom(queue, entry);
    for (final gone in outgoing) {
      _replace(gone, minted);
    }
    final slot = _slotIn(minted, entry);
    if (minted == null || slot == null) {
      // The mint may have landed while the queue moved out from under
      // it, which leaves a rendering listing this listener and a slot
      // taken for a stream nothing will ever fetch.
      _release(minted);
      return false;
    }
    _loaded = minted;
    try {
      await session.reloadTimeline(slot, resume: resume);
      return true;
    } on Object catch (error) {
      debugPrint('timeline reload failed: $error');
      _release(_loaded);
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
    _generation++;
    _retry?.cancel();
    _retry = null;
    _releaseAll([_handedOff, _loaded, _pending]);
    _handedOff = null;
    _loaded = null;
    _pending = null;
    _wanted = null;
  }

  /// The rendering currently playing, or null when none is.
  String? get loadedPid => _loaded?.pid;

  /// Every rendering this feeder is holding, for a client that has to
  /// release them somewhere the feeder is not around to: a browser tab
  /// closing sends them on the exit path.
  ///
  /// All of them, not only the one playing. A queue edit mints a
  /// replacement the server already counts this listener as being on,
  /// and a slot is per listener: releasing the playing one alone leaves
  /// the replacement holding it, and the release then does nothing at
  /// all because the server can still see a live rendering of theirs.
  List<String> get heldPids {
    final out = <String>[];
    for (final held in [_loaded, _pending, _handedOff]) {
      final pid = held?.pid;
      if (pid != null && !out.contains(pid)) out.add(pid);
    }
    return out;
  }

  /// Lets go of one rendering in favour of another, handing the
  /// outgoing one's slot back.
  ///
  /// Not when the two are the same rendering: re-minting a queue the
  /// server still holds answers the same pid, and releasing that would
  /// take back the slot the new stream is about to fetch on. Every
  /// place that stops holding a `_Minted` goes through here, because
  /// the server keeps counting a listener as listening until it hears
  /// otherwise - one dropped silently keeps the slot alive for the
  /// minute the release exists to save.
  void _replace(_Minted? outgoing, _Minted? incoming) {
    if (outgoing == null || outgoing.pid == incoming?.pid) return;
    _release(outgoing);
  }

  /// Hands back the transcode slot a rendering was holding. Fire and
  /// forget in both directions: the server's idle sweep releases it a
  /// minute later anyway, so this must never delay a teardown and a
  /// failure is not worth reporting.
  void _release(_Minted? minted) => _releasePid(minted?.pid);

  /// Hands back everything named here, each rendering once and none of
  /// them [keeping]. A re-mint of a queue the server still holds answers
  /// the same pid, so two of these can name one rendering - and the
  /// second DELETE for it is a request for nothing, which is what
  /// [_replace]'s guard exists to avoid one transition at a time.
  void _releaseAll(Iterable<_Minted?> held, {_Minted? keeping}) {
    final done = <String>{?keeping?.pid};
    for (final one in held) {
      final pid = one?.pid;
      if (pid == null || !done.add(pid)) continue;
      _releasePid(pid);
    }
  }

  /// [_release] by pid, for a rendering the server minted that never
  /// became a [_Minted] here.
  void _releasePid(String? pid) {
    if (pid == null) return;
    unawaited(repository.releaseQueueTimeline(pid).catchError((Object _) {}));
  }

  /// Teardown, which is [clear]: a rendering dropped without a release
  /// keeps its slot for the idle minute, and on every platform but a
  /// browser tab this is the only teardown there is - there is no exit
  /// beacon anywhere else to send one.
  void dispose() => clear();

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
        // The server minted it: a slot is taken and a rendering is
        // stashed listing this listener, for a stream this end cannot
        // play. Handing it straight back matters more here than
        // anywhere else, because what happens next is a progressive
        // stream per track and each of those wants a slot of its own -
        // at a cap of one, the next track is refused by the rendering
        // nobody is listening to.
        _releasePid(tl.pid);
        _giveUp('gapless-format');
        return null;
      }
      _say(null);
      return _Minted(_mediaFrom(tl), <String>[
        for (final e in run) e.queueId,
      ], tl.pid);
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
    final generation = _generation;
    _retry = Timer(delay ?? remintDelay, () async {
      _retry = null;
      final entry = queue.currentEntry;
      if (entry == null) return;
      final minted = await _mintFrom(queue, entry);
      if (minted == null) return;
      if (generation != _generation) {
        // Stopped, or torn down, while the mint was in flight.
        // Cancelling the timer cannot reach an await that had already
        // begun, and installing here would leave a rendering the server
        // already counts this listener as being on with nothing left to
        // hand it back - on the web the exit beacon has fired by now,
        // so the idle sweep is the only thing that would.
        _release(minted);
        return;
      }
      // Held rather than installed: the stream playing is the one the
      // listener is hearing, and the swap belongs at a seam. A
      // replacement this one displaces was never played, so its slot
      // goes straight back.
      _replace(_pending, minted);
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
