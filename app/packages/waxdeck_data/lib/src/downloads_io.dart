import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:waxdeck_api/waxdeck_api.dart';

import 'database.dart';
import 'downloads_port.dart';

/// The real manager over background_downloader. Files land under the
/// app support directory, named by essence hash so a retag or move
/// server-side never invalidates local bytes.
class BackgroundDownloadManager implements DownloadManagerPort {
  BackgroundDownloadManager({
    required this.db,
    required this.repository,
    required this.baseUrl,
  }) {
    _updatesSub = FileDownloader().updates.listen(_onUpdate);
  }

  final MirrorDatabase db;
  final WaxDeckRepository repository;

  /// The server origin download URLs resolve against (native builds
  /// always have an absolute one).
  final String baseUrl;

  final _progress = StreamController<DownloadProgress>.broadcast();
  StreamSubscription<TaskUpdate>? _updatesSub;
  final _taskPids = <String, String>{}; // taskId -> pid

  @override
  Stream<DownloadProgress> get progress => _progress.stream;

  void dispose() {
    _updatesSub?.cancel();
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
        continue; // same audio already on disk; a retag changes nothing
      }
      final fileName = '${f.essenceHash}${p.extension(f.fileName)}';
      final task = DownloadTask(
        url: f.url,
        filename: fileName,
        directory: 'waxdeck/media',
        baseDirectory: BaseDirectory.applicationSupport,
        updates: Updates.statusAndProgress,
        retries: 3,
        allowPause: true,
      );
      _taskPids[task.taskId] = pid;
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
              state: 'pending',
              spanStartMs: Value(info.spanStartMs),
              spanEndMs: Value(info.spanEndMs),
            ),
          );
      await FileDownloader().enqueue(task);
    }
  }

  Future<void> _onUpdate(TaskUpdate update) async {
    final pid = _taskPids[update.task.taskId];
    if (pid == null) return;
    if (update is TaskStatusUpdate) {
      if (update.status == TaskStatus.complete) {
        final path = await update.task.filePath();
        await (db.update(db.downloadRecords)..where(
              (t) =>
                  t.pid.equals(pid) & t.fileName.equals(update.task.filename),
            ))
            .write(
              DownloadRecordsCompanion(
                state: const Value('complete'),
                localPath: Value(path),
              ),
            );
        if (await isComplete(pid)) {
          _progress.add(
            DownloadProgress(pid: pid, fraction: 1, complete: true),
          );
        }
      } else if (update.status == TaskStatus.failed ||
          update.status == TaskStatus.canceled) {
        _progress.add(
          DownloadProgress(
            pid: pid,
            fraction: 0,
            complete: false,
            failed: true,
          ),
        );
      }
    } else if (update is TaskProgressUpdate) {
      _progress.add(
        DownloadProgress(
          pid: pid,
          fraction: update.progress.clamp(0, 1),
          complete: false,
        ),
      );
    }
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
      paths: [for (final r in rows) r.localPath],
      spanStartMs: rows.first.spanStartMs,
      spanEndMs: rows.first.spanEndMs,
    );
  }

  @override
  Future<void> remove(String pid) async {
    final rows = await (db.select(
      db.downloadRecords,
    )..where((t) => t.pid.equals(pid))).get();
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
