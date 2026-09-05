import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'database.dart';
import 'events_channel.dart';

/// How the engine currently reaches the server.
enum SyncConnection { connected, connecting, offline }

/// One frame of engine status for the UI.
class SyncStatus {
  const SyncStatus({required this.connection, this.lastSyncAt});

  final SyncConnection connection;
  final DateTime? lastSyncAt;

  bool get online => connection == SyncConnection.connected;
}

/// The delta-sync engine: mirrors the catalog and the user's own play
/// states into the local database, follows the server's WebSocket
/// invalidations, queues mutations while offline, and replays them with
/// their recorded times on reconnect so the server can reconcile per
/// medium. A `sync-reset` from either stream drops the affected mirror
/// half and re-mirrors; the full resync is an ordinary code path here,
/// not an emergency.
class SyncEngine {
  SyncEngine({
    required this.db,
    required this.repository,
    required EventsChannelFactory channelFactory,
    this.onAuthExpired,
  }) : _channelFactory = channelFactory;

  final MirrorDatabase db;
  final WaxDeckRepository repository;
  final EventsChannelFactory _channelFactory;

  /// Called when the server answers 401: credentials are gone and the
  /// engine stops; the auth layer owns what happens next.
  final void Function()? onAuthExpired;

  final _status = StreamController<SyncStatus>.broadcast();
  final _catalogChanged = StreamController<void>.broadcast();
  final _playStateChanged = StreamController<String>.broadcast();
  final _serverEvents = StreamController<ServerSyncEvent>.broadcast();

  SyncStatus _current = const SyncStatus(connection: SyncConnection.offline);
  EventsChannel? _channel;
  Timer? _reconnect;
  bool _running = false;
  int _backoffSeconds = 1;
  Future<void> _work = Future.value();

  /// Engine status, replayed to new listeners via [current].
  Stream<SyncStatus> get status => _status.stream;
  SyncStatus get current => _current;

  /// Whether [start] has been called (and [stop] has not). An engine
  /// that never started reports offline without meaning it.
  bool get started => _running;

  /// Fires after mirror rows changed (drift watches also work; these
  /// are for invalidating server-backed views).
  Stream<void> get catalogChanged => _catalogChanged.stream;

  /// Pids whose per-user playback state moved: an item's own state, or
  /// an artist or album whose star or rating changed. Consumers treat it
  /// as an invalidation signal, not a payload.
  Stream<String> get playStateChanged => _playStateChanged.stream;

  /// Every server-state change this engine pulled *while running*, as it
  /// arrived.
  ///
  /// The engine already reads and discriminates these to keep its mirror
  /// current; publishing them costs nothing and saves a second consumer
  /// (the notifications bell) from running its own cursor over the same
  /// stream. Broadcast and not replayed: a listener attached later hears
  /// what happens next, which is what a session-scoped surface means.
  ///
  /// The catch-up walk is deliberately silent. This engine's cursor is
  /// persisted, so its first pull of a session covers everything since
  /// the last launch - a week of it, if the app has been closed a week -
  /// and announcing that as it arrives would report a backlog as though
  /// it had just happened. A client with no engine mints its cursor and
  /// reports nothing from its first pull for exactly the same reason;
  /// this is that rule on the other transport, rather than a difference
  /// decided by which build somebody is running.
  Stream<ServerSyncEvent> get serverEvents => _serverEvents.stream;

  /// Pids whose audio the server cannot give back.
  ///
  /// A `delete` entry means one of two things and the server says which:
  /// `removed` is audio deleted outright or a catalog row dropped,
  /// `hidden` is a transition this caller can come back from (deleted to
  /// the trash, a grant they lost). Only the first is published, because
  /// the one thing anybody does with it is reclaim what was downloaded,
  /// and doing that on a `hidden` would cost the whole transfer again the
  /// moment somebody restored the item.
  ///
  /// The pids are the mirror's own, not the wire's: a tombstone for a
  /// vanished item cannot name its kind and carries the track prefix
  /// whatever it was.
  ///
  /// Published rather than acted on: the mirror is this package's job,
  /// and the downloads store and the artwork pins are the app's. An
  /// unrecognised reason is treated as `hidden` and stays unpublished,
  /// which is the half that reclaims nothing. **Consumers must reclaim
  /// one pid at a time**: removing two downloads concurrently lets each
  /// see the other's row and conclude a shared file is still referenced,
  /// which leaves it on disk with nothing pointing at it.
  Stream<String> get itemsRemoved => _itemsRemoved.stream;

  final _itemsRemoved = StreamController<String>.broadcast();

  /// Whether the first walk of this session has been made, after which
  /// what arrives is news rather than backlog.
  bool _caughtUp = false;

  /// Starts the engine: reconcile now, then follow invalidations.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _connect();
  }

  Future<void> stop() async {
    _running = false;
    _reconnect?.cancel();
    await _channel?.close();
    _channel = null;
    _setStatus(SyncConnection.offline);
  }

  void dispose() {
    stop();
    _status.close();
    _catalogChanged.close();
    _playStateChanged.close();
    _serverEvents.close();
    _itemsRemoved.close();
  }

  void _setStatus(SyncConnection c) {
    _current = SyncStatus(
      connection: c,
      lastSyncAt: c == SyncConnection.connected
          ? DateTime.now()
          : _current.lastSyncAt,
    );
    if (!_status.isClosed) _status.add(_current);
  }

  /// Serializes sync work: reconcile, pulls, and flushes never overlap.
  Future<T> _serialized<T>(Future<T> Function() body) {
    final next = _work.then((_) => body());
    _work = next.then((_) {}, onError: (_) {});
    return next;
  }

  /// Control-plane frames (anything that is not invalidate/resync)
  /// hand off here: the app's Connect layer speaks the player command
  /// bus over this same socket.
  void Function(Map<String, Object?> frame)? onControlFrame;

  /// Player-topic invalidations: endpoint and session lists changed.
  /// No cursor and no mirror half; the lists always answer current
  /// truth, so the hint is all there is.
  void Function()? onPlayerInvalidate;

  /// Radio-topic invalidations: artwork the server was fetching for an
  /// announced title landed. No cursor and no mirror half; a listener
  /// re-reads play-info, and one not tuned to a station ignores it.
  void Function()? onRadioInvalidate;

  /// Fires after each successful (re)connect, once the subscribe frame
  /// is on the wire; the Connect layer re-registers its endpoint and
  /// re-watches here.
  void Function()? onConnected;

  /// Sends one control frame on the live socket. False when offline.
  bool sendControl(Map<String, Object?> frame) {
    final channel = _channel;
    if (channel == null) return false;
    return channel.send(jsonEncode(frame));
  }

  void _connect() {
    if (!_running) return;
    _setStatus(SyncConnection.connecting);
    _channel = _channelFactory(
      onFrame: _onFrame,
      onDone: _onChannelDown,
      subscribe: () async {
        final cursors = await _cursors();
        return jsonEncode({
          if (cursors.catalogSince != null)
            'catalogSince': cursors.catalogSince,
          if (cursors.serverSince != null) 'serverSince': cursors.serverSince,
        });
      },
    );
    _channel!
        .connect()
        .then((_) async {
          _backoffSeconds = 1;
          _setStatus(SyncConnection.connected);
          onConnected?.call();
          await _serialized(reconcile);
        })
        .catchError((Object e) {
          _onChannelDown();
        });
  }

  void _onChannelDown() {
    if (!_running) return;
    _channel = null;
    _setStatus(SyncConnection.offline);
    _reconnect?.cancel();
    final delay = Duration(seconds: _backoffSeconds);
    _backoffSeconds = math.min(_backoffSeconds * 2, 60);
    _reconnect = Timer(delay, _connect);
  }

  void _onFrame(String data) {
    Map<String, Object?> frame;
    try {
      frame = jsonDecode(data) as Map<String, Object?>;
    } on FormatException {
      return;
    }
    switch (frame['type']) {
      case 'invalidate':
        switch (frame['topic']) {
          case 'catalog':
            _serialized(pullCatalog);
          case 'user':
            _serialized(pullServer);
          case 'player':
            onPlayerInvalidate?.call();
          case 'radio':
            onRadioInvalidate?.call();
        }
      case 'resync':
        final topic = frame['topic'];
        _serialized(() async {
          if (topic == null || topic == 'catalog') await resyncCatalog();
          if (topic == null || topic == 'user') await _remintServer();
        });
      default:
        // Command-bus frames route to the Connect layer; anything it
        // does not recognize either is ignored by contract.
        onControlFrame?.call(frame);
    }
  }

  /// Reconcile after (re)connecting: flush the offline queues first so
  /// the pulls that follow already see the winners, then catch both
  /// mirror halves up.
  Future<void> reconcile() async {
    try {
      await flushOutbox();
      await _ensureCatalogMirror();
      await pullServer();
      _setStatus(SyncConnection.connected);
    } on WaxDeckApiException catch (e) {
      _handleApiFailure(e);
    }
  }

  Future<({String? catalogSince, String? serverSince})> _cursors() async {
    final row = await db.select(db.syncCursors).getSingleOrNull();
    return (catalogSince: row?.catalogSince, serverSince: row?.serverSince);
  }

  Future<void> _saveCatalogCursor(String since) async {
    await db
        .into(db.syncCursors)
        .insertOnConflictUpdate(
          SyncCursorsCompanion(id: const Value(1), catalogSince: Value(since)),
        );
  }

  Future<void> _saveServerCursor(String since) async {
    await db
        .into(db.syncCursors)
        .insertOnConflictUpdate(
          SyncCursorsCompanion(id: const Value(1), serverSince: Value(since)),
        );
  }

  /// Snapshot when the mirror has no cursor yet; delta otherwise.
  Future<void> _ensureCatalogMirror() async {
    final cursors = await _cursors();
    if (cursors.catalogSince == null) {
      await _snapshotCatalog();
    } else {
      await pullCatalog();
    }
  }

  Future<void> _snapshotCatalog() async {
    String? cursor;
    String? since;
    final rows = <MirrorItemsCompanion>[];
    while (true) {
      final page = await repository.syncCatalog(cursor: cursor, limit: 500);
      // Sync from the FIRST page's cursor: it is the one captured
      // before anything was read, so a change landing mid-snapshot
      // falls inside the first delta instead of between two cursors.
      since ??= page.nextSince;
      for (final e in page.entries) {
        final item = e.item;
        if (e.op != 'upsert' || item == null) continue;
        rows.add(_itemRow(item));
      }
      if (page.nextCursor == null) break;
      cursor = page.nextCursor;
    }
    await db.transaction(() async {
      await db.delete(db.mirrorItems).go();
      await db.batch((b) => b.insertAllOnConflictUpdate(db.mirrorItems, rows));
    });
    await _saveCatalogCursor(since);
    _catalogChanged.add(null);
  }

  /// Pulls catalog deltas to the tail. A sync-reset drops the mirror
  /// and snapshots again.
  Future<void> pullCatalog() async {
    final cursors = await _cursors();
    var since = cursors.catalogSince;
    if (since == null) {
      await _snapshotCatalog();
      return;
    }
    try {
      var changed = false;
      while (true) {
        final page = await repository.syncCatalog(since: since);
        for (final e in page.entries) {
          switch (e.op) {
            case 'upsert':
              final item = e.item;
              if (item == null) continue;
              await db
                  .into(db.mirrorItems)
                  .insertOnConflictUpdate(_itemRow(item));
              changed = true;
            case 'delete':
              // Tombstones match on the ULID; the prefix carries no
              // meaning once the item is gone.
              final ulid = _ulidOf(e.pid);
              // Read before the delete, because the mirror row is what
              // knows the pid everything else stored. A tombstone for an
              // item that is genuinely gone cannot name its kind, so it
              // carries the track prefix whatever the item was - and a
              // download or an artwork pin for an audiobook was written
              // under `bk-`. Reclaiming on the wire pid would miss every
              // one of them.
              // Read only for the branch that uses it, and still before
              // the delete. `hidden` is the common tombstone - it is what
              // trashing sends -
              // and reading a row to discard it costs one round trip per
              // item: two hundred of them for a discography.
              final rows = e.reason == 'removed'
                  ? await (db.select(
                      db.mirrorItems,
                    )..where((t) => t.ulid.equals(ulid))).get()
                  : const <MirrorItem>[];
              await (db.delete(
                db.mirrorItems,
              )..where((t) => t.ulid.equals(ulid))).go();
              // The row goes either way; the bytes only when the catalog
              // has genuinely dropped it.
              if (e.reason == 'removed') {
                // The wire pid when nothing was mirrored under that ULID,
                // which is not the same as nothing to reclaim: a mirror
                // reset re-snapshots without the archived items, so a
                // later tombstone for one finds no row to name it. A
                // reclaim for a pid this client never downloaded is a
                // no-op, so the fallback costs nothing and rescues the
                // case where the stored pid did carry the track prefix.
                if (rows.isEmpty) {
                  _itemsRemoved.add(e.pid);
                }
                for (final row in rows) {
                  _itemsRemoved.add(row.pid);
                }
              }
              changed = true;
            // Unrecognized ops are dropped by contract.
          }
        }
        since = page.nextSince;
        if (!page.more) break;
      }
      await _saveCatalogCursor(since);
      if (changed) _catalogChanged.add(null);
    } on WaxDeckApiException catch (e) {
      if (e.code == 'sync-reset') {
        await resyncCatalog();
        return;
      }
      _handleApiFailure(e);
    }
  }

  /// Drops the catalog mirror and re-mirrors from a fresh snapshot.
  Future<void> resyncCatalog() async {
    await db
        .into(db.syncCursors)
        .insertOnConflictUpdate(
          const SyncCursorsCompanion(id: Value(1), catalogSince: Value(null)),
        );
    await _snapshotCatalog();
  }

  /// Pulls the caller's server-state deltas; play states land in the
  /// mirror. A sync-reset re-mints and re-hydrates downloaded items.
  Future<void> pullServer() async {
    final cursors = await _cursors();
    var since = cursors.serverSince;
    if (since == null) {
      await _remintServer();
      return;
    }
    try {
      while (true) {
        final page = await repository.syncServer(since: since);
        for (final ev in page.events) {
          if (_caughtUp) _serverEvents.add(ev);
          if (ev.kind == 'play-state' && ev.playState != null) {
            await _storePlayState(ev.playState!);
            _playStateChanged.add(ev.playState!.pid);
          } else if (ev.kind == 'entity-state' && ev.pid != null) {
            // A marker: an artist or album star or rating moved. There
            // is nothing to mirror (entity state is a live read, and the
            // mirror is item-scoped), so it only announces the pid to
            // refetch.
            _playStateChanged.add(ev.pid!);
          }
          // prefs events invalidate through catalogChanged consumers
          // watching prefs; the prefs controller refetches on its own.
        }
        since = page.nextSince;
        if (!page.more) break;
      }
      await _saveServerCursor(since);
      _caughtUp = true;
    } on WaxDeckApiException catch (e) {
      if (e.code == 'sync-reset') {
        await _remintServer();
        return;
      }
      _handleApiFailure(e);
    }
  }

  /// Mints a fresh server cursor and re-hydrates play states for the
  /// items this device holds offline (play states only matter for
  /// items a client keeps).
  Future<void> _remintServer() async {
    final page = await repository.syncServer();
    await _saveServerCursor(page.nextSince);
    // A minted cursor has nothing behind it, so everything after this is
    // news: without this the walk *after* a fresh install or a reset
    // would be swallowed as though it were the backlog.
    _caughtUp = true;
    final held =
        await (db.selectOnly(db.downloadRecords, distinct: true)
              ..addColumns([db.downloadRecords.pid]))
            .map((r) => r.read(db.downloadRecords.pid)!)
            .get();
    for (var i = 0; i < held.length; i += 500) {
      final batch = held.sublist(i, math.min(i + 500, held.length));
      final states = await repository.listPlayStates(batch);
      for (final st in states) {
        await _storePlayState(st);
        _playStateChanged.add(st.pid);
      }
    }
  }

  /// The mirrored play state for one item, or null when never synced.
  /// Offline resume reads this instead of the server.
  Future<PlayState?> localPlayState(String pid) async {
    final row = await (db.select(
      db.mirrorPlayStates,
    )..where((t) => t.pid.equals(pid))).getSingleOrNull();
    if (row == null) return null;
    return PlayState(
      pid: row.pid,
      positionMs: row.positionMs,
      played: row.played,
      finished: row.finished,
      playCount: row.playCount,
      lastPlayedAt: row.lastPlayedAt,
      starred: row.starred,
      rating: row.rating,
      updatedAt: row.updatedAt,
    );
  }

  Future<void> _storePlayState(PlayState st) async {
    await db
        .into(db.mirrorPlayStates)
        .insertOnConflictUpdate(
          MirrorPlayStatesCompanion(
            pid: Value(st.pid),
            positionMs: Value(st.positionMs),
            played: Value(st.played),
            finished: Value(st.finished),
            playCount: Value(st.playCount),
            lastPlayedAt: Value(st.lastPlayedAt),
            starred: Value(st.starred),
            rating: Value(st.rating),
            updatedAt: Value(st.updatedAt),
          ),
        );
  }

  // --- the offline outbox ----------------------------------------------------

  /// Runs one outbox write, dropped once the mirror is closed: a
  /// playback session's unawaited shutdown checkpoint can arrive after
  /// container teardown has closed the database, and a position with
  /// nowhere left to land is not worth an uncaught error on the way
  /// out. The gate is the mirror's own lifetime, not this engine's - a
  /// server address change rebuilds the engine while the mirror stays
  /// open, and a session holding the old engine must keep queueing.
  /// While the mirror is open, every failure still surfaces; drift does
  /// not export its closed-channel exception type, so the narrowing is
  /// this state check rather than an `on` clause.
  Future<void> _outboxWrite(Future<void> Function() body) async {
    if (db.closed) return;
    try {
      await body();
    } catch (_) {
      if (!db.closed) rethrow;
    }
  }

  /// Replaces any queued mutation of the same kind for the same item:
  /// the outbox carries final intents, not history, so an hour of
  /// offline checkpoints replays as one write, not seven hundred.
  Future<void> _coalesce(String kind, String pid) async {
    await (db.delete(
      db.outboxMutations,
    )..where((t) => t.kind.equals(kind) & t.pid.equals(pid))).go();
  }

  /// Queues a position checkpoint (also applied to the local mirror so
  /// offline UI reflects it immediately).
  Future<void> queueCheckpoint(String pid, int positionMs) =>
      _outboxWrite(() async {
        await _coalesce('position', pid);
        await db
            .into(db.outboxMutations)
            .insert(
              OutboxMutationsCompanion.insert(
                kind: 'position',
                pid: pid,
                positionMs: Value(positionMs),
                recordedAt: DateTime.now(),
              ),
            );
        await db.customStatement(
          'INSERT INTO mirror_play_states (pid, position_ms) VALUES (?, ?) '
          'ON CONFLICT(pid) DO UPDATE SET position_ms = excluded.position_ms',
          [pid, positionMs],
        );
      });

  Future<void> queueStar(String pid, bool starred) => _outboxWrite(() async {
    await _coalesce('star', pid);
    await db
        .into(db.outboxMutations)
        .insert(
          OutboxMutationsCompanion.insert(
            kind: 'star',
            pid: pid,
            starred: Value(starred),
            recordedAt: DateTime.now(),
          ),
        );
    await db.customStatement(
      'INSERT INTO mirror_play_states (pid, starred) VALUES (?, ?) '
      'ON CONFLICT(pid) DO UPDATE SET starred = excluded.starred',
      [pid, starred ? 1 : 0],
    );
  });

  Future<void> queueRating(String pid, int? rating) => _outboxWrite(() async {
    await _coalesce('rating', pid);
    await db
        .into(db.outboxMutations)
        .insert(
          OutboxMutationsCompanion.insert(
            kind: 'rating',
            pid: pid,
            rating: Value(rating),
            recordedAt: DateTime.now(),
          ),
        );
    await db.customStatement(
      'INSERT INTO mirror_play_states (pid, rating) VALUES (?, ?) '
      'ON CONFLICT(pid) DO UPDATE SET rating = excluded.rating',
      [pid, rating],
    );
  });

  /// Queues a star on a catalog entity (an artist or an album).
  ///
  /// No mirror write: mirror_play_states is the item play-state cache,
  /// and an entity star is its own fact, not a member's. The winning
  /// value comes back through the server stream on reconnect.
  Future<void> queueEntityStar(String pid, bool starred) =>
      _outboxWrite(() async {
        await _coalesce('entity-star', pid);
        await db
            .into(db.outboxMutations)
            .insert(
              OutboxMutationsCompanion.insert(
                kind: 'entity-star',
                pid: pid,
                starred: Value(starred),
                recordedAt: DateTime.now(),
              ),
            );
      });

  /// Queues a rating on a catalog entity; see [queueEntityStar].
  Future<void> queueEntityRating(String pid, int? rating) =>
      _outboxWrite(() async {
        await _coalesce('entity-rating', pid);
        await db
            .into(db.outboxMutations)
            .insert(
              OutboxMutationsCompanion.insert(
                kind: 'entity-rating',
                pid: pid,
                rating: Value(rating),
                recordedAt: DateTime.now(),
              ),
            );
      });

  /// Queues a finished listen session; the session id is the
  /// idempotency key, so a duplicate flush can never double-count.
  Future<void> queueListen(ListenSession session) => _outboxWrite(() async {
    await db
        .into(db.outboxListens)
        .insert(
          OutboxListensCompanion.insert(
            sessionId: session.sessionId,
            pid: session.pid,
            startedAt: session.startedAt,
            msPlayed: session.msPlayed,
            finished: Value(session.finished),
            client: Value(session.client ?? ''),
            skippedMs: Value(session.skippedMs),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  });

  /// Replays the queues in recorded order. Mutations carry their
  /// recorded times; the server reconciles per medium and the winning
  /// state comes back through [pullServer]. Entries are deleted only
  /// after their replay succeeds, so a crash mid-flush retries safely.
  Future<void> flushOutbox() async {
    final mutations = await (db.select(
      db.outboxMutations,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    for (final m in mutations) {
      try {
        switch (m.kind) {
          case 'position':
            await repository.putPlayState(
              m.pid,
              m.positionMs ?? 0,
              recordedAt: m.recordedAt,
            );
          case 'star':
            await repository.setStar(
              m.pid,
              m.starred ?? false,
              recordedAt: m.recordedAt,
            );
          case 'rating':
            await repository.setRating(
              m.pid,
              m.rating,
              recordedAt: m.recordedAt,
            );
          case 'entity-star':
            await repository.setEntityStar(
              m.pid,
              m.starred ?? false,
              recordedAt: m.recordedAt,
            );
          case 'entity-rating':
            await repository.setEntityRating(
              m.pid,
              m.rating,
              recordedAt: m.recordedAt,
            );
        }
      } on WaxDeckApiException catch (e) {
        if (_permanent(e)) {
          // The item is gone or the write is invalid forever; keeping
          // the entry would wedge the queue.
        } else {
          rethrow;
        }
      }
      await (db.delete(
        db.outboxMutations,
      )..where((t) => t.id.equals(m.id))).go();
    }

    final listens = await db.select(db.outboxListens).get();
    if (listens.isNotEmpty) {
      for (var i = 0; i < listens.length; i += 500) {
        final batch = listens.sublist(i, math.min(i + 500, listens.length));
        await repository.reportListens([
          for (final l in batch)
            ListenSession(
              sessionId: l.sessionId,
              pid: l.pid,
              startedAt: l.startedAt,
              msPlayed: l.msPlayed,
              skippedMs: l.skippedMs,
              finished: l.finished,
              client: l.client.isEmpty ? null : l.client,
            ),
        ]);
        for (final l in batch) {
          await (db.delete(
            db.outboxListens,
          )..where((t) => t.sessionId.equals(l.sessionId))).go();
        }
      }
    }
  }

  bool _permanent(WaxDeckApiException e) {
    return e.code == 'not-found' || e.code == 'invalid-request';
  }

  void _handleApiFailure(WaxDeckApiException e) {
    if (e.statusCode == 401) {
      onAuthExpired?.call();
      stop();
      return;
    }
    // Transient: drop to offline; the reconnect loop retries.
    _channel?.close();
  }

  MirrorItemsCompanion _itemRow(ItemSummary item) {
    return MirrorItemsCompanion.insert(
      pid: item.pid,
      ulid: _ulidOf(item.pid),
      mediaType: item.mediaType.wireName,
      title: item.title,
      artist: Value(item.artist),
      album: Value(item.album),
      durationMs: item.durationMs,
      sortKey: item.title.toLowerCase(),
    );
  }

  static String _ulidOf(String pid) {
    final i = pid.indexOf('-');
    return i < 0 ? pid : pid.substring(i + 1);
  }
}
