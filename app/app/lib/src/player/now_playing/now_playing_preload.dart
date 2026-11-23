part of '../now_playing_controller.dart';

/// The preload of what comes next, timeline recovery, and the summaries.
mixin _NowPlayingPreload on _NowPlayingCore, _NowPlayingPark {
  /// Keeps what the engine has prepared in step with what the queue says
  /// comes next.
  ///
  /// A request that arrives while an arm is in flight is remembered and
  /// run after it, never dropped: resolving one takes three round trips,
  /// and a queue edited inside that window would otherwise leave the
  /// engine holding an item nobody wants next until the next position
  /// tick, or for good if playback is paused.
  Future<void> _syncPreload() async {
    if (_arming) {
      _armAgain = true;
      return;
    }
    _arming = true;
    try {
      do {
        _armAgain = false;
        try {
          await _reconcilePreload();
        } on Object catch (error) {
          // Preloading is best effort by contract: a failure here costs
          // the gapless crossing and nothing else, since the item loads
          // on advance the way it always did. Swallowed here rather than
          // around the loop, so a queue edit that arrived while this was
          // failing is still run: it is the edit that has no other way
          // of being noticed, since a paused queue emits no ticks.
          debugPrint('preload skipped: $error');
        }
      } while (_armAgain && ref.mounted);
    } finally {
      _arming = false;
      _armAgain = false;
    }
  }

  Future<void> _reconcilePreload() async {
    final next = ref.read(queueControllerProvider).nextEntry;
    final armed = _preload;
    final went = _copyWent;
    _copyWent = null;
    if (armed != null &&
        armed.entry.queueId == next?.queueId &&
        armed != went) {
      return;
    }
    if (armed != null) {
      // Cleared first, forgotten second: a clear that throws leaves the
      // engine holding the item, and the record has to say so or a
      // crossing into it arrives with nothing to identify it by.
      await _engine.clearPreload();
      _preload = null;
    }
    if (_refusedNext != null && _refusedNext != next?.queueId) {
      _refusedNext = null;
    }
    if (next == null || _refusedNext == next.queueId) return;
    final session = _session;
    // Until media reaches the engine, its position and duration are the
    // previous item's: measuring them would arm against the wrong item's
    // remaining time, and the load that follows drops the preload at the
    // engine while the record here goes on claiming it.
    if (session == null || !session.isLoaded) return;
    if (!_admitsPreload(session.item)) return;
    // A timeline holds the next member in the stream already playing,
    // so there is nothing to fetch and nothing to gate: no lead, since
    // the media is here, and no metered check, since arming spends no
    // bytes. Ahead of the window check because a timeline engine has no
    // window - crossing is the server's arrangement, not a caller's.
    if (_feeder.holds(session)) {
      final armed = await _feeder.armNext(ref.read(queueControllerProvider));
      _preload = armed == null
          ? null
          : (entry: armed.entry, info: armed.info, copy: null);
      return;
    }
    // An engine with no window drops whatever this prepares, and
    // preparing it is three round trips and a minted stream token per
    // track. It advances on `completed` instead, which is the same path
    // a queue's last item takes.
    if (!_engine.canPreload) return;
    // Too early to arm (a minted stream URL would age), or no length to
    // measure against.
    final remaining = session.mediaDuration - session.displayPosition;
    if (remaining <= Duration.zero || remaining > kPreloadLead) return;
    // A downloaded next track is armed from its file: nothing minted,
    // nothing asked of the server, and no bytes spent, so no metered check.
    if (_uncopiedNext != next.queueId) {
      final downloads = ref.read(downloadManagerProvider);
      final copy = await _copyOf(downloads, next.pid);
      if (!ref.mounted) return;
      if (copy != null) {
        await _armCopy(next, copy, downloads!);
        return;
      }
      _uncopiedNext = next.queueId;
      if (downloads != null) _watchDownload(downloads, next);
    }
    // Asked at the moment of arming rather than held as state, and not
    // recorded as a refusal: a listener who walks indoors mid-track gets
    // the gapless crossing, and one who walks out does not. Refusing by
    // queue id would stick to the entry for as long as it stayed next.
    if (ref.read(preloadOnWifiOnlyProvider) &&
        await ref.read(connectivityProvider).cost() == ConnectionCost.metered) {
      return;
    }
    if (!ref.mounted) return;

    final item = await _resolve(next.pid);
    if (!ref.mounted) return;
    if (!_admitsPreload(item)) {
      _refusedNext = next.queueId;
      return;
    }
    // No play-state read here any more. It refused an item with a saved
    // position, because the port prepares an item at the head of its
    // window - but both guards above have already returned for anything
    // that is not music, and music now always starts at the head. That
    // made the read a round trip per arm whose answer could not matter,
    // and it cost the gapless crossing into every track the listener had
    // once heard part of.
    final info = await ref
        .read(repositoryProvider)
        .getPlayInfo(
          next.pid,
          maxBitrateKbps: ref.read(streamMaxBitrateKbpsProvider),
        );
    if (!ref.mounted) return;
    // Only passthrough streams: a preloaded transcode opens a second
    // server-side session, which double counts against the transcode
    // limiter or is refused outright in the middle of a queue. Asked
    // without HLS, as here, the server marks a cut, capped, or
    // voice-boosted stream unseekable, so these two answers are the
    // whole test.
    if (!info.seekable || info.voiceBoost) {
      _refusedNext = next.queueId;
      return;
    }
    // The queue may have moved while all of that resolved.
    if (ref.read(queueControllerProvider).nextEntry?.queueId != next.queueId) {
      return;
    }
    await _engine.preloadNext(
      info.url,
      mimeType: info.mimeType,
      clipStart: info.spanStartMs == null
          ? null
          : Duration(milliseconds: info.spanStartMs!),
      clipEnd: info.spanEndMs == null
          ? null
          : Duration(milliseconds: info.spanEndMs!),
    );
    // Recorded even if the queue moved while that landed, because this
    // is what the engine holds, not what the queue wants: an edit inside
    // the window re-runs the reconcile, which drops it, and a crossing
    // that beats the reconcile still knows by identity which entry it
    // walked into.
    _preload = (entry: next, info: info, copy: null);
  }

  /// The device copy of [pid] where one is downloaded whole as one file.
  Future<LocalPlayback?> _copyOf(
    DownloadManagerPort? downloads,
    String pid,
  ) async {
    final copy = await downloads?.localFor(pid);
    return copy != null && copy.parts.length == 1 ? copy : null;
  }

  /// Arms [next] from [copy], its file on this device, and watches its
  /// download (see [_watchDownload]).
  Future<void> _armCopy(
    QueueEntry next,
    LocalPlayback copy,
    DownloadManagerPort downloads,
  ) async {
    final item = await _resolve(next.pid);
    if (!ref.mounted) return;
    if (!_admitsPreload(item)) {
      _refusedNext = next.queueId;
      return;
    }
    if (ref.read(queueControllerProvider).nextEntry?.queueId != next.queueId) {
      return;
    }
    final end = copy.spanEndMs;
    await _engine.preloadNext(
      Uri.file(copy.parts.first.path).toString(),
      clipStart: copy.spanStartMs == null
          ? null
          : Duration(milliseconds: copy.spanStartMs!),
      // An open end plays to the file's end, as a start of the copy does.
      clipEnd: end == null || end <= 0 ? null : Duration(milliseconds: end),
    );
    // Recorded as what the engine holds, for the reason given below.
    _preload = (entry: next, info: null, copy: copy);
    _watchDownload(downloads, next);
  }

  /// Watches [next]'s download while it is next: a download that ends
  /// (complete, failed, or stopped) under the copy armed for it drops that
  /// and arms what the store then holds; a refresh in progress or a pause
  /// leaves the armed file, which stays in place until the refresh lands.
  /// A download completing for it, found without one, looks it up again.
  void _watchDownload(DownloadManagerPort downloads, QueueEntry next) {
    if (_watchedNext == next.queueId) return;
    _watchedNext = next.queueId;
    unawaited(_downloadWatch?.cancel());
    _downloadWatch = downloads.progress.where((p) => p.pid == next.pid).listen((
      progress,
    ) {
      if (!ref.mounted) return;
      final armed = _preload;
      final ended = progress.complete || progress.failed || progress.stopped;
      if (armed != null &&
          armed.copy != null &&
          armed.entry.queueId == next.queueId) {
        if (!ended) return;
        _copyWent = armed;
      } else if (progress.complete && _uncopiedNext == next.queueId) {
        _uncopiedNext = null;
      } else {
        return;
      }
      unawaited(_syncPreload());
    });
  }

  /// Gapless is a music affordance, and both sides of a crossing have to
  /// be music for it.
  ///
  /// Spoken word carries per-item playback config the crossing cannot
  /// apply in time: a book or show plays at its own remembered speed, so
  /// an item crossed into would run at the previous one's rate until its
  /// session caught up, and an episode with a skip-intro setting does
  /// not start at its own head at all. Books roll their parts inside one
  /// session besides, which is not a queue boundary.
  bool _admitsPreload(ItemSummary item) => item.mediaType == MediaType.music;

  /// The loaded timeline stopped being servable: its token aged out, or
  /// the server let the render go. Re-minted and reloaded where the
  /// listener stands, keeping the listen session, which is the one
  /// mid-track reload this path allows.
  void _onTimelineLost(bool wasPlaying) {
    if (_radioOwnsEngine) return;
    _inFlight = _recoverTimeline(wasPlaying);
  }

  /// Re-mints where the listener stands, and starts the item the
  /// ordinary way when nothing could be re-minted.
  ///
  /// The fallback is the point: the stream that was playing is gone
  /// whatever happens next, so a mint that a 409, a transport failure
  /// or the server's cap turned down leaves nothing playing, no error
  /// pane, and a queue that never advances - a deck that has simply
  /// stopped, with nothing on screen to say so.
  ///
  /// A timeline lost again before playback proved itself is not minted
  /// once more ([PlaybackSession.mayRecover]): that entry starts on the
  /// ordinary path, so a rendering that keeps failing costs a mint or two
  /// rather than one per loss.
  Future<void> _recoverTimeline(bool wasPlaying) async {
    final began = _startToken;
    final queue = ref.read(queueControllerProvider);
    final session = _session;
    final spent = session != null && !session.mayRecover;
    if (spent) _feeder.clear();
    final recovered =
        !spent && await _feeder.onLost(session, queue, resume: wasPlaying);
    // A station took the engine, or something else started or stopped,
    // while the mint was out: that owns the engine now, park included.
    if (recovered || _superseded(began) || _radioOwnsEngine) return;
    final entry = queue.currentEntry;
    if (entry == null) return;
    await _start(entry, useSavedPosition: true, ordinary: spent);
  }

  Future<void> _dropPreload() async {
    if (_preload == null) return;
    _preload = null;
    await _engine.clearPreload();
  }

  Future<ItemSummary> _resolve(String pid) async {
    final known = _known[pid];
    if (known != null) return known;
    final repository = ref.read(repositoryProvider);
    final item = await repository.getItem(pid);
    if (item.mediaType != MediaType.podcast) {
      _remember(pid, item);
      return item;
    }
    // An episode reached by pid alone (a queue handed over by another
    // device, a browse leaf on a head unit, a restored queue the mirror
    // could not name) arrives from `GET /items/{pid}` as a plain item
    // detail, which carries no show pid, and the per-show speed, trim,
    // and skip settings all hang off that. The episode endpoint carries
    // one, so it is worth the second round trip on the rare path that
    // has no summary in hand.
    try {
      final episode = await repository.getEpisode(pid);
      _remember(pid, episode);
      return episode;
    } on WaxDeckApiException {
      // The show's settings are a refinement; the episode still plays.
      _remember(pid, item);
      return item;
    }
  }

  /// Holds [item] for [pid] from a read, which a start overtaken meanwhile
  /// may be past caring about: the park naming [pid] still follows. Not
  /// once the container has gone.
  void _remember(String pid, ItemSummary item) {
    if (!ref.mounted) return;
    _known[pid] = item;
    _parkFollowsKnown();
  }

  /// Forgets summaries no queue needs any more: neither the queue in hand
  /// nor the one an undo would bring back. The cache is a convenience for
  /// those, not a catalog.
  void _prune(QueueState queue) {
    final keep = {...queue.pids, ...?queue.undo?.queue.pids};
    final playing = _session?.item.pid;
    if (playing != null) keep.add(playing);
    _known.removeWhere((pid, _) => !keep.contains(pid));
    _parkFollowsKnown();
  }
}
