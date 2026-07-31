import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:waxdeck_api/waxdeck_api.dart';

import 'database.dart';
import 'downloads_port.dart';
import 'transfer_engine.dart';
import 'transfer_engine_io.dart'
    if (dart.library.js_interop) 'transfer_engine_stub.dart';

/// The download manager: which files an item needs, which are on disk, and
/// what the records say about them. Bytes move through a
/// [TransferEnginePort], which is the seam this class is tested through.
///
/// Files are named by essence hash, so a retag or a move server-side never
/// invalidates local bytes.
class BackgroundDownloadManager implements DownloadManagerPort {
  BackgroundDownloadManager({
    required this.db,
    required this.repository,
    required this.baseUrl,
    TransferEnginePort? engine,
    this.wifiOnly = _never,
  }) : engine = engine ?? BackgroundTransferEngine() {
    _events = this.engine.events.listen(_onEvent);
  }

  static bool _never() => false;

  /// Whether transfers should wait for an unmetered connection, asked
  /// each time one is started rather than captured once: this is a
  /// setting a listener changes, and the answer that matters is the one
  /// at the tap that queued the download.
  final bool Function() wifiOnly;

  final MirrorDatabase db;
  final WaxDeckRepository repository;

  /// The server origin download URLs resolve against (native builds
  /// always have an absolute one).
  final String baseUrl;

  final TransferEnginePort engine;

  final _progress = StreamController<DownloadProgress>.broadcast();
  late final StreamSubscription<TransferEvent> _events;

  /// Which item each transfer belongs to, and which transfers each item
  /// has in flight. Two directions of one fact, because both questions get
  /// asked: an event arrives with an id and needs its item, and stopping
  /// an item needs its ids.
  final _taskPids = <String, String>{};
  final _tasks = <String, Set<String>>{};

  /// The file name each transfer is writing, so a completion can find the
  /// row it belongs to. The plugin reports an id; the records are keyed by
  /// pid and name.
  final _taskFiles = <String, String>{};

  @override
  Stream<DownloadProgress> get progress => _progress.stream;

  void dispose() {
    _events.cancel();
    engine.dispose();
    _progress.close();
  }

  @override
  Future<void> download(String pid) async {
    final info = await repository.getDownloadInfo(pid);
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
      final fileName = '${f.essenceHash}${p.extension(f.fileName)}';
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
              state: 'pending',
              spanStartMs: Value(info.spanStartMs),
              spanEndMs: Value(info.spanEndMs),
            ),
          );
      final taskId = await engine.start(
        TransferRequest(url: f.url, fileName: fileName, wifiOnly: wifiOnly()),
      );
      _taskPids[taskId] = pid;
      _taskFiles[taskId] = fileName;
      (_tasks[pid] ??= <String>{}).add(taskId);
    }
  }

  Future<void> _onEvent(TransferEvent event) async {
    final pid = _taskPids[event.taskId];
    if (pid == null) return;
    switch (event.state) {
      case TransferState.complete:
        final fileName = _taskFiles[event.taskId];
        if (fileName != null) {
          await (db.update(db.downloadRecords)
                ..where((t) => t.pid.equals(pid) & t.fileName.equals(fileName)))
              .write(
                DownloadRecordsCompanion(
                  state: const Value('complete'),
                  localPath: Value(event.path ?? ''),
                ),
              );
        }
        _forget(pid, event.taskId);
        if (await isComplete(pid)) {
          _emit(DownloadProgress(pid: pid, fraction: 1, complete: true));
        }
      case TransferState.failed:
      case TransferState.canceled:
        _forget(pid, event.taskId);
        // Whole or not at all: a left-behind `pending` row reads as a
        // transfer forever, and dropping it alone would leave the parts
        // that landed answering `isComplete`.
        await _discard(pid);
        _emit(
          DownloadProgress(
            pid: pid,
            fraction: 0,
            complete: false,
            failed: true,
          ),
        );
      // Parked, not over: the task keeps its id and its mapping, because
      // resuming picks the same one back up.
      case TransferState.paused:
        break;
      case null:
        _emit(
          DownloadProgress(
            pid: pid,
            fraction: event.fraction ?? 0,
            complete: false,
          ),
        );
    }
  }

  void _emit(DownloadProgress progress) {
    if (!_progress.isClosed) _progress.add(progress);
  }

  /// Drops a transfer that has reached a terminal state from every map.
  ///
  /// Every one, because terminal means no further event can arrive for
  /// that id. Leaving the mappings behind would grow them for the life of
  /// the process, one entry per file ever transferred.
  void _forget(String pid, String taskId) {
    _taskPids.remove(taskId);
    _taskFiles.remove(taskId);
    final ids = _tasks[pid];
    if (ids == null) return;
    ids.remove(taskId);
    if (ids.isEmpty) _tasks.remove(pid);
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
    final out = <DownloadedItem>[];
    for (final entry in byPid.entries) {
      final files = entry.value;
      out.add(
        DownloadedItem(
          pid: entry.key,
          sizeBytes: files.fold(0, (sum, r) => sum + r.sizeBytes),
          files: files.length,
          complete: files.every((r) => r.state == 'complete'),
        ),
      );
    }
    return out;
  }

  /// Two verbs on the port because the manager has two affordances (one
  /// on a transfer, one on bytes), one operation underneath: a
  /// half-downloaded item is not a downloaded item.
  @override
  Future<void> cancel(String pid) => _discard(pid);

  @override
  Future<void> remove(String pid) => _discard(pid);

  /// Stops every transfer in flight for [pid] and forgets them. A task
  /// left running would land its file after the unlink and report against
  /// a row that is gone.
  Future<void> _stopTransfers(String pid) async {
    final ids = _tasks[pid]?.toList() ?? const <String>[];
    if (ids.isEmpty) return;
    await engine.cancel(ids);
    for (final id in ids) {
      _taskPids.remove(id);
      _taskFiles.remove(id);
    }
    _tasks.remove(pid);
  }

  @override
  Future<bool> pause(String pid) async {
    final ids = _tasks[pid]?.toList() ?? const <String>[];
    if (ids.isEmpty) return false;
    var paused = false;
    for (final id in ids) {
      paused = await engine.pause(id) || paused;
    }
    return paused;
  }

  @override
  Future<void> resume(String pid) async {
    for (final id in _tasks[pid]?.toList() ?? const <String>[]) {
      await engine.resume(id);
    }
  }

  /// Drops everything this device holds for [pid]: the transfers in
  /// flight, the bytes on disk, and the records naming them.
  Future<void> _discard(String pid) async {
    // Before anything is read or unlinked: a transfer still running would
    // write its file back after the unlink and report completion against
    // a row that no longer exists.
    await _stopTransfers(pid);
    final rows = await (db.select(
      db.downloadRecords,
    )..where((t) => t.pid.equals(pid))).get();
    // One at a time, and not a `Future.wait`. The unlink below asks
    // whether any *other* row still holds the same essence, so two items
    // sharing a file (CUE siblings share one image) removed concurrently
    // would each see the other's row still present, each decide the file
    // is shared, and leave it on disk forever.
    for (final r in rows) {
      // Another item may share the file (CUE siblings share one image);
      // only unlink when this was the last reference.
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
