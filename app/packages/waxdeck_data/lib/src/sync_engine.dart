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
  Stream<String> get playStateChanged => _playStateChanged.stream;

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
        }
      case 'resync':
        final topic = frame['topic'];
        _serialized(() async {
          if (topic == null || topic == 'catalog') await resyncCatalog();
          if (topic == null || topic == 'user') await _remintServer();
        });
      // Unrecognized frame types are ignored by contract.
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
              await (db.delete(
                db.mirrorItems,
              )..where((t) => t.ulid.equals(ulid))).go();
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
          if (ev.kind == 'play-state' && ev.playState != null) {
            await _storePlayState(ev.playState!);
            _playStateChanged.add(ev.playState!.pid);
          }
          // prefs events invalidate through catalogChanged consumers
          // watching prefs; the prefs controller refetches on its own.
        }
        since = page.nextSince;
        if (!page.more) break;
      }
      await _saveServerCursor(since);
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
            starred: Value(st.starred),
            rating: Value(st.rating),
            updatedAt: Value(st.updatedAt),
          ),
        );
  }

  // --- the offline outbox ----------------------------------------------------

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
  Future<void> queueCheckpoint(String pid, int positionMs) async {
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
  }

  Future<void> queueStar(String pid, bool starred) async {
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
  }

  Future<void> queueRating(String pid, int? rating) async {
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
  }

  /// Queues a finished listen session; the session id is the
  /// idempotency key, so a duplicate flush can never double-count.
  Future<void> queueListen(ListenSession session) async {
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
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

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
