import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import 'sync_engine_test.dart' show ScriptedRepository;

const _book = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';
const _track = 'tr-01JZX5N8QW3F4V9T2B7KDTRACK1';

/// A transfer engine that moves no bytes and records everything.
///
/// The seam the manager's bookkeeping is driven through: every transfer is
/// started, paused, and finished on this test's schedule, so the ordering
/// invariants are assertable - which is what neither the plugin nor a
/// filesystem would give.
class FakeTransferEngine implements TransferEnginePort {
  final _events = StreamController<TransferEvent>.broadcast();

  final started = <TransferRequest>[];
  final canceled = <String>[];
  final paused = <String>[];
  final resumed = <String>[];

  /// Ids handed out, in order.
  final ids = <String>[];

  /// What [pause] answers; false is a transfer that cannot be parked.
  bool pausable = true;

  /// Awaited by [report] once the event has been delivered, so a test can
  /// assert against bookkeeping the manager finished rather than
  /// bookkeeping it merely started. Wired to the manager under test.
  Future<void> Function()? settle;

  var _next = 0;

  @override
  Stream<TransferEvent> get events => _events.stream;

  @override
  Future<String> start(TransferRequest request) async {
    started.add(request);
    final id = 'task-${_next++}';
    ids.add(id);
    return id;
  }

  @override
  Future<bool> pause(String taskId) async {
    paused.add(taskId);
    return pausable;
  }

  @override
  Future<void> resume(String taskId) async => resumed.add(taskId);

  @override
  Future<void> cancel(List<String> taskIds) async => canceled.addAll(taskIds);

  /// Reports [state] for [taskId] and waits for the manager to act on it.
  ///
  /// Three steps, because the event crosses three hops: the first pump
  /// delivers it to the manager's subscription, [settle] waits for the
  /// handler that queued behind it, and the second pump delivers whatever
  /// that handler emitted on to a listening test. Pumping alone raced the
  /// handler's database and filesystem work, which is only ever a question
  /// of how loaded the machine is.
  Future<void> report(
    String taskId, {
    TransferState? state,
    double? fraction,
    String? path,
  }) async {
    _events.add(
      TransferEvent(
        taskId: taskId,
        state: state,
        fraction: fraction,
        path: path,
      ),
    );
    await pumpEventQueue();
    await settle?.call();
    await pumpEventQueue();
  }

  @override
  void dispose() => _events.close();
}

/// A repository answering download-info for one item of [files] parts.
class _DownloadRepository extends ScriptedRepository {
  _DownloadRepository();

  final Map<String, DownloadInfo> infoByPid = <String, DownloadInfo>{};

  @override
  Future<DownloadInfo> getDownloadInfo(String pid) async {
    final info = infoByPid[pid];
    if (info == null) {
      throw const WaxDeckApiException(code: 'not-found', message: 'no item');
    }
    return info;
  }
}

DownloadInfo _info(
  String pid, {
  required int parts,
  String hashPrefix = 'ess',
  int? durationMs = 60000,
  String etag = '1-1',
}) => DownloadInfo(
  pid: pid,
  files: <DownloadFileInfo>[
    for (var i = 0; i < parts; i++)
      DownloadFileInfo(
        url: 'https://example.test/$pid/$i',
        mimeType: 'audio/mp4',
        sizeBytes: 4194304,
        fileName: 'part$i.m4b',
        essenceHash: '$hashPrefix$i',
        etag: etag,
        durationMs: durationMs,
      ),
  ],
  expiresAt: DateTime.utc(2026, 7, 30),
);

void main() {
  late MirrorDatabase db;
  late FakeTransferEngine engine;
  late _DownloadRepository repo;
  late BackgroundDownloadManager manager;
  late Directory tmp;

  setUp(() {
    db = inMemoryMirrorDatabase();
    engine = FakeTransferEngine();
    repo = _DownloadRepository();
    manager = BackgroundDownloadManager(
      db: db,
      repository: () => repo,
      engine: engine,
    );
    engine.settle = () => manager.settled;
    tmp = Directory.systemTemp.createTempSync('waxdeck-downloads-test');
  });

  tearDown(() async {
    manager.dispose();
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Runs a whole item's transfers to completion, with real files on disk.
  Future<List<String>> completeAll(String pid) async {
    final paths = <String>[];
    for (final id in List<String>.of(engine.ids)) {
      final name = engine.started[engine.ids.indexOf(id)].fileName;
      final file = File('${tmp.path}/$name')..writeAsStringSync('bytes');
      paths.add(file.path);
      await engine.report(
        id,
        state: TransferState.complete,
        fraction: 1,
        path: file.path,
      );
    }
    return paths;
  }

  group('download', () {
    test('starts one transfer per file and records each as pending', () async {
      repo.infoByPid[_book] = _info(_book, parts: 3);
      await manager.download(_book);

      expect(engine.started, hasLength(3));
      // Named by essence hash, so the same audio is never held twice.
      expect(engine.started.map((r) => r.fileName), [
        'ess0.m4b',
        'ess1.m4b',
        'ess2.m4b',
      ]);
      final rows = await db.select(db.downloadRecords).get();
      expect(rows, hasLength(3));
      expect(rows.every((r) => r.state == 'pending'), isTrue);
      expect(rows.map((r) => r.durationMs), everyElement(60000));
    });

    // The server's essence hash is a structured identifier, not bare hex:
    // `sha256/mp3-frames-v1:<hex>`. Used verbatim it puts a path separator
    // in the file name, which the transfer engine rejects outright - so
    // every download failed before it started. The fixtures above use
    // separator-free hashes, which is why nothing here caught it.
    test('names a file safely from a structured essence hash', () async {
      repo.infoByPid[_book] = _info(
        _book,
        parts: 1,
        hashPrefix: 'sha256/mp3-frames-v1:beef',
      );
      await manager.download(_book);

      expect(engine.started, hasLength(1));
      final name = engine.started.single.fileName;
      expect(
        name,
        isNot(anyOf(contains('/'), contains(r'\'), contains(':'))),
        reason: 'a file name may not carry separators or a Windows colon',
      );
      expect(p.extension(name), '.m4b');
      // The hash still has to be in there: a stem that threw the whole
      // thing away would be portable and useless, since the name is what
      // stops the same audio being fetched twice.
      expect(p.basenameWithoutExtension(name), contains('beef'));
    });

    // The two that would collide under a plain substitution: swap the
    // separator and the colon and both read `sha256_a_b`. They would then
    // share one file on disk while `_discard`'s sharing check, which
    // compares raw hashes, saw no sharer - so removing either item would
    // unlink bytes the other still plays.
    test(
      'two essences that differ only in punctuation keep two names',
      () async {
        repo.infoByPid[_book] = _info(
          _book,
          parts: 1,
          hashPrefix: 'sha256/a:b',
        );
        await manager.download(_book);
        repo.infoByPid[_track] = _info(
          _track,
          parts: 1,
          hashPrefix: 'sha256:a/b',
        );
        await manager.download(_track);

        final names = engine.started.map((r) => r.fileName).toSet();
        expect(
          names,
          hasLength(2),
          reason: 'sanitising must not collapse two essences onto one file',
        );
      },
    );

    test('keeps bytes it already holds and refreshes the record', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1, durationMs: null);
      await manager.download(_book);
      await completeAll(_book);
      expect(engine.started, hasLength(1));

      // The same audio, now with a duration the catalog has learned and a
      // new etag from a retag. Nothing is re-fetched; the row catches up.
      repo.infoByPid[_book] = _info(
        _book,
        parts: 1,
        durationMs: 90000,
        etag: '2-2',
      );
      await manager.download(_book);

      expect(
        engine.started,
        hasLength(1),
        reason: 'the bytes are the same, so nothing transfers again',
      );
      final row = await db.select(db.downloadRecords).getSingle();
      expect(row.durationMs, 90000);
      expect(row.etag, '2-2');
      expect(row.state, 'complete');
    });

    test('re-fetches a file whose audio changed', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      await completeAll(_book);

      repo.infoByPid[_book] = _info(_book, parts: 1, hashPrefix: 'other');
      await manager.download(_book);

      expect(engine.started, hasLength(2));
      final row = await db.select(db.downloadRecords).getSingle();
      expect(row.state, 'pending');
      expect(row.essenceHash, 'other0');
    });
  });

  group('progress', () {
    test('a fraction is reported per item, not per file', () async {
      repo.infoByPid[_book] = _info(_book, parts: 2);
      await manager.download(_book);
      final seen = <DownloadProgress>[];
      manager.progress.listen(seen.add);

      await engine.report(engine.ids.first, fraction: 0.5);
      expect(seen.single.pid, _book);
      expect(seen.single.fraction, 0.5);
      expect(seen.single.complete, isFalse);
    });

    test('completion waits for every file of the item', () async {
      repo.infoByPid[_book] = _info(_book, parts: 2);
      await manager.download(_book);
      final done = <DownloadProgress>[];
      manager.progress.listen((p) {
        if (p.complete) done.add(p);
      });

      final first = File('${tmp.path}/ess0.m4b')..writeAsStringSync('a');
      await engine.report(
        engine.ids[0],
        state: TransferState.complete,
        path: first.path,
      );
      expect(done, isEmpty, reason: 'one part of two is not the item');

      final second = File('${tmp.path}/ess1.m4b')..writeAsStringSync('b');
      await engine.report(
        engine.ids[1],
        state: TransferState.complete,
        path: second.path,
      );
      expect(done, hasLength(1));
      expect(await manager.isComplete(_book), isTrue);
    });

    test('a failure is reported so a waiter stops waiting', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      final seen = <DownloadProgress>[];
      manager.progress.listen(seen.add);

      await engine.report(engine.ids.first, state: TransferState.failed);
      expect(seen.single.failed, isTrue);
      expect(seen.single.complete, isFalse);
    });

    test('a failed file discards the whole item', () async {
      // Left alone, the failed row stays `pending` behind a transfer
      // nothing is driving - a row the manager screen draws as a transfer
      // in flight forever. And the rows that *did* land would then be the
      // only ones left, every one of them complete, so a book missing its
      // last part would answer `isComplete`.
      repo.infoByPid[_book] = _info(_book, parts: 3);
      await manager.download(_book);
      final first = File('${tmp.path}/ess0.m4b')..writeAsStringSync('a');
      await engine.report(
        engine.ids[0],
        state: TransferState.complete,
        path: first.path,
      );

      await engine.report(engine.ids[2], state: TransferState.failed);

      expect(await db.select(db.downloadRecords).get(), isEmpty);
      expect(await manager.isComplete(_book), isFalse);
      expect(await manager.stored(), isEmpty);
      expect(first.existsSync(), isFalse);
      // The part still transferring was stopped rather than left to land
      // against records that are gone.
      expect(engine.canceled, contains(engine.ids[1]));
    });

    test('a paused transfer is not an ending', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      final seen = <DownloadProgress>[];
      manager.progress.listen(seen.add);

      await engine.report(engine.ids.first, state: TransferState.paused);

      expect(seen, isEmpty, reason: 'parked is neither progress nor an end');
      // And the mapping survives, which is what lets resume find it.
      await manager.resume(_book);
      expect(engine.resumed, [engine.ids.first]);
    });
  });

  group('remove', () {
    test('stops transfers in flight before deleting rows or files', () async {
      // The ordering invariant: a transfer still running would write its
      // file back after the unlink and report completion against a row
      // that is gone. "Clear all" is the path that reaches this, since it
      // sweeps every row it holds, in flight included.
      repo.infoByPid[_book] = _info(_book, parts: 2);
      await manager.download(_book);
      expect(engine.canceled, isEmpty);

      await manager.remove(_book);

      expect(engine.canceled, hasLength(2));
      expect(await db.select(db.downloadRecords).get(), isEmpty);
    });

    test('a canceled transfer reporting late touches nothing', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      final id = engine.ids.first;
      await manager.remove(_book);

      // The engine's cancellation notice arrives after the fact, as it
      // does in life. It must not resurrect a row or emit for an item the
      // listener has removed.
      final seen = <DownloadProgress>[];
      manager.progress.listen(seen.add);
      final orphan = File('${tmp.path}/ess0.m4b')..writeAsStringSync('x');
      await engine.report(id, state: TransferState.complete, path: orphan.path);

      expect(seen, isEmpty);
      expect(await db.select(db.downloadRecords).get(), isEmpty);
    });

    test('unlinks the bytes it held', () async {
      repo.infoByPid[_book] = _info(_book, parts: 2);
      await manager.download(_book);
      final paths = await completeAll(_book);
      expect(paths.every((p) => File(p).existsSync()), isTrue);

      await manager.remove(_book);

      expect(paths.every((p) => File(p).existsSync()), isFalse);
      expect(await manager.localFor(_book), isNull);
    });

    test('leaves a file a second item still holds', () async {
      // CUE siblings share one backing file, so the last reference is what
      // unlinks it. This is why the bulk sweeps are sequential.
      repo.infoByPid[_track] = _info(_track, parts: 1, hashPrefix: 'shared');
      await manager.download(_track);
      final shared = File('${tmp.path}/shared0.m4b')..writeAsStringSync('a');
      await engine.report(
        engine.ids.first,
        state: TransferState.complete,
        path: shared.path,
      );

      // A second item over the same essence.
      const sibling = 'tr-01JZX5N8QW3F4V9T2B7KDTRACK2';
      repo.infoByPid[sibling] = _info(sibling, parts: 1, hashPrefix: 'shared');
      await manager.download(sibling);
      await engine.report(
        engine.ids.last,
        state: TransferState.complete,
        path: shared.path,
      );

      await manager.remove(_track);
      expect(
        shared.existsSync(),
        isTrue,
        reason: 'the sibling still points at it',
      );

      await manager.remove(sibling);
      expect(shared.existsSync(), isFalse, reason: 'that was the last one');
    });

    // The sweep above is sequential because it asks whether any other row
    // still holds the essence. Started together, each would see the other's
    // row, each would call the file shared, and it would outlive every
    // record pointing at it. The manager serializes them rather than
    // trusting its callers to.
    test('two items removed at once still unlink what they shared', () async {
      repo.infoByPid[_track] = _info(_track, parts: 1, hashPrefix: 'shared');
      await manager.download(_track);
      final shared = File('${tmp.path}/shared0.m4b')..writeAsStringSync('a');
      await engine.report(
        engine.ids.first,
        state: TransferState.complete,
        path: shared.path,
      );

      const sibling = 'tr-01JZX5N8QW3F4V9T2B7KDTRACK2';
      repo.infoByPid[sibling] = _info(sibling, parts: 1, hashPrefix: 'shared');
      await manager.download(sibling);
      await engine.report(
        engine.ids.last,
        state: TransferState.complete,
        path: shared.path,
      );

      await Future.wait([manager.remove(_track), manager.remove(sibling)]);

      expect(shared.existsSync(), isFalse, reason: 'nothing holds it now');
      expect(await db.select(db.downloadRecords).get(), isEmpty);
    });
  });

  group('cancel', () {
    test('stops the transfers and drops the pending rows', () async {
      repo.infoByPid[_book] = _info(_book, parts: 2);
      await manager.download(_book);

      await manager.cancel(_book);

      expect(engine.canceled, hasLength(2));
      expect(await db.select(db.downloadRecords).get(), isEmpty);
    });

    test(
      'discards the parts that did land, not just the pending rows',
      () async {
        // A three-part book that got through part one and was then stopped.
        // Deleting only the pending rows would leave the one complete row
        // behind, and that reads as a *finished* download: `isComplete` sees
        // every remaining row complete, and `localFor` hands playback one
        // part as if it were the whole book. Half a book is not a download.
        repo.infoByPid[_book] = _info(_book, parts: 3);
        await manager.download(_book);
        final first = File('${tmp.path}/ess0.m4b')..writeAsStringSync('a');
        await engine.report(
          engine.ids[0],
          state: TransferState.complete,
          path: first.path,
        );
        expect(await manager.isComplete(_book), isFalse);

        await manager.cancel(_book);

        expect(await db.select(db.downloadRecords).get(), isEmpty);
        expect(await manager.isComplete(_book), isFalse);
        expect(await manager.localFor(_book), isNull);
        expect(first.existsSync(), isFalse, reason: 'the bytes go with it');
        // And the transfers still running were stopped.
        expect(engine.canceled, hasLength(2));
      },
    );
  });

  group('pause', () {
    test('answers false when no transfer can be parked', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      engine.pausable = false;

      expect(await manager.pause(_book), isFalse);
      expect(engine.paused, hasLength(1));
    });

    test('answers false for an item with nothing in flight', () async {
      expect(await manager.pause(_book), isFalse);
      expect(engine.paused, isEmpty);
    });

    test('answers true when one took', () async {
      repo.infoByPid[_book] = _info(_book, parts: 2);
      await manager.download(_book);
      expect(await manager.pause(_book), isTrue);
      expect(engine.paused, hasLength(2));
    });
  });

  group('bookkeeping', () {
    test('an item with no live transfers has none to act on', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      await completeAll(_book);

      expect(await manager.pause(_book), isFalse);
      await manager.resume(_book);
      expect(engine.resumed, isEmpty);
      await manager.cancel(_book);
      expect(engine.canceled, isEmpty);
    });

    test('a second report for a finished transfer is ignored', () async {
      // The observable half of "terminal transfers are forgotten". Every
      // id ever transferred used to stay mapped for the life of the
      // process, which is a leak with nothing to see - except this: a
      // mapping that outlives its transfer is a mapping something can act
      // on again, so a repeated report would rewrite a settled row and
      // announce a completion twice.
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      final id = engine.ids.single;
      final real = File('${tmp.path}/ess0.m4b')..writeAsStringSync('a');
      await engine.report(id, state: TransferState.complete, path: real.path);

      final seen = <DownloadProgress>[];
      manager.progress.listen(seen.add);
      final elsewhere = File('${tmp.path}/somewhere-else.m4b')
        ..writeAsStringSync('b');
      await engine.report(
        id,
        state: TransferState.complete,
        path: elsewhere.path,
      );

      expect(seen, isEmpty, reason: 'the item was already complete');
      final row = await db.select(db.downloadRecords).getSingle();
      expect(
        row.localPath,
        real.path,
        reason: 'a settled row is not rewritten by a dead id',
      );
    });

    test('a failed transfer is forgotten too', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      final id = engine.ids.single;
      await engine.report(id, state: TransferState.failed);

      final seen = <DownloadProgress>[];
      manager.progress.listen(seen.add);
      await engine.report(id, state: TransferState.failed);
      expect(seen, isEmpty);
    });
  });

  group('localFor', () {
    test('answers the parts in reading order, with their durations', () async {
      repo.infoByPid[_book] = _info(_book, parts: 3);
      await manager.download(_book);
      final paths = await completeAll(_book);

      final local = await manager.localFor(_book);
      expect(local!.parts.map((p) => p.path), paths);
      expect(local.parts.map((p) => p.durationMs), [60000, 60000, 60000]);
      expect(local.sequenced, isTrue);
    });

    test('parts with no stored duration cannot be sequenced', () async {
      repo.infoByPid[_book] = _info(_book, parts: 2, durationMs: null);
      await manager.download(_book);
      await completeAll(_book);

      final local = await manager.localFor(_book);
      expect(local!.parts, hasLength(2));
      expect(local.sequenced, isFalse);
    });

    test('answers nothing while a part is still pending', () async {
      repo.infoByPid[_book] = _info(_book, parts: 2);
      await manager.download(_book);
      final first = File('${tmp.path}/ess0.m4b')..writeAsStringSync('a');
      await engine.report(
        engine.ids[0],
        state: TransferState.complete,
        path: first.path,
      );

      expect(await manager.localFor(_book), isNull);
    });

    test('answers nothing when the bytes were evicted behind us', () async {
      repo.infoByPid[_book] = _info(_book, parts: 1);
      await manager.download(_book);
      final paths = await completeAll(_book);
      File(paths.single).deleteSync();

      expect(await manager.localFor(_book), isNull);
    });

    test('carries a carved track its window', () async {
      repo.infoByPid[_track] = DownloadInfo(
        pid: _track,
        files: <DownloadFileInfo>[
          const DownloadFileInfo(
            url: 'https://example.test/rip',
            mimeType: 'audio/flac',
            sizeBytes: 100,
            fileName: 'rip.flac',
            essenceHash: 'rip',
            etag: '1-1',
          ),
        ],
        spanStartMs: 60000,
        spanEndMs: 240000,
        expiresAt: DateTime.utc(2026, 7, 30),
      );
      await manager.download(_track);
      await completeAll(_track);

      final local = await manager.localFor(_track);
      expect(local!.spanStartMs, 60000);
      expect(local.spanEndMs, 240000);
    });
  });

  group('stored', () {
    test('is per item, with its files summed', () async {
      repo.infoByPid[_book] = _info(_book, parts: 3);
      await manager.download(_book);
      await completeAll(_book);
      repo.infoByPid[_track] = _info(_track, parts: 1, hashPrefix: 'tr');
      await manager.download(_track);

      final rows = await manager.stored();
      final book = rows.firstWhere((r) => r.pid == _book);
      expect(book.files, 3);
      expect(book.sizeBytes, 3 * 4194304);
      expect(book.complete, isTrue);
      // A pending item is held too, and says it is not complete: the
      // manager screen draws it as a transfer rather than as bytes.
      final track = rows.firstWhere((r) => r.pid == _track);
      expect(track.complete, isFalse);
    });
  });

  test('a record survives a schema upgrade with its duration null', () async {
    // The v3-to-v4 path from the other side: a row written before
    // durations existed reads null, which is what makes the item
    // unsequenceable rather than misplaced.
    await db
        .into(db.downloadRecords)
        .insert(
          DownloadRecordsCompanion.insert(
            pid: _book,
            fileIndex: 0,
            essenceHash: 'old',
            etag: '1-1',
            fileName: 'old.m4b',
            localPath: '${tmp.path}/old.m4b',
            sizeBytes: 10,
            state: 'complete',
            durationMs: const Value(null),
          ),
        );
    File('${tmp.path}/old.m4b').writeAsStringSync('x');

    final local = await manager.localFor(_book);
    expect(local!.parts.single.durationMs, isNull);
    expect(local.sequenced, isFalse);
  });
}
