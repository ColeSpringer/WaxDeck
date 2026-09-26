import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:waxdeck_api/waxdeck_api.dart';

import 'database.dart';
import 'downloads_port.dart';
import 'mirror_pages.dart';
import 'transfer_engine.dart';
import 'transfer_engine_io.dart'
    if (dart.library.js_interop) 'transfer_engine_stub.dart';

/// Where one file of an item stands. Only the manager moves a file between
/// stages: the engine's reports of pausing and running say what happened,
/// not who holds the file now.
enum _Stage {
  /// In the manager's queue; the engine has not seen it.
  queued,

  /// Handed to the engine.
  running,

  /// Paused by the gate, which wakes it.
  parked,

  /// Paused by the listener, who wakes it.
  stopped,
}

/// One unfinished file of an item.
class _Part {
  _Part(this.index, this.fileName);

  final int index;
  final String fileName;
  var stage = _Stage.queued;
  String? taskId;

  /// When the URL its transfer holds stops working, on this device's clock.
  DateTime? staleAt;

  /// 401s since it last moved, so a URL that fails fresh is not renewed
  /// forever.
  var renewals = 0;
}

/// An item with files still to fetch.
class _Item {
  _Item(this.pid);

  final String pid;

  /// Its unfinished files, in file order.
  final parts = <_Part>[];

  var files = 0;
  var title = '';

  /// The listener's pause, which the rows keep across a restart.
  var paused = false;

  DownloadInfo? info;

  /// When [info]'s URLs stop working.
  DateTime? staleAt;

  var fetching = false;
  var failures = 0;
  Timer? retry;
}

/// The download manager: a queue of files handed to a [TransferEnginePort]
/// one per item, a few items at a time, and the records of what is on
/// disk. Files are named by essence hash, so a retag never costs a fetch.
class BackgroundDownloadManager implements DownloadManagerPort {
  /// An essence hash (`sha256/mp3-frames-v1:<hex>`) as a portable file
  /// name stem. Percent-escaped, `%` included, so two hashes can never
  /// share a name and so a file that [_discard] thinks nobody else holds.
  static String _safeStem(String essenceHash) {
    final out = StringBuffer();
    for (final byte in utf8.encode(essenceHash)) {
      if (_portableNameByte(byte)) {
        out.writeCharCode(byte);
      } else {
        out.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return out.toString();
  }

  /// Whether [byte] is an ASCII character every filesystem WaxDeck runs
  /// on accepts in a name. `%` is deliberately absent: it is the escape
  /// character above, so it has to escape itself.
  static bool _portableNameByte(int byte) =>
      (byte >= 0x30 && byte <= 0x39) || // 0-9
      (byte >= 0x41 && byte <= 0x5A) || // A-Z
      (byte >= 0x61 && byte <= 0x7A) || // a-z
      byte == 0x2E || // .
      byte == 0x5F || // _
      byte == 0x2D; // -

  BackgroundDownloadManager({
    required this.db,
    required this.repository,
    TransferEnginePort? engine,
    required this.copy,
    this.gate = const OpenGate(),
    this.clock = DateTime.now,
    this.maxRunning = 3,
    this.timer = Timer.new,
  }) : engine = engine ?? BackgroundTransferEngine() {
    _events = this.engine.events.listen(
      (event) => _later(() => _onEvent(event)),
    );
    _gateChanges = gate.changes.listen((open) {
      _open = open;
      _later(open ? _opened : _shut);
    });
  }

  final MirrorDatabase db;

  /// Holds transfers back while it is shut: nothing starts, what runs
  /// parks, and both go on when it opens.
  final TransferGate gate;

  /// A notice's words, asked for as each item starts so they follow the
  /// app's language.
  final DownloadCopy Function() copy;

  final DateTime Function() clock;

  /// How many items fetch at once, each one file at a time.
  final int maxRunning;

  /// Schedules a retry; a seam for tests.
  final Timer Function(Duration, void Function()) timer;

  /// Resolved per call, never captured: the manager outlives a server
  /// switch on purpose (it owns every in-flight transfer), so the
  /// repository it would have captured can go stale under it.
  final WaxDeckRepository Function() repository;

  final TransferEnginePort engine;

  final _progress = StreamController<DownloadProgress>.broadcast();
  late final StreamSubscription<TransferEvent> _events;
  late final StreamSubscription<bool> _gateChanges;

  /// The gate's last answer; null until it has given one.
  bool? _open;

  /// Items with files to fetch, in the order they were asked for.
  final _items = <String, _Item>{};

  /// The part behind each transfer the engine holds, and its item.
  final _byTask = <String, (_Item, _Part)>{};

  /// Download-info reads under way, which [settled] waits for.
  final _reads = <Future<void>>{};

  static const _maxRenewals = 3;

  var _askedForNotifications = false;
  final _rationale = StreamController<void>.broadcast();
  Future<void>? _asking;

  /// The tail of the bookkeeping chain, which every read-then-write over
  /// the records and the parts runs through one at a time: two discards
  /// together would each see the other's row and keep the bytes.
  Future<void> _work = Future<void>.value();

  /// Runs [work] once everything queued has finished. Its error goes to
  /// the caller alone, so the chain's tail stays clean.
  Future<T> _serialize<T>(Future<T> Function() work) {
    final queued = _work.then((_) => work());
    _work = queued.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return queued;
  }

  /// Queues [work] with nobody waiting on it, so its error is reported
  /// rather than lost.
  void _later(Future<void> Function() work) {
    _serialize(work).catchError((Object e, StackTrace s) {
      Zone.current.handleUncaughtError(e, s);
    });
  }

  /// Completes once all bookkeeping queued so far has finished, reads of
  /// download-info included.
  Future<void> get settled async {
    while (true) {
      final work = _work;
      await Future.wait(<Future<void>>[work, ..._reads]);
      if (identical(work, _work) && _reads.isEmpty) return;
    }
  }

  @override
  Stream<DownloadProgress> get progress => _progress.stream;

  void dispose() {
    _events.cancel();
    _gateChanges.cancel();
    for (final item in _items.values) {
      item.retry?.cancel();
    }
    _rationale.close();
    engine.dispose();
    _progress.close();
  }

  @override
  Future<void> download(String pid) async {
    final info = await repository().getDownloadInfo(pid);
    final received = clock();
    if (info.files.isEmpty) return;
    unawaited(_ensureNotifications());
    await _serialize(() async {
      await _adopt(pid, info, received);
      await _pump();
    });
  }

  /// Takes an item's download-info: files already on disk catch their
  /// records up, and the rest are recorded and queued.
  Future<void> _adopt(String pid, DownloadInfo info, DateTime received) async {
    final item = _items[pid] ?? _Item(pid);
    final parts = <_Part>[];
    for (var i = 0; i < info.files.length; i++) {
      final f = info.files[i];
      final existing =
          await (db.select(db.downloadRecords)
                ..where((t) => t.pid.equals(pid) & t.fileIndex.equals(i)))
              .getSingleOrNull();
      if (existing != null &&
          existing.state == 'complete' &&
          existing.essenceHash == f.essenceHash) {
        // Same audio on disk; a retag changes nothing about the bytes. The
        // record still catches up, which is how an item downloaded before
        // durations existed gains them without re-fetching.
        if (existing.durationMs != f.durationMs || existing.etag != f.etag) {
          await (db.update(
            db.downloadRecords,
          )..where((t) => t.pid.equals(pid) & t.fileIndex.equals(i))).write(
            DownloadRecordsCompanion(
              durationMs: Value(f.durationMs),
              etag: Value(f.etag),
            ),
          );
        }
        continue;
      }
      final fileName = '${_safeStem(f.essenceHash)}${p.extension(f.fileName)}';
      final known = item.parts
          .where((part) => part.index == i && part.fileName == fileName)
          .firstOrNull;
      if (known != null) {
        parts.add(known);
        continue;
      }
      await db
          .into(db.downloadRecords)
          .insertOnConflictUpdate(
            DownloadRecordsCompanion.insert(
              pid: pid,
              fileIndex: i,
              essenceHash: f.essenceHash,
              etag: f.etag,
              fileName: fileName,
              localPath: '',
              sizeBytes: f.sizeBytes,
              durationMs: Value(f.durationMs),
              state: item.paused ? 'paused' : 'pending',
              spanStartMs: Value(info.spanStartMs),
              spanEndMs: Value(info.spanEndMs),
            ),
          );
      parts.add(_Part(i, fileName));
    }
    // Parts whose audio changed under them.
    await _drop([
      for (final part in item.parts)
        if (!parts.contains(part)) part,
    ]);
    item.parts
      ..clear()
      ..addAll(parts);
    if (parts.isEmpty) {
      _forget(item);
      return;
    }
    item
      ..info = info
      ..staleAt = _staleAt(info, received)
      ..files = info.files.length
      ..title =
          (await mirrorItemByPid(db, pid))?.title ?? info.files.first.fileName
      ..failures = 0
      ..retry?.cancel();
    _items[pid] = item;
    await _describe(item);
  }

  /// When [info]'s URLs stop working on this device's clock: the lifetime
  /// the server gave them, a minute early. A clock skewed past that gets
  /// ten minutes, and a 401 tells the rest.
  DateTime _staleAt(DownloadInfo info, DateTime received) {
    final life =
        info.expiresAt.difference(received) - const Duration(minutes: 1);
    return received.add(
      life > Duration.zero ? life : const Duration(minutes: 10),
    );
  }

  bool _fresh(DateTime? staleAt) =>
      staleAt != null && clock().isBefore(staleAt);

  /// Says how the item's transfers are announced: a notice a file, titled
  /// by the item, and only its last file says it is done.
  Future<void> _describe(_Item item) async {
    final words = copy();
    await engine.describe(TransferGroup(id: item.pid, copy: words));
    if (item.files > 1) {
      await engine.describe(
        TransferGroup(id: _partsOf(item.pid), copy: words, announceDone: false),
      );
    }
  }

  static String _partsOf(String pid) => '$pid.parts';

  Future<bool> _gateIsOpen() async => _open ??= await gate.isOpen();

  /// Whether the item takes one of the [maxRunning] places: a file of it
  /// moves, or its download-info is being read.
  static bool _moving(_Item item) =>
      item.fetching || item.parts.any((part) => part.stage == _Stage.running);

  /// Moves the queue while the gate is open: wakes what it parked and
  /// starts files, one per item and [maxRunning] items at a time. [first]
  /// goes ahead of the queue, keeping the place its read held.
  Future<void> _pump({_Item? first}) async {
    if (!await _gateIsOpen()) return;
    var moving = _items.values.where(_moving).length;
    for (final item in [?first, ..._items.values.where((i) => i != first)]) {
      if (moving >= maxRunning) return;
      if (item.paused || _moving(item) || _items[item.pid] != item) continue;
      final part =
          item.parts.where((p) => p.stage == _Stage.parked).firstOrNull ??
          item.parts.where((p) => p.stage == _Stage.queued).firstOrNull;
      if (part != null && await _go(item, part)) moving++;
    }
  }

  /// Wakes [part] or starts it, on a fresh URL where its own has expired,
  /// reading download-info first where it has to. Answers whether the item
  /// now takes a place.
  Future<bool> _go(_Item item, _Part part) async {
    final taskId = part.taskId;
    final info = item.info;
    final renew = !_fresh(part.staleAt);
    if ((taskId == null || renew) && (info == null || !_fresh(item.staleAt))) {
      return _read(item);
    }
    try {
      if (taskId != null && !renew) {
        await engine.resume(taskId);
      } else if (taskId != null) {
        final url = info!.files[part.index].url;
        await engine.resume(taskId, url: url, staleAt: item.staleAt);
      } else {
        final file = info!.files[part.index];
        final id = await engine.start(
          TransferRequest(
            url: file.url,
            fileName: part.fileName,
            pid: item.pid,
            group: part.index == item.files - 1 ? item.pid : _partsOf(item.pid),
            displayName: item.files > 1
                ? copy().part(item.title, part.index + 1, item.files)
                : file.fileName,
            staleAt: item.staleAt,
          ),
        );
        part.taskId = id;
        _byTask[id] = (item, part);
      }
    } on Object {
      await _giveUp(item.pid);
      return false;
    }
    part.stage = _Stage.running;
    if (renew) part.staleAt = item.staleAt;
    return true;
  }

  /// Reads an item's download-info off the chain, unless a failed read is
  /// waiting out its backoff. Answers whether a read is under way.
  bool _read(_Item item) {
    if (item.fetching) return true;
    if (item.retry?.isActive ?? false) return false;
    item.fetching = true;
    final done = _readInfo(item);
    _reads.add(done);
    unawaited(done.whenComplete(() => _reads.remove(done)));
    return true;
  }

  /// An answer for an item dropped meanwhile is thrown away; a failure
  /// other than not-found is asked again later, less often each time.
  Future<void> _readInfo(_Item item) async {
    DownloadInfo? info;
    Object? error;
    try {
      info = await repository().getDownloadInfo(item.pid);
    } on Object catch (e) {
      error = e;
    }
    final received = clock();
    await _serialize(() async {
      item.fetching = false;
      if (_items[item.pid] != item) return;
      if (info != null) {
        await _adopt(item.pid, info, received);
        return _pump(first: item);
      }
      if (error is WaxDeckApiException && error.code == 'not-found') {
        return _giveUp(item.pid);
      }
      item.retry = timer(_backoff(++item.failures), () => _later(_pump));
    });
  }

  /// A gate opening is a new connection: reads waiting out a failure go
  /// at once.
  Future<void> _opened() async {
    for (final item in _items.values) {
      item.retry?.cancel();
    }
    await _pump();
  }

  /// Thirty seconds, doubling up to ten minutes.
  static Duration _backoff(int failures) {
    final wait = Duration(seconds: 30 << (failures - 1).clamp(0, 5));
    const most = Duration(minutes: 10);
    return wait < most ? wait : most;
  }

  /// Parks what runs. A part the engine will not pause goes back in the
  /// queue: a shut gate means nothing moves.
  Future<void> _shut() async {
    for (final item in _items.values.toList()) {
      for (final part in item.parts.toList()) {
        if (part.stage != _Stage.running) continue;
        if (await engine.pause(part.taskId!)) {
          part.stage = _Stage.parked;
        } else {
          await _requeue(part);
        }
      }
    }
  }

  /// Stops the transfers behind [parts], forgetting them first so their
  /// cancellations do not read as the item failing.
  Future<void> _drop(Iterable<_Part> parts) async {
    final ids = <String>[];
    for (final part in parts) {
      final id = part.taskId;
      if (id == null) continue;
      _byTask.remove(id);
      ids.add(id);
      part
        ..taskId = null
        ..staleAt = null;
    }
    if (ids.isNotEmpty) await engine.cancel(ids);
  }

  Future<void> _requeue(_Part part) async {
    await _drop([part]);
    part.stage = _Stage.queued;
  }

  void _forget(_Item item) {
    if (_items[item.pid] == item) _items.remove(item.pid);
    item.retry?.cancel();
  }

  /// Once a run, at the first download: the OS asks where it never has,
  /// and where it was refused but may ask again, the app says why first.
  Future<void> _ensureNotifications() async {
    if (_askedForNotifications) return;
    _askedForNotifications = true;
    switch (await engine.notificationPermission()) {
      case NotificationPermission.undetermined:
        await requestNotificationPermission();
      case NotificationPermission.deniedExplainable:
        if (!_rationale.isClosed) _rationale.add(null);
      case NotificationPermission.granted:
      case NotificationPermission.denied:
        break;
    }
  }

  @override
  Stream<void> get notificationRationale => _rationale.stream;

  /// One at a time: a second request while one is up fails on Android.
  @override
  Future<void> requestNotificationPermission() => _asking ??= engine
      .requestNotificationPermission()
      .whenComplete(() => _asking = null);

  /// Picks up what a previous run left, before the engine replays it: the
  /// rows say what is unfinished and what the listener paused, the
  /// plugin's records which transfers are still behind them.
  Future<void> recover() => _serialize(() async {
    try {
      var tracked = const <TrackedTransfer>[];
      try {
        tracked = await engine.trackedTransfers();
      } on Object {
        // Unreadable records: the rows alone say what to fetch.
      }
      final rows = await (db.select(
        db.downloadRecords,
      )..orderBy([(t) => OrderingTerm.asc(t.fileIndex)])).get();
      final held = _items.keys.toSet();
      for (final row in rows) {
        if (held.contains(row.pid)) continue;
        final item = _items.putIfAbsent(row.pid, () => _Item(row.pid));
        item.files++;
        if (row.state == 'complete') continue;
        if (row.state == 'paused') item.paused = true;
        item.parts.add(_Part(row.fileIndex, row.fileName));
      }
      _items.removeWhere((_, item) => item.parts.isEmpty);
      final stale = <String>[];
      for (final t in tracked) {
        final item = _items[t.pid];
        final part = item?.parts
            .where((p) => p.fileName == t.fileName && p.taskId == null)
            .firstOrNull;
        if (item == null || part == null) {
          stale.add(t.taskId);
          continue;
        }
        if (t.state == TransferState.complete) {
          stale.add(t.taskId);
          item.parts.remove(part);
          await _land(t.pid, t.fileName, t.path);
          continue;
        }
        part
          ..taskId = t.taskId
          ..staleAt = t.staleAt
          ..stage = t.state != TransferState.paused
              ? _Stage.running
              : item.paused
              ? _Stage.stopped
              : _Stage.parked;
        _byTask[t.taskId] = (item, part);
      }
      if (stale.isNotEmpty) await engine.cancel(stale);
      _items.removeWhere((_, item) => item.parts.isEmpty);
      for (final item in _items.values) {
        await _describe(item);
      }
    } finally {
      // Whatever the records said, the plugin still has to start.
      await engine.recover();
    }
    // A pause from before the restart holds what the OS went on with.
    for (final item in _items.values.where((item) => item.paused)) {
      await _hold(item);
    }
    if (await _gateIsOpen()) {
      await _pump();
    } else {
      await _shut();
    }
  });

  /// What the engine reports. A transfer this run holds no part for is
  /// placed by its own record: enough to land a completion, never to drop
  /// an item.
  Future<void> _onEvent(TransferEvent event) async {
    final held = _byTask[event.taskId];
    if (held == null) {
      final pid = event.pid;
      final fileName = event.fileName;
      if (event.state == TransferState.complete &&
          pid != null &&
          fileName != null) {
        await _land(pid, fileName, event.path);
      }
      return;
    }
    final (item, part) = held;
    switch (event.state) {
      case TransferState.complete:
        _byTask.remove(event.taskId);
        item.parts.remove(part);
        if (item.parts.isEmpty) _forget(item);
        await _land(item.pid, part.fileName, event.path);
        await _pump();
      case TransferState.failed:
        await _failed(item, part, event.httpStatus);
      // Its own cancels are forgotten first, so this came from outside:
      // the notification's cancel.
      case TransferState.canceled:
        await _giveUp(item.pid);
      case TransferState.paused:
      case TransferState.running:
        break;
      case null:
        part.renewals = 0;
        final done = item.files - item.parts.length;
        _emit(
          DownloadProgress(
            pid: item.pid,
            fraction: (done + (event.fraction ?? 0)) / item.files,
            complete: false,
          ),
        );
    }
  }

  /// A paused part that fails lost what it had fetched, so it goes back
  /// in the queue. A 401 is an expired URL: the part goes on at a fresh
  /// one. Anything else gives the item up.
  Future<void> _failed(_Item item, _Part part, int? status) async {
    if (part.stage == _Stage.parked || part.stage == _Stage.stopped) {
      await _requeue(part);
      await _pump();
      return;
    }
    if (status == 401 && part.renewals < _maxRenewals) {
      part
        ..renewals += 1
        ..stage = _Stage.parked
        ..staleAt = null;
      // Every URL of the item came from the same token.
      item.staleAt = null;
      await _pump();
      return;
    }
    await _giveUp(item.pid);
  }

  /// Whole or not at all: a left-behind `pending` row reads as a transfer
  /// forever, and dropping it alone would leave the parts that landed
  /// answering `isComplete`.
  Future<void> _giveUp(String pid) async {
    await _discard(pid);
    _emit(
      DownloadProgress(pid: pid, fraction: 0, complete: false, failed: true),
    );
  }

  /// Marks a file on disk, and says so once the item is whole.
  Future<void> _land(String pid, String fileName, String? path) async {
    await (db.update(
      db.downloadRecords,
    )..where((t) => t.pid.equals(pid) & t.fileName.equals(fileName))).write(
      DownloadRecordsCompanion(
        state: const Value('complete'),
        localPath: Value(path ?? ''),
      ),
    );
    if (await isComplete(pid)) {
      _emit(DownloadProgress(pid: pid, fraction: 1, complete: true));
    }
  }

  void _emit(DownloadProgress progress) {
    if (!_progress.isClosed) _progress.add(progress);
  }

  @override
  Future<bool> isComplete(String pid) async {
    final rows = await (db.select(
      db.downloadRecords,
    )..where((t) => t.pid.equals(pid))).get();
    return rows.isNotEmpty && rows.every((r) => r.state == 'complete');
  }

  @override
  Future<LocalPlayback?> localFor(String pid) async {
    final rows =
        await (db.select(db.downloadRecords)
              ..where((t) => t.pid.equals(pid))
              ..orderBy([(t) => OrderingTerm.asc(t.fileIndex)]))
            .get();
    if (rows.isEmpty || rows.any((r) => r.state != 'complete')) {
      return null;
    }
    for (final r in rows) {
      if (!File(r.localPath).existsSync()) {
        return null; // evicted outside our control; treat as absent
      }
    }
    return LocalPlayback(
      parts: <LocalPart>[
        for (final r in rows)
          LocalPart(path: r.localPath, durationMs: r.durationMs),
      ],
      spanStartMs: rows.first.spanStartMs,
      spanEndMs: rows.first.spanEndMs,
    );
  }

  @override
  Future<List<DownloadedItem>> stored() async {
    final rows = await (db.select(
      db.downloadRecords,
    )..orderBy([(t) => OrderingTerm.asc(t.fileIndex)])).get();
    final byPid = <String, List<DownloadRecord>>{};
    for (final r in rows) {
      (byPid[r.pid] ??= <DownloadRecord>[]).add(r);
    }
    return <DownloadedItem>[
      for (final MapEntry(key: pid, value: files) in byPid.entries)
        DownloadedItem(
          pid: pid,
          sizeBytes: files.fold(0, (sum, r) => sum + r.sizeBytes),
          files: files.length,
          complete: files.every((r) => r.state == 'complete'),
          paused: files.any((r) => r.state == 'paused'),
        ),
    ];
  }

  /// Two verbs on the port because the manager has two affordances (one
  /// on a transfer, one on bytes), one operation underneath: a
  /// half-downloaded item is not a downloaded item.
  @override
  Future<void> cancel(String pid) => _serialize(() => _discard(pid));

  @override
  Future<void> remove(String pid) => _serialize(() => _discard(pid));

  /// Holds the item until [resume]: its running file pauses and nothing
  /// more starts. The rows keep the pause across a restart.
  @override
  Future<bool> pause(String pid) => _serialize(() async {
    final item = _items[pid];
    if (item == null) return false;
    item.paused = true;
    await _hold(item);
    await _mark(pid, 'paused');
    return true;
  });

  /// Stops what of [item] moves, and takes what the gate parked from it.
  /// A part the engine will not pause goes back in the queue.
  Future<void> _hold(_Item item) async {
    for (final part in item.parts.toList()) {
      switch (part.stage) {
        case _Stage.running:
          if (await engine.pause(part.taskId!)) {
            part.stage = _Stage.stopped;
          } else {
            await _requeue(part);
          }
        case _Stage.parked:
          part.stage = _Stage.stopped;
        case _Stage.queued:
        case _Stage.stopped:
          break;
      }
    }
  }

  /// Lifts the listener's pause: its file goes on, on a fresh URL where
  /// its own has expired, once the gate lets it.
  @override
  Future<void> resume(String pid) => _serialize(() async {
    final item = _items[pid];
    if (item == null || !item.paused) return;
    item
      ..paused = false
      ..retry?.cancel();
    for (final part in item.parts) {
      if (part.stage == _Stage.stopped) part.stage = _Stage.parked;
    }
    await _mark(pid, 'pending');
    await _pump();
  });

  /// Sets the state of the item's unfinished rows.
  Future<void> _mark(String pid, String state) =>
      (db.update(
            db.downloadRecords,
          )..where((t) => t.pid.equals(pid) & t.state.equals('complete').not()))
          .write(DownloadRecordsCompanion(state: Value(state)));

  /// Drops everything this device holds for [pid]: the transfers in
  /// flight, the bytes on disk, and the records naming them.
  Future<void> _discard(String pid) async {
    // Before anything is read or unlinked: a transfer still running would
    // write its file back after the unlink and report completion against
    // a row that no longer exists.
    final item = _items[pid];
    if (item != null) {
      _forget(item);
      await _drop(item.parts);
    }
    final rows = await (db.select(
      db.downloadRecords,
    )..where((t) => t.pid.equals(pid))).get();
    // One at a time: the unlink asks whether another row holds the same
    // essence (CUE siblings share an image), which rows removed together
    // would each answer yes.
    for (final r in rows) {
      final shared =
          await (db.select(db.downloadRecords)..where(
                (t) =>
                    t.essenceHash.equals(r.essenceHash) &
                    t.pid.equals(pid).not(),
              ))
              .get();
      if (shared.isEmpty && r.localPath.isNotEmpty) {
        final f = File(r.localPath);
        if (f.existsSync()) {
          await f.delete();
        }
      }
    }
    await (db.delete(db.downloadRecords)..where((t) => t.pid.equals(pid))).go();
  }
}
